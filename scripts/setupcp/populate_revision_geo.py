#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./populate_revision_geo.py --help
#
#
# Run this script once after updating to CcpV2 from CcpV1 database, to populate
# geometry columns in group_revision (otherwise clients don't get
# geosummaries).

# 2013.04.02: runic: 58.80 mins.

'''

./populate_revision_geo.py

nohup ./populate_revision_geo.py | tee 2013.04.02.pop-rev.txt 2>&1 &

'''

script_name = ('Populate Cyclopath Revision Geometry')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-08-14'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
#from util_ import logging2
from util_.console import Console
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, logging.DEBUG)

log = g.log.getLogger('pop_rev_geo')

# ***

import time

from grax.access_level import Access_Level
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from gwis.query_branch import Query_Branch
from item import item_base
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
# This script varies a lot. Some older revisions' geometries tend to take
# longer to compute, so, e.g., 10 loops might take 20 seconds or 2 minutes.
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
#debug_prog_log.debug_break_loop_cnt = 10
#debug_prog_log.debug_break_loop_cnt = 15
#debug_prog_log.debug_break_loop_cnt = 25
#debug_prog_log.debug_break_loop_cnt = 50
#debug_prog_log.debug_break_loop_cnt = 100 # 2012.08.15: 2500 in 15.64 mins.

debug_skip_commit = False
#debug_skip_commit = True

# Set this to restrict revision IDs to just those specified.
debug_rev_ids = None
# 2012.08.15: Rev. 4363 / CDT ERROR: new row for relation "revision" violates
#                         check constraint "enforce_geotype_geosummary"
#             There was a error using geom_polyized instead of geom_collected
#             in ST_Multi, which produced an empty geometry, but the geometry
#             type is GEOMETRYCOLLECTION(EMPTY), but the table constraint wants
#             a MULTIPOLYGON.
#debug_rev_ids = [4363,]
# 2012.08.15: This revision only has 435 geometries but it dies with
# cycling ccpv2 [local] UPDATE: RightmostEdgeFinder.cpp:77:
#  void geos::operation::buffer::RightmostEdgeFinder::findEdge(
#  std::vector<geos::geomgraph::DirectedEdge*>*): Assertion `checked>0' failed.
#debug_rev_ids = [6253,]
#debug_rev_ids = [70,71,]

# Set this to start processing revision IDs at a specific revision (useful for
# debugging when you don't want to start the whole darn thing over).
debug_rev_ids_start = None
#debug_rev_ids_start = 4363
#debug_rev_ids_start = 6253
#debug_rev_ids_start = 16611

#
debug_rev_ids_exclude = None
# HACK: This is for the original Minneapolis/St. Paul map, which has some
# revisions that don't want to have their geosummaries computer.
if conf.instance_name == 'minnesota':
   # 2012.08.15: These stats (geoms and mins) are from 2012.08.15. If a time
   # isn't listed, it's probably because it was less than 0.20 secs. (The times
   # are from [lb]'s laptop; on runic, times are half of what's listed here.)
   debug_rev_ids_exclude = [
      #70,     # 2399 geoms. Works okay.
      #71,     # 3437 geoms. Works fine.
      133,     # 131603 geometries; freezes [lb]'s laptop and then dies.
               #                    comment: '_./import_mndot_roads.py'
      142,     # 17259 geometries; [lb] hasn't bothered to see if this actually
               #                        works, but 17K geoms sounds like a lot.
               #                    comment: '_./import_mndot_biketrails.py'
      #2207,   #  371 geoms; fine.
      #3256,   #  412 geoms; fine. 0.51 mins.
      #3857,   #  190 geoms; fine. 0.33 mins.
      #4051,   #  448 geoms; fine. 0.20 mins.
      #4363,   #  285 geoms; fine.
      #4670,   #  447 geoms; fine.
      #4686,   #  425 geoms; fine.
      #5669,   #  108 geoms; fine. 0.63 mins.
      #5670,   #  168 geoms; fine. 0.44 mins.
      #5950,   #  177 geoms; fine. 1.37 mins.
      #6104,   #    4 geoms; fine. 1.00 mins.
      #6125,   #  204 geoms; fine. 0.59 mins.
      #6134,   #   38 geoms; fine. 1.03 mins.
      #6157,   # 1712 geoms; fine. 0.24 mins.
               #     Comment: '_overlap-path-cleanup.sql Automated cleanup of
               #        bike paths which obscure other blocks'
      6253,    #  435 geoms but [lb] gets ye olde RightmostEdgeFinder.cpp:77
               #            error that findEdge "Assertion `checked>0' failed."
      #6214,   #  187 geoms; fine. 1.17 mins.
      #6216,   #  331 geoms; fine. 0.41 mins.
      #6241,   #  234 geoms; fine. 0.31 mins. 2d time: 0.24 mins.
      #6604,   #   32 geoms; fine. 1.00 mins. 2d time: < 0.20 mins.
      #6805,   #  334 geoms; fine. 1.28 mins. 2d time: 0.23 mins.
      6851,    #   62 geoms but RightmostEdgeFinder.cpp's `checked>0' failed
      #6916,   #  168 geoms; fine. 0.23 mins. 2d time: 0.25 mins.
      6926,    #   70 geoms; RightmostEdgeFinder.cpp findEdge problem...
      7125,    #  1284 geoms; findEdge problem, preceded by
               #     "EdgeRing::getRingInternal: IllegalArgumentException:
               #      Invalid number of points in LinearRing found 3 -
               #        must be 0 or >= 4"
      7369,    #  639 geoms; lots of "Invalid number of points" exceptions.
      #7409,   #  561 geoms... weird, a couple Invalid no. points exceptions
               #     but it still worked. 0.98 mins. 2d time: 0.99 mins.
               #  FIXME: EXPLAIN: Watching the trace, a lot of SQL causes the
               #           Invalid no. of points exception... so what does this
               #           geometry look like, then? And is it the bbox, the
               #           geometry, the geosummary, or what?
      7502,    #  236 geoms; lots of "Invalid number of points" exceptions.
      #        #
      # NOTE: The remaining revisions don't seem to have the findEdge
      # problem...
      # MAYBE EXPLAIN: So what's wrong with the old revisions' geometries?
      #                Is it because the version of PostGIS changed?
      #                Did it have something to do with an old version of
      #                flashclient or pyserver?
      #        #
      #7763,   #  283 geoms; fine. 0.29 mins.
      #10012,  #  193 geoms; fine. 0.21 mins.
      #10378,  # 1601 geoms; fine. 0.35 mins. :
               #     Comment '_autotagger Added 'prohibited' tag to all
               #              Expressways'
      #10510,  #  208 geoms; fine. 0.35 mins. (User's: 'Hansen Park')
      10633,   # 13990 geoms; skipping-without-testing; not worth my time...
               #     Comment: '_autotagger Applied 'hill' tag to all blocks
               #               with grade > 4%.'
      #12811,  #  287 geoms; fine.
      16478,   # 34364 geoms; Takes 0.41 mins. to get the count of geoms.
               #     Comment: "Metc Bikeways Import"
               #     MAYBE: If we called ST_Merge on subsets of the geoms
               #     would that work better? Or is the problem that we are
               #     combining all the (x,y)s into one big geometry and it just
               #     annihilates all memory? Why is this different that other
               #     revs. like rid 6851 with 62 geoms. that fail quickly?
               #     Maybe there are two issues: one is funky geometry, and the
               #     other is that lots of geometry makes for one very big
               #     object. [lb] sees Postgres using 5 Gb memory and this
               #     revision being processed for minutes and minutes...
               #     I finally killed it. MAYBE: Test on runic and see if this
               #     revision's geosummary can be computed... also see how big
               #     it is, maybe don't do the geometry or geosummary
               #     calculation depending on the number of (x,y)s...
      #16601,  #   62 geoms; 0.92 mins. 'Created new branch "..."'
               # EXPLAIN: How does creating a new branch affect 62 geometries?
      ]

# BUG nnnn: When PostGIS fails, it takes Postgresql with it, so there's no
#           way to recover, and the only way to test if it'll work is to use a
#           separate process... but you still don't want to crash Postgres, or
#           maybe it isn't crashing, but your connection is. So maybe make the
#           geometry in a work_item thread? And just log an error if it fai

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

# *** Runtime Stats
#
# 2012.08.16: Runtime stats from runic:
#    pop_rev_geo  #  Bucket results:
#    pop_rev_geo  #     No. of revs with         0 gfs:    976
#    pop_rev_geo  #     No. of revs with      1-10 gfs:  10857
#    pop_rev_geo  #     No. of revs with     .<=25 gfs:   1687
#    pop_rev_geo  #     No. of revs with    ....50 gfs:    798
#    pop_rev_geo  #     No. of revs with   ....100 gfs:    353
#    pop_rev_geo  #     No. of revs with   ....250 gfs:    171
#    pop_rev_geo  #     No. of revs with  ....1000 gfs:     12
#    pop_rev_geo  #     No. of revs with .....1601 gfs:      1
#    pop_rev_geo  #     No. of revs with .....1712 gfs:      1
#    pop_rev_geo  #     No. of revs with .....2399 gfs:      1
#    pop_rev_geo  #     No. of revs with .....3437 gfs:      1
#    pop_rev_geo  #     No. of revs with ....25943 gfs:      1
#    pop_rev_geo  #  Processed 14859 revs / 16783 group_revs / rids 2:15961.
#   argparse_ccp  #  Script completed in 26.63 mins.

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)
      #
      # E.g.,
      #  self.add_argument('--new-branch-name', dest='new_branch_name',
      #     action='store', default='', type=str,
      #     help='the name of the new branch')

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      return ok

   #
   def parse(self):
      Ccp_Script_Args.parse(self)

# *** Populate [Revision Geometries]

class Populate(Ccp_Script_Base):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def go_main(self):

      rev_id = -1
      rid_beg = -1
      n_updated_revs = 0
      n_updated_grevs = 0

      stats_bucket = {}

      self.qb.db.transaction_begin_rw()

      rev_rows = self.get_revision_rows()

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.loop_max = len(rev_rows)
      prog_log.log_freq = 25

      for rev_row in rev_rows:

         time_0 = time.time()

         rev_id = rev_row['revision_id']
         gids_str = rev_row['group_ids']
         groups_ids = [ int(x) for x in gids_str.split(',') ]

         rev_gf_count = revision.Revision.geosummary_update(
                                             self.qb.db,
                                             rev_id,
                                             self.qb.branch_hier,
                                             groups_ids,
                                             skip_geometry=False,
                                             stats_bucket=stats_bucket)

         if rid_beg < 0:
            rid_beg = rev_id
         n_updated_revs += 1
         n_updated_grevs += len(groups_ids)

         t_elapsed = (time.time() - time_0) / 60.0
         if t_elapsed > 0.20:
            log.info('Pop Rev Get: Rev ID %d / %d feats / %d grps / %s'
                     % (rev_id, rev_gf_count, len(groups_ids),
                        misc.time_format_scaled(t_elapsed)[0],))

         if prog_log.loops_inc():
            break

      rid_fin = rev_id

      prog_log.loops_fin()

      self.query_builder_destroy(do_commit=(not debug_skip_commit))

      #
      log.info('Bucket results:')
      keys = stats_bucket.keys()
      keys.sort()
      for gf_count_str in keys:
         log.info('   No. of revs with %s gfs: %6d'
                  % (gf_count_str, stats_bucket[gf_count_str],))

      #
      log.info('Processed %d revs / %d group_revs / rids %d:%d.'
               % (n_updated_revs, n_updated_grevs, rid_beg, rid_fin,))

   #
   def get_revision_rows(self):

      rid_conception = 1
      rid_conclusion = conf.rid_inf

      rev_id_restrict = ''
      if debug_rev_ids:
         rev_id_restrict += (" AND revision_id IN (%s) "
                             % (','.join([ str(x) for x in debug_rev_ids ]),))
      if debug_rev_ids_start:
         rev_id_restrict += (" AND revision_id >= %d "
                             % (debug_rev_ids_start,))
      if debug_rev_ids_exclude:
         rev_id_restrict += (" AND revision_id NOT IN (%s) "
               % (','.join([ str(x) for x in debug_rev_ids_exclude ]),))

      # MAYBE: I've seen group_concat take a while, but circa Aug 2012 for
      # 16000 revision this is real quick ([lb] saw this with an intern when
      # trying to assemble stack IDs for the tilecache cache table).
      gids_sql = (
         """
         SELECT
            revision_id
            , group_concat(group_id::TEXT) AS group_ids
         FROM
            (
            SELECT
               valid_start_rid AS revision_id
               , group_id
            FROM
               group_item_access
            GROUP BY
               valid_start_rid
               , group_id
            UNION
               SELECT
                  valid_until_rid AS revision_id
                  , group_id
               FROM
                  group_item_access
               GROUP BY
                  valid_until_rid
                  , group_id
            ) AS foo
         WHERE
            revision_id != %d
            AND revision_id != %d
            %s
         GROUP BY
            revision_id
         ORDER BY
            revision_id
         """
         % (rid_conception,
            rid_conclusion,
            rev_id_restrict,))

      rows = self.qb.db.sql(gids_sql)

      return rows

   # ***

# ***

if (__name__ == '__main__'):
   prg = Populate()
   prg.go()

