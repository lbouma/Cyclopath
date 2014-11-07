# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The Revert request reverts the given revisions.

import os
import sys

import conf
import g

from grax.item_manager import Item_Manager
from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_versioned
from item.feat import byway
from item.util import revision
from util_ import strutil

log = g.log.getLogger('cmd.rev_revert')

# ***

"""

BUG_FALL_2013

user sends list of revision IDs

get list of revisions user can see...

for each revision,

   get raw list of stack IDs

   reduce list via item_user_access.Many()
   and add TEST_ME: Save new public item and new private item,
                    then log out and revert the revision: just
                    the public item should be reverted, and the
                    revision should be marked partially deleted...
                    or maybe group_revision needs a reverted column, too.

only problem is private link_value where
 attc or feat gets reverted?




"""


class Op_Handler(command.Op_Handler):

   __slots__ = (
      'changenote',
      'revs',
      'users',
      'rev_users',
      'revs_str',
# FIXME: route manip 2. this is wrong.
      'revs_batched', # {permission: {rids: [], visibility: W}}
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.changenote = None
      self.revs = None
      self.users = None
      self.rev_users = None
      self.revs_str = None
      self.revs_batched = None

   # ***

   #
   def __str__(self):
      selfie = (
         'revisn_revert: changenote: %s / revs: %s / users: %s / %s / %s / %s'
         % (self.changenote,
            self.revs,
            self.users,
            self.rev_users,
            self.revs_str,
            self.revs_batched,))
      return selfie

   # *** Request processing overrides

   #
   def decode_request(self):

      command.Op_Handler.decode_request(self)

      # User cannot revert if banned publicly.
      if self.user_client_ban.is_banned():
         raise GWIS_Warning('Cannot revert revisions while banned')

      # Look for the changenote.
      # MAYBE: Do we ensure this is always set?
      self.changenote = self.req.doc_in.find('metadata/changenote').text

      # Load the GWIS.
      revs_vals = self.decode_key('revs', None)
      if not revs_vals:
         raise GWIS_Error('Missing mandatory param: revs')
      try:
         self.revs = [int(r) for r in revs_vals.split(',')]
      except ValueError:
         raise GWIS_Warning(
            'Cannot revert revisions: param "revs" is not csv integers: %s' 
            % (revs_vals,))
      #self.revs_str = "(%s)" % (','.join([str(rid) for rid in self.revs]),)

      # Anonymous users can only revert one revision at a time.
      # MAYBE: Make this a conf option. Maybe anons can't revert.
      if ((self.req.client.username == conf.anonymous_username)
          and (len(self.revs) > 1)):
         raise GWIS_Warning(
            'Anonymous users cannot revert more than 1 revision.')

   #
   def fetch_n_save(self):

      command.Op_Handler.fetch_n_save(self)

      qb = self.req.as_iqb()

      # Limit to just the leaf branch, so we only return its revisions.
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1

      grevs_sql_all = grevs.sql_context_user(qb)

      qb.filters.rev_ids = self.revs

      grevs_sql_all = grevs.sql_context_user(qb)

# FIXME: Test via ccp.py?
#      import pdb;pdb.set_trace()
#      conf.break_here('ccpv3')
      import rpdb2;rpdb2.start_embedded_debugger('password',fAllowRemote=True)

      g.assurt(False) # FIXME/BUG nnnn: Reimplement this command.

      #results = qb.db.table_to_dom('revision', grevs_sql_all)
      rows = qb.db.sql(grevs_sql_all)


      self.users = set([(row['username'] or row['host']) for row in res])
      self.rev_users = [
            (row['id'], row['username'] or row['host'],) for row in res]
      self.revs_batched = dict()
      # convert revision rows into revisions batched by permission level
      # additionally, verify ownership/permission to revert while iterating
      g.assurt(False) # Update this to CcpV2...
      for row in res:
         if ((row['permission'] != p.public)
             and ((self.req.client.username == conf.anonymous_username)
                  or (self.req.client.username != row['username']))):
            raise GWIS_Error(
               'You do not have permission to revert the desired revision.')
         
         if (row['permission'] not in self.revs_batched):
            batch = {'rids': list(), 'visibility': v.noone}
            self.revs_batched[row['permission']] = batch
         else:
            batch = self.revs_batched[row['permission']]

         batch['rids'].append(row['id'])
         if (row['visibility'] < batch['visibility']):
            batch['visibility'] = row['visibility']

      # Cannot revert system accounts' work.
      # TEST_ME: The client should not allow this to happen.
      # MAGIC_NUMBER: '_' means startswith(conf.system_username_prefix)
      if len([u for u in self.users if (u[0] == '_')]) > 0:
         # BUG nnnn: Do we prevent user's from opening accts beginning with
         #           an underscore?
         raise GWIS_Warning('%s%s' 
            % ('Cannot revert revisions made by system accounts ',
               '(username starts with "_" character).',))

      # User cannot revert work by too many people.
      # EXPLAIN: Is this number based on research? So logged on users can
      # delete, e.g., 50 revisions, so long as they're all made by the same
      # one, two, or three users? Seems arbitrary... like many numbers we use.
      if len(self.users) > 3:
         raise GWIS_Warning(
            'Cannot revert revisions by more than 3 people at once')

      # ***

      # BUG 2688: Use transaction_retryable? [lb] thinks we're okay so long
      #           as we get the revision table lock.

      indeliberate = not self.qb.cp_maint_lock_owner
      revision.Revision.revision_lock_dance(
         self.req.db, caller='revision_revert.py', indeliberate=indeliberate)

      # Cannot revert if already reverted. This rejects reverts which revert
      # ANY already-reverted revisions. One could argue that only reverts
      # which revert ONLY already-reverted revisions should be rejected
      # (filtering out the already-reverted revisions). Perhaps this is true,
      # but this is easier to implement and it's not unreasonable.
      # FIXME Why is this commented out?
      #rows = self.req.db.sql("""SELECT rid_victim FROM revert_event
      #                          WHERE rid_victim IN %s""" % (self.revs_str))
      #if (len(rows) > 0):
      #   raise GWIS_Warning(
      #      "Can't revert revision(s) %s: already reverted."
      #      % ','.join([str(row['rid_victim']) for row in rows]))

      # FIXME: Use revision_peek...
      rid = revision.Revision.revision_create(self.req.db)

# FIXME: 2011.04.04 In V1/Route Analytics branch, revert byway delete fails
# because of phantom column in colorado.byway_segment that's not in 
# minnesota.byway_segment. merged_to_id is the column. I tried 
# 'minnesota.byway_segment' but that didn't work.
      for table in ([
            'annot_bs', # Fixme...
            'annotation',
            'tag_bs', # ...
            'tag_point',
            'tag_region',
            'terrain',
            'byway_segment',
            'point',
            'region',
            'route',
            ]):
         self.revert(table, rid)
# FIXME: route manip 2 does this:
#         self.revert(table, rid, self.revs_batched[perm]['rids'])

# FIXME link_lhs_type_id? link_rhs_type_id? 
      for (attc_type, feat_type,) in ([
            ('annotation', None),
            ('annotation', 'byway'),
            ('annotation', 'region'),
            ('annotation', 'waypoint'),
            ('attribute', None),
            ('attribute', 'byway'),
            ('attribute', 'region'),
            ('attribute', 'waypoint'),
            # NOTE: Skipping ('post', *),
            # NOTE: Skipping ('tag', None),
            ('tag', 'byway'),
            ('tag', 'region'),
            ('tag', 'waypoint'),
            # NOTE: Skipping ('thread', *),
            ('byway', None),
            ('region', None),
            ('terrain', None),
            ('waypoint', None),
            # NOTE: Skipping ('region_watched', *),
            # NOTE: Skipping (*, 'region_watched'),
            ]):
#FIXME: new revert params
# FIXME yar, this is currently wrong
         self.revert(rid, attc_type, feat_type)
# FIXME: route manip 2 does this:
#         self.revert(table, rid, self.revs_batched[perm]['rids'])

      self.byway_ratings_update(rid)

# FIXME: route manip 2 does this:
# FIXME: coupling. this does not belong here?
#      self.route_steps_update(rid, self.revs_batched[perm]['rids'])

      self.revert_log(rid)
# FIXME: route manip 2 does this:
#      self.revert_log(rid, perm)

      host = self.req.client.remote_host_or_remote_ip()



# BUG_FALL_2013:
#
# first search with group_revision.Many() using qb.filters.
#
#         qb.filters.rev_ids = list(self.branches[branch_id]['rids'])
#         grevs = group_revision.Many()
#         grev_sql = grevs.sql_context_user(qb)
#         res = qb.db.sql(grev_sql)
#         rev_rows = {}
#         for row in res:
#            rev_rows[row['revision_id']] = row
#         qb.filters.rev_ids = []
#
# and then for each group_revision, get a raw list of stack IDs
# then search on those stack IDs for the user
# - if count matches, group_revision is revertable
# - if count is lower, some items can be reverted.
# add okay stack IDs to collection
# repeat for each group_revision
#  (maybe reduce list of stack IDs as you progress?)
# finally, for each stack ID, do the brute-force revert?
# what about grac records, or stack IDs that are not items?
# maybe you should restrict search by item type -- YES
# you have to join item class against stack ids to get subset
#  of IDs, so that when you brute-force item_versioned, you
#  don't scoop up, e.g., work items.
# But what about item watchers? You won't have permissions...
#  but an item watcher is also acl_grouping aware, so, it's
#  not a revisiony item. Argh... so how do you revert link_values?
#  This is where separate group revisions being listed makes sense:
#   the private link_value should just be attached to the user's
#   private group_revision... which probably is broken... I don't know if
#   commit.py calculates the visible_items count so well...
#
# start with item_versioned, move outward, and how do you truly indicate
# reverted? i think if you have same group_id as group_revision then just
# do it...
#
#
# for each revision being deleted
#  get group_revisions for 
# get group_revisions for each revision being deleted
#  for each group stack id, check if user is member
#   if user is member, use qb with just that group sid and get rev sids
#    
#
#  user's group stack id, match 
#




      # FIXME: for now all revisions will be saved as public. Once revisions
      # of other permissions exist, gwis.command.revert must be modified to use
      # correct permisions.
      # FIXME: Populate groups_ids, or make revision_save populate
      groups_ids = None # []
      # FIXME: Update reverted_count
      #        or replace with something in group_revision...
      #         e.g., add public item and private item, save, log out, revert,
      #               then log in and what do/should you see?
      #               revision reverted? partially reverted? add your
      #               group_revision to the list, so break out by
      #               group_revision?
      #
      #    revision.count_group_revisions
      #    revision.count_group_reverts
      #    group_revision.reverted BOOLEAN
      #
      #    but then again, user might not have save group access?
      #
      # shoot: what about acl_grouping?
      # item_watcher should not be reverted...
      # routes should not be reverted... nor their item_versioneds...
      # so the stack ID search must come via each item type we care about
      #
      #
      #          
      # FIXME: Verify revision_save, I'm not sure if it should work exactly the
      #        same for revision_revert as it does for commit.

# FIXME: processed_items?
#      processed_items = None


# BUG_FALL_2013: Pass list of rev committers to be emailed if they so
# desired... and make item_event_alerts

      Item_Manager.revision_save(

# FIXME: now it's a qb
#        self.req.db,
         qb,
         rid,
         self.req.branch.branch_hier,
         host, 
         self.req.client.username,

         # We mung the changenote a bit: encapsulate the user's message within
         # an enclosing structure.
         ('Revert: "%s" (revision %s)'
          % (self.changenote, self.revs_string())),

         groups_ids,

         # FIXME: Wait, reverting user should be able to ask to be alerted if
         #        their revert is re-reverted, re-right?
         #        Meaning, flashclient should show dialog for activate_alerts
         #        (revert.alert_on_activity) so user can choose.
         activate_alerts=False,

         # The processed_items param is used to alert on revision_feedback.
         # So leave it blank.
         processed_items=None,

         # Make events for users whose revisions were deleted.
reverted_revs=[], # FIXME: Send list of reverts.

         skip_geometry_calc=False)
      # Skipping: qb?.item_mgr.finalize_seq_vals(self.req.db)

# FIXME: route manip 2 does this:
#         viz = self.revs_batched[perm]['visibility']
#         self.req.db.revision_save(rid, perm, viz, host, 
#                                   self.req.client.username,
#                                   ('Revert: %s (revision %s)'
#                                    % (self.changenote, self.revs_string())))


# FIXME: route manip 2. this is the end of the for: statement
#                      (for perm in self.revs_batched)

      self.req.db.transaction_commit()
      self.routed_hup(self.req.db)

   ## Helper methods

   #
   def byway_ratings_update(self, rid):
      # fetch byways affected by this revert
#FIXME: iv_gf_cur_byway and other iv_* views no longer exist
#       use group_item_access instead
      g.assurt(False)
      rows = self.req.db.sql(
         """
         SELECT
            stack_id,
            value AS rating_value
         FROM
            iv_gf_cur_byway bc
         LEFT OUTER JOIN byway_rating br
            ON (bc.stack_id = br.byway_stack_id
                AND br.username = %s)
         WHERE
            bc.valid_start_rid = %s
         """, (conf.generic_rater_username, rid,))
      for row in rows:
         # FIXME: Hack - put in a fake generic byway rating, if needed
         # (Postgres does not have INSERT IF NOT EXISTS, hence the join
         # above). This is needed because generic_rating_update() uses
         # byway.search(), which joins against byway_rating. So if there's no
         # generic rating on the block, this will find nothing and no generic
         # rating will be created - a catch-22. Thus, this lame-o hack
         # (recorded in bug 1700).
         if (row['rating_value'] is None):
            self.req.db.sql(
               """
FIXME: add branch_id

               INSERT INTO byway_rating
                  (byway_stack_id, value, username)
               VALUES (%s, -1, %s)
               """, (row['stack_id'],
                     conf.generic_rater_username,))

# FIXME: Need qb object
         #byway.One.generic_rating_update(
         #   int(row['id']), self.req.db, self.req.branch.branch_hier)
         # FIXME: This fcn. is deprecated.
         byway.One.generic_rating_update(qb, int(row['id']))

# FIXME: route manip 2. to_revert is new
   #
   def revert(self, table, rid, to_revert):
      'Revert the given table.'
      # FIXME: handle extra attributes, such as route_steps for the route table

      revs_str = strutil.sql_in_integers(to_revert)
      id_where = ("(id IN (SELECT id FROM %s WHERE valid_start_rid IN %s))"
#                  % (table, self.revs_str))
                  % (table, revs_str))
#      rev_last_unreverted = min(self.revs) - 1
      rev_last_unreverted = min(to_revert) - 1
#      revs_str = self.revs_str  # so it's available in locals()

      # Add some stuff to locals()
      revs_str = self.revs_str
      rid_inf = conf.rid_inf

# BUG nnnn: The following SQL (in CcpV1, too?) blindly closes the latest
# versions of items -- but we if these items had been edited since?? The
# revert should cause a branch conflict!
      g.assurt(False)
      # close the current versions
      self.req.db.sql(
         """
         UPDATE
            %(table)s
         SET
            valid_until_rid = %(rid)d
         WHERE
            %(id_where)s
            AND valid_until_rid = %(rid_inf)d
         """ % locals())

      # get column list
      cols = self.req.db.table_columns(table)
      cols.remove('version')
      cols.remove('valid_start_rid')
      cols.remove('valid_until_rid')

      # copy the old versions to be current.
      # old version = the one that was current in revision r-1 where r is the
      # earliest reverted revision.
      cstr = ','.join(cols)

      log.debug('reverting %s / %s' % (table, cstr,))

      self.req.db.sql(
         """
         INSERT INTO %(table)s
            (version, valid_start_rid, valid_until_rid, %(cstr)s)
         SELECT
            (SELECT max(version) + 1 FROM %(table)s inn WHERE inn.id = out.id),
            %(rid)d,
            %(rid_inf)d,
            %(cstr)s
         FROM %(table)s out
         WHERE
            %(id_where)s
            AND version = (
               SELECT version FROM %(table)s inn
               WHERE
                  inn.id = out.id
                  AND valid_start_rid <= %(rev_last_unreverted)d
                  AND valid_until_rid > %(rev_last_unreverted)d)
         """ % locals())

      # Create deleted versions for features created by reverted revisions.
      cols.remove('deleted')
      cstr = ','.join(cols)
      # MAGIC_NUMBER: The reverted item's version is 2; old item is version 1.
      self.req.db.sql(
         """
         INSERT INTO %(table)s
            (version, valid_start_rid, valid_until_rid, deleted, %(cstr)s)
         SELECT
            (SELECT max(version) + 1 FROM %(table)s inn WHERE inn.id = out.id),
            %(rid)d,
            %(rid_inf)d,
            't',
            %(cstr)s
         FROM %(table)s out
         WHERE
             %(id_where)s
             AND version = 1
             AND valid_start_rid IN %(revs_str)s
         """ % locals())

   #
   def revert_log(self, rid_reverting, permission):
      'Log the revert event.'
      g.assurt(False) #  FIXME: route manip 2. permission
#      for rid_victim in self.revs:
      for rid_victim in self.revs_batched[permission]['rids']:
         self.req.db.sql(
            """
            INSERT INTO revert_event
               (rid_reverting, rid_victim)
            VALUES
               (%d, %d)
            """ % (rid_reverting, rid_victim,))

   #
   def revs_string(self):
      'Return a string describing my revisions.'

      def pack(a, next):
         g.assurt(next[0] == next[1])
         if (len(a) == 0):
            return [next]
         elif (a[-1][1] + 1 == next[0]):
            return a[:-1] + [(a[-1][0], next[0])]
         else:
            return a + [next]

      def s(tup):
         if (tup[0] == tup[1]):
            return str(tup[0])
         elif (tup[0] + 1 == tup[1]):
            return '%d,%d' % tup
         else:
            return '%d-%d' % tup
         
      results = []
      for user in self.users:
         ids = [(id_, id_) for (id_, u) in self.rev_users if (u == user)]
         ids = reduce(pack, ids, list())
         results.append('%s by %s' % (','.join([s(range_) for xrange_ in ids]),
                                      user))
      return '; '.join(results)

# FIXME: route manip 2.
# FIXME: coupling. this fcn. does not belong here.
   #
   def route_steps_update(self, rid, reverted_revs):
      # fetch route ids and deleted status from rid
      res = self.req.db.sql("""SELECT id, deleted, version FROM route
                               WHERE valid_starting_rid = %d""" % rid)
      rev_last_unreverted = min(reverted_revs) - 1
      
      for route in res:
         route_id = route['id']
         dst_version = route['version']
         
         if (not route['deleted']):
            # get the oldest unreverted version of the route, since that
            # was the source of the this route
            v_rows = self.req.db.sql("""
SELECT version FROM route
WHERE id = %(route_id)d
      AND valid_before_rid > %(rev_last_unreverted)d
      AND valid_starting_rid <= %(rev_last_unreverted)d""" % (locals()))
            src_version = v_rows[0]['version']
         else:
            # route represents the deletion of a route created in the
            # reverted revisions, so use the version just before this route
            src_version = dst_version - 1
            g.assurt(src_version >= 1)

         # copy all route_steps from src_version to dst_version
         route_step_cols = self.req.db.table_columns('route_step')
         route_step_cols.remove('route_version')
         cstr = ','.join(route_step_cols)
         
         self.req.db.sql("""
INSERT INTO route_step (route_version, %(cstr)s)
SELECT %(dst_version)d as route_version,
       %(cstr)s
FROM route_step
WHERE route_id = %(route_id)d
      AND route_version = %(src_version)d""" % (locals()))

# FIXME: This seems very simplistic... just copying rows?
         # Copy all route_stops from src_version to dst_version.
         route_stop_cols = self.req.db.table_columns('route_stop')
         route_stop_cols.remove('route_version')
         cstr = ','.join(route_stop_cols)

         self.req.db.sql("""
INSERT INTO route_stop (route_version, %(cstr)s)
SELECT %(dst_version)d as route_version,
       %(cstr)s
FROM route_stop
WHERE route_id = %(route_id)d
      AND route_version = %(src_version)d""" % (locals()))

   # ***

# ***

