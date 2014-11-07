# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Provides utility functions for working with geometries. Right now the only
# functionality is conversion, but this may be expanded in the future to
# include other utilities.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

from decimal import Decimal
import math
import re

import conf
import g

log = g.log.getLogger('util_.geometry')

# *** Misc

#
def angle_normalize(a):
   '''Return an angle equivalent to a in the range (-pi, pi].'''
   if a > math.pi:
      a -= math.pi
   if a <= -math.pi:
      a += math.pi
   g.assurt(-math.pi < a <= math.pi)
   return a

#
def distance((x1, y1), (x2, y2)):
   return math.sqrt((x1-x2)**2 + (y1-y2)**2)

#
def rotation_ccw(a, b):
   '''Return the counterclockwise rotation angle from angle a to angle b,
      which must be in the range (-pi, pi].'''
   g.assurt(-math.pi < a <= math.pi)
   g.assurt(-math.pi < b <= math.pi)
   return angle_normalize(b - a)

#
def v_dir(a, b):
   '''Return the direction of the vector from point a to point b, from -pi to
      pi, where (1,0) is direction 0 and angles increase counterclockwise.'''
   c = (b[0] - a[0], b[1] - a[1])
   return math.atan2(c[1], c[0])

# *** Hausdorff Difference

# See: https://en.wikipedia.org/wiki/Hausdorff_distance

#
# See: http://mathworld.wolfram.com/Point-LineDistance2-Dimensional.html
def distance_pt_to_line_infinite((x0, y0), (x1, y1), (x2, y2)):
   # The distance from (x0, y0) to the line is given by
   # projecting r onto v, where v is the vector perpendicular
   # to the line specified by the points (x1, y1), (x2, y2),
   # and r is the vector from (x0, y0) to (x1, y1).
   numerator = abs((x2 - x1) * (y1 - y0) - (x1 - x0) * (y2 - y1))
   denominator = math.sqrt(math.pow((x2 - x1), 2) + math.pow((y2 - y1), 2))
   try:
      dist = numerator / denominator
   except ZeroDivisionError:
      dist = None
   return dist

#
def distance_pt_to_line_segment_phillip_nicoletti(
      (x0, y0), (x1, y1), (x2, y2)):
   '''
   # From: http://forums.codeguru.com/printthread.php?t=194400

    Subject 1.02: How do I find the distance from a point to a line?

    Let the point be C (Cx,Cy) and the line be AB (Ax,Ay) to (Bx,By).
    Let P be the point of perpendicular projection of C on AB.  The parameter
    r, which indicates P's position along AB, is computed by the dot product
    of AC and AB divided by the square of the length of AB:

    (1)    AC dot AB
        r = ---------
            ||AB||^2

    r has the following meaning:

        r=0      P = A
        r=1      P = B
        r<0      P is on the backward extension of AB
        r>1      P is on the forward extension of AB
        0<r<1    P is interior to AB

    The length of a line segment in d dimensions, AB is computed by:

        L = sqrt( (Bx-Ax)^2 + (By-Ay)^2 + ... + (Bd-Ad)^2)

    so in 2D:

        L = sqrt( (Bx-Ax)^2 + (By-Ay)^2 )

    and the dot product of two vectors in d dimensions, U dot V is computed:

        D = (Ux * Vx) + (Uy * Vy) + ... + (Ud * Vd)

    so in 2D:

        D = (Ux * Vx) + (Uy * Vy)

    So (1) expands to:

            (Cx-Ax)(Bx-Ax) + (Cy-Ay)(By-Ay)
        r = -------------------------------
                          L^2

    The point P can then be found:

        Px = Ax + r(Bx-Ax)
        Py = Ay + r(By-Ay)

    And the distance from A to P = r*L.

    Use another parameter s to indicate the location along PC, with the
    following meaning:
          s<0      C is left of AB
          s>0      C is right of AB
          s=0      C is on AB

    Compute s as follows:

            (Ay-Cy)(Bx-Ax)-(Ax-Cx)(By-Ay)
        s = -----------------------------
                        L^2

    Then the distance from C to P = |s|*L.
   '''

   # [lb] cleaned up this fcn. a bit (like handling 0 denom).
   #      This fcn. has a better runtime than some other algs
   #      I tried.

   # Weird: If we use r_numer = float(...) and r_denom = float(...),
   #        timeit goes from 2.3 to 2.8 to tit.timeit(number=1000000), e.g.,
   # tit = timeit.Timer(stmt="""
   #  from util_ import geometry
   #  geometry.distance_pt_to_line_segment_phillip_nicoletti((0,0), (1,0), (2,1))
   # """)
   # But with just the denom being float'd, it's 2.5 secs to timeit. Weird.
   # >>> tit = timeit.Timer('1');tit.timeit()
   # 0.01998615264892578
   # >>> tit = timeit.Timer('float(1.0)');tit.timeit()
   # 0.11561393737792969
   r_numer = ((x0 - x1) * (x2 - x1)) + ((y0 - y1) * (y2 - y1))
   r_denom = float(((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1)))
   try:
      r = r_numer / r_denom
   except ZeroDivisionError:
      r = float('inf')

   px = x1 + r * (x2 - x1)
   py = y1 + r * (y2 - y1)

   s = (((y1 - y0) * (x2 - x1)) - ((x1 - x0) * (y2 - y1))) / r_denom

   # (xx, yy) is the point on the lineSegment closest to (x0, y0)
   xx = px
   yy = py

   if ((r >= 0) and (r <= 1)):
      distanceLine = abs(s) * math.sqrt(r_denom)
      distanceSegment = distanceLine
   else:
      dist1 = (x0-x1)*(x0-x1) + (y0-y1)*(y0-y1)
      dist2 = (x0-x2)*(x0-x2) + (y0-y2)*(y0-y2)
      if dist1 < dist2:
         xx = x1
         yy = y1
         distanceSegment = math.sqrt(dist1)
      else:
         xx = x2
         yy = y2
         distanceSegment = math.sqrt(dist2)

   return distanceSegment

#
def dist_squared((x1, y1), (x2, y2)):
   return float(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2))

#
def distToSegmentSquared((x0, y0), (x1, y1), (x2, y2)):
   l2 = dist_squared((x1, y1), (x2, y2))
   if l2 == 0:
      return dist_squared((x0, y0), (x1, y1))
   t = ((x0 - x1) * (x2 - x1) + (y0 - y1) * (y2 - y1)) / l2
   if t < 0:
      return dist_squared((x0, y0), (x1, y1))
   if t > 1:
      return dist_squared((x0, y0), (x2, y2))
   return dist_squared((x0, y0), (x1 + t * (x2 - x1), y1 + t * (y2 - y1)))

#
def distance_pt_to_line_segment_Grumdrig((x0, y0), (x1, y1), (x2, y2)):
   return math.sqrt(distToSegmentSquared((x0, y0), (x1, y1), (x2, y2)))

#
def distance_pt_to_line_segment_quano((x0, y0), (x1, y1), (x2, y2)):

   # https://stackoverflow.com/questions/849211/
   #  shortest-distance-between-a-point-and-a-line-segment

   x, y = pt_pt_to_line_seg((x0, y0), (x1, y1), (x2, y2))

   dx = x - x0
   dy = y - y0

   # Note: If the actual distance does not matter,
   # if you only want to compare what this function
   # returns to other results of this function, you
   # can just return the squared distance instead
   # (i.e. remove the sqrt) to gain a little performance

   dist = math.sqrt(dx*dx + dy*dy)

   return dist

#
def pt_pt_to_line_seg((x0, y0), (x1, y1), (x2, y2)):

   px = x2-x1
   py = y2-y1

   something = px*px + py*py

   try:
      u = ((x0 - x1) * px + (y0 - y1) * py) / float(something)
   except ZeroDivisionError:
      u = float('inf')

   if u > 1:
      u = 1
   elif u < 0:
      u = 0

   x = x1 + u * px
   y = y1 + u * py

   return x, y

#
def hausdorff_distance(a_xys, b_xys):
   # Complexity is (len(a_xys) - 1)*(lenb_xys) - 1)).
   a_candidates = hausdorff_worker(a_xys, b_xys)
   b_candidates = hausdorff_worker(b_xys, a_xys)
   longie_shortie = max(a_candidates + b_candidates, key=tuple_0value)
   # Tuple of the form:
   #  (dist from pt to line,
   #   ref to source xys, i.e., id(a_xys) or id(b_xys),
   #   source line vertex index,
   #   source point (x0, y0),
   #   target segment vertex lhs (x1, y1),
   #   target segment vertex rhs (x2, y2),)
   return longie_shortie

#
def hausdorff_worker(src_xys, dst_xys):
   candidates = []
   for src_idx, src_xy in enumerate(src_xys):
      if len(dst_xys) > 1:
         shortest_dists = []
         dst_xy1_idx = len(dst_xys) - 2
         while dst_xy1_idx >= 0:
            dst_xy1 = dst_xys[dst_xy1_idx]
            dst_xy2 = dst_xys[dst_xy1_idx + 1]
            pt_to_ln_dist = distance_pt_to_line_segment_quano(
                                       src_xy, dst_xy1, dst_xy2)
            shortest_dists.append((pt_to_ln_dist,
                                   id(src_xys),
                                   src_idx,
                                   src_xy,
                                   dst_xy1,
                                   dst_xy2,))
            dst_xy1_idx -= 1
         longest_dist_tuple = min(shortest_dists, key=tuple_0value)
         candidates.append(longest_dist_tuple)
      elif len(dst_xys) > 0:
         dst_xy1 = dst_xys[0]
         dst_xy2 = None
         pt_to_pt_dist = distance(src_xy, dst_xy1)
         candidates.append((pt_to_pt_dist, src_idx, dst_xy1, dst_xy2,))
      else:
         dst_xy1 = None
         dst_xy2 = None
         pt_to_pt_dist = -1
         candidates.append((pt_to_pt_dist, src_idx, dst_xy1, dst_xy2,))
   return candidates

#
# This is something I [lb] just came up with. Given two line
# segments and their hausdorff distance, returns a value
# between 0.0 and 1.0, inclusive, that gives some sort of
# confidence value about the match. If the two lines are
# equal, their Hausdorff is 0 and the normalized value is
# 1. If the hausdorff is greater than either of the two
# lines' length, the normalized value is 0.
def normalize_hausdorff(a_xys, b_xys, hausdorff):
   a_len = xy_line_len(a_xys)
   b_len = xy_line_len(b_xys)
   if (   (not a_len)
       or (hausdorff >= a_len)
       or (not b_len)
       or (hausdorff >= b_len)):
      carmelized = 0.0
   else:
      if a_len <= b_len:
         carmelized = (a_len - hausdorff) / b_len
      else:
         carmelized = (b_len - hausdorff) / a_len
   return carmelized

#
def tuple_0value(the_tuple):
   return the_tuple[0]

# *** SR

#
def spatial_reference_from_wkt(wkt):
   '''Return a spatial references from a WKT string.'''
   ref = osr.SpatialReference()
   ref.ImportFromWkt(wkt)
   return ref

#
def spatial_reference_from_srid(srid):
   '''Return a spatial reference object given the corresponding EPSG code.'''
   ref = osr.SpatialReference()
   ref.ImportFromEPSG(srid)
   return ref

# *** SVG

#
# See also: gml.flat_to_xys...
def svg_line_to_xy(svg):
   '''Convert an SVG line string to a list of (x, y) tuples. For example:
      "M 100 200 L 102 205 Z" -> [(100, 200), (102, 305)]'''
   g.assurt(svg[:2] == 'M ')
   svg = re.sub(r'[MLZ] ?', '', svg)
   coords = svg.split(' ')
   xys = list()
   for i in xrange(len(coords) / 2):
      xys.append((float(coords[i * 2]), float(coords[i * 2 + 1]),))
   return xys

#
def xy_line_to_svg(xys):
   '''Convert list of (x, y) tuples to SVG line string. For example:
      [(100, 200), (102, 305)] -> "M 100 200 102 205"'''
   # CAVEAT: This is old style SVG, without the Ls and the Z.
   #         Cyclopath uses it to send SVG to the clients.
   #         So don't expect the same SVG as PostGIS's ST_AsSVG.
   svg = 'M ' + ' '.join(['%s %s' % (xy[0], xy[1],) for xy in xys])
   return svg

# *** WKT

# Convert a PostGIS box, e.g., "BOX(1 2,5 6)", to a tuple, e.g., (1,2,5,6,).
def wkt_box_to_tuple(wkt, precision=None):
   wkt_tuples = wkt_line_to_xy(wkt, precision)
   return (wkt_tuples[0][0], wkt_tuples[0][1],
           wkt_tuples[1][0], wkt_tuples[1][1],)

#
def wkt_line_to_xy(wkt, precision=None):
   '''Convert a WKT line string to a list of (x, y) tuples. For example:
      "LINESTRING(-93.23 44.97, -93.45 45.23)" ->
      [(-93.23, 44.97), (-93.45, 45.23)]'''
   wkt_pairs = wkt[wkt.find('(')+1:wkt.find(')')].split(',')
   wkt_tuples = []
   for xy in wkt_pairs:
      sp = xy.split(' ')
      # Just looking at sp[0] and sp[1]; if sp[2], e.g., 3-d, ignoring z-value.
      pt_xy = (float(sp[0]), float(sp[1]),)
      if precision is not None:
         pt_xy = (round(pt_xy[0], precision), round(pt_xy[1], precision),)
      wkt_tuples.append(pt_xy)
   return wkt_tuples

# E.g., "POINT(1235.55 34.44)" or "SRID=1234;POINT(5.55 34.44)"
wkt_point_re = (
   re.compile(r'^(SRID=\d+)?;?POINT\((-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)\)$'))
# 2012.09.25: CcpV1 Route Sharing uses a different regex, but [lb] is not sure
# that it's righter or works. I.e., the ?: before SRID=, and the \d{,5} in:
#   wkt_point_re = re.compile(
#      r'^(?:SRID=\d{,5};)?POINT\((-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)\)$')

#
def wkt_point_to_xy(wkt, precision=None):
   '''Convert a WKT point string to an (x, y) tuple. For example:
      "POINT(-93.23 44.97)" -> tuple(-93.23, 44.97)'''
   m = wkt_point_re.match(wkt)
   # MAGIC NUMBERS: Re: 2 and 3: See wkt_point_re ()-groups.
   # MAYBE: Complain if .group(2) != 'SRID=%d' % (conf.default_srid,)
   pt_xy = (float(m.group(2)), float(m.group(3)),)
   if precision is not None:
      pt_xy = (round(pt_xy[0], precision), round(pt_xy[1], precision),)
   return pt_xy

#
def wkt_pointi(linestring, i):
   '''Return a WKT point representation of point i (0-based) of linestring,
      which can be either WKT or SVG.'''
   g.assurt(False) # No one uses this fcn.
   if (linestring[:2] == 'M '):
      c = linestring.split()
      c.pop(0)                      # remove "M"
      g.assurt(len(c) % 2 == 0)     # must be even number of elems
      return 'POINT(%s %s)' % (c[2*i], c[2*i + 1])
   else: # assume WKT
      g.assurt(False) # unimplemented

#
def wkt_polygon_to_xy(wkt, precision=None):
   '''Convert a WKT line string to a list of (x, y) tuples. For example:
      "POLYGON((-93.23 44.97, -93.45 45.23))" ->
      [(-93.23, 44.97), (-93.45, 45.23)]'''
   all_polys = []
   sub_polys = wkt[wkt.find('((')+2:wkt.find('))')].split('),(')
   for sub_poly in sub_polys:
      wkt_pairs = sub_poly.split(',')
      wkt_tuples = []
      for xy in wkt_pairs:
         sp = xy.split(' ')
         try:
            pt_xy = (float(sp[0]), float(sp[1]),)
         except ValueError:
            import pdb;pdb.set_trace()
         if precision is not None:
            pt_xy = (round(pt_xy[0], precision), round(pt_xy[1], precision),)
         wkt_tuples.append(pt_xy)
      all_polys.append(wkt_tuples)
   return all_polys

# FIXME: Implement Multi-polygon support.
#        E.g.,
#        MULTIPOLYGON(((40 40, 20 45, 45 30, 40 40)),
#        ((20 35, 10 30, 10 10, 30 5, 45 20, 20 35),
#        (30 20, 20 15, 20 25, 30 20)))
#
def wkt_polygon_to_xy_multi(wkt, precision=None):

   g.assurt(False) # FIXME: Implement Multi-polygon support.

# ***

#
def xy_eq_xy_line(a_ln_xy, b_ln_xy, threshold):
   '''Returns 0 if the lines are not equal, 1 if they're equivalent in
      the same direction, or -1 if they're equivalent in the opposite.'''
   if len(a_ln_xy) != len(b_ln_xy):
      is_equal = 0
   else:
      xy_len = len(a_ln_xy)
      ndex = 0
      is_equal = 1
      while ndex < xy_len:
         if not xy_eq_xy_point(a_ln_xy[ndex], b_ln_xy[ndex], threshold):
            is_equal = 0
            break
         ndex += 1
      if (is_equal == 0) and (xy_len > 1):
         # Try one of the lines in reverse.
         # xy_len = 1 / n=0,r=0
         # xy_len = 2 / n=0,r=1 / n=1,r=0
         # xy_len = 3 / n=0,r=2 / n=1,r=1 / n=2,r=0
         # xy_len = 4 / n=0,r=3 / n=1,r=2 / n=2,r=1 / n=3,r=0
         # xy_len = 5 / n=0,r=4 / n=1,r=3 / n=2,r=2 / n=3,r=1 / n=4,r=0
         ndex = 0
         refl = xy_len - 1
         is_equal = -1
         while ndex < xy_len:
            # refl = xy_len - ndex - 1
            if not xy_eq_xy_point(a_ln_xy[ndex], b_ln_xy[refl], threshold):
               is_equal = 0
               break
            ndex += 1
            refl -= 1
   return is_equal

#
def xy_eq_xy_point(a_pt_xy, b_pt_xy, threshold):
   if (    (abs(a_pt_xy[0] - b_pt_xy[0]) <= threshold)
       and (abs(a_pt_xy[1] - b_pt_xy[1]) <= threshold)):
      is_equal = True
   else:
      is_equal = False
   return is_equal

#
def xy_eq_xy_polygon(a_pg_xy, b_pg_xy, threshold):
   # The logic is the same for a line and a polygon:
   # thefy're both just lists of points.
   return xy_eq_xy_line(a_pg_xy, b_pg_xy, threshold)

#
def xy_to_wkt_line(wkt_tuples, precision=None, srid=conf.default_srid):
   return xy_to_wkt_line_(wkt_tuples, precision, srid, extended=False)

#
def xy_to_ewkt_line(wkt_tuples, precision=None, srid=conf.default_srid):
   return xy_to_wkt_line_(wkt_tuples, precision, srid, extended=True)

#
def xy_to_wkt_line_(wkt_tuples, precision, srid, extended):
   '''Convert a list of (x, y) tuples to a WKT line string. For example:
      [(-93.23, 44.97), (-93.45, 45.23)] ->
      "LINESTRING(-93.23 44.97, -93.45 45.23)"'''
   if not precision:
      fmt_point = "%s %s"
   else:
      g.assurt(precision >= 0)
      fmt_point = ("%%.%df %%.%df" % (precision, precision,))
   pairs = [(fmt_point % (x[0], x[1],)) for x in wkt_tuples]
   srid_prefix = "SRID=%s;" % (srid,) if extended else ''
   wkt_line = "%sLINESTRING(%s)" % (srid_prefix, ','.join(pairs),)
   return wkt_line

#
def xy_to_wkt_point(pt_xy, precision, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, precision, srid, extended=False)

#
def xy_to_ewkt_point(pt_xy, precision, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, precision, srid, extended=True)

#
def xy_to_wkt_point_(pt_xy, precision, srid, extended):
   # E.g., "SRID=%s;POINT(%.1f %.1f)"
   g.assurt(precision >= 0)
   srid_prefix = "SRID=%s;" % (srid,) if extended else ''
   fmt_point = ("%sPOINT(%%.%df %%.%df)"
                % (srid_prefix, precision, precision,))
   wkt_point = (fmt_point % (pt_xy[0], pt_xy[1],))
   # 2013.10.18: [lb] notes that PostGIS removes the decimal part if it's
   #             just zero, which is fine, since we know how many significant
   #             digits we're using (so we don't need to, i.e., encode it
   #             in the value like we would if we were doing longform math
   #             on a piece of paper). So, to make it easier to compare
   #             values we create here with values from PostGIS (e.g., via
   #             ST_GeomFromEWKT), strip the decimal if it's zero.
   wkt_point = re.sub(r'\.0+([^\d])', r'\1', wkt_point)
   return wkt_point

#
def xy_to_wkt_point_lossless(pt_xy, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, conf.geom_precision, srid, extended=False)

#
def xy_to_ewkt_point_lossless(pt_xy, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, conf.geom_precision, srid, extended=True)

#
def xy_to_wkt_point_restrict(pt_xy, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, conf.node_precision, srid, extended=False)

#
def xy_to_ewkt_point_restrict(pt_xy, srid=conf.default_srid):
   return xy_to_wkt_point_(pt_xy, conf.node_precision, srid, extended=True)

#
def xy_to_wkt_polygon(polygons_xy, precision=None, srid=conf.default_srid):
   return xy_to_wkt_polygon_(polygons_xy, precision, srid, extended=False)

#
def xy_to_ewkt_polygon(polygons_xy, precision=None, srid=conf.default_srid):
   return xy_to_wkt_polygon_(polygons_xy, precision, srid, extended=True)

#
def xy_to_wkt_polygon_(polygons_xy, precision, srid, extended):
   # E.g., "SRID=%s;POLYGON((%.1f %.1f, ...))"
   listses = xy_to_wkt_polygon_solo(polygons_xy, precision)
   srid_prefix = "SRID=%s;" % (srid,) if extended else ''
   wkt_polygon = "%sPOLYGON((%s))" % (srid_prefix, '),('.join(listses),)
   return wkt_polygon

#
def xy_to_wkt_polygon_solo(polygons_xy, precision):
   if not precision:
      fmt_point = "%s %s"
   else:
      g.assurt(precision >= 0)
      # NOTE: The %.[0-9]f operator rounds.
      fmt_point = ("%%.%df %%.%df" % (precision, precision,))
   listses = []
   for poly_xys in polygons_xy:
      pairs = [(fmt_point % (x[0], x[1],)) for x in poly_xys]
      listses.append(','.join(pairs))
   return listses

#
def xy_to_wkt_polygon_multi(polygons_xy, precision=None,
                            srid=conf.default_srid):
   return xy_to_wkt_polygon_multi_(polygons_xy, precision, srid,
                                   extended=False)

#
def xy_to_ewkt_polygon_multi(polygons_xy, precision=None,
                            srid=conf.default_srid):
   return xy_to_wkt_polygon_multi_(polygons_xy, precision, srid, extended=True)

#
def xy_to_wkt_polygon_multi_(polygons_xy, precision, srid, extended):
   # E.g.,
   # "SRID=26915;MULTIPOLYGON(((40 40, 20 45, 45 30, 40 40)),
   #  ((20 35, 10 30, 10 10, 30 5, 45 20, 20 35),
   #  (30 20, 20 15, 20 25, 30 20)))"
   wkt_polys = []
   for poly_xys in polygons_xy:
      listses = xy_to_wkt_polygon_solo(poly_xys, precision)
      wkt_polys.append('(%s)' % ('),('.join(listses)),)
   srid_prefix = "SRID=%s;" % (srid,) if extended else ''
   wkt_mpolygon = ("%sMULTIPOLYGON((%s))"
                   % (srid_prefix, '),('.join(wkt_polys),))
   return wkt_mpolygon

#
def xy_to_raw_point(pt_xy, precision, srid=conf.default_srid):
   # E.g., "ST_GeomFromEWKT('SRID=%s;POINT(%.1f %.1f)')"
   raw_point = (
      "ST_GeomFromEWKT('%s')"
      % (xy_to_ewkt_point(pt_xy, precision, srid),))
   return raw_point

#
def xy_to_raw_point_lossless(pt_xy, srid=conf.default_srid):
   return xy_to_raw_point(pt_xy, conf.geom_precision, srid)

#
def xy_to_raw_point_restrict(pt_xy, srid=conf.default_srid):
   return xy_to_raw_point(pt_xy, conf.node_precision, srid)

#
def xy_to_xy_line__deprecated(ln_xy, tolerance, pretemper=None):
   '''Convert a list of (x, y) tuples to a list with specified precision.'''

   # This fcn. used to convert to string and then quantize, but
   # there are a couple of problems with that.
   #
   # 1. Consider two points whose precision doesn't match.
   #    The quantize fcn. will round equivalentish values
   #    differently.
   #
   # >>> Decimal('369426.250000').quantize(Decimal('.1'))
   # Decimal('369426.2')
   # >>> Decimal('369426.250000915').quantize(Decimal('.1'))
   # Decimal('369426.3')
   #
   # You might be able to quantize twice as a possible work-around,
   #
   # >>> Decimal('369426.250000915').quantize(Decimal('.01')) \
   #     .quantize(Decimal('.1'))
   # Decimal('369426.2')
   # >>> Decimal('369426.250000915').quantize(Decimal('.01'))
   # Decimal('369426.25')
   #
   # but it's probably better to find a better solution.
   #
   # 2. Converting to string defaults to just six digits of
   #    precision, and if it rounds, and then you round again,
   #    two equivalentish values again won't match.
   #
   # >>> str(372573.945000904)
   # '372573.945001'
   # >>> str(372573.9450000003)
   # '372573.945'
   #
   # >>> Decimal('372573.945001').quantize(Decimal('.01')) \
   #     .quantize(Decimal('.1'))
   # Decimal('372574.0')
   # >>> Decimal('372573.945').quantize(Decimal('.01')) \
   #     .quantize(Decimal('.1'))
   # Decimal('372573.9')
   #
   # You might be able to be more deliberate about the string conversion,
   # 
   # >>> '%.28f' % (372573.945000904,)
   # '372573.9450009039719589054584503174'
   #
   # but again, it's probably better to find a better solution.

   g.assurt(False) # deprecated fcn.

   xy_precise = []
   for xy in ln_xy:
      if pretemper is None:
         pt_xy = (Decimal(str(xy[0])).quantize(tolerance),
                  Decimal(str(xy[1])).quantize(tolerance),)
      else:
         pt_xy = (Decimal(str(xy[0])).quantize(pretemper).quantize(tolerance),
                  Decimal(str(xy[1])).quantize(pretemper).quantize(tolerance),)
      xy_precise.append(pt_xy)
   return xy_precise

#
def xy_to_xy_line(ln_xy, precision):
   '''Convert a list of (x, y) tuples to a list with specified precision.'''

   # We round twice to work around a problem with inequality when equal.
   #
   # And while it looks like just rounding to one more precision works:
   #
   # >>> round(351509.550000944, 1)
   # 351509.6
   # >>> round(351509.5499999998, 1)
   # 351509.5
   # >>> round(351509.550000944, 2)
   # 351509.55
   # >>> round(351509.5499999998, 2)
   # 351509.55
   # >>> round(round(351509.550000944, 2), 1)
   # 351509.5
   # >>> round(round(351509.5499999998, 2), 1)
   # 351509.5
   #
   # If doesn't always:
   #
   # (Pdb) round(615939.954999045, 1)
   # 615940.0
   # (Pdb) round(615939.9550000001, 1)
   # 615940.0
   # (Pdb) round(615939.954999045, 2)
   # 615939.95
   # (Pdb) round(615939.9550000001, 2)
   # 615939.96
   # (Pdb) round(round(615939.954999045, 2), 1)
   # 615939.9
   # (Pdb) round(round(615939.9550000001, 2), 1)
   # 615940.0
   # 
   # So maybe two more digits of precision works? Hrm:
   #
   # (Pdb) round(351509.550000944, 3)
   # 351509.55
   # (Pdb) round(351509.5499999998, 3)
   # 351509.55
   # (Pdb) round(round(351509.550000944, 3), 1)
   # 351509.5
   # (Pdb) round(round(351509.5499999998, 3), 1)
   # 351509.5
   # (Pdb) 
   # 351509.5
   # (Pdb) round(615939.954999045, 3)
   # 615939.955
   # (Pdb) round(615939.9550000001, 3)
   # 615939.955
   # (Pdb) round(round(615939.954999045, 3), 1)
   # 615940.0
   # (Pdb) round(round(615939.9550000001, 3), 1)
   # 615940.0
   #
   # Check another case:
   # 
   # (Pdb) round(615939.9504999045, 1)
   # 615940.0
   # (Pdb) round(615939.95050000001, 1)
   # 615940.0
   # (Pdb) round(615939.9504999045, 3)
   # 615939.95
   # (Pdb) round(615939.95050000001, 3)
   # 615939.951
   # (Pdb) round(round(615939.9504999045, 3), 1)
   # 615939.9
   # (Pdb) round(round(615939.95050000001, 3), 1)
   # 615940.0

   xy_precise = []

   for xy in ln_xy:
      pt_xy = (round(xy[0], precision), round(xy[1], precision),)
      xy_precise.append(pt_xy)

   return xy_precise

#
def xy_to_xy_point(pt_xy, precision):
   xy_precise = (round(pt_xy[0], precision), round(pt_xy[1], precision),)
   return xy_precise

#
def xy_to_xy_polygon(pg_xy, precision):
   xy_precise = []
   for middle_poly in pg_xy:
      xy_middle = []
      for inner_poly in middle_poly:
         if not isinstance(inner_poly, list):
            inner_poly = [inner_poly,]
         xy_inner = []
         for xy in inner_poly:
            pt_xy = (round(xy[0], precision), round(xy[1], precision),)
            xy_precise.append(pt_xy)
         xy_precise.append(xy_inner)
      xy_precise.append(xy_middle)
   return xy_precise

# *** Helpers

#
# NOTE: This so-called utility class is coupled to conf.py.
def raw_xy_make_precise(pt_xy, precision=conf.node_tolerance): # 0.1 meters
   # Check that our understanding of the precision is accurate.
   # The OGR library says 15 significant digits. Our x,y numbers
   # are usually in the hundreds of thousands of meters for x, and the
   # millions for y, so 6 or 7 non-decimal places and 8 or 9 decimal places.
   # Of course, 2 decimal places is on the units of centimeters, and our
   # data is not more accurate than that. Maybe even not by the decimeter.
   # NOTE: pt_xy is an (x,y,z) tuple from ogr. We don't care about the y.
   # NOTE: Python 2.6 complains is this is a float and not a str:
   #          TypeError: Cannot convert float to Decimal.
   #                     First convert the float to a string
   #       Python 2.7 doesn't care. But you get different results:
   #       >>> Decimal(2.0)     ==>   Decimal('2')
   #       >>> Decimal('2.0')   ==>   Decimal('2.0')
   pt_xy = (Decimal(str(pt_xy[0])), Decimal(str(pt_xy[1])))
 #  d_places_x = abs(pt_xy[0].as_tuple().exponent)
 #  d_places_y = abs(pt_xy[1].as_tuple().exponent)
 #  d_places = min(d_places_x, d_places_y)
   # It doesn't help to check the byway's xy coordinates to see what their
   # precision is: some xys in the database are whole numbers. So we'll just
   # have to assume they're accurate to the nearest... centimeter? Should
   # ask Reid.
   #if d_places < conf.node_tolerance:
   #   log.error('XY has fewer decimal places than expected: %d' % d_places)
   #   log.verbose4('pt_xy: %s' % (pt_xy,))
   #   g.assurt(False)
   #pt_xy = (pt_xy[0].quantize(conf.node_tolerance),
   #         pt_xy[1].quantize(conf.node_tolerance))
   pt_xy = (pt_xy[0].quantize(precision), pt_xy[1].quantize(precision))
   return pt_xy

#
def xy_line_len(xys):
   '''Compute the length of a linestring represented as a list of (x,y) tuples.
      The input matches the output of functions like svg_line_to_xy().'''
   length = 0.0
   prev = None
   for xy in xys:
      if prev is not None:
         dx = prev[0] - xy[0]
         dy = prev[1] - xy[1]
         length = length + math.sqrt(dx * dx + dy * dy)
      prev = xy
   return length

# ***

#
class Geo_Transform(object):

   #
   def __init__(self, gt):
      '''Create a geotransform object from a gdal geotransform array.'''
      self.top_left_x = gt[0]
      self.we_pixel_resolution = gt[1]
      self.rotation_x = gt[2]
      self.top_left_y = gt[3]
      self.rotation_y = gt[4]
      self.ns_pixel_resolution = gt[5]

   #
   def transform_point(self, x, y):
      '''Transform a point using the geo transform.'''
      x = int(abs((x - self.top_left_x) / self.we_pixel_resolution))
      y = int(abs((y - self.top_left_y) / self.ns_pixel_resolution))
      return (x, y)

   # ***

# ***

class Some_Test(object):

   #
   def __init__(self):
      '''2014.03.09: Tinkering further with a new test framework.

      Just
         cd $cp/pyserver
         ./ccp.py -i
         from util_ import geometry
         geometry.Some_Test()

         TODO: Either an --exec switch, and/or accept stdin, e.g.,
         echo "from util_ import geometry; geometry.Some_Test()" | ./ccp.py

./ccp.py -i
from util_.geometry import *
from util_.geometry_useful import *
#distance_pt_to_line_infinite((0,0), (1,0), (2,1))
distance_pt_to_line_segment_phillip_nicoletti((0,0), (1,0), (2,1))
distance_pt_to_line_segment_Grumdrig((0,0), (1,0), (2,1))
distance_pt_to_line_segment_quano((0,0), (1,0), (2,1))
# geoPointLineDist((0,0), ((1,0), (2,1)))
geoPointLineDist((0,0), ((1,0), (2,1)), testSegmentEnds=True)


./ccp.py -i
import timeit
tit = timeit.Timer(stmt="""
   from util_ import geometry
   geometry.distance_pt_to_line_segment_quano((0,0), (1,0), (2,1))
""")
tit.timeit(number=1000000) # 2.2 secs
tit.timeit(number=10000000) # 22.1 secs
tit = timeit.Timer(stmt="""
   from util_ import geometry
   geometry.distance_pt_to_line_segment_phillip_nicoletti((0,0), (1,0), (2,1))
""")
tit.timeit(number=1000000) # 2.8 secs
tit.timeit(number=10000000) # 27.8 secs

tit = timeit.Timer(stmt="""
   from util_ import geometry
   geometry.distance_pt_to_line_segment_Grumdrig((0,0), (1,0), (2,1))
""")
tit.timeit(number=1000000) # 4.2 secs
tit = timeit.Timer(stmt="""
   from util_ import geometry_useful
   geometry_useful.geoPointLineDist((0,0), ((1,0), (2,1)), testSegmentEnds=True)
""")
tit.timeit(number=1000000) # 8.1 secs


./ccp.py -i
from util_.geometry import *
distance_pt_to_line_segment_quano((-2.25,33.0), (126.33,0), (233,112))
distance_pt_to_line_segment_quano((1,1), (-100,-90), (-90,-80))



./ccp.py -i
from util_.geometry import *
a = [[0,0]]
b = [[1,0], [2,1]]
hausdorff_worker(a, b)
hausdorff_worker(b, a)
hausdorff_distance(a, b)
hausdorff_distance(b, a)
a = [[0,0], [0,0]]
b = [[1,0], [2,1]]
hausdorff_worker(a, b)
hausdorff_worker(b, a)
hausdorff_distance(a, b)
hausdorff_distance(b, a)
a = [[200,300]]
b = [[100,100], [100,200]]
hausdorff_worker(a, b)
a = [[150,150]]
b = [[100,100], [100,200]]
hausdorff_worker(a, b)
hausdorff_distance(a, b)

a = [[100,102], [200,102]]
b = [[ 98,100], [100,100], [148,100], [150, 98], [152, 100], [200,100,]]
hausdorff_distance(a, b)
hausdorff_distance(b, a)

./ccp.py -i
import timeit
tit = timeit.Timer(stmt="""
   from util_ import geometry
   a = [[100,102], [200,102]]
   b = [[ 98,100], [100,100], [148,100], [150, 98], [152, 100], [200,100,]]
   geometry.hausdorff_distance(a, b)
""")
tit.timeit(number=1000000) # 41.7 secs


SELECT ST_HausdorffDistance(
   'POINT (0 0)'::GEOMETRY,
   'LINESTRING (1 0, 2 1)'::GEOMETRY);
 st_hausdorffdistance
----------------------
     2.23606797749979

SELECT ST_HausdorffDistance(
  'LINESTRING (100 102, 200 102)'::GEOMETRY,
  'LINESTRING (98 100, 100 100, 148 100, 150 98, 152 100, 200 100)'::GEOMETRY);
 st_hausdorffdistance
----------------------
                    4


      '''

      pass

   # ***

# ***

if (__name__ == '__main__'):
   # The problem with trying to test individual files, e.g.,
   #  test = Some_Test()
   # here, and from the command line,
   #  cd /ccp/dev/cp/pyserver/util_/
   #  ./geometry.py
   # The problem is imports at the start of the file, e.g.,
   #  import conf / g / logger.
   # BUG nnnn: Unit test framework to load conf / g / logger,
   # and then load every file and try to create Some_Test().
   # Obviously, this infrastructure could become more complicated,
   # like testing only certain files, or having different levels
   # of testing... but then we'd have to go back over all our old
   # code and actually write test code! With "stable" code like
   # Ccp, we might be able to get away with functional testing.
   # E.g., using ccp.py to test GWIS commands and comparing
   # server responses to known values. We'd still want to write
   # unit test code for the important base and utility classes
   # (like this file, geometry.py!), but functional testing
   # the client API seems much more worth our time and probably
   # has the biggest payoff.
   pass

# ***

