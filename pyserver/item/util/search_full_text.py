# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('srch_fll_txt')

# ***

# FIXME: Implement this?

# See Postgis Geometry Relationship Functions:
#   http://postgis.refractions.net/documentation/manual-1.3/ch06.html#id2574517

# +waypoint:tag:"bike lane"
# +byway:/byway/speed_limit:<20
# +byway:/byway/one_way:1
# +byway,waypoint:
# +waypoint:intersects:region:tag:neighborhood

class Geometry_Relationship_Query(object):

   __slots__ = (
      'attc_compare_col',
      'attc_compare_op',
      'attc_compare_val',
      )

   def __init__(self):
      self.attc_compare_col = None
      self.attc_compare_op = None
      self.attc_compare_val = None

class Geometry_Relationship_Query(object):

   __slots__ = (
      'attc_type_id',
      'attc_compares',
      )

   def __init__(self):
      self.attc_type_id = 0
      self.attc_compares = []

class Geometry_Relationship_Query(object):

   __slots__ = (
      'feat_type_ids',
      'attc_type_compares',
      'geom_compare',
      )

   def __init__(self):
      self.feat_type_ids = []
      self.attc_type_compares = []
      self.geom_compare = 'ST_Intersects'

# ***

class Full_Text_Query_Part(object):

   # Make sure this list is ordered, because it's used in the SELECTs of many
   # UNION ALLs, and result columns are unioned by position not by column name.
   # SYNC_ME: Search text search vect types.
   ts_vects = [
      'all',
      'addr',
      'name',
      'hood',
      'tag',
      'note',
      'post',
      ]

   vect_stop_words = {
      # This class doesn't use custom stop words for all, name, addr.
      #  No: 'all': ccp_stop_words.Addy_Stop_Words__Item_Versioned,
      #  No: 'name': ccp_stop_words.Addy_Stop_Words__Byway,
      #  No: 'addr': ccp_stop_words.Addy_Stop_Words__Byway,
      # Okay, maybe we do need stop words on the name... otherwise,
      # e.g., 'ave' hits on so many things. And, ideally, we'd have
      # separate stop words for byways, regions, and points, but
      # search_map calls item_user_access.Many().search_get_sql and
      # not byway.Many, waypoint.Many, etc... so it searches all
      # item types at once, meaning we can't easily check item_type-
      # specific stop words for the name from search_map....
      'name': ccp_stop_words.Addy_Stop_Words__Byway,
      'hood': ccp_stop_words.Addy_Stop_Words__In_Region,
      'tag': ccp_stop_words.Addy_Stop_Words__Tag,
      'note': ccp_stop_words.Addy_Stop_Words__Annotation,
      #'post': ccp_stop_words.Addy_Stop_Words__Thread,
      }

   __slots__ = (
      'gc_address',  # the geocoded address?
      'raw',         # the raw query pieces
      'tsv',         # the ts-vectorized query pieces
      )

   def __init__(self):
      self.gc_address = None
      self.raw = {}
      self.tsv = {}
      for key in Full_Text_Query_Part.ts_vects:
         self.raw[key] = []
         self.tsv[key] = ''

   def __str__(self):
      the_str = 'ftqp: '
      for key in Full_Text_Query_Part.ts_vects:
         the_str += ('/ %s: %s -> %s '
                     % (key, self.raw[key], self.tsv[key],))
      return the_str

   def assemble(self, db):

      log.debug('assemble: assemble ftq tsv: self.raw: %s'
                % (self.raw,))

      for key in Full_Text_Query_Part.ts_vects:

         # Exclude empty and None terms.
         raw_terms = [s for s in self.raw[key] if s]

         if raw_terms:

            no_stops = []
            try:
               no_stops = [t for t in raw_terms
                  if t not in Full_Text_Query_Part.vect_stop_words[key].lookup]
            except KeyError:
               # No stop words being used.
               no_stops = raw_terms

            if (not no_stops) or (len(raw_terms) > 1):
               # All the terms might be feature-specific stop words, e.g.,
               # "pine point park" is a real-named geofeature, but "pine",
               # "point" and "park" are all byway-specific stop words
               # (see Addy_Stop_Words__Byway) and later code doesn't like it
               # when self.tsv[key] isn't set, so at least set it with an
               # 'and' (&) of all the terms, stop words or not.
               no_stops.append(' '.join(raw_terms))

            # If a term is multiple words, in lieu of &ing the words together and
            # using parentheses around everything, we can just double quote
            # everything.
            #
            # E.g., to_tsquery('''washington ave n''|''222''|''mpls''|''mn''')
            # returns the same string as:
            #       to_tsquery('(washington&ave&n)|222|mpls|mn')
            #
            # We follow the first example, so double-quote each term, and then the
            # caller will again quote the whole thing. Note that db.quoted returns
            # a quoted string, so we just quote what's quoted, and we get a
            # doubly-quoted string.
            ts_terms = ["'%s'" % db.quoted(s) for s in no_stops]
            self.tsv[key] = "|".join(ts_terms)

         else:

            # This fcn. called like: self.ftq.exclude.assemble(self.qb.db)
            #  so there's not always a key for this ts_vects slot.

            self.tsv[key] = ""

   # ***

# ***

class Full_Text_Query(object):

   __slots__ = (
      'include',
      'exclude',
      )

   def __init__(self):
      self.include = Full_Text_Query_Part()
      self.exclude = Full_Text_Query_Part()

   # ***

# ***

