# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import datetime
from lxml import etree
import os
import sys
import time
import uuid

import conf
import g

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from gwis.query_filters import Query_Filters
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import geofeature
from item import item_base
from item import item_user_watching
from item import item_versioned
from item.feat import byway
from item.feat import track_point
from item.util import revision
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
import VERSION

log = g.log.getLogger('track')

"""

  The anonymous user has no tracks:

    ./ccp.py -r -t track

  Get all tracks without using GWIS:

    ./ccp.py -U landonb --no-password -r -t track

  Get first 10 results of list of tracks using GWIS:

    ./ccp.py -U landonb --no-password -r -t track -G -C 10

  Test search_by_stack_id (which hydrates track_points):

    ./ccp.py -i -U landonb --no-password
    from item.feat import track
    stack_id = 1549944
    tracks = track.Many()
    tracks.search_by_stack_id(stack_id, self.qb)
    tracks[0].track_points[5].step_number

   Easy-on-the-eyes Track table view:

    SELECT * FROM _tr;

"""

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Default = 106

   Z_DEFAULT = 170

class One(geofeature.One):

   item_type_id = Item_Type.TRACK
   item_type_table = 'track'
   item_gwis_abbrev = 'tr'
   child_item_types = None
   gfl_types = Geofeature_Layer

   local_defns = [
      # py/psql name,   deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # 2012.09.18: In the database, each track_step has a timestamp.
      # Here, 'finish' is MAX(timestamp), and 'start' is MIN(timestamp).
      # Also, we rename 'finish' to 'created' on GWIS out.
      ('finish',        None,   True,   None,    str,  None, 'created',),
      ('start',         None,   True,   None,    str,  None, 'started',),
      ('length',           0,   True,   None, ),

      # 2014.05.21: Has 'comments' been missing from pyserver?
      #             Or was it deleted at some point? I see values
      #             in the database...
      ('comments',      None,   True,  False,    str,     0,),
      ]
   attr_defns = geofeature.One.attr_defns + local_defns
   psql_defns = geofeature.One.psql_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = geofeature.One.psql_defns + local_defns

   __slots__ = [
      'track_points',
      ] + [attr_defn[0] for attr_defn in local_defns]

   def __init__(self, qb=None, row=None, req=None, copy_from=None):     
      g.assurt(copy_from is None) # Not supported for this class.
      # self.geofeature_layer_id = Geofeature_Layer.Default
      geofeature.One.__init__(self, qb, row, req, copy_from)
      self.track_points = track_point.Many()
      if (row is not None) and ('finish' in row):
         self.finish = misc.sql_time_to_datetime(row['finish'])
      else:
         self.finish = None
      # Need this, too?:
      #  if (row is not None) and ('start' in row):
      #     self.start = misc.sql_time_to_datetime(row['start'])
      #  else:
      #     self.start = None
      if row is None:
         self.setup_item_revisionless_defaults(qb, force=True)

   # *** GML/XML Processing

   #
   def append_gml(self, elem, need_digest):

      track_elem = geofeature.One.append_gml(self, elem, need_digest)

      log.debug('append_gml: appending %d track points'
                % (len(self.track_points),))
      for track_point in self.track_points:
         track_point.append_gml(track_elem)

      return track_elem

   #
   def append_gml_geometry(self, new):
      gml.append_LineString(new, self.geometry_svg)

   # FIXME: Very similar to route's. Maybe the two classes should derive from a
   #        psuedo-geofeature class (that geofeature also derives from?)?
   #        See also command classes' prepare_metaresp.
   def as_xml(self, db):
      # SYNC_ME: Search fetch doc metadata.
      doc = etree.Element('data', 
               rid_max=str(revision.Revision.revision_max(db)),
               major=VERSION.major,
               gwis_version=conf.gwis_version)
      self.append_gml(doc, need_digest=False)
      return etree.tostring(doc)

   #
   def from_gml(self, qb, elem):

      geofeature.One.from_gml(self, qb, elem)
      # BUG nnnn: Make tracks revisionless. Uncomment this:
      # self.setup_item_revisionless_defaults(qb, force=True)

      xys_string = list()
      for tpoint in elem:
         tp = track_point.One()
         tp.from_gml(qb, tpoint)
         self.track_points.append(tp)
         xys_string.append((float(tp.x), float(tp.y)))
      self.set_geometry_wkt(gml.wkt_linestring_get(
                              gml.wkt_coords_format(xys_string)))

      if not self.track_points:
         log.warning('from_gml: no track_points: %d'
                     % (len(self.track_points),))

   #
   # MAYBE: Make this revisionless.
   #        See: route.prepare_and_commit_revisionless
   #
   def save_core(self, qb):
      g.assurt(self.stack_id > 0)
      geofeature.One.save_core(self, qb)
      self.save_insert(qb, One.item_type_table, One.private_defns)
      for i in xrange(len(self.track_points)):
         self.track_points[i].save_tpoint(qb, self, i)

   # BUG nnnn: Make tracks revisionless. Uncomment this:
   # #
   # def setup_item_revisionless_defaults(self, qb, force=False):
   #    geofeature.One.setup_item_revisionless_defaults(self, qb, force=True)

# BUG nnnn/FIXME/2014.08.17: Track saving causes route finder to reload!
#                            It also saves a new revision, at least when
#                            user also saves an annotation about the track.
#           select * from _gia where start = 22581 OR until = '22581';

   # ***

# ***

class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   # MAYBE: Maybe put this in outer select so we don't have to group by in the
   #        inner...
   sql_inner_select = (
      """
      , MAX(tp.timestamp) AS finish
      , MIN(tp.timestamp) AS start
      , length2d(gf.geometry) AS length
      """)
   sql_inner_join = (
      """
      JOIN track AS tk
         ON (gia.item_id = tk.system_id)
      JOIN track_point AS tp
         ON (tk.system_id = tp.track_id)
      """
      )
   # sql: programming: ERROR: aggregates not allowed in GROUP BY clause
   sql_inner_group_by = (
      """
      -- , finish
      -- , start
      -- , length
      """)
   # 2012.09.18: The outer used to include the created (now finish) time.
   #sql_outer_select = (
   #  """
   #  , to_char(group_item.finish, 'YYYY-DD-MM HH24:MI:SS') AS finish
   #  """)
   sql_outer_shared = (
      """
      , group_item.finish
      , group_item.start
      , group_item.length
      """)
   # FIXME: The base class sets this already, right?
   #sql_outer_group_by = (
   #   """
   #   , group_item.stack_id
   #   , group_item.name
   #   """)
   # 2012.09.18: This used to be "group_item.finish DESC". Now its finish ASC.
   # Are we sorting up chronologically now, rather than backwards in time?
   # 20133.09.08: Landmarks Experiment: Returning to DESC.
   sql_outer_order_by = (
      """
      group_item.finish DESC
      """)

   # Not using: sql_clauses_cols_setup()
   sql_clauses_cols_all = geofeature.Many.sql_clauses_cols_all.clone()
   sql_clauses_cols_all.inner.select += sql_inner_select
   sql_clauses_cols_all.inner.join += sql_inner_join
   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   # The aggregates above mean we need to enable the group by.
   sql_clauses_cols_all.inner.group_by += sql_inner_group_by
   sql_clauses_cols_all.inner.group_by_enable = True
   #sql_clauses_cols_all.outer.select += sql_outer_select
   g.assurt(not sql_clauses_cols_all.outer.group_by_enable)
   sql_clauses_cols_all.outer.shared += sql_outer_shared
   # Prob. don't need: sql_clauses_cols_all.outer.group_by_enable = True
   #sql_clauses_cols_all.outer.group_by += sql_outer_group_by
   sql_clauses_cols_all.outer.order_by_enable = True
   sql_clauses_cols_all.outer.order_by += sql_outer_order_by

   sql_clauses_cols_name = geofeature.Many.sql_clauses_cols_name.clone()
   sql_clauses_cols_name.inner.select += sql_inner_select
   sql_clauses_cols_name.inner.join += sql_inner_join
   g.assurt(not sql_clauses_cols_name.inner.group_by_enable)
   sql_clauses_cols_name.inner.group_by += sql_inner_group_by
   #sql_clauses_cols_name.outer.select += sql_outer_select
   g.assurt(not sql_clauses_cols_name.outer.group_by_enable)
   sql_clauses_cols_all.outer.shared += sql_outer_shared
   # Prob. don't need: sql_clauses_cols_name.outer.group_by_enable = True
   #sql_clauses_cols_name.outer.group_by += sql_outer_group_by
   sql_clauses_cols_name.outer.order_by_enable = True
   sql_clauses_cols_name.outer.order_by += sql_outer_order_by

   # FIXME/BUG nnnn: Make track revisionless, like route;
   #                 see: route.sql_clauses_cols_versions

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   #
   def search_get_items(self, qb):
      geofeature.Many.search_get_items(self, qb)
      if (not qb.db.dont_fetchall) and (qb.filters.include_item_aux):
         self.tracks_load_aux(qb)
      # else, see search_for_items_clever and search_get_items_add_item_cb.

   #
   def search_for_items_clever(self, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      g.assurt(not qb.db.dont_fetchall)
      geofeature.Many.search_for_items_clever(self, qb)
      if qb.filters.include_item_aux:
         self.tracks_load_aux(qb)

   # 
   def search_for_items_diff(self, qb):
      g.assurt(False) # Not supported.

   #
   def search_for_items_load(self, qb, diff_group):
      # To get an historic version of restricted-access items, use
      # revision.Comprehensive.
      g.assurt(isinstance(qb.revision, revision.Current))
      geofeature.Many.search_for_items_load(self, qb, diff_group)


   # BUG nnnn: Tracks should be revisionless. Implement these:
   #
   # #
   # def sql_apply_query_filters_item_stack_revisiony(self, qb,
   #                                                        use_inner_join):
   #    # Routes, tracks, posts, threads, oh my, are revisionless.
   #    self.sql_apply_query_filters_item_stack_revisionless(qb,
   #                                                         use_inner_join)
   #
   # #
   # def sql_apply_query_filters_last_editor(self, qb, where_clause,
   #                                                   conjunction):
   #    return self.sql_apply_query_filters_last_editor_revisionless(qb,
   #                                            where_clause, conjunction)

   #
   def tracks_load_aux(self, qb):

      # SYNC_ME: route.routes_load_aux and track.tracks_load_aux.

      # MAYBE: [lb] wonders if we should impose a limit on the number of tracks
      #        we'll hydrate. I'll keep it at 1 unless Fernand or Yanjie wants
      #        it larger.
      tracks_aux_limit = 1
      if len(self) > tracks_aux_limit:
         log.warning("More than %d tracks found: ignoring %d tracks' aux data"
                     % (tracks_aux_limit, (len(self) - tracks_aux_limit),))
      elif len(self) == 0:
         log.debug('tracks_load_aux: no tracks: %s' % (str(self),))

      tracks = self[0:tracks_aux_limit]

      for tk in tracks:

         # Track points.
         # Used to be: ORDER BY timestamp. But step_number should work.
         rows = qb.db.sql(
            """
            SELECT
               step_number,
               x,
               y,
               timestamp,
               altitude,
               bearing,
               speed,
               orientation,
               temperature
            FROM 
               track_point
            WHERE
               track_id = %d
            ORDER BY 
               step_number ASC
            """ % (tk.system_id,))

         for row in rows:
            tk.track_points.append(track_point.One(qb, row=row))

   # ***

# ***

