# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import difflib
import Levenshtein
from lxml import etree
import math

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.feat import byway
from item.feat import region
from item.feat import waypoint
from item.util import search_full_text
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import misc

log = g.log.getLogger('search_result')

class Search_Result_Geofeature(object):

   __slots__ = (
      'result_group',
      'stack_id',
      'geometry',
      'center',
      'x', # sometimes longitude
      'y', # sometimes latitude
      'width',
      'height',
      )

   def __init__(self, result_group):
      self.result_group = result_group
      self.stack_id = None
      self.geometry = None
      self.center = None
      self.x = None
      self.y = None
      self.width = None
      self.height = None

   #
   def __str__(self):
      return ('sid: %s / x, y: %s, %s (ctr: %s) / w x h: %s x %s / geom: %s'
              % (self.stack_id,
                 self.x,
                 self.y,
                 self.center,
                 self.width,
                 self.height,
                 self.geometry,))

   #
   def equal_ts(self, other):
      return self.result_group.equal_ts(other.result_group)

   # ***

# ***

class Search_Result_Group(object):

   __slots__ = (
      'gf_name',
      'gf_type_id',
      'gf_stack_id',
      # We remember the ts_query matches so we can compare search results and
      # so we can indicate to the client what types of terms this group of 
      # results matches.
      'ts_include',
      'ts_exclude',
      # These are used to group connected byways into a single search result.
      #'beg_nodes',
      #'fin_nodes',
      # This is a list of connected byways, grouped as a single result.
      'result_gfs',
      # The beg_node_id and fin_node_id of said connected byways.
      'node_ids',
      #
      'gc_fulfiller', # Geocoder source, e.g., Bing, MapQuest, Cyclopath, etc.
      'gc_confidence',
      )

   # used for sorting; if several objects have the same edit distance, regions
   # come before points and points before byways.
   object_priorities = {
      Item_Type.ADDY_COORDINATE: 1,
      Item_Type.ADDY_GEOCODE: 2, # I.e., external result.
      Item_Type.REGION: 3,
      Item_Type.WAYPOINT: 4,
      Item_Type.BYWAY: 5,
      }

   # MAGIC_NUMBER: See store_result_raw().
   ts_largest_scalar = 15

   def __init__(self):
      self.gf_name = None
      self.gf_type_id = None
      self.gf_stack_id = None
      self.ts_include = {}
      self.ts_exclude = {}
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         self.ts_include[vect_name] = False
         self.ts_exclude[vect_name] = False
      self.result_gfs = []
      self.node_ids = set()
      self.gc_fulfiller = None
      self.gc_confidence = None

   # *** Dev trace fcns.

   #
   def __str__(self):
      return ('srg: %s: (%d%s)'
              % (self.gf_name,
                 len(self.result_gfs), 
                 '-' if self.has_exclusion() else '',))

   #
   def __str__verbose__(self):
      hit_str = ''
      miss_str = ''
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         if self.ts_include[vect_name]:
            hit_str += vect_name + ' '
         if self.ts_exclude[vect_name]:
            miss_str += vect_name + ' '
      vstr = (
         '%s (%d%s): %s / cnf %s / "%s" / hit: %s / miss: %s'
         % (Item_Type.id_to_str(self.gf_type_id),
            len(self.result_gfs),
            '-' if self.has_exclusion() else '',
            ','.join([str(x.stack_id) for x in self.result_gfs]),
            self.gc_confidence,
            self.gf_name,
            hit_str,
            miss_str,))
      return vstr

   def __str__verbose_2__(self):
      rstr = ''
      try:
         rstr = (
            '%7s-typ:%2d / cnf %d / %s'
            % (self.gf_stack_id,
               self.gf_type_id,
               self.gc_confidence,
               #'in_addr ' if row['ts_in_addr'] else '',
               #'in_name ' if row['ts_in_name'] else '',
               #'in_hood ' if row['ts_in_hood'] else '',
               #'in_tag  ' if row['ts_in_tag']  else '',
               #'in_note ' if row['ts_in_note'] else '',
               #'in_post ' if row['ts_in_post'] else '',
               #'ex_addr ' if row['ts_ex_addr'] else '',
               #'ex_name ' if row['ts_ex_name'] else '',
               #'ex_hood ' if row['ts_ex_hood'] else '',
               #'ex_tag  ' if row['ts_ex_tag']  else '',
               #'ex_note ' if row['ts_ex_note'] else '',
               #'ex_post ' if row['ts_ex_post'] else '',
               self.gf_name,
               ))
      except KeyError, e:
         log.error(str(e))
      return rstr

   #
   @staticmethod
   def result_row_str(row):
      #vals = row.keys()
      #vals.sort()
      #for val in vals:
      #   pass
      rstr = ''
      try:
         rstr = (
            '%7s%s-acl:%s-grp:%s-typ:%2d / %s / %s'
            % (int(row['stack_id']),
               '+DEL' if row['deleted'] else '',
               row['access_level_id'],
               row['acl_grouping'],
               int(row['real_item_type_id']),
               # Skipping: row['valid_until_rid']: should be 2000000000000
               # Skipping: row['geometry']
               # Skipping: row['center'],
               # Skipping: row['beg_node_id'],
               # Skipping: row['fin_node_id'],
               # Not in the SQL row: float(row['gc_confidence']),
               '%s%s%s%s%s%s%s%s%s%s%s%s'
               % ('in_addr ' if row['ts_in_addr'] else '',
                  'in_name ' if row['ts_in_name'] else '',
                  'in_hood ' if row['ts_in_hood'] else '',
                  'in_tag  ' if row['ts_in_tag']  else '',
                  'in_note ' if row['ts_in_note'] else '',
                  'in_post ' if row['ts_in_post'] else '',
                  'ex_addr ' if row['ts_ex_addr'] else '',
                  'ex_name ' if row['ts_ex_name'] else '',
                  'ex_hood ' if row['ts_ex_hood'] else '',
                  'ex_tag  ' if row['ts_ex_tag']  else '',
                  'ex_note ' if row['ts_ex_note'] else '',
                  'ex_post ' if row['ts_ex_post'] else '',),
               #row['name'],
               row['name_enclosed'],
               ))
      except KeyError, e:
         log.error(str(e))
      return rstr

   # ***

   #
   def has_exclusion(self):
      excluded = False
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         if self.ts_exclude[vect_name]:
            excluded = True
            break
      return excluded

   #
   def equal_ts(self, other):
      equal = True
      g.assurt(self.gf_name == other.gf_name)
      g.assurt(self.gf_type_id == other.gf_type_id)
      #?g.assurt(self.gf_stack_id == other.gf_stack_id)
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         if ((self.ts_include[vect_name] != other.ts_include[vect_name])
             or (self.ts_exclude[vect_name] != other.ts_exclude[vect_name])):
            equal = False
            break
      return equal

   #
   def add_result_gp(self, result_gp):
      self.node_ids = self.node_ids.union(result_gp.node_ids)
      self.result_gfs.extend(result_gp.result_gfs)

   # BUG nnnn: V1 search sends array of TRUE/FALSE for include and exclude 
   # matches but flashclient treats results of ORing array (include and
   # exclude) as basis for filtering results.
   def as_xml(self):
      elem = etree.Element('result')
      misc.xa_set(elem, 'gf_name', self.gf_name)
      misc.xa_set(elem, 'gf_type_id', self.gf_type_id)
      # Skipping (since some are addys... or maybe that doesn't matter):
      #   misc.xa_set(elem, 'gf_stack_id', self.gf_stack_id)
      for result in self.result_gfs:
         obj = etree.Element('gf_item')
         misc.xa_set(obj, 'stack_id', result.stack_id)
         if result.geometry:
            misc.xa_set(obj, 'geometry', result.geometry)
         # Skipping center, which we only use interally.
         misc.xa_set(obj, 'x', result.x)
         misc.xa_set(obj, 'y', result.y)
         # MAYBE: width and height... or no one cares?
         elem.append(obj)
      # 
      obj_in = etree.Element('ts_in')
      obj_ex = etree.Element('ts_ex')
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         misc.xa_set(obj_in, vect_name, self.ts_include[vect_name])
         misc.xa_set(obj_ex, vect_name, self.ts_exclude[vect_name])
      elem.append(obj_in)
      elem.append(obj_ex)
      #
      return elem

   #
   def store_result_raw(self, row, raw_queries, search_map_obj):

      # Only call this fcn. on a new object, i.e., one that's not a group yet.
      g.assurt(not self.result_gfs)

      # Rather than use the item's real name, use the one that might include
      # the name of the region in parantheses.
      # Instead of: self.gf_name = row['gf_name']
      self.gf_name = row['name_enclosed']

      # Since we searched using item_user_access, we had to do a little extra
      # magic to get the item_type_id of the result.
      self.gf_type_id = row['real_item_type_id']

      # Finally, a straight forward value to consume.
      self.gf_stack_id = row['stack_id']

      # Consume all the ts_in/ts_ex_* values into two lookups.
      for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
         if vect_name != 'all':
            self.ts_include[vect_name] = bool(int(row['ts_in_' + vect_name]))
            self.ts_exclude[vect_name] = bool(int(row['ts_ex_' + vect_name]))

      # Remember byway node IDs so we can assemble connected byways into a
      # single group of results.
      try:
         self.node_ids.add(row['beg_node_id'])
         self.node_ids.add(row['fin_node_id'])
      except AttributeError:
         pass # Not a byway.

      # Setup the first, and maybe only, result geometry object.
      gf_res = Search_Result_Geofeature(self)
      gf_res.stack_id = row['stack_id']
      if ((self.gf_type_id == Item_Type.BYWAY)
          or (self.gf_type_id == Item_Type.REGION)):
         gf_res.geometry = row['geometry_svg']
      elif self.gf_type_id == Item_Type.WAYPOINT:
         # Skipping: geometry; would be same as 'center', so just leave None.
         pass
      else:
         raise GWIS_Error('Unexpected object type: %s.' % (self.gf_type_id,))
      gf_res.center = row['center']
      (gf_res.x, gf_res.y,) = geometry.wkt_point_to_xy(gf_res.center)
      gf_res.width = row['width']
      gf_res.height = row['height']

      # 2014.06.20: [lb] retiring use of ts_rank and switching to Levenshtein.
      #
      # What we're trying to do is to order matches better.
      #
      # Consider searching 'dupont ave s': the 's' is a full text stop word,
      # so the results will include anything with 'dupont' and 'ave', e.g.,
      # 'dupont ave s' and 'dupont ave n'.
      #
      # The problem with text search ranking -- or maybe it's how I've been
      # using it -- is that it doesn't really normalize well, i.e., two
      # separate comparisons on two different sets of equivalent terms
      # produces two different values.
      #
      # E.g,  
      #        SELECT ts_rank_cd(to_tsvector('english', 'dupont|ave|s'),
      #                          to_tsquery('english', 'dupont|ave|s'));
      # returns 0.2, even though the search term and the target exactly match.
      # Basically, for every non-stop word that matches ('dupont' and 'ave'),
      # the ts_rank_cd function increases the return value by 0.1 (starting
      # from 0).
      #
      # As another example, consider a four word term that's mostly stop words.
      #
      #        SELECT to_tsvector('english', 'what&is&my&name');
      #        SELECT to_tsquery('english', 'what&is&my&name');
      #          both return
      #         'name':4
      #          i.e., the other words are stop words.
      # and so we can expect the rank to be 0.1:
      #        SELECT ts_rank_cd(to_tsvector('english', 'what&is&my&name'),
      #                          to_tsquery('english', 'what&is&my&name'));
      #
      # What we want is a value from 0 to 1, where 1 means there's a strong
      # match between the strings, and 0 means no match. So I don't get why
      # ts_rank_cd basically just returns a count of words that match, but
      # it doesn't scale it according to the total number of terms (e.g., so
      # a one-word match for a one-word query returns a value of 1).
      #
      # The ts_rank and ts_rank_cd functions accept a normalization parameter,
      # but it doesn't seem to help. They also accept a weights parameter, but
      # [lb] doesn't really want to bother trying to figure out how it works,
      # 'cause I'm not sure it would help.
      #  "The weight arrays specify how heavily to weigh each category of word,
      #   in the order:
      #     {D-weight, C-weight, B-weight, A-weight}
      #   If no weights are provided, then these defaults are used:
      #     {0.1, 0.2, 0.4, 1.0}"
      #
      # Anyway, one last comment about ts_rank and then back to Levenshtein.
      #
      # The weights or word category might be how full text search judges
      # the strength of each term, e.g., the more unique and less-often used
      # a word is in English, the greater the value of the match for that term.
      #
      # SELECT to_tsvector('english','name|building|wonderful|downhill|party');
      #     'build':2 'downhil':4 'name':1 'parti':5 'wonder':3
      #
      # SELECT to_tsvector('english','name&building&wonderful&downhill&party');
      #     'build':2 'downhil':4 'name':1 'parti':5 'wonder':3
      #
      # SELECT to_tsquery('english', 'name|building|wonderful|downhill|party');
      #     ( ( ( 'name' | 'build' ) | 'wonder' ) | 'downhil' ) | 'parti'
      #
      # SELECT to_tsquery('english', 'name&building&wonderful&downhill&party');
      #     'name' & 'build' & 'wonder' & 'downhil' & 'parti'
      #
      # And here's a cross-reference of all the ts_rank(_cd) values.
      #
      # Note that the normalization integer is a bit flag from 0 to 32.
      # see: http://www.postgresql.org/docs/8.3/static/textsearch-controls.html
      #
      # Query: a|b|c|d|e: 'name|building|wonderful|downhill|party'
      # Query: a&b&c&d&e: 'name&building&wonderful&downhill&party'
      #
      #                   ts_rank    ts_rank_cd     ts_rank    ts_rank_cd
      # normalization    a|b|c|d|e    a|b|c|d|e    a&b&c&d&e    a&b&c&d&e   
      # ts_rank     0    0.0607927    0.5          0.644239     0.1
      # ts_rank     1    0.0235178    0.279055     0.249226     0.0558111
      # ts_rank     2    0.0121585    0.1          0.128848     0.02
      # ts_rank     4    0.0607927    0.4          0.644239     0.1
      # ts_rank     8    0.0121585    0.1          0.128848     0.02
      # ts_rank    16    0.0235178    0.193426     0.249226     0.0386853
      # ts_rank    32    0.0573088    0.333333     0.391816     0.0909091
      #
      # Although, one problem with Levenshtein is that it compares edit
      # distance, and it doesn't consider words. Consider:
      #
      #  >>> Levenshtein.ratio('drinking gateway', 'drinking gateway')
      #  1.0
      #  >>> Levenshtein.ratio('gateway fountain', 'fountain gateway')
      #  0.5
      # 
      # compared to:
      #
      #        SELECT ts_rank(to_tsvector('english', 'gateway|fountain'),
      #                       to_tsquery('english', 'gateway|fountain'));
      #        SELECT ts_rank(to_tsvector('english', 'gateway|fountain'),
      #                       to_tsquery('english', 'fountain|gateway'));
      # which both return
      #     ts_rank  
      #   -----------
      #    0.0607927
      #
      # and
      #        SELECT ts_rank(to_tsvector('english', 'gateway|fountain'),
      #                       to_tsquery('english', 'gateway&fountain'));
      #        SELECT ts_rank(to_tsvector('english', 'gateway|fountain'),
      #                       to_tsquery('english', 'fountain&gateway'));
      # which both return
      #     ts_rank  
      #   -----------
      #    0.0991032
      #
      # where
      #
      #        SELECT to_tsvector('english', 'gateway|fountain');
      #                    to_tsvector        
      #             --------------------------
      #              'fountain':2 'gateway':1
      #
      # so maybe Levenshtein is still better. But it also feels like I'm
      # missing something about ts_rank... like how to take advantage of
      # the word weights better?....
      #
      # Interesting:
      # >>> Levenshtein.ratio('999999 dupont ave s, mpls, mn', 'dupont ave s')
      # 0.5853658536585366
      # >>> Levenshtein.ratio('999999 dupont ave s, mpls, mn', 'dupont ave n')
      # 0.5853658536585366
      #
      # >>> Levenshtein.ratio('dupont ave s mpls mn', 'dupont ave s')
      # 0.75
      # >>> Levenshtein.ratio('dupont ave s mpls mn', 'dupont ave n')
      # 0.75
      # >>> Levenshtein.ratio('dupont ave s', 'dupont ave s')
      # 1.0
      # >>> Levenshtein.ratio('dupont ave s', 'dupont ave n')
      # 0.9166666666666666

      # The raw_queries list is: [clean_query, full_street, full_street2,],
      #  so rank a clean_query match higher.
      # Also, self.gf_name is row['name_enclosed'], which might include
      # a region name in parantheses, so here we use row['gf_name'] (which
      # then means that we don't rank points-in-region higher artifically,
      # e.g., searching for "Minneapolis" finds all points in Minneapolis...
      # I think...
      #  TESTME: Search neighborhood name: Do you get all points within?
      try:
         gf_basename = row['name'].lower()
         gf_name_len = len(row['name'].split())
      except Exception, e:
         # Unnamed.
         gf_basename = ''
         gf_name_len = 0

      # log.debug('EXPLAIN: store_result_raw: name_enclosed: %s / name: %s'
      #           % (row['name_enclosed'], row['name'],))
      # E.g.s when   row['name_enclosed'] != row['name']:
      #              'Unnamed'               None
      #              'BP (Lyndale)'          'BP'

      # Sort by edit distance, giving additional priority for each match type.
      # MAYBE: This calculation is just made up... there's probably a better
      #        was to implement this.
      scalar = 0.0

      #if row['ts_in_addr']:
      #   scalar += 3.0

      if row['ts_in_name']:
         # First implementation:
         #  scalar += 3.0
         # 2014.09.12 implementation:
         #  The ts_rank_cd is 0.1 times the number of times a query word hits.
         #   SELECT ts_rank_cd(to_tsvector('english',
         #      'abc|abc|abc|abc|abc|abc|abc|abc|abc|abc|abc|abc|abc'),
         #      to_tsquery('english', 'abc|def|ghi'));
         #    ts_rank_cd 
         #   ------------
         #           1.3
         #
         levenshteins = 0
         levenaccumul = 0.0
         # We average the levenshteins of the different query parts. E.g.,
         #  >>> Levenshtein.ratio('999999 dupont ave s, mpls, mn', 'dupont ave s')
         #  0.5853658536585366
         #  >>> Levenshtein.ratio('dupont ave s', 'dupont ave s')
         #  1.0
         # and
         #  >>> Levenshtein.ratio('999999 dupont ave s, mpls, mn', 'dupont ave n')
         #  0.5853658536585366
         #  >>> Levenshtein.ratio('dupont ave s', 'dupont ave n')
         #  0.9166666666666666
         # So, for the byway, dupont ave s, levenration = 0.7926829268292683,
         # and for the byway, dupont ave n, levenration = 0.7510162601626016.
         contains_query = 0
         for raw_query in raw_queries:
            levenaccumul += Levenshtein.ratio(raw_query, gf_basename)
            levenshteins += 1
            if gf_basename.find(raw_query) >= 0:
               contains_query += 1
         levenratio = levenaccumul / levenshteins
         #
         num_word_matches = round(10.0 * row['ts_rank_cd'])
         #
         #normalized_rank = min(num_word_matches / gf_name_len, 1.0)
         #scalar += (normalized_rank * 4.5) + (levenratio * 4.5)
         scalar += min(
            pow(gf_name_len, min(num_word_matches / gf_name_len, 1.0)), 4.0)
         scalar += levenratio * 3.5
         if contains_query:
            scalar += 3.5
         # MAGIC NUMBERS: 4.0 + 3.5 + 3.5 = 11.0

      # TESTME: Search, like, "dupont ave s unpaved" and see if you
      #         can get tagged matches ranked higher?
      if row['ts_in_tag']:
         scalar += 2.0

      if row['ts_in_hood']:
         scalar += 1.0

      if row['ts_in_note']:
         scalar += 1.0

      #if row['ts_in_post']:
      #   scalar += 1.0

      # MAGIC_NUMBER: Scalars above add up to this value:
      #               ((4 + 3.5 + 3.5) + 2 + 1 + 1):
      g.assurt(Search_Result_Group.ts_largest_scalar == 15)

      # MAYBE: Cyclopath calculates the confidence for external results and
      #        also for internal results, but the values are not comparable.
      #        They don't relate at all... so intermixing results isn't
      #        meaningful when considering external vs. internal results.
      #        They both produce a value from 0 to 100, but they only share
      #        the same meaning at 100%, i.e., an external geocode result with
      #        80% confidence is not the same confidence as an internal geocode
      #        result with 80% confidence. Oh, well...

      self.gc_confidence = round(
         100.0
         # MAGIC_NUMBER: The largest scalar is (9 + 2 + 1 + 1) = 13.
         * scalar / float(Search_Result_Group.ts_largest_scalar)
         )

      self.gc_fulfiller = 'ccp_gf';

      self.result_gfs.append(gf_res)

   #
   def store_result_item(self, db, item):

      # This fcn. is called on a new object only.
      g.assurt(not self.result_gfs)

      # This fcn. assumes the item is an exact match.
      self.gc_confidence = 100

      self.gc_fulfiller = 'ccp_gf';

      self.gf_name = item.name
      self.gf_type_id = item.item_type_id
      self.gf_stack_id = item.stack_id

      # MAGIC_NUMBER: See Full_Text_Query_Part.vect_stop_words.
      self.ts_include['name'] = True

      try:
         self.node_ids.add(item.beg_node_id)
         self.node_ids.add(item.fin_node_id)
      except AttributeError:
         pass # Not a byway.

      gf_res = Search_Result_Geofeature(self)
      gf_res.stack_id = item.stack_id

      # This is a little different than above.
      # MAYBE: Make a qb.filters to add the center SQL in the original item
      #        query.
      # BUG nnnn/LOW PRIORITY/MEH: Handle other item types, like ROUTE.
      if self.gf_type_id == Item_Type.BYWAY:
         # Wrong: gf_res.geometry = item.geometry
         gf_res.geometry = item.geometry_svg
         center_sql = byway.One.search_center_sql(geom=item.geometry)
      elif self.gf_type_id == Item_Type.REGION:
         # Wrong: gf_res.geometry = item.geometry
         gf_res.geometry = item.geometry_svg
         center_sql = region.One.search_center_sql(geom=item.geometry)
      elif self.gf_type_id == Item_Type.WAYPOINT:
         # Skipping: geometry; would be same as 'center', so leave None.
         center_sql = waypoint.One.search_center_sql(geom=item.geometry)
      else:
         # This happens if you, e.g., put a route stack ID in the search
         # box and search on that. We'll find the route item, but we're
         # currently not wired to return it.
         # BUG nnnn: Search by stack ID for any item type and open that
         #           item (load its panel, find it on the map, etc.).
         log.info('store_result_item: Unexpected obj. type: %s / %s'
                  % (self.gf_type_id, item,))
         # Wrong:
         #  raise GWIS_Error('Unexpected obj. type: %s.' % (self.gf_type_id,))
         center_sql = None

      if center_sql:

         center_sql = "SELECT %s AS center" % (center_sql,)
         rows = db.sql(center_sql)
         g.assurt(len(rows) == 1)
         gf_res.center = rows[0]['center']
         (gf_res.x, gf_res.y,) = geometry.wkt_point_to_xy(gf_res.center)

         # We don't need width and height... it's never used. But set to -1
         # just to mess up any future code that tries to use it without coming
         # here and reading this comment and fixing this code.
         gf_res.width = -1
         gf_res.height = -1

         self.result_gfs.append(gf_res)

   # BUG nnnn: V1, this should be dict, not log(n) iteration. And is it
   # guaranteed to be sorting? algorithm depends it is sorted by name, right?
   # yes, that is right, there's an order by, but we want to order by rank,
   # so... let's just use a dict here.
   # BUG nnnn: V1, is it O(n*(n-1)) because of node_id-matching?
   @staticmethod
   def process_results_byways(byway_results):
      '''Condenses a list of byway results, combining connected byways with the
      same name that also match on the same search queries into a single search
      result.'''

      # List of byways grouped by name, matches, and connectedness
      results = []

      # Dict of gf_names to Lists of Search_Results_Group objects
      byways_named = {}

      # Dict of gf_results to Lists of gp_results
      byways_same_name_and_ts = {}

      # Go through the byways and group the results. Retain the existing sort
      # order.
      for result in byway_results:
         g.assurt(len(result.result_gfs) == 1)
         cur_gf_res = result.result_gfs[0]
         # See if we've seen this byway before.
         if result.gf_name in byways_named:
            # A list of Search_Result_Geofeature objects.
            byways_same_name_diff_ts = byways_named[result.gf_name]
         else:
            byways_same_name_diff_ts = list()
            byways_named[result.gf_name] = byways_same_name_diff_ts
         # For each collection of byways with the same name, see if the search
         # criteria also matches.
         matched = False
         for gf_res in byways_same_name_diff_ts:
            g.assurt(not cur_gf_res is gf_res)
            if cur_gf_res.equal_ts(gf_res):
               # A similar byway matched on the same query types. Add the node
               # ids to the lookups and we'll see if these byways are connected
               # later.
               byways_same_name_and_ts[gf_res].append(cur_gf_res.result_group)
               matched = True
               break
         if not matched:
            # This is the first byway with this name, or this byway doesn't
            # have the same search criteria as the other byway matches with the
            # same name. Add to the list of search_result_groups.
            byways_same_name_diff_ts.append(cur_gf_res)
            byways_same_name_and_ts[cur_gf_res] = []
            # NOTE: Adding object to its own list
            byways_same_name_and_ts[cur_gf_res].append(cur_gf_res.result_group)

      # For each collection of byways with the same name and the same search
      # criteria, group the byways by connectedness.
      for similar_gp_results in byways_same_name_and_ts.itervalues():
         # This fcn. takes up to O(n*(n-1)), where n is the number of matches 
         # with the same name and meeting the same search criteria. Here are 
         # some illustrations on why this takes so long:
         # Consider these byways, connected in order: 1-2-3-4-5-6-7-8-9-0.
         # Imagine a list with results 1,5,3,2: On the first pass, 1, 5, and
         # 3 are placed in their own groups, and then 2 is placed in with 1,
         # giving 1-2,5,3 (three groups).  But we want to loop again, so we get
         # 1-2-3,5 (two groups). Another e.g.: Consider results 8,2,6,4,3,5,7.
         # First pass: 8,2,6,4-3-5,7; 2nd: 8,2,6-4-3-5-7; 3rd: 8-6-4-3-5-7,2.
         # Here's an example where two groups of two results are grouped:
         # Results: 1,2,4,3,7,6,8; 1st loop: 1-2,4-3,7-6-8; 2nd: 1-2-4-3,7-6-8.
         loop_no = 0
         regrouped = True
         cur_gp_list = similar_gp_results
         while regrouped:
            regrouped = False
            next_gp_list = []
            for similar in cur_gp_list:
               g.assurt((loop_no > 0) or (len(similar.result_gfs) == 1))
               regrouped = False
               for grp_result in next_gp_list:
                  g.assurt(not similar is grp_result)
                  # SPEED: Is intersection costly? We just need to know len > 0
                  if (similar.node_ids.intersection(grp_result.node_ids)):
                     # This gf result shares a node with the other group.
                     grp_result.add_result_gp(similar)
                     regrouped = True
                     break
               if not regrouped:
                  # This group is the first group examined or it doesn't share
                  # node ids with any of the groups we've compared it to so far
                  next_gp_list.append(similar)
            cur_gp_list = next_gp_list
            loop_no += 1
            g.assurt(loop_no <= len(similar_gp_results))

         # We're done regrouping, so This Is Connectedness.
         if cur_gp_list:
            results.extend(cur_gp_list)

      return results

   # ***

# ***

