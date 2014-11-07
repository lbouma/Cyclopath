# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

from decimal import Decimal
import os
import re
import sys
import time

import conf
import g

log = g.log.getLogger('import_init')

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.grac_manager import Grac_Manager
from item.grac import group
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.shapefile_wrapper import Shapefile_Wrapper

from merge.import_stats import Import_Stats

# ***

class Feat_Skipped(Exception):

   def __init__(self, message=''):
      Exception.__init__(self, message)

# ***

class Import_Init(Import_Stats):

   shpf_classes = ['incapacitated', 'conflatable', 'importable',]

   geom_types = {
      ogr.wkbLineString: (ogr.wkbLineString, 
                          ogr.wkbLineString25D, 
                          ogr.wkbMultiLineString, 
                          ogr.wkbMultiLineString25D,),
      ogr.wkbPoint:      (ogr.wkbPoint, 
                          ogr.wkbPoint25D, 
                          ogr.wkbMultiPoint, 
                          ogr.wkbMultiPoint25D,),
      ogr.wkbPolygon:    (ogr.wkbPolygon, 
                          ogr.wkbPolygon25D, 
                          ogr.wkbMultiPolygon, 
                          ogr.wkbMultiPolygon25D,),
      }

   geom_multis = [
      ogr.wkbMultiLineString, 
      ogr.wkbMultiLineString25D,
      ogr.wkbMultiPoint, 
      ogr.wkbMultiPoint25D,
      ogr.wkbMultiPolygon, 
      ogr.wkbMultiPolygon25D,
   ]

   __slots__ = (
      # 
      # *** Members that persist across Shapefiles.
      # 
      # Lookup of Shapefiles we skipped because they don't have the fields we
      # need. Keyed by Shapefile name and value is the reason it was skipped.
      'skipped_shpf_errs',
      # Names of Shapefiles that we searched for missing features (compared
      # against skipped_shpf_errs to tell user which Shapefiles we processed).
      'agency_shpfs',
      #
      # *** Members specific to each Shapefile being processed.
      #
      # The shpf_class indicates what we can do with the Shapefile:
      #   'importable'    # The best state. User has audited; we can import.
      #   'conflatable'   # For fresh imports; we'll conflate to new Shapefile.
      #   'incapacitated' # Means to ignore Shapefile for some reason.
      'shpf_class',
      # 
      # The layer's geometry type.
      'layer_geom_type',
      # If the geometry type is something we can import (to a byway, region, 
      # terrain, waypoint, etc.), we'll set base_geom_type to layer_geom_type.
      'base_geom_type',
      #
      # *** Collections of Feature FIDs, specific to each Shapefile.
      #
      # The ccp_fids is a 1-to-m lookup of Ccp ID-to-Agy feats, where m >= 0.
      # We might have to save a new byway if the geometry is changed (e.g.,
      # if _NEW_GEOM, or otherwise), and we might have to split the byway into
      # multiple, split byways (if m > 1), and we might have to save new
      # link_values (if the attributes (Shapefile fields) have changed). (And
      # we don't have to conflate edges (Ccp Id to Agy Id) but we might have to
      # conflate nodes (at network intersections; see autonoding).)
      #
      # This lookup is a dict, keyed by Ccp stack ID; value is a list of FIDs.
      'ccp_fids',
      #
      # The agy_fids is a collection of so-called Standalone Updates: 
      # Line segments, or features, from the "Update" (Agency) dataset that are
      # guaranteed to not match any existing Cyclopath geofeature. These are 
      # new features: we'll save a new byway for 'em and new link_values, but 
      # we'll also wire them to the network (using automatic node snapping, or 
      # autonoding).
      #
      # FIXME: Autonoding only happens for endpoint-to-endpoint intersections?
      #        Does it apply to endpoint-edge intersections?
      #        What about edge-to-edge crossings? 
      #        Maybe autonoding is a secondary task/process?
      # (Note: calling it autonoding to avoid calling it node conflation. 
      #        though node matching could work, but without the "auto" you 
      #        might think it's manual.)
      #
      # This collection is a set of FIDs.
      'agy_fids',
      #
      # The Eat (Me) features (meant in the sense of the cake from Alice in 
      # Wonderland and not in the millions of other senses (ahem, thanks Urban
      # Dictionary, for tainting the phrase)) are totes new and unknown and we
      # have no idea what we're going to do with them... a/k/a, we'll conflate
      # them and spit them out in the final Shapefile and make sure the user
      # audits our results and sends them through import again before we commit
      # them to the database. For these features, since we're not making new
      # byways yet, we won't assign node_endpoints, but we'll try our 
      # dagnabbitest to at least snap-to existing node_endpoints.
      #
      # This collection is a set of FIDs.
      #'eat_fids',
      'new_fids',
      #
      # *** Missing feature helpers.
      #
      'agency_ids',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Stats.__init__(self, mjob, branch_defs)
      #
      self.skipped_shpf_errs = {}
      self.agency_shpfs = set()

   # ***

   #
   def reinit(self):
      Import_Stats.reinit(self)
      #
      self.shpf_class = None
      #
      self.layer_geom_type = None
      #
      self.base_geom_type = None
      #
      # Cyclop'tures: Cyclopath Features: Cyclopath stack ID => 1 or more FIDs.
      self.ccp_fids = {}
      #
      # Standalone Updates and Eat Mes are straight-up singular line features
      # from the agency source so we just need their FIDs... and then only
      # reason we use a set is because we're paranoid (FIDs should always be
      # unique...). The new features have already been conflated, so if their
      # _ACTION is 'Import', we'll import them as new byways. The eat features
      # have not been conflated; if there are any "eats", we'll run them
      # through conflation and spit them out in the final Shapefile.
      self.agy_fids = set()
      self.new_fids = set()
      #
      # List of feature IDs from the conflated data to check for missing feats.
      self.agency_ids = set()

   #
   def job_cleanup(self):
      Import_Stats.job_cleanup(self)
      # We've processed all of the Shapefiles that were in the zipfile so now
      # we can complain if there were Shapefiles that we couldn't process.
      skipped_names = set(self.skipped_shpf_errs.keys())
      problem_names = list(skipped_names.difference(self.agency_shpfs))
      err_s = ' / '.join([self.skipped_shpf_errs[x] for x in problem_names])
      if err_s:
         # FIXME: How do we complain to the user? Do we just raise and mark the
         # job failed, or do we still make the zip but don't commit? For now,
         # just raising...
         # FIXME: See RESULTS.txt: Just write it there.
         # E.g., Status: Successful / Audit Needed / Failed, etc...
         log.error(err_s)
         raise Exception(err_s)

   # *** Stage 1

   #
   def import_initialize(self):

      # Pop the next Shapefile from our list and open it.
      self.shapefile_open_source()

      # Take a look at the Shapefile and see if we recognize it. This raises if
      # the Shapefile is almost a Cyclopath shapefile but not quite.
      self.shapefile_classify()

      if self.shpf_class != 'incapacitated':
         self.import_initialize_classified()

   #
   def import_initialize_classified(self):

      if self.shpf_class == 'importable':
         self.shapefile_prepreprocess(load_config=True)
      else:
         g.assurt(self.shpf_class == 'conflatable')
         # MAYBE: load_config=False means this is a no-op?
         self.shapefile_prepreprocess(load_config=False)
         self.spf_conf.revision_id = revision.Revision.revision_max(
                                                      self.qb_cur.db)
         self.spf_conf.branch_id = self.mjob.wtem.branch_id
         if not self.mjob.wtem.enable_conflation:
            log.warning('Skipping shapefile: conflation not enabled.')
            self.shpf_class = 'incapacitated'
      # Check for conf errs. This raises if there's a problem.
      log.debug('import_initialize_classified: spf_conf: %s'
                % (str(self.spf_conf),))
      self.spf_conf.check_errs()

      # FIXME: Make a switch in CONFIG to indicate if this is production or
      # development build... and then only enable this for devs/demos.
      #if self.spf_conf.db_override:
      #   log.warning('import_initialize: db_override: %s'
      #               % (self.spf_conf.db_override,))
      #   db_glue.DB.set_db_name(self.spf_conf.db_override)

      all_errs = []

      if self.shpf_class != 'incapacitated':
         self.setup_qbs(all_errs)

      if self.spf_conf.branch_id != self.mjob.wtem.branch_id:
         self.shpf_class = 'incapacitated'
         err_s = ('Incompatible branch ID: Shapefile says %d, expecting %d.'
                  % (self.spf_conf.branch_id, self.mjob.wtem.branch_id,))
         all_errs.append(err_s)
         #
         self.qb_src = None
         self.qb_cur = None

      if not all_errs:
         self.branches_prepare()
         if self.shpf_class == 'importable':
            # See about them groups and permissions.
            self.verify_target_permissions(all_errs)
      if not all_errs:
         # Open the target shapefile.
         self.shapefile_engine_prepare()
         self.shapefile_create_targets(skip_tmps=False)
         # Create the geometry-less config "features".
         self.ccp_conf_create_feats()
         # Open the reference Shapefile, maybe. This raises if the Shapefile is
         # missing.
         if self.spf_conf.find_missing:
            self.agency_gdb, self.agency_lyr = (
               self.geodatabases_open_gdb(self.spf_conf.find_missing))
            self.agency_shpfs.add(self.agency_gdb.GetName())

      if all_errs:
         err_s = ('import_initialize: problems: %s' % (all_errs,))
         log.warning(err_s)
         raise Exception(err_s)

      # Load (and maybe create) the attributes.
      self.attributes_prepare()

      # Now that we've saved new attributes, we can load the item_mgr cache.
      self.qb_cur.item_mgr.load_cache_attachments(self.qb_cur)

   # ***

   #
   def shapefile_open_source(self):

      # Set up our projection. This is Cyclopath's spatial reference 
      # system, which in PostGIS is SRID 26915, but here we uses another name 
      # for it, UTM 15N; NAD83.
      self.ccp_srs = osr.SpatialReference()
      self.ccp_srs.SetProjCS('UTM 15N (NAD83)')
      self.ccp_srs.SetWellKnownGeogCS('')
      self.ccp_srs.SetUTM(15, True)

      self.geodatabases_close()

      try:
         shpf_fname = self.mjob.shpf_fnames.pop()
      except IndexError:
         # This should be a programmer error.
         err_s = 'Unexpected error: out of shapefile names'
         log.error(err_s)
         raise Exception(err_s)

      self.import_gdb, self.import_lyr = (
         self.geodatabases_open_gdb(shpf_fname))

   #
   def shapefile_classify(self):

      missing_fields = []

      layer_def = self.import_lyr.GetLayerDefn()

      # Look for '_ACTION', etc.
      g.assurt(self.defs.confln_required_fields)
      for field_name in self.defs.confln_required_fields:
         if layer_def.GetFieldIndex(field_name) == -1:
            missing_fields.append(field_name)

      if missing_fields:
         if len(self.defs.confln_required_fields) != len(missing_fields):
            self.shpf_class = 'incapacitated'
            err_s = (
               'Shapefile %s is missing *some* required Cyclopath fields: %s'
               % (self.import_lyr.GetName(), 
                  ', '.join(missing_fields),))
            #log.warning(err_s)
            #raise Exception(err_s)
            # FIXME: How do we notify the user that we're skipping this file?
            log.info(err_s)
            self.skipped_shpf_errs[self.import_gdb.GetName()] = err_s
         else:
            # Shapefile missing *all* required Cyclopath fields.
            # Check that none of its existing fields conflicts.
            conflicting_fields = []
            for ta_def in self.defs.attrs_metadata:
               if layer_def.GetFieldIndex(ta_def.field_source) != -1:
                  conflicting_fields.append(ta_def.field_source)
            if conflicting_fields:
               self.shpf_class = 'incapacitated'
               err_s = (
                  'Shapefile %s has conflicting Cyclopath fields: %s'
                  % (self.import_lyr.GetName(), 
                     ', '.join(conflicting_fields),))
               log.info(err_s)
               self.skipped_shpf_errs[self.import_gdb.GetName()] = err_s
            else:
               self.shpf_class = 'conflatable'
      else:
         # No missing required fields. We can do this!
         self.shpf_class = 'importable'

      if self.shpf_class != 'incapacitated':
         self.layer_geom_type = layer_def.GetGeomType()
         log.debug('shapefile_classify: layer_geom_type: %s' 
                   % (ogr.GeometryTypeToName(self.layer_geom_type),))
         for geom_type, matching_types in Import_Init.geom_types.iteritems():
            if self.layer_geom_type in matching_types:
               self.base_geom_type = geom_type
         if self.base_geom_type is None:
            err_s = ('Shapefile %s has unknown geometry type: %s'
                     % (self.import_lyr.GetName(), self.layer_geom_type,))
            log.warning(err_s)
            raise Exception(err_s)

   #
   def shapefile_prepreprocess(self, load_config):
      # Loop through the Shapefile and look for the Cyclopath config features.
      self.import_lyr.ResetReading()
      for feat in self.import_lyr:
         # FIXME: break here and test
         # the_action = feat.GetFieldAsString('FIXME_TEST')
         # See if this is a config element.
         is_conf_value = False
         if load_config:
            the_action = feat.GetFieldAsString(self.defs.confln_action)
            ccp_id = feat.GetFieldAsInteger(self.defs.confln_ccp_stack_id)
            unexpected_ccp_id = False
            if the_action == self.defs.action_shpf_def:
               if ccp_id != self.defs.shpf_def_stack_id: # I.e., != -1
                  # Not a big deal; just curious.
                  unexpected_ccp_id = True
               # sc_name is '_CONTEXT' field and sc_value is 'CCP_NAME'.
               sc_name = feat.GetFieldAsString(self.defs.confln_context)
               sc_value = feat.GetFieldAsString(self.defs.confln_ccp_name)
               # Set spf_conf.branch_id, spf_conf.branch_name, etc.
               self.spf_conf.consume_friendly(self, sc_name, sc_value)
               is_conf_value = True
            elif ccp_id < 0:
               unexpected_ccp_id = True
            if unexpected_ccp_id:
               # FIXME: This warning should go in an output file for the
               # user to review.
               log.warning('Unexpected CCP_ID for FID %d: %d' 
                           % (feat.GetFID(), ccp_id,))
         # Release memory.
         feat.Destroy()
      log.debug('shapefile_prepreprocess: spf_conf: %s'
                % (str(self.spf_conf),))

   # *** HELPER FCNS.

   #
   def branches_prepare(self):

      log.info('Preparing output branch')

      g.assurt(self.qb_cur is not None)
      #stack_id = self.mjob.target_branch.stack_id
      stack_id = self.mjob.wtem.branch_id # or self.qb_cur.branch_hier[0][0]?

      # Get a row lock on the branch item. This is, e.g., like calling 
      # self.db.transaction_begin_rw('revision'), except we're locking 
      # just updates on the branch and not any parent branches.
      self.qb_cur.request_lock_for_update = True
      # This throws if the stack ID misses.
      # BUG nnnn: Use NOWAIT, e.g., FOR UPDATE OF branch NOWAIT, so we don't 
      #  block the op? NOWAIT throws an error if the row is already locked.
      locked_branch = Grac_Manager.ccp_get_gf(branch.Many(), stack_id, 
                                              self.qb_cur)
      # NOTE: locked_branch goes out of scope but self.qb_cur has row-lock.
      self.qb_cur.request_lock_for_update = False
      # FIXME: Put a breakpoint here and check that the branch row is really
      # locked.
      # FIXME: Put a breakpoint before releasing qb_cur and make sure the
      # branch rows is still really locked.
      # BUG nnnn: Replace 'revision' locks with branch-row locks... I think
      # that's okay to do. If you merge/update two branches, get two row locks 
      # (get lowered-number one first). But you can let two different people
      # edit two different branches, i.e., one person edits the parent branch
      # and another person edits the child branch?

      log.info('Getting public group ID')

      # What's this doing in a fcn. called branches_prepare()?
      #self.group_public_id = (
      #   self.qb_cur.db.sql(
      #      "SELECT cp_group_public_id()")[0]['cp_group_public_id'])
      self.group_public_id = group.Many.public_group_id(self.qb_cur.db)

   #
   def verify_target_permissions(self, all_errs):
      # Make sure that either the public group or a shared group has at least 
      # editor access, or a private group has owner access.
      editor_group_assigned = False
      for perm_def in self.spf_conf.permissions:
         acl_id = Access_Level.get_access_level_id(perm_def.access_level)
         log.debug('verify_target_perms: looking for grp: %s / acl: %s [%d]'
                   % (perm_def.group, perm_def.access_level, acl_id,))
         if acl_id not in (Access_Level.owner,
                           Access_Level.arbiter,
                           Access_Level.viewer,
                           Access_Level.editor,):
            all_errs.append('verify_target_perms: unexpected access level: %s' 
                           % (perm_def.access_level,))
         else:
            editor_group_assigned |= self.resolve_accesses_group(
                                 perm_def.group, acl_id, all_errs)
      if not editor_group_assigned:
         all_errs.append(
            'verify_target_perms: group with editor or better not found.')

   #
   def resolve_accesses_group(self, group_name_or_id, acl_id, all_errs):
      # I'm [lb isn't] completely sure how this works. The user has arbiter
      # access or better to the branch, and this isn't as important. Here, 
      # we want to check the user has some sort of access to the groups it 
      # wants to assign ownership. To his/her private group, user has viewer
      # access, so that cannot unassign themselves. To the public group, as
      # well. It's to private groups that the user's access is a little
      # different. And why is all this complicated access code in this file?
      errs = []
      editor_group_assigned = False

      group_id, group_name = group.Many.group_resolve(self.qb_cur.db, 
                                                      group_name_or_id)
      if bool(group_id and group_name):
         try:
            gm = self.qb_cur.grac_mgr.group_memberships[group_id]
            log.debug('resolve_accesses_: found grp_mmbrshp: %s' % (gm,))
            g.assurt(self.user_group_id)
            if gm.group_id == self.user_group_id:
               log.debug('resolve_accesses_: assigning access to self.')
               g.assurt(gm.group_scope == Access_Scope.private)
               g.assurt(gm.access_level_id == Access_Level.viewer)
               # User must give themselves ownership of the item.
               if acl_id != Access_Level.owner:
                  errs.append(
'resolve_accesses_: you must be owner of your items, or do not assign access.')
               else:
                  editor_group_assigned = True
            elif gm.group_scope == Access_Scope.public:
               log.debug('resolve_accesses_: assigning access to public.')
               # Is this right?:
               #g.assurt(gm.access_level_id == Access_Level.viewer)
               # Most users have viewer access to Public group but devs and
               # admins have better.
               g.assurt(Access_Level.is_same_or_more_privileged(
                        gm.access_level_id, Access_Level.viewer))
               if acl_id not in (Access_Level.editor, Access_Level.viewer,):
                  errs.append(
                     'resolve_accesses_: public must be editor or viewer.')
               elif acl_id == Access_Level.editor:
                  editor_group_assigned = True
            elif gm.group_scope == Access_Scope.private:
               # User should never have group_membership to another user's 
               # private group.
               g.assurt(False)
            else:
               g.assurt(gm.group_scope == Access_Scope.shared)
               log.debug('resolve_accesses_: assigning access to shared.')
               if acl_id == Access_Level.editor:
                  editor_group_assigned = True
         except KeyError:
            log.debug('resolve_accesses_: user does not have membership: %s'
                      % (group_name,))
            # This is currently not allowed, and I can't think we'll ever want
            # to.
            errs.append('resolve_accesses_: not a group or access denied: %s'
                        % (group_name_or_id,))
         if not errs:
            if gm in self.target_groups:
               errs.append('resolve_accesses_: group specified twice: %s'
                           % (group_name_or_id,))
            else:
               self.target_groups[gm] = acl_id
      else:
         errs.append('resolve_accesses_: not a group or access denied: %s'
                     % (group_name_or_id,))
      all_errs.extend(errs)
      return editor_group_assigned

   # *** Stage 2

   #
   def shapefile_organize_feats(self):

      log.info('Loading conflated features...')

      num_feats = Shapefile_Wrapper.ogr_layer_feature_count(self.import_lyr)

      prog_log = self.progr_get(log_freq=5000, loop_max=num_feats)

      # Organize the conflated features by stack ID, that is, find all features
      # with the same stack ID.

      # FIXME: Update the Wiki docs. Esp. since splitstart/end are removed.
      #   ala, http://mediawiki/index.php?title=Tech:Cycloplan/Conflation
      #                                               #SPLITSTART_and_SPLITEND

      lookup = {}

      skipped_cnt = 0

      self.import_lyr.ResetReading()
      for feat in self.import_lyr:

         # NOTE: We only store the FID for now in some list, so we don't bloat
         #       memory. We'll fetch by FID later.
         try:
            cache_nodes = True
            self.shapefile_organize_feats_feat(feat)
         except Feat_Skipped, e:
            cache_nodes = False
            skipped_cnt +=1
         finally:
            # For feats we're going to process, pre-load their endpoints so we
            # can update the node_endpoint cache. We need the cache to join attr-
            # equivalent adjacent line segments, and we need to cache for
            # autonoding.
#            if cache_nodes:
#               self.node_cache_consume(feat)
            # NOTE: If we call feat.Destroy but someone has a handle to the 
            # feature, that certain someone will eventually cause a 
            # "Segmentation fault (core dumped)" if they try to use the feature
            # (even a dir(feat) in (Pdb) causes the core dump, because OGR is
            # implemented in C and we've told it to release the memory, but 
            # we've still got a Python shim to it). We also want to keep memory
            # usage low -- especially for developers -- so we just store FIDs
            # and hydrate features on an as-needed basis. So be gone to you,
            # feat.
            feat.Destroy()

         if prog_log.loops_inc():
            # DEVS: Even 30-some-thousand features should load quickly, so 
            # you might just want to 'pass' here rathen than 'break'.
            #pass
            break

      log.info('shapefile_organize_feats: Skipped %d feats.' % (skipped_cnt,))

   #
   def shapefile_organize_feats_feat(self, feat):

      # HACK ALERT: [lb] hates short-circuit returns... but... these used to be
      # continues in a for-loop, which I guess is pretty much the same offense,
      # and I wanted to make the for-loop more readable...
      # hmmm, what about raising? does that bother you, too?

      # Get the input data unique ID (Cyclopath stack ID).
      ccp_id = feat.GetFieldAsInteger(self.defs.confln_ccp_stack_id)

      # FIXME: For new Shapefiles, we don't have to require user to add all
      # the new fields. Instead, once we determine that 
      # (self.shpf_class == 'conflatable'), we should add the fields to the 
      # Shapefile herein our Python code.

      # See that we're not looking at a Cyclopath Conflation Setting.
      the_action = feat.GetFieldAsString(self.defs.confln_action)
      if the_action == self.defs.action_shpf_def: # E.g., == 'CCP_'
         # This is a self.spf_conf setting, so just move on.
         raise Feat_Skipped()
      elif ccp_id < 0:
         # MAYBE: This should probably just be log.debug.
         log.warning('Unexpected: feat has ccp_id < 0: FID: %s' 
                     % (feat.GetFID(),))
         self.tlayer_add_fix_me(feat, 'Negative CCP_ID')
         self.stats['fixme_negative_ccp_id'] += 1
         raise Feat_Skipped()

      # For quickly debugging specific features.
      if self.debug.debug_just_ids:
         # FIXME: What does this return if field not there?
         if ccp_id not in self.debug.debug_just_ids:
            raise Feat_Skipped()

      # Check the geometry type.
      geom = feat.GetGeometryRef()

      if geom is None:
         # MAYBE: This should probably just be log.debug.
         log.warning('Unexpected: feat has no geom: FID: %s' 
                     % (feat.GetFID(),))
         self.tlayer_add_fix_me(feat, 'Bad Geom (Empty)')
         self.stats['fixme_empty_geom'] += 1
         raise Feat_Skipped()

      geom_type = geom.GetGeometryType()
      if geom_type not in Import_Init.geom_types[self.base_geom_type]:
         # MAYBE: This should probably just be log.debug.
         log.warning(
            'Unexpected feat geom type: expected: %s / got: %s / FID: %s'
            % (ogr.GeometryTypeToName(self.layer_geom_type),
               ogr.GeometryTypeToName(geom_type),
               feat.GetFID(),))
         self.tlayer_add_fix_me(feat, 'Bad Geom (Wrong type)')
         self.stats['fixme_bad_geom_type'] += 1
         raise Feat_Skipped()

      # See if this is a multi-geometry.
      if geom_type in Import_Init.geom_multis:
         if geom.GetGeometryCount() > 1:
            # Add to the final Shapefile; temp_layer_add will split the single,
            # multi-geometry feature into multiple, single-geometry features.
            self.tlayer_add_fix_me(feat, 'Split from Multi')
            self.stats['fixme_multi_geom_src'] += 1
            raise Feat_Skipped()
      # else, not a multi-geometry. (Q: Does GetGeometryCount() work? Rets 1?)

      # See if the geometry is otherwise satisfactory.
      if not geom.IsSimple():
         self.tlayer_add_fix_me(feat, 'Bad Geom (Not Simple)')
         self.stats['fixme_bad_geom_unsimple'] += 1
         raise Feat_Skipped()
      #
      if geom.IsRing():
         # If OGR says IsRing and we save to Cyclopath, PostGIS will crash when
         # we call ST_SimplifyPreserveTopology (EXPLAIN: which versions?).
         # E.g., 
         #  EdgeRing::getRingInternal: IllegalArgumentException: 
         #   Invalid number of points in LinearRing found 3 - must be 0 or >= 4
         #  cycling ccpv3 [local] UPDATE: RightmostEdgeFinder.cpp:77: 
         #   void geos::operation::buffer::RightmostEdgeFinder::findEdge(
         #                  std::vector<geos::geomgraph::DirectedEdge*>*): 
         #                    Assertion `checked>0' failed.
         self.tlayer_add_fix_me(feat, 'Bad Geom (Ring)')
         self.stats['fixme_bad_geom_ring'] += 1
         raise Feat_Skipped()

      if self.shpf_class == 'conflatable':

         # A 'conflatable' Shapefile simply means a Shapefile that's never been
         # imported or submitted to the merge process. It may or may not have
         # the AGY_ID and AGY_NAME fields, but it doesn't have any Cyclopath
         # fields. Hence, none of the features have been conflated to Cyclopath
         # features.

         self.new_fids.add(feat.GetFID())

      else:

         g.assurt(self.shpf_class == 'importable')

         # Collect agency IDs so we can look for missing features later.
         # NOTE: This assume Agency IDs are unique per feature. We can't use
         #       feat.GetFID() because the FIDs don't relate between files.
         agency_id = feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
         if agency_id:
            # Because of splits, agency IDs may be duplicated. We use a set.
            self.agency_ids.add(agency_id)

         #the_action = feat.GetFieldAsString(self.defs.confln_action)
         the_context = feat.GetFieldAsString(self.defs.confln_context)

         if the_action != self.defs.action_import: # E.g., != 'Import'

            if the_action.lower() == self.defs.action_ignore: # == 'Ignore'
               self.stats['ignore_fts_total'] += 1
            # The System only cares once all features are _ACTIONed 'Import'
            # or 'Ignore'. We tally statistics on FIXMEs but really anything
            # that's not 'Import' or 'Ignore' is okay so we don't make
            # defines for these.
            elif the_action.lower() == 'fixme':
               self.stats['fixme_other_reason'] += 1
            else:
               self.stats['fixme_wrong_action'] += 1

            new_feat = self.tlayer_add_feat(feat, the_context, the_action)

            raise Feat_Skipped()

         else:

            # Add the feature FID to one of ccp_fids, agy_fids, or new_fids.
            self.shapefile_organize_import_feats(feat, 
               the_action, the_context, ccp_id, agency_id)

   # ***

   #
   def shapefile_organize_import_feats(self, feat, the_action, the_context, 
                                             ccp_id, agency_id):

      # Group features based on how we'll process them.

      if ccp_id == 0:

         # This is a "new" item, an item from the agency data set for
         # which there is no match in the Cyclopath data.

         is_conflated = self.defs.ogr_str_as_bool(feat, 
                     self.defs.confln_conflated, False) # '_CONFLATED'

         # If the user has marked the feature _CONFLATED, it means, indeed,
         # this feature is new; just check its end points and along its edge
         # for possible intersections and make and/or add to node_endpoint.

         if is_conflated:

            log.verbose(' >> standup: agency ID: %s' % (agency_id,))
            # Standups are not guaranteed to be well-connected. We'll run the
            # dangler hunterer on these later. (But they are guaranteed not to
            # match any existing geofeature in Cyclopath.)
            g.assurt(feat.GetFID() not in self.agy_fids)
            self.agy_fids.add(feat.GetFID())
            # MAYBE: Should we just use len(self.agy_fids) instead of stats[]?
            self.stats['count_fids_agy'] += 1

         else:

            # This line segment has not been conflated.
            self.new_fids.add(feat.GetFID())
            # MAYBE: Should we just use len(self.agy_fids) instead of stats[]?
            self.stats['count_fids_new'] += 1

      else:

         # For now, we can only treat all features as potentially split
         # features, so we collect them all into groups with matching Cyclopath
         # stack IDs.

         misc.dict_set_add(self.ccp_fids, ccp_id, feat.GetFID(),
                           strict=True)
         # We maintain a dict of sets, so maintain a count of all set sizes.
         self.stats['count_fids_ccp'] += 1

         # FIXME: Implement usage of EDIT_DATE. For not, scrutinizing all
         # features.
         # # 'EDIT_DATE'
         # if feat.GetFieldIndex(self.defs.confln_edit_date) != -1:
         #    edit_date = feat.GetFieldAsString(self.defs.confln_edit_date)
         #    log.debug(' >> edit_date: %s' % (edit_date,))
         #    # FIXME: Check the date is past a certain date?
         #    self.stats['count_edited'] += 1

   # *** Stage 3

   #
   def missing_features_consume(self):

      g.assurt(self.agency_lyr is not None)

      log.info('Looking for missing features in Shapefile: %s' 
               % (self.agency_lyr,))

      # Go through the original Agency source and find features that missed out
      # on the conflation.

      log.debug('  >> Conflated data has %d unique agency IDs' 
                % (len(self.agency_ids),))

      n_missing_geom = 0

      g.assurt(self.stats['fixme_missing_feats'] == 0)

      num_feats = Shapefile_Wrapper.ogr_layer_feature_count(self.agency_lyr)
      prog_log = self.progr_get(log_freq=5000, loop_max=num_feats)

      self.agency_lyr.ResetReading()
      for feat in self.agency_lyr:

         agency_id = None
         if feat.GetFieldIndex(self.defs.confln_agy_obj_id) != -1:
            agency_id = feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
         else:
            log.error('missing_features_consume: field missing: %s: FID: %s'
                      % (self.defs.confln_agy_obj_id, feat.GetFID(),))

         # FIXME: We don't check the database for this Agency ID (i.e., search 
         # attribute link_values). So if you've already imported and committed 
         # once, you can't run the find-missing command (unless we fix this
         # code and add a check of the database).
         #
         # Something like this?:
         #  agy_ids = link_attribute.Many('/metc_bikeways/agy_id')
         #  agy_ids.search_by_value_integer??(self.qb_cur, agency_id)

         if agency_id not in self.agency_ids:
            geom = feat.GetGeometryRef()
            if geom is not None:
               self.stats['fixme_missing_feats'] += 1
               self.tlayer_add_fix_me(feat, 'Missing Feature')
            else:
               log.debug('missing_features_consume: skipping geom-less: %d'
                         % (feat.GetFID(),))
               n_missing_geom += 1

            if prog_log.loops_inc():
               # DEVS: Even 30-some-thousand features should load quickly, so 
               # you might just want to 'pass' here rathen than 'break'.
               #pass
               break

         feat.Destroy()

      if self.stats['fixme_missing_feats']:
         log.info('Added %d missing feats of %d agy feats to target.'
                  % (self.stats['fixme_missing_feats'], 
                     self.agency_lyr.GetFeatureCount(),))

      if n_missing_geom:
         log.warning('missing_features_consume: skipped %d geom-less feats'
                     % (n_missing_geom,))

   # ***

   #
   def regions_to_shp(self):

      log.info('Writing regions to shapefile...')

      # FIXME: We can delete this fcn., right?
      #
      #
      g.assurt(False) # No longer used.

      # NOTE: We're searching for all regions. 

      regions = region.Many()

      self.qb_cur.db.dont_fetchall = True
      regions.search_for_items(self.qb_cur)

      g.assurt(self.qb_cur.db.curs.rowcount > 0)

      generator = regions.results_get_iter(self.qb_cur)
      for rg in generator:
         # Create feature.
         feat = ogr.Feature(self.layers['region'].GetLayerDefn())
         # Set fields.
         #feat.SetField('in_filter', rg.name in region_names)
         # Set geometry.
         geometry_wkt = rg.geometry_wkt
         if geometry_wkt.startswith('SRID='):
            geometry_wkt = geometry_wkt[geometry_wkt.index(';')+1:]
         geometry = ogr.CreateGeometryFromWkt(geometry_wkt)
         feat.SetGeometryDirectly(geometry)
         g.assurt(feat.GetGeometryRef().IsSimple())
         g.assurt(not feat.GetGeometryRef().IsRing())
         # Write + Cleanup.
         self.layers['region'].CreateFeature(feat)
         feat.Destroy()
      generator.close()

      self.qb_cur.db.dont_fetchall = False
      self.qb_cur.db.curs_recycle()

# ***

if (__name__ == '__main__'):
   pass

