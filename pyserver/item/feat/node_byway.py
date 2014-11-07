# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from decimal import Decimal
import os
import sys

import conf
import g

from item import geofeature
from item import item_base
from item import item_helper
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc

log = g.log.getLogger('node_byway')

# MAYBE: Is node_byway Big Data? It stores all byways' linestrings' vertices at
#        the Current revision. We only use it for network connectivity. So
#        maybe only build the table for import/export/conflate and branch
#        merging? (This, along with making node_endpoint_xy table, will
#        probably help with database size -- at least it's easy to test the
#        difference: keep implementing without addressing this issue, make the
#        tables, make the branches, dump the database; then do again with this
#        bug addressed, dump again, and compare dump sizes (there might be a
#        command-line way to see database size, or maybe just peek in the pgsql
#        data directory).

class One(item_helper.One):

   item_type = Item_Type.NODE_BYWAY
   item_type_table = 'node_byway'
   item_gwis_abbrev = 'nb'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('branch_id',           None,  False,   True,    int,  None),
      ('node_stack_id',       None,  False,   True,    int,  None),
      ('byway_stack_id',      None,  False,   True,    int,  None),
      # NOTE: Usually, we load the WKT, i.e., node_vertex_wkt, but we don't
      #       manipulate this geometry in pyserver, so no biggee, raw is okay.
      ('node_vertex_xy',      None,  False,  False,    str,  None),
      ]
   attr_defns = item_helper.One.attr_defns + local_defns
   psql_defns = item_helper.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(psql_defns)

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      item_helper.One.__init__(self, qb, row, req, copy_from)

   # *** Built-ins

   #
   def __str__(self):
      s = ('node_byway: br: %s / nd: %s / by: %s'
           % (self.branch_id, self.node_stack_id, self.byway_stack_id,))
      return s

   # *** GML/XML Processing

   #
   def append_gml(self, elem):
      g.assurt(False) # Doesn't get sent to client.
      return item_helper.One.append_gml(self, elem)

   # ***

   #
   def is_internal(self):
      # If the node_byway doesn't reference a node_endpoint, the byway is not
      # using this x,y as an endpoint, but as an internal node of its
      # linestring.
      return not self.node_stack_id
      # FIXME: Audit:
      #        - When two byways' node_vertex_xy are equal but
      #          not node_stack_id (i.e. different nodes; or
      #          one node is None, meaning x,y is internal for
      #          one of the byways).
      #        - When same byway has node_vertex_xy twice? But the
      #          primary key will prevent that...
      # FIXME: Where is_internal is TRUE and FALSE for same
      #        node_stack_id (i.e., a byway has a vertex at a place
      #        where other places have a node_endpoint.
      #        Is this part of import/export conny auditing (if z mismatches)?

class Many(item_helper.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   # Skipping sql_clauses: this class derives from item_helper.

   # *** Constructor

   def __init__(self):
      item_helper.Many.__init__(self)

   # ***

   #
   @staticmethod
   def get_where_is_internal(self, internals_ok=False, internals_only=False):
      # If this is not an endpoint node but an intermediate vertex.
      where_is_internal = ""
      if internals_only:
         where_is_internal = "AND (ndby.node_stack_id IS NULL)"
      elif not internals_ok:
         where_is_internal = "AND (ndby.node_stack_id IS NOT NULL)"
      return where_is_internal

   #
   def search_by_endpoint_xy(self, qb, pt_xy, internals_ok=False,
                                              limit_one=False):

      # NOTE: On SELECT, PostGIS calls ST_GeomFromEWKT if we don't (we can use
      #       raw geometry or WKT geometry in the SQL).
      where_vertex_xy = geometry.xy_to_ewkt_point_restrict(pt_xy)

      radius = pow(0.1, conf.node_precision) * 2.1 # E.g., 0.21
      #radius = conf.node_threshold # E.g., 0.11

      where_is_internal = Many.get_where_is_internal(internals_ok)

      # The node_byway table stores lossy geometry. See node_endpoint if you
      # want the raw point geometry.
      #  pt_xy = (Decimal(str(pt_xy[0])).quantize(conf.node_tolerance),
      #           Decimal(str(pt_xy[1])).quantize(conf.node_tolerance),)
      pt_xy = (round(pt_xy[0], conf.node_precision),
               round(pt_xy[1], conf.node_precision),)

      if limit_one:
         limit_sql = "LIMIT 1"
      else:
         limit_sql = ""

      # NOTE: We don't use node_endpt_xy table, but rather the node_byway
      #       table. The node_endpt_xy table sounds ideal, but the nodes
      #       in that table may or may not correspond to any current-
      #       versioned byways in the target branch. So use the node_byway
      #       table and we should be able to find a node associated with
      #       a live/current byway.

      # We used to "AND (ndby.node_vertex_xy = '%s')"
      # but now we ST_DWithin to allow a little wiggle
      # room.
      node_byway_sql = (
         """
         SELECT
              ndby.branch_id
            , ndby.node_stack_id
            , ndby.byway_stack_id
            , ndby.node_vertex_xy
            , ST_Distance(ndby.node_vertex_xy, '%s') AS pt_dist
         FROM
            node_byway AS ndby
         WHERE
            (ndby.branch_id = %d)
            AND ST_DWithin(ndby.node_vertex_xy, '%s', %s)
            %s
         ORDER BY
            --ndby.node_stack_id
            pt_dist ASC
         %s
         """ % (where_vertex_xy,
                qb.branch_hier[0][0],
                where_vertex_xy,
                radius,
                where_is_internal,
                limit_sql,))

      rows = qb.db.sql(node_byway_sql)
      for row in rows:
         self.append(self.get_one(qb, row))

   #
   def search_by_node_stack_id(self, qb, node_endpt_id, internals_ok=False):

      g.assurt(False) # Not currently used... maybe someday?

      # We don't need this where clause, e.g., ndby.node_stack_id IS NOT NULL
      # Nope: where_is_internal = Many.get_where_is_internal(internals_ok)

      rows = qb.db.sql(
         """
         SELECT
            , ndby.branch_id
            , ndby.node_stack_id
            , ndby.byway_stack_id
            , ndby.node_vertex_xy
         FROM
            node_byway AS ndby
         WHERE
                ndby.branch_id = %d
            AND ndby.node_stack_id = %d
         """ % (qb.branch_hier[0][0],
                node_endpt_id,))

      for row in rows:
         self.append(self.get_one(qb, row))

   #
   @staticmethod
   def search_get_stats(qb, node_stack_id, internals_ok=False):

      # Nope: where_is_internal = Many.get_where_is_internal(internals_ok)

      # MAYBE: We could calculate referencers with a custom aggregate
      #        that collapses byway_stack_id when we distinct(node_stack_id)
      # MAYBE: We could also check if node_vertex_xy doesn't match
      #        node_endpoint.endpoint_xy.
      sql_count_from_node_byway = (
         """
         SELECT
            DISTINCT(ndby.node_stack_id) AS node_stack_id
            , COUNT(ndby.byway_stack_id) AS reference_n
            /* MAYBE: Coalesce ndby.node_vertex_xy ? */
         FROM
            node_byway AS ndby
         WHERE
                ndby.branch_id = %d
            AND ndby.node_stack_id = %d
         GROUP BY
            ndby.node_stack_id
         """ % (qb.branch_hier[0][0],
                node_stack_id,))

      rows_node_byway = qb.db.sql(sql_count_from_node_byway)

      if rows_node_byway:
         g.assurt(len(rows_node_byway) == 1)
         node_byway_ref_n = rows_node_byway[0]['reference_n']
      else:
         # This happens when adding a byway from a parent branch to a child
         # branch: it's not there yet...
         node_byway_ref_n = -1
      log.verbose(
         'search_get_stats: node_byway: node_stack_id: %s / reference_n: %d'
         % (node_stack_id, node_byway_ref_n,))

      sql_count_from_geofeature = (
         """
         SELECT
            COUNT(foo.stack_id) AS reference_n
         FROM (
            SELECT
               DISTINCT(feat.stack_id)
            FROM
               geofeature AS feat
            JOIN
               item_versioned AS iv
                  USING (system_id)
            WHERE
               (    (feat.beg_node_id = %d)
                 OR (feat.fin_node_id = %d))
               AND %s
            ) AS foo
         """ % (node_stack_id,
                node_stack_id,
                qb.branch_hier_where('iv'),
                ))

      rows_geofeature = qb.db.sql(sql_count_from_geofeature)

      if rows_geofeature:
         g.assurt(len(rows_geofeature) == 1)
         geofeature_ref_n = rows_geofeature[0]['reference_n']
         log_fcn = log.verbose
      else:
         geofeature_ref_n = 0
         log_fcn = log.warning
      log_fcn(
         'search_get_stats: geofeature: node_stack_id: %s / reference_n: %d'
         % (node_stack_id, geofeature_ref_n,))

      # This is only called when adding a byway to an intersection, right?
      # So what's in node_byway is one less than the new count?
      if (node_byway_ref_n != -1) and (node_byway_ref_n != geofeature_ref_n):
         log.verbose(
            'search_get_stats: node_stack_id: %s / %s: %d != %s: %d'
            % (node_stack_id, 'node_byway_ref_n', node_byway_ref_n,
               'geofeature_ref_n', geofeature_ref_n,))

      # The number calculated the line segments' node IDs is accurate;
      # whatever is in node_byway might be stale...
      # No: reference_n = node_byway_ref_n
      reference_n = geofeature_ref_n

      return reference_n

   # ***

   #
   @staticmethod
   def reset_rows_for_byway(qb, for_byway, beg_node_id, fin_node_id):

      log.verbose('reset_rows_for_byway: node_byway: delete: for_byway: %s'
                  % (for_byway,))

      # Remove the byway's old entries from the table.
      rows = qb.db.sql(
         """
         DELETE FROM node_byway
         WHERE (branch_id = %d) AND (byway_stack_id = %d)
         """ % (qb.branch_hier[0][0], for_byway.stack_id,))
      # Insert the byway's vertices into the table.
      g.assurt(beg_node_id and fin_node_id)
      if not for_byway.deleted or for_byway.reverted:
         Many.insert_rows_for_byway(qb, for_byway, beg_node_id, fin_node_id)

   #
   @staticmethod
   def insert_rows_for_byway(qb, for_byway,
                                 beg_node_id,
                                 fin_node_id,
                                 bulk_list=None):

      # We don't expect deleted or reverted byways. The node_byway table is
      # another flattened-branch table, as opposed to a stacked-branch table:
      # rather than storing just changes in a branch, we store everything from
      # every branch. So if an item is really reverted in a branch, we won't
      # see that item but the parent item instead. And if an item is deleted in
      # a branch, it won't have been fetched for us, anyway (item_user_access
      # would have weeded it out).

      g.assurt((not for_byway.deleted) and (not for_byway.reverted))
      g.assurt((beg_node_id > 0) and (fin_node_id > 0))

      g.assurt(for_byway.geometry_wkt)
      xys_list = geometry.wkt_line_to_xy(for_byway.geometry_wkt,
                                         precision=conf.node_precision)

      insert_rows = []

      last_pt_i = len(xys_list) - 1
      for i in xrange(len(xys_list)):

         pt_xy = xys_list[i]

         # E.g., "SRID=%s;POINT(%.1f %.1f)"
         node_vertex_xy = geometry.xy_to_ewkt_point_restrict(pt_xy)

         if i == 0:
            g.assurt(beg_node_id > 0)
            node_id_str = str(beg_node_id)
         elif i == last_pt_i:
            g.assurt(fin_node_id > 0)
            node_id_str = str(fin_node_id)
         else:
            node_id_str = "NULL"
         g.assurt(node_id_str) # I.e., non-empty string.

         insert_vals = ("(%d, %s, %d, '%s')"
                        % (qb.branch_hier[0][0],
                           node_id_str,
                           for_byway.stack_id,
                           node_vertex_xy,))
         insert_rows.append(insert_vals)

      if bulk_list is not None:
         bulk_list.extend(insert_rows)
      else:
         Many.insert_bulk_byways(qb, insert_rows)

   #
   @staticmethod
   def insert_bulk_byways(qb, bulk_list):

      # BUG nnnn: Branch Merge: When merging two branches, you have to
      # recalculate the whole node_byway table for the branch that's
      # merged to. I'm not sure there's an easier way: since we use stacked
      # branching, we don't want to record a parent branch byway in
      # node_byway unless we edit the byway, since we want the record
      # from the last_merge_rid; then when we merge, all the parent branch
      # byways that were not edited in the leafy branch have to be
      # recalculated (so maybe part of merge is to collect all the stack IDs
      # of things from last_merge_rid that we've updated to the
      # working_rid, and then we can just repair only those).

      # The node_byway table is always the latest revision, so no need for
      # revision_id. And we use the leafy branch ID and not the byway's.

      log.verbose('insert_bulk_byways: node_byway: insert: bulk_list: %s'
                  % (bulk_list,))

      insert_sql = (
         """
         INSERT INTO node_byway
            (branch_id
             , node_stack_id
             , byway_stack_id
             , node_vertex_xy)
         VALUES
            %s
         """ % (','.join(bulk_list),))

      rows = qb.db.sql(insert_sql)
      g.assurt(rows is None)

   # *** Table management

   indexed_cols = (
      'byway_stack_id',
      'node_stack_id',
      )

   #
   @staticmethod
   def drop_indices(db):
      db.sql(
         """
         SELECT cp_constraint_drop_safe('node_byway', 'enforce_valid_geometry')
         """)
      db.sql("DROP INDEX IF EXISTS node_byway_node_vertex_xy")
      # FIXME: This loop shared by the node_ classes. Put in some base class.
      for col_name in Many.indexed_cols:
         # E.g., "DROP INDEX IF EXISTS node_byway_branch_id"
         db.sql("DROP INDEX IF EXISTS node_byway_%s" % (col_name,))

   #
   @staticmethod
   def make_indices(db):
      # Drop the indices first.
      Many.drop_indices(db)
      #
      sql_add_constraint = (
         """
         ALTER TABLE node_byway
            ADD CONSTRAINT enforce_valid_geometry
               CHECK (IsValid(node_vertex_xy))
         """)
      db.sql(sql_add_constraint)
      #
      # This is the PostGIS 1.x way: USING GIST (... GIST_GEOMETRY_OPS)
      sql_add_index = (
         """
         CREATE INDEX node_byway_node_vertex_xy ON node_byway
            USING GIST (node_vertex_xy)
         """)
      db.sql(sql_add_index)
      #
      for col_name in Many.indexed_cols:
         # E.g.,
         #  "CREATE INDEX node_byway_branch_id ON node_byway(branch_id)"
         db.sql("CREATE INDEX node_byway_%s ON node_byway(%s)"
                % (col_name, col_name,))

   # ***

# ***

