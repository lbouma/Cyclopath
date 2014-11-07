# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis.query_base import Query_Base
from gwis.exception.gwis_error import GWIS_Error
from util_ import rect

log = g.log.getLogger('gwis.q_viewport')

class Query_Viewport(Query_Base):
   '''
   A rectangular query consists of two orthorectangles, the include rect
   and the exclude rect. It matches all features which

      (a) have any part which intersects the include rect, and
      (b) and do not have any part which intersects the exclude rect.

   The exclude rect can be None, in which case part (b) does not apply.
   '''

   __after_slots__ = (
      'include',
      'exclude',
      )

   def __init__(self, req):
      # NOTE: req only needed if decoding GWIS.
      Query_Base.__init__(self, req)
      self.include = None
      self.exclude = None

   # *** Public interface

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
      return (    (self.include == other.include)
              and (self.exclude == other.include))

   #
   def __ne__(self, other):
      return not (self == other)

   #
   def __str__(self):
      return '(rq i="%s" e="%s")' % (str(self.include), str(self.exclude))

   #
   def as_sql_where(self, rev, alias):
      'Return an SQL WHERE snippet representing the include and exclude rects.'
      where_clause = ""
      table_prefix = Query_Base.table_name_prefixed(alias)
      if self.include is not None:
         where_clause = self.include.sql_intersect(table_prefix + "geometry")
      if self.exclude is not None:
         g.assurt(self.include is not None)
         where_clause = ("(%s) AND NOT (%s)" 
            % (where_clause, 
               self.exclude.sql_intersect(table_prefix + "geometry")))
      return where_clause

   #
   def decode_gwis(self):
      # Consume the bounding box restraints, if supplied.
      bbox_include = self.req.decode_key('bbxi', None)
      bbox_exclude = self.req.decode_key('bbxe', None)
      if self.req.cmd.filter_geo_enabled:
         if bbox_include is not None:
            self.parse_strs(bbox_include, bbox_exclude)
      else:
         if (bbox_include is not None) or (bbox_exclude is not None):
            # self.req.client/filters/revision.decode_gwis() has been called;
            # only self.req.branch.decode_gwis() remains.
            log.error(
               'decode_gwis: unexpected: q_vp: %s / q_fs: %s / q_rn: %s / %s'
               % (str(self),
                  str(self.req.filters),
                  str(self.req.revision),
                  str(self.req),))
            #raise GWIS_Error('This command does not expect bbxi or bbxe')
            bbox_include = None
            bbox_exclude = None

   #
   def parse_strs(self, bbox_include, bbox_exclude):
      '''Initialize myself according to the key/value pairs in dict d (i.e.,
         include bbox at key bbox and exclude bbox at bbox_exclude). If prefix
         is provided, use that key prefix when looking up values.'''
      g.assurt(bbox_include is not None)
      self.include = rect.Rect()
      self.include.parse_str(bbox_include)
      if (bbox_exclude is not None):
         self.exclude = rect.Rect()
         self.exclude.parse_str(bbox_exclude)

   # *** Encode GWIS

   # NOTE: Called by ccp.py to make a url to send to pyserver. See decode_gwis,
   #       which is the inverse of this function (it decodes the url we encode
   #       here).
   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::url_append_filters
   #                (Flashclient stores the bboxes in the filters object and
   #                doesn't have a query_viewport like we do.)
   def url_append_bboxes(self, url_str):
      g.assurt(url_str)
      if self.include:
         url_str += '&bbxi=' + self.include.as_raw(precision=0)
         # Only include exclude bbox if include bbox specified.
         if self.exclude:
            url_str += '&bbxe=' + self.exclude.as_raw(precision=0)
      return url_str

# *** Unit testing

if (__name__ == '__main__'):
   import sys
   from item.util import revision
   rev = sys.argv[1]
   bbox_include = sys.argv[2]
   try:
      bbox_exclude = sys.argv[3]
   except IndexError:
      bbox_exclude = None
   areq = None
   req = gwis.request.Request(areq)
   r = Query_Viewport(req)
   r.parse_strs(bbox_include, bbox_exclude)
   v = revision.Revision.revision_object_get(rev)
   print r.as_sql_where(v, 'f')

