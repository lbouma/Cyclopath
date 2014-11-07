# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import attachment
from item import item_base
from item import item_versioned
from item import link_value
from item.feat import branch
from item.link import tag_counts
from item.util.item_type import Item_Type
from util_.streetaddress import ccp_stop_words

# FIXME For vim, maybe <S-F8> <C-F8>:
#==> /tmp/pyserver.minnesota-apache.log <==
#Feb-07 10:42:04 DEBUG    !username, using anon: _user_anon_minnesota
#Feb-07 10:42:04 DEBUG    Item module import failed; module: "tag"; error: "cannot import name tag_counts"
#==> /var/log/httpd/error_log <==
#[Mon Feb 07 10:41:24 2011] [error] Unhandled exception; see $dump_dir/dump.EXCEPT for details: NameError: global name 'tag_counts' is not defined

log = g.log.getLogger('tag')

class One(attachment.One):

   item_type_id = Item_Type.TAG
   item_type_table = 'tag'
   item_gwis_abbrev = 'tag'
   child_item_types = None

   # Tag pref magic values.
   IGNORE_TAG  = 0
   BONUS_TAG   = 1
   PENALTY_TAG = 2
   AVOID_TAG   = 3

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?, pytyp,  reqv
      ('count_byways',        None,   True),
      ('count_regions',       None,   True),
      ('count_waypoints',     None,   True),
      ('exist_geofeatures',   None,   True),
      ('pref_generic',        None,   True),
      ('pref_user',           None,   True),
      ('pref_enabled',        None,   True),
      ]
   attr_defns = attachment.One.attr_defns + local_defns
   psql_defns = attachment.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      attachment.One.__init__(self, qb, row, req, copy_from)

   # *** Saving to the Database

   #
   def save(self, qb, rid):
      attachment.One.save(self, qb, rid)
      # Tell item_mgr we've changed. I.e., we're a new version of an existing
      # item, so the one in the lookup is the old version.
      # MAYBE: In commit, call qb.item_mgr.load_cache_attachments, which calls
      #        qb.item_mgr.load_cache_attc_tags.
      if qb.item_mgr.loaded_cache:
         qb.item_mgr.cache_tags[self.stack_id] = self
         qb.item_mgr.attr_and_tag_ids.add(self.stack_id)

   #
   # 2014.04.21: What a bug... we've been forgetting to save to the tag table!
   def save_core(self, qb):
      g.assurt_soft(self.name)
      attachment.One.save_core(self, qb)
      # Save to the 'tag' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_core_get_branch_id(self, qb):
      # Tags always use the baseline branch_id.
      return branch.Many.baseline_id(qb.db)

   # *** Client ID Resolution

   #
   def stack_id_correct(self, qb):
      '''Tag names are unique, so try to find the tag in the database.
         If the tag cannot be found, assign a new stack ID.'''
      # NOTE: Not calling: attachment.One.stack_id_correct(self, qb)
      qb.item_mgr.stack_id_lookup_by_name(qb, self)

   #
   def stack_id_lookup_by_name_sql(self, qb):
      return Many.stack_id_lookup_by_name_sql_(qb, self.name)

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      insert_expr = (
         "(%d, %d, %d, %d)"
         % (item.system_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            item.stack_id,
            item.version,
            ))

      return insert_expr

   # ***

# ***

class Many(attachment.Many):

   one_class = One

   __slots__ = ()

   sql_clauses_cols_all = attachment.Many.sql_clauses_cols_all.clone()

   # NOTE Counts for byways, points and regions are always the current
   #      total, even if this is a Diff fetch.
   sql_clauses_cols_all.inner.select += (
      """
      , tp.tpt_id AS pref_generic
      """
      )

   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   sql_clauses_cols_all.inner.group_by += (
      """
      , tp.tpt_id
      """
      )

   # Join on anon. user tag prefs
   sql_clauses_cols_all.inner.join += (
      """
      LEFT OUTER JOIN tag_preference tp
         ON (tp.username = '%s' 
             AND gia.stack_id = tp.tag_stack_id
             AND gia.branch_id = tp.branch_id)
      """ % (conf.generic_rater_username,))

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.pref_generic
      """
      )

   # *** Constructor

   def __init__(self):
      attachment.Many.__init__(self)

   # *** Query Builder routines

# http://127.0.0.1/gwis?request=checkout&item_type=tag&rev=14641&branch_id=2359963&browid=78341B09-DD75-4EA2-CDD6-55BD869EFB3A&sessid=C014B382-2BA2-EAA9-D267-09E2D2ECF842&body=yes

   #def search_for_items(self, *args, **kwargs):
   #   # Tags are non-geometric, so this is actually not a req.viewport since 
   #   # the include rect is ignored.
   #   # FIXME viewport is not None -- Why is this part of the fcn params?
   #   #viewport = None
   #   #if (isinstance(rev, revision.Diff)):
   #   #   g.assurt(rev.group == 'new')
   #   #else:
   #   #   log.debug('type(rev) %s' % (type(rev),))
   #   #   g.assurt(isinstance(rev, revision.Current))
   #   # FIXME Should viewport always be null? Should we always do this?
   #   viewport = None
   #   attachment.Many.search_for_items(self, *args, **kwargs)

# FIXME: Can I delete this?:
   ## NOTE: This fcn. is needed, otherwise attachment return glorified
   ##       link_values. The client is expecting tags....
   #def search_for_items(self, qb):
   #   viewport = None
   #   attachment.Many.search_for_items(self, qb)
# apparently viewport is still null for the request... because client doesnt
# specify bbox, it looks like...

   # FIXME Not named right... this just gets geofeature-type tags...
   def search_geofeature_tag_count(self, qb, feat_type):
      '''Returns SQL to produce count of tag applications of each tag on 
         geofeatures of type feat_type using the latest version of un-deleted 
         tags '''
      qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      qb.sql_clauses = tag_counts.Many.sql_clauses_cols_name.clone()
      links = tag_counts.Many(feat_type)
      # FIXME: 2012.05.08: Check this fcn works...
      #        2013.04.19: [lb] sees all 0s... at least for shapefile import.
      #                    I'm not sure about for flashclient route finder.
      #                    I think the route finder has okay tag counts...
      #                    so maybe the shapfile import is doing something else
      #           EXPLAIN: Why is this fcn. called so much on import?
      log.verbose('search_geofeature_tag_count: found %d' % (len(links),))
      sql = links.search_get_sql(qb)
      qb.db.close()
      return sql

   #@staticmethod
   #def search_geofeature_tags_exist():
# NOTE This only applies to current revision
   #   '''Returns SQL to produce count of tag applications of each tag on 
   #      geofeatures of type layer_name using the latest version of un-deleted
   #      tags '''
# FIXME Fix above comment
   #   sql = (
   #      """
   #      SELECT 
   #         t.id AS id,
   #         EXISTS (
   #            SELECT
   #            gf.id AS id
   #            FROM tag AS t2
   #            LEFT OUTER JOIN link_value lv ON (t2.id = lv.lhs_stack_id)
   #            LEFT OUTER JOIN item_versioned iv 
   #               ON (iv.id = lv.id 
   #                   AND iv.version = lv.version 
   #                   AND NOT iv.deleted 
   #                   AND iv.valid_until_rid = cp_rid_inf())
   #            LEFT OUTER JOIN geofeature gf ON (gf.id = lv.rhs_stack_id)
   #         ) AS exist_gf
   #      FROM tag t
   #      """)
   #   return sql

   #
   def search_get_items(self, qb):
      if not qb.filters.skip_tag_counts:
         self.search_get_items_add_tag_counts(qb)
      # Perform the SQL query
      attachment.Many.search_get_items(self, qb)

   #
   def search_get_items_add_tag_counts(self, qb):

      # NOTE The DISTINCT feels weird -- it should already be 1-1
      #qb.sql_clauses.inner.select += (
      #   #"""
      #   #, COUNT(DISTINCT tagged_byways.rhs_stack_id) AS count_byways
      #   #""")
      #   #"""
      #   #, tagged_byways.count_byways AS count_byways
      #   #""")
      #   """
      #   , tagged_byways.count_byways
      #   """)

# This is failing on child branch change

# FIXME: The clauses cannot be resued, but i think this can be 
# moved above, anyway, to class level (like sql_clauses_cols_all)
      for feat_type in ['byway', 'waypoint', 'region',]:
         qb.sql_clauses.inner.select += (
            """
            , tagged_%ss.count AS count_%ss
            """ % (feat_type, feat_type,))
         qb.sql_clauses.inner.group_by += (
            """
            , tagged_%ss.count
            """ % (feat_type,))
         #
         tagged_sql = self.search_geofeature_tag_count(qb, feat_type)
         qb.sql_clauses.inner.join += (
            """
            LEFT OUTER JOIN (%s) AS tagged_%ss
               ON (tagged_%ss.lhs_stack_id = gia.stack_id)
            """ % (tagged_sql, feat_type, feat_type,))
         qb.sql_clauses.outer.shared += (
            """
            , group_item.count_%ss
            """ % (feat_type,))

# FIXME: This, on the other hand makes clauses un-reusable
# we can fix this later, but for now, just assert
      # If the user is logged in, grab their tag prefs.
      if (qb.username != conf.anonymous_username):
         qb.sql_clauses.inner.select += (
            """
            , tp_u.tpt_id AS pref_user
            , tp_u.enabled AS pref_enabled
            """)
         # FIXME username quoting is a hack
         # Join on user tag prefs
         qb.sql_clauses.inner.join += (
            """
            LEFT OUTER JOIN tag_preference AS tp_u
               ON (tp_u.username = %s 
                   AND tp_u.tag_stack_id = gia.stack_id) 
            """ % (
               qb.db.quoted(qb.username),
               ))
         g.assurt(not qb.sql_clauses.inner.group_by_enable)
         qb.sql_clauses.inner.group_by += (
            """
            , tp_u.tpt_id
            , tp_u.enabled
            """)
         qb.sql_clauses.outer.shared += (
            """
            , group_item.pref_user
            , group_item.pref_enabled
            """)

   #
   def search_get_sql(self, qb):
      # Tags always come from the baseline at the latest revision.
      g.assurt(not qb.confirm_leafiness)
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = -1
      sql = attachment.Many.search_get_sql(self, qb)
      qb.branch_hier_limit = branch_hier_limit
      return sql

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      stop_words = ccp_stop_words.Addy_Stop_Words__Tag
      return attachment.Many.sql_apply_query_filter_by_text(
                  self, qb, table_cols, stop_words, use_outer)

   # ***

   #
   @staticmethod
   def stack_id_lookup_by_name_sql_(qb, tag_name):
      # Tag names are unique, and all tags are public (that is, the tag
      # definition, or name, is public; users only get link_values to
      # geofeatures they can view), so it's okay to skip the group_item_access
      # table and go directly to item_versioned. Also, all tags are assigned
      # the to baseline branch, so no need to check branch_id.
      sql = (
         """
         SELECT
            tag.stack_id
         FROM
            tag
         JOIN
            item_versioned AS iv
            ON (tag.system_id = iv.system_id)
         WHERE
            iv.name = '%s'
            AND tag.branch_id = %d
         """ % (tag_name, 
                qb.branch_hier[-1][0],))
      return sql

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, tg_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if tg_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(tg_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***

