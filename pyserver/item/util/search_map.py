# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# DEVs: For help testing this module, see:
#
#         scripts/dev/testing/search_map_test.sh
#
#       it's got a bunch of ccp.py commands you can run that should
#       hopefully cover all of the code paths in this module.

import copy
import difflib
import itertools
import Levenshtein
import math
import re
import time
import uuid

import conf
import g

from grax.item_manager import Item_Manager
from gwis.exception.gwis_warning import GWIS_Warning
from gwis.query_overlord import Query_Overlord
from item import geofeature
from item import item_user_access
from item import item_user_watching
from item import item_versioned
from item import link_value
from item.attc import annotation
from item.attc import attribute
from item.attc import tag
from item.feat import byway
from item.feat import region
from item.feat import waypoint
from item.link import link_tag
from item.util import address
from item.util import item_factory
from item.util import item_query_builder
from item.util import revision
from item.util import search_full_text
from item.util import search_result
from item.util.search_result import Search_Result_Group
from item.util.geocode import Geocode
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import misc
from util_.streetaddress import addressconf
from util_.streetaddress import ccp_stop_words
from util_.streetaddress import streetaddress
from util_.streetaddress.addressconf import States
#from util_.streetaddress.ccp_stop_words import Addy_Stop_Words
from util_.streetaddress.ccp_stop_words import U_S_State_Nicknames
from util_.streetaddress.ccp_stop_words import City_Names_MN

log = g.log.getLogger('search_map')

# MAYBE: The algorithm herein is a bunch of complicated SQL statements UNIONed
#        together. This lets us use pagination, except that we never paginate:
#        the client always gets all results. Also, we sort all of the rows in
#        Python, and not in SQL. So we could simplify the SQL here, but the
#        rest of the code would probably be just as complicated...


# TEST: When we check street_addy['postal_code'], we don't change the geocode
#        query, which should be fine, if the geocoder does its job... but
#        test, e.g., search '55401' -- it should geocode and also find
#        minneapolis region (we could also maybe find the neighborhood region,
#        too...).

# ***

class Search_Map(object):

   # [lb] notes that some zips are three or four digits, but conventionally
   #      people precede those with one or two zeroes.
   #ends_with_zip_code_re = re.compile(r'(.*)\b(\d{3,5})(?:-(\d{4}))?\W*$')
   ends_with_zip_code_re = re.compile(r'(.*)\b(\d{5})(?:-(\d{4}))?\W*$')

   # [lb] is not quite sure how streetaddress does it, but it matches
   # 'west virginia' and not just 'virginia', i.e., it consumes more words
   # rather than fewer words in the state pattern (after consuming the street
   # number, street name, and city), but the regex doesn't deliberately order
   # its keys and values in the alternation operator (e.g.,
   # r'(IA|virginia|west\\svirginia' still matches 'west virginia', and not
   # just 'ia'). Here, we use the ? operator to make .* less greedy, but I
   # don't see that in the streetaddress/addressconf regex... and I always
   # like to explain my regex patterns, otherwise I find myself re-reading
   # the Python regex documentation anytime I want to edit regex code....
   #
   # Start by combining all the state nicknames and fullnames into a list.
   state_names_and_abbrevs = (  States.STATE_CODES.values()
                              + States.STATE_CODES.keys())
   #
   # Sort the state abbreviation and names by their length, so that longer
   # names come first, otherwise, e.g., trying to match 'west virginia'
   # might just hit on 'virginia', or even 'IA'.
   state_names_and_abbrevs.sort(key=len, reverse=True)
   #
   # We use the "alternation" operator to OR all the state names and
   # abbreviations together (using the pipe symbol, or vertical bar;
   # whatever you want to call it, in regex lingo, it's the alternation
   # operator). But we don't want to leave spaces in multi-word state names,
   # so swap them for the space escape.
   state_names_and_abbrevs = [
      v.replace(' ','\\s') for v in state_names_and_abbrevs]
   #
   # Make the alternation command.
   state_name_alternation = '|'.join(state_names_and_abbrevs)
   #
   # When we use this pattern, we'll have maybe removed a ZIP code from the end
   # of the query string, and we look for the state name or abbreviation at the
   # end of the query string. So the regex ends with '$', but we use another
   # alternation so that nothing or anything can precede the state name, using
   # (^|.*?\W), where ^ matches the beginning of the string, or .*?\W matches
   # anything up to a word boundary, and the ? after the .* means the match is
   # less greedy (e.g., so querying 'west virginia' doesn't just hit
   # 'virginia': i.e., not only do we have to order the alternation terms, we
   # also have to tell the .* not to be greedy).
   ends_with_state_real_re = re.compile(
      r'(^|.*?\W)\b(%s)$' % (state_name_alternation,), re.IGNORECASE)
   # ends_with_state_real_re.match('city west virginia').group(1)

   state_synonyms = [v.replace(' ','\\s')
                      for v in U_S_State_Nicknames.by_synonym.keys()]
   state_syns_alternation = '|'.join(state_synonyms)
   ends_with_state_syns_re = re.compile(
      r'(^|.*?\W)\b(%s)$' % (state_syns_alternation,), re.IGNORECASE)

   # This is just a dev switch.
   debug_trace_sql = False
   #debug_trace_sql = True

   # ***

   __slots__ = (

      'qb',
      'db',
      'main_query',
      'main_query_word_cnt',
      'centerx',
      'centery',

      'search_for',
      'search_for_addresses',
      'search_in_attcs',
      'search_in_names',
      'search_for_except_waypoint',

      'thurrito',
      'thurrito_sql_annots',
      'thurrito_sql_tags',
      'thurrito_sql_annots_lvals',
      'thurrito_sql_tags_lvals',

      'query_include',
      # NOTE: negated queries are sent to client to be culled. This provides
      # better responsive on the clientside.
      'query_exclude',

      'ftq',

      'better_addy',
      'better_addr',
      'clean_query', # user's cleaned up query; lowercase 
      'is_citystate_query', # True if user searching, e.g., 'mpls, mn',
                            # i.e., we can be more confident about match.
      'full_street',
      'full_street2',

      'all_results',
      'all_results_sids',
      )

   # multiplier for query terms based on number of properties searched
   # (currently names, tags, and comments)
   query_multiplier = 3

   # *** Constructor

   def __init__(self, qb):

      self.qb = qb

      # If the qb.branch_hier is more than just one item, it'll set:
      #  self.qb.confirm_leafiness = True
      # because stacked branching is being used.

      self.db = self.qb.db

      self.main_query = self.qb.filters.filter_by_text_smart
      self.main_query_word_cnt = None
      # FIXME: Leave filter_by_text_smart set? It adds an @@ to the
      #        WHERE, which conflicts at least with the tag lookup.
      # (gia.tsvect_name @@ plainto_tsquery('english', '...'))
      self.qb.filters.filter_by_text_smart = ''

      self.centerx = self.qb.filters.centerx
      self.centery = self.qb.filters.centery
      if (not self.centerx) and (not self.centery):
         center_sql = (
            """
            SELECT ST_X(centroid), ST_Y(centroid)
            FROM (SELECT ST_Centroid(coverage_area) AS centroid FROM branch
                  WHERE stack_id = %d ORDER BY version DESC LIMIT 1) AS foo
            """ % (self.qb.branch_hier[0][0],))
         rows = self.qb.db.sql(center_sql)
         self.centerx = float(rows[0]['st_x'])
         self.centery = float(rows[0]['st_y'])

      self.thurrito = item_query_builder.Sql_Clauses()
      self.thurrito_sql_annots = None
      self.thurrito_sql_tags = None
      self.thurrito_sql_annots_lvals = None
      self.thurrito_sql_tags_lvals = None

      self.query_include = None
      self.query_exclude = None

      self.ftq = None

      self.better_addy = ''
      self.better_addr = None
      self.clean_query = ''
      self.is_citystate_query = False
      self.full_street = ''
      self.full_street2 = ''

      self.all_results = []
      self.all_results_sids = set()

      # NOTE: Restricting what to search for is possible if you remove
      #       elements from search_for, but flashclient gets all of the
      #       results and filters them locally.
      #
      #       Also, there's no way to say not to search for addresses,
      #       though it probably be very quite easy.
      #         Item_Type.ADDRESS
      #

      self.search_for = [
         Item_Type.BYWAY,
         Item_Type.REGION,
         Item_Type.WAYPOINT,
         # BUG nnnn: Enable editing and searching Terrain.
         #Item_Type.TERRAIN,
         ]
      self.search_for_addresses = True
      self.search_for_except_waypoint = (
         [x for x in self.search_for if x != Item_Type.WAYPOINT])

      self.search_in_attcs = [
         Item_Type.TAG,
         Item_Type.ANNOTATION,
         # BUG nnnn: Search for, e.g., /byway/speed_limit=30
         #   Item_Type.ATTRIBUTE,
         #   see: link_attribute.sql_apply_query_filters
         #        we can just set, e.g., qb.filters.filter_by_value_integer
         # Skipping, because the discussion panel has its own search box:
         #   Item_Type.POST,
         #   Item_Type.THREAD,
         # Skipping, since the Item_Type id will end up in the SQL, but
         # link_values don't link that abstract type.
         #   Item_Type.ITEM_NAME
         ]
      self.search_in_names = True

   # *** The search function

   #
   def search(self):

      # BUG 1828 Something about Pagination not being supported.
      #
      #          It's true, we do not paginate the Very Long SQL search
      #          query. If the caller wants, we'll limit what we return, so we
      #          can at least cut down on network bandwidth if we wanted. But
      #          flashclient supports a rich filtering system, so instead we
      #          usually find and return everything we can to the client.
      #
      #          At least for the route finder geocode request, this fcn.
      #          will be quick: we can short-circuit return if we find an
      #          exact Cyclopath region or waypoint name match, or if the
      #          external geocoder returns an address.
      #
      #          But for the search command, this fcn. might take a few, or
      #          twenty, seconds, since we'll do an in-depth search of the
      #          database (the thurrito SQL is something like 1,000 lines
      #          long). But this isn't a bad thing: this is a GIS editing tool
      #          for power users, so there's no reason to expect us to be super
      #          fast: if it takes a few seconds to fulfill a user's search
      #          query, so be it!
      #
      # BUG nnnn: We could at least split the external geocode request and
      #           the internal Cyclopath search requests from flashclient.
      #           Think of each of the search filters: matches name, matches
      #           note, matches region, etc. Each of these could be a separate
      #           request, and then flashclient would be able to display
      #           results as they come in, improving the user experience!
      #
      # Currently, don't do pagination until after we've searched everything.
      # Also, flashclient doesn't set pagin limits, so pagin_count and
      # pagin_offset will probably both be 0.
      pagin_count = self.qb.filters.pagin_count
      pagin_offset = self.qb.filters.pagin_offset
      self.qb.filters.pagin_count = 0
      self.qb.filters.pagin_offset = 0

      self.process_query()

      if not self.query_include:
         log.debug('search: vague query: %s' % (self.main_query,))
         raise GWIS_Warning('Please be more specific or add more words.',
                            logger=log.debug)

      # BUG nnnn/MAYBE: See if the search query is a stealth secret / GUID
      #                 (usually people have a well-formed URL... but it's
      #                 awkward to refresh the browser to try to load a
      #                 deep-link, since simply pasting the URL and pressing
      #                 Enter doesn't work, because the browser doesn't
      #                 see past the '#', so it thinks the URL is the same (at
      #                 least Firefox)).
      #  if not self.all_results:
      #     self.search_stealth_secret_guid()

      self.search_exact_stack_id()

      # See if the search query is an encoded point, e.g., "P(1,2)".
      self.search_encoded_point()

      self.broader_search()

      results = self.all_results

      # Sort results by distance to query center.
      results.sort(self.sort_compare_priority)

      if pagin_count:
         log.info('search: artifical pagination: count: %s / offset %s'
                  % (pagin_count, pagin_offset,))
         beg_i = pagin_count * pagin_offset
         fin_i = beg_i + pagin_count
         results = results[beg_i:fin_i]

      self.qb.filters.pagin_count = pagin_count
      self.qb.filters.pagin_offset = pagin_offset

      # We return the "clean query" to the client, which uses it to refresh
      # the search box (e.g., so "123 Main St, Mpls, Minn" gets converted
      # to "123 main st, mpls, mn").
      self.qb.filters.filter_by_text_smart = self.clean_query

      return results

   #
   def broader_search(self):

      # Try to find exactly-named Cyclopath items.
      self.search_exact_names()

      # Perform an external geocode request.
      if self.search_for_addresses:
         self.search_addresses()

      # Do a broad search of the Cyclopath database.
      # Look for geofeature by name and by linked attachments.
      self.search_geofeatures_and_links()

   # *** The query parser and its helpers

   #
   def process_query(self):

      # This fcn. splits query into a list of terms to include and a list of
      # terms to exclude from the search. An exact term or a term of two of
      # more words should be "surrounded by quotes". To exclude a term, precede
      # it with a -minus. Punctuation besides underscores is converted to
      # whitespace, except punctuation "w/in quotes".

      # See Bug 1925 -- Replace regex with another solution. Perhaps Python's
      # Standard Library's shlex? I [lb] think lex could help with stop words,
      # lex won't be anymore programmer-friendly than regex. And since full
      # text search handles stop words, I think we can close this bug....

      if not self.search_for:
         raise GWIS_Warning(
            'The search query does not indicate what to search for.')

      if not self.search_in_attcs:
         raise GWIS_Warning(
            'The search query does not indicate what to search in.')

      # Make a collection of search terms to be ORed. Each search term will be
      # one or more words; if multiple, the sequence of words must exactly
      # match. This is so, e.g., if someone searches 123 Main St N, Some City,
      # we'll geocode the query, but we'll also search "main st n" and "some
      # city", and probably "main", but not "st" or "n" (the latter two being
      # stop words).

      ccp_queries = set()

      # Be really strict and convert most non-char-nums to spaces.
      scrubbed_query = re.sub(r'\s+', ' ', self.main_query)
      # MAYBE: Do not remove periods but use them to help detect abbreviations,
      #        like street type.
      # Also keep intersection delimiters, '@' and '&'.
      # PROBABLY: We should drop apostrophes, right?
      scrubbed_query = scrubbed_query.replace("'", '')

      # SYNC_ME: SEARCH: Addy regex (just this function).
      # BUG nnnn: i18n: This regex obviously doesn't work with international
      #                 addresses...
      # 2014.08.19: There's a problem with colons. We were going to use colons
      # to refine searches, e.g., "tag:high volume", but for now we scrub
      # colons, otherwise all_name_terms in search_feat_by_name_base ends
      # up being empty because self.ftq.include.tsv['name'] is None, e.g.,
      # don't omit ':' here and try searching for 'big:' (as opposed to 'big').
      #scrubbed_query = re.sub(r'[^-:_,a-zA-Z0-9"\'@&]', ' ', scrubbed_query)
      scrubbed_query = re.sub(r'[^-_,a-zA-Z0-9"\'@&]', ' ', scrubbed_query)
      scrubbed_query = re.sub(r'&', ' & ', scrubbed_query)
      # We're about to test that each term has at least one letter or number.
      # But there might be spaces between words and commas, so remove said
      # possible whitespace.
      scrubbed_query = re.sub(r'\s+,', ',', scrubbed_query)
      # Send to lowercase and split on whitespace (removing all whitespace).
      scrubbed_query = scrubbed_query.lower()
      query_words = scrubbed_query.split()
      # Check that each term has a letter or number (isn't just punctuation).
      clean_words = []
      for some_word in query_words:
         # SYNC_ME: SEARCH: Addy regex (just this function).
         if re.search(r'[a-zA-Z0-9@&]', some_word):
            clean_words.append(some_word)
      # Make the clean query, e.g., "123 main st, mpls, mn". Strip off leading
      # and trailing whitespace and commas.
      self.clean_query = ' '.join(clean_words).strip(', ')

      # Different geocoders recognize different delimiters for intersections,
      # e.g., Microsoft Bing uses 'X and Y' and AOL MapQuest uses 'X @ Y'.
      # We'll let the geocode implementation convert '&', '@', and 'and' to
      # the appropriate delimiter that the external geocoder recognizes.
      symbol_ampersand_cnt = self.clean_query.count('&')
      symbol_heliko_cnt = self.clean_query.count('@')
      literal_and_cnt = self.clean_query.count(' and ')
      symbol_no_one_uses_X_cnt = self.clean_query.count(' X ')
      # We're still figuring this out: would a user use '&', '@', or ' and '
      # for any other reason than seeking an intersection, or would they use
      # more than one of the delimiter? Let's warn to find out.
      n_intersection_delimiters = (symbol_ampersand_cnt
                                   + symbol_heliko_cnt
                                   + literal_and_cnt
                                   + symbol_no_one_uses_X_cnt)
      if n_intersection_delimiters > 1:
         log.warning('process_query: multiple intersection delimiters: %d / %s'
                     % (n_intersection_delimiters, self.main_query,))

      # For checking if this is an address, remove the double-quotes.
      #
      # NOTE: This regex is like the earlier one, except we've added the
      #       space char and removed the double quote.
      #
      # WRONG: If the space comes first, then the double quotes are not
      #        removed.
      #  dequoted_query = re.sub(r'[^ -:_,a-zA-Z0-9\']', '', self.clean_query)
      #
      # SYNC_ME: SEARCH: Addy regex (just this function).
      dequoted_query = re.sub(r'[^-:_,a-zA-Z0-9 \'@&]', '', self.clean_query)

      # Check for special cases, starting with the question, is the user's
      # query just a bunch of stop words?

      # ccpv3_demo=# select * from _by where nom @@ 'the';
      # NOTICE:  text-search query contains only stop words or doesn't contain
      #            lexemes, ignored
      # [repeat ad nauseum... ^C]
      # ERROR:  canceling statement due to user request

      # ccpv3_demo=# select 'the'::tsquery @@ 'the brown fox'::tsvector;
      # ----------
      #  t
      #
      # ccpv3_demo=# select to_tsvector('the brown fox') @@ to_tsquery('the');
      # NOTICE:  text-search query contains only stop words or doesn't contain
      #           lexemes, ignored
      # ----------
      #  f

      # ccpv3_demo=# select to_tsquery('the');
      # NOTICE:  text-search query contains only stop words or doesn't contain
      #           lexemes, ignored
      #  to_tsquery
      # ------------
      #
      # ccpv3_demo=# select to_tsquery('the&brown&fox');
      #    to_tsquery
      # -----------------
      #  'brown' & 'fox'

      # >>> self.qb.db.sql("SELECT to_tsquery('the')")
      # [{'to_tsquery': ''}]
      # >>> self.qb.db.sql("SELECT to_tsquery('the|home|town|hero|won')")
      # [{'to_tsquery': "( ( 'home' | 'town' ) | 'hero' ) | 'won'"}]

      # Special Case: Check if query is all stop words.
      clean_tsquery = [x for x in clean_words if x not in ('&', '@',)]
      sql_tsquery = ("SELECT to_tsquery('english', '%s')"
                     % ('|'.join(clean_tsquery),))
      rows = self.qb.db.sql(sql_tsquery)
      g.assurt(len(rows) == 1)
      if not rows[0]['to_tsquery']:
         # NOTE: This doesn't consider stop words from, e.g.,
         #        ccp_stop_words.Addy_Stop_Words__Byway.lookup
         log.info('process_query: only stop words: %s' % (self.main_query,))
         # Stop processing the request now.
         raise GWIS_Warning(
            'Too vague: Please try using more specific search terms.')

      # This code is weird: it parses the query words for ZIP codes. But when
      # would a ZIP code ever not be the last word in the query? Otherwise,
      # we'd potentially misinterpret street numbers as ZIP codes.
      # # Special Case: Check if the query contains ZIP code(s).
      # # BUG nnnn: i18n: Iternationalization. This is U.S.-specific:
      # zipcode_cities = []
      # zipcode_states = []
      # for some_word in clean_words:
      #    # NOTE: Ignoring negation operator, e.g., "-55401". We could, like,
      #    #       exclude Minneapolis from search results, or exclude the
      #    #       55401 bbox, but there's not really a good argument for such
      #    #       a feature.
      #    if re.search(r'^\d{5}$', some_word):
      #       zip_code_sql = (
      #          "SELECT city, state FROM public.zipcodes WHERE zipcode = %d"
      #          % (int(some_word),))
      #       rows = self.qb.db.sql(zip_code_sql)
      #       if len(rows) == 1:
      #          zipcode_city = rows[0]['city'].lower()
      #          zipcode_state = rows[0]['state'].upper()
      #          zipcode_cities.append(zipcode_city)
      #          zipcode_states.append(zipcode_state)
      #          ccp_queries.add(zipcode_city)
      #          # Don't add the state, which is a two-letter state abbrev.
      #          # We'll resolve the state later to the lowercase fullname.
      #          #  No: ccp_queries.add(zipcode_state)
      #       else:
      #          log.warning('Unexpected zipcode lookup: %s / %s / %s'
      #                      % (some_word, rows, self.main_query,))
      # if zipcode_cities:
      #    match_obj = re.search(Search_Map.ends_with_zip_code_re,
      #                          dequoted_query)
      #    try:
      #       sans_zipcode = match_obj.group(1).strip(' ,')
      #       found_zipcode = match_obj.group(2)
      #    except AttributeError:
      #       # This happens if there's a number that looks like a ZIP code
      #       # that's really just the address, like 55401 Main St, Somewhere.
      #       sans_zipcode = dequoted_query
      #       found_zipcode = None
      # else:
      #    sans_zipcode = dequoted_query
      #    found_zipcode = None

      zipcode_city = None
      zipcode_state = None
      # >>> re.sub(r'^(.*)\s\d{5}$', r'\1', 'mpls mn 55401')
      #  'mpls mn'
      # >>> re.search(r'^(.*)[,\s]*(\d{5})$', 'mpls mn 55401')
      #  group(1) ==> 'mpls mn' / group(2) ==> '55401'
      # >>> re.search(r'^(.*)[,\s]*(\d{5})$', '55401').group(1) # ''
      # >>> re.search(r'^(.*)[,\s]*(\d{5})$', '55401').group(2) # '55401'
      # >>> re.search(r'^(.*)[,\s]*(\d{5})$', '123 main, mpls, mn, 55401')
      #  group(1) ==> '123 main, mpls, mn, ' / group(2) ==> '55401'
      match_obj = re.search(Search_Map.ends_with_zip_code_re, dequoted_query)
      try:
         sans_zipcode = match_obj.group(1).strip(' ,')
         found_zipcode = match_obj.group(2)
      except AttributeError:
         sans_zipcode = dequoted_query
         found_zipcode = None
      if found_zipcode:
         # Cast to int, which will remove leading zeroes, so that three- and
         # four-digit ZIP codes match (we store ints in the database, but
         # when written as text, ZIP codes are always five digits long).
         zip_code_sql = (
            "SELECT city, state FROM public.zipcodes WHERE zipcode = %d"
            % (int(found_zipcode),))
         rows = self.qb.db.sql(zip_code_sql)
         if len(rows) == 1:
            zipcode_city = rows[0]['city'].lower()
            zipcode_state = rows[0]['state'].upper()
            ccp_queries.add(zipcode_city)
            # Don't add the state, which is a two-letter state abbreviation.
            # We'll resolve the state later to the lowercase fullname.
            #  No: ccp_queries.add(zipcode_state)
         else:
            # 2014.09.09: Someone searched a full addres with a zip code
            #             without an entry in the zip code table:
            #              2650 Wells Fargo Way, Minneapolis, MN 55467
            #      Weird: Searching 55467 in other maps just zooms in
            #             on downtown (55401) but at usps.com if you
            #             enter the address as above, it confirms the
            #             zip code and include the +4: 55467-2694.
            #             So I guess our zip code table is incomplete,
            #             or maybe wells fargo has a very special zip.
            log.info('ZIP Code (TM) not found: %s / %s / %s'
                     % (found_zipcode, rows, self.main_query,))

      # Check the state.
      #
      # At this point, we're checking if the query is just a normal text query
      # (e.g., "coffee shop") or an address query (e.g., "123 main st st paul")
      # Since Cyclopath is generally state-specific, we can 'guess' the state
      # in address queries (e.g., "hennepin ave mpls").
      #
      # BUG nnnn: flashclient: on a route search, like 'a to b',
      #           submit route request. This search module does not
      #           expect to see route requests.

      sans_state = None
      found_state = None

      if sans_zipcode:
         # We can just check the last part of the query to see if it's a
         # state, but if we ignore commas, we could make a mistake: e.g.,
         # searching '123 main st, davenport west, virginia' shouldn't hit
         # on 'west virginia' as the state (not that 'davenport west' is an
         # actual city). So if there are commas, use them! Otherwise, just
         # do a greedy guess. Also, the user might delimit some address parts
         # but not all of them, e.g., "123 main st, mpls mn". But at least
         # with the last example, 'mpls mn' would still hit on 'mn' w/
         # the state pattern.
         sans_state = sans_zipcode
         state_name_or_syn = None
         try:
            prefixes, state_maybe = sans_zipcode.split(',', 2)
            # If we're here, we split on a comma. See if the tail is a state.
            mobj = Search_Map.ends_with_state_real_re.match(state_maybe)
            if mobj is not None:
               # Golden!
               sans_state = ('%s %s' % (prefixes, mobj.group(1).strip(', '),))
               state_name_or_syn = mobj.group(2)
         except ValueError:
            # No comma on which to split.
            mobj = Search_Map.ends_with_state_real_re.match(sans_zipcode)
            if mobj is not None:
               # The query ends with a valid state name or abbreviation.
               sans_state = mobj.group(1).strip(', ')
               state_name_or_syn = mobj.group(2)
         if state_name_or_syn:
            # Add the long name or two-letter abbreviation.
            # MAYBE: Two-letter state names should be considered stop words?
            try:
               # If the state is a two-letter abbrev., get the long name.
               found_state = addressconf.States.STATE_NAMES[
                                    state_name_or_syn.upper()]
               # MEH: It doesn't seem to make sense to search, e.g., 'MN'.
               #ccp_queries.add(state_name_or_syn)
            except KeyError:
               pass # Already formal state name... or not a state name/abbrev.
            ccp_queries.add(found_state)
         # If we didn't find a two-letter state abbreviation or a formal state
         # name, try for a state synonym.
         if not found_state:
            # See if the query ends with a state name synonym; the
            # streetaddress library only uses real state names and USPS
            # two-letter abbreviations, but Cyclopath can be customized to
            # accept other state name synonyms.
            try:
               prefixes, state_maybe = sans_zipcode.rsplit(',', 2)
               mobj = Search_Map.ends_with_state_syns_re.match(state_maybe)
               if mobj is not None:
                  sans_state = ('%s %s' % (prefixes, mobj.group(1),))
                  found_state = mobj.group(2)
            except ValueError:
               # No comma on which to split.
               mobj = Search_Map.ends_with_state_syns_re.match(sans_zipcode)
               if mobj is not None:
                  # The query ends with a valid state name or abbreviation.
                  sans_state = mobj.group(1)
                  found_state = mobj.group(2)
            if found_state:
               #ccp_queries.add(found_state) # The synonym, e.g., 'Minn', 'Wis'
               found_state = U_S_State_Nicknames.by_synonym[found_state]
               ccp_queries.add(found_state)
         sans_state = re.sub(r'\s+', ' ', sans_state).strip(', ')
      if not found_state:
         if zipcode_state:
            found_state = zipcode_state

      # Check the city.

      sans_city = None
      found_city = None

      if sans_state:

         # Now break out the last n words of the string and look for a city
         # match.
         #
         # We could do like we did for states: make a regex expression of the
         # 50 to 1000-some cities in each state, and using the state we just
         # deduced, we could check against a state's list of cities.
         #
         # (MN has 854 cities; RI has around 50; California has over 1,000.
         #  http://wiki.answers.com/Q/How_many_cities_are_in_each_state)
         #
         # But [lb] thinks maybe doing dictionary lookups will be quicker:
         #
         # City names might be multiple words, and some contain punctuation
         # (though not in Minnesota... [lb] is thinking Stratford-upon-Avon,
         # Warwickshire). So it's not as simple as taking the last word in
         # what's left of our query string (sans_state) and searching for the
         # city.
         #  SELECT municipal_name FROM state_cities
         #     WHERE municipal_name LIKE '%park';
         #  Returns: brooklyn park, brook park, lake park, saint louis park,
         #           etc.
         #
         # But if we know the maximum number of words in any city name in
         # minneapolis, we can pick words off the tail of the query and look
         # for matches.

         # First trying splitting on a comma.
         try:
            prefixes, city_maybe = sans_state.rsplit(',', 2)
         except ValueError:
            # No comma on which to split.
            prefixes, city_maybe = ('', sans_state,)

         # In city names, at least in MN, all 'st.'s are spelled out 'saint'.
         city_maybe_sainted = re.sub(
            #r'(^ste?\.?\s)|(\sste?\.?\s)', ' saint ', city_maybe).strip()
            # We can use word \boundary on the beginning but not the end, since
            # 'st.' splits between the 'st' and the period. So for the ending,
            # use the ?= lookahead zero-length assertion: after 'st', 'ste',
            # 'st.', or 'ste.', should come a non-word or end-of-string.
            # (Also note that we culled periods already....)
            r'\bste?\.?(?=(\W|$))', 'saint', city_maybe)

         # Split the query into words that we can count and reassemble.
         city_words = city_maybe_sainted.split()
         # Loop over the number of words, e.g., 4, 3, 2, 1.
         for nwords in xrange(City_Names_MN.n_words_in_longest_name, 0, -1):
            # See if we have enough query words to check for a city name.
            if len(city_words) >= nwords:
               # Rejoin the tail into a single string.
               try_name = ' '.join(city_words[-nwords:])
               # See if we can find the string in the list of city names.
               if try_name in City_Names_MN.city_names:
                  # Ya betcha!
                  # 2014.06.21: Oh, boy, corner case!: "Gateway Fountain"
                  # (downtown Mpls. waypoint) flows here because there's
                  # a Fountain, Minnesota!
                  found_city = try_name
               else:
                  # Check if it's a nickname, like 'mpls'.
                  try:
                     found_city = City_Names_MN.by_nick_name[try_name]
                     ccp_queries.add(try_name) # The nickname.
                  except KeyError:
                     pass # Not a real city name or nickname.
               if found_city:
                  ccp_queries.add(found_city) # The full city name.
                  # Don't use city_words, since we converted 'st' to 'saint'.
                  city_words = city_maybe.split()
                  sans_city = (
                     '%s %s' % (prefixes, ' '.join(city_words[:-nwords]),))
                  sans_city = re.sub(r'\s+', ' ', sans_city).strip(', ')
                  ccp_queries.add(sans_city)
                  self.is_citystate_query = bool(found_state)
                  # If we found a city but not the state, make an assumption.
                  break
      if not found_city:
         if zipcode_city:
            found_city = zipcode_city
         # User reported problem finding street + zip, e.g., 123 Main St 12345.
         # Test, e.g.: ./ccp.py -s -q "17 s 1st st 55401" (downtown mpls)
         # This line of code was missing:
         sans_city = sans_state
      if (not found_state) and found_city:
         # BUG nnnn: Multi-state support. For now, assuming one state.
         # What? Bing doesn't recognize "some_addy, minneapolis, minnesota",
         #       but it recognizes "some_addy, minneapolis, mn".
         # FIXME/EXPLAIN: What about MapQuest, et al.?
         #found_state = conf.admin_district_primary[0].lower()
         found_state = conf.admin_district_primary[1].lower()
         #ccp_queries.add(found_state)

      # Now we've got: sans_city, found_city, found_state, and found_zipcode.

      # See if the request looks like an address. We can fix abbreviations
      # and do a more intelligent search by adding the street name (e.g., when
      # searching "123 washington ave n, mpls", we'll search "washington",
      # "mpls", "minneapolis", and "washington ave n", and we'll geocode the
      # address, too.

      if found_city:

         self.better_addr = address.Address()

         self.better_addy = sans_city if sans_city else ''
         if found_city:
            self.better_addy += ', ' if self.better_addy else ''
            self.better_addy += found_city
            self.better_addr.city = found_city
         if found_state:
            # 2014.06.16: Bing doesn't recognize full state name; just abbrev.
            try:
               # If the state is a two-letter abbrev., get the long name.
               found_state = addressconf.States.STATE_CODES[found_state]
            except KeyError:
               pass # Already the (postally) abbreviated state name.
            self.better_addy += ', ' if self.better_addy else ''
            self.better_addy += found_state
            self.better_addr.state = found_state
         if found_zipcode:
            self.better_addy += ', ' if self.better_addy else ''
            self.better_addy += found_zipcode
            self.better_addr.zip = found_zipcode

         # We've done our best to prepare the address query. Now see if it
         # parses, and add the long street name to the query list. The parse
         # fcn. only works if the query starts with a house number.
         street_addy = streetaddress.parse(self.better_addy)
         if street_addy is not None:
            if ((street_addy['street'])
                and (street_addy['street_type']
                  or street_addy['prefix']
                  or street_addy['suffix'])):
               # Make the full street name, e.g., "S 1st", or "Dupont Ave",
               # or "W 38th St".
               self.full_street = street_addy['prefix'] or ''
               self.full_street += ' ' if self.full_street else ''
               self.full_street += street_addy['street']
               if street_addy['street_type']:
                  self.full_street += ' ' if self.full_street else ''
                  self.full_street += street_addy['street_type']
               if street_addy['suffix']:
                  self.full_street += ' ' if self.full_street else ''
                  self.full_street += street_addy['suffix']
               self.full_street = self.full_street.lower()
               ccp_queries.add(self.full_street)
               self.better_addr.street = self.full_street
            # See if the address parsed to an intersection.
            if ((street_addy['street2'])
                and (street_addy['street_type2']
                  or street_addy['prefix2']
                  or street_addy['suffix2'])):
               # Make the full street name, e.g., "S 1st", or "Dupont Ave",
               # or "W 38th St".
               self.full_street2 = street_addy['prefix2'] or ''
               self.full_street2 += ' ' if self.full_street2 else ''
               self.full_street2 += street_addy['street2']
               if street_addy['street_type2']:
                  self.full_street2 += ' ' if self.full_street2 else ''
                  self.full_street2 += street_addy['street_type2']
               if street_addy['suffix2']:
                  self.full_street2 += ' ' if self.full_street2 else ''
                  self.full_street2 += street_addy['suffix2']
               self.full_street2 = self.full_street2.lower()
               ccp_queries.add(self.full_street2)
               # DNE: self.better_addr.street2 = self.full_street2
            # Skipping:
            #  street_addy['number']            # House number
            #  street_addy['unit_prefix']       # E.g., 'apt'
            #  street_addy['unit']              # E.g., 221B
            #  street_addy['postal_code']       # ZIP Code
            #  street_addy['postal_code_ext']   # The +4 in ZIP+4

         # MEH: Adding the addy components will grab, e.g., the north streets
         # when the user wants the south streets of a road, or something.
         # for single_term in sans_city.split():
         #    if not singl_trm in ccp_stop_words.Addy_Stop_Words__Byway.lookup:
         #       # The word passes our simple test. Check it's 2 or more chars.
         #       if len(singl_trm) > 2:
         #          ccp_queries.add(singl_trm)

         self.query_include = ccp_queries
         self.query_exclude = set()

      else:

         # Not found_city (or zipcode), so not a geocodeable query.
         self.better_addy = ''

         # Since we didn't find any address parts, add each word or sequence of
         # quoted words as an ORable search term.
         #for some_word in clean_words:
         #   ccp_queries.add(some_word)

         # Process quoted, multi-term tokens.

         # NOTE: We can ignore single-quote 'quoted phrases', since Postgres
         #       text search handles this for us.
         #
         #         E.g.,  SELECT name FROM item_versioned
         #                WHERE name @@ to_tsquery('Settler''s');
         #
         #      returns:           name
         #                ----------------------
         #                 Settler's Ridge Pkwy
         #                 Settlers Ridge Pkwy

         # Get a list of "quoted phrases".
         query_terms = re.findall(r'-?\"[^\"]*\"', self.clean_query)
         # BUG nnnn: Allow quoted colonizers, like:
         #            tag:"bike lane" or "tag: bike lane"

         # Separate includes and excludes.

         self.query_include = set()
         self.query_exclude = set()

         # Separate into -"negated phrases" and "included phrases".
         # Also replace punctuation and special characters with whitespace.

         # NOTE: We could strip punctuation from phrases, e.g.,
         #          query_include = [re.sub(r'\W+', r' ', t.strip('"').strip())
         #       but Postgres text search can handle punctuation.
         #
         #         E.g., these two queries produce the same results:
         #                SELECT name FROM item_versioned
         #                   WHERE name @@ to_tsquery('''creek-indian''');
         #                SELECT name FROM item_versioned
         #                   WHERE name @@ to_tsquery('creek & indian');
         #                ==> BATTLE CREEK-INDIAN MOUNDS PARK

         for qt in query_terms:
            stripped_qt = qt.strip('-"').strip()
            # FIXME: The item_versioned class will check stop words, right?
            #if not stripped_qt in ccp_stop_words.Addy_Stop_Words__???.lookup:
            if True:
               # The word passes our simple test.
               if not qt.startswith('-'):
                  self.query_include.add(stripped_qt)
               else:
                  # If we were including the skip-words in the full text search
                  # (e.g., to_tsquery('(find | me) & !(''not me '')')), we'd
                  # use bang operator, but flashclient wants all results so it
                  # can do client-side sorting, so we don't use the bang
                  # operator but instead find matching negated results and tell
                  # the client they matched negatively.
                  self.query_exclude.add(stripped_qt)
            # else: The word is an addressy word.

         # Process single-term tokens.

         # Cull the "quoted phrases" we just extracted from the query string.
         (query, num_subs) = re.subn(r'-?\"[^\"]*\"', ' ', self.clean_query)

         # Unlike phrases, we do want to strip punctation from single-word
         # terms.  We can't just use \W (which is [^a-zA-Z0-9_]) because
         # we need to check for minuses. But we can split on any hypens
         # after checking for a leading minus. Also, leave colons, which are
         # :special.
         query_terms = re.split(r'[^-:_a-zA-Z0-9]+', query.strip())

         for qt in query_terms:
            if not qt.startswith('-'):
               subqts = qt.split('-')
               for subqt in subqts:
                  # FIXME: The item_versioned class will check stop words, eh?
                 #if not subqt in ccp_stop_words.Addy_Stop_Words__Byway.lookup:
                  if True:
                     if len(subqt) > 2:
                        self.query_include.add(subqt)
            else:
               subqts = qt.strip('-').split('-')
               for subqt in subqts:
                  # FIXME: The item_versioned class will check stop words, eh?
                 #if not subqt in ccp_stop_words.Addy_Stop_Words__Byway.lookup:
                  if True:
                     if len(subqt) > 2:
                        self.query_exclude.add(subqt)

         # BUG nnnn: Use common word synonyms. E.g., if someone searches
         # "Guthrie Theater", also try "Guthrie Theatre". Note that both
         # queries find the waypoint, but "Guthrie Theater" only works
         # because the waypoint has a note attached with "theater" in it.

         # ADD_TO_DOCS: We used to make a list of lists, and then we'd have to
         # flatten the inner lists, which one can do thusly:
         #  sublists = [[1], ['a', 'b'], ['yo'],]
         #  list(itertools.chain(*sublists)) # [1, 'a', 'b', 'yo']

      # NOTE: Not culling the query of one-character search terms. For one, not
      #       all 1 character words are stop words (e.g., 'a' is, 'x' isn't).
      #       Also, Postgres full text search removes stop words. See bug 2412.

      # Build the Full_Text_Query object.
      self.ftq_build()

   # ***

   #
   def ftq_build(self):
      # FIXME: Does this fcn. belong in Search_Map, or in Full_Text_Query?
      # Builds the Full_Text_Query object from the two query term arrays.
      self.ftq = search_full_text.Full_Text_Query()
      log.debug('ftq_build: query_include: %s / query_exclude: %s'
                % (self.query_include, self.query_exclude,))

      for term in self.query_include:
         if term:
            self.ftq_build_part(term, self.ftq.include)
      for term in self.query_exclude:
         if term:
            self.ftq_build_part(term, self.ftq.exclude)
      self.ftq.include.assemble(self.qb.db)
      self.ftq.exclude.assemble(self.qb.db)
      log.debug('ftq_build: include: %s / exclude: %s'
                % (self.ftq.include, self.ftq.exclude,))

   #
   def ftq_build_part(self, term, ftqp):
      # The user can specify search qualifiers, like tag:"bike lane",
      # BUG nnnn: Search for, e.g., "note:plowed attr:/byway/one_way<=25"
      # The following qualifiers are supported:
      #   addr: tag: note: post: attr: isect:
      # NOTE: Not restricting to just splitting on just one colon.
      splitted = term.split(':')
      if len(splitted) == 1:
         ftqp.raw['all'].append(term)
         # Always add the term to the other searches. We could do this later,
         # but that seems more complicated than just doing it now.
         for vect_name in search_full_text.Full_Text_Query_Part.ts_vects:
            if vect_name != 'all':
               ftqp.raw[vect_name].append(term)
         # BUG nnnn: Add searching by item type, e.g., "gateway type:byway"
         # FIXME: Default to attribute? or use / prefix, e.g., /speed_limit:20?
      else:
         try:
            # In case user specified additional colons, just split on 'em.
            ftqp.raw[splitted[0]].extend(splitted[1:])
         except KeyError:
            # FIXME: This is probably not a warning, is it?
            log.warning('ftq_build_part: unknown search qualifier: %s'
                        % (splitted[0],))
            ftqp.raw['all'].extend(splitted)
      # FIXME: Add support for attributes and intersections

   # *** The top-level search functions

   # **** MAYBE: Search on GUID or stack ID... or maybe make client do this.

# BUG_FALL_2013/DEFER/Implement in flashclient:
# BUG nnnn: In flashclient, parse the search query first and maybe send an
#           item checkout command before trying search:
#           - If the user is searching a number, do a stack ID checkout
#             and open the item panel
#           - If the user is searching a GUID, do a deeplink
#              (though how would you figure out the item type?)
#              and open the item panel
#
# then again, this code is probably pretty straight-forward, and resolving
# the GUID here means we don't have to worry about item type, since the
# client displays different types of geofeatures in the search results.
# But maybe, if we return just one result to the client, it should pan/zoom
# there and maybe just open its item details panel if it's not an address
# but a real Cyclopath item...

   # BUG nnnn: search_stealth_secret_guid
   #
   def search_stealth_secret_guid(self):

      log.warning('FIXME: not implemented: search_stealth_secret_guid')

      # BUG nnnn: Deep-link via search. So that you don't have to reload
      #           flashclient to use a deep-link url. Maybe also support
      #           searching the deep-link URL, http://...cyclopath...?...UUID..
      #
      try:
         stealth_id = uuid.UUID(self.main_query.strip())

         # Test with:
         # ./ccp.py -U landonb --no-password -s -t byway \
         #        -q '5fc61882-e6b6-4474-b19c-9c46bf9519cc'

         pass # Not implemented

      except ValueError:
         # Not a UUID.
         pass

   # BUG nnnn: search_exact_stack_id
   #
   def search_exact_stack_id(self):

      # See: ends_with_zip_code_re:
      #  re.compile(r'(.*)\b(\d{5})(?:-(\d{4}))?\W*$')
      #
      # If the user queries a five digit number and it matches a Cyclopath
      # item, and it matches a ZIP code... do you return both, or just the
      # ZIP code? Or maybe you fix Cyclopath so all stack IDs are six digits
      # or longer! The other option is to require query to be of the form,
      # "sid:12345" for stack IDs in the ZIP code range, i.e., if a five
      # digit number, assume ZIP code unless query is "sid:12345", otherwise,
      # any query that's all numbers but isn't five digits, like "1234567"
      # can be assumed to be a stack ID.

      # Test with:
      # ./ccp.py -U $USER --no-password -s -t byway -q '1062025'

      try:
         stk_id_maybe = int(self.main_query.strip())
      except ValueError:
         # Not an integer.
         stk_id_maybe = None

      if stk_id_maybe:

         itm_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)

         # Since we don't know the item type, we have to figure it out,
         # otherwise we don't know what kind of Many() to make.
         (itype_id, lhs_type_id, rhs_type_id,
            ) = Item_Manager.item_type_from_stack_id(itm_qb, stk_id_maybe)

         if itype_id:

            log.debug('search_exact_stack_id: itype_id: %s' % (itype_id,))
            g.assurt(Item_Type.is_id_valid(itype_id))
            itype = Item_Type.id_to_str(itype_id)

            log.debug('search_exact_stack_id: itype: %s' % (itype,))
            g.assurt(item_factory.is_item_valid(itype))
            items = item_factory.get_item_module(itype).Many()

            items.search_by_stack_id(stk_id_maybe, itm_qb)

            # Note that items is length 0 or 1, depending on user's access.
            for item in items:
               result = search_result.Search_Result_Group()
               # See similar fcn., store_result_raw.
               # This fcn. sets confidence = 100.
               result.store_result_item(self.qb.db, item)
               self.all_results.append(result)
               self.all_results_sids.add(result.gf_stack_id)
               log.debug('search_exact_stack_id: item: %s' % (item,))
               log.debug('==> %s' % (result.__str__verbose_2__(),))

            # Check confidence of, e.g., 3242020:
            #  Add here:
            #conf.break_here('ccpv3')
            #  Run this: ./ccp.py -s -q "3242020"
            #  Tell pdb: result.__str__verbose__()
            #  Be told: 'byway (1): 3242020 / rnk: 1.0 / pri: 7.0 
            #     / "County Rd 6" / hit: name  / miss: '

   # **** See if this is a coordinate query.

   #
   def search_encoded_point(self):

      # See if the address is an encoded point, e.g. "P(123.45, 678.90)".

      (coord_x, coord_y,) = Geocode.geocode_coordinate(self.clean_query)

      if (coord_x is not None) and (coord_y is not None):

         result = search_result.Search_Result_Group()

         result.gf_name = self.clean_query
         result.gf_type_id = Item_Type.ADDY_COORDINATE
         # Skipping: result.stack_id
         # Skipping: result.ts_include
         # Skipping: result.ts_exclude

         gf_res = search_result.Search_Result_Geofeature(result)
         result.result_gfs.append(gf_res)

         # Skipping: result.node_ids

         result.gc_fulfiller = 'ccp_pt';

         # MAGIC_NUMBER: 100 is the most plausibly highest confidence.
         result.gc_confidence = 100

         gf_res.x = coord_x
         gf_res.y = coord_y
         pt_xy = (gf_res.x, gf_res.y,)
         # NOTE: Not fetching EWKT.
         gf_res.center = geometry.xy_to_wkt_point_restrict(pt_xy)
         # Skipping: gf_res.stack_id
         # Skipping: gf_res.geometry
         # Skipping: gf_res.width
         # Skipping: gf_res.height

         # Is this right?:
         result.ts_include['name'] = True

         # This is probably pointless:
         #  self.centerx = gf_res.x
         #  self.centery = gf_res.y

         self.all_results.append(result)
         self.all_results_sids.add(result.gf_stack_id)

      # else, not a "P(x,y)" query.

   # **** Look for an exact Cyclopath match (for route request geocoding)

   #
   def search_exact_names(self):

      # This fcn. is called via the geocode command.
      # This fcn. is not called via the search command, which will
      #  always do a broad Cyclopath query and will find these items that
      #  way (and will also rank exactly named results higher than
      #  other results).

      # The idea here is to see if there's a Cyclopath item of the exact
      # same name as the query, and then to use that item as the more
      # confident result, and then not to bother contacting the external
      # geocoder or searching internally on a broader query.

      # Check for matching regions.
      #
      # This search is very fast since we're filtering by the exact name.

      rg_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
      rg_qb.filters.filter_by_names_exact = self.clean_query
      regions = region.Many()
      regions.search_for_items(rg_qb)
      for rg in regions:
         # Add the region(s) to the result(s).
         result = search_result.Search_Result_Group()
         # See similar fcn., store_result_raw.
         result.store_result_item(self.qb.db, rg)
         self.all_results.append(result)
         self.all_results_sids.add(result.gf_stack_id)
         #log.debug('==> %s' % (result.__str__verbose_2__(),))

      # Check for matching waypoints. This is also very fast.

      wp_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
      wp_qb.filters.filter_by_names_exact = self.clean_query
      waypts = waypoint.Many()
      waypts.search_for_items(wp_qb)
      for wp in waypts:
         # Add the waypoint(s) to the result(s).
         result = search_result.Search_Result_Group()
         # See similar fcn., store_result_raw.
         result.store_result_item(self.qb.db, wp)
         self.all_results.append(result)
         self.all_results_sids.add(result.gf_stack_id)
         #log.debug('==> %s' % (result.__str__verbose_2__(),))

      # Check confidence of a confident match.
      #  Add here:
      #conf.break_here('ccpv3')
      #  Run this: ./ccp.py -s -q "gateway fountain"
      #  Tell pdb: result.__str__verbose__()
      #  Be told: '

      # If we found any items, we can short-circuit outta here: this is
      # probably exactly what the user is looking for.

      # 2014.06: Don't do this:
      #    The filter_by_names_exact filter splits on commas, so, if, e.g.,
      #    the address is "123 main st, some city", don't consider that a
      #    confident match.
      #  if ((regions or waypts) and (self.clean_query.find(',') == -1)):
      #     self.gc_confidence = 100
      # Because, e.g., "Guthrie" matches "Guthrie, MN" and "Guthrie Theater.

      # Here's how you might test the previous code from ccp.py:
      #
      # from item.feat import region
      # rg_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
      # rg_qb.filters.filter_by_names_exact = 'minnEAPOlis'
      # regions = region.Many()
      # regions.search_for_items(rg_qb)
      # for rg in regions:
      #    print rg
      #
      # from item.feat import waypoint
      # wp_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
      # wp_qb.filters.filter_by_names_exact = 'GateWAY fountain'
      # waypts = waypoint.Many()
      # waypts.search_for_items(wp_qb)
      # for wp in waypts:
      #    print wp

      return

   # **** Geocode Address

   #
   def search_addresses(self):

      # If the query looks like an address or intersection, the externally
      # geocoded results will be ranked higher than the internal results.
      # But if the query doesn't look like an address, we can still try
      # to geocode the query, but the result will be ranked lower.

      if self.better_addy:
         is_real_address = True
         external_query = self.better_addy
         g.assurt(self.better_addr is not None)
      else:
         is_real_address = False
         # Not using: external_query = self.main_query
         external_query = self.clean_query
         g.assurt(self.better_addr is None)

      # Send the query to the external geocoder.

      # 2014.06.16: Let's be more deliberate, shalln't we:
      #  Old school: address_objs = Geocode.geocode(external_query)
      #  New school: address_objs = Geocode.geocode_bing(external_query)
      # 2014.06.16: Bing has been offline all day (well, not offline, but not
      # returning any results for known addresses). So let's use a fallback
      # service, if we think the user really is trying to find an address.
      # 2014.06.18: Why not may MapQuest the default service?
      address_objs = []
      # 2014.09.10: MapQuest TOS say one cannot geocode without also getting
      #             maps and routes. [lb] doesn't remember reading that, but
      #             gladmin just got an email from mapquest.
      damn_it = True
      if not damn_it:
         address_objs += Geocode.geocode_mapquest(external_query)

      # If self.better_addy is set -- which means we parsed a valid state name,
      # a known municipality, or a zip code -- then is_real_address is set.
      # Here, if MapQuest didn't find anything, try Bing.
      # FIXME/BUG nnnn: Uncomment this and check is_real_address?
      #                 For now, always try Bing if MapQuest has naught.
      #if (not address_objs) and is_real_address:
      #if not address_objs:
      # MapQuest isn't Bing+; it can't find: '7th st and 8th av, two harbors'.
      #   So if we don't have 100% confidence, ask Bing! (Ug!!)
      # BUG nnnn: See a comment a few score lines later: 
      #           Checking 'state in admin dist' is a hack.
      #           We should really use the x,y and context of the query to
      #           determine what's a match we care about.
      #           Currently, we use a simple, "what's in our U.S. State
      #           or in a bordering state or Canadian province" to judge
      #           results to be result-worthy.
      # FIXME: This is a hack. See culled_addys: we should move that
      #        to a new fcn. and call it, so we don't iterate twice.
      #        But, really, 'meh', it's usually just a handful of results.
      good_matches = [x.gc_confidence for x in address_objs
                      if x.state in conf.admin_districts_ok]
      max_confidence = max(good_matches) if good_matches else 0

      if (not address_objs) or (max_confidence < 100):
         # MAYBE: Always geocode both and use lat,lon to cull duplicates?
         address_objs += Geocode.geocode_bing(external_query)

      # DEPRECATED: Filter results outside of the viewport.
      #
      # See: conf.geocode_buffer (currently: 30,000 meters).
      #
      # 2013.10.30: [lb] doesn't see the value in omitting results,
      #             especially since we're going statewide. People
      #             who search for cities in bordering states will
      #             think our site is pretty lame if we can't find,
      #             e.g., Superior, Wisconsin.
      #
      # To re-enable filtering by branch coverage_area, uncomment:
      #
      #   culled_addys = Geocode.geocode_external(self.qb, address_objs)
      #
      # In lieu of suppressing results, tell the user what's up...
      # BUG nnnn: For results outside the viewport, indicate as such in
      #           flashclient. E.g., a red triangle with a bang symbol,
      #           and don't zoom to results outside the coverage_area.
      # Currently, we include results in neighboring states but not anything
      # further away... but we still want to indicate if a search result is
      # off the map.
      culled_addys = []
      for addr_obj in address_objs:
         # BUG nnnn: Cull by nearness, i.e., if we intermingle two or more
         # external geocoders' results, eliminate duplicates from the second
         # and subsequent geocoders. For now, using the administrative district
         # slash state name in the USA, and calling it okay for now until we
         # implement a viable i18n solution.
         if addr_obj.state:
            if addr_obj.state not in conf.admin_districts_ok:
               log.debug('search_addresses: ignoring far-away result: %s'
                         % (addr_obj,))
            else:
               culled_addys.append(addr_obj)
         else:
            # MAYBE: Should we check center against branch.coverage_area and
            #        exclude far away results? [lb] isn't sure why Bing
            #        wouldn't specifiy the state... maybe because the result
            #        is in, e.g., Antarctica?
            #
            # 2014: I'm seeing such searches as "Umi, Papua New Guinea".
            #       And every few days... weird. I wonder if that the same
            #       machine every time.
            #
            # 343641 134.84.157.98 - ccgogo123 [24/Jan/2014:19:21:53 -0600]
            # "POST /gwis?rqst=geocode&browid=...&sessid=...&android=true
            # HTTP/1.1" 200 183 "-" "Dalvik/1.6.0 (Linux; U; Android 4.4.2;
            # Nexus 5 Build/KOT49H)" 16.2
            #
            # This is for results from countries without "states"...
            # BUG nnnn: Cyclopath i18n support. Like, "no province".
            log.debug('search_addresses: no state: %s' % (addr_obj,))

      already_set_center = False

      for addr_obj in culled_addys:

         result = search_result.Search_Result_Group()

         result.gf_name = addr_obj.text
         result.gf_type_id = Item_Type.ADDY_GEOCODE

         gf_res = search_result.Search_Result_Geofeature(result)
         result.result_gfs.append(gf_res)

         # Calculate the center of the result so that we can sort external
         # results alongside internal results. The external geocoder sends
         # latitude and longitude values in the Mercator projection, which
         # we convert into our own SRID coordinates.

         lon = addr_obj.x # e.g., -93.1234
         lat = addr_obj.y # e.g.,  45.1234

         #coord_xy_sql = (
         #  """
         #  SELECT ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(%f, %f), %d), %d))
         #           AS coord_x,
         #         ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(%f, %f), %d), %d))
         #           AS coord_y
         #  """
         #  % (lon, lat, conf.srid_latlon, conf.default_srid,
         #     lon, lat, conf.srid_latlon, conf.default_srid,))
         coord_xy_sql = (
            """
            SELECT
               ST_X(transformed_pt) AS coord_x
               , ST_Y(transformed_pt) AS coord_y
               --, ST_AsText(transformed_pt) AS center
            FROM ST_Transform(
                  ST_SetSRID(
                   ST_MakePoint(%f, %f), %d), %d) AS transformed_pt;
            """
            % (lon, lat, conf.srid_latlon, conf.default_srid,))

         rows = self.qb.db.sql(coord_xy_sql)

         if rows:
            gf_res.x = rows[0]['coord_x']
            gf_res.y = rows[0]['coord_y']
         else:
            # PROBBY: Default x,y should be middle of branch.coverage_area.
            gf_res.x = 0
            gf_res.y = 0
            log.warning('unexpected: no center: %s, %s / %s'
                        % (addr_obj.x, addr_obj.y, self.main_query,))

         pt_xy = (gf_res.x, gf_res.y,)
         # NOTE: Not fetching EWKT.
         gf_res.center = geometry.xy_to_wkt_point_restrict(pt_xy)
         # Skipping: gf_res.stack_id
         # Skipping: gf_res.geometry
         # Skipping: gf_res.width
         # Skipping: gf_res.height

         # We can assume the name hit... right? Even if it's a ZIP code,
         # this result hit because of the name, even if the result has a
         # different name.
         result.ts_include['name'] = True

         # Here, we're not searching Cyclopath items but instead consuming an
         # externally geocoded result. So we have to compute confidence
         # differently than we do for internal results (see
         # search_result.store_result_raw). We do this by accounting for the
         # Entity Type (Bing) or geocodeQuality (MapQuest), etc., indicated
         # by the external geocoder: we can rank addresses, intersections,
         # city,states, and zip codes the highest, but for all the other entity
         # types, let's make sure they get sorted lower in the list of results.

         # MAYBE: Skip levenshtein and just use external confidence value?
         #        Or is it better that we just handle the calculation ourselves?
         # BUG nnnn: Consider pt_xy in relation to the query center and set
         #           confidence accordingly.
         # MAYBE: Are these two parameters the right ones?
         levenratio = Levenshtein.ratio(unicode(external_query),
                                        unicode(addr_obj.text))
         log.debug('search_addresses: extl_q: %s / result: %s'
                   % (external_query,
                      addr_obj.text,))

         result.gc_fulfiller = addr_obj.gc_fulfiller;

         g.assurt(addr_obj.gc_confidence is not None)
         result.gc_confidence = addr_obj.gc_confidence

         # Does this make a lick of sense?
         if addr_obj.state in conf.admin_districts_nearby:
            # In a nearby state, so confidence is less?
            result.gc_confidence *= 0.8
         # else, addr_obj.state in conf.admin_district_primary

         if ((result.gc_confidence == 100)
             or (self.is_citystate_query)):

            # I.e., an address, intersection, or postal code, or city-state.
            # I.e., i.e., we don't act as confident with just a city name or a
            # state name, or a county name, since lots of waypoints and regions
            # include the same. E.g., "Guthrie": Guthrie, MN, or the Theater?
            # We could maybe choose the "more popular" one in the client but
            # show the list of reults, too?

            result.ts_include['addr'] = True

            # The external geocoder says this is an address, so we can assume
            # this result exactly matches what the user is searching for.
            result.gc_confidence = 100

            # If an address hits, we want to sort all results by their distance
            # from the center of the address hit; otherwise, we sort results by
            # their distance from the center of the user's viewport.
            #
            # BUG nnnn: If we don't pan/zoom to the first result in the list,
            #           then none of the results might appear in the user's
            #           viewport. (TESTME: Try searching: New York, New York)
            #
            if not already_set_center:
               if gf_res.x and gf_res.y:
                  self.centerx = gf_res.x
                  self.centery = gf_res.y
                  already_set_center = True
               else:
                  log.error('no gf_res.x,y?: %s' % (self.main_query,))

         # else, this is not an address match, so we can't be confident that
         #       it's what the user is looking for; just keep the confidence
         #       that we've already computed.

         # Skipping: result.stack_id
         # Skipping: result.ts_include
         # Skipping: result.ts_exclude
         # Skipping: result.node_ids

         self.all_results.append(result)
         self.all_results_sids.add(result.gf_stack_id)

      # end: for addr_obj in culled_addys

   # **** Trace output helper

   #
   def sql_debug_banner(self, title):
      banner = ''
      if conf.search_pretty_print:
         banner = (
            '''
   /*
       %s
   */
            ''' % (title,))
      return banner

   # **** Search Cyclopath Data

   #
   def search_geofeatures_and_links(self):

      union_clause = ""
      conjunctor = ""

      if self.do_search_feat_by_name():
         self.search_feat_by_name_common()
         # Search for non-waypoint geofeatures whose names match.
         union_clause += self.sql_debug_banner('do_search_feat_by_name >>')
         union_sql = self.search_feat_by_name_standard()
         if union_sql:
            union_clause += (
               """
               %s %s
               """ % (conjunctor, union_sql,))
            #conjunctor = "UNION"
            conjunctor = "UNION ALL"
         union_clause += self.sql_debug_banner('<< do_search_feat_by_name')
         # Search for waypoints that match the name, and for waypoints in
         # cities and neighborhoods that match the name.
         if Item_Type.WAYPOINT in self.search_for:
            # FIXME: Is this feature really all that useful? Returning all the
            # points that lie within a particular region doesn't seem useful,
            # since, e.g., searching for "Minneapolis" returns hundreds of pts.
            # TEST: Make a small, private region and search that.
            union_clause += self.sql_debug_banner('feat_by_name_waypoint >>')
            union_sql = self.search_feat_by_name_waypoint()
            if union_sql:
               union_clause += (
                  """
                  %s %s
                  """ % (conjunctor, union_sql,))
               #conjunctor = "UNION"
               conjunctor = "UNION ALL"
            union_clause += self.sql_debug_banner('<< feat_by_name_waypoint')

      search_feat_by_link = self.do_search_feat_by_link()
      if search_feat_by_link:
         union_clause += self.sql_debug_banner('feat_by_link >>')
         if ((Item_Type.TAG in self.search_in_attcs)
             and (self.ftq.include.tsv['tag'])):
            union_clause += self.sql_debug_banner('linked_tag >>')
            union_sql = self.search_feat_by_linked_tag()
            if union_sql:
               union_clause += (
                  """
                  %s %s
                  """ % (conjunctor, union_sql,))
               #conjunctor = "UNION"
               conjunctor = "UNION ALL"
            union_clause += self.sql_debug_banner('<< linked_tag')
         if ((Item_Type.ANNOTATION in self.search_in_attcs)
             and (self.ftq.include.tsv['note'])):
            union_clause += self.sql_debug_banner('linked_annot >>')
            union_sql = self.search_feat_by_linked_annot()
            if union_sql:
               union_clause += (
                  #%s (%s) AS feat_by_link
                  """
                  %s %s
                  """ % (conjunctor, union_sql,))
               #conjunctor = "UNION"
               conjunctor = "UNION ALL"
            union_clause += self.sql_debug_banner('<< linked_annot')
         union_clause += self.sql_debug_banner('<< feat_by_link')

      # Add CASE statements to the SELECT to get the geometry and center.
      self.search_feat_center_geometry()

      # The ts_rank_cd |-ORed querie for the main query.
      main_query_ish = re.sub(r"[|&']", '', self.main_query)
      main_query_words = main_query_ish.split()
      ts_main_query = '|'.join(main_query_words)
      self.main_query_word_cnt = len(main_query_words)
      g.assurt(self.main_query_word_cnt > 0)

      # FIXME: Can I select the external addresses into the table for sorting
      #        and paging?
      #        http://initd.org/psycopg/docs/cursor.html#cursor.copy_from
      # NOTE: Using GROUP BY and Aggregate fcns. to combine rows with the same
      #       stack ID -- since we UNION results, we might find the same item
      #       via different searches, so just combine all the ts_in_* bools.
      # SYNC_ME: See item_user_access.Many.sql_clauses_cols_name et al
      #          for the order of and columns being selected.
      # 2014.09.15: FIXME/BUG nnnn: We get one result for each match type,
      # e.g., a byway might match on the name, an annotation, and a tag,
      # and we'll get three results. We could DISTINCT ON to ignore the
      # extra rows, but really we want to coalesce the ts_in_* and ts_ex_*
      # booleans.
      sql_ts_search = (
         """
         SELECT
              --DISTINCT ON (stack_id) stack_id
              include.stack_id
            , include.acl_grouping
            , include.access_level_id
            , include.name
            , include.deleted
            , include.valid_until_rid
            , FIRST(include.name_enclosed) AS name_enclosed
            , ts_rank_cd(include.tsvect_name_,
                         to_tsquery('english', '%s'))
              AS ts_rank_cd
            , include.real_item_type_id
            , include.beg_node_id
            , include.fin_node_id
            %s -- thurrito.select (geometry_svg, center, wid, hgt)
            %s -- ts_in_* booleans
            %s -- ts_ex_* booleans
         FROM (
            %s             -- union_clause
            ) AS include   -- (the inner SQL returns include matches)
         %s                -- thurrito.ts_queries
         WHERE TRUE
            %s             -- thurrito.where (exclude matches)
         GROUP BY
            include.stack_id
            , include.acl_grouping
            , include.access_level_id
            , include.name
            , include.deleted
            , include.valid_until_rid
            --, include.name_enclosed
            , include.tsvect_name_
            , include.real_item_type_id
            , include.beg_node_id
            , include.fin_node_id
            %s -- thurrito.group_by (geometry_svg, center, wid, hgt)
         ORDER BY
            include.stack_id DESC
         %s %s
         """ % (
            ts_main_query,
            self.thurrito.select,
            Search_Map.search_ts_cols_sql(
               tbl_prefix='include.',
               ts_clude='ts_in',
               ts_vect=None,
               ignore_vects=('all',),
               use_coalesce=True),
            # BUG nnnn: Implement the "-exclude" feature.
            # For now, just return FALSE AS ts_ex_*.
            Search_Map.search_ts_cols_sql(
               tbl_prefix='',
               ts_clude='ts_ex',
               ts_vect='',
               ignore_vects=('all',),
               use_coalesce=False),
            union_clause,
            self.thurrito.ts_queries,
            # NOTE: thurrito.where is empty: We let client exclude search
            #       results.
            self.thurrito.where,
            self.thurrito.group_by,
            # NOTE: Since flashclient wants all results and sorts and filters
            #       locally, limit and offset clauses should be empty.
            self.qb.filters.limit_clause(),
            self.qb.filters.offset_clause(),
            ))

      # Perform the SQL query

      if Search_Map.debug_trace_sql:
         log.debug('search_geofeatures_and_links: sql:\n%s' % (sql_ts_search,))

      # FIXME/2014.05.06/MAYBE/BUG nnnn: speed this up...
      #       [lb] made the note and tag searches faster (using WHERE not JOIN)
      #       but we may still want to tackle this further... or maybe making
      #       our users wait five seconds for a bunch of awesome search results
      #       will trick them into beliebing how awesome our tool is (because
      #       waiting longer == more cool).
      time_0 = time.time()
      log.debug('search_geofeatures_and_links: this might take a while...')

      rows = self.qb.db.sql(sql_ts_search)

      results = self.process_big_internal_query(rows)
      n_added = 0
      for search_res_grp in results:
         if not search_res_grp.gf_stack_id:
            append_grp = True
         elif search_res_grp.gf_stack_id not in self.all_results_sids:
            append_grp = True
         else:
            # This means gf_stack_id is already in self.all_results_sids,
            # i.e., we found duplicate results. This happens if we, e.g.,
            # find a region by name in search_addresses() and then find
            # it again in this fcn.
            append_grp = False
            log.debug('search_gfs_n_lvs: excluding: %s'
                      % (search_res_grp.__str__verbose__(),))
         if append_grp:
            self.all_results.append(search_res_grp)
            n_added += 1

      log.debug(
         'search_geofeatures_and_links: found %d results (%d unique) after %s'
         % (len(results),
            n_added,
            misc.time_format_elapsed(time_0),))

   # ***

   #
   def do_search_feat_by_name(self):
      do_search = False
      #if Item_Type.ITEM_NAME in self.search_in_attcs:
      if self.search_in_names:
         do_search = True
      return do_search

   #
   def do_search_feat_by_link(self):
      do_search = False
      # If at least one search_in_attcs type other than NAME is specified,
      # search attachments.
      seq_match = difflib.SequenceMatcher(
         None, self.search_in_attcs, Item_Type.all_attachments())
      if seq_match.ratio() != 0.0:
         do_search = True
      return do_search

   # ***

   #
   def search_feat_by_name_base(self, feat_ids, feat_qb=None):

      g.assurt(self.search_in_names) # Checked earlier in code path.

      # Join against the geometry table.
      feat_qb = self.search_gfs_geometry_add(feat_ids, feat_qb)
      sqlc = feat_qb.sql_clauses

      # Include excluded names because of how flashclient filters results.
      all_name_terms = self.ftq.include.tsv['name']
      if all_name_terms and self.ftq.exclude.tsv['name']:
         all_name_terms += '|'
      all_name_terms += self.ftq.exclude.tsv['name']
      g.assurt(all_name_terms)
      feat_qb.filters.filter_by_text_full = all_name_terms

      # Make the text search query.
      sqlc.inner.ts_queries += (
         """
         , to_tsquery('english', '%s') AS ts_name
         """ % (all_name_terms,))
      # Carry-forward text search columns from the inner-ring to the
      # thurrito-ring.
      sqlc.inner.shared += (
         """
         , ts_name
         """)

      return feat_qb

   #
   def search_feat_by_name_common(self):

      # MAYBE: We could sort by syntactic nearness, but we'd have to add an
      # option to the client: right now the client expects results to be sorted
      # by geographic nearness first, and then by query string second.

      # Make a new text search query, this one for excluding matches.
      if self.ftq.exclude.tsv['name']:
         self.thurrito.ts_queries += (
            """
            , to_tsquery('english', '%s') AS ts_name_
            """ % (self.ftq.exclude.tsv['name'],))

# BUG_FALL_2013: FIXME: Does "-name" work from client??
      # In the third-ring SQL, exclude by name.
      # NOTE: Client wants all results and wants to filter itself...
      #       otherwise we could to_tsquery('this & !that').
      #   self.thurrito.where += (
      #      """
      #      AND NOT (include.tsvect_name_ @@ ts_name_)
      #      """)

   #
   def search_feat_by_name_standard(self):

      sql_feat_by_name = ""

      if self.search_for_except_waypoint:
         sql_feat_by_name = self.search_feat_by_name_standard_impl(
                                    self.search_for_except_waypoint)

      if self.ftq.exclude.tsv['name']:
         # BUG nnnn: Excluding terms is not implemented.
         self.thurrito.select += (
            """
            , CASE
               WHEN (include.tsvect_name_ @@ ts_name_) THEN
                  TRUE
               ELSE
                  FALSE
               END AS ts_ex_name
            """)
      else:
         self.thurrito.select += (
            """
            , FALSE AS ts_ex_name
            """)
      self.thurrito.group_by += (
         """
         , ts_ex_name
         """)

      return sql_feat_by_name

      # SELECT *,
      #  CASE WHEN (item_versioned.tsvect_name
      #             @@ plainto_tsquery('english', 'Martin Way'))
      #     THEN TRUE ELSE FALSE END AS ts_ex_name
      #  FROM item_versioned WHERE name='Martin Way';

   #
   def search_feat_by_name_standard_impl(self, feat_ids_except_waypoint):

      feat_qb = self.search_feat_by_name_base(feat_ids_except_waypoint)

      sqlc = feat_qb.sql_clauses

      # For non-waypoints, use the table's pre-computed text search vector.
      sqlc.inner.select += (
         """
         , gia.tsvect_name AS tsvect_name_
         """)
      # Perform the full text search.
      sqlc.inner.where += (
         """
         AND (gia.tsvect_name @@ ts_name)
         """)
      sqlc.inner.group_by += (
         """
         --, gia.tsvect_name
         """)

      sqlc.outer.enabled = True

      # For non-waypoints, the 'enclosed' name is the same name as the name.
      # NOTE: Using a UNION, so be careful with SELECT (coord. w/ others). */
      sqlc.outer.select += (
         """
         , COALESCE(group_item.name, 'Unnamed') AS name_enclosed
         , group_item.tsvect_name_
         """)

      sqlc.outer.select += Search_Map.search_ts_cols_sql(
         tbl_prefix='',
         ts_clude='ts_in',
         ts_vect='name',
         ignore_vects=('all',),
         use_coalesce=False)
      #g.assurt(not sqlc.outer.group_by)
      #g.assurt(not sqlc.outer.group_by_enable)
      #sqlc.outer.group_by_enable = True
      g.assurt(sqlc.outer.group_by)
      g.assurt(sqlc.outer.group_by_enable)
      sqlc.outer.group_by += (
         """
         , group_item.name
         , group_item.tsvect_name_
         """)

      # NOTE: We search on item_type_id, so we don't use the individual
      #       geofeature item classes. So whatever stop words they might
      #       apply to filter_by_text_smart won't happen (also because we
      #       search_feat_by_name_base sets filter_by_text_full). Meaning,
      #       all geofeature items' names have the same stop words applied
      #       (which is ccp_stop_words.Addy_Stop_Words__Byway, which includes
      #       such horrendous terms such as "Ave").
      #sql_feat_by_name = geofeature.Many().search_get_sql(feat_qb)
      sql_feat_by_name = item_user_access.Many().search_get_sql(feat_qb)

      return sql_feat_by_name

   #
   def search_feat_by_name_waypoint(self):

      # We fetch Waypoints separately from other Geofeature types because
      # we also look for all waypoints within a neighborhood or city that
      # matches a query.
      # EXPLAIN: [lb] always found this feature to be a bit useless:
      #          what's the difference from just zooming the map to
      #          a neighborhood and city and poking around? Agreed,
      #          using search, the waypoints all appear in a nice
      #          list, but it also bloats the search results (which
      #          I suppose could be fixed if we made sure to sort
      #          neighborhood and city matches last).

      # Get SQL to join against regions that are tagged 'neighborhood' or
      # 'city'. (Do it now, since these fcns. use self.qb, which is overwritten
      # by search_feat_by_name_base.)

      sql_in_hood = self.search_feat_sql_tagged_regions('neighborhood', 'tr_n')
      sql_in_city = self.search_feat_sql_tagged_regions('city', 'tr_c')

      feat_ids_only_waypoint = [Item_Type.WAYPOINT,]

      feat_qb = self.search_feat_by_name_base(feat_ids_only_waypoint)
      sqlc = feat_qb.sql_clauses

      # FIXME: Make sure waypoints that only match region geometry and not a
      # name search are ranked lower than all other results.

      # Perform the full text search.
      sqlc.inner.where += (
         """
         AND ((gia.tsvect_name @@ ts_name)
              OR (tr_n.gf_name IS NOT NULL)
              OR (tr_c.gf_name IS NOT NULL))
         """)

      # For waypoints, the 'enclosed' name is special.
      #
      # In CcpV1, if a point is found in a region tagged 'neighborhood'
      # or 'city' that matches the search query, we return the geofeature
      # name with the name of the neighborhood or city in parantheses.
      # In CcpV2, [lb] wants to let users use a new 'search in' filter
      # called 'neighborhoods' so we don't always do this.
      # TESTME: found_in_hood and found_in_city: can flashclient
      #         filter out city and neighborhood results?
      sqlc.inner.select += (
         """
         , CASE
            WHEN (tr_n.gf_name IS NULL AND tr_c.gf_name IS NULL) THEN
               gia.name
            WHEN (tr_n.gf_name IS NULL) THEN
               gia.name || ' (' || tr_c.gf_name || ')'
            WHEN (tr_c.gf_name IS NULL) THEN
               gia.name || ' (' || tr_n.gf_name || ')'
            ELSE
               gia.name || ' (' || tr_n.gf_name || ', ' || tr_c.gf_name || ')'
         END AS name_enclosed
         , CASE WHEN (tr_n.gf_name IS NULL) THEN FALSE ELSE TRUE
            END AS found_in_hood
         , CASE WHEN (tr_c.gf_name IS NULL) THEN FALSE ELSE TRUE
            END AS found_in_city
         , gia.tsvect_name
         """)
      sqlc.inner.group_by += (
         """
         , tr_n.gf_name
         , tr_c.gf_name
         """)

      # Join against regions that are tagged 'neighborhood' or 'city'.
      sqlc.inner.join += sql_in_hood
      sqlc.inner.join += sql_in_city

      sqlc.outer.enabled = True

      # For waypoints, since the name is computed, compute the txt srch vector.
      # NOTE: Using a UNION, so be careful with SELECT (coord. w/ others). */
      # SYNC_ME: Search text search vect types. Column order matters.
      sqlc.outer.select += (
         """
         , COALESCE(group_item.name_enclosed, 'Unnamed') AS name_enclosed
         , to_tsvector('english', COALESCE(group_item.name_enclosed, ''))
              AS tsvect_name_
         , FALSE AS ts_in_addr
         , (group_item.tsvect_name @@ ts_name) AS ts_in_name
         , (group_item.found_in_hood OR group_item.found_in_city) AS ts_in_hood
         , FALSE AS ts_in_tag
         , FALSE AS ts_in_note
         , FALSE AS ts_in_post
         """)
      # This is wrong; hard-code instead (see previous).
      # HACK: The hard-coded ts_in_* cols means you cannot enable/disable
      # individual search options without editing the previous SQL.
      #sqlc.outer.select += Search_Map.search_ts_cols_sql(
      #                       '', 'ts_in', 'hood', ('all',))

      feat_qb.filters.force_resolve_item_type = True

      #g.assurt(not sqlc.outer.group_by)
      #g.assurt(not sqlc.outer.group_by_enable)
      #sqlc.outer.group_by_enable = True
      g.assurt(sqlc.outer.group_by)
      g.assurt(sqlc.outer.group_by_enable)
      sqlc.outer.group_by += (
         """
         , group_item.name_enclosed
         , group_item.tsvect_name
         , group_item.found_in_hood
         , group_item.found_in_city
         """)

      g.assurt(id(feat_qb.sql_clauses) == id(sqlc))
      #sql_feat_by_name = geofeature.Many().search_get_sql(feat_qb)
      sql_feat_by_name = waypoint.Many().search_get_sql(feat_qb)

      return sql_feat_by_name

   #
   def search_feat_sql_tagged_regions(self, tag_name, join_as_name):

      link_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
      link_qb.sql_clauses = link_tag.Many.sql_clauses_cols_all.clone()

      g.assurt(self.ftq.include.tsv['name'])
      g.assurt(self.ftq.include.raw['name'])
      # Don't search in large regions if the user did an address search.
      scrubbed = []
      for raw_term in self.ftq.include.raw['name']:
         # Don't include heavily populated regions or we'll grab thousands
         # of results and they won't be that useful.
         if raw_term not in ccp_stop_words.Addy_Stop_Words__In_Region.lookup:
            scrubbed.append(raw_term)
      raw_query = ["'%s'" % self.qb.db.quoted(s) for s in scrubbed]
      raw_query = "|".join(raw_query)

      link_qb.sql_clauses.inner.ts_queries += (
         """
         , to_tsquery('english', '%s') AS ts_name
         """
         % (raw_query,))
      link_qb.sql_clauses.inner.where += (
         """
         AND rhs_gia.tsvect_name @@ ts_name
         """)

      tagged_regions = link_tag.Many(tag_name, Item_Type.REGION)
      sql_tagged_regions = tagged_regions.search_get_sql(link_qb)

      sql_join_tagged_regions = (
         """
         LEFT OUTER JOIN
            (%s) AS %s
            ON (ST_Intersects(feat.geometry, %s.geometry))
         """ % (sql_tagged_regions,
                join_as_name,
                join_as_name,))

      return sql_join_tagged_regions

   #
   def search_feat_by_linked_tag(self):

      # BUG_FALL_2013: Can we close?: BUG 2435. It's about including
      #                tags and notes in search results...

      g.assurt(not self.qb.viewport.include)
      g.assurt(not self.qb.viewport.exclude)
      g.assurt(not self.qb.sql_clauses)

      sql_feats_by_tag = ''

      add_tagged_geofeatures = False
      if Item_Type.TAG in self.search_in_attcs:
      # FIXME: What about: if self.ftq.include.tsv['tag']:

         # Make a temp table of tags with the matching name.
         # Note that we're cloning to make a clean qb with clean filters,
         # but the db is the same object, so the temp table won't be spaghoten.
         attc_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
         attc_qb.sql_clauses = tag.Many.sql_clauses_cols_all.clone()

         all_tag_terms = self.ftq.include.tsv['tag']
         if self.ftq.include.tsv['tag'] and self.ftq.exclude.tsv['tag']:
            all_tag_terms += '|'
         all_tag_terms += self.ftq.exclude.tsv['tag']
         attc_qb.filters.filter_by_text_full = all_tag_terms

         Query_Overlord.finalize_query(attc_qb)

         attc_tags = tag.Many()
         #attc_tags.search_for_items(attc_qb)
         attc_qb.use_filters_and_viewport = True
         attcs_sql = attc_tags.search_get_sql(attc_qb)

         attc_stack_id_table_ref = 'temp_stack_id__tags_named'
         self.thurrito_sql_tags = (
            """
            SELECT
               stack_id
            INTO TEMPORARY TABLE
               %s
            FROM
               (%s) AS foo_tags_sid
            """ % (attc_stack_id_table_ref,
                   attcs_sql,))

         if Search_Map.debug_trace_sql:
            log.debug('search_feat_by_linked_tag: sql:\n%s'
                      % (self.thurrito_sql_tags,))

         rows = attc_qb.db.sql(self.thurrito_sql_tags)
         g.assurt(rows is None)

         tag_count_sql = ("SELECT COUNT(*) FROM %s"
                          % (attc_stack_id_table_ref,))
         rows = attc_qb.db.sql(tag_count_sql)
         tag_count = rows[0]['count']
         log.debug('search_feat_by_linked_tag: tag_count: %d' % (tag_count,))

         add_tagged_geofeatures = True
         if tag_count < 1:
            # No matching tags.
            add_tagged_geofeatures = False
         elif tag_count > 10:
            # 2014.06.22:
            # lots of tags: 18 / "canal park"
            # lots of tags: 53 / "freewheel bike"
            # lots of tags: 19 / "snelling state park"
            log.debug('search_feat_by_linked_tag: lots of tags: %d / "%s"'
                      % (tag_count, self.main_query,))

      if add_tagged_geofeatures:

         feat_qb = self.search_gfs_geometry_add(self.search_for)
         sqlc = feat_qb.sql_clauses

         if tag_count > 2500:
            # Does this path happen?
            log.warning('search_feat_by_linked_tag: test me: join vs. where')

            # I.e., "JOIN link_value AS flv ON (%s)"
            join_on_to_self = "feat.stack_id = flv.rhs_stack_id"
            # No need for the where.
            where_on_other = ""
            # Join on the temp table of tag stack IDs.
            join_on_temp = (
               """
               JOIN %s
                  ON (flv.lhs_stack_id = %s.stack_id)
               """ % (attc_stack_id_table_ref,
                      attc_stack_id_table_ref,))

            link_where = item_user_watching.Many.sql_where_filter_linked_impl(
               feat_qb, join_on_to_self, where_on_other, join_on_temp)

            sqlc.inner.join += (
               """
               JOIN item_versioned AS attc_iv
                  ON (attc_iv.stack_id = flv.lhs_stack_id)
               """)
            sqlc.inner.where += (
               """
               AND (%s)
               AND %s
               """ % (link_where,
                      revision.Revision.branch_hier_where_clause(
                        feat_qb.branch_hier,
                        'attc_iv',
                        include_gids=False,
                        allow_deleted=False),))

         else:

            (where_clause, sql_tmp_table,
               ) = link_value.Many.prepare_sids_temporary_table(self.qb,
                     'lhs_stack_id',
                     attc_stack_id_table_ref,
                     'rhs_stack_id',
                     'temp_stack_id__tagged_feats')
            self.thurrito_sql_tags_lvals = sql_tmp_table
            sqlc.inner.where += "AND %s" % (where_clause,)

         # Make the text search query.
         g.assurt(self.ftq.include.tsv['tag'])
         sqlc.inner.ts_queries += (
            """
            , to_tsquery('english', '%s') AS ts_name
            """ % (self.ftq.include.tsv['tag'],))
         # Carry-forward text search columns from the inner-ring to the
         # thurrito-ring.
         sqlc.inner.shared += (
            """
            , ts_name
            """)

         sqlc.outer.enabled = True
         sqlc.outer.select += (
            """
            , COALESCE(group_item.name, 'Unnamed') AS name_enclosed
            , to_tsvector('english', '') AS tsvect_name_
            """)
         sqlc.outer.group_by_enable = True

         # Add, i.e., TRUE AS ts_in_tag.
         sqlc.outer.select += Search_Map.search_ts_cols_sql(
            tbl_prefix='',
            ts_clude='ts_in',
            ts_vect='tag',
            ignore_vects=('all',),
            use_coalesce=False)

         sql_feats_by_tag = item_user_access.Many().search_get_sql(feat_qb)

      # end: if add_tagged_geofeatures

      return sql_feats_by_tag

   #
   def search_feat_by_linked_annot(self):

      # SYNC_ME: This fcn. c.f. previous, search_feat_by_linked_tag.

      sql_feats_by_annot = ''

      add_annotated_geofeatures = False
      if Item_Type.ANNOTATION in self.search_in_attcs:
      # FIXME: What about: if self.ftq.include.tsv['note']:

         # Make a temp table of notes that match. Clone the qb but keep ahold
         # of the same db, so we add the temp table to the right cursor.
         attc_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
         attc_qb.sql_clauses = annotation.Many.sql_clauses_cols_all.clone()

         all_annot_terms = self.ftq.include.tsv['note']
         if self.ftq.include.tsv['note'] and self.ftq.exclude.tsv['note']:
            all_annot_terms += '|'
         all_annot_terms += self.ftq.exclude.tsv['note']
         attc_qb.filters.filter_by_text_full = all_annot_terms

         Query_Overlord.finalize_query(attc_qb)

         attc_annots = annotation.Many()
         #attc_annots.search_for_items(attc_qb)
         attc_qb.use_filters_and_viewport = True
         attcs_sql = attc_annots.search_get_sql(attc_qb)

         attc_stack_id_table_ref = 'temp_stack_id__annots_named'
         self.thurrito_sql_annots = (
            """
            SELECT
               stack_id
            INTO TEMPORARY TABLE
               %s
            FROM
               (%s) AS foo_annots_sid
            """ % (attc_stack_id_table_ref,
                   attcs_sql,))

         if Search_Map.debug_trace_sql:
            log.debug('search_feat_by_linked_annot: sql:\n%s'
                      % (self.thurrito_sql_annots,))

         rows = attc_qb.db.sql(self.thurrito_sql_annots)
         g.assurt(rows is None)

         annot_count_sql = ("SELECT COUNT(*) FROM %s"
                            % (attc_stack_id_table_ref,))
         rows = attc_qb.db.sql(annot_count_sql)
         annot_count = rows[0]['count']
         log.debug('search_feat_by_linked_annot: annot_count: %d'
                   % (annot_count,))

         add_annotated_geofeatures = True
         if annot_count < 1:
            # No matching annots.
            add_annotated_geofeatures = False
         elif False:
            if annot_count > 200:
               # MAYBE: Should we impose a limit?
               # [lb] sees some queries with lots of annotation hits:
               #  "Edenvale Blvd" has 34 annot hits, because of Blvd.
               log.error(
                  'search_feat_by_linked_annot: lots of annots: %d / "%s"'
                  % (annot_count, self.main_query,))
               #? add_annotated_geofeatures = False

      if add_annotated_geofeatures:

         feat_qb = self.search_gfs_geometry_add(self.search_for)
         sqlc = feat_qb.sql_clauses

         if annot_count > 2500:
            # Does this path happen?
            log.warning('search_feat_by_linked_annot: test me: join vs. where')

            # I.e., "JOIN link_value AS flv ON (%s)"
            join_on_to_self = "feat.stack_id = flv.rhs_stack_id"
            # No need for the where.
            where_on_other = ""
            # Join on the temp table of annot stack IDs.
            join_on_temp = (
               """
               JOIN %s
                  ON (flv.lhs_stack_id = %s.stack_id)
               """ % (attc_stack_id_table_ref,
                      attc_stack_id_table_ref,))

            link_where = item_user_watching.Many.sql_where_filter_linked_impl(
               feat_qb, join_on_to_self, where_on_other, join_on_temp)

            sqlc.inner.join += (
               """
               JOIN item_versioned AS attc_iv
                  ON (attc_iv.stack_id = flv.lhs_stack_id)
               """)
            sqlc.inner.where += (
               """
               AND (%s)
               AND %s
               """ % (link_where,
                      revision.Revision.branch_hier_where_clause(
                        feat_qb.branch_hier,
                        'attc_iv',
                        include_gids=False,
                        allow_deleted=False),))

         else:

            (where_clause, sql_tmp_table,
               ) = link_value.Many.prepare_sids_temporary_table(self.qb,
                     'lhs_stack_id',
                     attc_stack_id_table_ref,
                     'rhs_stack_id',
                     'temp_stack_id__annoted_feats')
            self.thurrito_sql_annots_lvals = sql_tmp_table
            sqlc.inner.where += "AND %s" % (where_clause,)

         # Make the text search query.
         g.assurt(self.ftq.include.tsv['note'])
         sqlc.inner.ts_queries += (
            """
            , to_tsquery('english', '%s') AS ts_name
            """ % (self.ftq.include.tsv['note'],))
         # Carry-forward text search columns from the inner-ring to the
         # thurrito-ring.
         sqlc.inner.shared += (
            """
            , ts_name
            """)

         sqlc.outer.enabled = True
         sqlc.outer.select += (
            """
            , COALESCE(group_item.name, 'Unnamed') AS name_enclosed
            , to_tsvector('english', '') AS tsvect_name_
            """)
         sqlc.outer.group_by_enable = True

         # Add, i.e., TRUE AS ts_in_note.
         sqlc.outer.select += Search_Map.search_ts_cols_sql(
            tbl_prefix='',
            ts_clude='ts_in',
            ts_vect='note',
            ignore_vects=('all',),
            use_coalesce=False)

         sql_feats_by_annot = item_user_access.Many().search_get_sql(feat_qb)

      return sql_feats_by_annot

   # ***

   #
   def search_gfs_geometry_add(self, feat_ids, feat_qb=None):

      # Nope, since we might filter by item_type, and geofeature
      #       sets child_item_types, but item_user_access does not:
      #  sqlc = geofeature.Many.sql_clauses_cols_name.clone()
      if feat_qb is None:
         feat_qb = self.qb.clone(skip_clauses=True, skip_filtport=True)
         sqlc = item_user_access.Many.sql_clauses_cols_name.clone()
         feat_qb.sql_clauses = sqlc
      else:
         sqlc = feat_qb.sql_clauses

      #
      sqlc.inner.select += (
         """
         , gia.valid_until_rid
         """)
      sqlc.inner.group_by += (
         """
         , gia.valid_until_rid
         """)

      # Only look for specific geofeature type.
      if len(feat_ids) > 1:
         sqlc.inner.where += (
            """
            AND (gia.item_type_id IN (%s))
            """ % (",".join([str(tid) for tid in feat_ids]),))
      elif len(feat_ids) == 1:
         sqlc.inner.where += (
            """
            AND (gia.item_type_id = %d)
            """ % (feat_ids[0],))
      else:
         g.assurt(False)

      sqlc.outer.enabled = True

      # Always return the original name of the geofeature.
      # NOTE: Using a UNION, so be careful with SELECT (coord. w/ others). */
      sqlc.outer.select += (
         """
         , group_item.ts_name
         , group_item.deleted
         , group_item.valid_until_rid
         """)

      sqlc.outer.group_by_enable = True
      sqlc.outer.group_by += (
         """
         , group_item.name
         , group_item.ts_name
         , group_item.deleted
         , group_item.valid_until_rid
         """)

      sqlc.inner.join += (
         """
         JOIN geofeature AS feat
            ON (gia.item_id = feat.system_id)
         """)

      sqlc.inner.shared += (
         """
         , feat.geometry
         , feat.beg_node_id
         , feat.fin_node_id
         """)

      sqlc.outer.shared += (
         """
         , group_item.geometry
         , group_item.beg_node_id
         , group_item.fin_node_id
         """)

      return feat_qb

   # ***

   #
   @staticmethod
   def search_ts_cols_sql(tbl_prefix, ts_clude='', ts_vect='',
                          ignore_vects=[], use_coalesce=False):
      select_sql = ""
      for mask in ('ts_in', 'ts_ex',):
         if ts_clude and (mask != ts_clude):
            # Only include one set of cols, either ts_in_* or ts_ex_*.
            continue
         for vect in search_full_text.Full_Text_Query_Part.ts_vects:
            mask_vect = "%s_%s" % (mask, vect,)
            if vect in ignore_vects:
               continue
            elif (not ts_clude) or (ts_vect is None):
               val = mask_vect
            else:
               g.assurt(ts_clude in ('ts_in', 'ts_ex',))
               #g.assurt(ts_vect
               #       in search_full_text.Full_Text_Query_Part.ts_vects)
               if vect != ts_vect:
                  val = "FALSE"
               else:
                  val = "TRUE"
            if not use_coalesce:
               select_sql += (
                  """
                  , %s%s AS %s
                  """ % (tbl_prefix, val, mask_vect,))
            else:
               select_sql += (
                  """
                  , BOOL_OR(%s%s) AS %s
                  """ % (tbl_prefix, val, mask_vect,))
      #log.verbose('search_ts_cols_sql: select_sql: %s' % (select_sql,))
      return select_sql

   #
   def search_feat_center_geometry(self):
      feat_tids = {
         'byway_tid': Item_Type.BYWAY,
         'region_tid': Item_Type.REGION,
         'terrain_tid': Item_Type.TERRAIN,
         'waypoint_tid': Item_Type.WAYPOINT,
         'precis': conf.db_fetch_precision,
         # MAGIC_NUMBER: 'include' is table name; col. defaults to 'geometry'.
         'line_center': byway.One.search_center_sql(table_name='include'),
         'polygon_center': region.One.search_center_sql(table_name='include'),
         'point_center': waypoint.One.search_center_sql(table_name='include'),
         }
      # BUG nnnn: (Better) MULTIPOLYGON support.
      #  I [lb] imported some with the statewide data.
      #  SELECT COUNT(*) FROM geofeature WHERE
      #        ST_GeomtryType(geometry) ='ST_Polygon';      # 9499
      #        ST_GeomtryType(geometry) ='ST_MultiPolygon'; # 332
      # For now, avoid trouble by using ST_GeometryN. You could also maybe
      # accomplish something with ST_Dump (probably just another multi).
      #  SELECT gid, ST_Collect(ST_ExteriorRing(the_geom)) AS erings
      #     FROM (SELECT gid, (ST_Dump(the_geom)).geom AS the_geom
      #                        FROM sometable) As foo
      self.thurrito.select += (
         """
         , CASE
            WHEN include.real_item_type_id = %(byway_tid)d THEN       -- BYWAY
               ST_AsSVG(ST_Scale(include.geometry, 1, -1, 1), 0, %(precis)d)
            WHEN ((include.real_item_type_id = %(region_tid)d)       -- REGION
                  OR (include.real_item_type_id = %(terrain_tid)d)) -- TERRAIN
                  THEN
               ST_AsSVG(ST_Scale(ST_ExteriorRing(ST_GeometryN(include.geometry,
                                                              1)), 1, -1, 1),
                     0, %(precis)d)
            WHEN include.real_item_type_id = %(waypoint_tid)d THEN -- WAYPOINT
               ST_AsText(include.geometry)
            ELSE
               NULL
            END AS geometry_svg

         , CASE
            WHEN include.real_item_type_id = %(byway_tid)d            -- BYWAY
               THEN %(line_center)s
            WHEN ((include.real_item_type_id = %(region_tid)d)       -- REGION
                  OR (include.real_item_type_id = %(terrain_tid)d)) -- TERRAIN
               THEN %(polygon_center)s
            WHEN include.real_item_type_id = %(waypoint_tid)d      -- WAYPOINT
               THEN %(point_center)s
            ELSE
               NULL
            END AS center

         , (ST_XMax(geometry) - ST_XMin(geometry)) AS width
         , (ST_YMax(geometry) - ST_YMin(geometry)) AS height
         """ % feat_tids)
      # EXPLAIN: Are width and height used? We don't use them here, in
      # search_map, and even in search_result, they're not even sent to
      # the client.
      self.thurrito.group_by += (
         """
         , geometry_svg
         , center
         , width
         , height
         """)

   # *** Results-processing helpers

   #
   def process_big_internal_query(self, rows):

      results = []
      # Byways are special: group those that link together via node IDs.
      byways = []

# BUG_FALL_2013
# FIXME: Split a byway from basemap in leafy branch, rename it unique, then
#        search for it and the old byway: make sure new road is found and
#        new unique name search, and old road is not found with old name
#        search.

      log.debug('process_big_internal_query: len(rows): %d' % (len(rows),))

      # Send along the raw queries so that we can rank higher any results that
      # exactly match.
      #raw_queries = [self.main_query,]
      raw_queries = [self.clean_query,]
      # By adding the full street name, when searching for an address, the
      # geocoded location will be ranked first, and it'll be followed by
      # the street's byways. E.g., "1234 Dupont Av S, Mpls" will show the
      # geocode result first, followed by the Dupont Av S byways, followed
      # by the Dupont Ave N byways.
      if self.full_street:
         raw_queries.append(self.full_street)
      if self.full_street2:
         raw_queries.append(self.full_street2)
      # MAYBE: Should we add any "quoted substrings" from the clean_query?
      #  query_terms = re.findall(r'-?\"[^\"]*\"', self.clean_query)
      #  for qt in query_terms:
      #     raw_queries.append(qt)

      for row in rows:
         #log.debug('==> %s' % (Search_Result_Group.result_row_str(row),))
         result = search_result.Search_Result_Group()
         result.store_result_raw(row, raw_queries, self)
         if row['real_item_type_id'] == Item_Type.BYWAY:
            byways.append(result)
         else:
            g.assurt(row['real_item_type_id'] in (
               Item_Type.REGION,
               Item_Type.WAYPOINT,
               Item_Type.ADDY_COORDINATE,
               Item_Type.ADDY_GEOCODE,
               ))
            results.append(result)
         #log.debug('==> %s' % (result.__str__verbose_2__(),))

      # Note that results will be sorted later.

      byways = search_result.Search_Result_Group.process_results_byways(byways)
      byways.extend(results)
      results = byways

      return results

   # ***

   #
   def sort_compare_priority(self, a, b):
      # Compare results: First on confidence, then on item type, finally on
      #                  distance from center of user's viewport.
      result = cmp(b.gc_confidence, a.gc_confidence)
      if result == 0:
         # objects have same edit distance, compare on object type
         # (region -> point -> byway)
         result = cmp(a.object_priorities[a.gf_type_id],
                      b.object_priorities[b.gf_type_id])
      if result == 0:
         # objects have same edit distance and type, compare on distance to
         # query center
         try:
            # The thurrito that gets items doesn't set x,y but it sets center.
            # But some search results, like externally geocoded results, set
            # both x, y, and center. So center should always be set.
            (x1, y1,) = geometry.wkt_point_to_xy(a.result_gfs[0].center)
            (x2, y2,) = geometry.wkt_point_to_xy(b.result_gfs[0].center)
         except TypeError:
            # DEVS: If you're here, maybe you set x and y but not c(enter).
            g.assurt(False)
         dist_1 = (math.pow((self.centerx - x1), 2)
                 + math.pow((self.centery - y1), 2))
         dist_2 = (math.pow((self.centerx - x2), 2)
                 + math.pow((self.centery - y2), 2))
         result = cmp(dist_1, dist_2)
         #log.debug(
         #   'sort_compare_priority: center result: %s / %s / %s / %s / %s'
         #   % (result, dist_1, dist_2, a, b,))
      if result == 0:
         # Order groups of things (well, byways) with more items than other
         # similar groups of items.
         result = cmp(len(a.result_gfs), len(b.result_gfs))
      # Two results might be concerned equal when their strings aren't. E.g.,
      #      srg: [2725 - 2799] 77th Street Dr, Watkins, IA, 52354-9600: (1)
      #    / srg: [2724 - 2798] 77th Street Dr, Watkins, IA, 52354: (1)
      #   dist_1: 264422115826.0
      # / dist_2: 264422115826.0
      #if result == 0:
      #   log.warning('sort_compare_priority: really equal? %s / %s' % (a, b,))
      #   log.warning(' >> center: result: %s / dist_1: %s / dist_2: %s'
      #               % (result, dist_1, dist_2,))
      return result

   # ***

   #
   def prepare_case_query(self, f_type):

      g.assurt(False) # Deprecated. Using full text query now.

      # This case section of the query is for verifying whether each query term
      # matches and what type of match it is. We append an index to the column
      # name in order to make columns for every query and so that we can easily
      # identify them later.

      annotation_str = '(position(lower(%s) IN lower(comments)) > 0)'
      if (f_type == 'byway'):
         annotation_str = """(position(lower(%%s) IN %s) > 0)
                  """ % (self.prepare_array_search_query(f_type, 'annotation'))

      case = ''
      for i in xrange(len(self.query_include) + len(self.query_exclude)):
         if i > 0:
            case += ', '
         case += (
            """
            CASE
            WHEN ((position(lower(%%s) IN lower(name)) > 0))
              THEN true
              ELSE false
            END as name_match%s,
            CASE
            WHEN (%s)
              THEN true
              ELSE false
            END as comment_match%s,
            CASE
            WHEN ((position(lower(%%s) IN %s) > 0))
               THEN true
               ELSE false
            END as tag_match%s
            """ % (str(i),
                   annotation_str,
                   str(i),
                   self.prepare_array_search_query(f_type, 'tag'),
                   str(i)))

      return case

   # ***

# ***

