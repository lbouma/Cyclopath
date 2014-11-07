# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import psycopg2
import time

import conf
import g

from grax.access_level import Access_Level
from item import attachment
from item import item_base
from item import item_versioned
from item.attc.thread_type import Thread_Type
from item.util import revision
from item.util.item_type import Item_Type
from util_ import misc
from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('thread')

class One(attachment.One):

   item_type_id = Item_Type.THREAD
   item_type_table = 'thread'
   item_gwis_abbrev = 'thread'
   child_item_types = None

   item_save_order = 2

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('count_posts_total',   None,   True),
      ('count_posts_read',    None,   True),
      ('last_post_username',  None,   True),
      ('last_post_body',      None,   True),
      ('last_post_timestamp', None,   True),
      #
      ('likes',               None,   True),
      ('dislikes',            None,   True),
      #
      #('last_post_timestamp_raw', None, True),
      # The ttype/thread_type_id is used to differentiate between 'general'
      # threads (about non-route things) and route 'reaction' threads.
      # FIXME: [lb] added thread_type_id to replace ttype (a. more explicit
      #        name, and b. uses an enum). So we can maybe remove ttype.
      ('ttype',               None,   True,  False,    str,     0, ),
      ('thread_type_id',      None,   True,  False,    int,     0, ),
      ]
   attr_defns = attachment.One.attr_defns + local_defns
   psql_defns = attachment.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      attachment.One.__init__(self, qb, row, req, copy_from)
      if row is None:
         self.setup_item_revisionless_defaults(qb, force=True)

   # ***

   #
   def from_gml(self, qb, elem):
      attachment.One.from_gml(self, qb, elem)
      self.setup_item_revisionless_defaults(qb, force=True)

   # BUG nnnn/FIXME/MAYBE: See: prepare_and_commit_revisionless
   #                       Update commit.py and flashclient so
   #                       that posts and threads are saved revisionlessly.
   #                       They're mostly wired: it's just that the caller
   #                       needs to know not to create a new revision just
   #                       to save a thread and/or post.

   #
   def save_core(self, qb):
      attachment.One.save_core(self, qb)
      #
      # See comments in post.One.save_core: posts and threads are saved with
      # one publicly-editable GIA record so assert that editors are creators.
      self.save_verify_creator_arbiter(qb)
      #
      # Update the thread_type_id attribute. This is redundant with the ttype
      # attribute but I'm [mm] not sure why it exists. The flashclient sends
      # only ttype and hence thread_type_id remains null and creates problems
      # with insertion into the thread table. [lb] created thread_type_id
      # because he wanted to make it an enum like the other database enums.
      # Once both are working one can be deleted... most of the other database
      # columns are named after their enum class, e.g., access_level_id,
      # geofeature_layer_id, etc.
      # MAYBE: Send thread_type_id from server (use gwis abbrev of... ttyp!).
      self.thread_type_id = Thread_Type.lookup_by_str[self.ttype]
      #
      # Save to the 'thread' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def setup_item_revisionless_defaults(self, qb, force=False):
      attachment.One.setup_item_revisionless_defaults(self, qb, force=True)

   # ***

# ***

class Many(attachment.Many):

   one_class = One

   __slots__ = (
      'getting_posts',
      )

   # In CcpV1, this used to be, simply,
   #  COALESCE(post_rev.username, post_rev.host) AS post_username
   # but username is no longer NULL in V2 -- it might be the
   # anonymous user's username instead.
   sql_select_post_username = (
      """
      CASE
         WHEN (ir_n.edited_user = '%s') THEN
            ir_n.edited_host
         ELSE
            COALESCE(ir_n.edited_user, ir_n.edited_host)
         END AS post_username
      , ir_n.edited_user AS edited_user
      """ % (conf.anonymous_username,)
      )

   sql_clauses_cols_all = attachment.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.select += (
      """
      , thread.ttype
      , thread.thread_type_id
      """
      )

   sql_clauses_cols_all.inner.group_by += (
      """
      , thread.ttype
      , thread.thread_type_id
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN thread AS thread
         ON (gia.stack_id = thread.stack_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.ttype
      , group_item.thread_type_id
      """
      )

   # ***

   # sql_clauses_cols_posts is used search_for_items. It gets the latest post
   # in the thread to accompany the thread details. It is not used for some
   # queries, like search_by_stack_id.

   # FIXME: Fetching the most recent post along with the thread should probably
   #        be a query_filters filter option. The client tell us explicitly
   #        that it wants the most recent post along with the thread.
   # FIXME: See also comments below about this "most recent post": we cannot
   #        easily check its permissions if we get it with the post. We really
   #        should get the thread and then look for the most recent post.

   sql_clauses_cols_posts = sql_clauses_cols_all.clone()

   # Since the inner SQL uses DISTINCT ON the thread stack_id, use the outer
   # clause to join in the posts (if it's in the inner, we just get one post).
   sql_clauses_cols_posts.outer.select += (
      """
      , post.stack_id AS post_stack_id
      , post.body AS post_body
      , %s
      , ir_n.edited_date AS post_timestamp
      """ % (sql_select_post_username,)
      )

   g.assurt(not sql_clauses_cols_posts.outer.group_by_enable)
   sql_clauses_cols_posts.outer.group_by += (
      """
      , post.stack_id
      , post.body
      , ir_n.edited_user AS username
      , ir_n.edited_host AS host
      , ir_n.edited_date AS timestamp
      """
      )

   # PERMS: Here we indiscriminately join the post table without checking
   #        group_item_access. This means that, at least for the latest post
   #        that we return with the thread, we treat it like it has the same
   #        permissions as the thread (and also its link_value's permissions).
   #
   # FIXME: If we want to allow private posts in a public thread, we have to
   #        fix this issue. It's tedious to get the most recent post in the
   #        same SELECT as the thread (if not impossible) so we should get the
   #        thread and then get the most recent post and combine the two into
   #        one response.
   #
   # MAYBE: But how important are private posts? Private threads are easier and
   #        would serve a similar purpose (the only example [lb] can think of
   #        is Bugzilla, which lets you privatize posts within a bug, but this
   #        serves the purpose of an organization hiding bug comments from the
   #        public while not hiding the bug itself)).
   #
   # NOTE: The Join on post and revision means you cannot fetch a thread unless
   #       it has one or more posts. So a thread without a post is not gonna be
   #       found.
   #
   # NOTE: Not using gia.valid_start_rid because that is the gia record's start
   #       rid, and not necessarily the post's. Though [lb] thinks we coded to
   #       always sync the two (write new group_item_access records when we
   #       write new item versions), but he cannot remember for certain.
   #
   #sql_clauses_cols_posts.outer.join += (
   #   """
   #   JOIN post AS post
   #      ON (gia.stack_id = post.thread_stack_id)
   #   JOIN item_versioned AS post_iv
   #      ON (post.system_id = post_iv.system_id)
   #   JOIN revision AS post_rev
   #      ON (post_iv.valid_start_rid = post_rev.id)
   #   """
   #   )
   sql_clauses_cols_posts.inner.join += (
      """
      JOIN post AS post
         ON (gia.stack_id = post.thread_stack_id)
      """
      )
   sql_clauses_cols_posts.outer.join += (
      """
      JOIN post AS post
         ON (group_item.stack_id = post.thread_stack_id)
      JOIN item_versioned AS post_iv
         ON (post.system_id = post_iv.system_id)
      LEFT OUTER JOIN item_revisionless AS ir_n
         ON (post.system_id = ir_n.system_id
             AND ir_n.acl_grouping = 1)
      """
      )

   # 2013.03.29: We want the most recent post, right?
   # NOTE: We join the thread against all of its posts, so we might end up with
   #       multiple rows for the thread. Sort by the posts' valid_start_rid to
   #       make sure we grab the most recent post to send along with the thread
   #       back to the client.
   #       NOTE: We could alternatively sort by system_id DESC, since system_id
   #             is assigned incrementally as items are saved (so an item
   #             with a greater system ID than another item is younger/newer).
   #       NOTE: Then again, posts are ordered by their version=1, i.e., if
   #             someone were able to edit a post (version>1), we wouldn't
   #             move its position in the thread-post-list. So, actually, we
   #             need to sort by stack ID to get the last post in the thread
   #             (which may not be the most recently edited post...).
   #         NO: , post_iv.valid_start_rid DESC
   #         NO: , post_iv.system_id DESC
   sql_clauses_cols_posts.outer.order_by_enable = True
   comma_maybe = ', ' if sql_clauses_cols_posts.outer.order_by else ''
   sql_clauses_cols_posts.outer.order_by += (
      """
      %s post.stack_id DESC
       , post.version DESC
      """ % (comma_maybe,))

   # This is for when the above was all in inner instead of outer:
   #sql_clauses_cols_posts.outer.shared += (
   #   """
   #   , group_item.post_stack_id
   #   , group_item.post_body
   #   , group_item.post_username
   #   , group_item.post_timestamp
   #   """
   #   )

   # 2013.03.29: This code is... pointless. The original clauses that we cloned
   #             -- sql_clauses_cols_all -- distincts-on the thread's
   #             stack_id, so we have to get the most recent post in the inner
   #             select. Hence, sorting here in the outer select is a no-op...
   # #
   # # The outer.order_by is not being used for confirm_leafiness (since posts
   # # and threads are not stacked; they only live in one branch and do not get
   # # inherited by descendant branches), so we can use it to sort by latest
   # # post for each thread.
   # g.assurt(not sql_clauses_cols_posts.outer.order_by_enable)
   # sql_clauses_cols_posts.outer.order_by_enable = True
   # # FIXME: [lb] 2012.05.15: Changed stack_id from ASC to DESC so flashclient
   # # gets latest threads first. That's right, right?
   # g.assurt(not sql_clauses_cols_posts.outer.order_by)
   # sql_clauses_cols_posts.outer.order_by = (
   #    """
   #    group_item.stack_id DESC
   #    , group_item.post_timestamp DESC
   #    """
   #    )

   # *** Constructor

   def __init__(self):
      attachment.Many.__init__(self)
      self.getting_posts = False

   #
   def search_by_stack_id(self, stack_id, *args, **kwargs):
      ''' '''
      qb = self.query_builderer(*args, **kwargs)
      g.assurt(len(qb.branch_hier) == 1)
      attachment.Many.search_by_stack_id(self, stack_id, *args, **kwargs)

   #
   def search_for_items(self, *args, **kwargs):
      ''' '''
      qb = self.query_builderer(*args, **kwargs)
      #g.assurt(qb.filters.context_stack_id > 0)
      self.getting_posts = True
      qb.sql_clauses = Many.sql_clauses_cols_posts.clone()
      self.search_get_items_posts(qb)
      self.getting_posts = False

   #
   def search_get_sql(self, qb):
      # For threads, the branch is just the leafiest branch, since threads and
      # posts are not stacked.
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1
      qb.filters.include_item_stack = True
      sql = attachment.Many.search_get_sql(self, qb)
      qb.branch_hier_limit = branch_hier_limit
      return sql

   #
   def search_get_items_posts(self, qb):

      pagin_total = qb.filters.pagin_total
      qb.filters.pagin_total = False

      # Surround the normal, inner- and outer-select clauses created by
      # item_user_access with two more selects. The third-level select counts
      # the number of posts and determines the latest poster's username and
      # timestamp of the post. The fourth-level select pretty-prints the
      # latest timestamp (which is something we should probably just do in the
      # client).

      # Make sure the item_user_watching class joins the item_event_read table
      # (so we get item_read_id column, which tells the client if the latest
      # item has been read by the user).
      # This adds a join: self.qb_join_item_event_read(qb)
      # But we can get away with being part of the select:
      self.qb_add_item_event_read(qb)

      # Get the search string
      thread_sql = self.search_get_sql(qb)
      g.assurt(thread_sql)

      # These are the columns from item_user_access's
      #    sql_clauses_cols_all.outer.select, and
      #    sql_clauses_cols_all.outer.shared
      select_clause = (
         """
         branch_id
         , access_level_id
         , system_id
         , version
         , deleted
         , name
         """)

      # Create your Fourrito, ala
      #    http://www.urbandictionary.com/define.php?term=Thurrito
      # It's a Burrito within a Burrito, within the heart of that same Burrito.
      #
      # BUG nnnn: Cache polarity so we don't have to sub-select.
      #           (Though not a big deal on such a small table...).
      fourth_ring_sql = (
         """
         SELECT
            stack_id
            , %s -- select_clause (item_versioned cols)
            , count_posts_total
            , count_posts_read
            , last_post_username
            , last_post_body
            , %s AS last_post_timestamp
            , ttype
            , thread_type_id
         FROM
            (SELECT
               stack_id
               , %s -- select_clause (item_versioned cols)
               , ttype
               , thread_type_id
               , COUNT(*) AS count_posts_total
               , COUNT(user_has_read_item) AS count_posts_read
               --, FIRST(post_stack_id) AS last_post_stack_id
               , FIRST(post_username) AS last_post_username
               , FIRST(post_body) AS last_post_body
               , FIRST(post_timestamp) AS last_post_timestamp_raw
            FROM
               (%s) AS foo_thd_1
            GROUP BY
               stack_id
               --, post_timestamp
               , %s -- select_clause (item_versioned cols)
               , ttype
               , thread_type_id
            ORDER BY
               --stack_id, post_timestamp DESC
               --stack_id
               last_post_timestamp_raw DESC
               ) AS bar
         %s %s
         """ % (select_clause,
                attachment.Many.sql_format_timestamp(
                           'last_post_timestamp_raw'),
                select_clause,
                thread_sql, # foo_thd_1
                # 3-rd ring GROUP BY
                select_clause,
                # 4-th ring ORDER BY
                qb.filters.limit_clause(),
                qb.filters.offset_clause(),))

         # 2013.04.01: In CcpV1, for route reactions, we return a BOOL to say
         # if the user is watching this thread. But in CcpV2, watchers are
         # link_values. We could join link_value and check, but the client
         # lazy-loads link_values, so we no longer need to include watch data.

      if not pagin_total:

         try:
            # Perform the SQL query
            res = qb.db.sql(fourth_ring_sql)
         except psycopg2.ProgrammingError, e:
            #conf.break_here()
            raise

         # If caller didn't say dont_fetchall, process the results (append
         # their One() objects to self).
         if res is not None:
            for row in res:
               # Get the polarity numbers.
               polarity_sql = Many.sql_polarity(qb, row['stack_id'])
               polarows = qb.db.sql(polarity_sql)
               if len(polarows) > 0:
                  g.assurt(len(polarows) == 1)
                  row['likes'] = polarows[0]['likes']
                  row['dislikes'] = polarows[0]['dislikes']
                  row['comments'] = polarows[0]['comments']

               # FIXME/BUG nnnn: Reimplement like, dislikes, et al in client.
               self.append(self.get_one(qb, row))

      else:

         # Get a count of the total number of threads, for the paginator.
         # Don't call counts from item_mgr.load_items_quick
         if qb.db.dont_fetchall:
            log.warning('search_get_items_posts: disabling dont_fetchall')
            qb.db.dont_fetchall = False

         fifth_ring_sql = (
            """
            SELECT
               COUNT(*)
            FROM (%s) AS jar
            """ % (fourth_ring_sql,))

         # FIXME: Does this make sense? Seems like a timely sql operation.
         time_0 = time.time()

         try:
            res = qb.db.table_to_dom('item_count', fifth_ring_sql)
         except psycopg2.ProgrammingError, e:
            #conf.break_here()
            raise

         log.debug('search_get_items_posts: pagin_total: %s / %s'
                   % (res, misc.time_format_elapsed(time_0),))

         # Attach the XML doc. See item_base.Many.append_gml.
         self.append(res)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))

      # FIXME: Flashclient assumes we pass back total post count and
      #        number unread? Do we? 2013.03.27: lb thinks post count
      #        is sent but unsure about unread...

      if qb.filters.filter_by_thread_type:
         if qb.filters.filter_by_thread_type != 'all':
            # MAYBE: Check that ttype/thread_type_id is a known value?
            where_clause += (" %s (thread.ttype = %s)"
               % (conjunction,
                  qb.db.quoted(qb.filters.filter_by_thread_type),))
            conjunction = "AND"

      # Only select posts whose name matches the user's search query.
      where_clause = attachment.Many.sql_apply_query_filters(
                           self, qb, where_clause, conjunction)

      return where_clause

   #
   def sql_apply_query_filters_item_stack_revisiony(self, qb, use_inner_join):
      # Routes, tracks, posts, threads, oh my, are revisionless.
      self.sql_apply_query_filters_item_stack_revisionless(qb, use_inner_join)

   #
   def sql_apply_query_filters_last_editor(self, qb, where_clause,
                                                     conjunction):
      return self.sql_apply_query_filters_last_editor_revisionless(qb,
                                             where_clause, conjunction)

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      table_cols.insert(0, 'post.body')
      #stop_words = ccp_stop_words.Addy_Stop_Words__Thread
      stop_words = None
      return attachment.Many.sql_apply_query_filter_by_text(self, qb,
                              table_cols, stop_words, use_outer=True)

   #
   #def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted,
   #                                min_acl_id):
   #   where_extra = attachment.Many.sql_inner_where_extra(self, qb,
   #                        branch_hier, br_allow_deleted, min_acl_id)
   def sql_outer_where_extra(self, qb, branch_hier, br_allow_deleted,
                                   min_acl_id):
      where_extra = attachment.Many.sql_outer_where_extra(self, qb,
                           branch_hier, br_allow_deleted, min_acl_id)
      # Posts/threads only apply to leafiest branch.
      g.assurt(len(branch_hier) == 1)
      if self.getting_posts:
         qb.sql_clauses.outer.enabled = True
         # As stated above, posts are assumed to have the same permissions as
         # the thread, so just grab the posts without regard for permissions.
         include_gids = False
         allow_deleted = False # FIXME: Is this right?
         g.assurt((isinstance(qb.revision, revision.Current)
                  or isinstance(qb.revision, revision.Historic)))
         where_extra += (
            """
            AND %s
            """ % (revision.Revision.branch_hier_where_clause(
                     branch_hier, 'post_iv', include_gids, allow_deleted),))
            #""" % (qb.branch_hier_where('post_iv', include_gids=False,
            #                            allow_deleted=False),))
      return where_extra

   #
   def sql_where_filter_linked_join_on_to_self(self, qb):
      join_on_to_self = "post.stack_id = flv.lhs_stack_id"
      g.assurt(not qb.sql_clauses.outer.where)
      qb.sql_clauses.outer.where += (
         " AND (post.stack_id = group_item.flv_lhs_stack_id) ")
      return join_on_to_self

   # ***

   #
   @staticmethod
   def sql_polarity(qb, thread_stack_id):

      # NOTE: This fcn. doesn't check permissions on the posts.
      #       It's not an issue because posts all have the same
      #       permission as the thread. But if we did allow private
      #       posts, the number of comments would include private
      #       comments that not all users could see.
      rsql = (
         """
         SELECT
              likes
            , dislikes
            , comments
         FROM (
            SELECT
                 SUM((polarity > 0)::INT) AS likes
               , SUM((polarity < 0)::INT) AS dislikes
               , SUM(has_body) AS comments
            FROM (
               SELECT
                  --DISTINCT ON (post_0.stack_id)
                  post_0.stack_id,
                  post_0.polarity,
                  (post_0.body IS NOT NULL)::INT AS has_body
               FROM
                  thread AS thread_0
               JOIN
                  item_versioned AS thread_0_iv
                  ON (thread_0_iv.system_id = thread_0.system_id)
               JOIN
                  post AS post_0
                  ON (post_0.thread_stack_id = thread_0.stack_id)
               JOIN
                  item_versioned AS post_0_iv
                  ON (post_0_iv.system_id = post_0.system_id)
               WHERE
                      thread_0.stack_id = %d
                  AND thread_0.branch_id = %d
                  AND post_0.branch_id = %d
                  AND %s
                  AND %s
               --ORDER BY
               --   post_0.stack_id ASC,
               --   post_0.version DESC
                  ) AS foo_post_1
            ) AS foo
         """ % (thread_stack_id,
                qb.branch_hier[0][0],
                qb.branch_hier[0][0],
                qb.revision.as_sql_where_strict('thread_0_iv'),
                qb.revision.as_sql_where_strict('post_0_iv'),
                ))

      return rsql

   # ***

# ***

