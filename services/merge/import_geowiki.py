# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME: Implement pickle recovery... or check for paused/suspended and save
# work item step with appropriate pickled data

import copy
from decimal import Decimal
import os
import re
import psycopg2
import sys
import time

import conf
import g

log = g.log.getLogger('import_gwiki')

from grax.access_level import Access_Level
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from gwis.exception.gwis_error import GWIS_Error
from item import link_value
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from item.grac import group
from item.jobsq import merge_job
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.import_init import Import_Init

class Import_Geowiki(Import_Init):

   __slots__ = (
      'source_byways',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Init.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Init.reinit(self)
      self.source_byways = {} # old stack ID => old byway

   # ***

   # This is for the curious dev.
   filter_using_where_in = False

   #
   def byways_get_many_by_id(self, fts_lookup, prog_log, processing_fcn):

      # Make a list of IDs to lookup. We can use the SELECT statment's WHERE
      # clause or JOIN clause. The latter is probably preferrable.

      # 2012.07.01: substage_cleanup being called early?
      g.assurt(self.qb_src is not None)

      if Import_Geowiki.filter_using_where_in:
         g.assurt(len(self.qb_src.filters.only_stack_ids) == 0)
      else:
         g.assurt(not self.qb_src.filters.stack_id_table_ref)

      if isinstance(fts_lookup, dict):
         id_list = fts_lookup.keys()
      else:
         g.assurt(isinstance(fts_lookup, list))
         id_list = fts_lookup

      # Trim the stack ID list if we are de-veloping/bugging.
      if prog_log.debug_break_loops:
         max_ids = prog_log.log_freq * prog_log.debug_break_loop_cnt
         beg_i = prog_log.debug_break_loop_off
         fin_i = beg_i + max_ids
         id_list = id_list[beg_i:fin_i]

      if id_list:
         self.byways_get_many_by_id_(id_list, prog_log, processing_fcn)
      else:
         log.info('byways_get_many_by_id: no stack IDs; nothing to load.')

   #
   def byways_get_many_by_id_(self, id_list, prog_log, processing_fcn):

      # If debug_sids_from is not None, process split-groups sequentially
      # starting with a particular old_byway stack ID.
      # NOTE: When item_mgr loads the byways, it calls item_user_access which
      #       always orders by stack id ascending, so it's guaranteed that
      #       we're processing stack IDs sequentially at all times.
      if self.debug.debug_sids_from is not None:
         # Setting debug_sids_from to one or less is a freebie pass, otherwise 
         # we expect the stack ID to match -- basically, this value should only
         # be set during development, and you'll have a valid value to set for 
         # your particular Shapefile.
         if self.debug.debug_sids_from > 1:
            id_list.sort()
            try:
               idex = id_list.index(self.debug.debug_sids_from)
               id_list = id_list[idex:]
            except ValueError:
               raise GWIS_Error(
                  '_get_many_by_id_: debug_sids_from not a valid stack ID: %d'
                  % (self.debug.debug_sids_from,))

      #
      if Import_Geowiki.filter_using_where_in:
         if len(id_list) > 999:
            log.warning('byways_get_many_by_id: using big if: %d ids.' 
                        % (len(id_list),))
         id_list = [str(x) for x in id_list]
         self.qb_src.filters.only_stack_ids = ','.join(id_list)
      else:
         # Build the intermediate table.
         self.qb_src.load_stack_id_lookup('import_base', id_list)

      log.debug('byways_get_many_by_id: looking for %d byways' 
                % (len(id_list),))
      t0 = time.time()

      # NOTE: Using byway.Many().search_by_network so we get endpoints.
      # NOTE: Using heavyweight, which loads all the link_values, which causes
      # memory bloat, which is fine for this script.
      feat_search_fcn = 'search_by_network'
      self.qb_src.item_mgr.load_feats_and_attcs(
            self.qb_src,
            byway,
            feat_search_fcn,
            processing_fcn,
            prog_log,
            heavyweight=True, 
            load_groups_access=True)

      if self.qb_src.filters.stack_id_table_ref:
         self.qb_src.db.sql(
            "DROP TABLE %s" % (self.qb_src.filters.stack_id_table_ref,))

      if prog_log.progress != len(id_list):
         log.error(
            'byways_get_many_by_id: Fewer byways than expected: %s of %s.' 
            % (prog_log.progress, len(id_list),))
      else:
         log.debug('byways_get_many_by_id: Found %d byways.' % (len(id_list),))

      if Import_Geowiki.filter_using_where_in:
         self.qb_src.filters.only_stack_ids = ''
      else:
         self.qb_src.filters.stack_id_table_ref = ''

   # *** Attributes and Link Values

   #
   def feat_assoc_save(self, new_feat, ref_byway, new_byway):

      # The feature should be setup. We just need to peek at its target field.
      g.assurt(new_feat is not None)

      # 2012.02.02 For now, ref_byway is not None, but not in the future, for
      # new geometries (standalone updates).
      #g.assurt((ref_byway is not None) or (new_byway is not None))
      g.assurt(ref_byway is not None)
      # new_byway is not None if a split byway or a standin whose geom or byway
      # cols changed. new_byway could be in a different branch than ref_byway.

      for ta_def in self.defs.attrs_metadata:

         if ta_def.ccp_atid:
            new_val = self.defs.ta_def_get_field_value(ta_def, new_feat, 
                                                       use_target=True)
            log.verbose4('feat_assoc_save: tgt: %10s / new_val: %s' 
                         % (ta_def.field_target, new_val,))
            # The new_val can be None.
            save_val = False
            # Find the current link_value.
            do_delete = False
            attr = self.attributes_all[ta_def.ccp_atid]

            try:
               ref_byway.link_values
               log.verbose('feat_assoc_save: link_values ok: %d' 
                           % (ref_byway.stack_id,))
            except AttributeError:
               log.error('feat_assoc_save: link_values na: %d' 
                         % (ref_byway.stack_id,))
               g.assurt(False) # Programmer error.

            try:
               # NOTE: link_values is a heavyweight list, i.e., real link_value
               #       objects.
               link_attr = ref_byway.link_values[ta_def.ccp_atid]
               old_val = link_attr.get_value(attr)
               if new_val != old_val:
                  save_val = True
                  if ((new_val is None) 
                      or (ta_def.deleted_on 
                          and (new_val in ta_def.deleted_on))):
                     new_val = None
                     do_delete = True
            except KeyError:
               # The link_value does not exist.
               link_attr = None
               # Only save the new value if it's relevant.
               if ((new_val is not None) 
                   and ((not ta_def.deleted_on)
                        or (new_val not in ta_def.deleted_on))):
                  save_val = True
            #
            if save_val:
               self.link_values_create_delete(ta_def, ref_byway, new_byway, 
                                              new_val, link_attr, attr,
                                              do_delete)

   # 
   def link_values_create_delete(self, ta_def, ref_byway, new_byway, the_val, 
                                       link_attr, attr, do_delete):

      g.assurt(((    do_delete) and (the_val     in ta_def.deleted_on)) or 
               ((not do_delete) and (the_val not in ta_def.deleted_on)))

      g.assurt(the_val is not None)
      (val_boolean, val_integer, val_string
            ) = self.defs.link_value_get_field_value(ta_def, the_val)

      # The link at least exists in ref_byway.
      g.assurt(ref_byway.version >= 1)
      g.assurt(not ref_byway.fresh)
      g.assurt(not ref_byway.valid) # Just read from db, not ready to be saved.

      # beg: Defensive Programming. (The following code is just debug code.)
      attr_name = self.attributes_all[ta_def.ccp_atid].value_internal_name
      if new_byway is None:
         log.verbose1('link_vals_cre-del: same-stack old-byway link: %s'
                      % (attr_name,))
      else:
         if not new_byway.link_values:
            # Byways are not required to have links. Most roadways do, but lots
            # of user-added bike trails do not.
            log.verbose4('link_values_create_delete: no links: %s' 
                         % (new_byway,))
            g.assurt(new_byway.link_values is not None) # I.e., empty dict() ok
         if new_byway.branch_id != ref_byway.branch_id:
            log.verbose1('link_vals_cre-del: new-branch new-byway link: %s'
                         % (attr_name,))
         if new_byway.stack_id == ref_byway.stack_id:
            log.verbose1('link_vals_cre-del: same-stack new-byway link: %s'
                         % (attr_name,))
            g.assurt(new_byway.version > 1)
         else:
            # New split-from byway. We just saved new byway and new links.
            g.assurt((link_attr is None) or (link_attr.version == 1))
            g.assurt(new_byway.version == 1)
            g.assurt(new_byway.split_from_stack_id == ref_byway.stack_id)
            try:
               g.assurt(new_byway.link_values[ta_def.ccp_atid]
                        == ref_byway.link_values[ta_def.ccp_atid])
            except KeyError:
               pass
            log.verbose1('link_vals_cre-del: split-from new-byway link: %s'
                         % (attr_name,))
      # link_attr is currently set to the ref_byway's lookup.
      g.assurt((link_attr is None) 
               or (id(link_attr) 
                   == id(ref_byway.link_values[ta_def.ccp_atid])))
      # fin: Defensive Programming.

      # If this is a new byway or a split-from byway (also a new byway), all 
      # the links are new. Otherwise we use the existing link's stack ID when 
      # making the new one, since the byway hasn't changed (well, it may have a
      # new version and updated geometry, but it's got the same stack ID).
      ref_link = link_attr
      lval_update_ok = False
      if new_byway is not None:
         try:
            ref_link = new_byway.link_values[ta_def.ccp_atid]
         except KeyError:
            # Set the ref to None so we make a new link and don't accidentally
            # use the ref_byway's link's stack ID.
            ref_link = None
         # Also, if this is a split-from, the link_value was just saved, so we
         # can just update it (rather than making a new item version).
         if new_byway.stack_id != ref_byway.stack_id:
            # Since we just save this split-from and the new link, we don't
            # have to increment the link_value version (insert a new row in the
            # database) but can simply update the existing link_value.
            g.assurt(new_byway.newly_split())
            lval_update_ok = True
      # else, we'll use the ref_byway's link (which may not exist).
      if not lval_update_ok:
         g.assurt((new_byway is None) or (not new_byway.newly_split()))

      g.assurt(attr.stack_id == ta_def.ccp_atid)
      the_byway = new_byway or ref_byway
      new_link = self.byway_make_link_attr_and_save_(
            the_byway, attr,
            val_boolean, val_integer, val_string, 
            ref_link, lval_update_ok)

      if do_delete:
         new_link.mark_deleted(self.qb_cur, None)

      the_byway.wire_lval(self.qb_cur, new_link, heavywt=True)

# FIXME: Where are gf delete and revert commands?

   # ***

   #
   def byway_make_link_attr_and_save_(self, byway_, attr_,
                                      val_boolean, val_integer, val_string,
                                      ref_link=None, lval_update_ok=False):

      log.verbose4('Making link_value for attr: %s / %s|%s|%s' 
         % (str(attr_), val_boolean, val_integer, val_string,))

      g.assurt(byway_.stack_id > 0)
      g.assurt(attr_.stack_id > 0)

      if ref_link is not None:
         stack_id = ref_link.stack_id
         version = ref_link.version
         g.assurt(attr_.stack_id == ref_link.lhs_stack_id)
         g.assurt(byway_.stack_id == ref_link.rhs_stack_id)
         #try:
         #   start_rid = ref_link.valid_start_rid
         #except AttributeError:
         #   pass
         start_rid = ref_link.valid_start_rid
         client_id = None
      else:
         # It shouldn't matter if we set the stack ID to a client (negative) ID
         # or if we fetch a new ID here -- if we use a client ID, a real ID
         # will be assigned in prepare_and_save_item.
         stack_id = self.qb_cur.item_mgr.get_next_client_id()
         version = 0
         start_rid = None
         client_id = stack_id

      if start_rid == self.qb_cur.item_mgr.rid_new:

         # We just saved a new split-into byway with new link_values, and this
         # is one of them.
         g.assurt(lval_update_ok)

         # FIXME: This just means we've already saved this link value?
         #        So we're just updating it?
         log.debug('_make_link_attr_: rids would overlap: %s / %s' 
                   % (start_rid, self.qb_cur.item_mgr.rid_new,))

         # Update the link.
         new_link = ref_link
         g.assurt(new_link.branch_id == self.qb_cur.branch_hier[0][0])
         new_link.value_boolean         = val_boolean
         new_link.value_integer         = val_integer
         new_link.value_real            = None
         new_link.value_text            = val_string
         new_link.value_binary          = None
         new_link.value_date            = None

         new_link.save_update(self.qb_cur)

         log.verbose3('updated link: %s' % (new_link,))

      else:

         # It's okay if lval_update_ok is set: for new split-into byways, we
         # might also be creating new link_values.

         new_link = link_value.One(
            qb=self.qb_cur,
            row={
               # *** from item_versioned:
               'system_id'             : None, # assigned later
               'branch_id'             : self.qb_cur.branch_hier[0][0],
               'stack_id'              : stack_id,
               'version'               : version,
               'deleted'               : False,
               'name'                  : '', # FIXME: Is this right?
               #'valid_start_rid'      : # assigned by 
               #'valid_until_rid'      : #   version_finalize_and_increment
               # *** from link_value:
               'lhs_stack_id'          : attr_.stack_id,
               'rhs_stack_id'          : byway_.stack_id,
               'link_lhs_type_id'      : Item_Type.ATTRIBUTE,
               'link_rhs_type_id'      : Item_Type.BYWAY,
               'value_boolean'         : val_boolean,
               'value_integer'         : val_integer,
               'value_real'            : None,
               'value_text'            : val_string,
               'value_binary'          : None,
               'value_date'            : None,
               }
            )

         g.assurt(new_link.groups_access is None)

         log.verbose('_make_link_attr_: not clearing item_cache')
         # NO: self.qb_cur.item_mgr.item_cache_reset()
         self.qb_cur.item_mgr.item_cache_add(attr_)
         self.qb_cur.item_mgr.item_cache_add(byway_)

         if ref_link is not None:
            g.assurt(start_rid != self.qb_cur.item_mgr.rid_new)
            log.debug('_make_link_attr_: rids will not overlap: %s / %s' 
                      % (start_rid, self.qb_cur.item_mgr.rid_new,))
            # Since we pass the ref_link, grac_mgr calls prepare_item,
            # which sets access_level_id.
            self.qb_cur.item_mgr.item_cache_add(ref_item)
            new_link.prepare_and_save_item(self.qb_cur,
               target_groups=None,
               rid_new=self.qb_cur.item_mgr.rid_new,
               ref_item=ref_link)
         else:
            # Here... there is no access_level_id being set... hrmm...
            new_link.prepare_and_save_item(self.qb_cur,
               target_groups=self.target_groups,
               rid_new=self.qb_cur.item_mgr.rid_new,
               ref_item=None)

         self.qb_cur.item_mgr.item_cache_add(new_link, client_id)

         # EXPLAIN: Why do we reset? Just because it doesn't matter except
         #          during the save? And no one needs the cache later?
         log.verbose('_make_link_attr_: not clearing item_cache')
         # NO: self.qb_cur.item_mgr.item_cache_reset()

         log.verbose3('created link: %s' % (new_link,))

      log.verbose3(' >> groups_access: %s' % (new_link.groups_access,))
      g.assurt(new_link.groups_access)

      if new_link.version == 1:
         self.stats['count_link_values_new'] += 1
      else:
         g.assurt(new_link.version > 1)
         self.stats['count_link_values_old'] += 1
      self.stats['count_link_values_all'] += 1

      return new_link

   # ***

   #
   def byway_create(self, ref_byway, geom_wkt, is_geom_changed, 
                          is_split_from=False):

      # NOTE: We assigned client IDs here and prepare_and_save_item assigns a
      # real ID. We don't assign a real ID here because we're not sure if
      # prepare_and_save_item is going to be called (at least not for the
      # new-version-of-an-existing-item item, which we create to work on but
      # don't necessarily save).
      if not is_split_from:
         if ref_byway is not None:
            # This is a new version of an existing item.
            stack_id = ref_byway.stack_id
            version = ref_byway.version
         else:
            # This is a new byway altogher.
            stack_id = self.qb_cur.item_mgr.get_next_client_id()
            version = 0
         split_from_stack_id = None
      else:
         # This is a new, split-from byway.
         g.assurt(ref_byway is not None)
         stack_id = self.qb_cur.item_mgr.get_next_client_id()
         version = 0
         split_from_stack_id = ref_byway.stack_id

      # BUG nnnn: Import does not support deleting byways.

      new_byway = byway.One(
         qb=self.qb_cur,
         row={
            # *** from item_versioned:
            'system_id'             : None, # assigned later
            'branch_id'             : self.qb_cur.branch_hier[0][0],
            'stack_id'              : stack_id,
            'version'               : version,
            'deleted'               : False,
            'name'                  : getattr(ref_byway, 'name', ''),
            #'valid_start_rid'      : # assigned by 
            #'valid_until_rid'      : #   version_finalize_and_increment
            # *** from geofeature:
            # See below: 'geometry_wkt': geom_wkt,
            'z'                     : getattr(ref_byway, 'z', 0), # FIXME: 0?
            'geofeature_layer_id'   : getattr(ref_byway, 'geofeature_layer_id',
                                              byway.Geofeature_Layer.Unknown),
            # *** from byway:
            'one_way'               : getattr(ref_byway, 'one_way', 0),
            'beg_node_id'           : None, # byway will set this on save
            'fin_node_id'           : None, # byway will set this on save
            'split_from_stack_id'   : split_from_stack_id,
            # NOTE: byway.py will populate generic_rating on save.
            }
         )

      # Geofeatures have a special fcn. for setting geometry.
      new_byway.set_geometry_wkt(geom_wkt, is_changed=is_geom_changed)

      # Skipping computed values: geometry_len, user_rating, 
      #  beg_point, beg2_point, fin_point, fin2_point, 
      #  xcoord, ycoord, and start/node_rhs_elevation_m.

      g.assurt((not is_split_from) 
               ^ (is_split_from and new_byway.newly_split()))

      return new_byway

   #
   def byway_setup(self, new_byway, old_byway, new_feat):

      byway_updated = False

      # See if one or more byway attributes have changed. If so, save a new
      # version of the byway with the new value(s).
      for ta_def in self.defs.attrs_metadata:
         if ta_def.byway_source and ta_def.settable:
            # We've already updated new_feat to reflect the new value, but
            # new_byway is just a copy of old_byway, so we have to check each 
            # value again.
            old_val = self.defs.ta_def_get_attr_value(ta_def, old_byway)
            new_val = self.defs.ta_def_get_field_value(ta_def, new_feat, 
                                                       use_target=True)
            log.verbose4('stdin_fts_cnsm_: tgt: %10s / oldv: %10s / newv: %10s'
                         % (ta_def.field_target, old_val, new_val,))
            # The item base class, item_base, ignores item attributes that are
            # None. Furthermore, there's no way to set an SQL column to NULL.
            #if old_val in ta_def.deleted_on:
            #   log.warning('Shouldnt this be none?')
            #   old_val = None
            #if new_val in ta_def.deleted_on:
            #   new_val = None
            # NOTE: The item_versioned class defaults 'name' to the empty
            #       string but the value from the Shapefile is None, so 
            #       check that one of the values is logically true at least.
            if (old_val or new_val) and (old_val != new_val):
               # BUG nnnn: This won't work on 'faked' node_endpoint attributes
               #           (like dangle_ok).
               # FIXME: This won't work if new_val is None, since item_base
               # will ignore it.
               setattr(new_byway, ta_def.byway_source, new_val)
               byway_updated = True

      if old_byway.name and new_byway.name:

         # 2013.11.22: There's a problem with trailing whitespace, and [lb] is
         #             not sure where it was chopped, but it was. E.g.,
         # byway_setup: unexpected length: new: "Bruce Vento Trail" (17) 
         #  / old: "Bruce Vento Trail " [byway:1125382.v6/233453-b2500677-edt]
         old_byway.name = old_byway.name.strip()
         new_byway.name = new_byway.name.strip()

         # BUG nnnn: The MetC Shapefile has a 44-width line limit on item
         #           names, so some of them were truncated.
         # START: Name hack for MetC.
         #
         # FIXME: Add code to detect field width of name field for any
         #   BUG  Shapefile and always run this block to code to fix
         #  nnnn: truncated names.
         #
         # MAGIC_NUMBER: 44 is the MetC Shapefile name field width.
         if ((self.qb_src.branch_hier[0][2] == 'Metc Bikeways 2012')
             and (new_byway.name != old_byway.name)):
            forty_four_or_less = len(old_byway.name[:44].strip())
            if len(new_byway.name) < len(old_byway.name):
               if old_byway.name.startswith(new_byway.name):
                  # The length might be shorter, like 43, if a space was
                  # stripped...
                  if len(new_byway.name) != forty_four_or_less:
                     log_fcn = log.warning
                     log_msg = 'byway_setup: unexpected len:'
                  else:
                     log_fcn = log.debug
                     log_msg = 'byway_setup: fix truncated name:'
                     new_byway.name = old_byway.name
            else:
               # The older name is longer than or the same length as
               # the newer name, so probably a proper change. Probably.
               if len(new_byway.name) == forty_four_or_less:
                  log_fcn = log.warning
                  log_msg = 'byway_setup: name may be truncated:'
               else:
                  # Someone changed the name legitimately. Probably.
                  log_fcn = log.debug
                  log_msg = 'byway_setup: legit name change:'
            log_fcn('%35s new: "%s" (%s chars)'
                    % (log_msg, new_byway.name, len(new_byway.name),))
            log_fcn('%35s old: %s' % (' ', old_byway,))
         # END: Name hack for MetC.
      else:
         if old_byway.name or new_byway.name:
            log.warning('byway_setup: no name?: new: %s / old: %s'
                      % (new_byway, old_byway,))

      return byway_updated

   #
   def byway_save(self, unsaved_byway, ref_byway):

      log.verbose('byway_save: %s' % (unsaved_byway,))

      if ref_byway is not None:
         # Copy the reference byway's group item accesses.
         g.assurt((unsaved_byway.stack_id > 0) 
                  or (unsaved_byway.split_from_stack_id > 0))
         try:
            if self.qb_cur.db.integrity_errs_okay:
               log.warning('byway_save: unexpected integrity_errs_okay')
            self.qb_cur.db.integrity_errs_okay = True
            unsaved_byway.prepare_and_save_item(self.qb_cur,
               target_groups=None,
               rid_new=self.qb_cur.item_mgr.rid_new,
               ref_item=ref_byway)
         except psycopg2.IntegrityError, e:
            import pdb;pdb.set_trace()
            raise GWIS_Error('%s %s %s'
               % ('Byway already exists!',
                  'The trunky split-from byway has already been leafified: %s'
                     % unsaved_byway,
                  'Have you already imported this Shapefile?: %s'
                     % self.outp_datasrc.GetLayer(0).GetName(),))
         finally:
            self.qb_cur.db.integrity_errs_okay = False
         self.stats['count_new_byways_refed'] += 1
      else:
         # Otherwise, apply new GIA permissions per the import config.
         # BUG nnnn: Should we check geofeature table for exact geometry match,
         #           i.e., in case user is importing same new features twice?
         g.assurt(unsaved_byway.stack_id is not None)
         g.assurt(unsaved_byway.stack_id < 0)
         unsaved_byway.prepare_and_save_item(self.qb_cur, 
            target_groups=self.target_groups,
            rid_new=self.qb_cur.item_mgr.rid_new,
            ref_item=None)
         self.stats['count_new_byways_newed'] += 1

      self.stats['count_new_byways_total'] += 1

      # If the previously unsaved byway was not split-from, its link_values
      # lookup won't be populated.
      try:
         lvals_collection = unsaved_byway.link_values
      except AttributeError:
         lvals_collection = None
      if lvals_collection is None:
         log.verbose4('byway_save: loading link_values: %s' % (unsaved_byway,))
         #unsaved_byway.load_attributes_by_ids(self.qb_src, 
         #                                     self.attributes_all.keys())
         # FIXME: qb_src or qb_cur?
         #
         # FIXME: It might make more sense to call
         #        self.qb_src.item_mgr.load_feats_and_attcs
         #        and bulk-load byways... but [lb] knows the import
         #        code is a bear to test, sometimes, so let's not
         #        bother but just suffer the slowness.
         self.qb_src.item_mgr.load_links_slow(
            self.qb_src, unsaved_byway, heavyweight=True)
         self.stats['count_new_byways_not_split'] += 1

   # ***

# ***

if (__name__ == '__main__'):
   pass

