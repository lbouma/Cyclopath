# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

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
from item.util.watcher_parts_base import Watcher_Parts_Base
from item.util.watcher_parts_map_edit import Watcher_Parts_Map_Edit
from item.util.watcher_parts_new_post import Watcher_Parts_New_Post
from item.util.watcher_frequency import Watcher_Frequency
from util_ import misc
from util_ import db_glue
from util_.db_glue import DB
from util_.emailer import Emailer

log = g.log.getLogger('watcher_cpsr')

# DEVS: Set this True to not update item_event_alert, to help test.
DEV_SKIP_UPDATE_ITEM_EVENT_ALERT=False
#DEV_SKIP_UPDATE_ITEM_EVENT_ALERT=True

# ***

class Watcher_Composer(object):

   emailed_usernames = set()

   # ***

   def __init__(self,
                db,
                username,
                users_group_id,
                email_addy,
                service_delay,
                unsubscribe_proof):
      self.db = db
      self.username = username
      self.users_group_id = users_group_id
      self.email_addy = email_addy
      self.service_delay = service_delay
      self.unsubscribe_proof = unsubscribe_proof
      self.unsubscribe_link = Emailer.make_unsubscribe_link(
         'user_nowatchers', self.email_addy, self.unsubscribe_proof)
      # The heliko gets encoded with a percent symbol, which screws up
      # later interpolation.
      self.unsubscribe_link = self.unsubscribe_link.replace('%', '%%')

      self.msg_text = ''
      self.msg_html = ''
      self.edit_branch = {}
      self.edit_thread = {}
      self.rids_branch = set()
      self.rids_thread = set()
      self.msg_ids_branch = set()
      self.msg_ids_thread = set()
      self.n_all_ev = 0
      self.n_itm_ev = 0
      self.n_thd_ev = 0
      self.branch_qbs = {}
      self.user_grevs = {}

   # ***

   #
   def process_event(self, msgng_id, msg_type_id, branch_id, latest_rid,
                           item_stack_id, notifier_dat):

      # Some events get coalesced; others get processed immediately.
      if (msg_type_id in (Watcher_Parts_Base.MSG_TYPE_WITHIN,
                          Watcher_Parts_Base.MSG_TYPE_DIRECT,)):
         self.coalesce_edit_event(
            msgng_id, msg_type_id, branch_id, latest_rid, item_stack_id)

      elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_THREAD:
         self.coalesce_thread_event(
            msgng_id, msg_type_id, branch_id, latest_rid, item_stack_id)

      elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_REV_FEEDBACK:
         self.email_send_rev_feedback(
            msgng_id, branch_id, latest_rid, item_stack_id, notifier_dat)

      elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_REV_REVERT:
         self.email_send_rev_revert(
            msgng_id, branch_id, latest_rid, item_stack_id, notifier_dat)

      elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_RTE_REACTION:
         self.email_send_rte_reaction(
            msgng_id, branch_id, latest_rid, item_stack_id, notifier_dat)

      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_RTE_FEEDBACK:
      #   self.email_send_rte_feedback(
      #      msgng_id, branch_id, latest_rid, item_stack_id, notifier_dat)

      else:
         g.assurt(False)

      self.n_all_ev += 1

   # *** Helpers for all MSG_TYPE_*s

   #
   def get_qb_for_branch(self, branch_id):

      try:

         branch_qb, the_branch = self.branch_qbs[branch_id]
         log.debug('get_qb_for_branch: existing qb: user: %s / branch_id: %s'
                   % (self.username, branch_id,))

      except KeyError:

         rev = revision.Current()
         branch_hier = branch.Many.branch_hier_build(self.db, branch_id, rev)
         branch_qb = Item_Query_Builder(self.db, self.username, branch_hier,
                                        rev)
         g.assurt(branch_id == branch_hier[0][0])

         access_ok = True
         the_branch = None
         branches = branch.Many()
         branches.search_by_stack_id(branch_id, branch_qb)
         if branches:
            g.assurt(len(branches) == 1)
            the_branch = branches[0]
            if not the_branch.can_view():
               log.warning(
                  'send_email_: user cannot access leafy branch: %s / %s'
                  % (self.username, branch_id,))
               access_ok = False
         parent_branches = branch_hier[1:]
         for parent in parent_branches:
            branches = branch.Many()
            branches.search_by_stack_id(parent[0], branch_qb)
            if branches:
               g.assurt(len(branches) == 1)
               if not branches[0].can_view():
                  log.warning(
                     'send_email_: user cannot access parent branch: %s / %s'
                     % (self.username, branches[0].stack_id,))
                  access_ok = False

         if (the_branch is None) or (not access_ok):
            branch_qb = None
         self.branch_qbs[branch_id] = (branch_qb, the_branch,)

         log.debug('get_qb_for_branch: new qb: user: %s / branch_id: %s / %s'
                   % (self.username, branch_id, branch_qb,))

      return (branch_qb, the_branch,)

   #
   def hydrate_rev_for_user(self, qb, rev_id):

      try:

         rev_row = self.user_grevs[rev_id]
         log.debug('hydrate_rev_for_user: existing rev: user: %s / rev_id: %s'
                   % (self.username, rev_id,))

      except KeyError:

         qb.filters.rev_ids = [rev_id,]
         grevs = group_revision.Many()
         grev_sql = grevs.sql_context_user(qb)
         #res = qb.db.sql(grev_sql)
         #rev_rows = {}
         #for row in res:
         #   rev_rows[row['revision_id']] = row
         rev_res = qb.db.table_to_dom('revision', grev_sql)
         qb.filters.rev_ids = []

         if rev_res:
            g.assurt(len(rev_res) == 1)
            rev_row = rev_res[0]
            self.user_grevs[row.get('id')] = rev_row
            log.debug('hydrate_rev_for_user: loaded rev: user: %s / rev_id: %s'
                      % (self.username, rev_id,))
         else:
            rev_row = None
            log.warning('hydrate_rev_for_user: no rev: user: %s / rev_id: %s'
                        % (self.username, rev_id,))

      return rev_row

   #
   def hydrate_revs_for_user(self, qb, rev_ids):

      # We could avoid SQL and look in self.user_grevs to see if we've already
      # fetched any of the requested revisions, but that code seems tedious
      # and complex; it's easier just to maybe check out the save revs twice.

      qb.filters.rev_ids = rev_ids
      grevs = group_revision.Many()
      grev_sql = grevs.sql_context_user(qb)
      res = qb.db.sql(grev_sql)
      rev_rows = {}
      for row in res:
         rev_rows[row['revision_id']] = row
      #rev_res = qb.db.table_to_dom('revision', grev_sql)
      qb.filters.rev_ids = []

      # See if the user cannot see any of the revisions.
      okay_rids = set(rev_rows.keys())
      hidden_rids = set(rev_ids).difference(okay_rids)
      if hidden_rids:
         # E.g., route reaction at a private revision ID is not
         # wrong, it's just the way things work (that is, if the last map
         # save was a private revision, and then someone else gets a route,
         # the route will have the private revision ID).
         log.debug('send_email_: user cannot access rids: %s / %s'
                   % (self.username, hidden_rids,))
         for rid in hidden_rids:
            # Set the row to None so the caller knows what's hidden.
            rev_rows[rid] = None

      return rev_rows

   #
   @staticmethod
   def finalize_alerts(msgng_ids, username):

      g.assurt(msgng_ids)

      Watcher_Composer.emailed_usernames.add(username)

      msgng_ids_str = ','.join([str(x) for x in msgng_ids])

      rows_updated = 0

      if not DEV_SKIP_UPDATE_ITEM_EVENT_ALERT:

         # Getting a new database connection is expensive and not something
         # you'd want to do a lot if it can be avoided, but we want to commit
         # to the database and remember that we just emailed a user, in case
         # the code fails while processing the next email (so that when the
         # script is restarted, we don't send duplicate emails).
         db = db_glue.new()
         db.transaction_begin_rw()
         update_sql = (
            """
            UPDATE item_event_alert
               SET date_alerted = NOW()
             WHERE (date_alerted IS NULL)
               AND (messaging_id IN (%s))
            """ % (msgng_ids_str,))
         db.sql(update_sql)
         log.debug(
            'finalize_alerts: date_alerted: given: %s / updated: %d / user: %s'
            % (len(msgng_ids), db.curs.rowcount, username,))
         db.transaction_commit()

         rows_updated = db.curs.rowcount

      return rows_updated

   #
   def send_onesie(self, to_username, to_email_addy, unsubscribe_proof,
                   unsubscribe_link, email_subject, msg_text, msg_html):

      the_msg = Emailer.compose_email(
         conf.mail_from_addr,
         to_username,
         to_email_addy,
         unsubscribe_proof,
         unsubscribe_link,
         email_subject,
         msg_text,
         msg_html)

      Emailer.send_email(
         [to_email_addy,],
         the_msg,
         prog_log=None,
         delay_time=None,
         dont_shake=None)

   # *** Helpers for MSG_TYPE_WITHIN, MSG_TYPE_DIRECT, MSG_TYPE_THREAD

   #
   def coalesce_edit_event(self, msgng_id, msg_type_id, branch_id,
                                 latest_rid, item_stack_id):

      self.edit_branch.setdefault(branch_id, dict())
      self.edit_branch[branch_id].setdefault(latest_rid, dict())
      self.edit_branch[branch_id][latest_rid].setdefault(msg_type_id, set())
      self.edit_branch[branch_id][latest_rid][msg_type_id].add(item_stack_id)

      self.rids_branch.add(latest_rid)

      self.msg_ids_branch.add(msgng_id)

      self.n_itm_ev += 1

   #
   def coalesce_thread_event(self, msgng_id, msg_type_id, branch_id,
                                   latest_rid, item_stack_id):

      self.edit_thread.setdefault(branch_id, dict())
      self.edit_thread[branch_id].setdefault(latest_rid, set())
      self.edit_thread[branch_id][latest_rid].setdefault(msg_type_id, set())
      self.edit_thread[branch_id][latest_rid][msg_type_id].add(item_stack_id)

      self.rids_thread.add(latest_rid)

      self.msg_ids_thread.add(msgng_id)

      self.n_thd_ev += 1

   #
   def emails_send_coalesced_events(self):

      if self.edit_branch:
         self.email_send_coalesced_branch_events()
      if self.edit_thread:
         self.email_send_coalesced_thread_events()
      else:
         log.debug(
            'emails_send_coalesced_events: Skipping: no events: user: %s'
            % (self.username,))

   #
   def email_send_coalesced_branch_events(self):

      composed = self.compose_email_parts(
         Watcher_Parts_Map_Edit, self.edit_branch, self.rids_branch)

      if composed:
         self.branch_change_email_send()

      Watcher_Composer.finalize_alerts(self.msg_ids_branch, self.username)

   #
   def email_send_coalesced_thread_events(self):

      self.compose_email_parts(
         Watcher_Parts_New_Post, self.edit_thread, self.rids_thread)

      if composed:
         self.thread_change_email_send()

      Watcher_Composer.finalize_alerts(self.msg_ids_thread, self.username)

   # *** Helpers for coalescing multiple events into one email

   #
   def compose_email_parts(self, watcher_parts_class, edit_lookup,
                                 rids_lookup):

#      import rpdb2;rpdb2.start_embedded_debugger('password',fAllowRemote=True)
#      conf.break_here('ccpv3')

      n_events = 0

      all_parts = watcher_parts_class()
      all_parts.compose_email_header(self)

      branch_ids = edit_lookup.keys()
      branch_ids.sort()

      for branch_id in branch_ids:

         # Check permissions on branch hierarchy and get qb if user is authed.
         qb, the_branch = self.get_qb_for_branch(branch_id)

         if qb is None:
            log.warning('compose_email_parts: unathed branch for user: %s / %s'
                        % (self.username, branch_id,))
            continue

         n_br_parts = 0
         branch_parts = None

         # Get the list of revisions the user can see.
         # The lookup is a set, so convert to list.
         rev_rows = self.hydrate_revs_for_user(qb, list(rids_lookup))

         # Within each branch details in the email, sort first by revision.

         sorted_rids = rev_rows.keys()
         sorted_rids.sort(reverse=False)

         for rev_rid in sorted_rids:

            rev_row = rev_rows[rev_rid]

#            conf.break_here('ccpv3')

            n_rev_parts = 0
            rev_parts = watcher_parts_class()
            rev_parts.compose_email_revision(rev_rid, rev_row)

            msg_type_ids = edit_lookup[branch_id][rev_rid].keys()
            for msg_type_id in msg_type_ids:
               added_event = self.compose_events_branch(
                  qb, rev_parts, branch_id, rev_rid, msg_type_id, edit_lookup)
               if added_event:
                  n_rev_parts += 1
                  n_events += 1

            # end: for msg_type_id in edit_lookup[branch_id]['typs']

            if n_rev_parts:
               if branch_parts is None:
                  branch_parts = watcher_parts_class()
                  branch_parts.compose_email_branch(the_branch)
               branch_parts.combine(rev_parts)
               n_br_parts += 1

         # end: for rev_rid in sorted_rids

         if n_br_parts:
            all_parts.combine(branch_parts)
            #n_all_parts += 1

      # end: for branch_id in branch_ids

      all_parts.compose_email_footer(self)

#      conf.break_here('ccpv3')

      self.msg_text = all_parts.msg_text
      self.msg_html = all_parts.msg_html

      if n_events:
         log.debug(
           'compose_email_parts: itm evts for user: %s / nevts: %d / nraw: %d'
            % (self.username, n_events, self.n_itm_ev,))
      else:
         log.debug(
            'compose_email_parts: no itm evts for user: %s / no. raw: %d'
            % (self.username, self.n_itm_ev,))


      return (n_events > 0)

   #
   def compose_events_branch(self, qb, rev_parts, branch_id, rid, msg_type_id,
                                   edit_lookup):

      added_event = False

#      conf.break_here('ccpv3')

      sids = edit_lookup[branch_id][rid][msg_type_id]

      qb.filters.only_stack_ids = ','.join([str(x) for x in sids])
      qb.filters.force_resolve_item_type = True
      qb.filters.include_item_stack = True
      items_fetched = item_user_access.Many()
      #items_fetched.search_get_items(qb)
      items_fetched.search_for_items(qb)
      qb.filters.only_stack_ids = ''
      qb.filters.force_resolve_item_type = False
      qb.filters.include_item_stack = False

      if items_fetched:
         if len(items_fetched) != len(sids):
            log.warning(
               'compose_events_branch: fewer found: user: %s / sids: %s / %s'
               % (self.username, sids, len(items_fetched) - len(sids),))
         rev_parts.compose_email_msg_type(msg_type_id)
         rev_parts.compose_email_item_list(
                  qb, msg_type_id, items_fetched)
         added_event = True
      else:
         log.warning(
            'compose_events_branch: nothing found: user: %s / sids: %s'
            % (self.username, sids,))

      return added_event

   # *** Helpers for MSG_TYPE_WITHIN and MSG_TYPE_DIRECT

   #
   def branch_change_email_send(self):

      timeliness = ''
      if self.service_delay == Watcher_Frequency.immediately:
         timeliness = 'within the last few minutes'
      elif self.service_delay == Watcher_Frequency.daily:
         timeliness = 'since yesterday'
      elif self.service_delay == Watcher_Frequency.weekly:
         timeliness = 'since last week'
      elif self.service_delay == Watcher_Frequency.nightly:
         timeliness = 'since last night'
      elif self.service_delay == Watcher_Frequency.morningly:
         timeliness = 'since yesterday morning'
      else:
         # Watcher_Frequency.never, .ripens_at, or unknown.
         timeliness = 'recently'
         log.error('Unknown service_delay: %s' % (self.service_delay,))

      email_subject = 'Cyclopath notice: Changes %s' % (timeliness,)

      self.send_onesie(self.username,
                       self.email_addy,
                       self.unsubscribe_proof,
                       self.unsubscribe_link,
                       email_subject,
                       self.msg_text,
                       self.msg_html)

   # *** Helpers for MSG_TYPE_THREAD

   #
   def thread_change_email_send(self):

      email_subject = 'Cyclopath notice: New posts in thread(s) you watch'

      self.send_onesie(self.username,
                       self.email_addy,
                       self.unsubscribe_proof,
                       self.unsubscribe_link,
                       email_subject,
                       self.msg_text,
                       self.msg_html)

   # *** Helpers for MSG_TYPE_REV_FEEDBACK

   #
   def email_send_rev_feedback(self, msgng_id, branch_id, latest_rid,
                                     item_stack_id, notifier_dat):

      # The pickled structure is structured thusly:
      # [0]: The one writing the feedback.
      # [1]: The ones being fedback.
      # [2]: The revision IDs.
      rvt_dat = cPickle.loads(notifier_dat)
      feedbacker = rvt_dat[0]
      feedbackees = rvt_dat[1]
      revision_ids = rvt_dat[2]

      qb, the_branch = self.get_qb_for_branch(branch_id)

      if qb is not None:

         rev_rows = self.hydrate_revs_for_user(qb, revision_ids)

         posts = post.Many()
         posts.search_by_stack_id(item_stack_id, qb)
         if len(posts) > 0:
            g.assurt(len(posts) == 1)
            the_post = posts[0]
         else:
            the_post = None
            log.warning('email_send_rev_feedback: cannot see post: %s / %s'
                        % (qb.username, item_stack_id,))

         if the_post is not None:
            threads = thread.Many()
            threads.search_by_stack_id(the_post.thread_stack_id, qb)
            if len(threads) > 0:
               g.assurt(len(threads) == 1)
               the_thread = threads[0]

               if feedbacker != the_post.created_user:
                  log.warning('_send_rev_fb: unexpected: fber: %s / poster: %s'
                              % (feedbacker, the_post.created_user,))
               if the_post.created_user != the_post.edited_user:
                  log.warning('_send_rev_fb: weird: cr_usr: %s / ed_usr: %s'
                              % (the_post.created_user, the_post.edited_user,))
               # 2014.07.02: FIXME: test changes to what_username:
               u_feedbacker = User.what_username([the_post.edited_user,
                                                  the_post.edited_host,
                                                  the_post.edited_addr,])

               email_subject = 'Cyclopath notice: %s' % (thread.title,)

               link_uri = ('http://%s/#discussion?thread_id=%d'
                           % (conf.server_name, the_thread.stack_id,))

               msg_text = (
'''Another Cyclopath user wrote feedback about one or more revisions,
including at least one that you made.

Feedback by: %s
On revision(s): %s
+-----
%s
+-----

This feedback also begins a discussion thread in Cyclopath. Please
participate by clicking the following link:

%s
''' % (u_feedbacker,
       ', '.join([str(x) for x in revision_ids]),
       the_post.body,
       link_uri,))

               msg_html = (
'''<p>
Another Cyclopath user wrote feedback about one or more revisions,
including at least one that you made.
</p>

<p>
Feedback by: %s
<br/>
On revision(s): %s
<br/>
+-----
<br/>
%s
<br/>
+-----
<br/>
</p>

<p>
This feedback also begins a discussion thread in Cyclopath. Please
participate by clicking the following link:
</p>

<p>
<a href="%s">%s</a>
</p>
''' % (u_feedbacker,
       ', '.join([str(x) for x in revision_ids]),
       the_post.body,
       conf.server_name,
       the_thread.stack_id,
       link_uri,
       link_uri,))

      self.send_onesie(self.username,
                       self.email_addy,
                       self.unsubscribe_proof,
                       self.unsubscribe_link,
                       email_subject,
                       msg_text,
                       msg_html)

      Watcher_Composer.finalize_alerts([msgng_id,], self.username)

   # *** Helpers for MSG_TYPE_REV_REVERT

   #
   def email_send_rev_revert(self, msgng_id, branch_id, latest_rid,
                                   item_stack_id, notifier_dat):

# BUG_FALL_2013: Test this... which'll happen we rev revert is fixed.

      reverted_revs = cPickle.loads(notifier_dat)

      qb, the_branch = self.get_qb_for_branch(branch_id)
      if qb is not None:
         rev_row = self.hydrate_rev_for_user(qb, latest_rid)
         if rev_row is not None:

            email_subject = 'Cyclopath notice: your revision was reverted'

            msg_text = (
'''Another Cyclopath user reverted one or more revisions, including
at least one that you made.

Revert by: %s
On revision(s): %s
Changelog: %s

You can review the new revision by logging on to Cyclopath at
 %s
Click 'Activity' in the left column and then click 'Revisions'
to see the complete revision history for the map.

You are receiving this email because you saved a revision in Cyclopath
and asked to be notified if another user reverted it. Please email
%s if you have any questions.

''' % (rev_row['username'],
       ', '.join([str(x) for x in reverted_revs]),
       rev_row['comment'],
       conf.server_name,
       conf.mail_from_addr,))

            msg_text = (
'''<p>
Another Cyclopath user reverted one or more revisions, including
at least one that you made.
</p>

<p>
Revert by: %s
<br/>
On revision(s): %s
<br/>
Changelog: %s
</p>

<p>
You can review the new revision by logging on to Cyclopath at
 <a href="%s">%s
Click 'Activity' in the left column and then click 'Revisions'
to see the complete revision history for the map.
</p>

<p>
You are receiving this email because you saved a revision in Cyclopath
and asked to be notified if another user reverted it. Please email
<a href="mailto:%s">%s</a> if you have any questions.
</p>
''' % (rev_row['username'],
       ', '.join([str(x) for x in reverted_revs]),
       rev_row['comment'],
       conf.server_name,
       conf.server_name,
       conf.mail_from_addr,
       conf.mail_from_addr,))

            self.send_onesie(self.username,
                             self.email_addy,
                             self.unsubscribe_proof,
                             self.unsubscribe_link,
                             email_subject,
                             msg_text,
                             msg_html)

      Watcher_Composer.finalize_alerts([msgng_id,], self.username)

   # *** Helpers for MSG_TYPE_RTE_REACTION

   #
   def email_send_rte_reaction(self, msgng_id, branch_id, latest_rid,
                                     item_stack_id, notifier_dat):

      qb, the_branch = self.get_qb_for_branch(branch_id)
      if qb is not None:
         rev_row = self.hydrate_rev_for_user(qb, latest_rid)
         if rev_row is not None:

            # Fetch the route.
            routes = route.Many()
            qb.filters.include_item_stack = True
            routes.search_by_stack_id(stack_id, qb)
            qb.filters.include_item_stack = False

            if len(routes):
               g.assurt(len(routes) == 1)

               route = routes[0]

               # Compose the email.
               email_subject = 'Cyclopath Reminder: Share your route reaction'

               route_link = ('http://%s/#route_shared?id=%s'
                             % (conf.server_name,
                                route.stealth_secret,))

               msg_text = (
'''Hi, %s,

You found a route on Cyclopath and asked us to remind you about it.

Route name: %s
Requested on: %s

To share your reaction about the route you requested, please visit this link:

%s

Thank you for sharing your experience with the Cyclopath community!
''' % (self.username,
       route.name,
       route.created_date,
       route_link,)) 

               msg_html = (
'''
<p>
Hi, %s,
</p>

<p>
You found a route on Cyclopath and asked us to remind you about it.
</p>

<p>
Route name: %s
<br/>
Requested on: %s
</p>

<p>
To share your reaction about the route you requested, please visit this link:
</p>

<p>
<a href="%s">%s</a>
</p>

<p>
Thank you for sharing your experience with the Cyclopath community!
</p>
''' % (self.username,
       route.name,
       route.created_date,
       route_link,))

            self.send_onesie(self.username,
                             self.email_addy,
                             self.unsubscribe_proof,
                             self.unsubscribe_link,
                             email_subject,
                             msg_text,
                             msg_html)

      Watcher_Composer.finalize_alerts([msgng_id,], self.username)

   # *** Helpers for MSG_TYPE_RTE_FEEDBACK

   #  #
   #  def email_send_rte_feedback(self, msgng_id, branch_id, latest_rid,
   #                                    item_stack_id, notifier_dat):
   #     qb, the_branch = self.get_qb_for_branch(branch_id)
   #     if qb is not None:
   #        rev_row = self.hydrate_rev_for_user(qb, latest_rid)
   #        if rev_row is not None:
   #           pass # BUG nnnn: IMPLEMENT
   #                #  See comments in Watcher_Parts_Base, where
   #                #  MSG_TYPE_RTE_FEEDBACK is defined.
   #     Watcher_Composer.finalize_alerts([msgng_id,], self.username)

   # ***

# ***

