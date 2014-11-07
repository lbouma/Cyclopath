# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME: Implement pickle recovery... or check for paused/suspended and save
# work item step with appropriate pickled data

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import sys

from decimal import Decimal
import re
import time

import conf
import g

from grax.access_level import Access_Level
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from gwis import command_base
from item import item_versioned
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
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.shapefile_wrapper import Shapefile_Wrapper

from merge.ccp_merge_ceil import Ccp_Merge_Ceil
from merge.ccp_merge_layer_base import Ccp_Merge_Layer_Base

log = g.log.getLogger('import_base')

__all__ = ('Import_Base',)

# *** Import_Base

class Import_Base(Ccp_Merge_Ceil):

   __slots__ = (
      # Handle(s) to the shapefile(s).
      'import_gdb',
      'import_lyr',
      'agency_gdb',
      'agency_lyr',
      #
      'target_groups',
      #
      'tlyr_import',
      'tlyr_reject',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Ccp_Merge_Ceil.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Ccp_Merge_Ceil.reinit(self)
      #
      self.import_gdb = None
      self.import_lyr = None
      self.agency_gdb = None
      self.agency_lyr = None
      #
      self.target_groups = {}
      #
      self.tlyr_import = None
      self.tlyr_reject = None

   # ***

   #
   def field_val_setup_all(self, old_byway, src_feat, context,
                                 just_copy_from=False):
      dst_layer = self.target_layers_temp[self.tlyr_import]
      dst_feat = self.defs.field_val_setup_all(dst_layer, old_byway, src_feat,
                                               context, just_copy_from)
      return dst_feat

   #
   def substage_cleanup(self, maybe_commit):

      # Maybe-Commit just means don't commit (or vacuum) is this is just an
      # export operation.
      do_commit = maybe_commit

      log.debug('substage_cleanup: Closing database.')

      commit_msg = None
      if do_commit:
         g.assurt(self.import_gdb is not None)
         commit_msg = self.spf_conf.commit_msg
         if not commit_msg:
            # FIXME: Not tested...
            commit_msg = ('Shapefile Import: %s'
                          % (self.import_gdb.GetName(),))

      log.debug('substage_cleanup: Closing query_builders and databases.')

      if self.qb_cur is not None:
         self.commit_qbs(do_commit, commit_msg)
      # else, i.e., g.assurt(self.shpf_class == 'incapacitated')

      # The base class calls release_qbs which closes dbs and qbs.
      Ccp_Merge_Ceil.substage_cleanup(self, do_commit)

   # *** Database fcns.

   #
   def commit_qbs(self, do_commit, commit_msg, skip_vacuum=False,
                                               skip_geometry=False):

      g.assurt(self.qb_cur is not None)

      if (self.qb_cur.item_mgr.rid_new is not None) and (self.target_groups):

         # Both of these operations take a little bit of time.
         #
         # To make the new revision, we call cp_revision_geosummary_update,
         # which takes a while. And to commit everything, well, e.g.,
         # committing five hundred thousand rows takes a while.
         time_0 = time.time()

         log.info('Saving new revision: %s...'
                  % (self.qb_cur.item_mgr.rid_new,))

         # NOTE: We could use the host or IP address of the machine when the
         # user submitted the work job, but we also have a non-anonymous
         # username, so setting the host to 'localhost' doesn't really matter.
         host = 'localhost'

         # Make group_revisions for the public group and the shared group.
         groups_ids = []
         for grp_mship, acl_id in self.target_groups.iteritems():
            groups_ids.append(grp_mship.group_id)
         g.assurt(len(groups_ids) > 0)
         # FIXME: Make sure the new revision is marked not revertable:
         #        that would be crazy-silly if someone was able to issue a
         #        revert request on it!
         Item_Manager.revision_save(
            self.qb_cur,
            self.qb_cur.item_mgr.rid_new,
            self.qb_cur.branch_hier,
            host,
            self.mjob.wtem.created_by,
            commit_msg,
            groups_ids,
            activate_alerts=False,
            processed_items=None,
            reverted_revs=None,
            skip_geometry_calc=False,
            skip_item_alerts=False)

         # Claim the new revision ID.
         revision.Revision.revision_claim(self.qb_cur.db,
                                          self.qb_cur.item_mgr.rid_new)

         # Claim the new stack IDs.
         self.qb_cur.item_mgr.finalize_seq_vals(self.qb_cur.db)

         log.info('... new revision took %s'
                  % (misc.time_format_elapsed(time_0),))

      g.assurt(self.qb_cur is not None)

      time_0 = time.time()
      if do_commit:
         log.debug('Committing the database transaction.')
         # BUG 2688: Use transaction_retryable?
         self.qb_cur.db.transaction_commit()
      elif self.qb_cur is not None:
         log.debug('Rolling back the database!!')
         self.qb_cur.db.transaction_rollback()
      log.info('... %s took %s'
         % ('Commit' if do_commit else 'Rollback',
            misc.time_format_elapsed(time_0),))

# FIXME: Put in debug? And then delete this...
      skip_vacuum = True

      if do_commit and not skip_vacuum:
         self.db_vacuum()

      if do_commit:
         time_0 = time.time()
         # Update the revision's geometry approximation.
         # FIXME: Hopefully, this is faster after a vacuum.

         db = db_glue.new()
         db.transaction_begin_rw()
         branch_hier = self.qb_cur.branch_hier
         revision.Revision.geosummary_update(db, self.qb_cur.item_mgr.rid_new,
                                                 branch_hier, groups_ids,
                                                 skip_geometry)
         db.transaction_commit()
         db.close()
         log.info('... Rev Geom took %s'
                  % (misc.time_format_elapsed(time_0),))


# FIXME: Test this: 2013.10.30: Do like commit.py, and call do_post_commit
#        (which just tickles Mr. Do!) and called routed_hup (which sends
#        an interrupt to the route daemon).
      if do_commit:
         log.debug('commit_qbs: signalling Mr. Do!')
         self.qb_cur.item_mgr.do_post_commit(self.qb_cur)
         log.debug('commit_qbs: signalling route daemon')
         command_base.Op_Handler.routed_hup(self.qb_cur.db)

      self.qb_cur.item_mgr.rid_new = None

   #
   def setup_qb_cur(self, all_errs):

      # The user must be at least arbiter of the target and not just editor or
      # viewer.
      min_acl = Access_Level.arbiter

      Ccp_Merge_Ceil.setup_qb_cur(self, all_errs, min_acl)

      # Get a new revision ID
      if self.qb_cur is not None:
         log.debug(' >> revision_max: %d'
                   % (revision.Revision.revision_max(self.qb_cur.db),))

      # Get a table lock on 'revision'.
      # FIXME: The import might take a while; we should tell users we're in the
      #         middle of a big commit.
      #         2014.02.26: The revision_lock_dance sort of helps.
      # FIXME: What if another commit is happening by a user or the system?
      #        Will this job simply fail?
      revision.Revision.revision_lock_dance(
         self.qb_cur.db, caller='import_base.py')
      # on failure, maybe just queue again? or keep trying, indefinitely?

      # Get a new revision ID for the changes we're about to make.
      self.qb_cur.item_mgr.start_new_revision(self.qb_cur.db)
      log.debug(' >> got new revision: %d' % (self.qb_cur.item_mgr.rid_new,))

   #
   def db_vacuum(self, full_vacuum=False):

      time_0 = time.time()

      log.info('Vacuuming...')

      if not full_vacuum:
         db = db_glue.new(use_transaction=False)
         db.sql("VACUUM ANALYZE minnesota.geofeature (geometry);")
         db.close()
      else:
         # Vacuum and analyze.
         # EXPLAIN: ANALYZE vs. VACUUM ANALYZE vs. VACUUM FULL vs. CLUSTER.
         #          See also: vacuum analyze verbose.
         # NOTE: Should be database owner, lest some tables go unvacced.
         pg_db = db_glue.new(conf.db_owner, use_transaction=False)
         pg_db.sql("VACUUM ANALYZE;")
         pg_db.close()

      log.info('... Vacuum took %s'
               % (misc.time_format_elapsed(time_0),))

   # ***

   #
   def geodatabases_close(self):

      # We're just closing input Shapefiles here, so no need to call
      # layer.SyncToDisk() (or data_source.SyncToDisk(), which just
      # saves all the layers. (Anyway, I [lb] think when you Release()
      # and the reference count hits zero that there's an implicit save.)

      if self.import_lyr is not None:
         self.import_gdb.Release()
         self.import_gdb = None
         self.import_lyr = None

      if self.agency_lyr is not None:
         self.agency_gdb.Release()
         self.agency_gdb = None
         self.agency_lyr = None

   #
   def geodatabases_open_gdb(self, shpf_fname):

      log.info('geodatabases_open_gdb: %s' % (shpf_fname,))

      g.assurt(isinstance(self.mjob.wtem, merge_job.One))
      xname = '%s.usr' % (self.mjob.wtem.local_file_guid,)
      spath = os.path.join(conf.shapefile_directory, xname, shpf_fname)

      gdb_handle = ogr.Open(spath)
      if gdb_handle is None:
         err_s = 'Could not open shapefile: %s' % (spath,)
         log.error(err_s)
         raise Exception(err_s)

      #log.info('Opened shapefile:')
      #log.info('  %s' % (spath,))
      log.info('Opened shapefile: ===========>\n%s' % (spath,))
      for layer_i in xrange(gdb_handle.GetLayerCount()):
         layer = gdb_handle.GetLayerByIndex(layer_i)
         log.debug(' >> layer[%d]: %s' % (layer_i, layer.GetName(),))

      # You can ask for the layer by index or by name.
      if gdb_handle.GetLayerCount() == 1:
         # NOTE: You can call GetLayer(0) instead of GetLayerByIndex(0).
         gdb_layer = gdb_handle.GetLayerByIndex(0)
         #g.assurt(gdb_layer.GetName() == shpf_def.shpf_layr)
      else:
         #gdb_layer = gdb_handle.GetLayerByName(shpf_def.shpf_layr)
         layers = []
         for layer_i in xrange(gdb_handle.GetLayerCount()):
            lyr = gdb_handle.GetLayerByIndex(layer_i)
            layers.append(lyr.GetName())
         # The way Shapefiles and OGR work, I've [lb] only seen multiple layers
         # when created using OGR. When saved, the layers are each a Shapefile.
         # And to open, you specify a Shapefile name....
         err_s = 'Unexpected error: too many layers: %s' % (', '.join(layers),)
         log.error(err_s)
         raise Exception(err_s)

      log.info(' >> using lyr: %s' % (gdb_layer.GetName(),))
      log.info(' >> found %d features' % (gdb_layer.GetFeatureCount(),))

      # Set up SRS parameters. C.f. import_bmpolygons.
      shapefile_srs = gdb_layer.GetSpatialRef()
      expected_srs = osr.SpatialReference()
      expected_srs.ImportFromEPSG(conf.default_srid)
      if shapefile_srs is None:
         # 2013.04.25: [lb]'s ArcMap license expired, so I saved a Shapefile
         #             using OpenJump. I guess OpenJump didn't preserve the
         #             projection that I guess had been being saved by Arc.
         # Is this really worthy of a warning?
         log.warning('Shapefile has no SRS defined, assuming EPSG:%d'
                     % (conf.default_srid,))
         shapefile_srs = osr.SpatialReference()
         #shapefile_srs.SetWellKnownGeogCS(self.shp_conf.source_srs)
         shapefile_srs.ImportFromEPSG(conf.default_srid)
      else:
         # This script has not worked with shapefiles that indicate their SRS.
         #log.warning('Unexpected code path: not expecting SRS from shapefile')
         log.verbose('shapefile_srs: ===========>\n%s' % (shapefile_srs,))
         g.assurt(shapefile_srs.IsSame(expected_srs))
      self.geom_xform = osr.CoordinateTransformation(shapefile_srs,
                                                     self.ccp_srs)

      # To save memory, in our lookups we just store FIDs rather than storing
      # handles to hydrated Features. That mean the Shapefile must support
      # random read access. ([lb] isn't sure if all ESRI-compliant Shapefiles
      # support random read access and it's just that other OGR source drivers
      # don't, but I've never seen a Shapefile that didn't.)
      # 2011.11.16: Testing reveals:
      # * shapefiles we   read support just RandomRead but not CreateField
      # * shapefiles we create support both RandomRead     and CreateField
      #
      # # This just logs some output:
      Shapefile_Wrapper.gdb_layer_test_capabilities(gdb_layer)
      if not gdb_layer.TestCapability(ogr.OLCRandomRead):
         err_s = ('Your Shapefile does not support Random Read of FIDs: %s'
                  % (shpf_fname,))
         log.error(err_s)
         raise Exception(err_s)

      # Blather some details about the shapefile.
      Shapefile_Wrapper.shapefile_debug_examine_1(gdb_layer)
      Shapefile_Wrapper.shapefile_debug_examine_2(gdb_layer)

      return gdb_handle, gdb_layer

   # ***

   #
   def get_output_layer_names(self):
      g.assurt(self.import_lyr is not None)
      if self.target_lnames is None:
         self.tlyr_import = self.import_lyr.GetName()
         self.tlyr_reject = '%s (Rejected)' % (self.import_lyr.GetName(),)
         self.target_lnames = [self.tlyr_import, self.tlyr_reject,]
      return self.target_lnames

   # ***

   #
   def tlayer_add_feat(self, feat, context, action):
      g.assurt(action)
      new_feat = self.temp_layer_add(feat, self.tlyr_import, action, context)
      return new_feat

   #
   def tlayer_add_import(self, feat, context=None):
      return self.tlayer_add_feat(feat, context, self.defs.action_import)

   #
   def tlayer_add_fix_me(self, feat, context):
      ft = self.tlayer_add_feat(feat, context, self.defs.action_fix_me)
      # ft is None if the geometry is bad, otherwise it's set, but we always
      # send back None.
      return None

   #
   def tlayer_add_reject(self, feat, context):
      new_feat = self.temp_layer_add(feat, self.tlyr_reject,
                                     self.defs.action_reject, context)
      return new_feat

   # ***

   #
   def temp_layer_add(self, feat, lname, action, context):

      g.assurt((feat is not None) and lname and action)
      # Only FIXMEs can be added without a context.
      # MAYBE: Only Ignore has no context?

      new_feat = None
      geom = feat.GetGeometryRef()

      layer = self.target_layers_temp[lname]

      # Do some sanity checking. If the user types gibberish for _ACTION we
      # might get here.
      if (not ((action == self.defs.action_ignore)
               or (context)
               or (feat.GetField(self.defs.confln_context)))):
         log.error(
            'temp_layer_add: unexpected: no context, and action: %s / FID: %s'
            % (action, feat.GetFID(),))
         action = self.defs.action_fix_me
         new_feat = self.temp_layer_add_(feat, layer, action, context)
         g.assurt(new_feat is not None)
      # Or maybe the feature has no geometry. This can happen if you add a new
      # feature to a Shapefile accidentally that has no geometry (e.g., in
      # ArcGis, if you're looking at the attribute table and layer editing is
      # on, you can click at the bottom of the attribute list to create a new,
      # geometry-less feature.
      elif geom is None:
         log.error('temp_layer_add: no geom: FID: %s '% (feat.GetFID(),))
         action = self.defs.action_fix_me
         new_feat = self.temp_layer_add_(feat, layer, action, context,
                                         new_geom=None, geomless=True)
         g.assurt(new_feat is not None)
      # Before we import, we have to check the geometry.
      # NOTE: We preprocess features in import_init so if the geometry is bad,
      # we already know and are trying to add the feature as a FIXME. See the
      # fcn., shapefile_organize_feats_feat.
      elif geom.GetGeometryCount() > 1:
         # We always check geom before this fcn., so this should already be
         # marked FIXME.
         g.assurt(action == self.defs.action_fix_me)
         for geom_i in xrange(geom.GetGeometryCount()):
            single_geom = geom.GetGeometryRef(geom_i)
            new_feat = self.temp_layer_add_(feat, layer, action,
                                            context, new_geom=single_geom)
            g.assurt(new_feat is not None)
            self.stats['fixme_multi_geom_fin'] += 1
         # import_init has already added to self.stats['fixme_multi_geom_src']
      elif not geom.IsSimple():
         # Same as previous; preprocessing should have marked this 'FIXME'.
         g.assurt(action == self.defs.action_fix_me)
         log.error('Bad _NEW_ Feat: Not Simple: FID %d' % (feat.GetFID(),))
         log.verbose('The Bad Geom: %s' % (geom.ExportToWkt(),))
         new_feat = self.temp_layer_add_(feat, layer, action, context)
         g.assurt(new_feat is not None)
         # import_init already +1'ed self.stats['fixme_bad_geom_unsimple'].
      # If OGR says IsRing and we save to Cyclopath, PostGIS (EXPLAIN: version)
      # will crash when we call ST_SimplifyPreserveTopology.
      elif geom.IsRing():
         # Like I've said twice already, preprocessing already saw this.
         g.assurt(action == self.defs.action_fix_me)
         log.error('Bad _NEW_ Feat:    Is Ring: FID %d' % (feat.GetFID(),))
         log.verbose('The Bad Geom: %s' % (geom.ExportToWkt(),))
         new_feat = self.temp_layer_add_(feat, layer, action, context)
         g.assurt(new_feat is not None)
         # import_init already +1'ed self.stats['fixme_bad_geom_ring'].

      if new_feat is None:
         # NOTE: Caller is responsible for updating one of the stats, like we'd
         #       have done if this was a bad geometry.
         new_feat = self.temp_layer_add_(feat, layer, action, context)
         log.verbose4('temp_layer_add: FID: %d' % (new_feat.GetFID(),))
      else:
         # Return None so the caller knows not to keep processing the feat.
         # Also tells caller to not update any stats, since we've already done
         # it.
         new_feat = None

      return new_feat

   #
   def temp_layer_add_(self, feat, layer, action, context, new_geom=None,
                                                           geomless=False):

      # The feat should be an intermediate feature: read from the source
      # shapefile, fully hydrated, and currently a part of the SourceFeat
      # layer/shapefile.

      layer_defn = layer.GetLayerDefn()
      target_feat = ogr.Feature(layer_defn)

      log.verbose('temp_layer_add_: layer: %s / feat: %s'
                  % (layer.GetName(), feat,))
      g.assurt(target_feat.GetFID() == -1)

      # FIXME: del
      ## We can use forgiving because the intermediate shapefile and the target
      ## shapefile should have the same fields defined.
      #if layer.GetName() == 'TargetFeat':
      #   forgiving = False
      #else:
      #   forgiving = True
      #
      # We cannot use forgiving unless the source feat layer has the same
      # fields as the target feat layer, which we cannot guarantee here, since
      # the source layer is from the user.
      forgiving = False

# FIXME: Make sure _DELETE, _REVERT and _CONFLATED are maintained for
# all but features that were 'Import'ed... but how do you tell?

      # The source layer is the Shapefile we're import from, and the
      # target_feat here is the temporary layer. We use forgiving because
      # we have fields in the tmp layer that probably don't exist in the
      # source layer.
      ogr_err = target_feat.SetFrom(feat, forgiving=True)
      # NOTE: I search the ogr source in Python and it doesn't seem to have
      # constants for errors. SetFrom returns 6, a/k/a OGRERR_FAILURE, if the
      # target layer doesn't have all the fields as the source layer.
# FIXME: Verify last comment.
      g.assurt(not ogr_err)
      g.assurt(target_feat.GetFID() == -1)

      if new_geom is not None:
         target_feat.SetGeometry(new_geom)

      # The source shapefile features all specify geometries.
      if target_feat.GetGeometryRef() is not None:
         g.assurt(not geomless) # Not necessary, just how it's wired.
         if action != self.defs.action_fix_me: # I.e., 'FIXME'
            g.assurt(target_feat.GetGeometryRef().IsSimple())
            g.assurt(not target_feat.GetGeometryRef().IsRing())
         g.assurt((target_feat.GetGeometryRef().GetZ() == -9999.0)
                  or (target_feat.GetGeometryRef().GetZ() == 0.0))
         # Cyclopath fcns. don't know/care about the z-value.
         target_feat.GetGeometryRef().FlattenTo2D()
      else:
         # This happens when the feature is not a _CCP control feature and is
         # not a fixme _ACTION and is being added to the fixme layer in the
         # result shapefile. This can happen if the user creates features in
         # their GIS app but doesn't assign any geometry.
         g.assurt(geomless) # Not necessary, just how it's wired.

      if context is not None:
         target_feat.SetField(self.defs.confln_context, context)

      # NOTE: SetFrom gets all source fields, so no need to go through
      #       ta_def in self.defs.attrs_metadata.

      # Store the feature in the temporary shapefile.
      ogr_err = layer.CreateFeature(target_feat)
      g.assurt(not ogr_err)
      log.verbose('target_feat/CreateFeat: FID: %d' % (target_feat.GetFID(),))
      ##target_feat.Destoy()

      # NOTE to the callees: If you call SetField or SetGeometry on this
      #      returned feature, you have to call SetFeature for the changes to
      #      stick.
      return target_feat

   # ***

   #
   def target_layers_save(self):

      if self.debug.debug_skip_saves:
         return

      # Count the total number of features first, including those from each of
      # the sources.
      tot_feats = 0
      for lname in self.target_lnames:
         self.target_layers_temp[lname].ResetReading()
         tot_feats += Shapefile_Wrapper.ogr_layer_feature_count(
                                 self.target_layers_temp[lname])

      prog_log = self.progr_get(log_freq=1000, loop_max=tot_feats)
      # NOTE: Not all procedures take a while; saving Shapefiles is fast.
      # DEVS: Un-comment to skip short-circuit. See also similar uncommenting
      #       in target_layers_save_.
      #prog_log.debug_break_loops = False
      #prog_log.debug_break_loop_cnt = 1

      self.target_layers_save_(prog_log)

   #
   def target_layers_save_(self, prog_log):

      log.info('Saving target shapefiles...')

      # The OGR C-library has a DeleteField fcn but it's not supported by the
      # Python library. The work-around is to create a new shapefile and
      # exclude the fields you don't want.

      for lname in self.target_lnames:

         log.debug(' .. working on layer: %s' % (lname,))

         # The "inner" progress logger is just used for debugging, so make sure
         # it doesn't invoke our callback. Also, set the freq accordingly, so
         # we preempt with enough cycles left for all the shapefiles to be
         # examined.
         prog_lite = Debug_Progress_Logger(copy_this=self.debug.debug_prog_log)
         prog_lite.log_listen = None
         prog_lite.log_silently = True
         prog_lite.log_freq = prog_log.log_freq / len(self.target_lnames)
         # DEVS: Un-comment to not short-circuit, since saving Shapefs is fast.
         #prog_lite.debug_break_loops = False
         #prog_lite.debug_break_loop_cnt = 1

         layer_defn = self.target_layers_final[lname].GetLayerDefn()

         self.target_layers_temp[lname].ResetReading()
         for tmp_feat in self.target_layers_temp[lname]:

            # FIXME: tmp_feat.Destroy()?

            # Make a copy of the feat.
            final_feat = ogr.Feature(layer_defn)
            # The tmp feat has all the same fields and more fields than the
            # final feat, so forgiving can be False, right? Wrong: I think
            # forgiving=False enforces a two-way street: exact match of fields,
            # and not just that one is a subset of the other.
            ogr_err = final_feat.SetFrom(tmp_feat, forgiving=True)
            #ogr_err = final_feat.SetFrom(tmp_feat, forgiving=False)
            g.assurt(not ogr_err)
            g.assurt(final_feat.GetFID() == -1)
            # MAYBE/FIXME: 2013.04.25: This wasn't happening earlier, was it?
            #              Getting: 'Bad Geom (Empty)'.
            if final_feat.GetGeometryRef() is not None:
               g.assurt(final_feat.GetGeometryRef().GetZ() == 0.0)
               final_feat.GetGeometryRef().FlattenTo2D()
            else:
               log.warning(
                  'target_layers_save_: no geom?: FID: %s / _CONTEXT: %s'
                  % (final_feat.GetFID(),
                     final_feat.GetFieldAsString('_CONTEXT'),))
            # FIXME: 2013.04ish: Verify that the features with edited geom but
            #        no geom_okay flag in the new bikeways shapefile are
            #        handled. E.g.,
            #            if final_feat.GetField('CCP_ID') in (1019246,1358797):
            #               import pdb;pdb.set_trace()
            ogr_err = self.target_layers_final[lname].CreateFeature(final_feat)
            g.assurt(not ogr_err)

            # Note that, since we're doubly-looped, we just care about the
            # "inner" progress logger. Since we set its log_freq proportional
            # to the "outer" logger, we shouldn't have to check the outer
            # logger to know when we need to break.
            prog_log.loops_inc()
            if prog_lite.loops_inc():
               break

   #
   def target_layers_cleanup(self):

      if self.debug.debug_skip_saves:
         return

      log.info('Removing temporary shapefiles...')

      # NOTE: (a) OGR returns layers by name (b) layers do not know
      # their data source index and (c) you can only remove layers by
      # index. Ahoy. ;)
      # REMEMBER: Go backwards, since DeleteLayer, ya know, deletes
      #           layers.
      layer_nums = xrange(self.outp_datasrc.GetLayerCount())
      # The set() type does not support, i.e., layer_nums.reverse(), but it
      # does define the __reversed__() fcn.
      for layer_i in reversed(layer_nums):
         layer = self.outp_datasrc.GetLayer(layer_i)
         lname = layer.GetName()
         if lname in self.target_layers_temp_names:
            log.debug(' .. deleting layer: %s' % (lname,))
            g.assurt(lname.endswith('_tmp'))
            self.outp_datasrc.DeleteLayer(layer_i)
            # Don't forget to whack the layer and name from our own lookups.
            # This throws KeyError if lname doesn't exist but lname does.
            self.target_layers_temp_names.remove(lname)
            # MAGIC_NUMBER: The layer name ends in '_tmp' (4 characters) but
            # we've keyed it off the non-_tmp-named layer, so remove the
            # suffix.
            lname = lname[:-4]
            g.assurt(lname in self.target_layers_temp.keys())
            del self.target_layers_temp[lname]
         # else, the layer is in self.target_layers_final.

   # ***

# ***

if (__name__ == '__main__'):
   pass

