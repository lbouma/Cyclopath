# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import copy
import re
import time

import conf
import g

from grax.access_level import Access_Level
from grax.user import User
from gwis.query_base import Query_Base
from gwis.exception.gwis_error import GWIS_Error
from item.util.item_type import Item_Type
from util_ import misc

log = g.log.getLogger('revision')

# ***

class Revision(object):

   # Regex to decipher revision GML, e.g., rev=, rev=1, rev=2:3, or rev=4-5.
   GML_REV_REGEX = re.compile(r'^(\d+)?(:|-)?(\d+)?$')

   # True if we're in charge of the cp_maint_lock file.
   own_cp_maint_lock = False

   # *** Constructor

   def __init__(self):
      pass

   # ***

   # Factory method
   @staticmethod
   def revision_object_get(rev):
      '''
      Create and initialize an appropriate revision_query object based on
      key/value pairs in dict d. Raises GWIS_Error if there is a problem.
      '''
      rev_obj = None
      try:
         log.verbose('rev: %s' % rev)
         m = Revision.GML_REV_REGEX.match(rev)
         if (m.group(1) is None):
            # If rev is '' or None, assume Current revision.
            # NOTE: This also happens to some malformed input, e.g., "rev=:3"
            rev_obj = Current()
         elif (m.group(2) is None) or (m.group(3) is None):
            # One number is specified (e.g., "rev=4" or "rev=3:", so use
            # historic revision. Note that we don't check that the revision
            # actually exists.
            rev_obj = Historic(int(m.group(1)))
         elif (m.group(2) == ':'):
            # Both numbers are specified, separated by a colon, so a diff.
            rev_obj = Diff(int(m.group(1)), int(m.group(3)))
         elif (m.group(2) == '-'):
            # Both numbers are specified, separated by a dash, so an updated.
            rev_obj = Updated(int(m.group(1)), int(m.group(3)))
         else:
            g.assurt(False) # unreachable code
      except AttributeError, e:
         raise GWIS_Error("Parse error: invalid revision %s" % (rev))
      return rev_obj

   # *** Revision table helper methods

   #
   @staticmethod
   def revision_create(db):
      '''Create a new revision and return its ID.'''
      return db.sequence_get_next('revision_id_seq')

   #
   @staticmethod
   def revision_peek(db):
      '''Peek at the next revision number.'''
      return db.sequence_peek_next('revision_id_seq')

   #
   @staticmethod
   def revision_claim(db, rid):
      g.assurt(rid)
      next_rev_id = Revision.revision_peek(db)
      g.assurt(next_rev_id == rid)
      db.sequence_set_value('revision_id_seq', rid)

   ##
   #@staticmethod
   #def revision_last():
   #   '''Returns the last newly created revision ID.
   #      Not guaranteed to be the current revision ID, though, since it's just
   #      the last newly created revision ID by whatever script called us
   #      with that db handle they gave us.'''
   #   return self.sql("SELECT currval('%s');" % (seq_name))[0]['currval']
   #   Revision.rev_last = db.sequence_get_next('revision_id_seq')
   #   return Revision.rev_last

   #
   @staticmethod
   def revision_max(db):
      # See also scripts/util/bash_bash.sh for SQL for finding the latest
      # revision ID and timestamp for a branch. That is, this function gets
      # the system's latest revision ID, not just a branch's.
      return int(db.sql("SELECT MAX(id) FROM revision WHERE id != %s"
                        % (conf.rid_inf,))[0]['max'])

   #
   @staticmethod
   def revision_save(qb,
                     rid,
                     branch_hier,
                     host,
                     username,
                     comment,
                     group_ids,
                     activate_alerts=False,
                     processed_items=None,
                     reverted_revs=None,
                     skip_geometry_calc=False,
                     skip_item_alerts=False):
      '''
      Create a new revision row.
      '''

      ## Username should be set for logged-in users or be blank for anonymous.
      ##g.assurt(username is not None)
      # Username should always be set, either to logged-in user or anonymous.
      g.assurt(username)

      # We could probably figure out the list of group IDs by querying the
      # group_item_access table, but for now, we force the caller to pass in
      # a list of group IDs. (FIXME: See below. Probably get rid of this parm.)
      g.assurt(len(group_ids) > 0)

      visible_count_0 = 0
      #
      reverted_count_0 = 0

      # is_revertable is new to Ccpv2 and should always be True for user
      # actions (for scripts a developer might run when updating Cyclopath,
      # then it might be False).
      is_revertable = True

      # Here, we simply verify our logic -- look in the group_item_access table
      # and see which items had activity at this revision (i.e., whose
      # valid_start_rid or valid_until_rid changed is set to this revision).
      # Note that some revisions are created for non-item changes, like
      # creating or updating users, groups or group memberships. As such, what
      # we find in the group_item_access table is merely a subset of ....
      # Get a list of group IDs affected by this revision.
      gia_rows = qb.db.sql(
         """
         SELECT DISTINCT (group_id) FROM group_item_access WHERE %s
         """ % (Revision.sql_revision_activity(rid, '', ''),))
      gia_gids = set([x['group_id'] for x in gia_rows])
      grp_rows = qb.db.sql(
         """
         SELECT DISTINCT (stack_id) FROM group_ WHERE %s
         """ % (Revision.sql_revision_activity(rid, '', ''),))
      grp_gids = set([x['stack_id'] for x in grp_rows])
      gmp_rows = qb.db.sql(
         """
         SELECT DISTINCT (group_id) FROM group_membership WHERE %s
         """ % (Revision.sql_revision_activity(rid, '', ''),))
      gmp_gids = set([x['group_id'] for x in gmp_rows])
      #nip_rows = qb.db.sql(
      #   """
      #   SELECT DISTINCT (group_id) FROM new_item_policy WHERE %s
      #   """ % (Revision.sql_revision_activity(rid, '', ''),))
      #nip_gids = set([x['group_id'] for x in nip_rows])
      nip_gids = set()
      dbg_gids = gia_gids.union(grp_gids.union(gmp_gids.union(nip_gids)))

      # We have the caller pass in the list of group IDs in group_ids, but
      # we only use that to double-check our maths.
      # The set of group IDs passed in may contain the user's private group ID.
      if dbg_gids:
         # Fixed: 2012.05.16: Firing on commit of new byway connected to two
         # existing byways, in the Metc branch [lb]. commit setup my private
         # gia and one for the group, but not one for the public, and byways
         # nodes' have automatic public gia records.
         g.assurt(set(group_ids).issubset(dbg_gids))
         g.assurt(((len(group_ids) - len(dbg_gids)) <= 1))
      # else, this is an item-less revision; the caller is just making a point.

      # Create one or more group_revision entries.
      for group_id in group_ids:
         group_insert_sql = (
            """
            INSERT INTO group_revision
              (group_id,
               revision_id,
               branch_id,
               visible_items,
               is_revertable)
              VALUES
              (%d, %d, %d, %d, %s)
            """ % (group_id,
                   rid,
                   branch_hier[0][0],
                   visible_count_0,
                   is_revertable))
         rows = qb.db.sql(group_insert_sql)

      # Figure out how long we've had the revision lock.
      msecs_holding_lock = None
      if qb.db.locked_on_time0:
         msecs_holding_lock = int((time.time() - qb.db.locked_on_time0)
                                  * 1000.0)

      # Create the revision entry.
      rows = qb.db.sql(
         """
         INSERT INTO revision
           (id,
            branch_id,
            timestamp,
            host,
            username,
            comment,
            alert_on_activity,
            is_revertable,
            reverted_count,
            msecs_holding_lock)
           VALUES
           (%s, %s, now(), %s, %s, %s, %s, %s, %s, %s)
         """, (rid,
               branch_hier[0][0],
               host,
               username,
               comment,
               activate_alerts,
               is_revertable,
               reverted_count_0,
               msecs_holding_lock,))

      # If we're being called by a script for a Very Big Operation, it might be
      # nice to skip the geometry calculation for now (but be sure to call it
      # later).

      if not skip_geometry_calc:

         # MAYBE: Do either of these operations take a while?
         #        Should we schedule a Mr. Do! operation for these ([lb] says
         #        please, oh, please, yes! and use multiprocessing.Process or
         #        Pool().
         time_0 = time.time()

         Revision.geosummary_update(qb.db, rid, branch_hier, group_ids)

         # 2014.09.16: Increasing complaint threshold from 2 to 4 secs.,, as it
         # appears this happens on saves with just one hundred items, e.g.,
         # Sep-16 11:07:15 INFO command_base # doit: cmd: commit: cnt: 123
         # Sep-16 11:07:46 WARN util_.misc   # time_complain: took 2.73 secs.
         # 2014.09.22: 4.9 secs. on one track being committed, at 7:38 PM.
         misc.time_complain('geosummary_update',
                            time_0,
                            threshold_s=10.0,
                            at_least_debug=True,
                            debug_threshold=0.5,
                            info_threshold=1.0)

      # 2013.10.18: Finally implementing the new item_event_alert table
      # to replace the thread watcher and revision watcher from CcpV1,
      # which emailed users from the HTTP commit request. In CcpV2, a
      # cron job handles the emails.
      # This calls Watcher_Watcher(qb).add_alerts(rid, processed_items),
      # since we cannot include the watcher classes.
      if not skip_item_alerts:
         
         qb.item_mgr.watcher_add_alerts(qb, rid, processed_items,
                                                 reverted_revs)

# BUG_FALL_2013:
      # FIXME: Statewide UI: For a revert revision, need to update revert rid's
      #                      reverted_count

   # ***

   # 2014.02.21: This is a new way to handle dirty map commits. Rather than
   # just get the 'revision' table lock and hold on to it indefinitely, we
   # grab it and then record when we grabbed it. This is so other users trying
   # to commit don't end up waiting a long time for a lock that they won't get.
   # The caller is simply a name for the trace log.
   # If indeliberate is True, it means the commit is not being called
   # deliberately from the command line (i.e., when updating the database
   # deliberately), but rather is being called indiscriminately by users
   # saving map changes. For deliberate callers, we want to complain if
   # the system isn't in maintenance mode.
   @staticmethod
   def revision_lock_dance(db, caller, indeliberate=False):

      # See if the system is in or will soon be in maintenance mode.
      (time_est, kval_vals,
         ) = Revision.revision_lock_check_maint_mode(db, indeliberate)

      if (not indeliberate) and (not time_est):
         # If time_est is set, it means we're in maintenance mode. Not set...
         # well, why isn't it set?
         log.warning(
            'rev_lock_dance: deliberate caller: not maint mode: %s'
            % (caller,))

      # Compute the lock_timeout: see if another commit is being processed
      # and has been chugging away for a while: we don't want to waste the
      # user's time and spin for, e.g., 60 seconds, waiting for the table
      # lock if we know there's a long commit already in progress.
      try:
         fstats = os.stat(conf.cp_maint_lock_path)
         secs_elapsed = time.time() - fstats.st_mtime
      except OSError:
         # No lock file... but we still might be competing for it.
         secs_elapsed = None
         lock_timeout = conf.gwis_commit_timeout
      #
      if secs_elapsed is not None:
         if secs_elapsed > (conf.gwis_commit_timeout - 5):
            lock_timeout = 5.0 # seconds
            # Maybe warn... 2014.02.14: Still tweaking the warn delay.
            if secs_elapsed > conf.cp_maint_warn_delay:
               log.warning(
                  'rev_lock_dance: async commit: lock says %.2f mins elpsd'
                  % (float(secs_elapsed) / 60.0,))
         else:
            # Wait as long as gwis_commit_timeout would normally wait,
            # minus how long the other process says it's been running.
            # This value is between 5 and conf.gwis_commit_timeout
            # seconds.
            lock_timeout = conf.gwis_commit_timeout - secs_elapsed

      log.debug('rev_lock_dance: locking revision table...')
      time_0 = time.time()
      try:
         db.transaction_lock_try(
            'revision', caller=caller, timeout=lock_timeout)
         # We got the lock!
         #
         # Out of curiosity... (change/remove this if it happens a lot):
         misc.time_complain('rev_lock_dance', time_0, 2.0)
         #
         # Check if maintenance mode is indicated (it shouldn't be).
         if time_est and not indeliberate:
            log.error('rev_lock_dance: got lock, but maint mode indicated')
         # Check if cp_maint_lock file exists (it shouldn't exist).
         if secs_elapsed is not None:
            # If we ended up waiting for the lock, we'll have seen the touch
            # file earlier, but the lock holder will have unlinked the touch
            # file since.
            # 2014.09.25: FIXME: Disable this block once confirmed. The nightly
            # cron runs two export jobs simultaneously, and both their commit's
            # call this fcn. for the work_item job. The second job comes
            # through this path, because it saw the lock file and waited to
            # lock the revision table while the first job completed its commit.
            try:
               fstats = os.stat(conf.cp_maint_lock_path)
               secs_elapsed = time.time() - fstats.st_mtime
               log.error('rev_lock_dance: locked: cp_maint_lock exists: %s old'
                         % (secs_elapsed,))
            except OSError:
               # No lock file. Bueno.
               pass
         # Touch the lock file; it's ours now, so tell other threads what's up.
         misc.file_touch(conf.cp_maint_lock_path)
         Revision.own_cp_maint_lock = True
         # Not necessary, since the file should only be temporary, and we'll
         # delete it: os.chmod(conf.cp_maint_lock_path, 664)
      except Exception, e:
         log.error('rev_lock_dance: cannot save: %s' % (str(e),))
         if time_est:
            raise GWIS_Error('%s %s %s %s'
               % ('Unable to save right now:',
                  'We are updating the database.',
                  'If you wait, you might be able to save later.',
                  time_est,
                  ))
         if secs_elapsed is not None:
            # We couldn't get the lock, and the touch file exists, so
            # we can safely assume another process is making a big save.
            raise GWIS_Error('%s %s'
               % ('Unable to save: Someone else is making a Big Save.',
                  'Please try again later!',))
         else:
            # We couldn't get the lock and there's no touch file -- this
            # should mean we were competing simultaneously against another
            # process. But it also means we timed out waiting for the lock,
            # meaning, we spun for a while and either the other process is
            # taking a long time to complete, or it finished and we lost
            # a competition with (an)other process(es) vying for the lock.
            log.warning('rev_lock_dance: was not locked; failed to lock')
            raise GWIS_Error('%s %s'
               % ('Unable to save: Someone else is making a Big Save.',
                  'Please try again soon!',))

      # If the code reaches here and returns, it indicates that the revision
      # table was successfully locked. If not, then we raised an Exception
      # already.

   #
   @staticmethod
   def revision_lock_check_maint_mode(db, indeliberate):

      time_est = ''

      kval_vals = db.table_to_dict(
         'key_value_pair', 'key', 'value',
         'cp_maint_beg', 'cp_maint_fin')

      cp_maint_beg = kval_vals['cp_maint_beg']
      cp_maint_fin = kval_vals['cp_maint_fin']

      if cp_maint_beg:
         # Get the datetime.timedelta object, which stores delta as
         # days/min/seconds/microseconds.
         beg_age = misc.timestamp_age(db, cp_maint_beg)
         if beg_age.days < 0:
            # This is a negative age, so we've finished warning the
            # users and now we're serious: no one is allowed to edit.
            # Well, except the script we're trying to run.
            if cp_maint_fin:
               fin_age = misc.timestamp_age(db, cp_maint_fin)
               if fin_age.days >= 0:
                  time_est = misc.timestamp_age_est(fin_age)
                  time_est = (
                     'We hope to be done updating within %s or so.'
                     % (time_est,))
               elif indeliberate:
                  log.warning('Hey, dev, your maint promise is broken!')
               # else, in maintenance mode, and this is a maintenance script.
            else:
               log.warning('Hey, dev, you have not set cp_maint_fin?')
            if not time_est:
               time_est = ('Unfortunately, we are unable to estimate '
                           + 'when updating will be complete.')
         else:
            # beg_age is positive, so we're still counting down to maint mode.
            if not indeliberate:
               log.warning('Hey, dev, you are a little early')
      else:
         # I.e., not cp_maint_beg.
         if not indeliberate:
            log.warning('Deliberate caller indicated but litemaint off')

      return (time_est, kval_vals,)

   #
   @staticmethod
   def revision_release_lock():
      if Revision.own_cp_maint_lock:
         log.debug('transaction_rollback: removing cp_maint_lock')
         if os.path.exists(conf.cp_maint_lock_path):
            os.unlink(conf.cp_maint_lock_path)
         else:
            log.error('transaction_rollback: where is the lock file?: %s'
                      % (conf.cp_maint_lock_path,))
         Revision.own_cp_maint_lock = False

   #
   @staticmethod
   def transaction_commit(db):
      Revision.revision_release_lock()
      db.transaction_commit()

   #
   @staticmethod
   def transaction_rollback(db):
      Revision.revision_release_lock()
      db.transaction_rollback()

   # *** Geosummary helpers

   # C.f. 201-apb-54-groups-functs__.sql
   @staticmethod
   def geosummary_update(db, rid, branch_hier, group_ids,
                             skip_geometry=False,
                             stats_bucket=None):

      log.verbose('geosummary_update: rid: %d' % (rid,))

      # First update the revision table, collecting all items in the
      # revision and not worrying about permissions.
      group_id = 0
      all_gf_count = Revision.geosummary_update_group(
                                       db, rid, branch_hier, group_id,
                                       skip_geometry, stats_bucket)

      # Next, update the group_revision table for every group that can
      # see the revision, collecting only those items each group can see.
      rows = db.sql(
         "SELECT group_id FROM group_revision WHERE revision_id = %d"
         % (rid,))
      group_ids = [x['group_id'] for x in rows]
      group_ids.sort()
      # The group ids we got from the caller, group_ids, is a query on
      # group_item_access, and the new list of group ids is a query on
      # group_revision. I [lb] guess we don't really need to do the second
      # query, but it's nice to sanity check yerself.
      g.assurt(group_ids == group_ids)
      # NOTE: Just counting stats per revision, and not per group_revision.
      stats_bucket = None
      for group_id in group_ids:
         grp_gf_count = Revision.geosummary_update_group(
                                          db, rid, branch_hier, group_id,
                                          skip_geometry, stats_bucket,
                                          all_gf_count)

      return all_gf_count

   #
   @staticmethod
   def geosummary_update_group(db, rid, branch_hier, group_id, skip_geometry,
                                   stats_bucket, all_gf_count=None):

      # 2014.04.21: BUG nnnn: I [lb] saved a private region and the edit
      #             shows up in the recent changes list. However, I
      #             cannot reproduce the problem.
      #             EXPLAIN: What's the ID of the revision in question?
      #             The public group ID is 2500679... DEVs: enable this
      #             and save a private region to try testing this...
      #if group_id == 2500679:
      #   conf.break_here('ccpv3')

      log.verbose('geosum_upd_grp: r %d / grp_id: %d / skp_geo: %s'
                  % (rid, group_id, skip_geometry,))

      # Decide if we want the revision table or the group_revision table.
      if group_id == 0:
         g.assurt(all_gf_count is None)
         table_name = 'revision'
         col_name = 'id'
      else:
         g.assurt(all_gf_count is not None)
         g.assurt(group_id > 0)
         table_name = 'group_revision'
         col_name = 'revision_id'

      # Clear the geometry values.
      clear_geom_sql = (
         """
         UPDATE
            %s
         SET
            geometry = NULL
            , bbox = NULL
            , geosummary = NULL
         WHERE
            %s = %d
         """ % (table_name,
                col_name,
                rid,))
      rows = db.sql(clear_geom_sql)
      g.assurt(not rows)

      # Calculate the geometry values.
      gf_count = Revision.geosummary_update_group_geoms(
                                    db, rid, branch_hier, group_id,
                                    table_name, col_name, skip_geometry,
                                    stats_bucket, all_gf_count)

      # Update the visible count.
      # FIXME: What is visible_items used for?
      if group_id > 0:
         db.sql("UPDATE %s SET visible_items = %s WHERE %s = %s"
                % (table_name, gf_count, col_name, rid,))

      return gf_count

   # C.f. scripts/schema/
   # MAGIC_NUMBER: See below; GEOS bails with lots of geometry, so keep
   #               geomsummary_threshold reasonable.
   @staticmethod
   def geosummary_update_group_geoms(db, rid, branch_hier, group_id,
                                     table_name, col_name, skip_geometry,
                                     stats_bucket, all_gf_count=None,
                                     # BUG nnnn: At some point, it doesn't make
                                     # sense to make the geosummary, or maybe
                                     # it's the geometry. At what point is that
                                     # point? For now, most revisions have less
                                     # than 2,000 geoms or more than 10,000,
                                     # and the ones with less can have their
                                     # geomsummary computer without consuming
                                     # all memory (though [lb] hasn't checked
                                     # to see what the storage footprint of the
                                     # computer geometries are, i.e., we
                                     # canculate bbox, geometry, and geosummary
                                     # but maybe geometry or geosummary is very
                                     # large for revisions with big changes so
                                     # we shouldn't compute and store it).
                                     # NOTE: geomsummary_threshold can be 0 or
                                     #       None to disable it.
                                     geomsummary_threshold=3999):

      # Create the from-clause, which unions the geometry of geofeatures that
      # changed and the geometry of geofeatures of changed link_values.
      sql_from = Revision.sql_gf_geometry(db, rid, branch_hier, group_id)

      # First, use the from-clause to see how many geometries are affected.
      sql_gf_count = "SELECT COUNT(*) as gf_count %s" % (sql_from,)
      # NOTE: This can still take a while, i.e., for revisions with
      #       thousands and thousands of edits.
      # 2012.08.15: Save time. If revision has more rows than we want to
      # process, don't bother couting the items for each group. This should
      # really only apply to scripts that bulk-saved, so the group_id is
      # likely just the Public group.
      if ((all_gf_count is None)
          or (not geomsummary_threshold)
          or (all_gf_count <= geomsummary_threshold)):
         try:
            gf_count = db.sql(sql_gf_count)[0]['gf_count']
         except IndexError:
            # Hmmm... shouldn't there always a row, since we're doing COUNT()?
            log.warning('geosummary_update_group_geoms: Unexpected.')
            gf_count = 0
      else:
         # This might not be the actual gf_count of the group_revision items
         # but we don't care, since we're skipping the geometry calculation.
         gf_count = all_gf_count

      log.verbose('geosum_upd_grp_geoms: On rid: %d / no. gfs: %d'
                  % (rid, gf_count,))

      if (gf_count > 0) and ((not geomsummary_threshold)
                             or (gf_count <= geomsummary_threshold)):
         if (group_id == 0) and (gf_count >= 250):
            log.debug('_update_grp_geo: Big rev: %d / %d geoms.'
                      % (rid, gf_count,))
         Revision.geosummary_update_group_geoms_(db, sql_from, gf_count, rid,
                                                     table_name, col_name,
                                                     skip_geometry)
      else:
         if group_id == 0:
            if gf_count > 0:
               log.debug('_update_grp_geo: Skipping rid %d / %d gfs.'
                         % (rid, gf_count,))

      # NOTE: Just counting stats per revision, and not per group_revision.
      if stats_bucket is not None:
         # Fudge the gf_count so we don't end up with lots of buckets.
         # NOTE: The spaces and periods are so sort() works when we print.
         if gf_count <= 0:
            gf_count_str = '        0'
         elif gf_count <= 10:
            gf_count_str = '     1-10'
         elif gf_count <= 25:
            gf_count_str = '    .<=25'
         elif gf_count <= 50:
            gf_count_str = '   ....50'
         elif gf_count <= 100:
            gf_count_str = '  ....100'
         elif gf_count <= 250:
            gf_count_str = '  ....250'
         elif gf_count <= 1000:
            gf_count_str = ' ....1000'
         else:
            gf_count_str = '%s%d' % ((9 - len(str(gf_count))) * '.', gf_count,)
         misc.dict_count_inc(stats_bucket, gf_count_str)

      return gf_count

   #
   @staticmethod
   def geosummary_update_group_geoms_(db, sql_from, gf_count, rid,
                                          table_name, col_name,
                                          skip_geometry):

      # There's a bug in PostGIS (at least I [lb] assume it's a bug):
      #   http://trac.osgeo.org/geos/ticket/473
      #     "RightmostEdgeFinder assertion killing postgres process"
      # This happens if you try to ST_Buffer() too many geometries --
      # I couldn't find a hard-and-fast number of geometries because it varies
      # on the query, but, on my laptop, it generally happens when processing
      # 500 to 1000 geometries or more. The error occurs in both PostGIS
      # v1.3.6/Geos v3.2.0 and PostGIS v.1.5.3/Geos v3.3.0, and reads:
      #  SELECT: RightmostEdgeFinder.cpp:77:
      #    void geos::operation::buffer::RightmostEdgeFinder::findEdge(
      #      std::vector<geos::geomgraph::DirectedEdge*>*):
      #      Assertion `checked>0' failed.
      # After lots of fiddling, it turns out you can circumvent the error if
      # you simplify a polygonized collection of the geometry. I assume the
      # problem is resource-related and that simplifing the geometry collection
      # just avoids the problem. As for polygonizing, that converts the
      # MULTILINESTRING to a MULTIPOLYGON (otherwise the simplify just returns
      # a GEOMETRYCOLLECTION which triggers a table constrainst complaint).
      # FIXME: This runs and puts something valid in the database, but I still
      # haven't seen what it looks like in flashclient.
      # BUG nnnn: Explain the choice of values sent to ST_Buffer.

      # MAGIC NUMBER: 250 is how many geometries ST_Buffer can safely handle...
      # 2012.08.14: Test: [lb] thinks the ST_Buffer might be fixed in new GEOS
      #                   builds.
      # See Bug 2622: This might be fixed by geos 3.3.0.
      # 2012.08.14: Revision ID 133 has 131603 geofeatures. It grinds [lb]'s
      # laptop to a halt and I see eight GEOS errors and then GEOS bails.
      #   EdgeRing::getRingInternal: IllegalArgumentException:
      #     Invalid number of points in LinearRing found 3 - must be 0 or >= 4
      # CDT LOG:  system logger process (PID 5834) was terminated by signal 9:
      #           Killed
      # CDT LOG:  background writer process (PID 5836) was terminated by
      #           signal 9: Killed
      # CDT LOG:  terminating any other active server processes
      # CDT LOG:  statistics collector process (PID 5839) was terminated by
      #           signal 9: Killed
      # CDT WARNING:  terminating connection because of crash of another server
      #               process
      # CDT DETAIL:  The postmaster has commanded this server process to roll
      #              back the current transaction and exit, because another
      #              server process exited abnormally and possibly corrupted
      #              shared memory.
      # CDT HINT:  In a moment you should be able to reconnect to the database
      #            and repeat your command.
      # CDT LOG:  all server processes terminated; reinitializing
      # CDT LOG:  database system was interrupted; last known up at
      #           2012-08-14 23:08:31 CDT
      # CDT LOG:  database system was not properly shut down; automatic
      #           recovery in progress
      # CDT LOG:  record with zero length at 40/CB23C4F8
      # CDT LOG:  redo is not required
      #
      # The sql() fcn. catches the error as psycopg2.DatabaseError.

      # 2012.08.15: Meh. See geomsummary_threshold (currently 999)... seems
      #             better than 250, which is what CcpV2 has been using.
      geomsummary_threshold = None
      #geomsummary_threshold = 250
      #geomsummary_threshold = 500
      if (not geomsummary_threshold) or (gf_count <= geomsummary_threshold):
         geom_col = "geom_collected"
      else:
         log.warning(
            'More than %d gfs; using simplifypt; see Bug nnnn; found %d gfs.'
            % (geomsummary_threshold, gf_count,))
         # 2012.08.15: This is the right way, right? Silly typo...
         # NO: geom_col = "ST_SimplifyPreserveTopology(geom_polyized, 1)"
         geom_col = "ST_SimplifyPreserveTopology(geom_collected, 1)"

      # NOTE: Using ST_Buffer and not ST_DWithin because we want to make a
      # bounching region and are not searching for geometry.

      # Bug 2622: On the MetC import (30,000+ features), ST_Buffer bombs on
      # (geom, 100, 2) -- the 100 is how many units to expand from the
      # geometry, and the 2 is the number of "quarter-circle segments" (i.e.,
      # if 2, a circle/point would expanded to a not-quite-circular region with
      # 8 points (since a circle has four quarter arcs).
      #
      # EdgeRing::getRingInternal: IllegalArgumentException: Invalid number of
      #                       points in LinearRing found 3 - must be 0 or >= 4
      #  cycling ccpv3 [local] UPDATE: RightmostEdgeFinder.cpp:77:
      #     void geos::operation::buffer::RightmostEdgeFinder::findEdge(
      #        std::vector<geos::geomgraph::DirectedEdge*>*):
      #           Assertion `checked>0' failed.
      #
      # I [lb] tested and it's not one particular geometry: it's a combination
      # of geometries that tickle the failure. (I also searched the osgeo.org
      # bug tracker and can't find much about anything being done about this
      # bug in PostGIS.) (Above I said the error happens on 500 to 100
      # geometries; with MetC it happened on 15,000+ geometries, because when I
      # decreased the sample size it didn't happen.)
      #
      # I then tested the radius, and either a smaller (~ 5 units) or a larger
      # (~ 500 units) value avoids the fault.
      #
      # Nice graphics on how some PostGIS calls work:
      # http://www.bostongis.com/postgis_extent_expand_buffer_distance.snippet
      #
      # http://trac.osgeo.org/postgis/ticket/1351
      # Maybe I just need to update geos? So this isn't a PostGIS problem? Oh,
      # duh, findEdge is in the geos library...
      #
      # Add to docs:
      # SELECT postgis_full_version();
      #
      # EXPLAIN/BUG nnnn: Why just 1 quad-point?? Does this have to with (a)
      # size of the geometry (i.e., network bandwidth and client processing
      # time), (b) the time to calculate the geometry (i.e., is the server just
      # being lazy by using 1 quad-point and not 8?), or (c) does the resulting
      # region actually look better?
      sql_set_geometry = "ST_Multi(ST_Buffer(%s, 5, 1))" % (geom_col,)
      # This fails on geos 3.3.0. But what about 3.3.2? YES! Bug 2622 solved!
      sql_set_geosummary = ("ST_Multi(ST_Simplify(ST_Buffer(%s, 100, 2), 25))"
                            % (geom_col,))

      # EXPLAIN: Why just 2 quad-points? Is it supposedly quicker? (This is a
      # CcpV1 leftover; the default is 8, which we should test.)
      #sql_set_geosummary = ("ST_Multi(ST_Simplify(ST_Buffer(%s, 500, 2), 25))"
      #                      % geom_col)

      # Make the substitution lookup.
      subs = {
         'tname': table_name,
         'srid': conf.default_srid,
         'set_geometry': sql_set_geometry,
         'set_geosummary': sql_set_geosummary,
         'from_geometries' : sql_from,
         'col_name': col_name,
         'rid': rid,
         }

      # Perform the operation. This can take a while for big updates.
      # EXPLAIN: MAGIC NUMBERS.
      # NOTE: If you don't wrap the ST_Box2D with an ST_SetSRID, you get an
      #         IntegrityError: ERROR:  new row for relation "revision"
      #         violates check constraint "enforce_srid_bbox
      # NOTE: ST_Simplify does not guarantee that the geometry remains simple,
      #       as it might create self-intersections. This is okay, since we
      #       just need to send the geosummary to the client and we don't need
      #       to do any further PostGIS processing of it.
      #       FIXME: Use ST_SimplifyPreserveTopology instead and recreate the
      #              constraint?
      # FIXME: Move this to a script that lets you rebuild these columns from
      #        specific revisions, and lets you specify the magic numbers, so
      #        you can test performance vs. results.

      # 2012.08.15: If ST_Multi returns an empty geometry, it's returned as
      # GEOMETRYCOLLECTION(EMPTY), but the PostGIS enforce_* constraints will
      # complain that the geometry type isn't, e.g., MULTIPOLYGON. So we need
      # to wrap the FROM ... SELECT one additional time to check ST_IsEmpty.

      if not skip_geometry:
         update_sql = (
            """
            UPDATE
               %(tname)s
            SET
               bbox = bbox_
               , geometry = geometry_
               , geosummary = geosummary_
            FROM (
               SELECT
                  CASE WHEN ST_IsEmpty(bbox_)
                     THEN NULL ELSE bbox_ END
                        AS bbox_
                  , CASE WHEN ST_IsEmpty(geometry_)
                     THEN NULL ELSE geometry_ END
                        AS geometry_
                  , CASE WHEN ST_IsEmpty(geosummary_)
                     THEN NULL ELSE geosummary_ END
                        AS geosummary_
               FROM (
                  SELECT
                     ST_SetSRID(
                        ST_Box2d(
                           ST_Buffer(ST_Box2d(geom_collected), 0.001, 1)),
                        %(srid)d)
                        AS bbox_
                     , %(set_geometry)s
                        AS geometry_
                     , %(set_geosummary)s
                        AS geosummary_
                  FROM (
                     SELECT
                        ST_Collect(geometry) AS geom_collected
                        , ST_Polygonize(geometry) AS geom_polyized
                     %(from_geometries)s
                     ) AS foo_rev_3
                  ) AS foo_rev_2
               ) AS foo_rev_1
            WHERE
               %(col_name)s = %(rid)d
            """ % subs)
         db.sql(update_sql)

   # ***

   #
   @staticmethod
   def revision_visible_count(db, rid, group_id):
      g.assurt(False) # Not used?
      gf_ids = ','.join([str(x) for x in Item_Type.all_geofeatures()])
      where_group_id = ""
      if group_id != 0:
         where_group_id = (
            """
            AND gia.group_id = %d
            AND gia.access_level_id <= %d
            """ % (group_id, Access_Level.viewer,))
      visible_count = db.sql(
         """
         SELECT
            COUNT(*) AS count
         FROM
            group_item_access AS gia
         WHERE
            gia.valid_start_rid = %d
            AND gia.item_type_id IN (%s)
            %s
         """ % (rid,
                gf_ids,
                where_group_id,))[0]['count']
      return visible_count

   #
   @staticmethod
   def sql_revision_activity(rid, tbl, con='AND'):
      tbl = '' if not tbl else '%s.' % tbl
      rev_query = (
         """
         %(con)s (   %(tbl)svalid_start_rid = %(rid)d
                  OR %(tbl)svalid_until_rid = %(rid)d)
         """ % {'con': con, 'tbl': tbl, 'rid': rid,})
      return rev_query

   # C.f. 016-revision-geosummary.sql, but adding Group ID, since a group may
   # only see a subset of changes. Also adding del_ok, so user can choose to
   # include deleted items or not. */
   @staticmethod
   def sql_gf_geometry(db,
                       rid,
                       branch_hier,
                       group_id,
                       # 2012.06.17: Only one caller uses this fcn. and never
                       # sets these, so this fcn. always runs with these defts:
                       skip_links=False,
                       del_ok=True,
                       incl_perm_changes=False):
      # Make an historic revision object for making where clause bits.
      group_ids = [group_id,] if group_id else None
      gf_rev = Historic(rid, group_ids, allow_deleted=del_ok)
      # If searching by group ID, include the group table
      join_group_ = ""
      where_group_id = ""
      if group_id > 0:
         join_group_ = (
            """
            JOIN
               group_ AS gr
               ON gia.group_id = gr.stack_id
            """)
         include_gids = False # Fcn. would assume col named group_id, anyway.
         allow_deleted = False
         where_gr_rev = gf_rev.as_sql_where('gr', include_gids, allow_deleted)
         where_group_id = (
            """
            AND gr.stack_id = %d
            AND gia.group_id = %d
            AND gia.access_level_id <= %d
            AND %s
            """ % (group_id,
                   group_id,
                   Access_Level.viewer,
                   where_gr_rev,))
      else:
         g.assurt(not group_id)
      # FIXME: Will callers ever set del_ok to False? It's always True.
      if del_ok:
         where_del = ""
      else:
         where_del = "AND NOT iv.deleted"
      # Bug 2695: "Branchy Items Need to be 'Revertable'." As with deleted, we
      # want to find items that were deleted or reverted is this revision. So
      # we're testing AND NOT iv.reverted.
      #         
      # FIXME: Will callers ever set incl_perm_changes to True? Always False.
      if incl_perm_changes:
         g.assurt(False) # FIXME: Still joining (and not left outer joining) on
                       # gf, so will miss grac-activity (gractivity?) anyway...
         where_rev_acty = Revision.sql_revision_activity(rid, 'gia')
      else:
         where_rev_acty = Revision.sql_revision_activity(rid, 'iv')
      # Make the linked-gf rev where clause bit.
      include_gids = bool(group_ids)
      where_gf_rev = gf_rev.as_sql_where('rhs_gia', include_gids)
      where_gf_bra = Revision.branch_hier_where_clause(
                           branch_hier, 'rhs_gia', include_gids)

      common_select = (
         """
         SELECT
            gf.system_id,
            gf.geometry
         FROM
            group_item_access AS gia
         %s """ % (join_group_,))

      sql_geofeatures = (
         """
         UNION (
            %s
            JOIN
               geofeature AS gf
               ON (gia.item_id = gf.system_id)
            JOIN
               item_versioned AS iv
               ON (gf.system_id = iv.system_id)
            WHERE
               gf.geometry is NOT NULL
               %s %s %s
            GROUP BY
               gf.system_id, gf.geometry
            )
         """ % (common_select, where_group_id, where_del, where_rev_acty,))

      sql_link_values = ""
      if not skip_links:
         # FIXME: Feels like a link_value.Many().* call instead of this:
         sql_link_values = (
            """
            UNION (
               %s
               JOIN
                  link_value AS lv
                  ON (gia.item_id = lv.system_id)
               JOIN
                  item_versioned AS iv
                  ON (lv.system_id = iv.system_id)
               JOIN
                  group_item_access AS rhs_gia
                  ON (lv.rhs_stack_id = rhs_gia.stack_id)
               /*LEFT OUTER*/ JOIN
                  geofeature AS gf
                  ON (rhs_gia.item_id = gf.system_id)
               JOIN
                  item_versioned AS gf_iv
                  ON (gf.system_id = gf_iv.system_id)
               WHERE
                  gf.geometry is NOT NULL
                  %s %s %s
                  AND %s
                  AND %s
               GROUP BY
                  gf.system_id, gf.geometry
               )
            """ % (common_select,
                   where_group_id, where_del, where_rev_acty,
                   where_gf_rev,
                   where_gf_bra,))

      sql_str = (
         """
         FROM (
            SELECT gf.system_id, gf.geometry
            FROM (
               SELECT
                  0 AS system_id,
                  ST_GeomFromText('LINESTRING EMPTY', cp_srid())
                     AS geometry
               %s
               %s
               ) AS gf
            WHERE
               gf.system_id > 0
               AND NOT ST_IsEmpty(gf.geometry)
               AND ST_IsValid(gf.geometry)
            GROUP BY
               gf.system_id, gf.geometry
            ) AS geometries
         """ % (sql_geofeatures, sql_link_values,))

      return sql_str

   #
   # NOTE: This fcn. is very branch-knowledgeable, which is not a revisiony
   #       thing. But we can't put this in Item_Query_Builder or in branch,
   #       because we'd create a circular import loop, so it's either gonna
   #       be here or in a new file (branch_revision.py?).
   #
   # FIXME: Disallow include_gids=True? Or just include the GIDs of the first
   #        branch. Otherwise, if a user loses access to a group, a branch with
   #        an older last_merge_rid would return items from the basemap at the
   #        old revision. Granted, the user could go into Historic mode and
   #        we'd checkout items from the old revision since the user had access
   #        back then.
   @staticmethod
   def branch_hier_where_clause(branch_hier,
                                table_name=None,
                                include_gids=False,
                                allow_deleted=None):
      branch_query = ''
      tprefix_dotted = '' if not table_name else table_name + '.'
      for branch_tup in branch_hier:
         branch_id = branch_tup[0]
         g.assurt(isinstance(branch_id, int))
         #prev_last_merge_rid = branch_tup[1]
         branch_rev = branch_tup[1]
         g.assurt(isinstance(branch_rev, Current)
                  or isinstance(branch_rev, Historic))
         subq = ("(%s AND %sbranch_id = %s)"
                 % (branch_rev.as_sql_where(table_name,
                                            include_gids,
                                            allow_deleted),
                    tprefix_dotted,
                    branch_id,))
         if not branch_query:
            branch_query = subq
         else:
            branch_query = "%s OR %s" % (branch_query, subq,)

      if branch_query:
         branch_query = " (%s) " % branch_query
      return branch_query

   # ***

# ***

# Some of the SQL in the following classes is spaced funny so that it's easier
# to debug when you're analyzing a 100+-line SQL query (it's pretty printeder!)

class Revision_Base(Revision):

   __slots__ = (
      'gids',
      'allow_deleted',
      )

   # *** Constructor

   def __init__(self, gids=None, allow_deleted=False):
      Revision.__init__(self)
      self.gids = gids
      self.allow_deleted = allow_deleted

   # *** Built-in Function definitions

   #
   def __str__(self):
      return misc.module_name_simple(self)

   #
   def __eq__(self, other):
      equals = True
      # MAYBE?: equals = equals and (self.gids == other.gids)
      return equals

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   # *** Item Class SQL helper methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False,
                          allow_deleted=None):
      g.assurt(False) # Derived classes should implement.

   #
   def as_sql_where_strict(self, table_name=None):
      include_gids = False
      allow_deleted = False
      return self.as_sql_where(table_name, include_gids, allow_deleted)

   #
   def clone(self):
      g.assurt(False) # Abstract

   #
   def clone_(self, other):
      other.gids = copy.copy(self.gids)
      # log.debug('revision: clone_: gids: %s' % (self.gids,))
      other.allow_deleted = self.allow_deleted

   # SYNC_ME: See flashclient rev_spec module
   def gwis_postfix(self):
      g.assurt(False) # Abstract

   #
   def setup_gids(self, db, username):
      self.gids = User.group_ids_for_user(db, username)

   #
   def short_name(self):
      g.assurt(False) # Abstract

   #
   def sql_where_deleted(self, table_prefix=None, allow_deleted=None):
      sql_where = ""
      if allow_deleted is None:
         allow_deleted = self.allow_deleted
      if not allow_deleted:
         sql_where = " AND (NOT %sdeleted) " % (table_prefix,)
# FIXME_2013_06_11
# FIXME: this whole reverted nonsense... and always do, or just allow_deleted?
#      # Always never fetch reverted.
         sql_where += " AND (NOT %sreverted) " % (table_prefix,)
#      sql_where += " AND (NOT %sreverted) " % (table_prefix,)
      #
      return sql_where

   #
   def sql_where_group_ids(self, gids, table_prefix):
      sql_where = ""
      if gids and (len(gids) > 0):
         if len(gids) == 1:
            sql_where = (
               """
                 AND (%sgroup_id = %d)"""
                           % (table_prefix, gids[0],))
         else:
            sql_where = (
               """
                 AND (%sgroup_id IN (%s))"""
                           % (table_prefix, ','.join([str(x) for x in gids],)))
      return sql_where

   #
   def sql_where_exists_at_rid(self, rid, gids, table_name, allow_deleted):
      table_prefix = Query_Base.table_name_prefixed(table_name)
      args = {
         't': table_prefix,
         'rid': rid,
         'del': self.sql_where_deleted(table_prefix, allow_deleted),
         'gids': self.sql_where_group_ids(gids, table_prefix),
         }
      return (
         """
         (    (%(t)svalid_start_rid <= %(rid)d)
          AND (%(t)svalid_until_rid  > %(rid)d)
         %(del)s
         %(gids)s)
         """ % args)

   # ***

# ***

# *** Current revision class, i.e., latest version and not deleted

class Current(Revision_Base):

   __slots__ = ()

   # *** Constructor

   def __init__(self, gids=None, allow_deleted=False):
      Revision_Base.__init__(self, gids, allow_deleted)
      # log.debug('current: ctor: gids: %s' % (self.gids,))

   # *** Built-in Function definitions

   #
   def __str__(self):
      # Wait: doesn't this just return 'Current:Current'?
      return '%s:Current' % (Revision_Base.__str__(self),)

   #
   def __eq__(self, other):
      equals = (Revision_Base.__eq__(self, other)
                and isinstance(other, Current))
      return equals

   # *** Instance methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False,
                          allow_deleted=None,
                          # BUG nnnn: Mult. basemaps
                          # MAYBE: basemap_stack_id isn't always the basemap;
                          #         it can be an intermediate or leafy branch
                          #         (so rename the parm).
                          basemap_stack_id=None):
      table_prefix = Query_Base.table_name_prefixed(table_name)
      if basemap_stack_id:
         bsid = "AND %sbranch_id = %d" % (table_prefix, basemap_stack_id,)
      else:
         bsid = ""
      args = {
         't': table_prefix,
         'rid_inf': conf.rid_inf,
         'del': self.sql_where_deleted(table_prefix, allow_deleted),
         'gids': self.sql_where_group_ids(self.gids if include_gids else None,
                                          table_prefix),
         'bsid': bsid,
         }
      return (
         """
         ((%(t)svalid_until_rid = %(rid_inf)d)
         %(del)s
         %(gids)s
         %(bsid)s)
         """ % args)

   #
   def clone(self):
      new_rev = Current()
      self.clone_(new_rev)
      return new_rev

   #
   def clone_(self, other):
      Revision_Base.clone_(self, other)

   #
   def gwis_postfix(self):
      return ''

   #
   def short_name(self):
      return 'r:cur'

   #
   def sql_where_exists_at_rid(self, rid, gids, table_name, allow_deleted):
      g.assurt(False)

   # ***

# *** Single, historic revision

class Historic(Revision_Base):

   __slots__ = (
      'rid', # Revision ID of historic revision
      )

   # *** Constructor

   def __init__(self, rid, gids=None, allow_deleted=False):
      Revision_Base.__init__(self, gids, allow_deleted)
      self.rid = rid
      # log.debug('historic: ctor: gids: %s' % (self.gids,))

   # *** Built-in Function definitions

   #
   def __str__(self):
      return '%s:%d' % (Revision_Base.__str__(self), self.rid,)

   #
   def __eq__(self, other):
      equals = (Revision_Base.__eq__(self, other)
                and isinstance(other, Historic)
                and (self.rid == other.rid))
      return equals

   # *** Instance methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False,
                          allow_deleted=None):
      return self.sql_where_exists_at_rid(
            self.rid, self.gids if include_gids else None,
            table_name, allow_deleted)

   #
   def clone(self):
      new_rev = Historic(self.rid)
      self.clone_(new_rev)
      return new_rev

   #
   def clone_(self, other):
      other.rid = self.rid
      other.gids = copy.copy(self.gids)
      # log.debug('historic: clone_: gids: %s' % (self.gids,))
      Revision_Base.clone_(self, other)

   #
   def gwis_postfix(self):
      return str(self.rid)

   #
   def short_name(self):
      return 'r:%d' % (self.rid,)

   # ***

# *** Comparing two revisions

# The Diff class is not used like the others. Callers need to split into two
# Historic revisions and query on those.

class Diff(Revision_Base):

   __slots__ = (
      'rid_old', # the older revision ID, a/k/a former or lhs
      'rid_new', # the newer revision ID, a/k/a latter or rhs
      )

   # *** Constructor

   def __init__(self, rid_old, rid_new, gids=None, allow_deleted=False):
      Revision_Base.__init__(self, gids, allow_deleted)
      self.rid_old = rid_old
      self.rid_new = rid_new

   # *** Built-in Function definitions

   #
   def __str__(self):
      return ('%s:%d:%d' % (Revision_Base.__str__(self),
                            self.rid_old, self.rid_new,))

   #
   def __eq__(self, other):
      equals = (Revision_Base.__eq__(self, other)
                and isinstance(other, Diff)
                and (self.rid_old == other.rid_old)
                and (self.rid_new == other.rid_new))
      return equals

   # *** Instance methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False,
                          allow_deleted=None):
      g.assurt(False) # Not used on Diff.

   #
   def as_sql_where_get_rid(self):
      g.assurt(False) # Not used on Diff.

   #
   def as_sql_where_strict(self, table_name=None):
      g.assurt(False) # Not used on Diff.

   #
   def clone(self):
      new_rev = Diff(self.rid_old, self.rid_new)
      self.clone_(new_rev)
      return new_rev

   #
   def clone_(self, other):
      other.rid_old = self.rid_old
      other.rid_new = self.rid_new
      Revision_Base.clone_(self, other)

   #
   def gwis_postfix(self):
      # Colon ':' signifies Diff.
      return ('%d:%d' % (self.rid_old, self.rid_new,))

   #
   def short_name(self):
      return 'r:%d:%d' % (self.rid_old, self.rid_new,)

   #
   def sql_where_deleted(self, table_prefix=None, allow_deleted=None):
      g.assurt(False) # Not used on Diff.

   #
   def sql_where_group_ids(self, gids, table_prefix):
      g.assurt(False) # Not used on Diff.

   #
   def sql_where_exists_at_rid(self, rid, gids, table_name, allow_deleted):
      g.assurt(False) # Not used on Diff.

   # ***

# ***

# The Updated revision is a special revision used to fetch items that have
# changed between two revisions. Since Updated is used to update internal
# lookups, we fetch items regardless of user context (we ignore permissions)
# and we also fetch deleted items. Also, this should only be used to fetch
# items from a single branch, and not a branch hierarchy.

class Updated(Revision_Base):

   __slots__ = (
      'rid_min', # The earlier revision.
      'rid_max', # The laterer revision.
      )

   # *** Constructor

   def __init__(self, rid_min, rid_max):
      Revision_Base.__init__(self, gids=None, allow_deleted=True)
      # MAYBE?:
      #g.assurt(rid_min < rid_max)
      self.rid_min = rid_min
      self.rid_max = rid_max

   # *** Built-in Function definitions

   #
   def __str__(self):
      return ('%s:%d-%d' % (Revision_Base.__str__(self),
                            self.rid_min, self.rid_max,))

   #
   def __eq__(self, other):
      equals = (Revision_Base.__eq__(self, other)
                and isinstance(other, Updated)
                and (self.rid_min == other.rid_min)
                and (self.rid_max == other.rid_max))
      return equals

   # *** Instance methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False, # Ignored by Updated.
                          allow_deleted=None):
      table_prefix = Query_Base.table_name_prefixed(table_name)
      args = {
         't': table_prefix,
         'rid_min': self.rid_min,
         'rid_max': self.rid_max,
         }
      g.assurt(self.allow_deleted)

      sql = (
         """ (   (    (%(t)svalid_start_rid >= %(rid_min)d)
                  AND (%(t)svalid_start_rid <= %(rid_max)d))
              OR (    (%(t)svalid_until_rid >= %(rid_min)d)
                  AND (%(t)svalid_until_rid <= %(rid_max)d)) )
         """ % args)

      return sql

   #
   def as_sql_where_strict(self, table_name=None):
      # Behave like Historic.
      #
      # EXPLAIN: 2013.05.29: This fcn. is just used for grac tables?
      log.warning('WARNING: as_sql_where_strict: really called for Updated?')
      return self.sql_where_exists_at_rid(
            self.rid_max, gids=None, table_name=table_name,
            allow_deleted=False)

   #
   def clone(self):
      new_rev = Updated(self.rid_min, self.rid_max)
      self.clone_(new_rev)
      return new_rev

   #
   def clone_(self, other):
      other.rid_min = self.rid_min
      other.rid_max = self.rid_max
      Revision_Base.clone_(self, other)

   #
   def gwis_postfix(self):
      # Dash '-' signifies Updated.
      return ('%d-%d' % (self.rid_min, self.rid_max,))

   #
   def setup_gids(self, db, username):
      pass # Updated does not use gids.

   #
   def short_name(self):
      return 'r:%d-%d' % (self.rid_min, self.rid_max,)

   #
   def sql_where_deleted(self, table_prefix=None, allow_deleted=None):
      g.assurt(False) # Not used on Updated.

   #
   def sql_where_group_ids(self, gids, table_prefix):
      g.assurt(False) # Not used on Updated.

   # ***

# *** Special NaN Revision, or Include-All-Revisions Revision,
#     or, Don't-Care-About-Or-Need-To-Know-The-Revision Revision.

# The comprehensive revision considers all revisions. Another way
# to view it is it ignores all revisions because it doesn't join
# on the revision tables -- it's only useful if you're looking for
# an item using a system ID, since the revision is essentially
# encoded in the system ID.

class Comprehensive(Revision_Base):

   __slots__ = ()

   # *** Constructor

   # This is the only revision class to set allow_deleted=True by default; it
   # assumes if you're using a system ID that you want the item, no matter wha.
   def __init__(self, gids=None):
      Revision_Base.__init__(self, gids, allow_deleted=True)

   # *** Built-in Function definitions

   #
   def __str__(self):
      #return misc.module_name_simple(self)
      return 'Comprehensive'

   #
   def __eq__(self, other):
      equals = (Revision_Base.__eq__(self, other)
                and isinstance(other, Comprehensive))
      return equals

   # *** Instance methods

   #
   def as_sql_where(self, table_name=None,
                          include_gids=False,
                          allow_deleted=None):
      # The item_user_access search_get_sql won't call this fcn. It'll check
      # group IDs and permissions in another way, and it won't WHERE or JOIN on
      # any revision IDs. And since we don't have to worry about that, we can
      # use this fcn. to trick query_branch: in branch_hier_build, it'll call
      # this fcn. to check a user's branch access, in which case we can just
      # act like we're Current.
      fake = Current()
      return fake.as_sql_where(table_name, include_gids, allow_deleted,
                               basemap_stack_id=None)

   #
   def as_sql_where_get_rid(self):
      g.assurt(False) # Not used on Comprehensive.

   #
   def as_sql_where_strict(self, table_name=None):
      g.assurt(False) # Not used on Comprehensive.

   #
   def clone(self):
      new_rev = Comprehensive()
      self.clone_(new_rev)
      return new_rev

   #
   def clone_(self, other):
      Revision_Base.clone_(self, other)

   #
   def gwis_postfix(self):
      g.assurt(False) # Not used on Comprehensive.

   #
   def setup_gids(self, db, username):
      #
      # We use the user's current group memberships. This prevents a problem
      # with people being able to view shared items to which they no longer
      # have access. E.g., if a user searches for an item by system ID and
      # we used the user's group memberships at, say, the valid_start_rid of
      # ths item, and if the user happened to have access at that revision,
      # then we'd allow them view access to the item. So stick with "now".
      # Permissions should not wikiable, i.e., a user's group memberships
      # are always considered at the Current revision, and not historically.
      #
      # However, there is another problem: Consider sharing a route in, e.g.,
      # revision 1, and then editing the route and making it private. First,
      # for this example to work, the route has to be edited so that version=2
      # is created; because of how acl_grouping works, the current version of
      # the item becomes inaccessible, but previous versions retain their old
      # access_level_id and group_id values. So someone could ask for the route
      # with its version=1 system ID, and we'd see that the route was shared at
      # the version, so we'd allow the user access to the item.
      #
      # This is already how viewing old revisions works: we checkout items
      # and use the items' group IDs from the historic revision, so if an
      # item was previously shared, then it's going to be fetched.
      #
      # We could change this policy: during a fetch for Historic, we could also
      # do a Current fetch and then compare results, removing any items to
      # which a user no longer has access.
      #
      # Except that, at least how new_item_policy is currently setup, and how
      # flashclient currently works, geofeatures and attachments are private or
      # public for their entire lifetime. E.g., when you create a new point,
      # the client asks you to choose its permissions, and then you can never
      # change it.
      #
      # So this only applies to routes, or other restricted-access style items:
      # if a client asks for a route using gwis checkout and specifies an old
      # revision id, we could find them the item using the old permissions.
      # Except we now (2014.05.10) disallow that (using a raunchy assert
      # because no clients currently send gwis checkout for routes using an
      # historic revision ID).
      #
      # A client should get old versions of restricted-access style items using
      # this new revision class, Comprehensive, and sending a system ID that
      # they either magically know about (landmarks experiment) or that they
      # find using item_history_get.
      #
      Revision_Base.setup_gids(self, db, username)

   #
   def short_name(self):
      return 'r:all'

   #
   def sql_where_deleted(self, table_prefix=None, allow_deleted=None):
      g.assurt(False) # Not used on Comprehensive.

   #
   def sql_where_group_ids(self, gids, table_prefix):
      g.assurt(False) # Not used on Comprehensive.

   #
   def sql_where_exists_at_rid(self, rid, gids, table_name, allow_deleted):
      g.assurt(False) # Not used on Comprehensive.

   # ***

# ***

# *** Unit test code

if (__name__ == '__main__'):
   import sys
   rev = None
   if (len(sys.argv) > 1):
      rev = sys.argv[1]
   f = Revision.revision_object_get(rev)
   print f.as_sql_where('foo')

