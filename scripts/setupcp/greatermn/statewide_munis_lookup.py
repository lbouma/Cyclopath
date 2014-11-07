#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ INSTANCE=minnesota ./statewide_munis_lookup.py --help
#

script_name = ('Populate MN cities lookup')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-10-24'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# ***

# NOTE: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE1
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('stwd_munis_l')

# ***

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import sys

import re
import time
import traceback

import conf
import g

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from item import item_versioned
from item import item_user_access
from item import geofeature
from item.feat import region
from item.grac import group
from item.grac import new_item_policy
from item.util import revision
from util_ import db_glue
from util_ import misc
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
from util_.shapefile_wrapper import Shapefile_Wrapper
from util_.streetaddress import addressconf
from util_.streetaddress import streetaddress

from merge.ccp_merge_layer_base import Ccp_Merge_Layer_Base

# ***

debug_skip_commit = False
#debug_skip_commit = True

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   # ***

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      self.add_argument(
         '--citys_state', dest='citys_state', action='store', type=str,
         default=conf.admin_district_abbrev, # default='MN',
         help='The U.S. state in which the cities exist.')

      # Download the city polygon Shapefile from:
      # http://www.dot.state.mn.us/maps/gdma/gis-data.html
      # http://www.dot.state.mn.us/maps/gdma/data/metadata/muni.htm
      # http://www.dot.state.mn.us/maps/gdma/data/datafiles/statewide/muni.zip
      self.add_argument(
         '--shapefile-cities', dest='shp_cities', action='store', type=str,
         default='/ccp/var/shapefiles/greatermn/muni_city_names/muni.shp',
         help='The path to the Shapefile of cities to import')

      # Download the county polygon Shapefile from:
      # http://www.dot.state.mn.us/maps/gdma/gis-data.html
      # http://www.dot.state.mn.us/maps/gdma/data/metadata/county.htm
      #http://www.dot.state.mn.us/maps/gdma/data/datafiles/statewide/county.zip
      self.add_argument(
         '--shapefile-counties', dest='shp_counties', action='store', type=str,
         default='/ccp/var/shapefiles/greatermn/county/county.shp',
         help='The path to the Shapefile of counties to import')

# *** Statewide_Munis_Lookup_Populate

class Statewide_Munis_Lookup_Populate(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      do_commit = False

      try:

         self.qb.db.transaction_begin_rw()

         self.lookup_tables_reset()

         self.lookup_tables_populate()

         self.report_on_popular_street_types()

         log.debug('Committing transaction')

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def lookup_tables_reset(self):

      self.lookup_tables_reset_state_cities()

      self.lookup_tables_reset_state_city_abbrev()

      self.lookup_tables_reset_state_counties()

      self.lookup_tables_reset_state_name_abbrev()

   #
   def lookup_tables_reset_state_cities(self):

      log.debug('Dropping name lookup table')

      drop_sql = "DROP TABLE IF EXISTS public.state_cities CASCADE"
      self.qb.db.sql(drop_sql)

      log.debug('Creating city lookup table')

      create_sql = (
         """
         CREATE TABLE public.state_cities (
            state_city_id SERIAL PRIMARY KEY
            , state_name TEXT                -- E.g., "MN"
            , municipal_name TEXT            -- MUNI_NAME
            , population INTEGER             -- POPULATION
            , area REAL                      -- AREA
            , perimeter REAL                 -- PERIMETER
            --, id_fips INT -- FIPS (Federal Information Processing Standard)
            --, id_mcd INTEGER               -- MCD (Minor Civil Division)
            --, id_mun_ INTEGER              -- MUN_
            , mun_id INTEGER                 -- MUN_ID
         )
         """)
      self.qb.db.sql(create_sql)

      index_sql = (
         """
         CREATE INDEX state_cities_state_name
            ON state_cities (state_name)
         """)
      self.qb.db.sql(index_sql)

      index_sql = (
         """
         CREATE INDEX state_cities_municipal_name
            ON state_cities (municipal_name)
         """)
      self.qb.db.sql(index_sql)

      add_geom_sql = (
         #"""
         #SELECT AddGeometryColumn(
         #   'state_cities', 'geometry', %d, 'MULTIPOLYGON', 2)
         #""" % (conf.default_srid,))
         """
         SELECT AddGeometryColumn(
            'state_cities', 'geometry', %d, 'GEOMETRY', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS state_cities_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX state_cities_geometry ON state_cities
            USING GIST (geometry);
         """)

   #
   def lookup_tables_reset_state_city_abbrev(self):

      log.debug('Dropping city name abbreviation table')

      drop_sql = "DROP TABLE IF EXISTS public.state_city_abbrev CASCADE"
      self.qb.db.sql(drop_sql)

      log.debug('Creating city name abbreviation table')

      create_sql = (
         """
         CREATE TABLE public.state_city_abbrev (
            state_name TEXT
            , municipal_name TEXT
            , municipal_abbrev TEXT
         )
         """)
      self.qb.db.sql(create_sql)

      pkey_sql = (
         """
         ALTER TABLE state_city_abbrev
            ADD CONSTRAINT state_city_abbrev_pkey
            PRIMARY KEY (state_name, municipal_name, municipal_abbrev)
         """)
      self.qb.db.sql(pkey_sql)

   #
   def lookup_tables_reset_state_counties(self):

      log.debug('Dropping county name lookup table')

      drop_sql = "DROP TABLE IF EXISTS public.state_counties CASCADE"
      self.qb.db.sql(drop_sql)

      log.debug('Creating county name lookup table')

      # The county_num is the alphanumberic order of the county name.
      # The county_id is also in the MnDOT Shapefile, but other Shapefiles
      # use county_num exclusively...
      create_sql = (
         """
         CREATE TABLE public.state_counties (
            county_id INTEGER PRIMARY KEY
            , state_name TEXT
            , county_name TEXT
            , county_num INTEGER
            , area REAL
            , perimeter REAL
         )
         """)
      self.qb.db.sql(create_sql)

      index_sql = (
         """
         CREATE INDEX state_counties_state_name
            ON state_counties (state_name)
         """)
      self.qb.db.sql(index_sql)

      index_sql = (
         """
         CREATE INDEX state_counties_county_name
            ON state_counties (county_name)
         """)
      self.qb.db.sql(index_sql)

      add_geom_sql = (
         #"""
         #SELECT AddGeometryColumn(
         #   'state_counties', 'geometry', %d, 'MULTIPOLYGON', 2)
         #""" % (conf.default_srid,))
         """
         SELECT AddGeometryColumn(
            'state_counties', 'geometry', %d, 'GEOMETRY', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS state_counties_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX state_counties_geometry ON state_counties
            USING GIST (geometry);
         """)

   #
   def lookup_tables_reset_state_name_abbrev(self):

      log.debug('Dropping state name abbreviation table')

      drop_sql = "DROP TABLE IF EXISTS public.state_name_abbrev CASCADE"
      self.qb.db.sql(drop_sql)

      log.debug('Creating state name abbreviation table')

      create_sql = (
         """
         CREATE TABLE public.state_name_abbrev (
            state_name TEXT
            , state_abbrev TEXT
         )
         """)
      self.qb.db.sql(create_sql)

      pkey_sql = (
         """
         ALTER TABLE state_name_abbrev
            ADD CONSTRAINT state_name_abbrev_pkey
            PRIMARY KEY (state_name, state_abbrev)
         """)
      self.qb.db.sql(pkey_sql)

   #
   def lookup_tables_populate(self):

      self.state_abbrev = self.validate_state_name_and_abbrev()

      self.populate_table_city_geoms()

      self.populate_table_city_abbrevs()

      self.populate_table_county_geoms()

      self.populate_table_state_abbrevs()

   #
   def validate_state_name_and_abbrev(self):

      # *** Check that the state is valid.

      state_abbrev = self.cli_opts.citys_state.upper()
      if state_abbrev not in addressconf.States.STATE_NAMES:
         try:
            state_name = self.cli_opts.citys_state.lower()
            state_abbrev = addressconf.States.STATE_CODES[state_name].upper()
         except KeyError:
            err_s = ('Please specify a valid statename, not: %s'
                     % (self.cli_opts.citys_state,))
            log.error(err_s)
            raise Exception(err_s)

      return state_abbrev

   #
   def populate_table_city_geoms(self):

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(self.cli_opts.shp_cities, 'MUN_ID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      log.debug('Compiling city lookup insert statement')

      rows_to_insert = []

      self.shpw.gdb_layer.ResetReading()

      for feat in self.shpw.gdb_layer:

         #geoms = self.shpw.get_polygon_geoms(feat)
         #g.assurt(len(geoms) == 1)
         geom = feat.GetGeometryRef()
         g.assurt(geom is not None)

         rows_to_insert.append(
            #"('%s', %d, '%s', %d, %.5f, %.5f, ST_Multi('SRID=%d;%s'))"
            "('%s', %d, '%s', %d, %.5f, %.5f, 'SRID=%d;%s')"
            % (self.state_abbrev, # E.g., "MN"
               int(feat.GetFieldAsString('MUN_ID')),
               feat.GetFieldAsString('MUNI_NAME').lower(),
               int(feat.GetFieldAsString('POPULATION')),
               # MAYBE: Now that we store the geometry, these are just
               #        redundant calculated values...
               float(feat.GetFieldAsString('AREA')),
               float(feat.GetFieldAsString('PERIMETER')),
               conf.default_srid,
               #geoms[0].ExportToWkt(),
               geom.ExportToWkt(),
               # Skipping:
               #  int(feat.GetFieldAsString('MUN_')),
               #  int(feat.GetFieldAsString('MUN_ID')),
               #  int(feat.GetFieldAsString('FIPS')),
               #  int(feat.GetFieldAsString('MCD')),
               ))

      self.shpw.source_close()

      # END: C.f. Shapefile_Wrapper.source_open

      # *** Populate the database table.

      log.debug('Populating city lookup table')

      insert_sql = (
         """
         INSERT INTO public.state_cities (
            state_name
            , mun_id
            , municipal_name
            , population
            , area
            , perimeter
            , geometry
            ) VALUES
            %s
         """ % (','.join(rows_to_insert),))
      self.qb.db.sql(insert_sql)

   #
   def populate_table_city_abbrevs(self):

      # *** Populate the city abbreviations table.

      # FIXME: This code does not belong here...
      if self.state_abbrev == 'MN':

         # https://en.wikipedia.org/wiki/List_of_city_nicknames_in_Minnesota

         insert_sql = (
            """
            INSERT INTO public.state_city_abbrev (
               state_name
               , municipal_name
               , municipal_abbrev
               ) VALUES
                  ('MN', 'alexandria', 'alex'),
                  ('MN', 'appleton', 'app'),
                  ('MN', 'arden hills', 'a hills'),
                  ('MN', 'austin', 'spamtown'),
                  ('MN', 'austin', 'spamtown usa'),
                  ('MN', 'cannon falls', 'cann'),
                  ('MN', 'detroit lakes', 'troit'),
                  ('MN', 'east bethel', 'eb'),
                  ('MN', 'eden prairie', 'ep'),
                  ('MN', 'eden prairie', 'e.p.'),
                  ('MN', 'edina', 'bubble'),
                  ('MN', 'golden valley', 'gv'),
                  ('MN', 'marine on saint croix', 'marine'),
                  ('MN', 'marine on saint croix', 'mosc'),
                  ('MN', 'minneapolis', 'city of lakes'),
                  ('MN', 'minneapolis', 'mill city'),
                  ('MN', 'minneapolis', 'mini apple'),
                  ('MN', 'minneapolis', 'mpls'),
                  ('MN', 'minnesota city', 'mn city'),
                  ('MN', 'minnesota lake', 'mn lake'),
                  ('MN', 'minnetonka', 'mtka'),
                  ('MN', 'minnetonka beach', 'mtka beach'),
                  ('MN', 'mountain iron', 'mtn iron'),
                  ('MN', 'mountain lake', 'mtn lake'),
                  ('MN', 'north saint paul', 'north stp'),
                  ('MN', 'north saint paul', 'nstp'),
                  ('MN', 'north saint paul', 'nsp'),
                  ('MN', 'norwood young america', 'norwood'),
                  ('MN', 'norwood young america', 'young america'),
                  ('MN', 'new york mills', 'ny mills'),
                  ('MN', 'park rapids', 'prap'),
                  ('MN', 'robbinsdale', 'birdtown'),
                  ('MN', 'rochester', 'med town'),
                  ('MN', 'saint louis park', 'slp'),
                  ('MN', 'saint paul', 'pigs eye'),
                  ('MN', 'saint paul', 'stp'),
                  ('MN', 'saint paul', 'st p'),
                  ('MN', 'two harbors', '2harb'),
                  ('MN', 'warroad', 'hockeytown'),
                  ('MN', 'west saint paul', 'west stp'),
                  ('MN', 'west saint paul', 'wstp'),
                  ('MN', 'west saint paul', 'wsp'),
                  ('MN', 'worthington', 'turkey capital of the world')
            """)
         self.qb.db.sql(insert_sql)

         __verify_sql__ = (
            """
            SELECT * FROM public.state_cities AS sc
            JOIN public.state_city_abbrev AS sca
               ON (sc.municipal_name = sca.municipal_abbrev)
            """)
         rows = self.qb.db.sql(__verify_sql__)
         g.assurt(len(rows) == 0)

   #
   def populate_table_county_geoms(self):

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(self.cli_opts.shp_counties, 'COUNTY_ID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      log.debug('Compiling county lookup insert statement')

      rows_to_insert = []

      self.shpw.gdb_layer.ResetReading()

      for feat in self.shpw.gdb_layer:

         #geoms = self.shpw.get_polygon_geoms(feat)
         #g.assurt(len(geoms) == 1)
         geom = feat.GetGeometryRef()
         g.assurt(geom is not None)

         rows_to_insert.append(
            #"(%d, '%s', '%s', %d, %.5f, %.5f, ST_Multi('SRID=%d;%s'))"
            "(%d, '%s', '%s', %d, %.5f, %.5f, 'SRID=%d;%s')"
            % (int(feat.GetFieldAsString('COUNTY_ID')),
               self.state_abbrev, # E.g., "MN"
               feat.GetFieldAsString('COUNTYNAME').lower(),
               int(feat.GetFieldAsString('COUNTY_NUM')),
               # MAYBE: Since we also store the geometry, these are just
               #        redundant calculated values...
               float(feat.GetFieldAsString('AREA')),
               float(feat.GetFieldAsString('PERIMETER')),
               conf.default_srid,
               #geoms[0].ExportToWkt(),
               geom.ExportToWkt(),
               # Skipping:
               #  int(feat.GetFieldAsString('COUNTY_')),
               #  int(feat.GetFieldAsString('COUNTYFIPS')),
               #  int(feat.GetFieldAsString('FIPS')),
               ))

      self.shpw.source_close()

      # END: C.f. Shapefile_Wrapper.source_open

      # *** Populate the database table.

      log.debug('Populating county lookup table')

      insert_sql = (
         """
         INSERT INTO public.state_counties (
            county_id
            , state_name
            , county_name
            , county_num
            , area
            , perimeter
            , geometry
            ) VALUES
            %s
         """ % (','.join(rows_to_insert),))
      self.qb.db.sql(insert_sql)

   #
   def populate_table_state_abbrevs(self):

      # *** Populate the state abbreviations table.

      # FIXME: This code does not belong here...
      if self.state_abbrev == 'MN':

         # https://en.wikipedia.org/wiki/List_of_U.S._state_nicknames

         insert_sql = (
            """
            INSERT INTO public.state_name_abbrev (
               state_name
               , state_abbrev
               ) VALUES

                  ('MN', 'minnesota'),
                  ('MN', 'minn'),
                  ('MN', 'gopher state'),
                  ('MN', 'land of lakes'),
                  ('MN', 'land of 10,000 lakes'),
                  ('MN', 'land of sky-blue waters'),
                  ('MN', 'north star state'),

                  ('IA', 'hawkeye state'),

                  ('ND', 'rough rider state'),

                  ('SD', 'mount rushmore state'),
                  ('SD', 'sunshine state'),

                  ('WI', 'cheese state'),
                  ('WI', 'badger state')
            """)
         self.qb.db.sql(insert_sql)

   # ***

   #
   # This is just some sneaky code that tells us which street types (like,
   # 'ave', 'st', 'court', 'lane', etc.) should be considered stop words
   # and should be excluded from searches.
   def report_on_popular_street_types(self):

      # NOTE: This takes hundreds of msec per query! At least on [lb]'s
      #       laptop. And there are 550 Street type and Six outer loops.
      # Oct-28 16:43:31 INFO script_base # Script completed in 22.30 mins.
      enable_reporting = True
      enable_reporting = False

      street_types = addressconf.Streets.STREET_TYPES_LIST.keys()
      street_types.sort()

      debug_reporting = False
      #debug_reporting = True
      if debug_reporting:
         street_types = street_types[:20] # Just testing 20

      analyze_these = [
         ('item_versioned',   'item_versioned.name', '',),
         ('annotation',       'annotation.comments', '',),
         ('tag',              'item_versioned.name', '',),
         ('geofeature',       'item_versioned.name', 'ST_LineString',),
         ('geofeature',       'item_versioned.name', 'ST_Polygon',),
         ('geofeature',       'item_versioned.name', 'ST_Point',),
         ]

      if enable_reporting:

         for a_def in analyze_these:

            log.debug('======================================================')
            log.debug('starting analysis on: table: %s / geom: %s...'
                      % (a_def[0], a_def[2] if a_def[2] else 'n/a',))

            time_0 = time.time()

            join_maybe = ""
            if a_def[0] != 'item_versioned':
               join_maybe = (
                  "JOIN %s ON (item_versioned.system_id = %s.system_id)"
                  % (a_def[0], a_def[0],))

            where_geom = ""
            if a_def[2]:
               where_geom = ("AND ST_GeometryType(geofeature.geometry) = '%s'"
                             % (a_def[2],))

            common_stypes = {}

            for stype in street_types:

               # The postgres regex checks that the street type is its own
               # word, either in the middle of the text or at the end (so,
               # whitespace preceeding the street type, and either either
               # whitespace or EOF following the street type).
               #
               # WRONG: AND %s ~* E'\\\\s%s(\\\\s|$)'
               sql_commonest_street_types = (
                  """
                  SELECT count(*) FROM item_versioned
                  %s
                  WHERE valid_until_rid = %d
                  AND %s ~* E'(\\\\W|^)%s(?=(\\\\W|$))'
                  %s
                  """ % (join_maybe,
                         conf.rid_inf,
                         a_def[1],
                         stype,
                         where_geom,))

               rows = self.qb.db.sql(sql_commonest_street_types)
               g.assurt(len(rows) <= 1)

               if rows:
                  #common_stypes[stype] = rows[0]['count']
                  #                     top-level dict, key name, list of vals
                  misc.dict_list_append(common_stypes, rows[0]['count'], stype)

            log.debug('... elapsed time: %s'
                      % (misc.time_format_elapsed(time_0),))
            log.debug('')
            log.debug('report_on_popular_street_types: table: %s / geom: %s'
                      % (a_def[0], a_def[2] if a_def[2] else 'n/a',))
            log.debug('')
            stype_cnts = common_stypes.keys()
            stype_cnts.sort(reverse=True)
            for cnt in stype_cnts:
               log.debug('cnt: %8d / %s' % (cnt, common_stypes[cnt],))

      # 2013.10.25: Here's the current list, for the 7-county metro area,
      #             of street_type stop words with a usage count >= 99.

      # BUG nnnn: We need a better way to deal with stop words:
      #           1. Analyze all item names and count the number of
      #              times each word in a name is used.
      #           2. Change item_user_access's sql statement so
      #              LIMIT and OFFSET can be used in the inner sql?
      #              This seems hard, since the basic item sql fetch
      #              statement orders by branch_id, stack_id, version DESC.
      #              But maybe for searching geofeatures by name, for stop
      #              words, we could restrict by the user's viewport bbox.

      __blather__ = (
"""
Oct-25 01:35:19  DEBG      stwd_munis_l  #  report_on_popular_street_types: you asked for it
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    50280 / ['ave']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    34568 / ['st']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    21863 / ['via']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    17991 / ['hwy']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    16318 / ['rd']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    11017 / ['trail']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    10541 / ['dr']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     9952 / ['la']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     6754 / ['lake']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     5981 / ['blvd']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     5642 / ['park']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     5009 / ['route']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     3554 / ['ct']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     2843 / ['tr']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     2565 / ['cir']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     2487 / ['pkwy']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     2462 / ['river']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     1892 / ['creek']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     1672 / ['pl']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     1447 / ['way']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     1196 / ['path']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:     1099 / ['road']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      844 / ['gateway']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      706 / ['view']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      700 / ['ridge']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      663 / ['summit']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      568 / ['center']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      487 / ['ter']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      436 / ['bluffs']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      420 / ['hills']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      380 / ['valley']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      372 / ['hill']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      356 / ['bridge']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      336 / ['street']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      280 / ['point']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      276 / ['avenue']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      267 / ['heights']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      248 / ['highway']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      233 / ['cv']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      230 / ['shore']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      223 / ['lane']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      200 / ['grove']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      190 / ['lk']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      178 / ['rapids']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      171 / ['prairie']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      166 / ['ferry']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      161 / ['lakes']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      158 / ['drive', 'island']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      157 / ['extension']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      155 / ['dale']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      152 / ['pine']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      139 / ['parkway']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      121 / ['curve']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      120 / ['crossing', 'meadow']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      107 / ['crossroad']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      104 / ['fort']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      102 / ['loop']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:      101 / ['ln']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       99 / ['beach', 'rdg']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       97 / ['hollow']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       89 / ['brook']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       86 / ['spur']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       79 / ['club']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       77 / ['station']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       72 / ['pt']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       71 / ['forest']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       70 / ['circle']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       69 / ['dam']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       67 / ['crest']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       62 / ['glen']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       59 / ['place', 'terrace']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       58 / ['cr']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       57 / ['falls', 'rte']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       55 / ['mill']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       54 / ['bend']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       53 / ['arcade']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       52 / ['isles', 'paths']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       51 / ['court', 'trails']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       50 / ['field']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       49 / ['square']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       48 / ['cove']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       47 / ['garden']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       45 / ['bluff', 'cliff']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       43 / ['course']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       42 / ['plains']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       21 / ['haven', 'spring']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       20 / ['trl']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       18 / ['branch', 'fields', 'mountain']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       17 / ['frwy']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       15 / ['manor']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       14 / ['courts']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       13 / ['ctr', 'grn', 'tracks']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       12 / ['crescent', 'green', 'light', 'plaza', 'sq']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       11 / ['camp', 'centre', 'is', 'roads']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:       10 / ['greens']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        9 / ['meadows']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        8 / ['rest', 'springs']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        7 / ['av', 'canyon', 'corner', 'gardens', 'landing', 'tunnel', 'vista']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        6 / ['alley', 'union']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        5 / ['crt', 'lanes', 'overpass', 'pines', 'wells']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        4 / ['ally', 'rdgs']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        3 / ['bottom', 'corners', 'curv', 'lndg', 'lock', 'lodge', 'mtn', 'pike', 'pl
                                         #  ain', 'terr', 'trace', 'track', 'villiage']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        2 / ['bluf', 'brooks', 'cres', 'frt', 'holw', 'hts', 'isle', 'junction', 'kno
                                         #  lls', 'parks', 'pkway', 'stream', 'vally', 'vsta']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        1 / ['annex', 'bch', 'bypass', 'common', 'estate', 'estates', 'express', 'ext
                                         #  ', 'grv', 'harbor', 'lights', 'manors', 'oval', 'passage', 'pts', 'ranch', 'streets', 'tr
                                         #  ce', 'ville', 'well']
Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:        0 / ['allee', 'aly', 'anex', 'annx', 'anx', 'arc', 'aven', 'avenu', 'avn', 'a
                                         #  vnue', 'bayoo', 'bayou', 'bg', 'bgs', 'blf', 'blfs', 'bnd', 'bot', 'bottm', 'boul', 'boul
                                         #  v', 'br', 'brdge', 'brg', 'brk', 'brks', 'brnch', 'btm', 'burg', 'burgs', 'byp', 'bypa', 
                                         #  'bypas', 'byps', 'byu', 'canyn', 'cape', 'causeway', 'causway', 'cen', 'cent', 'centers',
                                         #   'centr', 'circ', 'circl', 'circles', 'cirs', 'ck', 'clb', 'clf', 'clfs', 'cliffs', 'cmn'
                                         #  , 'cmp', 'cnter', 'cntr', 'cnyn', 'cor', 'cors', 'coves', 'cp', 'cpe', 'crcl', 'crcle', '
                                         #  crecent', 'cresent', 'crk', 'crscnt', 'crse', 'crsent', 'crsnt', 'crssing', 'crssng', 'cs
                                         #  wy', 'ctrs', 'cts', 'cvs', 'cyn', 'div', 'divide', 'dl', 'dm', 'driv', 'drives', 'drs', '
                                         #  drv', 'dv', 'dvd', 'est', 'ests', 'exp', 'expr', 'expressway', 'expw', 'expy', 'extension
                                         #  s', 'extn', 'extnsn', 'exts', 'flat', 'fld', 'flds', 'fls', 'flt', 'flts', 'fords', 'fore
                                         #  sts', 'forg', 'forges', 'fork', 'forks', 'frd', 'frds', 'freewy', 'frg', 'frgs', 'frk', '
                                         #  frks', 'frry', 'frst', 'frway', 'ft', 'fwy', 'gardn', 'gatewy', 'gatway', 'gdn', 'gdns', 
                                         #  'glens', 'gln', 'glns', 'grden', 'grdn', 'grdns', 'grns', 'grov', 'groves', 'grvs', 'gtwa
                                         #  y', 'gtwy', 'harb', 'harbors', 'harbr', 'havn', 'hbr', 'hbrs', 'height', 'hgts', 'highwy'
                                         #  , 'hiway', 'hiwy', 'hl', 'hllw', 'hls', 'hollows', 'holws', 'hrbor', 'ht', 'hvn', 'hway',
                                         #   'inlet', 'inlt', 'islands', 'islnd', 'islnds', 'iss', 'jct', 'jction', 'jctn', 'jctns', 
                                         #  'jcts', 'junctions', 'junctn', 'juncton', 'key', 'keys', 'knl', 'knls', 'knol', 'ky', 'ky
                                         #  s', 'lck', 'lcks', 'ldg', 'ldge', 'lf', 'lgt', 'lgts', 'lks', 'lndng', 'loaf', 'locks', '
                                         #  lodg', 'loops', 'mdw', 'mdws', 'medows', 'mission', 'missn', 'ml', 'mls', 'mnr', 'mnrs', 
                                         #  'mnt', 'mntain', 'mntn', 'mntns', 'motorway', 'mountains', 'mountin', 'msn', 'mssn', 'mt'
                                         #  , 'mtin', 'mtns', 'mtwy', 'nck', 'neck', 'opas', 'orch', 'orchrd', 'ovl', 'parkways', 'pa
                                         #  rkwy', 'pikes', 'pk', 'pkwys', 'pky', 'plaines', 'pln', 'plns', 'plza', 'pne', 'pnes', 'p
                                         #  ort', 'ports', 'pr', 'prarie', 'prk', 'prr', 'prt', 'prts', 'psge', 'rad', 'radial', 'rad
                                         #  iel', 'radl', 'ranches', 'rapid', 'rdge', 'rds', 'ridges', 'riv', 'rivr', 'rnch', 'rnchs'
                                         #  , 'rpd', 'rpds', 'rst', 'rvr', 'shl', 'shls', 'shoal', 'shoals', 'shoar', 'shoars', 'shr'
                                         #  , 'shrs', 'skwy', 'skyway', 'smt', 'spg', 'spgs', 'spng', 'spngs', 'sprng', 'sprngs', 'sp
                                         #  urs', 'sqr', 'sqre', 'sqrs', 'sqs', 'squ', 'squares', 'sta', 'statn', 'stn', 'str', 'stra
                                         #  ', 'strav', 'strave', 'straven', 'stravenue', 'stravn', 'streme', 'strm', 'strt', 'strvn'
                                         #  , 'strvnue', 'sts', 'sumit', 'sumitt', 'throughway', 'tpk', 'tpke', 'traces', 'trafficway
                                         #  ', 'trak', 'trfy', 'trk', 'trks', 'trls', 'trnpk', 'trpk', 'trwy', 'tunel', 'tunl', 'tunl
                                         #  s', 'tunnels', 'tunnl', 'turnpike', 'turnpk', 'un', 'underpass', 'unions', 'uns', 'upas',
                                         #   'valleys', 'vdct', 'viadct', 'viaduct', 'views', 'vill', 'villag', 'villages', 'villg', 
                                         #  'vis', 'vist', 'vl', 'vlg', 'vlgs', 'vlly', 'vly', 'vlys', 'vst', 'vw', 'vws', 'walks', '
                                         #  wl', 'wls', 'wy', 'xing', 'xrd']
""")

   # ***

# ***

if (__name__ == '__main__'):
   smlp = Statewide_Munis_Lookup_Populate()
   smlp.go()

