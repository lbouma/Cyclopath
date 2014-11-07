# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import time

import conf
import g

from grax.access_level import Access_Level
from grax.user import User
from gwis.exception.gwis_error import GWIS_Error
from item import attachment
from item import item_base
from item import item_versioned
from item import link_value
from item.attc import thread
from item.attc.thread_type import Thread_Type
from item.link import link_post
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import misc

log = g.log.getLogger('post')

class One(attachment.One):

   item_type_id = Item_Type.POST
   item_type_table = 'post'
   item_gwis_abbrev = 'post'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('thread_stack_id',     None,   None,  False,    int,     2),
      # FIXME: Route Reactions save a post with body == '' but
      #        with polarity set to -1 or 1. We should enforce this
      #        rule, and another rule, that non-Route Reactions specify
      #        a body
      #('body',               None,   True,  False,    str,     2),
      ('body',                None,   True,  False,    str,     0),
      # route reactions: instead of post.body, polarity is -1 or 1
      #                  to indicate "thumbs down" or "thumbs up".
      ('polarity',               0,   True,  False,    int,     0),
      ]
   attr_defns = attachment.One.attr_defns + local_defns
   psql_defns = attachment.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      'owning_thread',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      attachment.One.__init__(self, qb, row, req, copy_from)
      self.owning_thread = None
      if row is None:
         self.setup_item_revisionless_defaults(qb, force=True)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      attachment.One.from_gml(self, qb, elem)
      self.setup_item_revisionless_defaults(qb, force=True)

      # BUG 2717: Flashclient used to send a list of usernames and we'd blindly
      # email them about the revision feedback (and we'd send the email while
      # saving, such that even if the commit failed we'd still have sent the
      # emails (and also blocking the apache request)). 2012.08.17: Now we send
      # emails after commit.py successfully commits. (This isn't ideal; really,
      # Mr. Do! or a cron job should send the email, so we can complete the
      # apache request sooner.) Anyway, see item_manager.do_post_commit:
      # after we commit (so we know the new thread, post and link_value are
      # saved), the item_mgr will see if a link_post-revision was created and,
      # if so, it'll call us to do the emailing (see notify_revision_feedback).

   # ***

   #
   def setup_owning_thread(self, qb):

      g.assurt(self.thread_stack_id > 0)

      if self.owning_thread is None:
         # EXPLAIN: This happens when a caller created a post.One() and is
         #          saving it, right?
         self.owning_thread = Many.get_owning_thread(qb, self.thread_stack_id)
         log.debug('setup_owning_thread: set owning_thread: %s'
                   % (self.owning_thread,))

      log.verbose('setup_owning_thread: %s / thread_type_id: %s / ttype: %s'
                  % (self.owning_thread,
                     self.owning_thread.thread_type_id,
                     self.owning_thread.ttype,))

      # Verify reality. [mm]: This isn't quite right. A non-null body doesn't
      # always mean a general thread. It is possible for someone to add a
      # reply to a reaction thread. It is also possible to save a reaction
      # with a body.
      if self.body:
         # g.assurt(self.owning_thread.ttype == 'general')
         # g.assurt(self.owning_thread.thread_type_id == Thread_Type.general)
         pass
      else:
         self.body = None # So it's not ''.
         # g.assurt(self.owning_thread.ttype == 'reaction')
         # g.assurt(self.owning_thread.thread_type_id == Thread_Type.reaction)

   # *** Saving to the Database

   #
   def save_core(self, qb):

      attachment.One.save_core(self, qb)

      # Do some fact checking.
      self.setup_owning_thread(qb)

      # BUG nnnn: Create two GIA records for posts and threads.
      # WORKAROUND: Posts and threads are saved publicly-editable
      # (just one GIA record; i.e., not a public read-only record and an
      # owner edit-allowed record), so we assert to prevent non-creators
      # from editing other users' posts and threads. Except for branch
      # arbiters, who can do wha' they wan'.
      self.save_verify_creator_arbiter(qb)

      # Save to the 'post' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def setup_item_revisionless_defaults(self, qb, force=False):
      attachment.One.setup_item_revisionless_defaults(self, qb, force=True)

   # *** Client ID Resolution

   #
   def stack_id_correct(self, qb):
      # Get the thread ID's stack ID.
      self.thread_stack_id = qb.item_mgr.stack_id_translate(
                  qb, self.thread_stack_id, must_exist=True)
      attachment.One.stack_id_correct(self, qb)

   # ***

# ***

class Many(attachment.Many):

   one_class = One

   __slots__ = (
      'owning_thread',
      'linked_byways',
      'linked_regions',
      'linked_waypoints',
      'linked_revisions',
      # FIXME: route reactions.
      'linked_routes',
      'reac_data',
      )

   sql_clauses_cols_all = attachment.Many.sql_clauses_cols_all.clone()

   # BUG nnnn: Along with tracks and work_items, posts and threads,
   #           and possibly by this logic, also tags and attributes,
   #           should all be revisionless.
   sql_clauses_cols_all.inner.select += (
      """
      , post.thread_stack_id AS thread_stack_id
      , post.body AS body
      , post.polarity AS polarity
      """
      )

   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   sql_clauses_cols_all.inner.group_by += (
      """
      , post.thread_stack_id
      , post.body
      , post.polarity
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN post AS post
         ON (gia.item_id = post.system_id)
      """
      )

   g.assurt(not sql_clauses_cols_all.outer.enabled)
   sql_clauses_cols_all.outer.enabled = True

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.thread_stack_id
      , group_item.body
      , group_item.polarity
      """)

   # *** Constructor

   def __init__(self):
      attachment.Many.__init__(self)
      self.owning_thread = None
      self.linked_byways = None
      self.linked_regions = None
      self.linked_waypoints = None
      self.linked_revisions = None
      self.linked_routes = None
      self.reac_data = None

   # ***

   #
   @staticmethod
   def get_owning_thread(qb, thread_stack_id):
      qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      # FIXME: Don't need to worry about qb.diff_group?
      threads = thread.Many()
      threads.search_by_stack_id(thread_stack_id, qb)
      if len(threads) < 1:
         raise GWIS_Error('Unknown thread or access denied.')
      g.assurt(len(threads) == 1)
      owning_thread = threads[0]
      qb.db.close()
      return owning_thread

   # ***

   #
   def search_get_sql(self, qb):
      # Get the edited date, username, and hostname/ip.
      qb.filters.include_item_stack = True
      sql = attachment.Many.search_get_sql(self, qb)
      return sql

   # ***

   #
   def search_get_items(self, qb):
      # Posts are inherently tied to Threads. While we could let someone just
      # query all posts, we choose not to: users must supply a Thread ID.
      # On checkout, context_stack_id is set, but on commit, we might need to
      # get it via thread_stack_id.
      thread_stack_id = qb.filters.context_stack_id
      if not thread_stack_id:
         if (self.owning_thread is None) or (not self.owning_thread.stack_id):
            post_stack_id = int(qb.filters.only_stack_ids)
            # td_stk_sql = (
            #    """
            #    SELECT thread_stack_id
            #      FROM post
            #     WHERE stack_id = %d
            #       AND version = 1
            #    """ % (post_stack_id,))
            # rows = qb.db.sql(td_stk_sql)
            # if len(rows) < 1:
            #    raise GWIS_Error('Unknown post or access denied.')
            # else:
            #    g.assurt(len(rows) == 1)
            #    thread_stack_id = rows[0]['thread_stack_id']
            #
            # Return just the post with the indicated stack ID, and
            # not all posts for the thread.
            return attachment.Many.search_get_items(self, qb)
         else:
            log.debug('search_get_items: using self.owning_thread.stack_id: %s'
                      % (self.owning_thread.stack_id,))
            thread_stack_id = self.owning_thread.stack_id
      if thread_stack_id <= 0:
         raise GWIS_Error(
            'Client error: Expecting positive "context_stack_id".')
      # For posts, the branch is just the leafiest branch. That is, threads
      # and posts are not stacked.
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1
      # Get the owning thread, the posts, and the posts' link_values.
      self.search_get_items_owning_thread(qb, thread_stack_id)
      self.search_get_items_posts(qb)
      self.search_get_items_post_links(qb)
      self.search_get_items_setup_posts(qb)
      qb.branch_hier_limit = branch_hier_limit

   #
   def search_get_items_owning_thread(self, qb, context_stack_id):
      self.owning_thread = Many.get_owning_thread(qb, context_stack_id)

   #
   def search_get_items_posts(self, qb):
      # NOTE: qb.filters is generally applied by sql_apply_query_filters,
      #       but for the thread ID, it belongs in sql_clauses (that is, it's
      #       not an optional filter).
      # FIXME: Verify qb.filters.context_stack_id exists and user can access.
      qb = qb.clone(skip_clauses=False, skip_filtport=True, db_clone=True)
      # FIXME: Don't need to worry about qb.diff_group?
      # FIXME: Should this be added in a callback instead?
      # 2013.10.22: When post.body is NULL, it's just a route reaction (where a
      # like or dislike is signalled by setting polarity to -1 or 1).
      qb.sql_clauses.inner.where += (
         """
         AND post.thread_stack_id = %d
         """
         # If a user edits a post and deletes all text, still show it.
         #  NO: AND post.body IS NOT NULL
         % (self.owning_thread.stack_id,))

      # Order the results so that pagination works.
      g.assurt(not qb.sql_clauses.outer.order_by_enable)
      qb.sql_clauses.outer.order_by_enable = True
      g.assurt(not qb.sql_clauses.outer.order_by)
      qb.filters.include_item_stack = True
      # Sort by stack ID so posts are ordered by item creation date.
      # Wrong: qb.sql_clauses.outer.order_by = "group_item.edited_date ASC"
      qb.sql_clauses.outer.order_by = "group_item.stack_id ASC"
      # Perform the SQL query
      attachment.Many.search_get_items(self, qb)
      qb.db.close()

   #
   def search_get_items_post_links(self, qb):

      # Posts that are linked to Geofeatures are linked with simple
      # link_values.

      thread_stack_id = self.owning_thread.stack_id

      self.linked_byways = link_post.Many(Item_Type.BYWAY)
      self.linked_byways.search_by_thread_id(qb, thread_stack_id)

      self.linked_regions = link_post.Many(Item_Type.REGION)
      self.linked_regions.search_by_thread_id(qb, thread_stack_id)

      self.linked_waypoints = link_post.Many(Item_Type.WAYPOINT)
      self.linked_waypoints.search_by_thread_id(qb, thread_stack_id)

      # Posts linked to revisions use a special attribute.

      self.linked_revisions = link_post.Many(Item_Type.ATTRIBUTE)
      # NOTE: attribute_load loads just one attribute. The preferred
      #       way to load attributes is too load them all at once, via:
      #         qb.item_mgr.load_cache_attachments(qb)
      #       But we only load/care about this one attribute,
      #       so the single-load fcn. is perfectly acceptable.
      self.linked_revisions.attribute_load(qb, '/post/revision')
      log.debug('self.linked_revisions: %s'
                % (self.linked_revisions,))
      self.linked_revisions.search_by_thread_id(
                              qb, thread_stack_id)
      log.debug('len(self.linked_revisions): %d'
                % (len(self.linked_revisions),))

      self.linked_routes = link_post.Many(Item_Type.ROUTE)
      self.linked_routes.search_by_thread_id(qb, thread_stack_id)

#      # Reaction likes/dislikes/comments counts...
#      self.search_calculate_reactions(qb)

   #
   def search_get_items_setup_posts(self, qb):
      # This makes sense, right? Tell each post who's thread it is's.
      for one in self:
         one.owning_thread = self

   # *** Query Builder routines

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))

      # 2014.05.21: We should always grab the item_stack and revision details,
      #             so we can say who made the post and when.
      qb.filters.include_item_stack = True

      return attachment.Many.sql_apply_query_filters(
               self, qb, where_clause, conjunction)

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
   def sql_where_filter_linked(self, qb, join_on_to_self,
                                         where_on_other,
                                         join_on_temp=""):

      linked_items_where = attachment.Many.sql_where_filter_linked(
         qb, join_on_to_self, where_on_other, join_on_temp)

      qb.sql_clauses.inner.join += (
         """
         JOIN post AS post
            ON (flv.lhs_stack_id = post.stack_id)
         """)

      return linked_items_where

   # ***

   #
   def search_calculate_reactions(self, qb):

# BUG_FALL_2013: Delete this fcn.

      # See polarity_sql = Many.sql_polarity in thread.py: [lb] thinks this
      # fcn. can be deleted. We calculate the likes and dislikes of a thread,
      # but it doesn't make sense to count it for just one post... especially
      # since a post with polarity has no comment, so it doesn't make sense
      # that we'd hydrate such a post. And posts with comments have no polarity
      # so the likes and dislikes will be zero...
      g.assurt(False) # FIXME: Delete this fcn. and the commented-out code
                      #        above that calls it.

      g.assurt(self.owning_thread is not None)

      if (self.owning_thread.thread_type_id == Thread_Type.reaction):

         # SELECT polarity, body FROM post WHERE body IS NULL;
         # ==> polarity is 1 or -1, body is never set.
         # SELECT polarity, body FROM post WHERE body IS NOT NULL;
         # ==> polarityis 0 and body is set.

         # MAYBE: Does this sql take a while?
         time_0 = time.time()

         rsql = thread.Many.sql_polarity(qb, self.owning_thread.stack_id)

         rres = qb.db.sql(rsql)

         self.reac_data = etree.Element('reac_data')
         misc.xa_set(self.reac_data, 'likes', rres[0]['likes'])
         misc.xa_set(self.reac_data, 'dislikes', rres[0]['dislikes'])
         misc.xa_set(self.reac_data, 'comments', rres[0]['comments'])

         log.debug(
            'srch_calc_reacts: likes: %d / disls: %d / cmmnts: %d / %s'
            % (rres[0]['likes'], rres[0]['dislikes'], rres[0]['comments'],
               misc.time_format_elapsed(time_0),))

   # ***

   #
   def postpare_response(self, doc, elem, extras):

      # gwis.command_.checkout sets up the XML document. We add a few
      # attributes to the <items> doc and make new ones for the link_posts.

      g.assurt(self.owning_thread is not None)

      # Add a few thread details to the XML doc.
      misc.xa_set(elem, 'thread_stack_id', self.owning_thread.stack_id)
      misc.xa_set(elem, 'thread_title', self.owning_thread.name)
      misc.xa_set(elem, 'ttype', self.owning_thread.ttype)
      misc.xa_set(elem, 'thread_type_id', self.owning_thread.thread_type_id)

      # Add the link_values and their geometries.
      #doc.append(self.result)
      # NOTE: Users can link some geofeature types to posts, but not all types.
      #       We currently don't support branches, routes, or terrain.
      for link_posts in (self.linked_byways,
                         self.linked_regions,
                         self.linked_waypoints,
                         self.linked_revisions,
                         self.linked_routes,):
         if link_posts:
            # MAGIC_NUMBER: 'link_post'
            sub_doc = self.prepare_resp_doc(doc, 'link_post')
            link_posts.append_gml(sub_doc, need_digest=False)

      if self.reac_data:
         doc.append(self.reac_data);

   # ***

# ***

