# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import cPickle
import datetime
import os
import sys
import time

import conf
import g

from grax.user import User
from item import item_user_access
from item.attc import post
from item.attc import thread
from item.feat import branch
from item.feat import route
from item.grac import group_revision
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_composer import Watcher_Composer
from item.util.watcher_frequency import Watcher_Frequency
from item.util.watcher_parts_base import Watcher_Parts_Base
from util_ import misc

log = g.log.getLogger('watchr_wtchr')

# DEVS: You can easily test this module. Use flashclient to create alert
#       events. Then, run ./scripts/daily/watchers_emailer.py.
#       You can test over with
#         UPDATE item_event_alert SET date_alerted = NULL;

# ***

class Watcher_Watcher(object):

   PICKLE_PROTOCOL_ASCII = 0

   watcher_internal_name = '/item/alert_email'

   def __init__(self, qb):
      self.qb = qb

   # ***

   #
   def add_alerts(self, rid, processed_items=None, reverted_revs=None):

      g.assurt(isinstance(self.qb.revision, revision.Current))

      self.attr_alert_email = self.qb.item_mgr.get_system_attr(
                                 self.qb,
                                 Watcher_Watcher.watcher_internal_name)
      g.assurt(self.attr_alert_email is not None)

      # For some saved items, we can do an INSERT FROM SELECT.

      self.make_events_direct(rid)

      self.make_events_within(rid)

      self.make_events_thread(rid)
 
      # For some saved items, it's easier to iterate through what was
      # just saved. This processes revision-feedback (attr-post lval).
      if processed_items:
         self.make_events_revfbk(rid, processed_items)

      # Revision reverts aren't items and are watched a little differently.
      # On revert, add event to email user whose revision was reverted.
      if reverted_revs:
         self.make_events_revrvt(rid, reverted_revs)

   # ***

   #
   # First, make events for items the user is watching that were edited.
   def make_events_direct(self, rid):

      # Skipping: messaging_id (it's got a default).
      # Skipping: date_created (it's got a pre-insert trigger).
      # Skipping: date_alerted (it hasn't happened yet).
      # Skipping: notifier_dat and notifier_raw (not implement yet/if ever).
      # Note: lv.value_integer is the Watcher_Frequency value.
      # insert_edited_sql = (
      #    """
      #    INSERT INTO item_event_alert
      #       (  username
      #        , latest_rid
      #        , item_id
      #        , branch_id
      #        , item_stack_id
      #        , watcher_stack_id
      #        , msg_type_id
      #        , service_delay)
      #    SELECT
      #         gm.username
      #       , %d AS rid
      #       , rhs_iv.system_id
      #       , rhs_iv.branch_id
      #       , rhs_iv.stack_id
      #       , lv.stack_id
      #       , %d -- msg_type_id
      #       , lv.value_integer
      #    FROM group_item_access AS gia
      #    JOIN link_value AS lv
      #       ON (gia.item_id = lv.system_id)
      #    JOIN item_versioned AS rhs_iv
      #       ON (lv.rhs_stack_id = rhs_iv.stack_id)
      #    JOIN group_membership AS gm
      #       ON (gia.group_id = gm.group_id)
      #    JOIN user_ AS u
      #       ON (gm.username = u.username)
      #    WHERE 
      #          (gia.branch_id = %d)
      #      AND (lv.lhs_stack_id = %d)
      #      AND (   rhs_iv.valid_start_rid = %d
      #           OR rhs_iv.valid_until_rid = %d)
      #      AND %s -- group_item_access revision
      #      AND %s -- group_membership revision
      #      AND u.enable_watchers_email IS TRUE
      #    """ % (rid,
      #           Watcher_Parts_Base.MSG_TYPE_DIRECT,
      #           self.qb.branch_hier[0][0],
      #           self.attr_alert_email.stack_id,
      #           rid,
      #           rid,
      #           self.qb.revision.as_sql_where_strict('gia'),
      #           self.qb.revision.as_sql_where_strict('gm'),
      #           ))

      insert_edited_sql = (
         """
         INSERT INTO item_event_alert
            (  username
             , latest_rid
             , item_id
             , branch_id
             , item_stack_id
             , watcher_stack_id
             , msg_type_id
             , service_delay)
         SELECT
              gm.username
            , %d AS rid
            , rhs_iv.system_id
            , rhs_iv.branch_id
            , rhs_iv.stack_id
            , lv.stack_id
            , %d -- msg_type_id
            , lv.value_integer
         FROM item_versioned AS rhs_iv
         JOIN link_value AS lv
            ON (rhs_iv.stack_id = lv.rhs_stack_id)
         JOIN item_versioned AS lv_iv
            ON (lv.system_id = lv_iv.system_id)
         JOIN group_item_access AS gia
            ON (lv_iv.system_id = gia.item_id)
         JOIN group_membership AS gm
            ON (gia.group_id = gm.group_id)
         JOIN user_ AS u
            ON (gm.username = u.username)
         WHERE 
               (rhs_iv.branch_id = %d)
           AND (   rhs_iv.valid_start_rid = %d
                OR rhs_iv.valid_until_rid = %d)
           AND (lv.lhs_stack_id = %d)
           AND %s -- link_value's group_item_access revision
           AND %s -- user's group_membership revision
           AND u.enable_watchers_email IS TRUE
           --AND u.username != %s
         """ % (rid,
                Watcher_Parts_Base.MSG_TYPE_DIRECT,
                self.qb.branch_hier[0][0],
                rid,
                rid,
                self.attr_alert_email.stack_id,
                self.qb.revision.as_sql_where_strict('lv_iv'),
                self.qb.revision.as_sql_where_strict('gm'),
                self.qb.db.quoted(self.qb.username),
                ))

      rows = self.qb.db.sql(insert_edited_sql)

      log.debug('make_events_direct: rowcount: %s'
                % (self.qb.db.curs.rowcount,))

   # ***

   #
   # Second, make events for regions user is watching within which items
   # were edited.
   def make_events_within(self, rid):
      # NOTE: We might make events for the same item, but we leave it up
      #       to the email fcn. to coalesce records so that the user email
      #       doesn't include redundant events.

# TEST: Don't filter by Region: indicate on any item being watched that
#       overlaps with another item that was edited.
      insert_isects_sql = (
         """
         INSERT INTO item_event_alert
            (  username
             , latest_rid
             , item_id
             , branch_id
             , item_stack_id
             , watcher_stack_id
             , msg_type_id
             , service_delay)
         SELECT
              gm.username
            , %d AS rid
            , rhs_iv.system_id
            , rhs_iv.branch_id
            , rhs_iv.stack_id
            , lv.stack_id
            , %d -- msg_type_id
            , lv.value_integer
         FROM link_value AS lv
         JOIN item_versioned AS lv_iv
            ON (lv.system_id = lv_iv.system_id)
         JOIN group_item_access AS gia
            ON (lv.system_id = gia.item_id)
         JOIN geofeature AS rhs_gf
            ON (lv.rhs_stack_id = rhs_gf.stack_id)
         JOIN item_versioned AS rhs_iv
            ON (rhs_gf.system_id = rhs_iv.system_id)
         JOIN group_membership AS gm
            ON (gia.group_id = gm.group_id)
         JOIN user_ AS u
            ON (gm.username = u.username)
         JOIN revision AS rev
            ON (rev.id = %d)
         WHERE
               (gia.branch_id = %d)
--AND (gia.rhs_item_type_id = %d) -- a Region
           AND (lv.lhs_stack_id = %d)
           AND %s -- lv_iv revision
           AND %s -- rhs_iv revision
           AND ST_Intersects(rhs_gf.geometry, rev.geometry)
           AND %s -- group_membership revision
           AND u.enable_watchers_email IS TRUE
           --AND u.username != %s
         """ % (rid,
                Watcher_Parts_Base.MSG_TYPE_WITHIN,
                rid,
                self.qb.branch_hier[0][0],
Item_Type.REGION,
                self.attr_alert_email.stack_id,
                self.qb.revision.as_sql_where_strict('lv_iv'),
                self.qb.revision.as_sql_where_strict('rhs_iv'),
                self.qb.revision.as_sql_where_strict('gm'),
                self.qb.db.quoted(self.qb.username),
                ))

      rows = self.qb.db.sql(insert_isects_sql)

      log.debug('make_events_within: rowcount: %s'
                % (self.qb.db.curs.rowcount,))

   # ***

   #
   # Third, add thread events.
   def make_events_thread(self, rid):

      insert_thread_sql = (
         """
         INSERT INTO item_event_alert
            (  username
             , latest_rid
             , item_id
             , branch_id
             , item_stack_id
             , watcher_stack_id
             , msg_type_id
             , service_delay)
         SELECT
              gm.username
            , %d AS rid
            , post_iv.system_id
            , post_iv.branch_id
            , post_iv.stack_id
            , lv.stack_id
            , %d -- msg_type_id
            , lv.value_integer
         FROM item_versioned AS post_iv
         JOIN post
            ON (post_iv.system_id = post.system_id)
         JOIN thread
            ON (post.thread_stack_id = thread.stack_id)
         JOIN link_value AS lv
            ON (thread.stack_id = lv.rhs_stack_id)
         JOIN item_versioned AS lv_iv
            ON (lv.system_id = lv_iv.system_id)
         JOIN group_item_access AS gia
            ON (lv_iv.system_id = gia.item_id)
         JOIN group_membership AS gm
            ON (gia.group_id = gm.group_id)
         JOIN user_ AS u
            ON (gm.username = u.username)
         WHERE 
               (   post_iv.valid_start_rid = %d
                OR post_iv.valid_until_rid = %d)
           AND (post_iv.branch_id = %d)
           AND (lv.lhs_stack_id = %d)
           AND %s -- lv_iv revision
           AND %s -- group_membership revision
           AND u.enable_watchers_email IS TRUE
           --AND u.username != %s
         """ % (rid,
                Watcher_Parts_Base.MSG_TYPE_THREAD,
                rid,
                rid,
                self.qb.branch_hier[0][0],
                self.attr_alert_email.stack_id,
                self.qb.revision.as_sql_where_strict('lv_iv'),
                self.qb.revision.as_sql_where_strict('gm'),
                self.qb.db.quoted(self.qb.username),
                ))

      rows = self.qb.db.sql(insert_thread_sql)

      log.debug('make_events_thread: rowcount: %s'
                % (self.qb.db.curs.rowcount,))

   # ***

   #
   # Fourth, add revision feedback events.
   def make_events_revfbk(self, rid, processed_items):

      # Look for link_post-revisions and add events for revision committers.
      attr_post_rev = None
      link_post_revs = set()
      for item in processed_items:
         # Commit saves link_post items as link_value; only on checkout do we
         # use link_post items.
         # NOTE: Don't just use isinstance; the Python way is to just check the
         #       interface.
         try:
            if ((item.link_lhs_type_id == Item_Type.POST)
                and (item.link_rhs_type_id == Item_Type.ATTRIBUTE)):
               # Check/Assurt that the attribute is /post/revision.
               if attr_post_rev is None:
                  attr_post_rev = link_post.Many(Item_Type.ATTRIBUTE)
                  attr_post_rev.attribute_load(self.qb, '/post/revision')
               g.assurt(item.rhs_stack_id == attr_post_rev.stack_id)
               # Remember the link_post item.
               g.assurt(not item in link_post_revs)
               link_post_revs.add(item)
         except AttributeError:
            pass # Not a link_value or link_post.
      # If a new link_post-revision was created, email the revisioner.
      if link_post_revs:
         log.debug('do_post_commit: Found %d link_post-revisions.'
                   % (len(link_post_revs),))
         # The user might be talking about multiple revisions, but it's still
         # just one post.
         the_post = None
         rev_ids = set()
         for lpost_rev in link_post_revs:
            # Find the post.
            try:
               post = processed_items[lpost_rev.lhs_stack_id]
               if the_post is None:
                  the_post = post
               else:
                  g.assurt(post == the_post)
            except KeyError:
               g.assurt(False)
            # Get the revision ID.
            rev_id = lpost_rev.value_integer
            g.assurt(rev_id > 0)
            g.assurt(rev_id not in rev_ids)
            rev_ids.add(rev_id)
         g.assurt(rev_ids)
         # Get the thread.
         try:
            the_thread = processed_items[the_post.thread_stack_id]
         except KeyError:
            g.assurt(False)

         self.make_events_revfbk_threads(the_thread, the_post, rev_ids)
      # else: not link_post_revs

   #
   def make_events_revfbk_threads(self, the_thread, the_post, rev_ids):

# FIXME: Flashclient limits the number of revisions one can provide
# feedback on at the same time, so we should g.assurt... oh, wait, Flashclient
# doesn't limit the number of revisions in the same feedback. (It's limited by
# the length of the revision history list, though.) How exactly does that work?
# If you comment on Revs 1,2,3 in one Post, can someone else make a new thread
# about one of those Revs? I think that should be allowed but the user should 
# be prompted that there exists a thread -- we should suggest they talk in the
# same thread, but really, what if the user has something else to say about the
# revision? Either that, or we shouldn't allow commenting on mult revs at once,
# since that forces all follow-up posts to do the same (so follow-up posts
# cannot talk about just one of those revisions).
#
# TEST_ME: Make feedback on Rev 12345, then try making feedback
# again on 12345, then try making feedback on 12345 and 12346. For the
# first test, a new discussion should be created; for the second test,
# the existing discussion should be used; for third test, does a new
# discussion get created, or does the revision get added to the existing
# discussion?
      g.assurt(the_thread.stack_id > 0)

      # Get the list of revision committers.

      rev_ids_str = ','.join([str(x) for x in rev_ids])
      rev_user_sql = (
         """
         SELECT
            id AS revision_id
            , username
            , alert_on_activity
         FROM
            revision
         WHERE
            id IN (%s)
         ORDER BY
            username
         """ % (rev_ids_str,))

      rows = self.qb.db.sql(rev_user_sql)
      if len(rows) == len(rev_ids):
         log_fcn = log.debug
      else:
         # This could be a programmer error, or maybe a client error.
         log_fcn = log.error
      log_fcn('mk_evts_revfbk_tds: found %d revs in db (wanted %d)'
              % (len(rows), len(rev_ids),))

      alert_users = {}

      # Collect revs for each user (the feedbackees).
      cur_user = None
      alert_ok = False
      for row in rows:
         if (cur_user is not None) and (cur_user != row['username']):
            self.add_revfbk_user(alert_users, alert_ok, cur_user)
            cur_user = None
         if cur_user is None:
            cur_user = row['username']
            alert_ok = False
         if ['alert_on_activity']:
            # NOTE: If reverter reverts two revisions from same user, but user
            #       is only asking to be alerted on one but not the other,
            #       since we only send one email for the single revert
            #       thread... well, you get the picture: if at least one
            #       revision for the same user indicates alerting, we'll alert.
            alert_ok = True
         # Ignoring: row['revision_id']
      # After looping, process the first of 1 entry, or the last of 2+ entries.
      if cur_user is not None:
         self.add_revfbk_user(alert_users, alert_ok, cur_user)
         cur_user = None

      # Pickle a structure we'll use to make the feedback emails.
      # [0]: The one writing the feedback.
      # [1]: The ones being fedback.
      # [2]: The revision IDs.
      rvt_dat = (post.post_username, alert_users, rev_ids,)
      notifier_dat = cPickle.dumps(
         rvt_dat, Watcher_Watcher.PICKLE_PROTOCOL_ASCII)

      # Unless it's a script, the feedbacker always gets an email.
      # NO: This is really old CcpV1 behavior. Now we just make a
      # new discussion, so the feedbacker doesn't need an email with
      # a link (in old CcpV1, the discussion was held in google groups).
      #  if post.post_username != self.qb.username:
      #     log.error('make_events_revfbk: unexpected: post-by: %s / user: %s',
      #               (post.post_username, self.qb.username,))
      #  cur_user = self.qb.username
      #  if ((cur_user != conf.anonymous_username)
      #      and (not User.user_is_script(cur_user))):
      #     self.add_revfbk_event(cur_user, the_thread, the_post, notifier_dat)

      # Add events for each user whose revision was feededback (feedbackees).
      for (cur_user, alert_ok,) in alert_users.iteritems():
         if alert_ok:
            self.add_revfbk_event(cur_user, the_thread, the_post, notifier_dat)

      # Make a weird, hacky event for emailing the general public.
      # NO: This is really old CcpV1 behavior, to email
      #     cyclopath-feedback@googlegroups.com. But we
      #     just make a new discussion instead and don't
      #     send a public email.
      # self.add_revfbk_event(conf.anonymous_user, the_thread, the_post,
      #                       notifier_dat)

   #
   def add_revfbk_user(self, alert_users, alert_ok, cur_user):

      if not alert_ok:
         # This means user did not ask for revision.alert_on_activity.
         log.debug(
            'add_revfbk_user: alert_on_activity says no: u:%s / t:%s / p:%s'
            % (cur_user, the_thread, the_post,))
      elif cur_user == conf.anonymous_username:
         # Ignore revisions created by ACs (anonymous cowards) since no email.
         log.debug('mk_evts_revfbk_tds: rev. from anon coward.')
         alert_ok = False
      elif User.user_is_script(cur_user):
         # 2012.08.17: Check that the revision wasn't made by a robot.
         log.debug('mk_evts_revfbk_tds: rev. from silly robot.')
         alert_ok = False
      # One might not think that we should email the feedbacker, but we do!
      #  elif cur_user == self.qb.username:
      #     log.debug(
      #       'mk_evts_revfbk_tds: skipping: poster == revver: %s / rid: %d'
      #        % (self.qb.username, row['revision_id'],))
      elif cur_user == self.qb.username:
         log.debug('mk_evts_revfbk_tds: user is reverter: %s' % (cur_user,))
         alert_ok = True
      else:
         log.debug('mk_evts_revfbk_tds: user is revertee: %s' % (cur_user,))
         alert_ok = True

      alert_users[cur_user] = alert_ok

   #
   # Record feedback event alert for individual users.
   def add_revfbk_event(self, cur_user, the_thread, the_post, notifier_dat):

      user_qb = Item_Query_Builder(
         self.qb.db, cur_user, self.qb.branch_hier, self.qb.revision)
      # NO?: Query_Overlord.finalize_query(user_qb)
      threads = threads.Many()
      threads.search_by_stack_id(the_thread.stack_id, user_qb)
      if not threads:
         log.error(
            'mk_evts_revfbk_tds: user cannot see thread: %s / %s'
            % (cur_user, the_thread,))
      else:
         g.assurt(len(threads) == 1)
         g.assurt(threads[0].system_id == the_thread.system_id)
         # NOTE: For simplicity, we're not checking enable_watchers_email.
         #       Since this is an immediate event, cron is about to run
         #       and it'll check that it's okay to email the user then.
         insert_rev_sql = (
            """
            INSERT INTO item_event_alert
               (  username
                , latest_rid
                , branch_id
                , item_id
                , item_stack_id
                , watcher_stack_id
                , msg_type_id
                , service_delay
                , notifier_dat)
            VALUES
               (  '%s'  -- username
                ,  %d   -- latest_rid
                ,  %d   -- branch_id
                ,  %d   -- item_id
                ,  %d   -- item_stack_id
                ,  %d   -- watcher_stack_id
                ,  %d   -- msg_type_id
                ,  %d   -- service_delay
                , '%s') -- notifier_dat
            """ % (cur_user,
                   # Store the post values, not the thread's.
                   the_post.valid_start_rid,
                   the_post.branch_id, # ==? self.qb.branch_hier[0][0]
                   the_post.system_id,
                   the_post.stack_id,
                   0, # No link_value watcher, since
                      # revision.alert_on_activity
                   Watcher_Parts_Base.MSG_TYPE_REV_FEEDBACK,
                   Watcher_Frequency.immediately,
                   notifier_dat,
                   ))

         rows = self.qb.db.sql(insert_rev_sql)

         log.debug('make_events_revfbk_threads: rowcount: %s'
                   % (self.qb.db.curs.rowcount,))

   #
   # Fifth, add revision revert events.
   def make_events_revrvt(self, rid, reverted_revs):

      log.error('FIXME: TEST_ME: This fcn...')

      # C.f. This code looks like make_events_revfbk_threads.

      notifier_dat = cPickle.dumps(
         reverted_revs, Watcher_Watcher.PICKLE_PROTOCOL_ASCII)

      rev_ids_str = ','.join([str(x) for x in reverted_revs])
      rvt_revs_sql = (
         """
         SELECT
            id AS revision_id
            , username
            , alert_on_activity
         FROM
            revision
         WHERE
            id IN (%s)
         ORDER BY
            username
         """ % (rev_ids_str,))

      rows = self.qb.db.sql(rvt_revs_sql)
      if len(rows) == len(reverted_rows):
         log_fcn = log.debug
      else:
         # This could be a programmer error, or maybe a client error.
         log_fcn = log.error
      log_fcn(
         'make_events_revrvt: found %d revs in db (wanted %d) / %s / %s'
         % (len(rows), len(reverted_rows), rid, reverted_rows,))

      row_values = []

      user_revs = {}
      cur_user = None
      alert_ok = False
      for row in rows:
         if (cur_user is not None) and (cur_user != row['username']):
            self.get_insert_sql_revrvt(
               alert_ok, cur_user, rid, notifier_dat, row_values)
            cur_user = None
         if cur_user is None:
            cur_user = row['username']
            alert_ok = False
         if ['alert_on_activity']:
            alert_ok = True
      # end: for row in rows
      if cur_user is not None:
         self.get_insert_sql_revrvt(
            alert_ok, cur_user, rid, notifier_dat, row_values)

      if row_values:
         insert_rev_sql = (
            """
            INSERT INTO item_event_alert
               (  username
                , latest_rid
                , branch_id
                , item_id
                , item_stack_id
                , watcher_stack_id
                , msg_type_id
                , service_delay
                , notifier_dat)
            VALUES
               (%s)
            """ % (','.join(row_values),))
         rows = self.qb.db.sql(insert_rev_sql)
         log.debug('make_events_revrvt: rowcount: %s'
                   % (self.qb.db.curs.rowcount,))

   #
   def get_insert_sql_revrvt(self, alert_ok, cur_user, rid, notifier_dat,
                                   row_values):

      if not alert_ok:
         log.debug(
            'get_insert_sql_revrvt: alert_on_activity: no / usr: %s / dat: %s'
            % (cur_user, notifier_dat,))
      else:
         log.debug('Adding event for revert: user: %s / rid: %s / rvt: %s'
                   % (row['username'], rid, row['id'],))
         values_sql = (
            """(  '%s'  -- username
                ,  %d   -- latest_rid
                ,  %d   -- branch_id
                ,  %d   -- item_id
                ,  %d   -- item_stack_id
                ,  %d   -- watcher_stack_id
                ,  %d   -- msg_type_id
                ,  %d   -- service_delay
                , '%s') -- notifier_dat
            """ % (cur_user,
                   rid,
                   self.qb.branch_hier[0][0],
                   0, # No item_id
                   0, # No item_stack_id
                   0, # No item watcher; see revision.alert_on_activity
                   Watcher_Parts_Base.MSG_TYPE_REV_REVERT,
                   Watcher_Frequency.immediately,
                   notifier_dat,
                   ))
         row_values.append(values_sql)

   # ***

   #
   def send_alerts(self, service_delay):

      #log.debug('send_alerts: service_delay: %s (%s)'
      #   % (service_delay,
      #      Watcher_Frequency.get_watcher_frequency_name(service_delay),))

      # Select item alerts to make it easy to make emails:
      # 1. We email one user at a time, so order by user firstly.
      # 2. Events for some message types can be coalesced but
      #    for other message types, we send one alert per email.

      self.qb.db.dont_fetchall = True

      fetch_events_sql = (
         """
         SELECT
              iea.messaging_id
            , iea.username
            , iea.branch_id
            , iea.msg_type_id
            , iea.latest_rid
            , iea.item_stack_id
            , iea.service_delay
            , iea.watcher_stack_id
            , iea.notifier_dat
            , u.email
            , u.enable_watchers_email
            , u.unsubscribe_proof
         FROM item_event_alert AS iea
         JOIN user_ AS u
            ON (iea.username = u.username)
         WHERE
                (date_alerted IS NULL)
            AND (service_delay = %d)
            AND ((ripens_at IS NULL)
                 OR (ripens_at <= NOW()))
         ORDER BY
              iea.username ASC
            , iea.msg_type_id DESC
            , iea.branch_id ASC
            , iea.latest_rid DESC
            , iea.item_stack_id DESC
            , iea.item_id DESC
         """ % (service_delay,))

      rows = self.qb.db.sql(fetch_events_sql)
      g.assurt(rows is None)

      if not self.qb.db.curs.rowcount:
         log.debug('send_alerts: zero events for service_delay: %s'
            % (Watcher_Frequency.get_watcher_frequency_name(service_delay),))
      else:
         log.debug('send_alerts: found %d events (%s)'
            % (self.qb.db.curs.rowcount,
               Watcher_Frequency.get_watcher_frequency_name(service_delay),))

      # Get a cursor for the processing fcns, since we're iterator over ours.
      event_db = self.qb.db.clone()
      event_db.dont_fetchall = False

      db = self.qb.db.clone()
      db.dont_fetchall = False
      #log.debug('send_alerts: self.qb.db.curs: %s / db.curs: %s'
      #          % (id(self.qb.db.curs), id(db.curs),))

      cur_email = None

      all_msgng_ids = []

      generator = self.qb.db.get_row_iter()
      for row in generator:

         messaging_id = row['messaging_id']
         username = row['username']
         branch_id = row['branch_id']
         msg_type_id = row['msg_type_id']
         latest_rid = row['latest_rid']
         item_stack_id = row['item_stack_id']
         service_delay = row['service_delay']
         watcher_stack_id = row['watcher_stack_id']
         notifier_dat = row['notifier_dat']
         email_addy = row['email']
      # FIXME: Delete column user_.enable_watchers_digest
         enable_watchers_email = row['enable_watchers_email']
         unsubscribe_proof = row['unsubscribe_proof']

         all_msgng_ids.append(messaging_id)

         g.assurt(username)
         if (cur_email is None) or (cur_email.username != username):

            if cur_email is not None:
               cur_email.emails_send_coalesced_events()
               cur_email = None

            users_group_id = User.private_group_id(event_db, username)

            cur_email = Watcher_Composer(
               event_db,
               username,
               users_group_id,
               email_addy,
               service_delay,
               unsubscribe_proof)

         do_add_event = False
         if watcher_stack_id:
            still_active_sql = (
               """
               SELECT lv.value_integer
                 FROM group_item_access AS gia
                 JOIN link_value AS lv
                   ON (gia.item_id = lv.system_id)
                WHERE
                      gia.stack_id = %d
                  AND gia.group_id = %d
                  AND gia.valid_until_rid = %d
                ORDER BY
                      gia.version DESC,
                      gia.acl_grouping DESC
                LIMIT 1
               """ % (watcher_stack_id,
                      users_group_id,
                      conf.rid_inf,))

            rows = event_db.sql(still_active_sql)
            if rows:
               watcher_freq = rows[0]['value_integer']
               log.debug(
                  'send_alerts: watcher_stack_id: %s / usr: %s / freq: %s'
                  % (watcher_stack_id,
                     username,
                     Watcher_Frequency.get_watcher_frequency_name(
                                                      watcher_freq),))
               g.assurt(len(rows) == 1)
               if watcher_freq != Watcher_Frequency.never:
                  do_add_event = True
            else:
               log.debug('send_alerts: watcher inactive: %s / usr: %s'
                         % (watcher_stack_id, username,))
         # end: if watcher_stack_id
         else:
            # No watcher_stack_id, meaning this is revision.alert_on_activity.
            g.assurt(msg_type_id in (
               Watcher_Parts_Base.MSG_TYPE_REV_FEEDBACK,
               Watcher_Parts_Base.MSG_TYPE_REV_REVERT,
               Watcher_Parts_Base.MSG_TYPE_RTE_REACTION,))
            do_add_event = True

         if do_add_event:
            if enable_watchers_email:
               # For watched items and watch regions, we'll coalesce events
               # into one email and we'll send the email via compone_and_send;
               # for all of msg_types, we'll send the email here.
               cur_email.process_event(messaging_id, msg_type_id, branch_id,
                                       latest_rid, item_stack_id, notifier_dat)
            else:
               log.debug('send_alerts: watchers disabled; skip evt: id: %d'
                         % (messaging_id,))
         else:
            log.debug('send_alerts: watcher is never; skip evt: id: %d'
                      % (messaging_id,))

      # end: for row in generator

      if cur_email is not None:
         # On the last user, we'll exit the loop before emailing, so,
         # special case, email the last user.
         cur_email.emails_send_coalesced_events()
         cur_email = None

      # The Watcher_Composer handled finalizing messaging IDs, so
      # this call should say 0 rows updated.
      if all_msgng_ids:
         row_count = Watcher_Composer.finalize_alerts(all_msgng_ids, None)
         if row_count:
            log.warning(
               'send_alerts: unexpected finalize_alerts row_count: %s'
               % (row_count,))

      # Cleanup in aisle db!
      #log.debug('send_alerts: cleanup: db.curs: %s' % (id(db.curs),))
      db.close()
      event_db.close()

      log.debug('send_alerts: emailed usernames: %s'
                % (Watcher_Composer.emailed_usernames,))

   # ***

# ***

