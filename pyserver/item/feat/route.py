# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import datetime
from lxml import etree
import os
import psycopg2
import sys
import time
import traceback
import uuid

import conf
import g

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.library_squelch import Library_Squelch
from grax.user import User
from gwis.query_filters import Query_Filters
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import geofeature
from item import item_base
from item import item_revisionless
from item import item_user_watching
from item import item_versioned
from item.feat import byway
from item.feat import route_step
from item.feat import route_stop
from item.grac import group
from item.util import revision
from item.util.item_type import Item_Type
from item.util import ratings
from planner.travel_mode import Travel_Mode
import planner.routed_p1.route_finder
import planner.routed_p2.route_finder
import planner.routed_p3.route_finder
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
import VERSION

log = g.log.getLogger('route')

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Default = 105

   # SYNC_ME: pyserver/item/feat/route.py::route.Geofeature_Layer.Z_DEFAULT
   #          flashclient/items/feats/Route.as::Route.z_level_always
   Z_DEFAULT = 160

class One(geofeature.One):
   '''A route from one byway node to another.'''

   item_type_id = Item_Type.ROUTE
   item_type_table = 'route'
   item_gwis_abbrev = 'rt'
   child_item_types = None
   gfl_types = Geofeature_Layer

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # The user can edit 'details' to provide a description of the route.
      ('details',             None,   True,  False,    str,      0),

      # In old CcpV1, 'from_addr' and 'to_addr' were stored in the route
      # table. For Route Sharing, those columns were removed and we used the
      # route_stop table to look them up. But in CcpV2 we want to cache these
      # values, like we cache other origin/destination information, so it's
      # quicker (and easier for devs) to get route metadata.
      # RENAMED: Were: from_addr and to_addr / Now: beg_addr and fin_addr.
      ('beg_addr',            None,   True,  False,    str,      3,),
      ('fin_addr',            None,   True,  False,    str,      3,),

      # BUG nnnn: The client recomputes the length, but we have it here.
      #           FIXME: Should this include transit edge lengths?
      # The rsn_len is the length of bicycle (non-transit) route steps.
      # The client can recompute this from route step lengths, which
      # flashclient does when a user drags a route and flashclient
      # "stitches" a sequence of routes together (though why flashclient
      # doesn't just add up each sequence's rsn_lens is a mystery).
      ('rsn_len',             None,   True,   None,  float,      3,),
      # The client can either figure these values out from the steps or we can.
      ('rsn_min',             None,   True,   None,    int,      3,),
      ('rsn_max',             None,   True,   None,    int,      3,),
      ('n_steps',             None,   True,   None,    int,      3,),
      ('beg_nid',             None,   True,   None,    int,      3,),
      ('fin_nid',             None,   True,   None,    int,      3,),

      # BUG nnnn/MAYBE: In the client, show the avg edge weight for the route,
      # and highlight byways by their edge cost for whatever algorithm was
      # used. Historically, we've had a feature to color each byway by its
      # rating, so maybe it would be useful to color each byway by the edge
      # weight the finder used, e.g., so the user can differentiate between
      # the "better" parts and the "worse" parts of the route.
      # Currently, ccp.py at leasy shows you the average cost, and you can
      # poke your head in the GWIS/XML to see each step's edge weight.
      ('avg_cost',            None,   True,   None,  float,      3,),
      ('stale_steps',         None,   True,   None,    int,   None,),
      ('stale_nodes',         None,   True,   None,    int,   None,),

      # The travel mode indicates the planner used to generate the route.
      ('travel_mode',            0,   True,  False,    int,      0,),
      # When the user requests a new route, the client sends the planner
      # preferences separately, in the route_get command. When the user
      # modifies a route and saves a new version, the planner options are
      # also meaningless, since they apply only to generating the initial
      # route. However, that's not to say we can't at least send these
      # values to the client on route checkout. Historically, a user looking
      # at an old route wouldn't know what planner preferences were used to
      # generate that route. Well, now they will. Also, by sending these
      # values to the client, the client can help a user recreate a route
      # request, and not just by using the same destinations, but by
      # configuring the planner with the same options, too.
      # p1 Planner options.
      ('p1_priority',         None,   True,   None,  float,      3,),
      # p2 Planner options.
      # [lb] renamed the two multimodal preferences because android doesn't
      # use the multimodal planner, so we don't have to worry about backwards
      # compatibility by preserving the old GWIS name.
      ('p2_depart_at',          '',   True,   None,    str,      3,),
      ('p2_transit_pref',        0,   True,   None,    int,      3,),
      # p3 Planner options.
      ('p3_weight_attr',        '',   True,   None,    str,      3,),
      ('p3_weight_type',        '',   True,   None,    str,      3,),
      ('p3_rating_pump',         0,   True,   None,    int,      3,),
      ('p3_burden_pump',         0,   True,   None,    int,      3,),
      ('p3_spalgorithm',        '',   True,   None,    str,      3,),
      # Personalized Planner options (always-on in p1 and p2; opt-in in p3).
      # Skipping/meaningless to client: rating_min.
      # See __slots__ for 'tagprefs'.
      # MAYBE: Send tagprefs route each route back to client?
      ('tags_use_defaults',  False,   True,   None,   bool,      3,),

      # NOTE: We lock-down the z_level: it's neither sent to nor received from
      #       the client. The client figures out its own layering for routes.
      #       I [lb] think we only have it here to keep geofeature happy...
      # MAYBE: Just consolidate byway.z and route.z in geofeature.z.
      ('z',                   None,  False,   None,    int,      0,),
      ]
   attr_defns = geofeature.One.attr_defns + local_defns
   psql_defns = geofeature.One.psql_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = geofeature.One.psql_defns + local_defns

   ctrlled_tag_sids = None

   __slots__ = [
      # For a calculated route, rsteps is a list of route steps (or line
      # segments that determine the path of the route), and rstops is a
      # list of route stops (or important points to visit along the path).
      'rsteps', # In CcpV1, this was named 'path'.
      'rstops',
      'tagprefs',
      'stale_byway_sids',
      'stop_steps_stale',
      'filled_path',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      #self.geofeature_layer_id = Geofeature_Layer.Default
      geofeature.One.__init__(self, qb, row, req, copy_from)
      # In CcpV1, steps and stops were just lists, but in CcpV2 we've made 'em
      # true class objects.
      self.rsteps = route_step.Many()
      self.rstops = route_stop.Many()
      self.tagprefs = dict()
      self.filled_path = False
      if row is None:
         self.setup_item_revisionless_defaults(qb, force=True)

   #
   def __str__(self):
      return ('"%s" [%s] { beg: "%s" } { end: "%s" } %s'
              % (self.name,
                 self.__str_deets__(),
                 self.beg_addr,
                 self.fin_addr,
                 '[mode:%d|3attr:%s|p3wgt:%s|p3rat:%s|p3fac:%s|p3alg:%s]'
                 % (self.travel_mode,
                    self.p3_weight_attr,
                    self.p3_weight_type,
                    self.p3_rating_pump,
                    self.p3_burden_pump,
                    self.p3_spalgorithm,
                    ),))

   # *** GML/XML Processing

   #
   def append_gml(self, elem, need_digest):

      # Call base class. We could also do, e.g.,
      #   route_elem = elem.findall('./route')[0]
      route_elem = geofeature.One.append_gml(self, elem, need_digest)

      # notify the client if the sessions match, but we don't want to
      # actually send out session ids since the route may not be going to the
      # original creator.
      # NOTE: If the packet came locally from the route finder (for route
      # analysis), the req object is not set.

      log.verbose('append_gml: appending %d route steps' % (len(self.rsteps),))
      for rstep in self.rsteps:
         rstep.append_gml(route_elem)

      log.verbose('append_gml: appending %d route stops' % (len(self.rstops),))
      for rstop in self.rstops:
         rstop.append_gml(route_elem)

      return route_elem

   #
   def append_gml_geometry(self, new):
      gml.append_LineString(new, self.geometry_svg)

   #
   def from_gml(self, qb, elem):

      # The route analysis route finder ('analysis', not 'general') does not
      # save routes to the database, so the stack ID isn't set.
      if elem.get('stid') is None:
         elem.set('stid', '0')
         # MAYBE: Will stack_id=0 cause problems later?
         #        See item_versioned.from_gml.
         #        (But so far, [lb] hasn't noticed any issues... but he hasn't
         #         spent much time testing the route analysis tool recently).

      # Now call the base class (after making sure 'stid' is set).
      geofeature.One.from_gml(self, qb, elem)
      self.setup_item_revisionless_defaults(qb, force=True)

      # Loading rsteps and rstops is optional so that we can use this class
      # and this fcn. to load what CcpV1 calls route_metadata, or just details
      # about routes. In CcpV2, we don't want to repeat code, and we want to
      # use Many() and One() for route just like we do for other item classes.

      # Append the route steps to the route -- the route steps are the line
      # segments that each represent one byway.
      # NOTE: These should be the same: findall('./step/*'), findall('step').
      # MAYBE: Does/should this search use dont_fetchall? Should it?
      # MAYBE: This should be renamed 'rstep' but android still uses this name.
      for step in elem.findall('step'):
         rs = route_step.One()
         rs.from_gml(qb, step)
         self.rsteps.append(rs)

      # MAYBE: Does/should this search use dont_fetchall? Should it?
      # MAYBE: Use findall('./stop/*') instead of findall('stop')?
      #        Does it matter?
      # MAYBE: This should be renamed 'rstop' but android still uses this name.
      for stop in elem.findall('waypoint'):
         rw = route_stop.One()
         rw.from_gml(qb, stop)
         self.rstops.append(rw)

      if (not self.rsteps) or (not self.rstops):
         log.error('from_gml: no steps and/or stops: %d and/or %d'
                   % (len(self.rsteps), len(self.rstops),))
         # FIXME: This fcn. isn't called for style changes, is it?
         #        If not, we should raise an error.
         #        We'll find out if logcheck reports any of these errors...
         # MAYBE?: raise GWIS_Error('Missing steps or stops for route.')

   # ***

   #
   def as_gpx(self, db):

      # Bug 1126: lxml Python warnings in error.log.
      #           as_gpx() sets 'xmlns:xsi=asdf'
      #             and 'xsi:schemaLocation=asdf'
      #           When loading apache, it writes to
      #              /var/log/apache2/error.log:
      #           TagNameWarning: Tag names must not contain ':',
      #           lxml 2.0 will enforce well-formed tag names as
      #           required by the XML specification.

      # From: http://stackoverflow.com/questions/3685374/
      #  how-to-set-a-namespace-prefix-in-an-attribute-value-using-the-lxml
      # See also: http://lxml.de/tutorial.html#namespaces
      # Oh, wait, see also: http://stackoverflow.com/questions/8432912/
      #              lxml-tag-name-with-a

      # 2012.09.29: Adding nsmap and replacing colons with {}s.

      xsi = 'http://www.w3.org/2001/XMLSchema-instance'
      xmlns = 'http://www.topografix.com/GPX/1/1'
      schemaLocation = ('%s %s'
                        % ('http://www.topografix.com/GPX/1/1',
                           'http://www.topografix.com/GPX/1/1/gpx.xsd',))
      version = '1.1'

      # Define the namespace map.
      # Wrong: schema_nsmap = {'xmlns':'xmlns', 'xsi':'xsi',}
      #        This adds two attr-value pairs to the XML:
      #          <gpx xmlns:xmlns="xmlns" xmlns:xsi="xsi" ... />
      # Do this instead, per http://stackoverflow.com/questions/2850823/
      #                       multiple-xml-namespaces-in-tag-with-lxml
      schema_nsmap = {'xsi': xsi, None: xmlns,}

      gpx = etree.Element(
         '{%s}gpx' % (xmlns,),
         version=version,
         creator='Cyclopath - http://cyclopath.org',
         # lxml will remove the braces and replace with a trailing colon.
         attrib={'{%s}schemaLocation' % (xsi,): schemaLocation},
         nsmap=schema_nsmap)

      # build up the metadata element
      meta = etree.SubElement(gpx, 'metadata')
      author = etree.SubElement(meta, 'author')

      name = etree.SubElement(author, 'name')
      name.text = 'Cyclopath'

      email = etree.SubElement(author, 'email')
      misc.xa_set(email, 'id', 'info')
      misc.xa_set(email, 'domain', 'cyclopath.org')

      link = etree.SubElement(author, 'link')
      misc.xa_set(link, 'href', 'http://cyclopath.org')

      route = etree.SubElement(gpx, 'trk')
      comment = etree.SubElement(route, 'cmt')

      # 2012.09.26: FIXME: I'm not sure if we've set beg_addr and fin_addr...
      #                    but it feels like we should have.
      g.assurt(self.beg_addr == self.rstops[0].name)
      g.assurt(self.fin_addr == self.rstops[-1].name)

      beg_name = self.rstops[0].name
      if beg_name is None:
         beg_name = 'Point entered in map'

      fin_name = self.rstops[-1].name
      if fin_name is None:
         fin_name = 'Point entered in map'

      comment.text = beg_name + ' to ' + fin_name

      desc = etree.SubElement(route, 'desc')
      desc.text = 'Cyclopath route from ' + comment.text

      # FIXME: Why are route steps being append to 'trkseg', which sounds like
      #        something for tracks? Why 'trk'? Because GPX?
      track = etree.SubElement(route, 'trkseg')
      #
      # QUESTION: Does for i in xrange(len(y)) produce the
      #           same-ordered list as for x in y?
      #           I.e., why can't we for step in rsteps?
      # The code in CcpV1 seems weird since rsteps is already an ordered
      # sequence, but it xranged the list to send the route step its step
      # number.
      #  CcpV1: for i in xrange(len(self.rsteps))
      # But I think it may have been copied from save_core, where we use xrange
      # since the route steps have been assigned step_numbers yet.
      for step in self.rsteps:
         step.append_gpx(db, track, self)

      return gpx

   #
   def as_xml(self, db, as_gpx, appendage=None, appage_nom=None):

      if as_gpx:
         doc = self.as_gpx(db)
         g.assurt(not appendage)
      else:
         # This is a hack since routed calls this fcn. and we're not part of
         # the command hier.
         doc = etree.Element('data',
                  rid_max=str(revision.Revision.revision_max(db)),
                  major=VERSION.major,
                  gwis_version=conf.gwis_version)
         self.append_gml(doc, need_digest=False)
         if appendage:
            g.assurt(appage_nom)
            doc.find(appage_nom).append(appendage)

      return etree.tostring(doc, pretty_print=as_gpx)

   # FIXME: Check usages of this fcn., to make sure the returned result is
   # okay. The problem is that this fcn. (or the PostGIS fcn. it uses) finds
   # the line segment nearest the pt, and then finds the endpoint nearest that
   # pt. This affects the route finder, esp. when routing to/from a point near
   # a long line segment (the route finder will tell you to start/end at the
   # end point, but it probably makes more sense to find the vertex nearest the
   # point...).
   # BUG nnnn: Use m-values when routing. Client sends x,y pts to and from, and
   # we find the nearesy byways, so we should also find the m-value and send
   # that back so the client can draw the route line more accurately.
   @staticmethod
   def byway_closest_xy(qb, addr_name, pt_xy, rating_func, rating_min,
                            is_latlon, radius=None):
      '''Return the ID of the byway node nearest to pt_xy (x,y) which is on a
         byway with rating greater than or equal to rating_min for user
         username. On failure, raise GWIS_Error.'''
      closest_byway = None
      if not is_latlon:
         # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
         point_sql = geometry.xy_to_raw_point_lossless(pt_xy)
      else:
         # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
         point_sql = geometry.xy_to_raw_point_lossless(pt_xy,
                                                       srid=conf.srid_latlon)
         point_sql = "ST_Transform(%s, %d)" % (point_sql, conf.default_srid,)
      if radius is None:
         the_radius = conf.geocode_filter_radius # 1000
         # Don't do 100: it takes a long time.
         # 1000.0, 10000.0, 100000.0: 1, 10, 100 Km
         #magnitudes = (1, 10, 100,)
         # MAYBE: Even 10 seems way too far to look.
         magnitudes = (1, 10,)
      else:
         the_radius = radius
         magnitudes = (1,)
      g.assurt(qb.viewport.include is None)
      g.assurt(qb.viewport.exclude is None)
      g.assurt(qb.filters == Query_Filters(None))
      # FIXME: Skip this for-loop and test just slow to make sure it works.
      go_slow = False
      for scalar in magnitudes:
         try_radius = the_radius * scalar
         closest_byway = One.byway_closest_xy_find(
            qb, go_slow, rating_func, rating_min, point_sql, try_radius)
         if closest_byway is not None:
            break
         else:
            log.debug('byway_closest_xy/fast: not found at radius: %s'
                      % (try_radius,))
      if radius is None:
         if closest_byway is None:
            log.debug('byway_closest_xy/fast: no byway for point_sql: %s'
                      % (point_sql,))
            go_slow = True
            closest_byway = One.byway_closest_xy_find(
               qb, go_slow, rating_func, rating_min, point_sql)
         if closest_byway is None:
            log.warning('byway_closest_xy/slow: no byway for point_sql: %s'
                        % (point_sql,))
            raise GWIS_Error('No routable streets or trails near "%s".'
                             % (addr_name,))
      # Reset the filters... we checked above that these weren't special.
      qb.filters = Query_Filters(None)
      return closest_byway

   #
   # FIXME: 2012.08.02: Use new node_endpoint table?
   @staticmethod
   def byway_closest_xy_find(qb, go_slow, rating_func, rating_min, point_sql,
                             radius=None):
      ''' ... '''
      closest_byway = None
      g.assurt((not go_slow and radius is not None)
               or (go_slow and radius is None))
      g.assurt(qb.finalized)
      # FIXME: MAGIC NUMBER: Analyze loop and see if 10 should be increased.
      qb.filters.pagin_count = 10
      qb.filters.pagin_offset = 0
      give_up = False
      while not give_up:
         byways = byway.Many()
         byways.search_by_distance(qb, point_sql, radius)
         # sets 'st_line_locate_point', an m-value
         if len(byways) == 0:
            give_up = True
         else:
            closest_byway = One.byway_closest_xy_find_nearest(qb,
                                 byways, rating_func, rating_min)
            if closest_byway is not None:
               give_up = True
         if not give_up:
            log.info('byway_closest_xy_find: not giving up...')
            qb.filters.pagin_offset += qb.filters.pagin_count
      return closest_byway

   #
   @staticmethod
   def byway_closest_xy_find_nearest(qb, byways, rating_func, rating_min):
      closest_byway = None
      for byway_ in byways:
         # BUG 2340: Cannot always route to/from a point that gets
         # associated with a one_way, so, as a temporary solution, don't
         # choose the node of a one_way!
# FIXME: 2011.08.05: See Bug 2340, this is messing up route finder, e.g.,
# around humprey airport, it never chooses one_ways, but it should if you're
# traveling in that direction
# 2014.04.03: Can we just not choose a one-way for the origin?
         if (((rating_func is None)
              or (rating_func(byway_.stack_id) >= rating_min))
             # FIXME/BUG nnnn: Allow One-ways as O and/or D of O/D pair.
             and (byway_.one_way == 0)
             # Expressways and expressway ramps are never rideable.
             and (byway_.geofeature_layer_id
                  # See also:
                  #  byway.Geofeature_Layer.controlled_access_gfids
                  not in (byway.Geofeature_Layer.Expressway,
                          # NOTE: Some MnDOT ramps are not connected to
                          #       expressways. See: Other Ramp.
                          # We include ramps in routes, but not as O/D, since
                          # we don't know if this is a true xway ramp or not.
                          byway.Geofeature_Layer.Expressway_Ramp,
                          byway.Geofeature_Layer.Railway,
                          byway.Geofeature_Layer.Private_Road,))):
            # The byway has no rating fcn., or it's rated above the minimum;
            # the byway is not a one-way;
            # and the byway has a geofeature layer ID and isn't controlled,
            #  or an expressway ramp.
            # Now see that the byway isn't tagged impassable or controlled.
            is_controlled = False
            One.ensure_ctrlled_tags_loaded(qb)
            if One.ctrlled_tag_sids:
               where_branch = revision.Revision.branch_hier_where_clause(
                  qb.branch_hier,
                  'iv',
                  include_gids=False,
                  allow_deleted=False)
               lval_sql = (
                  """
                  SELECT lv.stack_id FROM link_value AS lv
                  JOIN item_versioned AS iv
                     USING (system_id)
                  WHERE lv.rhs_stack_id = %d
                    AND lv.lhs_stack_id IN (%s)
                    AND %s
                  """ % (byway_.stack_id,
                         ','.join([str(x) for x in One.ctrlled_tag_sids]),
                         where_branch,
                         ))
               rows = qb.db.sql(lval_sql)
               if len(rows) > 0:
                  is_controlled = True
            if not is_controlled:
               closest_byway = byway_
               break
      return closest_byway

   #
   @staticmethod
   def ensure_ctrlled_tags_loaded(qb):
      # This is kinduv a late minute hack: skip byways tagged impassable.
      if One.ctrlled_tag_sids is None:
         One.ctrlled_tag_sids = []
         qb.item_mgr.load_cache_attachments(qb)
         for tag_name in byway.Geofeature_Layer.controlled_access_tags:
            the_tag = qb.item_mgr.cache_tag_lookup_by_name(tag_name)
            if the_tag is None:
               log.warning('ensure_ctrlled_tags_loaded: Could not find tag: %s'
                           % (tag_name,))
            else:
               One.ctrlled_tag_sids.append(the_tag.stack_id)

   # *** Saving to the Database

   # FIXME: We need to add a row to route_step_count...
   #        Or maybe we can drop route_step_count and just add the column,
   #        step_count, to the route table?

   #
   def save_core(self, qb):

      log.debug('save_core: route: %s / no. rsteps: %s / no. rstops: %s'
                % (self, len(self.rsteps), len(self.rstops),))

      g.assurt(self.stack_id > 0)

      # FIXME: In CcpV1, we always make the stealth_secret/deep_link
      #        for public and shared routes. In CcpV2, we don't always.
      #        Make sure things still work well...
      # We could wait for the user to ask for a so-called "deep-link", or we
      # could just always make the new so-called "stealth secret". Realize that
      # the presense of the stealth secret doesn't mean it's usable: the route
      # still needs a GIA record for the public with a stealth access level.
      # For that reason, we wait to make the stealth secret until the user
      # wants it.

      # Save to the base class tables.
      geofeature.One.save_core(self, qb)

      # Save to the route table.
      self.save_insert(qb, One.item_type_table, One.private_defns)

      # FIXME: What if user is just changing a route's name or details, i.e.,
      # not changing any route stops. Do we still save a new version of the
      # route with new copies of the same rsteps and rstops? Seems like a waste
      # of space for editing metadata...
      # 2014.09.08: Verified: Bug nnnn/MAYBE: Changing just the route name
      # causes all the route steps to be saved again... except we're just
      # taking what the client sent us and not double-checking stack IDs!
      #
      # FIXME: Make a route_metadata table to store name, details, etc? And
      # then only change route.version and save a new route when rsteps or
      # rstops changes?

      # NOTE: Not doing (for step in self.rsteps) because step_numbering may
      # have changed (2012.09.27: I [lb] think; I'm just guessing).
      for i in xrange(len(self.rsteps)):
         self.rsteps[i].save_rstep(qb, self, i)

      for i in xrange(len(self.rstops)):
         self.rstops[i].save_rstop(qb, self, i)

      # Only save route parameters and tag preferences the first time.
      if self.version == 1:

         qb.db.insert(table='route_parameters',
                      id_cols={
                       'route_stack_id': self.stack_id,
                       'branch_id': self.branch_id,},
                      nonid_cols={
                       'travel_mode': self.travel_mode,
                       'p1_priority': self.p1_priority,
                       'p2_depart_at': self.p2_depart_at,
                       'p2_transit_pref': self.p2_transit_pref,
                       'p3_weight_attr': self.p3_weight_attr,
                       'p3_weight_type': self.p3_weight_type,
                       'p3_rating_pump': self.p3_rating_pump,
                       'p3_burden_pump': self.p3_burden_pump,
                       'p3_spalgorithm': self.p3_spalgorithm,
                       'tags_use_defaults': self.tags_use_defaults,
                       },
                      skip_empties=True)

         for t in self.tagprefs:
            qb.db.insert('route_tag_preference',
                         {'route_stack_id': self.stack_id,
                          'branch_id': self.branch_id,
                          'tag_stack_id': t,},
                         {'tpt_id': self.tagprefs[t],})

      # MAYBE: This belongs in save_related_maybe. Maybe some of the previous
      #        code, too...
      # Record a route view if this is a new, user-requested route.
      if ((self.client_id < 0)
          and (self.fresh)
          and (qb.username != conf.anonymous_username)):
         # NOTE: Not locking since we're insert_clobbering a row in route_view
         #       and already have the primary keys (route_id and username)...
         #       FIXME: Isn't there already a lock on 'revision', anyway?
         g.assurt(self.version == 1)
         ## NO: qb.db.lock_table('route_view', 'EXCLUSIVE')
         # NO: qb.db.lock_table('route_view', 'SHARE ROW EXCLUSIVE')
         qb.db.insert_clobber(
            'item_findability',
            {'username': qb.username,
             'item_stack_id': self.stack_id,},
            {'user_id': qb.user_id,
             # New routes are hidden by default; the user 'saves' the route
             # if they want it in their library, or to edit its permissions.
             'library_squelch': Library_Squelch.squelch_always_hide,
             'show_in_history': True,
             # Trigger will set: last_viewed.
             'branch_id': self.branch_id,})

   # ***

   #
   def save_init_item_findability(self, qb, username, user_id):

      # This probably belongs in a base or utility class. But route is the only
      # class to do this so far... well, see also similar code in route_get.py.

      sql_exists_itm_fbily = (
         """
         SELECT *
           FROM item_findability
          WHERE item_stack_id = %d
            AND username = %s
            AND branch_id = %d
         """ % (self.stack_id,
                qb.db.quoted(username),
                qb.branch_hier[0][0],))
      rows = qb.db.sql(sql_exists_itm_fbily)

      if not rows:
         sql_update_itm_fbily = (
            """
            INSERT INTO item_findability
               (item_stack_id,
                username,
                user_id,
                library_squelch,
                show_in_history,
                branch_id)
            VALUES
               (%d, %s, %d, %d, %s, %d)
            """ % (self.stack_id,
                   qb.db.quoted(username),
                   user_id,
                   Library_Squelch.squelch_always_hide,
                   'FALSE', # show_in_history,
                   qb.branch_hier[0][0],))
         qb.db.sql(sql_update_itm_fbily)

   #
   def save_related_maybe(self, qb, rid):
      geofeature.One.save_related_maybe(self, qb, rid)
      # Update the node columns. This just has to come after save_rstep (which
      # happens in save_core). Oh, and we need a system_id.
      g.assurt(self.system_id > 0)
      # FIXME: If we're just changing GIA permissions (not recomputing the
      # route) we should skip the stats update (which recalculates the
      # beg_addr, fin_addr, route_len, route_step geometry, etc).
      sole_row = Many.update_node_stats(qb, system_id=self.system_id)
      if sole_row:
         self.beg_addr = sole_row['beg_addr']
         self.fin_addr = sole_row['fin_addr']
         if sole_row['lhs_forward']:
            self.beg_nid = sole_row['lhs_beg_node_id']
         else:
            self.beg_nid = sole_row['lhs_fin_node_id']
         # MAYBE/EXPLAIN: Is the final node ID the first or last node
         #                of the last route step byway?
         if sole_row['rhs_forward']:
            self.fin_nid = sole_row['rhs_fin_node_id']
         else:
            self.fin_nid = sole_row['rhs_beg_node_id']
         self.rsn_min = sole_row['step_count_min']
         self.rsn_max = sole_row['step_count_max']
         self.n_steps = sole_row['step_count_count']
         self.rsn_len = round(sole_row['steps_total_len'], 1)
      else:
         g.assurt_soft(False)
      # Checkout the missing columns that just got writ and update some attrs.
      self.savex_fetch_calculated_node_stats(qb)
      # Save item_findability records so the route is not shown in the library.
      self.save_init_item_findability(qb, conf.anonymous_username,
                                          User.user_id_from_username(qb.db,
                                                   conf.anonymous_username))
      # See save_core for what's essentially the following:
      #   if qb.username != conf.anonymous_username:
      #      self.save_init_item_findability(qb, qb.username, qb.user_id)

   #
   def savex_fetch_calculated_node_stats(self, qb):

      # SYNC_ME: See Many.update_node_stats_process.
      #
      # Ignoring: beg_addr, fin_addr,
      #           rsn_min, rsn_max, n_steps,
      #           beg_nid, fin_nid
      #
      # MAYBE: See update_node_stats; we shouldn't need to do this:
      fetch_sql = ("SELECT rsn_len FROM route WHERE system_id = %d"
                   % (self.system_id,))

      rows = qb.db.sql(fetch_sql)

      if len(rows) == 1:
         row = rows[0]
         if (self.rsn_len) and ((self.rsn_len - row['rsn_len']) > 1.0):
            # The static update_node_stats fcn. computes route stats,
            # and in save_related_maybe we apply those values to the
            # route object, so what we just found in the database should
            # be what we just wrote to the database. Or close enough.
            log.warning('fetch_calcd_nd_stats: unexpected: rsn_len: %s / %s'
                        % (self.rsn_len, row['rsn_len'],))
         self.rsn_len = row['rsn_len']
      else:
         log.error('fetch_calcd_nd_stats: nothing found sys_id: %d / rows: %d'
                   % (self.system_id, len(rows),))

      if self.avg_cost is None:

         self.avg_cost = float('inf')

         # If we load the route from memory, we'll call self.fill_path, but
         # if the route is from a client, it contains lightweight route
         # steps, i.e., just the byway stack ID, and not rating or geometry.
         # We could call byway.Many to load all the byways in the route, and
         # to grab the ratings and geometries from there, but the client
         # doesn't look for rsn_len or avg_cost in the commit response, so
         # we're fine skipping this calculation if not filled_path.

         if self.rsn_len and self.filled_path:

            cumulative_cost = 0.0

            for step in self.rsteps:

               step.calc_length_and_cost()
               try:
                  cumulative_cost += step.edge_weight
               except TypeError:
                  # NOTE: The step.rating is the generic rating...
                  #       so if the cost is the length, this is the
                  #       wrong value...
                  cumulative_cost += step.rating * step.edge_length
            self.avg_cost = (
               (cumulative_cost / route_step.One.weight_multiplier)
               / self.rsn_len)
            log.debug('fetch_calcd_nd_stats: avg_cost: %s' % (self.avg_cost,))

         # end: if self.rsn_len

      # end: if self.avg_cost is None

   #
   def setup_item_revisionless_defaults(self, qb, force=False):
      geofeature.One.setup_item_revisionless_defaults(self, qb, force=True)

   #
   def validize_geom(self, qb, is_new_item, ref_item):
      # Currently, routes themselves are geometry-less. Even though they
      # derived from geofeature.
      # NO: geofeature.One.validize_geom(self, qb, is_new_item, ref_item)
      pass

   #
   def version_finalize_and_increment(self, qb, rid, same_version=False,
                                                     same_revision=False):
      geofeature.One.version_finalize_and_increment(self, qb, rid, 
                                                    same_version,
                                                    same_revision)

   # *** Other methods

   #
   def fill_tagprefs(self, qb):

      # Older android will continue to send Travel_Mode.bicycle, but for newer,
      # non-personalized p3, we can ignore tag preferences.

      if ((self.travel_mode in (Travel_Mode.bicycle,
                                Travel_Mode.classic,))
          or ((self.travel_mode == Travel_Mode.wayward)
              # MAGIC_NUMBER: 'p' as in 'prat', 'pfac', 'rac'.
              and (self.p3_weight_type.startswith('p')))):

         prefs = qb.db.sql(
            """
            SELECT
               tag_stack_id,
               tpt_id
            FROM
               route_tag_preference
            WHERE
               route_stack_id = %d
               AND branch_id = %d
            """ % (self.stack_id,
                   self.branch_id,))

         for row in prefs:
            self.tagprefs[row['tag_stack_id']] = int(row['tpt_id'])

   #
   def fill_path(self, qb):
      #
      # Before running this function, it is is mandatory to run fill_tagprefs()
      #

      # compute bonus and penalty tag sets now, we'll need them to
      # compute the bonus/penalty flags and modified ratings for
      # rating steps (loaded below)

      bonus_tags = set([t for t in self.tagprefs
                        if self.tagprefs[t] == ratings.t_bonus])
      penal_tags = set([t for t in self.tagprefs
                        if self.tagprefs[t] == ratings.t_penalty])

      log.debug('fill_path: bonus_tags: %s / penal_tags: %s'
                % (bonus_tags, penal_tags,))

      # Rating sql

      rating_sql = self.prepare_rating_sql(qb)

      # Route steps

      # MAYBE: Move this code to route_step.

      # read in all route steps, including geometry and elevation
      # tag preferences and ratings will be read in per-step below

      # BUG NNNN: (probably CcpV1, too): Byway Rating missing from
      #           routes loaded from route library.
      # BUG nnnn: loading routes is slow -- ratings loaded one by one.

      # NOTE: Left-outer-joining geofeature et al. so that we don't exclude
      #       transit steps.
      rsteps_sql = (
         """
         SELECT

            DISTINCT ON (rs.route_id, rs.step_number)
            rs.route_id,
            rs.step_number,

            rs.route_stack_id,
            rs.route_version,
            rs.byway_id,
            rs.byway_stack_id,
            rs.byway_version,
            --iv.valid_until_rid AS byway_until_rid,

            COALESCE(rs.step_name, iv.name) AS step_name,

            rs.beg_time,
            rs.fin_time,

            rs.travel_mode,

            length2d(gf.geometry) AS length,
            rs.forward,

            gf.geofeature_layer_id AS byway_geofeature_layer_id,

            gf.beg_node_id,
            gf.fin_node_id,
            gf_latest.beg_node_id AS latest_beg_node_id,
            gf_latest.fin_node_id AS latest_fin_node_id,
            --gf.one_way AS byway_one_way,
            gf_latest.beg_node_id AS latest_one_way,

            CASE
               WHEN transit_geometry is null
               THEN ST_AsSVG(ST_Scale(gf.geometry, 1, -1, 1), 0, %d)
               ELSE ST_AsSVG(ST_Scale(transit_geometry, 1, -1, 1), 0, %d)
            END AS geometry,

            -- These are not used:
            nel_iv.name AS node_lhs_name,
            ner_iv.name AS node_rhs_name

         FROM route_step AS rs

         LEFT OUTER JOIN geofeature AS gf
              ON (gf.system_id = rs.byway_id)
         LEFT OUTER JOIN item_versioned AS iv
              ON (iv.system_id = gf.system_id)

         LEFT OUTER JOIN geofeature AS gf_latest
              ON (gf_latest.stack_id = rs.byway_stack_id)
         LEFT OUTER JOIN item_versioned AS iv_latest
              ON (iv_latest.system_id = gf_latest.system_id)

         LEFT OUTER JOIN node_endpoint AS nel
              ON (nel.stack_id = gf.beg_node_id)
         LEFT OUTER JOIN item_versioned AS nel_iv
              ON (nel_iv.system_id = nel.system_id)

         LEFT OUTER JOIN node_endpoint AS ner
              ON (ner.stack_id = gf.fin_node_id)
         LEFT OUTER JOIN item_versioned AS ner_iv
              ON (ner_iv.system_id = ner.system_id)

         WHERE
            rs.route_id = %d
            -- MAYBE: Only supporting latest elevation data, i.e., not historic
            AND nel_iv.valid_until_rid = %d
            AND ner_iv.valid_until_rid = %d
            AND iv_latest.valid_until_rid = %d
         ORDER BY
            rs.step_number ASC
         """ % (conf.db_fetch_precision,
                conf.db_fetch_precision,
                self.system_id,
                conf.rid_inf,
                conf.rid_inf,
                conf.rid_inf,
                ))

      time_0 = time.time()

      rstep_rows = qb.db.sql(rsteps_sql)

      log.debug('fill_path: found %d route steps in %s'
         % (len(rstep_rows), misc.time_format_elapsed(time_0),))

      time_0 = time.time()

      self.stale_nodes = 0
      self.stale_byway_sids = []
      self.stop_steps_stale = {}
      #self.stale_steps = 0
      # Primer. So that we have all stop numbers ready to iterate.
      for stop_num in xrange(len(self.rstops)):
         self.stop_steps_stale[stop_num] = []

      curr_stop_num = 0
      last_stop_num = len(self.rstops) - 1
      next_stop = None

      last_rstep = None

      rstep_num = 0

      gap_hack = None

      for row in rstep_rows:

         step = route_step.One(qb, row=row)

         if last_rstep is not None:
            # 2013.04.29: Query above was not DISTINCTing, so we were seeing
            #             contiguous route steps for the same byway segment.
            g.assurt(last_rstep != step)
         else:
            # E.g., self.rstops[0].stop_step_number = 0
            self.rstops[curr_stop_num].stop_step_number = rstep_num

         if step.byway_stack_id is not None:

            # MAYBE: It's up to the client to send all these values.
            #        Should we verify them? Or maybe just fetch the
            #        system_id so the client doesn't have to send it?
            g.assurt(step.byway_id > 0)
            g.assurt(step.byway_stack_id > 0)
            g.assurt(step.byway_version > 0)

            if last_rstep is None:
               # This happens only the first time through the for loop.
               warn_nid = False
               if step.forward:
                  if self.rstops[0].node_id != step.beg_node_id:
                     warn_nid = True
               else:
                  if self.rstops[0].node_id != step.fin_node_id:
                     warn_nid = True
               if warn_nid:
                  # This might happen if the user drags an endpoint
                  # destination, since the node ID will be unique and not match
                  # a road? Or do we always snap to the closest byway node?
                  log.warning(
                     'fill_path: rstops[0].nid != step[0].nid: %s / %s'
                     % (self.rstops[0], step,))
               self.rstops[curr_stop_num].stop_step_number = rstep_num # 0
               next_stop = self.rstops[curr_stop_num+1] # I.e., [1]

            # We could compare byway_one_way != latest_one_way
            # but checking latest_one_way vs. step.forward seems
            # more properer.
            if (   (step.beg_node_id != step.latest_beg_node_id)
                or (step.fin_node_id != step.latest_fin_node_id)
                or ((step.latest_one_way == 1) and (not step.forward))
                or ((step.latest_one_way == -1) and (step.forward))):
               self.stale_nodes += 1
               # We really only need this list when route is fetched w/
               # check_invalid.
               self.stale_byway_sids.append(step.byway_stack_id)
               misc.dict_list_append(self.stop_steps_stale,
                                     curr_stop_num,
                                     step.byway_stack_id)
            #if step.byway_until_rid < conf.rid_inf:
            #   self.stale_steps += 1

            # Check if this edge starts from a route stop. This applies to
            # all route stops except the last, 'natch.
            if (rstep_num > 0) and (curr_stop_num < last_stop_num):
               found_next_stop = False
               if next_stop.node_id == step.beg_node_id:
                  if step.forward:
                     found_next_stop = True
                     gap_hack = None
                  else:
                     # This should be the route step leading into the stop,
                     # and the next step is the one we want, leading away.
                     # Unless this is one of the buggy routes...
                     gap_hack = step
               elif next_stop.node_id == step.fin_node_id:
                  if not step.forward:
                     found_next_stop = True
                     gap_hack = None
                  else:
                     # This should be the route step leading into the stop.
                     gap_hack = step
               elif gap_hack is not None:
                  # This step does not share a node with the last
                  # step, and the last step was a stop... oy.
                  log.warning('fill_path: gap_hack: step: %s / %s'
                              % (str(step), self,))
                  curr_stop_num += 1
                  self.rstops[curr_stop_num].stop_step_number = rstep_num - 1
                  next_stop = self.rstops[curr_stop_num+1]
                  gap_hack = None

               elif next_stop.node_id == 0:
# FIXME/BUG nnnn: Fix routes in db with missing node IDs
# ccpv3_live=> select * from _rt_stop where rt_stk_id = 4120056;
#  rt_v | stop |      rs_nom      |     x     |     y      |  nd_id  |
# ------+------+------------------+-----------+------------+---------+
#     1 |    0 | Gateway Fountain | 478882.96 | 4981091    | 1301266 |
#     1 |    1 | Edina, MN        | 472560.76 | 4973173.34 | 1239800 |
#     2 |    0 | Gateway Fountain | 478882.96 | 4981091    | 1301266 |
#     2 |    1 |                  | 474846.40 | 4975076.5  |       0 |
#     2 |    2 | Edina, MN        | 472560.76 | 4973173.34 | 1239800 |
                 pass

               if found_next_stop:
                  curr_stop_num += 1
                  self.rstops[curr_stop_num].stop_step_number = rstep_num
                  next_stop = self.rstops[curr_stop_num+1]

            # Query to get rating (user's or generic rater's).
            #
            # MAYBE: Do one bulk SQL for ratings rather than loading them each
            #        individually. E.g., move this sql() outside of the for
            #        loop and run it just once... [lb] usually sees fetching
            #        all the rows one of the time as being faster than fetching
            #        one of the rows all of the time (i.e., for any SQL query,
            #        and not just for ratings).
            # BUG nnnn/INVESTIGATE: Try a long route without getting personal
            #                       ratings and see if checking out existing
            #                       routes is any faster. If so, rework this
            #                       sql so we get all ratings in one SQL query.
            #
            rating_rows = qb.db.sql(rating_sql % (step.byway_stack_id,))
            if len(rating_rows) > 0:
               rating = rating_rows[0]['value']
            else:
               rating = None

            if bonus_tags or penal_tags:
               # query to get tag applications on route-step's byway segment
               # FIXME: this query is similar to tag query in ratings.py.
               # FIXME: This ignores permissions.
               # FIXME: Maybe we should get all the byway stack IDs for all the
               #      route steps and bulk-load the byways with tags populated?
               tag_rows = qb.db.sql(
                  """
                  SELECT
                     lv.lhs_stack_id AS tag_id
                  FROM
                     link_value AS lv
                  JOIN group_item_access AS gia
                     ON (gia.item_id = lv.system_id
                         AND gia.item_type_id = %d)
                  WHERE
                     lv.branch_id = %d
                     AND gia.valid_until_rid = %d
                     AND gia.link_lhs_type_id = %d
                     AND gia.link_rhs_type_id = %d
                     AND NOT gia.deleted
                     AND lv.rhs_stack_id = %d
                  """ % (Item_Type.LINK_VALUE,
                         self.branch_id,
                         conf.rid_inf,
                         Item_Type.TAG,
                         Item_Type.BYWAY,
                         step.byway_stack_id,))

               block_tags = set([int(t['tag_id']) for t in tag_rows])
               bonus_ct = len(bonus_tags & block_tags)
               penal_ct = len(penal_tags & block_tags)
            else:
               bonus_ct = 0
               penal_ct = 0

            # Update step based on tagging/rating information.
            if rating is not None:
               step.rating = ((rating + bonus_ct * 5.0 + penal_ct * 0.5)
                              / (1 + bonus_ct + penal_ct))
            else:
               # EXPLAIN: This path ignored in CcpV1. Why?
               # See, e.g.: 1416896 (W Bush Lake Rd).
               #            Where's its generic rating?
               #            It's just got three user ratings...
               #            and it's deleted!
               # Ideally, we'd log a warning if not byway.deleted,
               # but we don't have a handle on the byway, and it's
               # not important enough to add more SQL.
               log.debug('fill_path: no generic rating: byway prob deleted: %s'
                         % (str(step),))
            step.bonus_tagged = (bonus_ct > 0);
            step.penalty_tagged = (penal_ct > 0);

         else:
            # This is a transit step that isn't tied to a rateable byway.
            step.rating = 3.0
            step.bonus_tagged = 0.0
            step.penalty_tagged = 0.0

         self.rsteps.append(step)

         rstep_num += 1

         last_rstep = step

      # end: for row in rstep_rows

      self.rstops[-1].stop_step_number = rstep_num - 1

      # There's at least one route, e.g., Stk ID 1582594,
      # that has a route stop whose node ID only matches one of the
      # route steps (in the example route, named "molly quinn to Humphry"
      # the edge leading into the stop shares a node ID, but not the
      # escape edge. I [lb] also see that version=2 of the route steps
      # have no names in the database, so it looks like there were some
      # issues when the route was last saved.
      rstop_i = 0
      while rstop_i < len(self.rstops):
         try:
            self.rstops[rstop_i].stop_step_number
            # Success!
         except AttributeError:
            log.warning('did not find route step for route stop: %d / %s'
                        % (rstop_i, self,))
            if rstop_i <= 0:
               step_num = 0
            elif rstop_i >= (len(self.rstops) - 1):
               step_num = len(self.rsteps)
            else:
               step_num = self.rstops[rstop_i-1].stop_step_number
            self.rstops[rstop_i].stop_step_number = step_num
         rstop_i += 1

      if (curr_stop_num + 1) != last_stop_num:
         log.warning(
            'fill_path: curr_stop_num + 1 != last_stop_num: %d + 1 != %d'
            % (curr_stop_num, last_stop_num,))

      log.debug('fill_path: processed %d route steps in %s'
         % (len(rstep_rows), misc.time_format_elapsed(time_0),))

      log.debug('fill_path: stale_nodes: %d' % (self.stale_nodes,))

      self.filled_path = True

   #
   def prepare_rating_sql(self, qb):
      # Create a sql string that will load a user's rating on a byway,
      # Or the generic rating if there is no user or the user hasnt rated it
      if qb.username == conf.anonymous_username:
         rating_sql = (
            """
            SELECT
               value
            FROM
               byway_rating
            WHERE
               username = '%s'
               AND byway_stack_id = %%d
               AND branch_id = %d
            """ % (conf.generic_rater_username,
                   self.branch_id,))
      else:
         rating_sql = (
            """
            SELECT
               CASE WHEN r2.value IS NULL
                    THEN r1.value
                    ELSE r2.value
            END AS value
               FROM
                  byway_rating AS r1
               LEFT JOIN
                  byway_rating AS r2
                     ON (r2.byway_stack_id = r1.byway_stack_id
                         AND r2.branch_id = r1.branch_id
                         AND r2.username=%s)
               WHERE
                  r1.username = '%s'
                  AND r1.byway_stack_id = %%d
                  AND r1.branch_id = %d
               """ % (qb.db.quoted(qb.username),
                      conf.generic_rater_username,
                      self.branch_id))
      return rating_sql

   # ***

   #
   def steps_fill_geometry(self, qb):

      # NOTE: This uses the route's path to construct the geometry. It does
      #       not assume that the route is actually one that is saved in the
      #       database.
      #       Currently it's just used by route analysis to make WKT for
      #       the Shapefile.

      byway_ids = list()
      for rstep in self.rsteps:
         byway_ids.append(rstep.byway_id)

      res = qb.db.sql(
         """
         SELECT
            ST_AsText(ST_Collect(gf.geometry)) AS geometry_wkt
         FROM
            geofeature AS gf
         WHERE
            gf.system_id IN (%s)
         """ % (", ".join(map(str, byway_ids)),))
      g.assurt(len(res) == 1)

      self.set_geometry_wkt(res[0]['geometry_wkt'], is_changed=True)

   #
   # Similar To (S.t.) item_user_access.prepare_and_save_item
   def prepare_and_commit_revisionless(self, qb, grac_mgr):

      log.debug('prepare_and_commit_revisionless: saving route to database')

      # MAYBE: Use the geometry field? We at least have to make it
      #        POLYGON EMPTY or LINESTRING EMPTY (they're both the same value,
      #        so it doesn't matter: 01070000202369000000000000 (if you use
      #        ST_AsText you'll get GEOMETRYCOLLECTION EMPTY)).
      # No: self.set_geometry_wkt(geometry_wkt=None, is_changed=None)
      if not self.geometry_wkt:
         self.geometry_wkt = 'LINESTRING EMPTY'
      else:
         log.warning('prep_n_commit_rvsnlss: Unexpected: geometry_wkt?: %s'
                     % (str(self),))

      # Since we're using an existing revision ID and using the sequences to
      # get new stack IDs and system IDs, we don't need to lock any tables,
      # and we don't need to worry about duplicate IDs since we just got new
      # ones from the sequences. So start a r/w session but don't bother
      # locking any tables.
      qb.db.transaction_begin_rw()

      # NOTE: Trample grac_mgr and ignore item_mgr. This has to come after
      # starting the rw transaction, since prepare_mgr gets row locks on NIP.
      qb.grac_mgr = grac_mgr
      qb.grac_mgr.prepare_mgr('user', qb)

      # In old CcpV1 (before route sharing), valid_start_rid existed but wasn't
      # used (it was added in schema script 058; though the table had a
      # last_modified column since 008 until it got recreated as the created
      # column in 067, and last_modified wasn't dropped until 079, and then
      # created was booted in 246, replaced by item_revisionless.edited_date).
      # So the V1->V2 SQL update just tags all the routes without revisions as
      # being revisioned at the revision of the upgrade. This should be fine,
      # since we also don't have access records for the old routes (so old
      # routes are just used for research purposes only, while new routes can
      # be added to a user's route library, etc.).
      #
      # Also in old CcpV1, all saved route changes are revisioned. Which floods
      # the revision history with "auto-updated" revisions (whenever someone
      # opens a route whose streets have been edited, the route is updated and
      # auto-saved, and the revision history reflects this).
      #
      # In CcpV2, [lb] argues that the revision history should be for
      # meaningful map edits, and not for routes. The only drawback is that
      # you cannot revert route edits, but the CcpV1 behavious is so buggy!
      #
      # BUG nnnn/CcpV1: Whenever you load a route, it rechecks road geometry.
      #                 Even if you don't save 'Use Suggested Fix', the route
      #                 is saved with a new revision. If you refresh
      #                 flashclient and reopen the map, the same thing happens!
      #                 That is, another revision is created and the route is
      #                 saved again! This is probably because the route fetch
      #                 is thinking the route was last updated and the current
      #                 revision minus one, even though the new revision was
      #                 only because of route changes! In other words, the
      #                 route finder thinks that all revision changes
      #                 necessitate rechecking routes, even though, in CcpV1
      #                 since route sharing was added, most revisions are just
      #                 routes been auto-updated. Oy!
      #
      # Bug nnnn/CcpV1: Like I said above, if you don't revision routes, you
      #                 cannot revert them, but in CcpV1, you cannot tell what
      #                 route you're reverting, anyway! If you
      #
      # Bug nnnn/CcpV1: It seems like loading a route from the library always
      #                 takes a while becuase the route is being recomputed.
      #                 Another forehead-slapper! We should load the route
      #                 first, and then flashclient should ask the server --
      #                 in the background, so the user can start working with
      #                 the route -- if anything changed, and then flashclient
      #                 can reveal a widget if an updated route is returned.
      #
      qb.item_mgr.start_new_revision(qb.db, use_latest_rid=True)
      log.debug('prep_n_commit_rvsnlss: using latest rev for new rt: rev ID %d'
                % (qb.item_mgr.rid_new,))

      # To set the stack ID, if we were making a new revision, we'd use
      # negative client IDs, e.g.,
      #   self.stack_id = -1
      #   self.stack_id_correct(qb)
      # But we're not making a new revision, so we can just pluck the next
      # stack ID value directly from the sequence.
      if self.stack_id < 0:
         client_id = self.stack_id
      if (self.stack_id is None) or (self.stack_id < 0):
         self.stack_id = qb.item_mgr.seq_id_steal_stack_id(qb.db)
         g.assurt(self.version == 0)
         self.fresh = True
      else:
         # Otherwise, keep the same stack ID. We'll also keep the same version.
         g.assurt(self.version > 0)
         pass
      g.assurt(self.stack_id > 0)

      log.debug('prep_n_commit_rvsnlss: clearing item_cache')
      qb.item_mgr.item_cache_reset()
      qb.item_mgr.item_cache_add(self, client_id)

      # See init_permissions_new: this sets arbiter for either the session
      # group or the user's private group, depending.

      # The default behavior gives the user arbiter access to the route, so
      # it'll show up in route search and route library. Users use
      # route_view.active to remove a route from their library and search
      # results.
      #
      # FIXME: Option to include inactive route in searches. Also make sure
      #        searches and the library are filtered by inactive. And maybe
      #        rename active to something more unique.

      # FIXME: route_view.active should be True for this route. Is it?

      # FIXME: See notes in scripts/schema/201-apb-60-groups-pvt_ins3.sql
      #        Should we add access for the basemap owners group?
      #        Or make a new group, called, route-spy?

      prepared = qb.grac_mgr.prepare_item(qb,
         self, Access_Level.editor, ref_item=None)
      g.assurt(prepared)

      # Save a newly requested route.
      # MAYBE: Does this handle an updated, existing route?
      g.assurt(self.version == 0)
      self.version_finalize_and_increment(qb, qb.item_mgr.rid_new,
                                              same_version=False)
      g.assurt(self.version == 1)
      self.save(qb, qb.item_mgr.rid_new)

      try:
         # BUG 2688: Use transaction_retryable?
         qb.db.transaction_commit()
      except psycopg2.IntegrityError, e:
         # This can happen if a user edits a byway in the live database,
         # and then we use a Shapefile from that database to start the
         # route finder, and our test database is older than the edit.
         advice = 'If testing, update to latest live snapshot.'
         log.error('prep_n_commit_rvsnlss: %s (%s)'
                   % (str(e), advice,))
         raise

      log.debug('prep_n_commit_rvsnlss: save completed')

   # ***

   #
   def compute_stats_raw(self):
      '''
      Called to compute some stats about the route, if update_node_stats
      not being called because this is a transient route and not being
      saved to the database. The update_node_stats fcn. calculates stats
      using SQL; we have to do it using Python maths.
      '''
      # See: Many.node_bulk_update. We populate the same columns it does.

      # Skipping: self.system_id, since this route isn't saved.

      # Skipping: self.beg_addr and self.fin_addr, since they're already set.

      step_count_min = sys.maxint #float('inf')
      step_count_max = -sys.maxint #float('-inf')
      step_count_count = 0
      steps_total_len = 0.0
      cumulative_cost = 0.0
      for step in self.rsteps:
         step_count_min = min(step_count_min, step.step_number)
         step_count_max = max(step_count_max, step.step_number)
         step_count_count += 1
         step.calc_length_and_cost()
         steps_total_len += step.edge_length
         cumulative_cost += step.edge_weight

      self.rsn_min = step_count_min
      self.rsn_max = step_count_max
      self.n_steps = step_count_count
      self.rsn_len = steps_total_len
      if self.avg_cost is None:
         if self.rsn_len:
            self.avg_cost = (
               (cumulative_cost / route_step.One.weight_multiplier)
               / float(self.rsn_len))
            log.debug('compute_stats_raw: avg_cost: %s' % (self.avg_cost,))
         else:
            self.avg_cost = float('inf')

      if self.rsteps[0].forward:
         self.beg_nid = self.rsteps[0].beg_node_id
      else:
         self.beg_nid = self.rsteps[0].fin_node_id

      if self.rsteps[-1].forward:
         self.fin_nid = self.rsteps[-1].beg_node_id
      else:
         self.fin_nid = self.rsteps[-1].fin_node_id

   # ***

   #
   def get_friendly_name(self):
      '''Compute the newly-requested route's friendly (default) name.'''

      # NOTE: This fcn. runs in the context of the route finder because it
      # requires that route_step.edge_length be set. The edge_length is
      # only set by the route finder. Don't call this fcn from apache-pyserver.

      # In old CcpV1, before route sharing, new routes were assigned a name and
      # a (long) timestamp.
      #     'New Route %s' % (time.strftime('%I:%M %m-%d-%y',
      #                       time.localtime(time.time())),),

      # MAYBE: This algorithm is pretty cool -- it finds the edge name
      # travelled the longest and uses that for the new route name. But maybe
      # we want to include the beg_stop or fin_stop, or maybe the date? Or do
      # those belong as metadata, i.e., so the client can display those
      # independently (e.g., the date could be in smaller font, or the user
      # could choose to show/hide the route stop names).

      if self.rsteps:

         steps_dict = dict()

         for step in self.rsteps:

            # Add step to dictionary, if it doesn't exist.
            steps_dict.setdefault(step.step_name, 0)

            # Compute effective length.
            if self.travel_mode != Travel_Mode.transit:
               # For bike-only route, length is distance.
               if step.edge_length is not None:
                  length_eff = step.edge_length
               else:
                  length_eff = 0
            else:
               # For transit route, length is time.
               if ((step.beg_time is not None)
                   and (step.fin_time is not None)):
                  length_eff = step.fin_time - step.beg_time
               else:
                  length_eff = 0

            # Aggregate effective length by step name.
            steps_dict[step.step_name] += length_eff

         # Find longest step.
         max_len = 0
         smart_name = ''
         for step_name in steps_dict:
            if steps_dict[step_name] > max_len:
               max_len = steps_dict[step_name]
               smart_name = step_name

         # Finalise the smart name.
         friendly_name = 'Route via %s' % (smart_name,)

      else:

         # This route doesn't have any route steps.

         # Normally a route will have route steps. But if it doesn't...
         # well, we could leave the route titled 'Untitled', or we could say
         # something about this route not having any route steps.

         # MAYBE: Use the names of the route stops?

         log.warning('set_friendly_name: route has no steps')

         friendly_name = 'Untitled (Empty Route)'

      return friendly_name

   #
   def set_friendly_name(self):
      self.name = self.get_friendly_name()

   # ***

# ***

# FIXME: routes are supposed to be appended to the Many, not returned from
#        search functions
class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   sql_clauses_cols_all = geofeature.Many.sql_clauses_cols_all.clone()

   # NOTE: Not sending z (z_level), since it's always the same value (160).
   #       MAGIC_NUMBER: 160 is route z-level.
   sql_clauses_cols_all.inner.shared += (
      """
      , rt.details
      , rt.beg_addr
      , rt.fin_addr
      , rt.rsn_len
      --, rt.travel_mode
      , rt_ps.travel_mode
      , rt_ps.p1_priority
      , rt_ps.p2_depart_at
      , rt_ps.p2_transit_pref
      , rt_ps.p3_weight_attr
      , rt_ps.p3_weight_type
      , rt_ps.p3_rating_pump
      , rt_ps.p3_burden_pump
      , rt_ps.p3_spalgorithm
      , rt_ps.tags_use_defaults
      """
      )

   # We shouldn't have to outer join route_parameters,
   # but if it's missing any rows, than the client
   # might be able spot errors, since we don't have
   # any table constraints to protect us.
   sql_clauses_cols_all.inner.join += (
      """
      JOIN route AS rt
         ON (gia.item_id = rt.system_id)
      LEFT OUTER -- <--should be unnecessary
      JOIN route_parameters AS rt_ps
         ON ((gia.stack_id = rt_ps.route_stack_id)
         AND (gia.branch_id = rt_ps.branch_id))
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.details
      , group_item.beg_addr
      , group_item.fin_addr
      , group_item.rsn_len
      , group_item.travel_mode
      , group_item.p1_priority
      , group_item.p2_depart_at
      , group_item.p2_transit_pref
      , group_item.p3_weight_attr
      , group_item.p3_weight_type
      , group_item.p3_rating_pump
      , group_item.p3_burden_pump
      , group_item.p3_spalgorithm
      , group_item.tags_use_defaults
      """)

   g.assurt(not sql_clauses_cols_all.outer.order_by)

   # For route list pagination, order by last edited date.
   sql_clauses_cols_all.outer.order_by = (
      """
      edited_date DESC
      """)

   # **** SQL: Item version history query

   # FIXME/BUG nnnn: Copy this to track.py when we make it revisionless.
   #                 Also work_item, etc.
   sql_clauses_cols_versions = (
      item_revisionless.Many.sql_clauses_cols_versions_revisionless)
   #sql_clauses_cols_versions = (
   #   item_revisionless.Many.sql_clauses_cols_versions_revisionless.clone())

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   # *** Route-finding routines

   #
   def search_graph(self, req, routed, handler):
      '''Finds a route from a beginning point (beg_xy) to a finishing point
         (fin_xy). On success, stores the route in self.rsteps and
         self.rstops; on error, including no route found, raises
         GWIS_Error.'''

      beg_xy = (handler.beg_ptx, handler.beg_pty,)
      fin_xy = (handler.fin_ptx, handler.fin_pty,)

      qb = None
      rt = One(
         qb,
         row={
            # Use a generic name for now. After computing the route, we'll fix
            # the name so that it's more friendly.
            'name': 'Untitled',
            'geofeature_layer_id': Geofeature_Layer.Default,
            'branch_id': req.branch.branch_id,
            'z': 160, # MAGIC_NUMBER: 160 is route z-level.
            #
            # NOTE: The beg/fin addr friendly names are officially stored
            #       in route_stop rows (the first and last route stop for this
            #       route) but they're also cached in the route table (so we
            #       can get lists of routes quickly/easily).
            'beg_addr': handler.beg_addr,
            'fin_addr': handler.fin_addr,
            # Set below: beg_nid, fin_nid
            # Calculated later: rsn_len, rsn_min, rsn_max, n_steps, avg_cost
            'travel_mode': handler.travel_mode,
            # p1 planner:
            'p1_priority': handler.p1_priority,
            # p2 planner:
            'p2_depart_at': handler.p2_depart_at,
            'p2_transit_pref': handler.p2_transit_pref,
            # p3 planner:
            # Skipping: p3_weight_attr
            'p3_weight_type': handler.p3_weight_type,
            'p3_rating_pump': handler.p3_rating_pump,
            'p3_burden_pump': handler.p3_burden_pump,
            'p3_spalgorithm': handler.p3_spalgorithm,
            # Personalized routing Tag preferences:
            # Set next: tagprefs
            'tags_use_defaults': handler.tags_use_defaults,
            #
            # Skipping: details (EXPLAIN: This is only used by mobile??
            #                             Or it's only editable after a route
            #                             is saved?)
            # Skipping: stealth_secret (See item_stack table.)
            # Skipping: created (set by setup_item_revisionless_defaults)
         })

      log.debug(
         'search_graph: travel_mode: %s / route: %s'
         % (Travel_Mode.lookup_by_id[handler.travel_mode], rt,))

      rt.tagprefs = handler.tagprefs

      try:
         rating_func = routed.graph.ratings.rating_func(
            req.client.username, rt.tagprefs, routed.graph)
      except AttributeError:
         # Graph class doesn't define ratings (i.e., p3 planner).
         rating_func = None

      qb = req.as_iqb()
      # Debugging: just checking that the request didn't specify any viewport
      # or other filters.
      g.assurt(qb.viewport.include is None)
      g.assurt(qb.viewport.exclude is None)
      g.assurt(qb.filters == Query_Filters(None))
      is_latlon = False

      time_0 = time.time()

      if handler.beg_nid is None:
         # 2014.04.03: [lb] cannot find evidence that rating_min is
         # set by the user. In route_get.py, it's set to 0.5.
         src_by = One.byway_closest_xy(qb, rt.beg_addr, beg_xy,
                                           rating_func, handler.rating_min,
                                           is_latlon)
         src_id = src_by.nearest_node_id()
      else:
         src_id = handler.beg_nid
      rt.beg_nid = src_id

      if handler.fin_nid is None:
         dst_by = One.byway_closest_xy(qb, rt.fin_addr, fin_xy,
                                           rating_func, handler.rating_min,
                                           is_latlon)
         dst_id = dst_by.nearest_node_id()
      else:
         dst_id = handler.fin_nid
      rt.fin_nid = dst_id

      log.info('search_graph: found node IDs in %s'
         % (misc.time_format_elapsed(time_0),))

      if src_id == dst_id:
         # BUG nnnn: Honor m-values. If same m-value ret. x,y and draw a point.
         raise GWIS_Warning('Locations given are too close to each other.')

      if rt.travel_mode in Travel_Mode.p3_modes:
         rt_finder = planner.routed_p3.route_finder.Problem(
                                       req, routed.graph, rt)
      elif rt.travel_mode in Travel_Mode.p2_modes:
         # Calculate path using graphserver, which uses the simpler Dijkstra's.
         is_reverse = False
         rt_finder = planner.routed_p2.route_finder.Problem(
                                       req, routed.graph, rt,
            src_id, dst_id, rating_func, handler.rating_min,
            beg_xy, fin_xy, is_reverse)
      elif rt.travel_mode in Travel_Mode.p1_modes:
         # Deprecated. Replaced by: Travel_Mode.personalized.
         #             But you can get here via Ccp.py still,
         #             and also route analysis. And via flashclient
         #             if you choose Classic Routes.
         rt_finder = planner.routed_p1.route_finder.Problem(
                                       req, routed.graph, rt,
            src_id, dst_id, rating_func, handler.rating_min)
      else:
         g.assurt(False)

      time_0 = time.time()

      (rsteps, rstops, path_cost, path_len,) = rt_finder.solve(qb)

      log.info(
         'search_graph: found %d steps (%d stops) at %s cost (%s len) in %s'
         % (len(rsteps), len(rstops), path_cost, path_len,
            misc.time_format_elapsed(time_0),))

      # The route finder raises GWIS_Warning if no route is found.
      g.assurt(rsteps and rstops)

      time_0 = time.time()

      rt.rsteps = rsteps
      rt.rstops = rstops

      # Make a default friendly name according to the route steps (we figure
      # out which byway is most used and use that in the name of the route).
      rt.set_friendly_name()

      if ((rt.avg_cost is None)
          and ((handler.travel_mode != Travel_Mode.bicycle)
               or (qb.username != conf.anonymous_username))):
         if path_len:
            rt.avg_cost = ((path_cost / route_step.One.weight_multiplier)
                           / path_len)
            log.debug('search_graph: 1 / rt.avg_cost: %s' % (rt.avg_cost,))
         # else, we'll set avg_cost in either compute_stats_raw or
         #       savex_fetch_calculated_node_stats.

      bonus_t = [t for t in rt.tagprefs if rt.tagprefs[t] == ratings.t_bonus]
      penal_t = [t for t in rt.tagprefs if rt.tagprefs[t] == ratings.t_penalty]

      cumulative_cost = None
      if (((rt.avg_cost is None)
           and (rating_func is not None)
           and (rt.travel_mode == Travel_Mode.bicycle)
           and (qb.username != conf.anonymous_username))
          or (bonus_t)
          or (penal_t)):

         steps_total_len = 0.0
         cumulative_cost = 0.0

         for step in rt.rsteps:

            if step.byway_stack_id:
               # Lookup tags using the step cache.
               step.bonus_tagged = routed.graph.byway_has_tags(
                                    step.byway_stack_id, bonus_t)
               step.penalty_tagged = routed.graph.byway_has_tags(
                                    step.byway_stack_id, penal_t)
               # SYNC_ME: Search edges...
               if ((step.rating is None)
                   or (qb.username != conf.anonymous_username)):
                  try:
                     step.rating = rating_func(step.byway_stack_id)
                  except TypeError:
                     # rating_func is None.
                     # The route_step.One.init_from_shpfeat fcn. gets the
                     # average/generic rating for the byway, so that should
                     # be sufficient to return.
                     pass
               # else, rating already set and user anonymous, so rating_func
               #       would just return the same value.
# FIXME/APRIL2014: Delete this else block or comment out after
# verifying (logcheck will complain if it hits, so, no logcheck
# complaints means it's okay to delete).
               else:
                  anon_rating = rating_func(step.byway_stack_id)
                  if anon_rating != step.rating:
                     log.warning(
                        'rating dispute: step.rating: %s / anon_rating: %s'
                        % (step.rating, anon_rating,))
            else:
               log.warning('route step has no byway id?: %s' % (step,))

            if rt.avg_cost is None:
               step.calc_length_and_cost()
               steps_total_len += step.edge_length
               cumulative_cost += step.edge_weight

         # end: for step in rt.rsteps

         if rt.avg_cost is None:
            if steps_total_len:
               rt.avg_cost = (
                  (cumulative_cost / route_step.One.weight_multiplier)
                  / steps_total_len)
               log.debug('search_graph: 2 / rt.avg_cost: %s' % (rt.avg_cost,))
            # else, we'll set avg_cost in either compute_stats_raw or
            #       savex_fetch_calculated_node_stats.

      # An all_bike_path is from p1 or p3, i.e., not the p2 multimodal planner.
      all_bike_path = True
      for step in rt.rsteps:
         if step.travel_mode != Travel_Mode.bicycle:
            all_bike_path = False
            break
      if all_bike_path and (rt.travel_mode == Travel_Mode.transit):
         # If the route came from routed_p2 but is all bike paths, adjust
         # its travel mode so that it will function like an editable route.
         # BUG nnnn: When the user chooses to edit this route, the fact that it
         #           was a transit route will be lost. When user's choose
         #           to edit a route, can they use the Metro Transit
         #           checkbox? Would this imply creating/cloning the route?
         #           For now, we could just tell the user with a popup or
         #           alert.
         rt.travel_mode = Travel_Mode.bicycle
         #rt.travel_mode = Travel_Mode.wayward

      log.info('search_graph: iterated over step ratings in %s'
         % (misc.time_format_elapsed(time_0),))

      log.debug(
         'search_graph: found rte: %d steps / %d stops / %s'
         % (len(rsteps),
         len(rstops),
         'path_cost: %s / path_len: %s / cuml_cost: %s / avg_cost: %s'
         % ('None' if path_cost is None
             else '%.2f' % (path_cost,),
            'None' if path_len is None
             else '%.2f' % (path_len,),
            'None' if cumulative_cost is None
             else '%.2f' % (cumulative_cost,),
            'None' if rt.avg_cost is None
             else '%.2f' % (rt.avg_cost,),),))

      # Return the fresh, invalid route (invalid because it's up to the caller
      # to prepare the item for saving and then save it, if they so desire).

      return rt

   # *** Query Builder routines

   # MAYBE: In CcpV1, there's a search_by_rquery you can use to find routes by
   #        geometry. [lb] isn't quite remembering how exactly it worked... but
   #        is it something maybe we want to implement again?
   # E.g.,
   # def search_by_rquery(self, req, username, rquery, vquery):
   #    ...
   #   # HACK: route's historic query does not work like most map features
   #   # so Historic has a special flag that can be turned on to change
   #   # it's behavior
   #   if isinstance(vquery, revision_query.Historic):
   #      vquery.is_route = True
   #
   #   where_user = '''(visibility = 1 OR (visibility = 2
   #                    AND owner_name IS NOT NULL
   #                    AND owner_name = %s))''' % (req.db.quoted(username))
   #
   #   rows = req.db.sql(
   #      """
   #      SELECT id, version
   #      FROM route_geo rg
   #      WHERE %s
   #         AND %s
   #         AND %s
   #      """ % (where_user,
   #             rquery.as_sql_where(vquery, 'route_geo', 'rg'),
   #             vquery.as_sql_where(),))
   #
   #   for row in rows:
   #      self.add(self.search_by_id(req, row['id'], row['version']))

   #
   def search_by_stack_id(self, stack_id, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      geofeature.Many.search_by_stack_id(self, stack_id, qb)

   # ***

   #
   def search_get_sql(self, qb):
      # Forever, and always. We always sort routes by edited_date,
      # so we always need to set include_item_stack.
      qb.filters.include_item_stack = True
      sql = geofeature.Many.search_get_sql(self, qb)
      return sql

   #
   def search_get_items(self, qb):
      geofeature.Many.search_get_items(self, qb)
      # Skipping: qb.filters.dont_load_route_details
      if (not qb.db.dont_fetchall) and (qb.filters.include_item_aux):
         self.routes_load_aux(qb)
      # else, see search_for_items_clever and search_get_items_add_item_cb.

   #
   def search_for_items_clever(self, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      g.assurt(not qb.db.dont_fetchall)
      geofeature.Many.search_for_items_clever(self, qb)
      if qb.filters.include_item_aux:
         self.routes_load_aux(qb)

   #
   def search_for_items_diff(self, qb):
      raise GWIS_Error('Diff checkout not supported for routes.')

   #
   def search_for_items_load(self, qb, diff_group):
      # To get an historic version of restricted-access items, use
      # revision.Comprehensive.
      g.assurt(isinstance(qb.revision, revision.Current))
      geofeature.Many.search_for_items_load(self, qb, diff_group)

   #
   def sql_apply_query_filters_item_stack_revisiony(self, qb, use_inner_join):
      # Routes, tracks, posts, threads, oh my, are revisionless.
      self.sql_apply_query_filters_item_stack_revisionless(qb, use_inner_join)

   #
   def sql_apply_query_filters_last_editor(self, qb, where_clause,
                                                     conjunction):
      # NOTE: Not calling geofeature.Many.sql_apply_query_filters_last_editor.
      #       We got this.
      # FIXME: Copy this fcn. to track, when we make tracks revisionless.
      #        Or derive route and track from common ancestor.
      return self.sql_apply_query_filters_last_editor_revisionless(qb,
                                             where_clause, conjunction)

   #
   def sql_enabled_squelch_circuitry(self):
      # Refer to the item_findability table when searching for non-specific
      # items.
      return True

   # ***

   #
   def routes_load_aux(self, qb):

      # Routes are special objects that require a lot more manual loading.

      # SYNC_ME: route.routes_load_aux and track.tracks_load_aux.

      # NOTE/FIXME: routes are branch-specific, so
      #                WHERE stack_id= AND branch_id=
      #             is not really needed (and maybe misleading?).

      # NOTE: Starting with rtsharing, routes are versioned, but that
      # doesn't matter for route_parameters and route_tag_preference, since
      # those values are set just once.

      routes_aux_limit = 1
      if len(self) > routes_aux_limit:
         log.warning("More than %d routes found: ignoring %d routes' aux data"
                     % (routes_aux_limit, (len(self) - routes_aux_limit),))
      elif len(self) == 0:
         log.debug('routes_load_aux: no routes: %s' % (str(self),))

      routes = self[0:routes_aux_limit]

      for rt in routes:

         # Route stops.
         rows = qb.db.sql(
            """
            SELECT
               stop_number,
               name,
               x,
               y,
               node_id,
               is_pass_through,
               is_transit_stop,
               internal_system_id,
               external_result
            FROM
               route_stop
            WHERE
               route_id = %d
            ORDER BY
               stop_number ASC
            """ % (rt.system_id,))

         for row in rows:
            rt.rstops.append(route_stop.One(qb, row=row))

         # Tag preferences (tag_preference table)
         rt.fill_tagprefs(qb)

         # Route steps (route_step table)
         rt.fill_path(qb)

         # Fix route stops with empty node IDs.
         # BUG nnnn: Routed p2: Editable routes.
         route_step.Many.repair_node_ids(qb, rt.rsteps)

         # The route is now completed, and it's already been appended to
         # self (Many) so we can continue looping over the routes (though
         # it's unlikely to be more than one).

   # *** Table management

   indexed_cols = (
      #'rsn_min', # The first step_number; BUGBUG: not always 0.
      #'rsn_max', # The last step_number, since a few gaps have
      #           #   gaps in their route_step sequence.
      #'n_steps', # Number of route_step rows for this route.
      #'rsn_len', #
      'beg_nid', # The beginning node endpoint.
      'fin_nid', # The finishing node endpoint.
      )

   #
   @staticmethod
   def drop_indices(db):
      # FIXME: This loop shared by the node_ classes. Put in some base class.
      for col_name in Many.indexed_cols:
         db.sql("DROP INDEX IF EXISTS route_%s" % (col_name,))

   #
   @staticmethod
   def make_indices(db):
      # Drop the indices first.
      Many.drop_indices(db)
      # Re(make) the indices.
      for col_name in Many.indexed_cols:
         db.sql("CREATE INDEX route_%s ON route(%s)"
                % (col_name, col_name,))

   # ***

   #
   # MAYBE: This gets called whenever the route is saved, even if it's just
   # that the user made a stealth secret and we just had to make a GIA record.
   @staticmethod
   def update_node_stats(qb, system_id=None,
                             stack_id=None,
                             all_routes=False,
                             prog_log=None):

      if system_id:
         g.assurt(not (stack_id or all_routes))
         where_clause = "WHERE rt.system_id = %d" % (system_id,)
      elif stack_id:
         g.assurt(not (system_id or all_routes))
         where_clause = "WHERE rt.stack_id = %d" % (stack_id,)
      else:
         g.assurt(not (stack_id or system_id))
         where_clause = ""

      # We don't have to worry about the revision because we group things by
      # route system ID, and its route_steps have the system IDs of byways --
      # and system IDs are inherently revisiony.

      # MAYBE: NOTE: Some routes in the database are inconsistent. Some have
      # missing route_step rows (i.e., there are missing route_numbers) and
      # some don't start on 0, which is supposed to be the first index.
      #first_index = 0

      # NOTE: To calculate beg_addr and fin_addr, we could make an inner select
      # that calculates the min() and max() stop_numbers for the route and use
      # that to join against route_stop (like we do for beg_nid and
      # fin_nid), or we could do a select in the select list and use order-by
      # to get the rows we want (a trick first writ by [ml]).


# FIXME: wrong: you need to iterate one route at a time, dummy.
#        or else the new outer join totally slowed this down...
#        or maybe i'm not patient

# this is taking almost a halh hour now -- you should do route IDs, then at
# least you can test what's taking so long (prob. scratch space! maybe this
# runs fast if you have the mem)

      # FIXME: transit_geometry and geometry. Maybe rename geometry to
      # byway_geometry? Or move both to a single geometry column and use
      # a boolean to indicate that its transit (or rely on NULL byway_id?)?
      routes_sql = (
         """

         SELECT
            --
            foo_rte_1.system_id
            --
            , (SELECT name FROM route_stop AS rw
               WHERE rw.route_id = foo_rte_1.system_id
               ORDER BY rw.stop_number ASC LIMIT 1) AS beg_addr
            , (SELECT name FROM route_stop AS rw
               WHERE rw.route_id = foo_rte_1.system_id
               ORDER BY rw.stop_number DESC LIMIT 1) AS fin_addr
            --
            , rs_beg.forward     AS lhs_forward
            , gf_beg.beg_node_id AS lhs_beg_node_id
            , gf_beg.fin_node_id AS lhs_fin_node_id
            --
            , rs_fin.forward     AS rhs_forward
            , gf_fin.beg_node_id AS rhs_beg_node_id
            , gf_fin.fin_node_id AS rhs_fin_node_id
            --
            , foo_rte_1.step_count_min
            , foo_rte_1.step_count_max
            , foo_rte_1.step_count_count
            --
            --, foo_rte_1.steps_total_len
            /* FIXME: I don't know that we need to correct reversed line
            segments...
            , (SELECT ST_Length(
                  SELECT ST_Collect(
                     SELECT
                        CASE
                           WHEN rs.transit_geometry IS NOT NULL
                              THEN rs.transit_geometry
                           ELSE (
                              SELECT
                                 CASE
                                    WHEN rs.forward THEN gf.geometry
                                    ELSE ST_Reverse(gf.geometry)
                                    END AS geometry
                              FROM geofeature AS gf
                              WHERE gf.system_id = rs.byway_id)
                           END AS geometry
                     FROM route_step AS rs
                     WHERE (rs.route_id = foo_rte_1.system_id)))
               ) AS steps_total_len
            */
            --, ST_Length(ST_Collect(collected_geo_geo, collected_geo_tx))
            --   AS steps_total_len
            , CASE
               WHEN collected_geo_geo is NOT NULL THEN
                  ST_Length(ST_Collect(collected_geo_geo, collected_geo_tx))
               ELSE
                  -- FIXME: Is this right? 0?
                  0
               END AS steps_total_len
         /* Get the system ID and step count using an inner query. */
         FROM (
            SELECT
               rt.system_id
               , MIN(rs.step_number) AS step_count_min
               , MAX(rs.step_number) AS step_count_max
               , COUNT(rs.step_number) AS step_count_count
--, ST_Collect(rs.geometry) AS collected_geo_geo
               , ST_Collect(gf_inner.geometry) AS collected_geo_geo
               , ST_Collect(rs.transit_geometry) AS collected_geo_tx
            FROM
               route AS rt
            JOIN
               route_step AS rs
               ON (rt.system_id = rs.route_id)
            LEFT OUTER JOIN
               geofeature AS gf_inner
               ON (rs.byway_id = gf_inner.system_id)
            %s -- WHERE
            GROUP BY
               rt.system_id
            ) AS foo_rte_1

         /* First route_step and its byway. */
         JOIN
            route_step AS rs_beg
            ON ((foo_rte_1.system_id = rs_beg.route_id)
                AND (rs_beg.step_number = foo_rte_1.step_count_min))
         JOIN
            geofeature AS gf_beg
            ON (rs_beg.byway_id = gf_beg.system_id)

         /* Last route_step and its byway. */
         JOIN
            route_step AS rs_fin
            ON ((foo_rte_1.system_id = rs_fin.route_id)
                AND (rs_fin.step_number = foo_rte_1.step_count_max))
         JOIN
            geofeature AS gf_fin
            ON (rs_fin.byway_id = gf_fin.system_id)

         """ % (where_clause,))

      if not where_clause:
         logl = log.info
      else:
         # MAYBE: log.verbose
         logl = log.debug

      # This takes a while when searching all routes!
      # 2012.07.11: Raw SQL: 102474 rows in 4-1/3 mins.
      # 2012.07.11: LIMIT 1:      1 row in 5360.518 ms.
      # 2012.07.13: From node_cache_maker: 102587 in 0.9.

      logl('update_node_stats: searching for routes...')

      sole_row = None

      time_0 = time.time()

      try:

         db = qb.db.clone()

         db.dont_fetchall = True

         db.sql(routes_sql)

         if db.curs.rowcount <= 0:
            log.warning('update_node_stats: no routes found: %d'
                        % (db.curs.rowcount,))
         else:
            log.info('Found %d routes in %s'
               % (db.curs.rowcount,
                  misc.time_format_elapsed(time_0),))
            time_0 = time.time()
            try:
               another_db = db.clone()
               #another_db.transaction_begin_rw()
               sole_row = Many.update_node_stats_process(
                                 db, another_db, prog_log)
            finally:
               another_db.close()
            log.info('update_node_stats_process: in %s'
               % (misc.time_format_elapsed(time_0),))

      finally:

         log.verbose('update_node_stats: disabling dont_fetchall')
         db.dont_fetchall = False
         #db.curs_recycle()
         db.close()

      return sole_row

   #
   @staticmethod
   def update_node_stats_process(db, another_db, prog_log=None):

      log.info('Processing routes and updating table...')

      sole_row = None

      step_count_exact = 0
      step_count_holey = 0
      step_count_later = 0
      step_count_buckets = {}

      if prog_log is None:
         prog_log = Debug_Progress_Logger()
         prog_log.log_listen = None
         prog_log.log_silently = True
      prog_log.loop_max = db.curs.rowcount
      if prog_log.log_freq == 1:
         prog_log.log_freq = 1000

      # MAGIC NUMBER: I'm just guessing here. Testing new idea: bulk UPDATEs.
      update_freq = 1000
      g.assurt(update_freq > 0)
      # Reset the bulk collection.
      updates = []

      generator = db.get_row_iter()
      for row in generator:

         # Get the columns.
         #
         system_id = row['system_id']
         #
         beg_addr = row['beg_addr']
         fin_addr = row['fin_addr']
         #
         lhs_forward = row['lhs_forward']
         lhs_beg_node_id = row['lhs_beg_node_id']
         lhs_fin_node_id = row['lhs_fin_node_id']
         #
         rhs_forward = row['rhs_forward']
         rhs_beg_node_id = row['rhs_beg_node_id']
         rhs_fin_node_id = row['rhs_fin_node_id']
         #
         step_count_min = row['step_count_min']
         step_count_max = row['step_count_max']
         step_count_count = row['step_count_count']
         #
         steps_total_len = row['steps_total_len']

         # The step_column value is 0-based, non-negative, and incremental.
         # 2012.07.13: EXPLAIN: Why are there missing step_numbers in the
         # table? I.e.,
         #  select * from route where system_id = 234872;
         #  select * from route_step where route_id = 234872;
         # NOT ALWAYS TRUE: g.assurt(step_count_max == (step_count_count - 1))
         if step_count_max == (step_count_count - 1):
            step_count_exact += 1
         else:
            g.assurt(step_count_max >= (step_count_count - 1))
            step_count_holey += 1
         #
         if step_count_min > 0:
            step_count_later += 1
         #
         misc.dict_count_inc(step_count_buckets, step_count_count)

         if lhs_forward:
            rte_beg_node_id = lhs_beg_node_id
         else:
            rte_beg_node_id = lhs_fin_node_id
         #
         # 2014.09.11: Should'nt the order be reversed here?
         #             Or don't we have enough information to
         #             know which node is closer to the user's
         #             true destination?
         #   if rhs_forward:
         #      rte_fin_node_id = rhs_beg_node_id
         #   else:
         #      rte_fin_node_id = rhs_fin_node_id
         if rhs_forward:
            rte_fin_node_id = rhs_fin_node_id
         else:
            rte_fin_node_id = rhs_beg_node_id

         # Save a tuple to the update list.
         updates.append("(%d, %s, %s, %d, %d, %d, %.1f, %d, %d)"
            % (system_id,
               db.quoted(beg_addr),
               db.quoted(fin_addr),
               step_count_min,   # rsn_min
               step_count_max,   # rsn_max
               step_count_count, # n_steps
               steps_total_len,  # rsn_len
               rte_beg_node_id,  # beg_node_id
               rte_fin_node_id,  # fin_node_id
               ))

         # We only update every so often.
         if prog_log.progress % update_freq == 0:
            # Time to bulk-update.
            # NOTE: Using qb's db, not the cloned one we're using to fetchone.
            Many.node_bulk_update(another_db, updates)
            # Reset the update list.
            updates = []

         if db.curs.rowcount == 1:
            sole_row = row

         # If debugging, break early maybe.
         if prog_log.loops_inc():
            break

      # end: for row in generator

      if generator is not None:
         generator.close()
         generator = None

      # One last time.
      if updates:
         # NOTE: Again using qb's db and not our local clone.
         Many.node_bulk_update(another_db, updates)
         updates = []

      log.info('update_node_stats: good step_count seqs.: %d'
               % (step_count_exact,))
      log.info('                 w/ gaps in the sequence: %d'
               % (step_count_holey,))
      log.info('                w/ first step_number > 0: %d'
               % (step_count_later,))

      keys = step_count_buckets.keys()
      #keys.sort()
      #for step_count in keys:
      for key_i in xrange(len(keys)):
         try:
            step_count = keys[key_i]
            # Only output the last few route stats or any short routes.
            if (step_count < 3) or (key_i >= (len(keys) - 2)):
               route_ct = step_count_buckets[step_count]
               log.info('   No. of Routes with %03d route_steps: %d'
                        % (step_count, route_ct,))
         except KeyError:
            pass

      prog_log.loops_fin(callee='update_node_stats')

      return sole_row

   #
   @staticmethod
   def node_bulk_update(another_db, updates):
      g.assurt(updates)
      # Format is, e.g.,
      #    UPDATE
      #       tbl_1
      #    SET
      #       col1 = t.col1
      #    FROM (
      #       VALUES
      # 	        (25, 3)
      # 	        (26, 5)
      #       ) AS t(id, col1)
      #    WHERE tbl_1.id = t.id;
      update_sql = (
         """
         UPDATE
            route
         SET
              beg_addr = foo_rte_2.beg_addr
            , fin_addr = foo_rte_2.fin_addr
            , rsn_min = foo_rte_2.rsn_min
            , rsn_max = foo_rte_2.rsn_max
            , n_steps = foo_rte_2.n_steps
            , rsn_len = foo_rte_2.rsn_len
            , beg_nid = foo_rte_2.beg_node_id
            , fin_nid = foo_rte_2.fin_node_id
         FROM
            (VALUES %s) AS foo_rte_2(system_id,
                                     beg_addr,
                                     fin_addr,
                                     rsn_min,
                                     rsn_max,
                                     n_steps,
                                     rsn_len,
                                     beg_node_id,
                                     fin_node_id)
         WHERE
            route.system_id = foo_rte_2.system_id
         """ % (','.join(updates),))
      another_db.sql(update_sql)

   # ***

# ***

