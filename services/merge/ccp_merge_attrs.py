# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys
import time

import conf
import g

log = g.log.getLogger('ccp_mrg_attrs')

from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from item.attc import attribute
from item.util.item_type import Item_Type

from merge.ccp_merge_base import Ccp_Merge_Base

class Ccp_Merge_Attrs(Ccp_Merge_Base):

   __slots__ = (
      'attributes_all',
      )

   def __init__(self, mjob, branch_defs):
      Ccp_Merge_Base.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Ccp_Merge_Base.reinit(self)
      self.attributes_all = {}

   # ***

   #
   def attributes_prepare(self):

      # Load attributes from the database or make new ones, per the 
      # attrs_define_* definitions.

      log.info('Preparing attributes...')

      new_attrs = []

      for ta_def in self.defs.attrs_metadata:
         if ta_def.attr_source:
            attr = self.attribute_load(ta_def)
            if attr is None:
               attr = self.attributes_create_from(ta_def)
               new_attrs.append(attr)
            # else, MAYBE: See if attribute definition has changed, and update 
            #              attribute if so. Or complain and make user use
            #              ccp.py to update the attribute. For now, assuming
            #              existing attr is okay.
            ta_def.ccp_atid = attr.stack_id
            g.assurt(attr.stack_id not in self.attributes_all)
            self.attributes_all[attr.stack_id] = attr
            # 2013.05.11: Use the field name specified by the attribute. So
            #             that it no longer has to be hard-coded in a
            #             branches/*_defs.py file.
            log.debug('attrs_prepare: field_target: %s / spf_field_name: %s'
                      % (ta_def.field_target, attr.spf_field_name,))
            g.assurt(attr.spf_field_name)
            ta_def.field_target = attr.spf_field_name

      # In the unlikely event the user has enabled no_new_attrs, bail now (and
      # rollback the database on the way out).
      if self.spf_conf.no_new_attrs and new_attrs:
         raise GWIS_Error('%s: %s. %s'
               % ('Cannot export branch: attr(s) not created yet',
                  ', '.join([str(x) for x in new_attrs]),
                  'Try importing first, or disabling no_new_attrs.',))

   #
   def attribute_load(self, ta_def):
      attr = None
      if ta_def.attr_source:
         # See if the attribute already exists.
         internal_name = ta_def.attr_source
         attrs = attribute.Many()
         attrs.search_by_internal_name(internal_name, self.qb_cur)
         if (len(attrs) == 1):
            log.debug('attr_load: %s' % (attrs[0],))
            attr = attrs[0]
         else:
            g.assurt(len(attrs) == 0)
      return attr

   #
   def attributes_create_from(self, ta_def):

      # NOTE: 2013.05.11: spf_field_name is new. Until now, the name and the
      #       field name have been the same, but really, the name should be
      #       anything the user wants (a "friendly name") and we should have
      #       a separate field for the 10-character-maximum Shapefile field
      #       name.
      #       Here, we use the field name as the attribute name, but the user
      #       is free to change the value (i.e., via flashclient). The user
      #       can also now edit the Shapefile field name via flashclient, and
      #       this'll be reflected the next time the user exports a Shapefile
      #       (so whatever current spf_field_name is set is the one used for
      #       the import for export).

      attr_name = ta_def.field_target
      internal_name = ta_def.attr_source
      spf_field_name = ta_def.field_target

      if int == ta_def.attr_type:
         attr_type = 'integer'
      elif str == ta_def.attr_type:
         attr_type = 'text'
      elif bool == ta_def.attr_type:
         attr_type = 'boolean'
      else:
         g.assurt(False)

      log.verbose(' >> attributes_create_from: %s (%s) / %s' 
                  % (attr_name, internal_name, attr_type,))

      new_attr = attribute.One(
         qb=self.qb_cur,
         row={
            # item_versioned
            'system_id'           : None, # assigned later
            'branch_id'           : self.qb_cur.branch_hier[0][0],
            'stack_id'            : self.qb_cur.item_mgr.get_next_client_id(),
            'version'             : 0,
            'deleted'             : False,
            'reverted'            : False,
            'name'                : attr_name,
            #'valid_start_rid'    : # assigned by 
            #'valid_until_rid'    : #   version_finalize_and_increment
            # attribute
            'value_internal_name' : internal_name,
            'spf_field_name'      : spf_field_name,
            'value_type'          : attr_type,
            'value_hints'         : '',
            'value_units'         : '',
            'value_minimum'       : None,
            'value_maximum'       : None,
            'value_stepsize'      : None,
            'gui_sortrank'        : None,
            'applies_to_type_id'  : Item_Type.BYWAY,
            'uses_custom_control' : False,
            'value_restraints'    : None,
            'multiple_allowed'    : False,
            'is_directional'      : False,
            }
         )

      # This attribute is new, and we're using target_groups to set 
      # permissions, so don't set grac_mgr=self.qb_cur.grac_mgr.
      # 
      # See ccp_merge_conf.check_errs. The user can specify the groups access
      # in an input file but normally the target_groups is just one record for
      # the Public group to be editor (see self.add_perms('Public', 'editor')).
      #
      new_attr.prepare_and_save_item(self.qb_cur,
                  target_groups=self.target_groups, 
                  rid_new=self.qb_cur.item_mgr.rid_new,
                  ref_item=None)

      log.info('Created attribute: %s' % (new_attr.value_internal_name,))

      return new_attr

   # ***

# ***

if (__name__ == '__main__'):
   pass

