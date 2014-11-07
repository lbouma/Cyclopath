# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys
import time
import traceback

import conf
import g

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from gwis.query_overlord import Query_Overlord
from item.feat import branch
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_.log_progger import Debug_Progress_Logger

from merge.ccp_merge_conf import Ccp_Merge_Conf
from merge.ccp_merge_debug import Ccp_Merge_Conf_Base_Debug
from merge.ccp_merge_error import Ccp_Merge_Error
from utils.work_item_job import Work_Item_Job

log = g.log.getLogger('ccp_mrg_base')

from util_ import logging2
log.setLevel(logging2.VERBOSE)

__all__ = ('Ccp_Merge_Base',)

class Ccp_Merge_Base(object):

   __slots__ = (
      #
      'mjob',
      'defs',
      #
      'debug',
      #
      'substage_lookup',
      'stage_num_base',
      'stage_num_times',
      #
      'target_lnames',
      #
      'spf_conf',
      #
      'qb_src',
      'qb_cur',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):

      self.mjob = mjob
      self.defs = branch_defs

      #if self.defs is not None:
      #   self.defs.set_controller(self)
      g.assurt(mjob.handler is None)
      mjob.handler = self

      log.debug('__init__: set mjob.handler: %s / mjob: %s' 
                % (str(self), str(mjob),))

      # Setup the dev-configurable debug settings.
      self.debug = Ccp_Merge_Conf_Base_Debug()
      # Tell the log_prog our callback.
      self.debug.debug_prog_log.log_listen = self.mjob.prog_update
      # We don't attach a prog_log payload, so leave blank.
      self.debug.debug_prog_log.user_data = None

      # If this job has substages, it'll list them here.
      self.substage_lookup = None
      # These'll be set by the derived class in make_substage_lookup.
      self.stage_num_base = None
      self.stage_num_times = None
      #
      self.make_substage_lookup()

      # This is redundant (it's called for every first substage stage) but
      # it'll help you debug before the code runs for a while.
      self.reinit()

   # ***

   #
   def reinit(self):
      self.spf_conf = Ccp_Merge_Conf()
      self.qb_src = None
      self.qb_cur = None
      #
      self.target_lnames = None

   # ***

   #
   def get_output_layer_names(self):
      g.assurt(False)

   # ***

   #
   def cur_substage_num(self):

      # Old comment?:
      # The stage number is 1-based, so, e.g., if the uber-stage-num is 3, 
      # which is also the starting stage number of the substages, then that's 
      # not the 0th substage but really the 1st substage, so we have to adjust
      # one side of this equality by 1.

      if self.mjob.wtem.latest_step.status_text == 'working':
         # We haven't called stage_initialize so the stage_num lags by one.
         cur_stage_num = self.mjob.wtem.latest_step.stage_num + 1
      else:
         g.assurt(self.mjob.wtem.latest_step.status_text == 'resuming')
         # BUG nnnn: Implement resuming to accompany suspended.
         # BUG nnnn: If we're resuming, the stage_num is really the stage num
         # (it doesn't lag by one, like in the if). Except we still want to run
         # any init routines, which may be the first stage(s) (so we should 
         # split substage_lookup into two: init and therest).
         g.assurt(False) # BUG nnnn
         cur_stage_num = self.mjob.wtem.latest_step.stage_num

      substage_num = (cur_stage_num 
                      - self.stage_num_base 
                      - (len(self.substage_lookup) * self.stage_num_times))

      return substage_num

   #
   def is_last_stage(self):
      return (len(self.substage_lookup) == self.cur_substage_num())

   #
   def make_substage_lookup(self, stage_num_base, substage_lookup):
      # The derived class calls this to give us its substage lookup and to 
      # tell us which uber-stage is our first stage.
      self.stage_num_times = 0
      self.stage_num_base = stage_num_base
      self.substage_lookup = substage_lookup

   #
   def substage_fcn_go(self):

      # Find the cur stage number, then translate into an index into the
      # substage lookup.

      substage_num = self.cur_substage_num()
      log.info('substage_fcn_go: cur_stage: %d / substage: %d' 
               # We haven't called stage_initialize so stage_num lags by one.
               % (self.mjob.wtem.latest_step.stage_num + 1, 
                  substage_num,))
      g.assurt((substage_num >= 0) 
               and (substage_num < len(self.substage_lookup)))

      # NOTE: We haven't called stage_initialize so substage_num is actually 1
      # less than it really is, but that's good, since it's a 1-based value and
      # the list is a 0-based lookup.
      substage_fcn = self.substage_lookup[substage_num]
      substage_fcn()

   # ***

   #
   def do_merge_io(self, merge_io_handler):

      maybe_commit = False

      failure_reason = None
      failure_do_warn = True

      last_stage = False

      try:

         log.verbose('do_merge_io: calling merge_io_handler')

         # It's the first stage if the stage num is 0 (since the substage
         # increments it to its usual 1-based self in merge_io_handler).
         if self.cur_substage_num() == 0:
            self.reinit()

         # This is called once for each substage fcn. and then calls whichever
         # one is the processor of this substage num.
         merge_io_handler() # the import or export fcn.

         # Only (maybe) commit if this is the last step, or if we're being
         # suspended; if we're being canceled, we just rollback.
         if self.is_last_stage():
            last_stage = True
            if self.debug.debug_skip_commit:
               log.warning('do_merge_io: skipping commit')
            else:
               maybe_commit = True

      except Ccp_Merge_Error, e:

         # This is an import-user error (something in the import config or
         # shapefiles).

         # Note: DeprecationWarning: BaseException.message has been deprecated
         #                           as of Python 2.6.
         # [lb] didn't know that...
         # Ancient history: failure_reason = e.message
         failure_reason = str(e)

         log.debug('do_merge_io: Ccp_Merge_Error: message: %s' % (str(e),))
         log.verbose('do_merge_io: Ccp_Merge_Error: stack:\n%s' 
                     % (traceback.format_exc(),))

      except Work_Item_Job.Ccp_Preempted, e:

         failure_reason = 'this failure intentionally left blank'

         raise # Keep going up; job is already marked failed.

      except GWIS_Nothing_Found, e:

         failure_reason = str(e)

         # This error is legit: it means someone exported using
         # filter_by_region but there was no matching city, county, township,
         # etc. The user will otherwise realize the problem, and they may not
         # even care, in the case of the MetC Bikeways shapefile exports.

         failure_do_warn = False

         log.info('do_merge_io: GWIS_Nothing_Found: %s' % (str(e),))

      except AssertionError, e:

         # Cyclopath uses a derived class, g.Ccp_Assert -- called via g.assurt
         # -- that sets e.message to the stack trace. Otherwise, AssertionError
         # just sets the line number of the assert. Devs should use g.assurt.

         # FIXME: DeprecationWarning:
         #        BaseException.message has been deprecated as of Python 2.6

         failure_reason = str(e)

         log.error('do_merge_io: AssertionError:\n%s' % (str(e),))

      except Exception, e:

         # This is a developer error (something in the code) and not an assurt.
         #
         # NOTE: The stack trace here only shows this fcn. and what we've
         # called. It doesn't show the frames above us, i.e.,
         # merge_job_import.py and metc_bikeways_defs.py.

         # FIXME: Which log message should we emit?
         #        This one:
         err_s, detail, trbk = sys.exc_info()
         log.warning('do_merge_io: failed:')
         log.warning('%s' % (err_s,))
         log.warning('%s\n%s' % (detail, ''.join(traceback.format_tb(trbk)),))
         #        or this one?:
         err_s = ('do_merge_io: Exception: %s\n%s' 
                  % (str(e), traceback.format_exc(),))
         failure_reason = err_s
         log.error(err_s)

         # DEVS: There's no point to break hear since we've already lost the
         #       offending call stack.
         # No point: g.assurt(False) / pdb.set_trace().
         #
         # WANTED: When the other thread dies, can we have it do like winpdb or
         #         rpdb and start listening as a remote debug session? Or is
         #         there another way to debug it?

      okay = True
      if failure_reason is not None:
         self.mjob.job_mark_failed(failure_reason, warn=failure_do_warn)
         # The last statement raised Work_Item_Job.Ccp_Preempted and will
         # trigger a call to self.substage_cleanup().

      if last_stage:
         if self.qb_cur is None:
            # This is an import, i.e., 
            #    g.assurt(self.shpf_class == 'incapacitated')
            maybe_commit = False
         else:
            # Spew the stats we've been collecting.
            self.spats_stew()
         # Do any cleanup, like saving and closing Shapefiles.
         self.substage_cleanup(maybe_commit)
         # Fiddle with the base offset, in case we're called all over again.
         self.stage_num_times += 1
         # Vacuum the database if we've committed.
         # FIXME: Should we always vacuum? If takes a while, right? So maybe we
         # should trigger a vacuum after the job completes, so we don't stall
         # the user...
         if maybe_commit:
            full_vacuum = True
            # Note: This only vacuums on import; export does nothing.
# FIXME: Make this optional:
# ALSO: Do at end of importing all shapefiles, instead of after each one?
            skip_vacuum = True
            if not skip_vacuum:
               self.db_vacuum(full_vacuum)
         # Tell the developer if they're still just testing.
         if self.debug.debugging_enabled:
            log.error("REMEMBER: This was all just a dream.")
            log.error("          Don't forget to disable your debug switches.")

      return okay

   #
   def job_cleanup(self):
      # This is called when the uber-controller is at its last stage. We
      # clean up qbs and dbs during the last substage stage, via 
      # substage_cleanup, but some derived classes also do some cleanup at the
      # very, very end.
      pass

   #
   def substage_cleanup(self, maybe_commit):

      log.debug('substage_cleanup: Closing query_builders and databases.')

      self.release_qbs()

      log.debug('substage_cleanup: Closing source shapefile(s).')

      self.geodatabases_close()

   # *** Database fcns.

   #
   def release_qbs(self):

      if self.qb_src is not None:
         log.debug('release_qbs: closing qb_src')
         if self.qb_src.db is not None:
            self.qb_src.db.close()
            self.qb_src.db = None
         self.qb_src = None

      if self.qb_cur is not None:
         log.debug('release_qbs: closing qb_cur')
         if self.qb_cur.db is not None:
            self.qb_cur.db.close()
            self.qb_cur.db = None
         self.qb_cur = None

   #
   def db_vacuum(self, full_vacuum=False):
      pass # Import actually vacuums; export doesn't override this.

   # ***

   #
   def geodatabases_close(self):
      g.assurt(False) # abstract

   #
   def progr_get(self, log_freq, loop_max=None):
      prog_log = Debug_Progress_Logger(copy_this=self.debug.debug_prog_log)
      prog_log.log_freq = log_freq
      prog_log.loop_max = loop_max
      return prog_log

   #
   def spats_stew(self):
      g.assurt(False) # abstract

   # ***

   #
   def setup_qbs(self, all_errs):
      self.setup_qb_src(all_errs)
      self.setup_qb_cur(all_errs)

   #
   def setup_qb_src(self, all_errs):

      qb_src = None

      username = self.mjob.wtem.created_by

      # The source qb is just for reading...
      db = db_glue.new()
      # ... but we'll be making temporary tables of stack IDs, so start a
      # transaction.
      db.transaction_begin_rw()

      # The byways in the conflated were not marked deleted when they were
      # exported for conflation, so we don't need to look for deleted.
      # NOTE: The original MetC import script used based rev off
      #       self.target_branch.last_merge_rid rather than what's in the
      #       config file.
      g.assurt(self.spf_conf.revision_id)
      revision_id = self.spf_conf.revision_id
      rev = revision.Historic(revision_id, allow_deleted=False)

      # Make the branch_hier.
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db, 
                           self.mjob.wtem.branch_id, branch_hier_rev=rev)

      # Put it all together.
      if branch_id is None:
         all_errs.append(
            'setup_qb_src: not a branch: %s at %s' 
            % (self.mjob.wtem.branch_id, str(rev),))
         # Don't forget to close. Not too big a deal, but oddly, if we don't,
         # the next attempt by this thread to get the db will result in the
         # same DB() object being created and the same self.conn returned, 
         # and then db_glue complains that it's got that self and conn in
         # conn_lookup.
         db.close()
         db = None
      else:
         g.assurt(branch_hier)
         qb_src = Item_Query_Builder(db, username, branch_hier, rev)

         # It's nice to have both the raw, opaque hexadecimal geometry as well
         # as the WKT geometry, since not all APIs are that flexible, and also 
         # because it's easier to work with WKT in Python and OSGeo (and also
         # because [lb] hasn't seen an OGR fcn. to convert raw PostGIS geom, 
         # but he's probably not looking hard enough).
         qb_src.filters.skip_geometry_raw = False
         qb_src.filters.skip_geometry_svg = True
         qb_src.filters.skip_geometry_wkt = False

         qb_src.item_mgr = Item_Manager()
# FIXME: Is this right? What about tgraph?
         qb_src.item_mgr.load_cache_attachments(qb_src)

         Query_Overlord.finalize_query(qb_src)

         # Check that user has viewer access on the source branch.
         source_branch = self.verify_branch_access(qb_src, 
                              Access_Level.viewer, all_errs)
         # NOTE: The job itself is already access-controlled, so generally the 
         # user has arbiter access to the branch at the Current revision.

      self.qb_src = qb_src

   #
   def setup_qb_cur(self, all_errs, min_acl=Access_Level.viewer):

      # For both import and export, qb_src is used to retrieve items from the
      # database, and qb_cur is used to check the user's group accesses and
      # maybe to search for regions if a restrictive bbox is being imposed.
      # But qb_cur is also used during import to save changes to the database;
      # qb_cur is not used during export to save anything to the database.
      #
      # NOTE: On import, we row-lock on the grac tables, group_membership 
      # and new_item_policy. We also row-lock the destination branch.
      # So other operations might block while this code runs.
      # CONFIRM: We don't lock anything on export, right?

      qb_cur = None

      username = self.mjob.wtem.created_by

      db = db_glue.new()

      rev = revision.Current(allow_deleted=False)
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db, 
                     self.mjob.wtem.branch_id, branch_hier_rev=rev)

      if branch_id is None:
         # EXPLAIN: How come we don't raise here, like we do in the else?
         #          Or, why doesn't the else block use all_errs?
         #          See: raise_error_on_branch.
         #          And if you look at export_cyclop.substage_initialize,
         #          you'll see that it assurts not all_errs, so I guess
         #          it expects us to raise.
         all_errs.append(
            'setup_qb_cur: not a branch: %s at %s' 
            % (self.mjob.wtem.branch_id, str(rev),))
      else:

         g.assurt(branch_hier)
         g.assurt(branch_id == branch_hier[0][0])

         raise_error_on_branch = False

         if not self.spf_conf.branch_name:
            # This happens on export, since export_cyclop.substage_initialize
            # only sets branch_id when setting up the qbs. This is because it
            # uses the merge_job's branch_id, and since merge_job is just an
            # item_versioned item, all it has is its branch_id, as items do
            # not also store the branch name.
            self.spf_conf.branch_name = branch_hier[0][2]
         elif self.spf_conf.branch_name != branch_hier[0][2]:
            # The branch name in the shapefile should match.
            log.error('setup_qb_cur: branch_name mismatch: %s / %s'
                      % (self.spf_conf.branch_name, branch_hier[0][2],))
            raise_error_on_branch = True
         # else, the branch_name in the conf matches the one we loaded by ID.
         #
         if self.spf_conf.branch_id != branch_id:
            # But the branch ID we can tolerate being wrong.
            log.warning('setup_qb_cur: unexpected spf_conf.branch_id: %s'
                        % (self.spf_conf.branch_id,))
            # For the Metc Bikeways shapefile, this just means [lb] hasn't
            # update the branch ID attribute in the shapefile...
            g.assurt(self.spf_conf.branch_name)
            (try_branch_id, try_branch_hier) = branch.Many.branch_id_resolve(
                           db, self.spf_conf.branch_name, branch_hier_rev=rev)
            if try_branch_id == branch_id:
               log.warning('setup_qb_cur: ok: overriding branch_id: %s'
                           % (branch_id,))
               self.spf_conf.branch_id = branch_id
            else:
               log.error('setup_qb_cur: try_branch_id != branch_id: %s != %s'
                         % (try_branch_id, branch_id,))
               raise_error_on_branch = True

         if raise_error_on_branch:
            if conf.break_on_assurt:
               import pdb;pdb.set_trace()
            raise GWIS_Error(
               'Shapefile branch ID and name do not match job details: '
               'work_item: %s/%s | shapefile: %s/%s'
               % (branch_hier[0][2],
                  branch_hier[0][0],
                  self.spf_conf.branch_name,
                  self.spf_conf.branch_id,))

         qb_cur = Item_Query_Builder(db, username, branch_hier, rev)

         # Load both the raw geometry and the WKT geometry; we need to be
         # flexible.
         qb_cur.filters.skip_geometry_raw = False
         qb_cur.filters.skip_geometry_svg = True
         qb_cur.filters.skip_geometry_wkt = False

         # To save things, we need to set the group ID explicitly.
         self.user_group_id = User.private_group_id(qb_cur.db, username)
         qb_cur.user_group_id = self.user_group_id

         qb_cur.item_mgr = Item_Manager()
         # Load the attachment cache now. On import, if we create new
         # attributes (see metc_bikeways_defs.py), we'll keep it updated.
         qb_cur.item_mgr.load_cache_attachments(qb_cur)

         Query_Overlord.finalize_query(qb_cur)

         # FIXME: This comment. I like it. But it's not true... yet.
         #  Getting row lock in branches_prepare. So don't table lock.
         #
         # Start the transaction, since the grac_mgr does some row locking.
         # We'll keep the rows locked until we've verified permissions.
      # FIXME: Verify you rollback and start a new 'revision' lock...
      #        or maybe just start a new 'revision' lock? or can you 
      #        write to a Shapfile first and zip through the Shapefile 
      #        to save quickly and not hold the lock so long?
         # BUG nnnn: Investigate using a row-level branch lock; for now, 
         #           just lock rev.
         qb_cur.db.transaction_begin_rw()

         qb_cur.grac_mgr = Grac_Manager()
         load_grp_mmbrshps = True
         qb_cur.grac_mgr.prepare_mgr('user', qb_cur, load_grp_mmbrshps)

         # FIXME: Does qb_src need grac_mgr?
         #self.qb_src.grac_mgr = qb_cur.grac_mgr

         # Check user's minimum access level.
         target_branch = self.verify_branch_access(qb_cur, min_acl, all_errs)
         g.assurt(target_branch.stack_id == self.spf_conf.branch_id)
         if (self.spf_conf.branch_name
             and (self.spf_conf.branch_name != qb_cur.branch_hier[0][2])):
            log.warning('Unexpected spf_conf.branch_name: %s'
                        % (self.spf_conf.branch_name,))
         self.spf_conf.branch_name = qb_cur.branch_hier[0][2]

      self.qb_cur = qb_cur

      log.debug('setup_qb_cur: spf_conf: %s' % (str(self.spf_conf),))

   # ***

   #
   def verify_branch_access(self, qb, acl_id, all_errs):
      # This is really similar to:
      #   branch.Many.branch_enforce_permissions(qb, min_access)
      the_branch = None
      # Check the user's permission.
      branches = branch.Many()
      # Not using self.mjob.wtem.branch_id; usually == qb.branch_hier[0][0]
      # unless branch does not exist at qb's revision.
      branches.search_by_stack_id(qb.branch_hier[0][0], qb)
      # EXPLAIN: What about checking permissions on parent branches?
      if branches:
         g.assurt(len(branches) == 1)
         the_branch = branches[0]
         if not Access_Level.is_same_or_more_privileged(
                     the_branch.access_level_id, acl_id):
            # Bad. The user does not have access.
            the_branch = None
      if the_branch is None:
         all_errs.append(
            'verify_branch_access: not a branch or access denied: %s' 
            % (branch_,))
      return the_branch

   # ***

   #
   def ccp_conf_create_feats(self):
      # target_layers_temp or target_layers_final?
      for lname, layer in self.target_layers_final.iteritems():
         log.debug('ccp_conf_create_feats: layer: %s' % (lname,))
         self.spf_conf.record_as_feats(self, layer)

   # ***

# ***

if (__name__ == '__main__'):
   pass

