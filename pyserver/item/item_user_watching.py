# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import traceback

import conf
import g

from grax.access_level import Access_Level
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from item import item_base
from item import item_user_access
from item.util import revision
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency

log = g.log.getLogger('item_user_watchn')

class One(item_user_access.One):

   item_type_id = None
   #item_type_id = Item_Type.ITEM_USER_WATCHING
   item_type_table = None
   item_gwis_abbrev = None # A derived class will override this.
   #item_gwis_abbrev = 'iuw'
   # Set child_item_types to None since our parent class set it to an
   # empty collection, but we don't want to allow callers to specify
   # this class's item type to get items.
   child_item_types = None

   local_defns = [
      ]
   attr_defns = item_user_access.One.attr_defns + local_defns
   psql_defns = item_user_access.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   cols_copy_nok = item_user_access.One.cols_copy_nok + []

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_user_access.One.__init__(self, qb, row, req, copy_from)

   # ***

# ***

class Many(item_user_access.Many):

   one_class = One

   __slots__ = ()

   def __init__(self):
      item_user_access.Many.__init__(self)

   #
   def qb_join_item_event_alert(self, qb):

      log.error(
         'FIXME: BUG nnnn: qb_join_item_event_alert: not implemented')
         # and the table is empty, too.

      if qb.sql_clauses.inner.join.find('item_event_read') == -1:

         if qb.username != conf.anonymous_username:
            qb.sql_clauses.inner.select += (
               """
               , ievt.messaging_id AS item_read_id
               """
               )
            qb.sql_clauses.inner.join += (
               """
               LEFT OUTER JOIN item_event_alert AS ievt
                  ON (gia.item_id = ievt.item_id)
               """)
            qb.sql_clauses.inner.group_by += (
               """
               , ievt.messaging_id
               """
               )
         else:
            qb.sql_clauses.inner.select += (
               """
               , NULL AS item_read_id
               """
               )
         qb.sql_clauses.outer.shared += (
            """
            , group_item.item_read_id
            """
            )

   #
   def qb_join_item_event_read(self, qb):

      g.assurt(False) # Deprecated.

      # See: qb_add_item_event_read. We should just select in the outer.
      log.error('qb_join_item_event_read: Deprecated')

      if qb.sql_clauses.inner.join.find('item_event_read') == -1:

         if qb.username != conf.anonymous_username:
            qb.sql_clauses.inner.select += (
               """
               , itrd.id AS itrd_event_id
               """
               )
            qb.sql_clauses.inner.join += (
               """
               LEFT OUTER JOIN item_event_read AS itrd
                  ON ((gia.item_id = itrd.item_id)
                      AND (itrd.username = %s))
               """ % (qb.db.quoted(qb.username),))
            qb.sql_clauses.inner.group_by += (
               """
               , itrd.id
               """
               )
            # If we joined using stack_id and not also version and branch_id,
            # we'd want to order by revision ID:
            #   qb.sql_clauses.inner.order_by += (
            #      # Order by latest read event: we can use event id or rev id.
            #      #  I.e., the following is effectively same as: itrd.id DESC
            #      """
            #      , itrd.revision_id DESC
            #      """
            #      )
            # 
            # Argh. [lb] wants to deprecate this fcn: it justs add to an
            # alreayd long join chain, and by joining, and since we add
            # multiple rows for the same system ID, it maybe makes more
            # sense to do an outer select fcn...
         else:
            qb.sql_clauses.inner.select += (
               """
               , NULL AS itrd_event_id
               """
               )
         qb.sql_clauses.outer.shared += (
            """
            , group_item.itrd_event_id
            """
            )

   #
   def qb_add_item_event_read(self, qb):

      qb.sql_clauses.outer.enabled = True

      # MAYBE: This seems inefficient. Maybe qb can track what's been added,
      #        instead of searching strings all the time.
      if qb.sql_clauses.outer.group_by.find('user_has_read_item') == -1:

         qb.sql_clauses.outer.select += (
            """
            , CASE
               WHEN EXISTS(SELECT id FROM item_event_read
                           WHERE item_id = group_item.system_id
                           AND username = %s
                           LIMIT 1) THEN TRUE
                  ELSE NULL END AS user_has_read_item
            """ % (qb.db.quoted(qb.username),))

         qb.sql_clauses.outer.group_by += (
            """
            , user_has_read_item
            """)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      if qb.filters.filter_by_unread:

         # User must be logged in. Client should prevent this.
         g.assurt(qb.username and (qb.username != conf.anonymous_username))

         # BUG nnnn: Display alerts in the client.
         #  Questions: Would we still send digest item watcher emails?
         #             How would you finish designing item_event_alert table?
         #             - Define the different msg_type_id types.
         #
         # For now, we use the item_event_read table, which is basically
         # the thread_read_event table from CcpV1, but now it works on
         # any item type. The client can ask that we return only items
         # that a user has not read, or it can ask us to mark what's
         # been read and what's not been read.
         #
         # The first implementation was a join:
         #
         #  self.qb_join_item_event_read(qb)
         #  # Or, using the new, unimplemented item_event_alert table:
         #  #  self.qb_join_item_event_alert(qb)
         #
         # But that creates two problems: 1., we already join a ton of tables,
         # which ends up impacting SQL performance, and 2., the server saves
         # multiple read events for the same item (same system ID), so the join
         # could cause a magnifying effect on the number of rows fetched in the
         # inner query. It seems to make more sense to run an EXISTS in the
         # outer SELECT. This causes one more SQL statement for every row
         # fetched... but how bad can it be?
         #
         # This is the code used when joing item_event_read:
         #
         #   # Look for items that have no read record, or whose record is old.
         #   # We checked that the record belongs to the user in the join, so
         #   # we just check that a record doesn't exist or that it's rev_id is
         #   # dated.
         #   #
         #   # NOTE: Since we're using system IDs, we shouldn't need to look at
         #   #       revision IDs (or versions). So, this is not necessary:
         #   # overkill: ((itrd.id IS NULL)
         #   #            OR (itrd.revision_id < gia.valid_start_rid))
         #   where_clause += (
         #      """
         #      %s (itrd.id IS NULL)
         #      """ % (conjunction,))
         #   conjunction = "AND"
         #
         # And this is untested code for use when joining item_event_alert:
         #
         #   where_clause += (
         #      """
         #      %s
         #          (ievt.messaging_id IS NOT NULL)
         #      AND (ievt.username = %s)
         #      AND (ievt.date_alerted IS NOT NULL)
         #      AND (ievt.msg_type_id = ??? /* none defined yet... */)
         #      """ % (conjunction,
         #             qb.db.quoted(qb.username),))
         #   conjunction = "AND"

         # Add the SELECT and GROUP BY for the EXISTS that tests
         # item_event_read for presence of a (username, item_system_id)
         # read event record.
         self.qb_add_item_event_read(qb)

         # Now add a WHERE that says the item must not have been read.
         # And we cannot use the where_clause, which is for the inner select.
         #
         # The column is in the SELECT, so the WHERE must use its own
         # calculation.
         #  qb.sql_clauses.outer.where += (
         #     """
         #     AND (user_has_read_item IS NULL)
         #     """)
         qb.sql_clauses.outer.where += (
            """
            AND (NOT EXISTS(SELECT id FROM item_event_read
                              WHERE item_id = group_item.system_id
                              AND username = '%s'
                              LIMIT 1))
            """ % (qb.username,))

         # We didn't add to where_clauses, so skipping: conjunction = "AND"

      if qb.filters.filter_by_watch_item:
         # NOTE: The idea with the filter_by_watch_item enum is/was, if it:
         #       == 0: Don't use.
         #       == 1: Use items I'm watching at revision.Current.
         #       == 2: Use items I was watching at qb.revision (which could
         #             be revision.Historic).
         #       But the way it got wired, the feature just uses qb.revision.
         #       So this is always option 2. Option 1 seems more meaningful,
         #       otherwise the user cannot make a new set of item watchers
         #       and then go to a historic revision to see things about those
         #       watchers. But who cares. That sounds like a silly use case.
         #       And the user can still use regions they are watching, since
         #       we always fetch those at revision.Current.

         # 2013.10.10: MAYBE delete this comment: Something about:
         #  Statewide UI: Debugging: We want to skip this if block the second
         #                            time through...
         #  which means what, exactly? [lb] can only guess that I saw the code
         #  come through this block twice, but then we'd be adding the same
         #  column names to the SELECT statement, and SQL would bail. So I had
         #  to have meant something else... meh.

         # 2014.05.04: Is this slow? [lb] seeing joining tables on lhs_stack_id
         #     or rhs_stack_id taking seconds, and WHEREing on stack_id
         #     IN (SELECT ...) instead taking less than a second.
         #     See: recent changes to searching note- and tag-matches when
         #     geocoding: make temp tables of stack IDs and then WHERE IN
         #     (SELECT FROM) instead of JOINing.
         watched_items_where = self.sql_where_filter_watched(qb)
         g.assurt(watched_items_where)
         where_clause += " %s %s " % (conjunction, watched_items_where,)
         conjunction = "AND"

         # NOTE: See qb.filters.only_in_multi_geometry for including watched
         #       items by geometry.

      return item_user_access.Many.sql_apply_query_filters(
                        self, qb, where_clause, conjunction)

   #
   def sql_where_filter_watched(self, qb):

      # E.g., find user's watched regions.

      # MAYBE: If we added new alerts (twitter, sms, etc.) we'd have to
      #        add more attributes here. For now, there's just the one
      #        alert: /item/alert_email.
      #
      # Get the well-known item watcher attribute. 
      g.assurt(qb.item_mgr is not None)
      attr_qb = qb.clone(skip_clauses=True, skip_filtport=True)
      internal_name = '/item/alert_email'
      # get_system_attr is implemented by attribute.Many but we can't import
      # attribute so we jump through object hoops instead.
      # 2013.03.29: Using qb.item_mgr.get_system_attr because this fcn. used to
      #             live in geofeature but now that we're in region maybe we
      #             can import attribute with causing an infinite import loop?
      #             Oh, well, this works just as well:
      attr_alert_email = attr_qb.item_mgr.get_system_attr(attr_qb,
                                                          internal_name)
      g.assurt(attr_alert_email is not None)

      # It doesn't make sense for the anonymous user to use this filter.
      if qb.username == conf.anonymous_username:
         # This happens if client specifies 'wgeo=1' but user is anon.
         log.error('silly anon client has no watchers')
         raise GWIS_Nothing_Found()

      join_on_to_self = "gia.stack_id = flv.rhs_stack_id"
      where_on_other = "(flv.lhs_stack_id = %d)" % (attr_alert_email.stack_id,)
      watched_items_where = self.sql_where_filter_linked(qb, join_on_to_self,
                                                             where_on_other)

      qb.sql_clauses.inner.select += (
         """
         , flv.value_integer AS flv_value_integer
         """)
      qb.sql_clauses.inner.group_by += (
         """
         , flv.value_integer
         """)
      qb.sql_clauses.outer.where += (
         """
         AND (flv_value_integer > %d)
         """ % (Watcher_Frequency.never,))

      return watched_items_where

   #
   # [lb] is not quite sure where this fcn. should live. Here is fine for now.
   def sql_where_filter_linked(self, qb, join_on_to_self,
                                         where_on_other,
                                         join_on_temp=""):

      linked_items_where = Many.sql_where_filter_linked_impl(
            qb, join_on_to_self, where_on_other, join_on_temp)

      return linked_items_where

   #
   @staticmethod
   def sql_where_filter_linked_impl(qb, join_on_to_self,
                                        where_on_other,
                                        join_on_temp=""):

      # 2014.05.05: This fcn. is slow: specifically, we could set the
      #             join_collapse_limit to 1 and then select from the
      #             temp table first ([lb] saw the sql searching for
      #             items via notes taking 4 secs. instead of 10 secs.
      #             with better join ordering); more importantly, we
      #             could use a WHERE rather than JOINing, e.g.,
      #              WHERE stack_id IN (SELECT stack_id FROM temp_table)
      #             is usually a lot faster than
      #              FROM link_value JOIN temp_table
      #             simply because JOINing a large table like link_value
      #             is slower than searching for IDs... although [lb]
      #             would've expected them to be similar in runtimes,
      #             since the JOIN is an inner join and joins on the
      #             stack ID, so the results are basically the same...

      #log.debug('sql_where_filter_linked_impl')

      g.assurt(qb.sql_clauses.inner.join.find('JOIN link_value AS flv') == -1)

      # 2013.03.27: [lb] hopes this isn't too costly. We have to check
      #             the user's permissions on the link-attribute, since
      #             item watcher links are private (i.e., if we didn't
      #             check permissions, we'd get all users' watchers).
      # 2014.05.04: It is costly, like, ten seconds to look for notes
      #             matching "gateway fountain". But using explicit join
      #             ordering and disabling join_collapse_limit, we can
      #             improve the search to a little under 4 seconds...
      #             [lb] is not sure what the search is still so costly
      #             because we're selecting from a temporary table with
      #             only 21 rows (in the 'gateway fountain' example).
      qb.sql_clauses.inner.join += (
         """
         JOIN link_value AS flv
            ON (%s)
         JOIN group_item_access AS flv_gia
            ON (flv.system_id = flv_gia.item_id)
         %s
         """ % (join_on_to_self,
                join_on_temp,))
      qb.sql_clauses.inner.select += (
         """
         , flv.lhs_stack_id AS flv_lhs_stack_id
         , flv_gia.deleted AS flv_deleted
         , flv_gia.access_level_id AS flv_access_level_id
         """)
      qb.sql_clauses.inner.group_by += (
         """
         , flv_gia.deleted
         , flv_gia.access_level_id
         """)
      qb.sql_clauses.inner.order_by += (
         """
         , flv_gia.branch_id DESC
         , flv_gia.acl_grouping DESC
         , flv_gia.access_level_id ASC
         """)
      #
      g.assurt(qb.branch_hier)
      g.assurt(qb.revision.gids)
      linked_items_where = ""
      conjunction = ""
      if where_on_other:
         linked_items_where += (
            """
            %s %s
            """
            % (conjunction,
               where_on_other,))
         conjunction = "AND"
      linked_items_where += (
         """
         %s %s
         """
         % (conjunction,
            # Check user's access to the link. This is similar to:
            # no "AND (flv_gia.group_id IN (%s))" % ','.join(qb.revision.gids)
            # no qb.revision.sql_where_group_ids(qb.revision.gids, 'flv_gia.')
            revision.Revision.branch_hier_where_clause(
               qb.branch_hier, 'flv_gia', include_gids=True,
               allow_deleted=True),))
      conjunction = "AND"
      #
      linked_items_where = " (%s) " % (linked_items_where,)
      #

      # NOTE: To avoid deleted links, we have to use an outer join,
      #       otherwise we'll find the previous undeleted links, since
      #       link_values use lhs and rhs stack_ids and not system_ids.

      # MAYBE: This may be enabled for branches.
      qb.sql_clauses.outer.enabled = True
      qb.sql_clauses.outer.where += (
         """
         AND (NOT group_item.flv_deleted)
         AND (group_item.flv_access_level_id <= %d)
         """ % (Access_Level.client,))

      return linked_items_where

   # ***

# ***

