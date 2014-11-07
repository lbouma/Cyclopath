# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import re

import conf
import g

from gwis.exception.gwis_error import GWIS_Error

log = g.log.getLogger('util_.rect')

coord_re = re.compile(r'^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$')

class Rect(object):
   '''An orthogonally aligned rectangle.'''

   """
   __slots__ = ('xmin',
                'ymin',
                'xmax',
                'ymax')
   """

   # ***

   def __init__(self, xmin=None, ymin=None, xmax=None, ymax=None):
      # FIXME: Should this class use Decimal?
      self.xmin = xmin
      self.ymin = ymin
      self.xmax = xmax
      self.ymax = ymax

   # ***

   """
   #
   def __getstate__(self):
      return False

   #
   def __setstate__(self, state):
      g.assurt(False)
   """

   #
   def __eq__(self, other):
      return (    (self.xmin == other.xmin)
              and (self.ymin == other.ymin)
              and (self.xmax == other.xmax)
              and (self.ymax == other.ymax))

   #
   def __ne__(self, other):
      return not (self == other)

   #
   def __str__(self):
      # 2012.07.12: Being explicit about precision. This used to just be %f.
      #E.g., ("'BOX(%.6f %.6f, %.6f %.6f)'::Box2d"
      #       % (self.xmin, self.ymin, self.xmax, self.ymax,))
      box_sql = (("'BOX(%%.%df %%.%df, %%.%df %%.%df)'::Box2d"
                  % tuple([conf.geom_precision,] * 4))
                 % (self.xmin, self.ymin, self.xmax, self.ymax,))
      return box_sql


   #
   def as_raw(self, precision=None):
      if precision == 0:
         # This isn't really necessary: %.0f is the same as %d.
         fmt = '%d,%d,%d,%d'
      elif precision is None:
         fmt = '%f,%f,%f,%f'
      else:
         g.assurt(precision > 0)
         fmt = '%%.%(p)df,%%.%(p)df,%%.%(p)df,%%.%(p)df' % {'p': precision,}
      return (fmt % (self.xmin, self.ymin, self.xmax, self.ymax,))

   #
   def as_wkt(self):
      # 2012.07.12: Being explicit about precision. This used to just be %f.
      # 2013.05.27: Only apache2sql.py calls this, and db_glue.dict_prep
      #             complains that the format is missing the SRID.
      poly_sql = ((
         """SRID=%(srid)s;POLYGON((
            %%.%(p)df %%.%(p)df, 
            %%.%(p)df %%.%(p)df, 
            %%.%(p)df %%.%(p)df, 
            %%.%(p)df %%.%(p)df, 
            %%.%(p)df %%.%(p)df))"""
            % {'srid': conf.default_srid,
               'p': conf.geom_precision,})
         % (self.xmin, self.ymin,
            self.xmin, self.ymax,
            self.xmax, self.ymax,
            self.xmax, self.ymin,
            self.xmin, self.ymin))
      return poly_sql

   #
   def parse_str(self, s):
      try:
         m = coord_re.match(s)
         if (m is None):
            raise ValueError("Can't parse coordinates '%s'" % s)
         self.xmin = float(m.group(1))
         self.ymin = float(m.group(2))
         self.xmax = float(m.group(3))
         self.ymax = float(m.group(4))
      except ValueError, e:
         raise GWIS_Error('Cannot parse rectangle: err: "%s" (str: "%s")' 
                          % (str(e), s,))

   #
   def sql_geom(self):
      'Return a SQL snippet representing me as a geometry.'
      return ('ST_SetSRID(%s, %d)' % (self, conf.default_srid,))

   #
   def sql_intersect(self, col):
      'Return a SQL WHERE snippet returning true when I intersect column col.'
      # 2013.10.31: Make sure the source geometry is not empty, lest postgres
      # complain:
      #  ERROR:  Relate Operation called with a LWGEOMCOLLECTION type.
      #           This is unsupported.
      #  HINT:  Change argument 1: 'SRID=26915;GEOMETRYCOLLECTION EMPTY'
      sql_intersect = (
         " ((NOT ST_IsEmpty(%s)) AND (ST_Intersects(%s, ST_SetSRID(%s, %d)))) "
         % (col, col, str(self), conf.default_srid,))
      return sql_intersect

   #
   def sql_within(self, col):
      'Return a SQL WHERE snippet returning true when I am within column col.'
      sql_within = (
         " ((NOT ST_IsEmpty(%s)) AND (ST_Within(%s, ST_SetSRID(%s, %d)))) "
         % (col, col, str(self), conf.default_srid,))
      return sql_within

   #
   def area(self):
      return (self.xmax - self.xmin) * (self.ymax - self.ymin)

   # ***

# ***

