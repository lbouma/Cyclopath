# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import hashlib
from lxml import etree

import conf
import g

from grax.access_level import Access_Level
from gwis.query_filters import Query_Filters
from item import item_base
from item import item_versioned
from item import item_user_watching
from item import link_value
from item.util import revision
from item.util.item_type import Item_Type
from util_ import gml
from util_ import misc

__all__ = ['One', 'Many']

log = g.log.getLogger('geofeature')

class One(item_user_watching.One):

   item_type_id = Item_Type.GEOFEATURE
   item_type_table = 'geofeature'
   item_gwis_abbrev = 'ft'
   # This is a little coupled: all this class's derived classes' item_types.
   child_item_types = (
      Item_Type.GEOFEATURE,
      Item_Type.BYWAY,
      Item_Type.REGION,
      Item_Type.TERRAIN,
      Item_Type.WAYPOINT,
      Item_Type.ROUTE,
      Item_Type.TRACK,
      # Item_Type.BRANCH,
      )

   item_save_order = 3

   # BUG nnnn: routed resources: only make item_base class attrs for those
   #           values we care about. and do we need geometry for route_step?
   local_defns = [
      # py/psql name,            deft,  send?,  pkey?,  pytyp, reqv, abbrev
      ('geometry',               None,  False, False,     str,),
      ('geometry_wkt',           None,  False,  None,     str,),
      ('geometry_svg',           None,  False,  None,     str,),
      # BUG nnnn: Restrict z to 130 to 138, inclusive, for byways, since
      #           tilecache does the same amount of work for each zoom level
      #           (so maybe restrict z to just, e.g., five values instead).
      # RENAME: 'z' is hard to search usages on, since a) it's a single char,
      #         and b) it gets confused with other things, like 'zoom level'.
      #         'z' should be called 'bridge_level'.
      ('z',                      None,   True, False,     int,    1),
      ('geofeature_layer_id',    None,   True, False,     int,    1, 'gflid'),
      ('st_line_locate_point',   None,  False), # for route finder
      ('annotation_cnt',         None,   True,  None,     int, None, 'nann'),
      ('discussion_cnt',         None,   True,  None,     int, None, 'ndis'),
      # The is_disconnected bool is just for byway, but it's here because the
      # db column is not null.
      ('is_disconnected',       False,  False,  True,   bool, None, 'dcnn'),
      # EXPLAIN: split_from_stack_id is not needed to be persisted? We just
      #          need it to clone the split-into byways and their link_values
      #          from the split-from byway, right? But, whatever, it's stored
      #          in the table nonetheless.
      ('split_from_stack_id',    None,  False, False,    int,     0, 'splt'),
      ]
   attr_defns = item_user_watching.One.attr_defns + local_defns
   psql_defns = item_user_watching.One.psql_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = item_user_watching.One.psql_defns + local_defns
   #
   cols_copy_nok = item_user_watching.One.cols_copy_nok + (
      [
       # copy_from is used for split-from and split-into byways. For the 
       # latter, while we're just deleting split-from byways, the geometry is
       # technically the same, so we copy it; so the latter, split-into byways
       # will inherit the split-from byway's geometry but we'll soon replace
       # it.
       # NO: 'geometry',
       # NO: 'geometry_wkt',
       # NO: 'geometry_svg',
       # NO: 'z',
       'st_line_locate_point',
       'annotation_cnt',
       'discussion_cnt',
      ])

   __slots__ = [
      'geometry_changed',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_user_watching.One.__init__(self, qb, row, req, copy_from)

   # *** Built-in Function definitions

   def __str_verbose__(self):
      return ('%s, attrs [%s], tags [%s], lvals [%s]' 
              % (item_user_watching.One.__str_verbose__(self),
                 self.attrs, 
                 self.tagged,
                 getattr(self, 'link_values', None)
                 ))

   # *** GML/XML Processing

   #
   # Note that elem is the outer container, to which item_base will append new.
   def append_gml(self, elem, need_digest, new=None, extra_attrs=None, 
                        include_input_only_attrs=False):
      # We're called by item_base.Many for each record it found. It created
      # a master XML document, and it wants us to create a child document to
      # contain the geofeature.
      g.assurt(not new)
      if new is None:
         # NOTE This code CxPx from item_versioned.append_gml
         g.assurt(self.item_type_id != '')
         new = etree.Element(Item_Type.id_to_str(self.item_type_id))
      if need_digest:
         # NOTE The GML elem 'dg' is the _d_igest for _g_eometry
         # EXPLAIN: How is the digest used? 
         # FIXME: Can I use any of the geometries?? Probably not...
         g.assurt(self.geometry_svg)
         # MAYBE: Depending on the geometry representation, it's a diff digest.
         geometry = self.geometry_svg or self.geometry_wkt 
                    # or self.geometry_raw
         misc.xa_set(new, 'dg', hashlib.md5(geometry).hexdigest())
      if self.attrs:
         attrs = etree.Element('attrs')
         for attr_name, attr_val in self.attrs.iteritems():
            attr = etree.Element('a')
            misc.xa_set(attr, 'k', attr_name)
            # FIXME: Does this value need to be encoded?
            #        Test with </t> in a tag name. or <t>
            misc.xa_set(attr, 'v', attr_val)
            attrs.append(attr)
         new.append(attrs)
      if self.tagged:
         # We can't just use a comma-separated list because some tags include
         # commas. It's easiest just to make another subdocument.
         #   NO: misc.xa_set(new, 'tags', ', '.join(self.tagged))
         tags = etree.Element('tags')
         for tag_name in self.tagged:
            tag = etree.Element('t')
            tag.text = tag_name
            tags.append(tag)
         new.append(tags)
      self.append_gml_geometry(new)
      return item_user_watching.One.append_gml(self, elem, need_digest, new,
                                       extra_attrs, include_input_only_attrs)

   #
   def append_gml_geometry(self, new):
      # NOTE: Derived classes do not call this fcn; they only override it.
      # This is called when a client calls checkout with the intermediate item
      # type, Geofeature, with some geofeature's stack ID and wants to lazy-
      # load remaining item details, like annotations and discussions counts.
      # So client already has item geometry and/or doesn't care about geometry.
      #
      # DEVS: Here's an interesting cmd.:
      # ./ccp.py -r -t geofeature -I 1400013 -G \
      #    -f include_item_stack 1 \
      #    -f do_load_lval_counts 1 \
      #    -f dont_load_feat_attcs 1
      pass

   #
   def from_gml(self, qb, elem):
      item_user_watching.One.from_gml(self, qb, elem)
      # FIXME: Derived classes should verify self.geofeature_layer_id.

   #
   def set_geometry_wkt(self, geometry_wkt, is_changed=None):
      # NOTE: There's one other place where geometry_wkt is set: when we
      #       consume a 'row' on __init__. Search for the SQL using:
      #        ST_AsSVG ... AS geometry_svg and ST_AsText ... AS geometry_wkt.
      self.geometry_wkt = geometry_wkt
      # If we read the geometry from GML, we don't know if it's changed or not
      # (we have to read from the database first); but if the geometry is set
      # locally, we can let the caller tell us so.
      if is_changed is not None:
         self.geometry_changed = is_changed
      else:
         # Set to None so we know we don't know.
         self.geometry_changed = None

   # *** Validating Saving

   #
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      item_user_watching.One.validize(self, qb, is_new_item, dirty_reason, 
                                                ref_item)
      self.validize_geom(qb, is_new_item, ref_item)

   #
   def validize_geom(self, qb, is_new_item, ref_item):
      # The byway class needs to know if the geometry changes so it can decide
      # whether to update node_byway and node_endpoint.
      if is_new_item:
         g.assurt(self.geometry or self.geometry_wkt)
         try:
            g.assurt(self.geometry_changed is not False)
         except AttributeError:
            pass
         self.geometry_changed = True
      else:
         g.assurt(self.geometry_wkt)
         try:
            self.geometry_changed
         except AttributeError:
            # This happens when cloning an item prior to marking it deleted.
            g.assurt(ref_item is not None)
            g.assurt(self.geometry == ref_item.geometry)
            g.assurt(self.geometry_wkt == ref_item.geometry_wkt)
            self.geometry_changed = False
         if self.geometry_changed is None:
            g.assurt(not qb.db.dont_fetchall)
            if self.branch_id == ref_item.branch_id:
               # 2012.08.14: The item hasn't had version_finalize_and_increment
               #             called yet.
               g.assurt(self.version == ref_item.version)
               # MAYBE: Do we always prefix the SRID like we should?
               #          SRID=26915;POINT(468503.87 4964887.96)
               #        If not, postgis will complain.
               # MAYBE: Put this in geometry.py? See also: db_glue.py and
               #        geofeature.py.
               self_geom = ('SRID=%s;%s' 
                            % (conf.default_srid, self.geometry_wkt,))
               rows = qb.db.sql(
                  "SELECT ST_GeomFromEWKT(%s) = %s AS is_equal",
                  (self_geom, ref_item.geometry,))
               g.assurt(len(rows) == 1)
               self.geometry_changed = not rows[0]['is_equal']
            else:
               self.geometry_changed = False
      log.verbose('validize_geom: geom_changed: %s' 
                  % (self.geometry_changed,))

   # *** Saving to the Database

   #
   def load_all_link_values(self, qb):

      # The base class shouldn't import link_value, so send it one, er, many.
      links = link_value.Many()

      self.load_all_link_values_(qb, links, lhs=False, rhs=True, heavywt=True)

   #
   def save(self, qb, rid):
      item_user_watching.One.save(self, qb, rid)
      self.geometry_changed = False

   #
   def save_core(self, qb):
      g.assurt(self.z >= 0)
      item_user_watching.One.save_core(self, qb)
      self.save_insert(qb, One.item_type_table, One.private_defns)

   #
   def save_insert(self, qb, table, psql_defns, do_update=False):
      # If self.geometry is set, it's the raw geometry loaded from the
      # database. Otherwise, we've got WKT geometry.
      # NOTE: We always preference the WKT geometry! We have code to manipulate
      # (parse, play around with, etc.) the WKT format, bot not so much the raw
      # PostGIS format (though [lb] thinks there's probably a way, but it
      # probably just converts the hexadecimal format to WKT... I mean, it's
      # not like GDAL makes working with raw geometry easy, does it?).
      if self.geometry_wkt:
         if not self.geometry_wkt.startswith('SRID='):
            # Always preferences the WKT format, since that's what we edit.
            self.geometry = 'SRID=%s;%s' % (conf.default_srid,
                                            self.geometry_wkt,)
         else:
            self.geometry = self.geometry_wkt
      else:
         # else, self.geometry is set from an existing database record and
         #       we're just copying that.
         # There's a not-null constraint on geometry so might as well check
         # here, too.
         if not do_update:
            g.assurt(self.geometry)
      # Insert to the database.
      item_user_watching.One.save_insert(self, qb, table, psql_defns, 
                                         do_update)
      #
      if self.geometry_wkt:
         self.geometry = None

   #
   def save_update(self, qb):
      g.assurt(False) # Not impl. for geofeature.
      item_user_watching.One.save_update(self, qb)
      self.save_insert(qb, One.item_type_table, One.private_defns, 
                       do_update=True)

   # ***

   #
   def diff_compare(self, other):
      different = item_user_watching.One.diff_compare(self, other)
      if not different:
         if ((self.attrs != other.attrs)
             or (self.tagged != other.tagged)):
            different = True
      return different

   # ***

   #
   def ensure_zed(self):
      # Derived classes should override this.
      if not self.z:
         self.z = self.gfl_types.Z_DEFAULT

   #
   @staticmethod
   def as_insert_expression(qb, item):

      item.ensure_zed()

      insert_expr = (
         "(%d, %d, %d, %d, %d, %d, %s, %s, '%s'::GEOMETRY)"
         % (item.system_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            item.stack_id,
            item.version,
            item.geofeature_layer_id,
            #item.control_of_access,
            item.z,
            #item.one_way,
            item.split_from_stack_id or "NULL",
            #item.beg_node_id,
            #item.fin_node_id,
            item.is_disconnected or "FALSE",
            #item.geometry,
            item.geometry_wkt,
            ))

      return insert_expr

   # ***

# ***

class Many(item_user_watching.Many):

   one_class = One

   # Modify the SQL clauses for getting everything about an item

   sql_clauses_cols_all = item_user_watching.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , gf.geometry
      , gf.z
      , gf.geofeature_layer_id
      """)

   # EXPLAIN/MAYBE: Why are we always joining geofeature_layer?
   sql_clauses_cols_all.inner.join += (
      """
      JOIN geofeature AS gf
         ON (gia.item_id = gf.system_id)
      JOIN geofeature_layer AS gfl
         ON (gf.geofeature_layer_id = gfl.id)
      """)

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.z
      , group_item.geofeature_layer_id
      """)

   # We wait to add the geometry columns until we've filtered by branch_id,
   # etc., so we don't call Postgis a lot on data we don't care about.
   g.assurt(not sql_clauses_cols_all.outer.enabled)
   sql_clauses_cols_all.outer.enabled = True
   sql_clauses_cols_all.outer.geometry_needed = True

   # No one should enable the outer select unless they have to, since it has
   # the potential to slow down the query significantly (depending on
   # pageination, etc.).
   g.assurt(not sql_clauses_cols_all.outer.group_by_enable)
   sql_clauses_cols_all.outer.group_by += (
      """
      , group_item.geometry
      """)

   # Modify the SQL clauses for getting the names of items

   # NOTE Cloning the SQL for getting just an item's name (so we'll get 
   #      just its name and also its geometry)
   sql_clauses_cols_geom = (
                        item_user_watching.Many.sql_clauses_cols_name.clone())

   sql_clauses_cols_geom.inner.shared += (
      """
      , gf.geometry
      """)

   sql_clauses_cols_geom.inner.join += (
      """
      JOIN geofeature AS gf
         ON (gia.item_id = gf.system_id)
      """)

   # Note that we're only setting the outer clause "just in case."
   g.assurt(not sql_clauses_cols_geom.outer.enabled)
   sql_clauses_cols_geom.outer.shared += (
      """
      , group_item.geometry
      """)

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      item_user_watching.Many.__init__(self)

   # *** Query Builder routines

   # Here we convert the binary geometry from the database into an SVG object
   # if it's being sent to the client, or a WKT object if we want to use it
   # internally.
   # EXPLAIN: Why do we scale the geometry?
   def sql_outer_select_extra(self, qb):
      extra_select = item_user_watching.Many.sql_outer_select_extra(self, qb)
      if qb.sql_clauses.outer.enabled and qb.sql_clauses.outer.geometry_needed:
         if not qb.filters.skip_geometry_raw:
            extra_select += (
               """
               , group_item.geometry AS geometry
               """)
         if not qb.filters.skip_geometry_svg:
            extra_select += (
               """
               , ST_AsSVG(ST_Scale(group_item.geometry, 1, -1, 1), 0, %d) 
                     AS geometry_svg
               """ % (conf.db_fetch_precision,))
         if not qb.filters.make_geometry_ewkt:
            # ST_AsText doesn't include SRID=, which we want, since you
            # cannot insert geometry back into the db with srid information.
            # , ST_AsText(group_item.geometry) AS geometry_wkt
            extra_select += (
               """
               , ST_AsEWKT(group_item.geometry) AS geometry_wkt
               """)
         elif not qb.filters.skip_geometry_wkt:
            extra_select += (
               """
               , ST_AsTEXT(group_item.geometry) AS geometry_wkt
               """)
      return extra_select

# Called by revision_get
   def sql_geometry_by_item_name(self, qb, item_name):
      g.assurt(False) # This fcn. not called.
      qb.sql_clauses = self.sql_clauses_cols_geom.clone()
      # FIXME Should this be LIKE or ~?
      qb.sql_clauses.where += (
         "AND gia.name LIKE %s" % qb.db.quoted((item_name,)))
      qb.use_filters_and_viewport = False # FIXME: Is this right?
      return self.search_get_sql(qb)
# FIXME: Instead of LIKE, use tilde-operator ~ ?

# Called by revision_get
   def sql_geometry_by_items_watched(self, qb):
      g.assurt(False) # This fcn. not called.
      g.assurt(qb.username != conf.anonymous_username)
      qb.sql_clauses = self.sql_clauses_cols_geom.clone()
      qb.sql_clauses.join += (
         """
FIXME: deprecated:
         JOIN item_watcher AS iw
            ON (gia.stack_id = iw.stack_id
                AND gia.branch_id = iw.branch_id
                AND u.username = iw.username)
         """)
#                AND iw.enable_email = TRUE)
      qb.sql_clauses.where += "AND iw.enable_email = TRUE"
      qb.use_filters_and_viewport = False # FIXME: Is this right?
      return self.search_get_sql(qb)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      return item_user_watching.Many.sql_apply_query_filters(
                           self, qb, where_clause, conjunction)

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      where_c = item_user_watching.Many.sql_apply_query_viewport(
                                                   self, qb, "gf")
      return where_c

   # ***

   #
   def search_for_items_clever(self, *args, **kwargs):

      # From ccp.py and checkout.py, we're called without a dont_fetchall.
      # We optimize the search on their behalf, getting link_values for the
      # geofeatures. This saves time in the long run.

      qb = self.query_builderer(*args, **kwargs)

      if ((qb.filters.dont_load_feat_attcs) 
          and (not qb.filters.do_load_lval_counts)):

         item_user_watching.Many.search_for_items_clever(self, qb)

      else:

         g.assurt(not qb.db.dont_fetchall)

         # don't need: qb.sql_clauses = self.sql_clauses_cols_all.clone()

         if (isinstance(qb.revision, revision.Current)
             or isinstance(qb.revision, revision.Historic)):

            qb.item_mgr.load_feats_and_attcs(qb, self,
               feat_search_fcn='search_for_items',
               processing_fcn=self.search_get_items_add_item_cb, 
               prog_log=None, heavyweight=False, fetch_size=0, 
               keep_running=None, diff_group=None)

         elif isinstance(qb.revision, revision.Updated):

            # This is only allowed via ccp.py, for testing.
            g.assurt(qb.request_is_local and qb.request_is_script)
            qb.item_mgr.update_feats_and_attcs(qb, self,
               feat_search_fcn='search_for_items',
               processing_fcn=self.search_get_items_add_item_cb, 
               prog_log=None, heavyweight=False, fetch_size=0, 
               keep_running=None)

         elif isinstance(qb.revision, revision.Diff):

            self.search_for_items_diff(qb)

      # I don't think we should definalize, in case the caller wants to use the
      # query_builder again with the same filters.
      #qb.definalize()
      qb.db.curs_recycle()

   #
   def search_for_items_diff_search(self, qb, diff_group):
      qb.item_mgr.load_feats_and_attcs(qb, self,
         feat_search_fcn='search_for_items',
         processing_fcn=self.search_get_items_by_group_consume,
         prog_log=None, heavyweight=False, fetch_size=0,
         keep_running=None, diff_group=diff_group)

   #
   def search_get_item_counterparts_search(self, qb, diff_group):
      qb.item_mgr.load_feats_and_attcs(qb, self,
         feat_search_fcn='search_for_items',
         processing_fcn=self.search_get_item_counterparts_consume,
         prog_log=None, heavyweight=False, fetch_size=0,
         keep_running=None, diff_group=diff_group)

   # ***

   # For the route finder, to geocode endpoints.
   def search_by_distance(self, qb, point_sql, radius):

      g.assurt(not qb.sql_clauses)
      g.assurt(qb.finalized) # Weird that 'clauses isn't.
      g.assurt(not qb.db.dont_fetchall)
      # finalize() has been called, by qb doesn't have any geom filters;
      # rather, we're about to add one to the where clause.
      g.assurt(not qb.confirm_leafiness)
      if len(qb.branch_hier) > 1:
         qb.confirm_leafiness = True

      # We want to find the nearest geofeature to another geofeature (for the 
      # route finder, when we geocode, we're looking for the nearest byway to 
      # a point).
      #
      # But we can't just call search_get_items: if we're on a leafy branch, we
      # need to let item_user_access confirm_leafiness, so we can't order-by 
      # closest distance until after searching for items.

      self.sql_clauses_cols_setup(qb)

      if radius is not None:
         # Pre-Postgis vSomething: " AND gf.geometry && ST_Expand(%s, %g) "
         qb.sql_clauses.inner.where += (
            """
            AND ST_DWithin(gf.geometry, %s, %g)
            AND gf.is_disconnected IS FALSE
            """ % (point_sql, radius,))

      g.assurt(qb.sql_clauses.outer.enabled)

      qb.sql_clauses.outer.select += (
         """
         , ST_line_locate_point(group_item.geometry, %s)
         """ % (point_sql,))

      g.assurt(not qb.sql_clauses.outer.order_by_enable)
      qb.sql_clauses.outer.order_by_enable = True

      g.assurt(not qb.sql_clauses.outer.order_by)
      qb.sql_clauses.outer.order_by = (
         """
         ST_Distance(group_item.geometry, %s) ASC
         """ % (point_sql,))

      self.search_get_items(qb)

      qb.sql_clauses = None

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, gf_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if gf_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               , geofeature_layer_id
               --, control_of_access
               , z
               --, one_way
               , split_from_stack_id
               --, beg_node_id
               --, fin_node_id
               , is_disconnected
               , geometry
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(gf_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***

