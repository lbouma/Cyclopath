# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item import geofeature
from item import item_base
from item import item_helper
from item.feat import waypoint
from item.util import landmark
from item.util.item_type import Item_Type
from planner.travel_mode import Travel_Mode
from util_ import geometry
from util_ import gml
from util_ import misc
from util_ import rect
from util_.shapefile_wrapper import ojint
from util_.shapefile_wrapper import ojints

log = g.log.getLogger('route_step')

# ***

class One(item_helper.One):
   '''One step along a route. Note that unlike other geofeatures, this
      doesn't have an ID.'''

   item_type = Item_Type.ROUTE_STEP
   item_type_table = 'route_step'
   item_gwis_abbrev = 'rs'
   child_item_types = None

   # The networkx graph search functions like whole-number edge weights,
   # so make sure that we don't consider sub-1/2-meter line segments as
   # having 0 cost. Instead, round to the nearest decimeter.
   weight_multiplier = 10.0

   # BUG 2641: Poor Python Memory Management
   #           Should route_step be more lightweight, so the route manager uses
   #           less memory? (The route_step object is used both for making
   #           routes and also as the object that the route manager uses to
   #           build its road network) Note: whether or not an attribute is
   #           set, the fact that it's in __slots__ means it takes up space.
   #           (So we'd have to remove __slots__ from all classes in the
   #           ancestry.)
   #           Ideally, the route finder should just be re-written in C++....

   local_defns = [
      # py/psql name,          deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # NOTE: Because of the route finder, all of these values should at least
      #       be reqv=inreqd_local_only, because the route finder sends em to
      #       the route analysis script.

      # FIXME: Make more abbrevs to make the XML smaller

      # *** For both planners: p1 or p2 / travel_mode = 'bicycle' or 'transit'.
      #     For all egde types.

# FIXME: audit what we're sending to the client,
#        like route_id v stack_id/version, and byway_id v stack_id/version
      ('route_id',             None,   True,   True),
      # FIXME: Need route_stack_id and route_version?
      ('route_stack_id',       None,   True,  False,    int,     3),
      ('route_version',        None,   True,  False,    int,     3),
      # NOTE: In CcpV1, step_number is not in __slots__, rather, it's just set
      # on save. This probably explains why the new route sharing code uses
      # xrange to iterate over the list of steps, since it has to glean the
      # step_number from the order in the list and cannot use the value from
      # the database (since the step_number is never retrieved from the 
      # database).
      ('step_number',          None,  False,   True),
      # NOTE: step_name is only internally-set, i.e., reqv=3/inreqd_local_only.
      ('step_name',            None,   True,  False,    str,     3),
      ('travel_mode', 
                Travel_Mode.bicycle,   True,  False,    int,     3),
      # NOTE: send? is False because we append the geometry as XML text.
      ('geometry',             None,  False,   None,    str,     3),
      ('geometry_wkt',         None,  False,   None,    str,     3),
      # MAYBE: forward defaults to True, but convention says item attributes
      #        should default to nothingness. Should we invert and rename to
      #        is_backward (or... is_reverse? in_reverse? is_opp_dir?).
      ('forward',              True,   True,  False,   bool,     3),

      # *** For Cyclopath edges (in either the p1 or p2 route finder).

      ('byway_id',             None,   True,  False,    int,     3),
      ('byway_stack_id',       None,   True,  False,    int,     3),
      # FIXME: Need byway_version?
      ('byway_version',        None,   True,  False,    int,     3),
      ('byway_until_rid',      None,   None,   None,    int,     3),
      ('byway_geofeature_layer_id', None, True, None,   int,     3, 'gflid',),
      # The byway's node IDs.
      # EXPLAIN: What if this is a transit leg? Are the node IDs still set?
      # NOTE: In the route table, these are beg_nid and fin_nid.
      ('beg_node_id',          None,   True,   None,    int,     3, 'nid1'),
      ('fin_node_id',          None,   True,   None,    int,     3, 'nid2'),
      ('latest_beg_node_id',   None,   None,   None,    int,     3),
      ('latest_fin_node_id',   None,   None,   None,    int,     3),
      #('byway_one_way',        None,   None,   None,    int,     3),
      ('latest_one_way',       None,   None,   None,    int,     3),
      # MAYBE: Should we compute (lookup) elev for transit nodes?
      ('node_lhs_elevation_m', None,   True,   None,  float,     3, 'nel1'),
      ('node_rhs_elevation_m', None,   True,   None,  float,     3, 'nel2'),
      # For flashclient to show info about edge costs.
      ('bonus_tagged',        False,   True,   None,   bool,     3),
      ('penalty_tagged',      False,   True,   None,   bool,     3),
      ('rating',               None,   True,   None,  float,     3),
      # Edge length; real-world length of line segment geometry, in meters.
      # FIXME: Send fewer floating point digits to client... the GWIS is
      #        bloated with useful precision for elevation and length.
      ('edge_length',          None,   True,   None,  float,     3),
      ('edge_weight',          None,   True,   None,  float,     3),

      # For track conflation.
      # EXPLAIN: This seems like a weird attribute for a route step...
      ('split_from_stack_id',  None,   True,   None,    int,     3),

      # *** For transit edges (in the p2 (multimodal) route finder).

      # The transit_geometry is populated in the table for transit edges. For
      # byway edges, this field is Null and we fetch the geometry for the
      # byway. In either case, the local variable name is route_step.geometry.
      ('transit_geometry',     None,  False,  False),
      # NOTE: beg_node_id is < 0 for transit steps, but unique for route.
      # MAYBE: The beg_time and fin_time apply to the p2 route finder.
      #        [ml] asks if we should we compute if for the p1 finder.
      #        [lb] notes that it the p1 finder measures cost in distance
      #             rather than time. It appears this is an easy conversion
      #             (just convert distance to time using a guessed velocity)
      #             but the p1 finder rewards and penalizes edges, so the
      #             distance cost is not the *actual* distance... so we'd have
      #             to determine both cost and true distance and use just the
      #             true distance to compute the beg_time and fin_time.
      # MAYBE: Can we use a datetime or similar Python type? Using str for now.
      ('beg_time',             None,   True,   None,    str,     3),
      ('fin_time',             None,   True,   None,    str,     3),
      # MAYBE: 2012.Spring: Remove duration? [ml]
      #        2012.09.27: [lb] suggests searching the code to better
      #                    understand its usage. (A quick search of CcpV1 seems
      #                    to reveal that duration is not used at all... it's
      #                    accepted in __init__ if in cols, but other than that
      #                    it's not used.)
      # MAYBE: What's duration? This is found in CcpV1 but it's not used nor is
      #        it ever set...
      #('duration',             True,  False,   None,  float,     3),
      # 2014.04.27: Do we need something like this?
      ('since_deleted',        None,   True,   None,   bool,     3, 'sdel',),
      ]
   attr_defns = item_helper.One.attr_defns + local_defns
   psql_defns = item_helper.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(psql_defns)

   __slots__ = [
      # These attributes are used by the route finders during path finding.
      # They are not saved, not sent to the client, nor received from the route
      # finder via GML.
      # FIXME: Since these aren't sent via GML, the route finder only sets
      #        these for its internal route_steps. I.e., for a route_get
      #        operation, the route steps we get from the finder do not include
      #        these attributes.  So does that mean we need a new class -- one
      #        route_step for pyserver (apache process) and one route_step for
      #        routed (its own process, which also uses the pyserver code)?
      # Travel direction entering and exiting edge (compass rose; in degrees).
      'dir_entry',
      'dir_exit',
      # Landmarks experiment.
      'landmarks',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      item_helper.One.__init__(self, qb, row, req, copy_from)
      self.dir_entry = None
      self.dir_exit = None
      # Landmarks experiment.
      self.landmarks = list()

   # *** Init methods

   #
   def init_from_byway(self, byway):

      # This fcn. is only called by the route planners.

      # Not available yet: self.route_id

      self.step_name = byway.name

      # Set by caller: self.travel_mode

      # BUG nnnn: We only use the geometry in the response to the user (that
      # is, we don't need it for computing a route). We could save memory by
      # just getting the geometry once the route is computed (and maybe even
      # having PostGIS just make one line segment and not a bunch of little
      # ones, though route reactions requires a bunch of little ones...).
      self.geometry = byway.geometry_svg
      self.geometry_wkt = byway.geometry_wkt

      # The length of the byway is used by the route finder's cost fcn.
      self.edge_length = byway.geometry_len

      #log.debug('init_from_byway: geom?: %s / edge_length: %s'
      #   % ((self.geometry is not None) and (self.geometry != ''),
      #      self.edge_length,))

      # Set by caller: self.forward

      self.byway_id = byway.system_id
      g.assurt(self.byway_id > 0)
      self.byway_stack_id = byway.stack_id
      g.assurt(self.byway_stack_id > 0)
      # 2012.09.27: I don't think we need the byway version.
      self.byway_version = byway.version
      g.assurt(self.byway_version > 0)

      self.byway_geofeature_layer_id = byway.geofeature_layer_id

      self.beg_node_id = byway.beg_node_id
      self.fin_node_id = byway.fin_node_id
      self.node_lhs_elevation_m = byway.node_lhs_elevation_m
      self.node_rhs_elevation_m = byway.node_rhs_elevation_m

      #self.bonus_tagged
      #self.penalty_tagged
      # Set by caller: self.rating
      #self.beg_sta_name
      #self.fin_sta_name
      #self.duration
      # Set by caller: self.beg_time
      # Set by caller: self.fin_time
      # Set by caller: dir_entry
      # Set by caller: dir_exit

      # Don't forget the byway's attachment link_values.
      self.attrs = byway.attrs
      self.tagged = byway.tagged

   #

   shp_warnings = set()

   #
   def init_from_shpfeat(self, qb, shpfeat):

      # This fcn. is only called by the p3 route planner.

      # Not available yet: self.route_id

      self.step_name = shpfeat['properties']['CCP_NAME']

      # Set by caller: self.travel_mode

      # BUG nnnn: We only use the geometry in the response to the user (that
      # is, we don't need it for computing a route). We could save memory by
      # just getting the geometry once the route is computed (and maybe even
      # having PostGIS just make one line segment and not a bunch of little
      # ones, though route reactions requires a bunch of little ones...).
      self.geometry = geometry.xy_line_to_svg(
         shpfeat['geometry']['coordinates'])

      # The length of the byway is used by the route finder's cost fcn.
      try:
         self.edge_length = float(shpfeat['properties']['geom_len'])
      except KeyError:
         self.edge_length = geometry.xy_line_len(
            shpfeat['geometry']['coordinates'])

      #log.debug('init_from_byway: geom?: %s / edge_length: %s'
      #   % ((self.geometry is not None) and (self.geometry != ''),
      #      self.edge_length,))

      # Set by caller: self.forward

      try:
         self.byway_id = ojint(shpfeat['properties']['CCP_SYS'])
      except KeyError:
         self.init_from_shpfeat_complain('CCP_SYS')
         self.byway_id = -1

      self.byway_stack_id = ojint(shpfeat['properties']['CCP_ID'])
      g.assurt(self.byway_stack_id > 0)

      try:
         self.byway_version = ojint(shpfeat['properties']['CCP_VERS'])
      except KeyError:
         self.init_from_shpfeat_complain('CCP_VERS')
         self.byway_version = -1

      if (self.byway_id < 0) or (self.byway_version < 0):
         # We could save time and not load system IDs, but in routed we'd
         # have to be sure to not call rt.prepare_and_commit_revisionless.
         # Anyway, newer Shapefiles should contain the system ID. And version.
         sys_id_sql = (
            """
            SELECT iv.system_id, iv.version
            FROM item_versioned AS iv
            WHERE iv.stack_id = %d AND %s
            """ % (self.byway_stack_id,
                   qb.branch_hier_where('iv'),))
         rows = qb.db.sql(sys_id_sql)
         g.assurt(len(rows) == 1)
         self.byway_id = rows[0]['system_id']
         self.byway_version = rows[0]['version']

      try:
         self.byway_geofeature_layer_id = ojint(
            shpfeat['properties']['gf_lyr_id'])
      except KeyError:
         self.init_from_shpfeat_complain('gf_lyr_id')
         self.byway_geofeature_layer_id = byway.Geofeature_Layer.Other

      self.beg_node_id = ojint(shpfeat['properties']['ndl_nodeid'])
      self.fin_node_id = ojint(shpfeat['properties']['ndr_nodeid'])

      try:
         self.node_lhs_elevation_m = float(shpfeat['properties']['ndl_elev'])
      except:
         # KeyError: Missing 'ndl_elev'.
         # TypeError: float() argument must be a string or a number
         self.node_lhs_elevation_m = conf.elevation_mean
         self.init_from_shpfeat_complain('ndl_elev')

      try:
         self.node_rhs_elevation_m = float(shpfeat['properties']['ndr_elev'])
      except:
         # KeyError: Missing 'ndl_elev'.
         # TypeError: float() argument must be a string or a number
         self.node_rhs_elevation_m = conf.elevation_mean
         self.init_from_shpfeat_complain('ndr_elev')

      #self.bonus_tagged
      #self.penalty_tagged
      # Set by caller: self.rating
      #self.beg_sta_name
      #self.fin_sta_name
      #self.duration
      # Set by caller: self.beg_time
      # Set by caller: self.fin_time
      # Set by caller: dir_entry
      # Set by caller: dir_exit

      self.tagged = set()
      try:
         for tag_name in shpfeat['properties']['item_tags'].split(','):
            tag_name = tag_name.strip().lower()
            self.tagged.add(tag_name)
      except AttributeError:
         pass
      except KeyError:
         self.init_from_shpfeat_complain('item_tags')

      self.attrs = {}
      try:
         self.attrs['/byway/speed_limit'] = (
            shpfeat['properties']['speedlimit'])
      except KeyError:
         self.init_from_shpfeat_complain('speedlimit')

      try:
         self.attrs['/byway/lane_count'] = (
            shpfeat['properties']['lane_count'])
      except KeyError:
         self.init_from_shpfeat_complain('lane_count')

      try:
         self.attrs['/byway/outside_lane_width'] = (
            shpfeat['properties']['out_ln_wid'])
      except KeyError:
         self.init_from_shpfeat_complain('out_ln_wid')

      try:
         self.attrs['/byway/shoulder_width'] = (
            shpfeat['properties']['shld_width'])
      except KeyError:
         self.init_from_shpfeat_complain('shld_width')

      try:
         self.attrs['/byway/cycle_facil'] = (
            shpfeat['properties']['bike_facil'])
      except KeyError:
         self.init_from_shpfeat_complain('bike_facil')

      try:
         self.attrs['/byway/cautionary'] = (
            shpfeat['properties']['cautionary'])
      except KeyError:
         self.init_from_shpfeat_complain('cautionary')
         
      # BUG nnnn: Implement Cycle Route:
      try:
         self.attrs['/byway/cycle_route'] = (
            shpfeat['properties']['cycleroute'])
      except KeyError:
         self.init_from_shpfeat_complain('cycleroute')

      # MAYBE: In the other route finders, rstep.rating is the user's rating,
      # or the average rating. For route_steps loaded from a Shapefile, we're
      # not doing personalized ratings. So: can we just get away with the
      # generic rating? Or should we set all the rstep.ratings to, say, 3
      # (neutral rating)?
      try:
         self.rating = shpfeat['properties']['rtng_gnric']
      except KeyError:
         self.init_from_shpfeat_complain('rtng_gnric')

      # Skipping: shpfeat['geometry']['z_level']

      # Consumed by called?: shpfeat['geometry']['one_way']

   #
   def init_from_shpfeat_complain(self, field_name):
      if field_name not in One.shp_warnings:
         log.warning('Shapefile missing field: %s' % (field_name,))
         One.shp_warnings.add(field_name)

   # *** Built-in Function definitions

   #
   def __eq__(self, other):
      # See that other item is really a route step.
      if not isinstance(other, One):
         # This usually happens when you test == None.
         log.warning('Possibly comparing route_step to null: %s / %s'
                     % (str(self), str(other),))
         # EXPLAIN: What about multimodal causes this? Is this a hack?
         return False
      # Depending on the transit type...
      if self.travel_mode == Travel_Mode.bicycle:
         # FIXME: Do we use system_id (strict) or stack_id (loosy)?
         #        In CcpV1, only stack ID is compared (and not version).
         return((self.byway_stack_id == other.byway_stack_id)
                and (self.forward == other.forward))
      else:
         return ((self.step_name == other.step_name)
                 and (self.beg_time == other.beg_time))

   #
   def __ne__(self, other):
      return not (self == other)

   #
   def __hash__(self):
      return self.byway_stack_id + (int(self.forward) << 29)

   # FIXME: Delete this. fcn.
   # (EXPLAIN: What's the diff btw. __repr__ and __str__? I forget...)
   def __repr__(self):
      return self.__str__()

   #
   def __str__(self):
      s = ('step: rt %s #%s / %s: %s (%s)'
           % (self.route_id,
              self.step_number,
              Travel_Mode.get_travel_mode_name(self.travel_mode),
              self.step_name,
              self.byway_stack_id,))
      if ((self.beg_node_id is not None)
          and (self.fin_node_id is not None)):
         if (self.forward):
            s += ': %d -> %d' % (self.beg_node_id, self.fin_node_id)
         else:
            s += ': %d -> %d' % (self.fin_node_id, self.beg_node_id)
      return s

   # *** GML/XML Processing

   #
   def append_gml(self, elem):

      # MAYBE: This should be renamed 'rstep' but android still uses this name.
      new = etree.Element('step')

      item_helper.One.append_gml(self, elem, need_digest=False, new=new)
# FIXME: these are in attr_defns, so do we need that as extra_attrs?
#         , extra_attrs=['bonus_tagged', 'penalty_tagged', 'rating'])

      # FIXME: What about transit_geometry?
      # BUG nnnn: Can graphserver tell us the real transit geometry?

      gml.append_LineString(new, self.geometry)

      # Landmarks feature.
      for p in self.landmarks:
         p.append_gml(new)

      return new

   #
   def append_gpx(self, db, elem, step_number):

      # NOTE: we must re-query the geometry so that we can transform it into
      # WGS84 for the gpx spec
      # FIXME: EXPLAIN: Do we care about permissions here?
      # FIXME: If we know we're exporting to GPX, can't we do this on fetch?
      if self.travel_mode == Travel_Mode.bicycle:
         rows = db.sql(
            """
            SELECT
               ST_AsText(ST_Transform(geometry, %d)) as geometry
            FROM 
               geofeature
            WHERE
               system_id = %d
            """ % (conf.srid_latlon,
                   self.byway_id,))
      else:
         g.assurt(self.step_number)
         rows = db.sql(
            """
            SELECT
               ST_AsText(ST_Transform(transit_geometry, %d)) as geometry
            FROM 
               route_step
            WHERE
               route_id = %d 
               AND step_number = %d
            """ % (conf.srid_latlon,
                   self.route_id,
                   self.step_number,))

      wgs_xy = geometry.wkt_line_to_xy(rows[0]['geometry'])
      if not self.forward:
         wgs_xy.reverse()
         
      for lonlat in wgs_xy:
         # Parsed pair is [longitude, latitude]
         # FIXME: Search this element name. Why 'trk'? Because GPX?
         new = etree.Element('trkpt')
         misc.xa_set(new, 'lat', lonlat[1])
         misc.xa_set(new, 'lon', lonlat[0])
         
         name = etree.SubElement(new, 'name')
         name.text = self.step_name

         elem.append(new)

   #
   def from_gml(self, qb, elem):

      item_helper.One.from_gml(self, qb, elem)

      # from_gml() for route_step is a little weird because it gets used when
      # splicing a route and when a route is being saved by the user.
      #
      # Normally, geometry is read from the DB as 'M ...' and is the expected
      # form when generating output. But when getting data from the user, we
      # expect improperly formatted flat data and add an 'M' and later convert
      # it to 'LINESTRING(...)' when saved to the DB.

      g.assurt(not self.geometry)
      if elem.text is not None:
         # Format the geometry from the user, and overwrite whatever the
         # route_step geometry was.
         self.geometry = 'M %s' % (elem.text,)
      else:
         self.geometry = None

      if not self.edge_length:
         if self.geometry:
            self.edge_length = gml.geomstr_length(self.geometry)
         else:
            self.edge_length = 0.0
            # This happens when saving a deleted route or saving a route with
            # changes, since, for bike-only routes, flashclient only sends
            # byway stack_ids and doesn't send geometry.
            #  log.warning('from_gml: unexpected: step has no geometry?: %s'
            #              % (str(self),))
      else:
         # The route finder passes this back to route_get, which is the context
         # in which we're being run.
         pass

      # 2013.09.12: So late in the game, and we're just now testing saving
      #             route_steps...

      if self.travel_mode == Travel_Mode.bicycle:
         if not (self.byway_stack_id and self.byway_version):
            raise GWIS_Error(
               'route_step missing byway_stack_id and/or byway_version.')

         # FIXME: Should we just have flashclient send the system ID? Hrmm...
         #        Or, could we do this en masse? It seems like doing SQL for
         #        every step could take a while...
         #        like, do an item_mgr bulk load using the byway_stack_ids...
         #         oh, but what about version, I suppose...
         # BUG nnnn: The client sends all route steps and route stops when
         #           saving a route. If we're concerned about data usage, we
         #           could just have the client send byway system IDs, and
         #           not also: stack ID, version, step name, travel_mode,
         #                     beg_time, fin_time, and forward...

         if not self.byway_id:
            log.debug('from_gml: looking for byway sid: %s / vers: %s'
                      % (self.byway_stack_id, self.byway_version,))
            # FIXME... PROBABLY: Should we check the user's permission on the
            #                    byway.
            # FIXME: Do we call this once per route step?
            #        What about bulk loading? Or is this not slow?
            revision_permissions_branch_where = (
               qb.branch_hier_where(tprefix='gia',
                                    include_gids=True,
                                    allow_deleted=True))
            byway_id_sql = (
               """
               SELECT gf.system_id,
                      gia.deleted
                 FROM geofeature AS gf
                 JOIN group_item_access AS gia
                   ON (gia.item_id = gf.system_id)
                WHERE gf.stack_id = %d
                  AND gf.version = %d
                  AND %s
                ORDER BY gia.acl_grouping DESC
                LIMIT 1
               """ % (self.byway_stack_id,
                      self.byway_version,
                      revision_permissions_branch_where,))
            rows = qb.db.sql(byway_id_sql)
            if rows:
               # A given, now with the LIMIT: g.assurt(len(rows) == 1)
               self.byway_id = rows[0]['system_id']
               self.since_deleted = rows[0]['deleted']
               if self.since_deleted:
                  log.error('from_gml: FIXME: what about deleted rsteps?')
               log.debug('from_gml: fetched byway_id: %s / %s'
                         % (self.byway_id, self,))
            else:
               log.error('from_gml: no byway for step: byway sid: %s / %s'
                         % (self.byway_stack_id, self,))
         else:
            # The route finder sends the byway's system_id.
            # VERIFY...MAYBE: That stack_id and version match the system_id.
            pass

   # *** Saving to the Database

   warned_re_sysid_stk_ids = set()

   # This fcn. is not derived fr. geofeature.One.save_core() b/c. we don't use
   # that ID pool. Also, in old CcpV1, this was simply save, but we're only
   # saved when a route is saved, so this fcn. is renamed save_rstep and now
   # it's called when route is saved.
   # MAYBE: We're called from route.save_core, but maybe it should be from
   #        route.save_related_maybe?
   def save_rstep(self, qb, route, step_number):

      self.route_id = route.system_id
      # FIXME: Do we need these? They're in the table...
      self.route_stack_id = route.stack_id
      self.route_version = route.version

      self.step_number = step_number

      g.assurt(self.byway_stack_id > 0)
      g.assurt(self.byway_version > 0)
      # 2014.08.19: flashclient sending byway_id="0" ???
      if (not self.byway_id) or (self.byway_id <= 0):
         if route.stack_id not in One.warned_re_sysid_stk_ids:
            One.warned_re_sysid_stk_ids.add(route.stack_id)
            log.warning(
               'save_rstep: byway_id not sent from client: route sid: %s'
               % (route.stack_id,))
         branch_ids = [str(branch_tup[0]) for branch_tup in qb.branch_hier]
         # FIXME: The ORDER BY is pretty lame... but if we just have a stack ID
         #        and a version, and if we don't check against the time when
         #        the route was requested, we can't know for sure which branch
         #        the byway is from (e.g., a route was requested in a leafy
         #        branch and the parent branch's byways were selected, but
         #        then one byway is edited in both the parent and the leaf,
         #        then there are two byways with the same stack ID and version
         #        but different branch_ids: since our qb is Current but the
         #        route is historic, we would really need to find the revision
         #        when the route was requested and use that to find the true
         #        byway system_id). This code just finds the leafiest matching
         #        byway... which is probably okay, since this code is for
         #        saving byways, and most users will be saving to the basemap
         #        branch (who uses the MetC Bikeways 2012 branch, anyway? No
         #        one...), and also this code is just a stopgap until we fix
         #        the real problem that is the client is not sending byway
         #        system IDs, which might be a pyserver problem not sending
         #        them to the client in the first place....
         sys_id_sql = (
            """
            SELECT iv.system_id
              FROM item_versioned AS iv
             WHERE iv.stack_id = %d
               AND iv.version = %d
               AND branch_id IN (%s)
             ORDER BY branch_id DESC
             LIMIT 1
            """ % (self.byway_stack_id,
                   self.byway_version,
                   ','.join(branch_ids),))
         rows = qb.db.sql(sys_id_sql)
         g.assurt(len(rows) == 1) # Or not, if no match, which would be weird.
         self.byway_id = rows[0]['system_id']
         g.assurt(self.byway_id > 0)

      if (self.geometry and (self.travel_mode == Travel_Mode.transit)):
         # Old CcpV1: db_glue automatically prepends the SRID for columns named
         # 'geometry' but we have to do it manually here so constraints pass.
         # 2012.09.27: What does 'constraints pass' mean? Doesn't db_glue fix
         #             this list the comment says?
         # MAYBE: This feels like a gml fcn. See maybe: wkt_linestring_get.
         wkt_geom = ('SRID=%s;LINESTRING(%s)' 
                     % (conf.default_srid, 
                        gml.wkt_coords_format(
                           # FIXED?: Was: gml.flat_to_xys(self.geometry[2:])
                           gml.flat_to_xys(self.geometry)),))
      else:
         # Either this is a byway-associated route_step, so we don't save the
         # byway's geometry (it's easy to lookup in the database), or something
         # else...
         wkt_geom = None
         if self.travel_mode == Travel_Mode.transit:
            # FIXME: Does this mean we're clearing existing geometry? Seems
            #        weird...
            log.warning(
               'save_rstep: transit step has geometry? are we clearing it?')

      # FIXME: What about wkt_geom? Is this right?
      self.transit_geometry = wkt_geom

      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # ***

   #
   def calc_length_and_cost(self):

      if self.edge_length is None:
         if self.geometry_wkt is not None:
            #self.edge_length = geometry.xy_line_len(
            #                    geometry.wkt_line_to_xy(
            #                     self.geometry_wkt))
            self.edge_length = gml.geomstr_length(self.geometry_wkt)
         elif self.geometry is not None:
            #self.edge_length = geometry.xy_line_len(
            #                    geometry.svg_line_to_xy(
            #                     self.geometry))
            self.edge_length = gml.geomstr_length(self.geometry)
         else:
            log.warning('calc_len_and_cost: missing geometry?: %s' % (self,))
            self.edge_length = 0.0

      if self.edge_weight is None:
         # The rating isn't set for p1 routes that were just fetched. [lb]
         # isn't sure when it's set, maybe just when fetching a route and
         # routes_load_aux is called. But each of the planners should set
         # edge_weight when they make the list of route steps that represent
         # the chosen path, so we probably never come through here.
         if self.rating is not None:
            self.edge_weight = (self.rating
                                * self.edge_length
                                * One.weight_multiplier)
            # Edge weight is a whole number to avoid some graph search issues,
            # at least using networkx. Not that this matters here: edge_weight
            # is only set after the route is found, and it represents the
            # edge_weight that the route planner just used to decide to include
            # this edge in the chosen path.
            self.edge_weight = int(round(self.edge_weight, 0))
         else:
            self.edge_weight = 0
            log.warning('calc_len_and_cost: no rating or cost: %s' % (self,))

   # ***

# ***

class Wrap(object):

   # Skipping: __slots__

   def __init__(self, rstep):
      self.rstep = rstep

   # Rather than make a bunch of wrappers to return rstep.{whatever},
   # we'll just make a new route_step.One() from the wrapper's rstep,
   # and then we'll copy the other few attributes over. That is,
   # this Wrap() class is just used for storage -- Wrap instances
   # will be converted back to route_step.One rather than being
   # used directly.

   # ***

class Many(item_helper.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   # This class is old-skule V1 and not a true Nonwiki item, so we don't use
   # the clauses; we don't have group_item_access records for these types of 
   # items.

   # *** Constructor

   def __init__(self):
      item_helper.Many.__init__(self)

   # ***

   # 
   # NOTE: This is unlike the other search_by_* fcns. in that it doesn't use
   # sql_clauses or call upon item_user_access to do the search.
   #
   def search_by_route(self, qb, rt):

# FIXME_2013_06_11: This is no longer being called. What happened?
# also, why is step_name from byway.name and not route_step.step_name?
#       or, maybe why elsewhere is it the other way around...
      log.error('search_by_route: deprecated')

      # Load all the route steps.

      # MAYBE: The database stores elevation as a float but in pyserver and
      # beyond it's just an int.
      # MAYBE: We could cache the node_endpoints... should we?
      res = qb.db.sql(
         """
         SELECT 
            DISTINCT ON (rs.route_id, rs.step_number)
            rs.route_id,
            rs.step_number,
            iv.name AS step_name,
            rs.byway_id,
            --gf.stack_id AS byway_stack_id,
            rs.byway_stack_id,
            ST_AsSVG(ST_Scale(gf.geometry, 1, -1, 1), 0, %d) AS geometry,
            length2d(gf.geometry) AS length,
            rs.forward,
            gf.beg_node_id,
            gf.fin_node_id,
            bnl.elevation_m AS node_lhs_elevation_m,
            bnr.elevation_m AS node_rhs_elevation_m
         FROM 
            route_step AS rs
         JOIN 
            geofeature AS gf
            ON (gf.system_id = rs.byway_id)
         JOIN 
            item_versioned AS iv
            ON (iv.system_id = gf.system_id)
         LEFT JOIN 
            node_endpoint AS bnl 
            ON (bnl.stack_id = gf.beg_node_id)
         LEFT JOIN 
            node_endpoint AS bnr 
            ON (bnr.stack_id = gf.fin_node_id)
         WHERE
            rs.route_id = %d
         ORDER BY 
            rs.step_number ASC
         """ % (conf.db_fetch_precision, 
                rt.system_id,))

      for row in res:
         self.append(self.get_one(qb, row=row))

   # ***

   #
   @staticmethod
   def repair_node_ids(qb, route_steps):
      # Fix all beg_node_id and fin_node_id in the sequence of steps to remove
      # any null ids. Null ids are replaced with consecutive negative ids
      # consistent with the ordering of the steps.
      # 2014.04.29: Could someone please explain why this fcn exists:
      #             "Repair" means something broke. What?

      for step_i in xrange(len(route_steps)):
         step = route_steps[step_i]
         if not step.beg_node_id:
            # get a new beg_node_id
            if (step.forward) and (step_i > 0):
               # a previous step should have a node id already
               prev = route_steps[step_i - 1]
               step.beg_node_id = (prev.fin_node_id if prev.forward
                                   else prev.beg_node_id)
            else:
               # We still didn't find a matching route stop, so assign a new
               # client ID.
               step.beg_node_id = qb.item_mgr.get_next_client_id()
         else:
            # push beg_node_id onto previous step to ensure connectivity
            if (step.forward) and (step_i > 0):
               prev = route_steps[step_i - 1]
               if (prev.forward and prev.fin_node_id < 0):
                  prev.fin_node_id = step.beg_node_id
               elif (not prev.forward and prev.beg_node_id < 0):
                  prev.beg_node_id = step.beg_node_id
                     
         if not step.fin_node_id:
            # get a new fin_node_id
            if (not step.forward) and (step_i > 0):
               # a previous step should have a node id already
               prev = route_steps[step_i - 1]
               step.fin_node_id = (prev.fin_node_id if prev.forward
                                   else prev.beg_node_id)
            else:
               # We didn't find a matching route stop, so just assign an id.
               step.fin_node_id = qb.item_mgr.get_next_client_id()
         else:
            # push fin_node_id onto previous step to ensure connectivity
            if (not step.forward) and (step_i > 0):
               prev = route_steps[step_i - 1]
               if (prev.forward) and (prev.fin_node_id < 0):
                  prev.fin_node_id = step.fin_node_id
               elif (not prev.forward) and (prev.beg_node_id < 0):
                  prev.beg_node_id = step.fin_node_id
                  
         g.assurt(step.beg_node_id)
         g.assurt(step.fin_node_id)

      # end for.

   # ***

# ***

