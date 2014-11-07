# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This file contains utility methods for working with GML.

# NOTE: The functions for building WKT from GML elements do not check the
# input for validity. Therefore, to protect against SQL injection attacks, you
# _must_ quote these strings properly when inserting them into the database.

# FIXME: Polygon rings sent from server to client are NOT closed, while those
# sent from client to server ARE closed.
# BUG nnnn: How come the server has unclosed polygons? Seems strange. Also,
# OpenJUMP won't even load them...

from lxml import etree
import os
import re
import sys

import conf
import g

from util_ import geometry

log = g.log.getLogger('util_.gml')

#
def append_LineString(elem, geometry):
   '''Append a GML LineString representation of Geometry to elem. geometry
      must be an SVG path string.'''

   # The geometry is empty (None) if the item is deleted.
   # The geometry is empty ('') if the item is a route.
   if geometry:

      # Postgis has always started svg linestrings with 'M '.
      g.assurt(geometry[:2] == 'M ')
      g.assurt(elem.text is None)
      # In PostGIS >= 1.4, Postgis added the 'L' to conform to svg standards.
      elem.text = geometry[2:].replace('L ', '')

#
def append_MultiPolygon(elem, geometry):
   '''Append a GML representation of the multipolygon geometry to elem.
      geometry is an SVG path string, with the different polygons separated by
      " Z M ". NOTE: All member polygons are assumed to have a single external
      ring.'''

   # The geometry is empty if the item is deleted.
   if geometry:

      # Trim leading 'M ' and trailing ' Z', then split polygons.
      g.assurt((geometry[:2] == 'M ') and (geometry[-2:] == ' Z'))
      polys = geometry[2:-2].split(' Z M ')

      for poly in polys:
         subel = etree.Element('polygon')
         # In PostGIS >= 1.4, Postgis added the 'L' to conform to svg stds.
         subel.text = poly.replace('L ', '')
         elem.append(subel)

#
def append_Point(elem, geometry):
   '''Append a GML Point representation of geometry to elem. geometry must be
      a WKT (not EWKT) point string.'''

   # The geometry is empty if the item is deleted.
   if geometry:

      g.assurt(elem.text is None)
      if geometry.startswith('POINT('):
         elem.text = geometry[6:-1]
      else:
         srid_prefix = 'SRID=%s;POINT(' % (conf.default_srid,)
         if geometry.startswith(srid_prefix):
            elem.text = geometry[len(srid_prefix):-1]
         else:
            g.assurt(False)
      # FIXME group_item_access uses GEOMETRY ??
      #log.debug('geometry: %s' % (geometry),)
      #g.assurt(geometry[:4] == 'cx="')
      #elem.text = geometry

#
def append_Polygon(elem, geometry):
   '''Append a GML representation of the polygon geometry to elem. geometry is
      an SVG path string, with the different rings separated by "M". The first
      ring is the external ring and the rest are internal.

      NOTE: see fixme about polygon rings above.'''

   # The geometry may be empty if the item is deleted.
   # Or if the branch's coverage_area isn't set.
   if geometry:

      g.assurt(geometry[:2] == 'M ' and geometry[-2:] == ' Z')
      
      # In Postgis >= 1.4, there's an 'L' to conform to the SVG standard, e.g.,
      #    M 479284.67 4974056.7 L 479487.08 4974055.45 479489.83 ... Z
      #    (in older Postgis there was just the leading M and trailing Z).

      # Note that polygons are defined by an outer ring and zero of more
      # inner rings. The polygon is considered simple if the inner rings
      # do not intersect or cross the outer ring, or if they intersect, it's
      # only at a point and not along an edge.
      #
      #  E.g., M 0 0 L 0 4 4 4 4 0 Z M 1 1 L 1 2 2 2 2 1 Z
      #
      #  select gf.stack_id,
      #         iv.name,
      #         geofeature_layer_id as gfld_id,
      #         st_issimple(geometry)
      #  from geofeature as gf join item_versioned as iv using (system_id)
      #  where st_geometrytype(geometry) = 'ST_Polygon'
      #        and st_nrings(geometry) > 2;
      #
      # 2013.09.24: All ST_Polygon geometries in Cyclopath with one or more
      # inner rings are simple. Most are Terrain Open Space or Terrain Water,
      # but an alien handful are Regions.
      #
      # TEST: Make sure these regions display correctly. And can you edit?
      # BUG nnnn: Polygon editing: Does flashclient handle editing rings?
      #
      #   stk_id  | iv.name
      #   ------- + -----------------
      #   1446112 | Farmington
      #   1446259 | Benton Twp.
      #   1446115 | Hampton Twp.
      #   1446249 | Stillwater
      #   1446265 | Waconia
      #   1446270 | Watertown
      #   1446239 | Mahtomedi
      #   1446182 | Rogers
      #   1446261 | Young America Twp.
      #   1446220 | New Market Twp.

      # Split the rings. The lead element in the list will be empty because the
      # string's first characters are the split characters, so ignore the first
      # element of the split.
      rings = geometry.split('M ')[1:]

      # NOTE: [lb] wrote sometime in 2010 or 2011 or 2012 that OpenJump won't
      #       load Polygons with inner rights. I'm not sure if that's right,
      #       or if I was having another issue, but it led me to write all
      #       the comments above about exterior and interior rings in 2013.

      # And the outer, exterior, or external ring, however you want to call it.
      external = etree.Element('external')
      # Remove the 'L ' with replace and chop of the trailing ' Z' with slice.
      external.text = rings.pop(0)[:-2].replace('L ', '')
      # Add the exterior ring.
      elem.append(external)

      # Add the interior rings, if any.
      for ring in rings:
         internal = etree.Element('internal')
         # Slice the string to exclude trailing ' Z', then replace any 'L 's.
         internal.text = ring[:-2].replace('L ', '')
         elem.append(internal)

#
def flat_to_xys(geom_str):
   '''
   Convert flat coordinate text to a sequence of (x,y) tuples.
   
   Input Examples:

      Not SVG: "1 2 3 4 5 6"
          SVG: "M 1 2 L 3 4 5 6 Z"
          WKT: "LINESTRING (1 2,3 4,5 6) "

   Output Example:

               [(1,2), (3,4), (5,6)]

   Re: SVG, see, e.g., http://www.w3schools.com/svg/svg_path.asp
   M = moveto, L = lineto, Z = closepath

   '''

   # See if geom_str is really a WKT, i.e., LINESTRING(%s).
   wkt_prefix = 'LINESTRING'
   g.assurt(isinstance(geom_str, basestring))
   if geom_str.startswith('SRID='):
      geom_str = geom_str[geom_str.index(';')+1:]
   if geom_str.startswith(wkt_prefix):
      # MAGIC_NUMBER: Remove from paren to paren; +1 to skip first paren.
      beginning_at = geom_str.index('(') + 1
      finishing_at = geom_str.index(')')
      g.assurt(finishing_at > beginning_at)
      text = geom_str[beginning_at:finishing_at]
   else:
      text = geom_str

   # In PostGIS >= 1.4, Postgis added the 'L' to conform to svg stds.
   text = re.sub(r'[MLZ] ?', '', text)
   text = text.replace(',', ' ')
   text = re.sub(r' +', ' ', text)
   # Strip the space left over from ' Z' and split on whitespace.
   coords = text.strip().split(' ')

   try:
      # NOTE: zip is a Python built-in. Returns a list of tuples.
      #       Matches the two lists element-to-element, index-by-index.
      xys = zip([float(x) for x in coords[0::2]],
                [float(y) for y in coords[1::2]])
   except Exception, e:
      # Programmer error.
      g.assurt(False)

   return xys

#
def geomstr_length(geom_str):
   'Return the length of the geometry contained in geom_str.'
   xys = flat_to_xys(geom_str)
   g.assurt(len(xys) >= 2)
   d = 0
   last = xys[0]
   for xy in xys[1:]:
      d += geometry.distance(last, xy)
      last = xy
   return d

# ***

# E.g., '%.6f %.6f'
float_format = '%%.%df %%.%df' % (conf.geom_precision, conf.geom_precision,)

#
def wkt_coords_format(xys):
   'Return the coordinate sequence xys as a WKT text coordinate sequence.'
   # MAYBE: How was .6 decided? This is the precision we store in the database
   #        and send to clients when they want geometry. This probably affects
   #        geometry size in the database? It definitely affects geometry
   #        calculations. I [lb] think conf.node_tolerance is too strict, so
   #        I'm happy to leave this, but I'm curious what the 'proper' value
   #        is... maybe it is .1? I wonder what map editing would look like
   #        with snapping to every decimeter (could probably test in ArcGIS).
   # I.e., ','.join(['%.6f %.6f'...
   return ','.join([float_format % (x, y,) for (x, y) in xys])

#
def wkt_point_get(geom_str):
   'Return the WKT point geometry contained in geom_str.'
   return 'POINT(%s)' % (geom_str)

#
def wkt_linestring_get(geom_str):
   '''Return the WKT linestring geometry contained in geom_str. If the 
      linestring degenerates to a point, return None.'''

   xys = flat_to_xys(geom_str)
   g.assurt(len(xys) >= 2)

   # Check for degeneracy. Since we're checking for sameness, make sure we 
   # fuzz-out the comparison to conf.node_tolerance (usually 1 decimeter).
   pcoord = geometry.xy_to_wkt_point_restrict((xys[0][0], xys[0][1],))
   for i in xrange(1, len(xys)):
      # We're lazy and just compare the WKT (we use the _to_wkt_ fcn. just
      # because it uses conf.geom_precision).
      ncoord = geometry.xy_to_wkt_point_restrict((xys[i][0], xys[i][1],))
      if pcoord != ncoord:
         return 'LINESTRING(%s)' % (wkt_coords_format(xys),)

   # if we've gotten here, all coordinates in xys were equal
   # to within 6 decimal points so it degenerates to a point
   return None


#
# Given a multilinestring in WKT, return a list of linestrings in WKT

# 2013.01.03: CcpV1's tilecache_update used to use this, because it used
# ST_LineMerge(ST_Collect) to coalesce line segments. In CcpV2, we do the
# tedious business of comparing node endpoint IDs.

# Regex to strip MULTILINESTRING() container
MLS_STRIP_RE = re.compile(r'^MULTILINESTRING\(|\)$')

# Regex to split on '),(' pattern, but keep the parens.
MLS_SPLIT_RE = re.compile(r'(?<=\)),(?=\()')

#
def wkt_multilinestring_split(mls):
   splitted = [('LINESTRING' + x)
               for x in MLS_SPLIT_RE.split(MLS_STRIP_RE.sub('', mls))]
   return splitted

# Currently assumes that the text child of elem represents the external ring
# of the polygon.  Internal rings are not yet supported (ideally they will be
# stored as a separate attr, while external ring handling remains unchanged).
#
# NOTE: See fixme regarding polygon rings above.
def wkt_polygon_get(elem):
   'Return the WKT polygon geometry contained in elem.'
   xys = flat_to_xys(elem.text)
   return 'POLYGON((%s))' % (wkt_coords_format(xys))

# ***

