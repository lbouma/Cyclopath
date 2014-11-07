# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from grax.access_level import Access_Level
from grax.library_squelch import Library_Squelch
from grax.user import User
from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from gwis.query_filters import Query_Filters
from item import item_user_access
from item.feat import route
from util_ import misc

log = g.log.getLogger('cmd.fdbl_put')

# This class updates item_findability. The user must have appropriate
# permissions to do what they're doing.
#
# MAYBE: Changes to this table are not revisioned.
#        Should we at least track changes, for research purposes?

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'item_stack_ids',
      'action_history_add',
      'action_history_chg',
      'action_squelch_pub',
      'action_squelch_usr',
      'use_all_in_history',
      'insert_values',
      'update_stack_ids',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      #
      self.item_stack_ids = None
      #
      # The client specifies one of these:
      self.action_history_add = None
      self.action_history_chg = None
      self.action_squelch_pub = None
      self.action_squelch_usr = None
      #
      self.use_all_in_history = False
      #
      self.insert_values = None
      self.update_stack_ids = None

   # ***

   #
   def __str__(self):
      selfie = (
  'itm_fbility_put: sids: %s / hist a/c: %s/%s / sql p/u: %s/%s / %s / %s / %s'
         % (self.item_stack_ids,
            self.action_history_add,
            self.action_history_chg,
            self.action_squelch_pub,
            self.action_squelch_usr,
            self.use_all_in_history,
            self.insert_values,
            self.update_stack_ids,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

      num_actions = 0
      #
      self.action_history_add = self.decode_key('hist_add', None)
      if self.action_history_add is not None:
         self.action_history_add = bool(int(self.action_history_add))
         num_actions += 1
      #
      self.action_history_chg = self.decode_key('hist_chg', None)
      if self.action_history_chg is not None:
         self.action_history_chg = bool(int(self.action_history_chg))
         num_actions += 1
      #
      self.action_squelch_pub = self.decode_key('sqel_pub', None)
      if self.action_squelch_pub is not None:
         self.action_squelch_pub = int(self.action_squelch_pub)
         num_actions += 1
      #
      self.action_squelch_usr = self.decode_key('sqel_usr', None)
      if self.action_squelch_usr is not None:
         self.action_squelch_usr = int(self.action_squelch_usr)
         num_actions += 1

      if num_actions != 1:
         raise GWIS_Error('Expecting one of action_history_add, etc.')

# BUG_FALL_2013: FIXME: This is not used. Is this a CcpV1 hangover?
#        I think this is the 'Clear All' button, right??
#        So we should probably implement this...
      self.use_all_in_history = bool(int(self.decode_key('fbil_hist', 0)))

      # NOTE: We'll make insert_values and update_stack_ids from 'fbil_sids'
      #       in fetch_n_save.

      # We don't expect that the user wants to apply squelch to the history
      # items (history items should just have hist_usr run on them). But
      # it's also not an error, is it?

   # BUG nnnn: When you Clear All from Routes I've Looked At, if there are
   # routes in routes_view but not saved to your library (i.e., no GIA records
   # for you to find them again), you should warn the user that some routes
   # will be lost forever.

   #
   def fetch_n_save(self):

      gwis_errs = []

      # Call parent's fcn., which calls Query_Overlord.prepare_filters() 
      # and initializes self.doc to etree.Element('data').
      command.Op_Handler.fetch_n_save(self)

      # Assemble the qb from the request.
      qb = self.req.as_iqb(addons=False)
      g.assurt(qb.filters == Query_Filters(None))

      # We set login_required so this should always be the case.
      g.assurt(self.req.client.username != conf.anonymous_username)
      g.assurt(qb.username == self.req.client.username)

      self.item_stack_ids = qb.filters.decode_ids_compact('./fbil_sids',
                                                          self.req.doc_in)
      if self.item_stack_ids and self.use_all_in_history:
         gwis_errs.append('Please specify only fbil_sids or all_hist.')

      items = item_user_access.Many()
      g.assurt(qb.sql_clauses is None)
      qb.sql_clauses = item_user_access.Many.sql_clauses_cols_all.clone()
      qb.filters.dont_load_feat_attcs = True
      qb.filters.min_access_level = Access_Level.denied

      if not self.item_stack_ids:
         g.assurt(self.use_all_in_history)
         stack_id_table_ref = 'temp_stack_id__item_findability'
         stack_ids_sql = (
            """
            SELECT
               stack_id
            INTO TEMPORARY TABLE
               %s
            FROM
               (SELECT
                  item_stack_id
                FROM
                  item_findability
                WHERE
                  (show_in_history IS TRUE)
                  AND (username = %s)) AS foo_ifp
            """ % (stack_id_table_ref,
                   qb.db.quoted(qb.username),))
         rows = qb.db.sql(stack_ids_sql)
         #
         qb.sql_clauses.inner.join += (
            """
            JOIN %s
               ON (gia.stack_id = %s.stack_id)
            """ % (stack_id_table_ref,
                   stack_id_table_ref,))
         check_exist = False
      else:
         id_count = self.item_stack_ids.count(',')
         if id_count > conf.constraint_sids_max:
            gwis_errs.append('Too many stack IDs in request: %d (max: %d).'
                             % (id_count, conf.constraint_sids_max,))
         else:
            qb.filters.only_stack_ids = self.item_stack_ids
         # We'll have to double-check if these records exist before updating.
         check_exist = True

      if True:

         items.search_for_items_clever(qb)

         if not items:
            log.warning('fetch_n_save: no findability items: %s'
                        % (str(qb.filters),))
            gwis_errs.append('No items were found to be findabilitied.')
         else:
            log.debug('fetch_n_save: no. item_findability: %d' % (len(items),))

         use_sids = []
         for itm in items:
            if ((self.action_squelch_pub is not None)
                or (self.action_squelch_usr is not None)):
               if itm.access_level_id <= Access_Level.arbiter:
                  log.debug('fetch_n_save: action_squelch: item: %s', itm)
                  use_sids.append(str(itm.stack_id))
               else:
                  gwis_errs.append('You must be arbiter to change squelch.')
            else:
               # self.action_history_add, self.action_history_chg
               if itm.access_level_id > Access_Level.viewer:
                  gwis_errs.append('Unknown item or access denied.')
               else:
                  log.debug('fetch_n_save: action_history: item: %s', itm)
                  use_sids.append(str(itm.stack_id))

         if not use_sids:

            gwis_errs.append('No items were found.')

         else:

            # use_sids = [ str(sid) for sid in use_sids ]
            self.update_stack_ids = ", ".join(use_sids)

            if check_exist:
               # Make a list of stack IDs to insert first, before updating.
               if ((self.action_history_add is not None)
                   or (self.action_history_chg is not None)):
                  username = qb.username
               elif self.action_squelch_pub is not None:
                  username = conf.anonymous_username
               else:
                  g.assurt(self.action_squelch_usr is not None)
                  username = qb.username
               user_id = User.user_id_from_username(qb.db, username)
               missing_sids_sql = (
                  """
                  SELECT
	                  DISTINCT(itmv.stack_id)
                  FROM
                     item_versioned AS itmv
                  LEFT OUTER JOIN
                     item_findability AS itmf
                     ON ((itmv.stack_id = itmf.item_stack_id)
                         AND (itmf.username = %s))
                  WHERE
                     (itmf.username IS NULL)
                     AND (itmv.stack_id IN (%s))
                  """ % (qb.db.quoted(username),
                         self.update_stack_ids,))
               rows = qb.db.sql(missing_sids_sql)
               log.debug('fetch_n_save: missing: %d'
                         % (len(missing_sids_sql),))
               value_objs = []
               for row in rows:
                  # These value objects match below:
                  #   INSERT INTO item_findability
                  #      (item_stack_id, username, user_id,
                  #       library_squelch, show_in_history, branch_id)
                  value_objs.append(
                     "(%d, '%s', %d, %d, %s, %d)"
                     % (row['stack_id'],
                        username,
                        user_id,
                        Library_Squelch.squelch_always_hide,
                        'FALSE',
                        qb.branch_hier[0][0],))
               self.insert_values = ", ".join(value_objs)

            success = qb.db.transaction_retryable(self.attempt_save, qb, qb)

            if not success:
               log.warning('fetch_n_save: failed!')

      if gwis_errs:
         err_str = ' / '.join(gwis_errs)
         log.debug('fetch_n_save: err_str: %s' % (err_str,))
         raise GWIS_Error(err_str)

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      (qb,) = args

      self.req.db.transaction_begin_rw()

      if self.action_squelch_pub is not None:
         username = conf.anonymous_username
      else:
         g.assurt(   (self.action_history_add is not None)
                  or (self.action_history_chg is not None)
                  or (self.action_squelch_usr is not None))
         username = qb.username

      # RENAME?: action_history_add is really just action_history_show
      if self.action_history_add is not None:
         # Just update the timestamp... and make sure the record exists, too.
         set_clause = ("show_in_history = TRUE")
      # EXPLAIN: Why do we need a toggle action?
      #          Shouldn't we just let the caller say on or off?
      # FIXME?: replace action_history_chg with action_history_hide?
      if self.action_history_chg is not None:
         set_clause = ("show_in_history = %s"
                       % ("TRUE" if self.action_history_chg else "FALSE",))

# FIXME: This seems wrong... there 
      if self.action_squelch_pub is not None:
         set_clause = ("library_squelch = %d" % (self.action_squelch_pub,))
      if self.action_squelch_usr is not None:
         set_clause = ("library_squelch = %d" % (self.action_squelch_usr,))

      g.assurt(self.update_stack_ids)

      # First insert any new records.
      if self.insert_values:
         log.debug('attempt_save: new record(s): %s' % (self.insert_values,))
         insert_sql = (
            """
            INSERT INTO item_findability
               (item_stack_id, username, user_id,
                library_squelch, show_in_history, branch_id)
            VALUES
               %s
            """ % (self.insert_values,))
         db.sql(insert_sql)

      # Now update all of the records, old and new, with the new settings.
      update_sql = (
         """
         UPDATE
            item_findability
         SET
            %s
         WHERE
            (item_stack_id IN (%s))
            AND (username = %s)
         """ % (set_clause,
                self.update_stack_ids,
                db.quoted(username),))
      db.sql(update_sql)

      db.transaction_commit()

   # ***

# ***

