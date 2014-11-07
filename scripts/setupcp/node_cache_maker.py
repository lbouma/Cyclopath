#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.



# FIXME: How does this file handle the node_id values in route_stop??




# Usage:
#
#  $ ./node_cache_maker.py --help
#
# Also:
#
#  $ ./node_cache_maker.py |& tee 2012.07.07.node_maker.txt
#
# Run this script once to create the node_endpoint and associated cache
# tables.  Be careful: if you let users edit node_endpoint attributes, i.e.,
# elevation_m, dangle_okay, etc., you'll want to update this script to alter
# table rather than drop/create.

# TIMINGS
#
# 2012.01.12: connectivity_audit script:     ==> ~ 11 mins.
# 2012.02.13: First node_endpoint script:    ==> ~  9 mins. (133873 nodes)
# 2012.07.08: Create tables, Add Internals, Vacuum, also Populate and Audit
#             ./node_cache_maker.py -C -I -V ==> 2.67 hours.
# 2012.07.13: Implemented Perf. Improvement, like Bulk Transactions
#             On pluto ([lb]'s laptop with one core and 3 Gb RAM):
#              --branch 0 --update-route     ==>  1.79 mins.
#              --branch 0 --add-internals    ==>  4.23 mins.
#              --branch 0 --populate-nodes   ==> 37.99 mins.
#             On runic: Did all three at once => 21.84 mins.
#              --branch 0 --populate-nodes   ==> 17.53 mins.
#              --branch 0 --add-internals    ==>  2.15 mins.
#              --branch 0 --update-route     ==>  0.87 mins.
#             On runic: "Metc Bikeways 2012" ==> 25.45 mins.
# 2012.08.02: Implemented --quick-nodes to copy parent nodes to new branch.
#             On pluto
#               -b "Metc Bikeways 2012" --purge-nodes --quick-nodes
#               ==> 5.65 mins.

# MAYBE: Multi-thread this script, i.e., fork a bunch of processes to do a
# handful of IDs at once? You could fetch all IDs, make one text file for
# each sub-process, and do that...
#    BUT: Would locking the database between threads be a pain?

# Bug 2565 - Distinct Node IDs Share Multiple (X,Y) Coordinates
# http://bugs.grouplens.org/show_bug.cgi?id=2565

# MAYBE: There are a lot of node_endpoints where reference_n == 0
#        and endpoint_xy is empty. We can delete these from GIA,
#        from item_versioned, and node_endpoint, etc., but that
#        still wouldn't release the stack IDs back into the pool,
#        so probably not that important... what we really need is
#        to be using GUIDs instead of stack IDs...
#        BUG nnnn: Use GUIDs instead of stack IDs (and list this
#        problem, since it would be solved by using GUIDs, since
#        deleting the rows from item_versioned would mean the
#        stack IDs are available, since I assume the system makes
#        up a GUID and then checks that it's available, as opposed
#        to how stack ID is currently implemented, which is using
#        a postgres sequence).

script_name = ('Cyclopath Node Table Maker and Populator')
# Version 1.0s: Old scripts: v052.0-02-node_endpoint.py
#                        and connectivity_audit.py.
script_version = '2.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-07-07'

# *** That's all she rote.

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
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('node_maker')

# ***

from decimal import Decimal
import gc
import signal
import socket
import time
import traceback

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from gwis.query_branch import Query_Branch
from item import item_base
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
#from item.feat import node_endpt_xy
from item.feat import node_byway
from item.feat import node_traverse
from item.feat import route
from item.grac import group
from item.link import link_attribute
from item.link import link_tag
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
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
##debug_prog_log.debug_break_loop_cnt = 10

debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)
      #
      self.groups_none_use_public = True
      #
      self.master_worker_expected = True

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      # *** First command: Drop tables and re-create them.

      self.add_argument('--create-tables', dest='create_tables',
         action='store_true', default=False,
         help='recreate the node_* tables')

      # *** If you don't want to drop tables, you can purge rows
      #     while creating node entries.

      self.add_argument('--purge-nodes', dest='purge_nodes',
         action='store_true', default=False,
         help='purge node_endpoint branch rows before operation')

      # *** Second command: Populate node_endpoint table.

      #
      self.add_argument('--populate-nodes', dest='populate_nodes',
         action='store_true', default=False,
         help='populate node_endpoint, node-for-node: this is slow')

      # 2014.02.14: This script is now multi-thread aware. You can use
      #             scripts_args' --instance-master and --instance-worker
      #             to run this script on more than just one processor core.

      # You'll generally want to make sure the node row is deleted from
      # item_versioned before inserting it. If you set this and the row
      # already exists... well, nuts to you, your script will crash.
      self.add_argument('--skip-delete', dest='skip_delete',
         action='store_true', default=False,
         help='do not bother deleting the node stack_id from item_versioned')

      #
      # FIXME: quick_nodes probably doesn't work right if last_merge_rid is not
      #        parent's latest rid.
      self.add_argument('--quick-nodes', dest='quick_nodes',
         action='store_true', default=False,
         help='populate node_endpoint for a leafy branch quickly')

      # *** Third command: Populate node_byway table.

      self.add_argument('--add-internals', dest='add_internals',
         action='store_true', default=False,
         help='update node_byway with internal vertices (non-intersections)')

      # *** Fourth command: Update calculated route table columns.
      #                     See: route.Many.node_bulk_update.

      self.add_argument('--update-route', dest='update_route',
         action='store_true', default=False,
         help='update route table: rsn_min,rsn_max,n_steps,beg_nid,fin_nid')

      # *** Fifth command: Calculate intersection confidences.
      #     FIXME: This is not implemented.

      self.add_argument('--assign-confidences', dest='assign_confidences',
         action='store_true', default=False,
         help='assign confidence to any node_endpoint used by two+ byways')

      # *** Final command: Recreate node_* table indices.

      # After all other commands are run, we can recreate table indices.
      self.add_argument('--recreate-indices', dest='recreate_indices',
         action='store_true', default=False,
         help='recreate the node_* and route table indices')

   #
   def verify_handler(self):

      ok = Ccp_Script_Args.verify_handler(self)

      if self.cli_opts.populate_nodes and self.cli_opts.quick_nodes:
         log.error(
            'Please do not specify both --populate-nodes and --quick-nodes')
         ok = False

      if self.cli_opts.purge_nodes and not (self.cli_opts.populate_nodes
                                         or self.cli_opts.quick_nodes):
         log.error(
            'Specify --populate-nodes or --quick-nodes with --purge-nodes')
         ok = False

      if self.cli_opts.quick_nodes:
         # Check that the branch is two or more deep.
         if len(self.branch_hier) < 2:
            log.error('The option --quick-nodes only works on leafy branches')
            ok = False

      return ok

# *** Node_Cache_Maker

class Node_Cache_Maker(Ccp_Script_Base):

   __slots__ = (
      'stats',
      #'another_db',
      #'target_groups',
      'bulk_shift',
      'bulk_delay',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      self.stats = {}
      #
      # This is the total no. of node_endpoints (and node_endpt_xys) created.
      #
      self.stats['node_ct_insertd'] = 0
      #
      # These are sub-counts of the total.
      #
      self.stats['node_ct_retired'] = 0 # Nodes in Current not used by byways.
      self.stats['node_ct_widowed'] = 0 # Nodes we can't find existence of.
      self.stats['node_ct_zeroish'] = 0 # Unexpected node IDs.
      self.stats['node_ct_allgood'] = 0 # Nodes in use in Current we inserted.
      self.stats['node_ct_discrep'] = 0 # Old/Existing elev. diff. from DEM.
      #
      self.stats['no_xys_examined'] = 0 # Total no. of xy coords we looked at.
      #
      # Bucketed Counts... not sure what the technical term is.
      # A count of counts, aggregated in some fashion... histogramatic?
      # I guess it's more of a Stem-and-Leaf Diagram.
      # https://en.wikipedia.org/wiki/Stemplot
      # These are stemplots!
      self.stats['byway_ct_node_ct'] = {}
      self.stats['xys_ct_node_ct'] = {}
      self.stats['rounded_dist_node_ct'] = {}

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         if self.cli_opts.create_tables:
            # Be sure to cleanup item_versioned before dropping node_* tables.
            self.purge_nodes()
            # Recreate node_endpoint and whatnot.
            self.create_tables()

         needs_revision = False
         if (self.cli_opts.populate_nodes
             or self.cli_opts.quick_nodes
             or self.cli_opts.add_internals
             or self.cli_opts.update_route
             or self.cli_opts.instance_master):
            needs_revision = True

         if needs_revision:
            self.prepare_maker()

         if self.cli_opts.populate_nodes or self.cli_opts.quick_nodes:
            if self.cli_opts.purge_nodes:
               if not self.cli_opts.create_tables:
                  self.purge_nodes()
               # else, we purged before creating the new tables.
            if self.cli_opts.populate_nodes:
               self.make_nodes()
            elif self.cli_opts.quick_nodes:
               self.quick_nodes()

         if self.cli_opts.add_internals:
            self.add_internals()

         if self.cli_opts.update_route:
            self.update_route()

         if self.cli_opts.assign_confidences:
            self.assign_confidences()

         if needs_revision:
            if self.cli_opts.instance_master:
               log.info('Waiting for Ctrl-C before finalizing revision')
               # NOTE: Cannot wait for Ctrl-C on Event. The event wait is
               #       implemented in C, so the Python interpreter blocks
               #       until it's down. So we have to sit in a loop....
               #       NOPE: Ccp_Script_Base.master_event.wait()
               while not Ccp_Script_Base.master_event.isSet():
                  Ccp_Script_Base.master_event.wait(timeout=1)
            self.finalize_maker()

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         # Release memory so Postgres has more.
         self.stats = {}
         gc.collect()

         self.cli_args.close_query(do_commit)

         if do_commit:

            time_0 = time.time()

            if self.cli_opts.recreate_indices:

               log.info('Rebuilding the node_* table indices...')

               # MAYBE: Don't use a transaction?
               #          db = db_glue.new(use_transaction=False)
               # NOTE: We don't need a table lock, do we?
               #       We're just making column indices...
               # NO: db.transaction_begin_rw('revision')
               db = db_glue.new()
               db.transaction_begin_rw()

               node_byway.Many.make_indices(db)
               node_endpoint.Many.make_indices(db)
               #node_endpt_xy.Many.make_indices(db)
               node_traverse.Many.make_indices(db)
               if self.cli_opts.update_route:
                  route.Many.make_indices(db)

               db.transaction_commit()
               db.close()

               log.debug('Rebuilt indices in %s'
                         % (misc.time_format_elapsed(time_0),))

            if self.cli_opts.purge_nodes:
               time_0 = time.time()
               #
               log.info('Vacuuming tables...')
               db = db_glue.new(use_transaction=False)
               for table in ['node_traverse',
                             'node_byway',
                             'node_endpt_xy',
                             'node_endpoint',
                             #'route',
                             ]:
                  db.sql("VACUUM ANALYZE %s" % (table,))
               db.close()
               #
               log.debug('Vacuumed in %s'
                         % (misc.time_format_elapsed(time_0),))

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)
      self.qb.filters.skip_geometry_raw = True
      self.qb.filters.skip_geometry_svg = True
      self.qb.filters.skip_geometry_wkt = False

   # ***

   #
   def cleanup_tables(self):

      g.assurt(False) # Get rid of this fcn. This is for byway_node cleanup.

      log.info('Cleaning up old tables...')

      # Use a fresh db connection, otherwise sql complains about not finding a
      # constraint (but the error doesn't name the constraint; it just prints a
      # long int).
      try:
         self.cli_args.close_query(do_commit=False)
         rebuild_qb = True
      except AttributeError:
         rebuild_qb = False
      db = db_glue.new()
      db.transaction_begin_rw()

      cleaned_up = False

      cleaned_up |= self.cleanup_old_table(db, table_name='node_traverse')
      cleaned_up |= self.cleanup_old_table(db, table_name='node_byway',
                                               just_drop=True)
      cleaned_up |= self.cleanup_old_table(db, table_name='node_endpt_xy',
                                               just_drop=True)
      cleaned_up |= self.cleanup_old_table(db, table_name='node_endpoint')
      # NOTE: Up until June 2012 node_endpoint was known as byway_node. But I
      # [lb] wanted to group all the node tables together and make better
      # names (node_byway and node_traverse are new; and node_byway is more
      # representative than byway_node: node_byway is about one-to-one
      # relationships between byways and node, whereas node_endpoint is just
      # data about nodes; node_traverse is about relationships between two
      # byways that connect at a node). Also, byway_node was used circa 2006
      # for a short-lived table that existed before node_attribute was created.
      cleaned_up |= self.cleanup_old_table(db, table_name='byway_node')
      # FIXME: Delete node_attribute eventually... after you've vetted this
      # script and are comfortable tossing node_attribute's data.

      # 2012.07.08: Just dropping the byway_node table and its entries in
      # item_versioned and group_item_access. Took: 7 mins.
      if cleaned_up:
         log.info('Committing table changes. This may take a few moments...')
         time_0 = time.time()
         # MAYBE: Use debug_skip_commit here
         db.transaction_commit()
         #
         log.debug('Committed in %s'
                   % (misc.time_format_elapsed(time_0),))

      db.close()

      # Rebuild the revisioned query.
      if rebuild_qb:
         self.query_builder_prepare()

   #
   def cleanup_old_table(self, db, table_name, just_drop=False):

      cleaned_up = False

      if db.table_exists(table_name):
         log.info('Cleaning up old table: %s.' % (table_name,))
         if not just_drop:
            self.cleanup_old_node_table(db, table_name)
         db.sql("DROP TABLE %s" % (table_name,))
         cleaned_up = True
      else:
         log.info('Skipping table; already deleted: %s.' % (table_name,))

      return cleaned_up

   #
   def cleanup_old_node_table(self, db, table_name, include_gia=True):

      g.assurt(False) # Get rid of this fcn. This is for byway_node cleanup.

      # NOTE: If you try delete-from using an inner select but you get the name
      # of the inner column wrong but it happens to match a column from the
      # table you want to delete, you're screwed -- the command works but uses
      # the wrong IDs. E.g., node_byway does not have a stack_id column, but
      # this runs:
	   #   DELETE FROM
	   #      item_versioned
	   #   WHERE
	   #      stack_id IN (SELECT DISTINCT(stack_id) FROM node_byway)
      # So be sure to specify the name of the table:
      #   WHERE
      #      stack_id IN (SELECT DISTINCT(node_byway.stack_id) FROM node_byway)

      if include_gia:
         db.sql(
            """
            DELETE FROM
               group_item_access
            WHERE
               stack_id IN (SELECT DISTINCT(%s.stack_id) FROM %s)
            """ % (table_name, table_name,))

      # We cannot delete from item_versioned while still referenced from
      # node_endpoint, so drop the constraint first.

      # FIXME: Most of these constraints aren't set on the node tables?
      db.table_drop_constraint_safe(table_name,
            '%s_system_id_fkey' % (table_name,))
      db.table_drop_constraint_safe(table_name,
            '%s_system_id_branch_id_stack_id_version_fkey' % (table_name,))
      db.table_drop_constraint_safe(table_name,
            '%s_branch_id_system_id_fkey' % (table_name,))
      db.table_drop_constraint_safe(table_name,
            '%s_branch_id_stack_id_version_fkey' % (table_name,))

      # Now we can whack from item_versioned.
      #
      # 2012.02.13: This fcn. takes a while. Over 100,000 rows, yo!
      #             DELETE 245732 / Time: 534865.878 ms
      db.sql(
         """
         DELETE FROM
            item_versioned
         WHERE
            stack_id IN (SELECT DISTINCT(%s.stack_id) FROM %s)
         """ % (table_name, table_name,))

   # ***

   #
   def purge_nodes(self):

      if self.qb.db.table_exists(table_name='node_endpoint'):

         log.info('Purging node_endpoint table and rows in item_versioned...')

         # 2012.08.02: This command can take a few minutes.
         self.qb.db.sql(
            """
            DELETE FROM
               item_versioned
            WHERE
               branch_id = %d
               AND system_id IN (
                  SELECT
                     system_id
                  FROM
                     node_endpoint
                  WHERE
                     branch_id = %d)
            """ % (self.qb.branch_hier[0][0],
                   self.qb.branch_hier[0][0],))

         # 2012.08.02: This command should be quick.
         self.qb.db.sql(
            """
            DELETE FROM
               node_endpoint
            WHERE
               branch_id = %d
            """ % (self.qb.branch_hier[0][0],))

   # ***

   #
   def create_tables(self):

      self.create_tables_drop_all()

      # 2012.01.11: We need the node_endpoint table for fixing dangles and
      # improving network connectedness. The node_traverse table is not needed
      # but we'll include it anyway so we can at least start playing around
      # with it.
      self.create_table_node_endpoint()
      self.create_table_node_endpt_xy()
      self.create_table_node_byway()
      self.create_table_node_traverse()

      # 2012.08.02: Is it true that without indices the script takes 4x as long
      #             to run? Well, that observation was from before
      #             --quick-nodes, and [lb] notes that quick_nodes searches the
      #             table for the parent's rows, so best not to drop the index
      #             once it's created, but for the initial table build? I'm
      #             still not sure why having indices matters, unless it's
      #             because node_endpoint needs to search node_byway to
      #             calculate reference_n.
      #
      node_endpoint.Many.make_indices(self.qb.db)
      #node_endpt_xy.Many.make_indices(self.qb.db)
      node_byway.Many.make_indices(self.qb.db)
      node_traverse.Many.make_indices(self.qb.db)

   #
   def create_tables_drop_all(self):

      # Start with the views.
      views_names = (
         '_nby',
         '_nde',
         )
      # And then delete the tables.
      table_names = (
         node_traverse.One.item_type_table,
         node_byway.One.item_type_table,
         #node_endpt_xy.One.item_type_table,
         'node_endpt_xy',
         node_endpoint.One.item_type_table,
         )

      do_drop_all = False
      for table_name in table_names:
         if self.qb.db.table_exists(table_name):
            do_drop_all = True
            break

      if do_drop_all:

         log.info('Dropping node tables and views...')

         time_0 = time.time()

         # 2012.08.02: Is this comment still valid?:
         # Use a fresh db connection, otherwise sql complains about not finding
         # a constraint (but the error doesn't name the constraint; it just
         # prints a long int).
         try:
            log.info('Rolling back no-op transaction...')
            g.assurt(self.cli_args.qb is not None)
            self.cli_args.close_query(do_commit=False)
            rebuild_qb = True
         except AttributeError:
            # If we're being called from make_new_branch, begin_query hasn't
            # been called and self.cli_args.qb doesn't exist.
            rebuild_qb = False
         db = db_glue.new()
         db.transaction_begin_rw()

         for view_name in views_names:
            db.sql("DROP VIEW IF EXISTS %s" % (view_name,))
         for table_name in table_names:
            db.sql("DROP TABLE IF EXISTS %s" % (table_name,))

         db.transaction_commit()

         log.debug('Dropped tables in %s'
                   % (misc.time_format_elapsed(time_0),))

         db.close()

         # Rebuild the revisioned query.
         if rebuild_qb:
            self.query_builder_prepare()

   #
   def create_table_node_endpoint(self):

      log.info('Creating table: node_endpoint.')

      #g.assurt(False)


# BUG nnnn: Add network-GUID. After loading all the endpoints, make sets() of
# byways that exist in the same network. Then, for each set, assign those nodes
# a common network-GUID. Then, when we run the route finder, we can indicate
# the island-ness.


# BUG nnnn: export/audit: find not just coincident lines,
#           but lines that share same endpoints regardless of geom

      self.qb.db.sql(
         """
         CREATE TABLE node_endpoint (

            /* == Item Versioned columns == */

            system_id INTEGER NOT NULL
            , branch_id INTEGER NOT NULL
            , stack_id INTEGER NOT NULL
            , version INTEGER NOT NULL

            /* == Byway Node columns == */

            /* *** Calculated Values. */

            /* The geometry is defined below, using PostGIS.
            , endpoint_xy SOMETHING */
            /* Number of byways which use this node. */
            , reference_n INTEGER NOT NULL DEFAULT 0
            /* A list of all the byways' stack IDs that use this node. */
            , referencers TEXT

            /* *** User-Editable Values. */

            /* Elevation, from the DEM. */
            , elevation_m REAL NOT NULL
            /* When reference_n == 1, it's a dangle. This usually
               requires a human to tell us if that's cool or not. */
            , dangle_okay BOOLEAN DEFAULT NULL
            /* When reference_n == 2, it 'has two streets'.
               If possible, we'll desegment two byways back into one,
               but sometimes the attributes are different. */
            , a_duex_rues BOOLEAN DEFAULT NULL
         )
         """)

      self.qb.db.sql(
         """
         ALTER TABLE node_endpoint
            ADD CONSTRAINT node_endpoint_pkey
            PRIMARY KEY (system_id)
         """)

      # FIXME: Eventually delete/archive node_attribute table.

   #
   def create_table_node_endpt_xy(self):

      log.info('Creating table: node_endpt_xy.')

      self.qb.db.sql(
         """
         CREATE TABLE node_endpt_xy (
            node_stack_id INTEGER NOT NULL
            /* The geometry is defined below, using PostGIS.
            , endpoint_xy SOMETHING */
         )
         """)

      self.qb.db.sql(
         """
         ALTER TABLE node_endpt_xy
            ADD CONSTRAINT node_endpt_xy_pkey
            PRIMARY KEY (node_stack_id)
         """)

      dimension = 2
      table_name = 'node_endpt_xy'
      geometry_col = 'endpoint_xy'
      self.qb.db.sql(
         """
         SELECT AddGeometryColumn(%s, %s, %s, 'POINT', %s)
         """, (table_name, geometry_col, conf.default_srid, dimension,))

   #
   def create_table_node_byway(self):

      # FIXME: Implement.

      # FIXME: Not sure we really need this table. I [lb] can't remember
      #        what I was thinking... I think it's either this table or
      #        node_endpoint.referencers.

      log.info('Creating table: node_byway.')

      self.qb.db.sql("DROP TABLE IF EXISTS node_byway")

      self.qb.db.sql(
         """
         CREATE TABLE node_byway (
            id SERIAL PRIMARY KEY
            , branch_id INTEGER NOT NULL
            , node_stack_id INTEGER DEFAULT NULL
            , byway_stack_id INTEGER NOT NULL
            /* See below for:
            , node_vertex_xy GEOMETRY */
         )
         """)

      # SYNC_ME: See the constraints script for the foreign keys and what nots.

      dimension = 2
      table_name = 'node_byway'
      geometry_col = 'node_vertex_xy'
      self.qb.db.sql(
         """
         SELECT AddGeometryColumn(%s, %s, %s, 'POINT', %s)
         """, (table_name, geometry_col, conf.default_srid, dimension,))

   #
   def create_table_node_traverse(self):

      # FIXME: node_traverse is not implemented. It's probably similar to
      # node_endpoint, in that is has one gia record for the public as editor.
      # Also, copy the code for node_endpoint above that deletes from all the
      # tables.

      log.info('Creating table: node_traverse.')

      self.qb.db.sql("DROP TABLE IF EXISTS node_traverse")

      self.qb.db.sql(
         """
         CREATE TABLE node_traverse (
            -- Item Versioned columns
            system_id INTEGER NOT NULL,
            branch_id INTEGER NOT NULL,
            stack_id INTEGER NOT NULL,
            version INTEGER NOT NULL,
            -- Node Traverse columns
            node_stack_id INTEGER NOT NULL,
            exit_stack_id INTEGER NOT NULL,
            into_stack_id INTEGER NOT NULL,
            troll_cost INTEGER
         )
         """)

      self.qb.db.sql(
         """
         ALTER TABLE node_traverse
            ADD CONSTRAINT node_traverse_pkey
            PRIMARY KEY (system_id)
         """)

      # SYNC_ME: See the constraints script for the foreign keys and what nots.

   # ***

   #
   def prepare_maker(self):

      # Get the next revision ID.
      #
      # This uses revision_peek rather than revision_create
      # in case an error occurs and we have to rollback.
      self.qb.item_mgr.start_new_revision(self.qb.db)
      log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

      if self.cli_opts.instance_worker:
         # The workers don't get any table locks, which would otherwise
         # confuse Item_Manager, so hack its flag (we'd normally instead
         # just call start_new_revision with use_latest_rid = True, but
         # the master thread hasn't committed yet, so the latest rid is
         # the wrong rid (so I guess we could instead instead get the
         # latest rid and add one... whatever)).
         self.qb.item_mgr.rid_latest_really = True
         #pass

   # ***

   # The following stats are circa October, 2011.
   #
   # There are 326,250 rows in the geofeature table.
   #    SELECT COUNT(*) FROM geofeature;
   #
   # There are 220,935 linestring (byways) in the geofeature table.
   #    SELECT COUNT(*) FROM
   #       (SELECT ST_GeometryType(geometry) FROM geofeature) AS foo
   #    WHERE st_geometrytype = 'ST_LineString';
   #
   # There are 220,935 non-null beg_node_ids.
   #    SELECT COUNT(*) FROM geofeature WHERE beg_node_id IS NOT NULL;
   # Same for beg_node_ids > 0, and for fin_nodes_ids.
   #
   # (It might also help to know that all line_strings have node IDs:
   #    SELECT COUNT(*) FROM
   #       (SELECT *, ST_GeometryType(geometry) FROM geofeature) AS foo
   #    WHERE (beg_node_id IS NULL OR fin_node_id IS NULL)
   #          AND st_geometrytype = 'ST_LineString';
   #  is 0.)
   #
   # There are 114,615 distinct beg_node_ids.
   #    SELECT COUNT(*) FROM
   #       (SELECT DISTINCT(node_id)
   #        FROM (SELECT beg_node_id AS node_id FROM geofeature) AS foo
   #        WHERE node_id > 0) AS foo;
   #
   # There are 115,095 distinct fin_node_ids.
   #    SELECT COUNT(*) FROM
   #       (SELECT DISTINCT(node_id)
   #        FROM (SELECT fin_node_id AS node_id FROM geofeature) AS foo
   #        WHERE node_id > 0) AS foo;
   #
   # There are 132,410 distinct node_ids.
   #    SELECT COUNT(*) FROM
   #       (SELECT DISTINCT(node_id)
   #        FROM (SELECT beg_node_id AS node_id FROM geofeature
   #             UNION SELECT fin_node_id AS node_id FROM geofeature) AS foo
   #        WHERE node_id > 0) AS foo;
   # or 132,411 if you include NULLs (note that UNION excludes duplicates
   # unless you use UNION ALL, so no need to distinct):
   #    SELECT COUNT(*)
   #    FROM (SELECT beg_node_id AS node_id FROM geofeature
   #          UNION SELECT fin_node_id AS node_id FROM geofeature) AS foo;

   # Triggered if self.cli_opts.populate_nodes.
   def make_nodes(self):

      # Force the DEM to load. Better to fail now than later (not that we're
      # going to fail) and it makes the debug trace look neater.
      node_endpoint.Many.node_endpoints_cache_ensure()
      #
      # A little blather about the DEM.
      # 2014.02.12: This script seems to generate a lot of DEM warnings...
      # 2014.02.12: That's because the old DEM was just the metro area...
      #             now we've got a DEM for the State of Minnesota.
      if node_endpoint.Many.elevdata is not None:
         log.debug('make_nodes: elevdata.RasterXSize: %s'
                   % (node_endpoint.Many.elevdata.RasterXSize,))
         log.debug('make_nodes: elevdata.RasterYSize: %s'
                   % (node_endpoint.Many.elevdata.RasterYSize,))

      # 2012.07.13: On runic: 0.33 mins.
      log.info('Searching for node IDs...')

      time_0 = time.time()

      #self.target_groups = {}
      #public_group_id = group.Many.public_group_id(self.qb.db)
      #self.target_groups[public_group_id] = Access_Level.editor

      # Make a clone of the db connection so we can use fetchone.
      another_db = self.qb.db.clone()
      # Start a r/w op since we might make a lookup table.
      #another_db.transaction_begin_rw()

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)

      try:

         generator = None

         # Get the node IDs from various tables.
         sql = self.node_stack_ids()

         another_db.dont_fetchall = True
         results = another_db.sql(sql)
         g.assurt(results is None)

         log.debug('Found %d node IDs and elevations in %s'
                   % (another_db.curs.rowcount,
                      misc.time_format_elapsed(time_0),))

         prog_log.loop_max = another_db.curs.rowcount

         log.info('Processing node IDs...')

         generator = another_db.get_row_iter()
         for row in generator:

            node_id = row['node_id']
            # BUG nnnn: Elevation isn't set for byways that have node stack IDs
            # that weren't saved in node_attribute. This might just be historic
            # node IDs? Anyway, just run this script on the entire byway
            # network and fix that.
            if row['elevation_m']:
               # Honor elevation_m just to conf.elev_tolerance.
               #  elevation_m = Decimal(str(row['elevation_m'])).quantize(
               #                                      conf.elev_tolerance)
               elevation_m = round(row['elevation_m'], conf.elev_precision)
               # NOTE: We probably won't use this value: if we find an
               #       elevation in the DEM, we'll always use that.
            else:
               elevation_m = None

            if node_id <= 0:
               self.stats['node_ct_zeroish'] += 1
               log.warning('make_nodes: Node ID is zero or less: %d'
                           % (node_id,))
            else:
               self.node_id_process(node_id, elevation_m)

            # Update the console.
            # 2012.07.08: Taking 2 secs. or so per 100.
            # FIXME: It seems like this operation should be faster: it's taking
            # 50 minutes to process 133,000 nodes... granted, we are searching
            # for groups of byways for each node... still, it seems like
            # something is being unnecessarily slow.
            #if prog_log.loops_inc(log_freq=250):
            if prog_log.loops_inc(log_freq=25):
               break

      finally:

         # We really only need the try/finally to avoid psycopg2 exception on
         # KeyboardInterrupt: "Cannot rollback when multiple cursors open."

         if generator is not None:
            generator.close()
            generator = None

         another_db.dont_fetchall = False
         #another_db.curs_recycle()
         another_db.close()

         prog_log.loops_fin(callee='make_nodes')

   # ***

   #
   def new_node_save(self, node_id, pt_used_ct, elevation_m, pt_xy):

      # The elevation is set unless all we have is the node ID.
      g.assurt((elevation_m is not None) or (not pt_used_ct))
      if elevation_m is not None:
         #elevation_m = str(elevation_m)
         # EXPLAIN: Aren't we re-rounding? And why add another precision?
         elevation_m = str(round(float(elevation_m), conf.elev_precision + 1))

      # node_endpt_xy.endpoint_xy stores extra precision (uses
      # conf.geom_precision, e.g., 6) whereas node_byway.node_vertex_xy
      # uses restrictive precision (conf.node_precision, e.g., 1).
      #endpoint_xy = geometry.xy_to_wkt_point_lossless(pt_xy)
      # 2012.07.30: Nuts to that, it's too confusing; these are node_endpoints'
      # geometries, so use node_precision.
      #endpoint_wkt = geometry.xy_to_wkt_point_restrict(pt_xy)
      # 2014.04.16: Make it an ewicket!
      endpoint_wkt = geometry.xy_to_ewkt_point_restrict(pt_xy)

      # Make the new node.
      new_node = node_endpoint.One(
         qb=self.qb,
         row={
            # *** from item_versioned:
            'system_id'          : None, # assigned later
            'branch_id'          : self.cli_args.branch_id,
            'stack_id'           : node_id,
            'version'            : 0,
            'deleted'            : False,
            'reverted'           : False,
            'name'               : '', # FIXME: Empty string of NULL?
            #'valid_start_rid'   : # assigned by
            #'valid_until_rid'   : #   version_finalize_and_increment
            # *** from node_endpoint:
            'reference_n'        : pt_used_ct,
            # MAYBE: Implement referencers
            'referencers'        : '',
            'dangle_okay'        : None,
            'a_duex_rues'        : None,
            'elevation_m'        : elevation_m,
            'endpoint_wkt'       : endpoint_wkt,
            })

      # Fake that we're fresh (the base class only sets it if stack_id less
      # than 0, but we're using an existing ID).
      new_node.fresh = True

      log.verbose('new_node_save: saving: %s' % (str(new_node),))

      # Save the new node.
      #
      # Set the valid_start_rid to 1 so we backfill the revision history.
      # BUG nnnn: WONTFIX: node_endpoint not correctly populated for
      #                    revisions prior to first CcpV2 release.
      # 2012.08.08: If you recreate the node table, you leave crud in
      # item_versioned, like node stack_ids referenced by byways, so be
      # destructive before being constructive.
      if not self.cli_opts.skip_delete:
         delete_sql = (
            """
            DELETE FROM
               item_versioned
            WHERE
               branch_id = %d
               AND stack_id = %d
            """ % (self.qb.branch_hier[0][0],
                   new_node.stack_id,))
         rows = self.qb.db.sql(delete_sql)
         g.assurt(rows is None)
         # Skipping: The item_stack is not populated for node_endpoints.
      #
      new_node.save_new_connection(self.qb, for_byway=None,
                                            rid_new=1,
                                            old_node_id=None)

      self.stats['node_ct_insertd'] += 1

   # ***

   #
   def node_stack_ids(self):

      # FIXME/MAYBE: This SQL seems dated.
      #              See the lookup in assign_confidences().
      
      # The node_attribute table is historic. We get the elevation from it (not
      # that we can't just get the elevation from the DEM). node_attribute is
      # only valid for the Public branch.
      select_node_attribute = ''
      if (self.qb.db.table_exists('node_attribute')
          and (self.cli_args.branch_id
               == branch.Many.public_branch_id(self.qb.db))):
         select_node_attribute = (
            """
            UNION SELECT
               node_id AS node_id
               , elevation_meters AS elevation_m
            FROM
               node_attribute
            """)

      select_node_endpoint = ''
      if self.qb.db.table_exists('node_endpoint'):
         select_node_endpoint = (
            """
            UNION SELECT
               stack_id AS node_id
               , elevation_m
            FROM
               node_endpoint
            """)

      select_node_limit = ""
      if self.cli_opts.items_limit:
         select_node_limit = "LIMIT %d" % (self.cli_opts.items_limit,)

      select_node_offset = ""
      if self.cli_opts.items_offset:
         select_node_offset = "OFFSET %d" % (self.cli_opts.items_offset,)

      # Make the query to get the list of distinct node IDs. Note that we don't
      # actually need to use DISTINCT(): UNION (as opposed to UNION ALL)
      # removes duplicates. Also, we're getting node IDs from both the
      # node_attribute table and the byway table, but these should be the same
      # lists of IDs (but we'll audit and make sure none are in one but not the
      # other).
      sql_distinct_node_ids = (
         """
         SELECT
            DISTINCT(node_id) AS node_id
           , MAX(elevation_m) AS elevation_m
         FROM
            (
            /* From geofeature */
            SELECT
               beg_node_id AS node_id
               , NULL::REAL AS elevation_m
            FROM
               geofeature
            /* From geofeature */
            UNION SELECT
               fin_node_id AS node_id
               , NULL::REAL AS elevation_m
            FROM
               geofeature
            /* From node_attribute */
            %s
            /* From node_endpoint */
            %s
            /* */
            ) AS foo
         /* The geofeature table contains other types of geometries that don't
            have node_endpoints (regions, terrain, waypoints, etc.) so ignore
            nulls. */
         WHERE
            node_id IS NOT NULL
         GROUP BY
            node_id
         ORDER BY
            node_id
         %s
         %s
         """ % (select_node_attribute,
                select_node_endpoint,
                select_node_limit,
                select_node_offset,))

      return sql_distinct_node_ids

   #
   def node_ids_from_new(self):

      sql_distinct_node_ids = (
         """
         SELECT
            node_id
            , elevation_m
         FROM
            node_endpoint
         """)

      return sql_distinct_node_ids

   # ***

   #
   def node_id_process(self, node_id, elevation_m):

      # Get the byways that share this node_id and examine their geometries.

      log.verbose('node_id_process: node_id: %d' % (node_id,))

      # PERMS WARNING: Node Endpoints are always public. But the point is moot:
      # the endpoint_xy never changes and is just a point, and it is only
      # discovered if the user has access to a byway that uses it. So our only
      # worry would be about details about node_endpoint, like elevation or
      # reference_n. We usually don't show reference_n to users -- we might
      # export it in a Shapefile, and we might use it to decide where to
      # suggest work for people (a/k/a work hints); but even if the user knows
      # the reference_n, who cares. And per elevation, that's hardly sacred, so
      # everyone should be able to read a node's elevation, and as for editing,
      # that can be controlled at the branch-level using the new_item_policy.

      sql_byways = self.find_byways_sql(node_id, allow_deleted=False)

      g.assurt(not self.qb.db.dont_fetchall)

      results = self.qb.db.sql(sql_byways)

      self.node_process_results(results, node_id, elevation_m)

   # ***

   #
   def find_byways_sql(self, node_id, allow_deleted):

      # Find the byways that use a particular node.

      g.assurt(id(self.qb.revision) == id(self.cli_args.revision))

      # The geofeature table is branch-stacked, so we may need a nested query.

      sql_byways = (
         """
         SELECT
            DISTINCT ON (iv.stack_id) iv.stack_id
            , iv.system_id
            , iv.branch_id
            , iv.version
            , iv.deleted
            , iv.reverted
            , gf.beg_node_id
            , gf.fin_node_id
            , ST_AsText(ST_StartPoint(gf.geometry)) AS pt_beg
            , ST_AsText(ST_EndPoint(gf.geometry)) AS pt_fin
            -- Need geometry_wkt for node_byway.
            , ST_AsText(gf.geometry) AS geometry_wkt
            --, ST_AsEWKT(gf.geometry) AS geometry_wkt
         FROM
            geofeature AS gf
         JOIN
            item_versioned AS iv
               USING (system_id)
         WHERE
            ((gf.beg_node_id = %d) OR (gf.fin_node_id = %d))
            AND %s -- branch and revision and last_merge_revs
         ORDER BY
            iv.stack_id ASC
            , iv.branch_id DESC
            , iv.version DESC
         """ % (node_id, node_id,
                self.qb.branch_hier_where('iv', allow_deleted=allow_deleted),
                ))

      if not allow_deleted:
         sql_byways = (
            """
            SELECT
               stack_id
               , system_id
               , branch_id
               , version
               , deleted
               , reverted
               , beg_node_id
               , fin_node_id
               , pt_beg
               , pt_fin
               , geometry_wkt
            FROM (
               %s
            ) AS foo
            WHERE
               deleted IS FALSE
            """ % (sql_byways,))

      return sql_byways

   # ***

   #
   def node_process_results(self, results, node_id, elevation_m):

      try:
         self.stats['byway_ct_node_ct'][len(results)] += 1
      except KeyError:
         self.stats['byway_ct_node_ct'][len(results)] = 1

      # EXPLAIN: MAGIC_NUMBER: 30
      if len(results) > 30:
         log.debug(' %d byways with node id %d'
                   % (len(results), node_id,))
      else:
         log.verbose(' %d byways with node id %d'
                   % (len(results), node_id,))

      if not results:
         self.stats['node_ct_retired'] += 1
         # The node_endpoint is orphaned: it's been used in previous revisions
         # but in the Current revision no byways use it.
         sql_byways = self.find_byways_sql(node_id, allow_deleted=True)
         results = self.qb.db.sql(sql_byways)
         if len(results) == 0:
            # Widowed is like retired/orphaned except we couldn't find *any*
            # prior use of the node (you'd expect to find deleted byways that
            # used to use the node ID).
            self.stats['node_ct_widowed'] += 1
         else:
            self.node_add_orphan(results, node_id, elevation_m)

      else:
         # The node_endpoint is used by at least one byway; examine its usages.
         self.node_add_active(results, node_id, elevation_m)

   #
   def node_add_orphan(self, results, node_id, elevation_m):

      # For orphans, we just need to find the endpoint_xy.

      the_pt = None

      for row in results:

         if row['beg_node_id'] == node_id:
            the_pt = row['pt_beg']
         else:
            g.assurt(row['fin_node_id'] == node_id)
            the_pt = row['pt_fin']
         the_pt = geometry.wkt_point_to_xy(the_pt,
                     precision=conf.node_precision)

         # Don't bother checking all old byways; they *should* all have the
         # same point geometry for this node... or, *most likely should*.
         break

      # MAYBE: There seem to be quite a number of these. Is that my fault or is
      # that really the case?
      log.verbose('node_add_orphan: %d' % (node_id,))

      # Update the records for this node_endpoint.
      reference_n = 0
      self.new_node_save(node_id, reference_n, elevation_m, the_pt)

   #
   def node_add_active(self, results, node_id, elevation_m):

      xys = {}

      leafy_count = 0

      self.stats['node_ct_allgood'] += 1

      # These are temporary collections to help us look at the byways that use
      # this node.
      # HINT: Search for: node_id_.
      node_id_xys_set = set()
      node_id_brs_set = set()
      node_id_xys_cts = {}

      for row in results:

         self.stats['no_xys_examined'] += 1

         if row['beg_node_id'] == node_id:
            the_pt = row['pt_beg']
         else:
            g.assurt(row['fin_node_id'] == node_id)
            the_pt = row['pt_fin']
         the_pt = geometry.wkt_point_to_xy(the_pt,
                     precision=conf.node_precision)

         # Make a fake-ish byway so we can update node_byway.
         for_byway = byway.One(qb=self.qb, row=row)
         node_byway.Many.reset_rows_for_byway(self.qb, for_byway,
                                                       for_byway.beg_node_id,
                                                       for_byway.fin_node_id)

         # The pt is raw and not Decimal()ized. We'll use precision on save.
         log.verbose('  node %09d / bway %09d / br %09d / %s'
                   % (node_id, row['system_id'], row['branch_id'], the_pt,))

         node_id_xys_set.add(the_pt)
         node_id_brs_set.add(row['branch_id'])
         misc.dict_count_inc(node_id_xys_cts, the_pt)

      xys_cts = 0
      for xys_ct in node_id_xys_cts.itervalues():
         xys_cts += xys_ct
      g.assurt(xys_cts == len(results))

      self.node_audit_xy_cts(node_id, node_id_xys_set, node_id_xys_cts)

      # Get the number of times this byway node is referenced by a byway in
      # this branch or any branch up the hier.
      reference_n = 0
      max_used_ct = 0
      use_elevation = None
      g.assurt(node_id_xys_cts)
      pts_used_iter = node_id_xys_cts.iteritems()
      for a_pt, pt_used_ct in pts_used_iter:

         # FIXME: elev. fcn should allow you to spec. DEM source?
         pt_elevation = node_endpoint.Many.elevation_get_for_pt(a_pt)
         # Honor pt_elevation just to conf.elev_tolerance.
         #  pt_elevation = Decimal(str(pt_elevation)).quantize(
         #                                   conf.elev_tolerance)
         pt_elevation = round(pt_elevation, conf.elev_precision)

         if pt_elevation is None:
            log.warning('node_add_active: No elevation for pt: %s' % (a_pt,))
            if elevation_m is not None:
               log.info('node_add_active: Using old elevation: %d / %s'
                        % (node_id, elevation_m,))
               pt_elevation = elevation_m
            # else, keep looping until maybe we find a pt with a valid elev.
         else:
            if elevation_m is not None:
               # 2012.07.29: Oops, orig. elev data (CcpV1) has 3 digits
               # precision (millimeter precision) but my first node script
               # truncated to 1 digit (decimeter) but I really want centimeter.
               # Anyway, loosening this check for now.
               # MAYBE:
               #    if abs(pt_elevation - elevation_m) > conf.elev_tolerance:
               # The *10 changes, e.g., 0.01 to 0.10
               #  if (abs(pt_elevation - elevation_m)
               #      > (conf.elev_tolerance * 10)):
               if abs(pt_elevation - elevation_m) > conf.elev_threshold:
                  self.stats['node_ct_discrep'] += 1
                  log.verbose(
                     'node_add_active: elev. mismatch: %d / old: %s / new: %s'
                     % (node_id, elevation_m, pt_elevation,))
            else:
               # 2012.07.13: In the Metc Branch, about 1 in 100 byways has
               # no elevation in node_attribute. I bet I [lb] messed up the
               # import (it is a very old branch I'm running against -- it
               # was imported six months ago, long before the import/export
               # overhaul).
               log.verbose('node_add_active: using DEM elevation: %d / %s'
                           % (node_id, pt_elevation,))

         g.assurt(pt_used_ct > 0)
         if max_used_ct < pt_used_ct:
            max_used_ct = pt_used_ct
            use_elevation = pt_elevation
            use_a_pt = a_pt
         reference_n += pt_used_ct

      if use_elevation is None:
         log.warning('node_add_active: Using average elev.: %d / %.1f'
                     % (node_id, conf.elevation_mean,))
         #use_elevation = Decimal(str(conf.elevation_mean))
         use_elevation = round(conf.elevation_mean, conf.elev_precision)

      log.verbose4('node_add_active: adding node_endpoint: %d / %s / ref_n: %s'
                   % (node_id, use_a_pt, reference_n,))
      g.assurt(reference_n > 0)

      log.verbose('node_add_active: %d' % (node_id,))

      self.new_node_save(node_id, reference_n, use_elevation, use_a_pt)

   #
   def node_audit_xy_cts(self, node_id, node_id_xys_set, node_id_xys_cts):

      # Ideally, pts_used_ct is 1, i.e., the byways that use this node_endpoint
      # all agree on the endpoint_xy. But in CcpV1, some byways that share node
      # IDs don't also share the same node ID geometry.
      pts_used_ct = len(node_id_xys_set)
      # Update the stemplot.
      try:
         self.stats['xys_ct_node_ct'][pts_used_ct] += 1
      except KeyError:
         self.stats['xys_ct_node_ct'][pts_used_ct] = 1
      # See if the node_id has a different xy from different byways.
      if pts_used_ct != 1:
         log.verbose1('node_id does not have one XY: node_id: %d / ct: %d'
                      % (node_id, pts_used_ct,))
         logged_preamble = False
         first = None
         best_pt = None
         best_ct = 0
         pts_used_iter = node_id_xys_cts.iteritems()
         for a_pt, pt_used_ct in pts_used_iter:
            #log.debug('    .. byway %09d pt: %s' % (row['system_id'], a_pt,))
            if not first:
               first = a_pt
               best_pt = a_pt
               best_ct = 1
            else:
               dist = geometry.distance(a_pt, first)
               #log.debug('      .. dist from first: %.6f' % (dist))
               g.assurt(dist > 0)
               rounded = round(dist * 1000)
               try:
                  self.stats['rounded_dist_node_ct'][rounded] += 1
               except KeyError:
                  self.stats['rounded_dist_node_ct'][rounded] = 1
               # Log a msg if more than 10 mm.
               # 2011.10.24: There are eight of these, all <= 1 meter.
               if rounded > 10:
                  if not logged_preamble:
                     logged_preamble = True
                     log.warning('_audit_xy_cts: node id: %d'
                                 % (node_id,))
                     log.warning('. first: %s' % (first,))
                  log.warning(   '. other: %s' % (a_pt,))
                  log.warning(   '.. dist: %.6f' % (dist,))
               if pt_used_ct > best_ct:
                  #log.debug(
                  #   ' .. found better pt for %09d: old cnt %d / new cnt %d'
                  #          % (node_id, best_ct, pt_used_ct,))
            # FIXME: best_pt and best_ct are not used...
            # I think I wanted to used best_pt as the xy to use if we
            # fixed those nodes that don't share the same xy...
                  best_pt = a_pt
                  best_ct = pt_used_ct

   # ***

   #
   def quick_nodes(self):

      try:

         generator = None

         # Make a clone of the db connection so we can use fetchone.
         another_qb = self.qb.clone(db_clone=True)

         prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)

         # We want the nodes for the direct ascendant.
         another_qb.branch_hier = self.qb.branch_hier[1:]
         g.assurt(another_qb.branch_hier)

         endpts = node_endpoint.Many()

         endpts.sql_clauses_cols_setup(another_qb)

         nodes_sql = endpts.search_get_sql(another_qb)

         another_qb.db.dont_fetchall = True

         time_0 = time.time()

         results = another_qb.db.sql(nodes_sql)
         g.assurt(results is None)

         log.debug('Found %d nodes in %s'
                   % (another_qb.db.curs.rowcount,
                      misc.time_format_elapsed(time_0),))

         prog_log.loop_max = another_qb.db.curs.rowcount

         log.info('Processing (quick) nodes...')

         g.assurt(self.cli_args.branch_id == self.qb.branch_hier[0][0])

         generator = another_qb.db.get_row_iter()
         for row in generator:

            parent_node = node_endpoint.One(qb=self.qb, row=row)

            leafy_node = node_endpoint.One(qb=self.qb, copy_from=parent_node)

# FIXME_2013_06_11: We should use same stack ID but we need to search
#                   node_endpt_xy and not just node_endpoint when looking
#                   for a node stack ID. (BUG nnnn?)
#
            leafy_node.stack_id = parent_node.stack_id
            leafy_node.fresh = True

            # Since we're not calling version_finalize_and_increment().
            leafy_node.valid_start_rid = self.qb.item_mgr.rid_new
            leafy_node.valid_until_rid = conf.rid_inf
            g.assurt(leafy_node.version == 0)
            leafy_node.version = 1
            # Permissions-free items have no grac records.
            g.assurt(leafy_node.groups_access is None)
            leafy_node.groups_access = {}
            leafy_node.latest_infer_id = None
            leafy_node.latest_infer_username = None
            # We haven't called save() yet, & this class doesn't use validize()
            g.assurt(not leafy_node.is_dirty())
            leafy_node.dirty_reason_add(item_base.One.dirty_reason_item_auto)
            # Since we're not using validize().
            g.assurt(not leafy_node.valid)
            leafy_node.valid = True


# FIXME_2013_06_11: This is the second place where maybe I messed up upgrade
#                   scripts.
# 2013.05.31: What did I change?!
# sql: integrity: ERROR:  duplicate key value violates ...
# This happens on MetC branch... maybe missing branch ID?
#
            leafy_node.save(self.qb, self.qb.item_mgr.rid_new)

            self.stats['node_ct_insertd'] += 1
            #self.stats['no_xys_examined'] += 1

            if prog_log.loops_inc(log_freq=1000):
               break

      finally:

         # We really only need the try/finally to avoid psycopg2 exception on
         # KeyboardInterrupt: "Cannot rollback when multiple cursors open."

         if generator is not None:
            generator.close()
            generator = None

         another_qb.db.dont_fetchall = False
         #another_qb.db.curs_recycle()
         another_qb.db.close()

         prog_log.loops_fin(callee='quick_nodes')

   # ***

   #
   def add_internals(self):

      # First cleanup existing rows: Since search_by_network returns
      # non-deleted and non-reverted byways, we won't know if there's gunk in
      # node_byway that should be removed, so we just start over.

      log.info('Resetting node_byway at branch "%s" (add_internals)'
               % (self.qb.branch_hier[0][2],))

      delete_sql = (
         "DELETE FROM node_byway WHERE branch_id = %d"
         % (self.qb.branch_hier[0][0],))
      rows = self.qb.db.sql(delete_sql)
      g.assurt(rows is None)

      # NOTE: The node_byway table is always against the Current revision.
      # NOTE: For each branch, we have to include all nodes for all byways
      #       that get fetched. This is a little different than how stacked
      #       branching is otherwise implemented. Normally, if we don't find an
      #       item in the leafiest branch, we check the parent branch at
      #       last_merge_rid. But since node_byway contains calculated values,
      #       we can't just get the parent branch's node_byway: what if a new
      #       byway in the branch connects to the parent's byway? then the
      #       parent's byway_node's reference_n is less than the actual value
      #       for the branch. As such... the node_byway table probably contains
      #       a ton of redundant information. I hope this doesn't cause
      #       postgres dump bloat...

      log.info('Updating node_byway with all vertices.')

      # keep_running is a threading.Event() we can unset to tell item_mgr to
      # stop processing, but it's only necessary for threads (see mr_do).

      # MAYBE: After populating from node_attribute, create the index?
      #        This command is slow, esp. while adding internals:
      #          ./node_cache_maker.py -C -I -V
      #        takes a minute or two (it varies) per 1,000 byways to
      #        populate the node_byway table.

      # Do bulk inserts to speed things along.
      self.bulk_shift = []
      self.bulk_delay = 10000

      time_0 = time.time()

      #prog_log = Debug_Progress_Logger(log_freq=25000)
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 2500

      # Use 'search_by_network' to get node endpoint geometries for each byway.
      log.debug('add_internals: calling load_feats_and_attcs...')
      self.qb.item_mgr.load_feats_and_attcs(self.qb, byway,
         'search_by_network', self.update_node_byway_from_byway, prog_log,
         heavyweight=False, fetch_size=0, keep_running=None)
      log.debug('add_internals: processed %d byways in %s'
                % (prog_log.progress,
                   misc.time_format_elapsed(time_0),))

      # One last bulk insert.
      if self.bulk_shift:
         node_byway.Many.insert_bulk_byways(self.qb, self.bulk_shift)
         del self.bulk_shift

   #
   def update_node_byway_from_byway(self, qb, bway, prog_log):

      #log.debug('update_node_byway_from_byway: bway: %s' % (bway,))

      g.assurt(id(qb) == id(self.qb))

      # See above; we've already cleaned up byway_node of all data pertaining
      # to this branch, so skip node_byway.Many.reset_rows_for_byway and just
      # insert.

      node_byway.Many.insert_rows_for_byway(qb, bway,
                                                bway.beg_node_id,
                                                bway.fin_node_id,
                                                self.bulk_shift)

      # We only insert every so often.
      if self.bulk_shift and (not (prog_log.progress % self.bulk_delay)):
         node_byway.Many.insert_bulk_byways(qb, self.bulk_shift)
         self.bulk_shift = []

   # ***

   #
   def update_route(self):

      log.info('Recalculating node endpoint columns in route at branch "%s"'
               % (self.qb.branch_hier[0][2],))

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 10000

      # Holy cow, using bulk update is *FAST*! Awesome!
      route.Many.update_node_stats(self.qb, all_routes=True,
                                            prog_log=prog_log)

   # ***

   #
   def assign_confidences(self):

      log.info('Recalculating node endpoint confidences for branch "%s"'
               % (self.qb.branch_hier[0][2],))

      # This is just to get a count so we can init the progress logger and also
      # alert the dev with an expected runtime.

      num_endpoints_sql = (
         """
         SELECT COUNT(stack_id) FROM (
            SELECT DISTINCT(ne.stack_id)
            FROM node_endpoint AS ne
            JOIN item_versioned AS iv
               USING (system_id)
            WHERE
               iv.valid_until_rid = %d
               AND deleted IS FALSE
            ) AS foo
         """ % (conf.rid_inf,))

      rows = self.qb.db.sql(num_endpoints_sql)

      misc.time_complain('num_endpoints_sql', time_0, 3.0, True)

      log.debug('assign_confidences: total total node endpoint count: %d'
                % (rows[0]['count'],))

      # This is a more accurate count of node endpoints (those in use for the
      # branch whose nodes are being remade).

      bw_gfl_ids = ','.join([str(x) for x in byway.Geofeature_Layer.all_gfids])

      # This is for devs to CxPx to psql for testing:
      __dev_cxpx__ = (
         """
         SELECT COUNT(node_stack_id) FROM (
            SELECT DISTINCT(gf.beg_node_id) AS node_stack_id
            FROM geofeature AS gf
            JOIN item_versioned AS iv USING (system_id)
            WHERE iv.branch_id = 2500677
              AND iv.valid_until_rid = 2000000000
              AND gf.geofeature_layer_id
                  IN (1,2,41,10,11,12,14,15,16,17,21,22,42,31)
              AND gf.beg_node_id IS NOT NULL
            UNION
            SELECT DISTINCT(gf.fin_node_id) AS node_stack_id
            FROM geofeature AS gf
            JOIN item_versioned AS iv USING (system_id)
            WHERE iv.branch_id = 2500677
              AND iv.valid_until_rid = 2000000000
              AND gf.geofeature_layer_id
                  IN (1,2,41,10,11,12,14,15,16,17,21,22,42,31)
              AND gf.beg_node_id IS NOT NULL
            ) AS foo;
         """)

      # This is what produced the previous CxPx string.
      # See also: the SQL in node_stack_ids, which unions the deprecated
      # node_attribute and also node_endpoint, but we can just get away
      # with examining geofeature and getting active node endpoint IDs.
      distinct_node_ids_sql = (
         """
         -- First UNION:
            SELECT DISTINCT(gf.beg_node_id) AS node_stack_id
            FROM geofeature AS gf
            JOIN item_versioned AS iv USING (system_id)
            WHERE iv.branch_id = %d
              AND iv.valid_until_rid = %d
              AND gf.geofeature_layer_id IN (%s)
              AND gf.beg_node_id IS NOT NULL

         -- Second UNION:
         UNION
            SELECT DISTINCT(gf.fin_node_id) AS node_stack_id
            FROM geofeature AS gf
            JOIN item_versioned AS iv USING (system_id)
            WHERE iv.branch_id = %d
              AND iv.valid_until_rid = %d
              AND gf.geofeature_layer_id IN (%s)
              AND gf.beg_node_id IS NOT NULL
         """ % (self.qb.branch_hier[0][0],
                conf.rid_inf,
                bw_gfl_ids,
                self.qb.branch_hier[0][0],
                conf.rid_inf,
                bw_gfl_ids,))
      num_endpoints_sql = (
         "SELECT COUNT(node_stack_id) FROM (%s) AS foo"
         % (distinct_node_ids_sql,))
      rows = self.qb.db.sql(num_endpoints_sql)
      misc.time_complain('num_endpoints_sql', time_0, 3.0, True)
      log.debug('assign_confidences: in-use branch node endpoint count: %d'
                % (rows[0]['count'],))

      log.info('Searching for active node IDs...')

      time_0 = time.time()

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 1
#?prog_log.log_freq = 10000
      #prog_log.loop_max = rows[0]['count']

      # Make a clone of the db connection so we can use fetchone.
      another_db = self.qb.db.clone()

      try:

         generator = None

         another_db.dont_fetchall = True
         results = another_db.sql(num_endpoints_sql)
         g.assurt(results is None)

         log.debug('Found %d node IDs in %s'
                   % (another_db.curs.rowcount,
                      misc.time_format_elapsed(time_0),))

         prog_log.loop_max = another_db.curs.rowcount

         log.info('Processing active node IDs...')

         generator = another_db.get_row_iter()
         for row in generator:

            node_id = row['node_stack_id']
            g.assurt(node_id > 0)

            __what_to_do__ = (
"""

for each node_stack_id, find a set of byways, either using the node stack ID,
or search for other node stack IDs first using the point geometry.

for each set of byways, bucket them using their gfl id:
expressway to anything but another expressway or a ramp is very suspect
a bike trail or major trail or sidewalk connecting with a highway is somewhat
   suspect, or a major road a little less so, but ignore local roads?
so, what? just make counts by gfl ID sets and assign confidence accordingly?

1. get byways for each intersection coordinate __OR__ node ID via item_mgr
   maybe node ID, since that's the logical intersection?
   if we want, we could audit two IDs at same coord, but that's something else.
2. use gfl ID and 'restricted' tab to assess confidence.
3. for controlled access to not, if it's a freeway, there is no intersection.
   Only ramps connect to non-controlled access?
   We can clean these up automatically!
   - We might want to double-check, though, since we won't know
     which is underpass and which is overpass: we can guess expressway
     is always underpass, but we should ask, too.

At least two confidence ratings:
(a.) Confidence that edges connect.
     1a. Auto-correct controlled access differences.
     2a. Ask about partial control and... anything with no control of access?
         Or maybe rank bike trails and local road confidence lower than
         major road and partial control...
     3.  Ask about bike trails and sidewalks that intersect highways or partial
         control of access roads... major roads are more confident... ignore
         local road intersection.
(b.) Confidence on what's underpass and what's overpass for non-connections.




""")


            if prog_log.loops_inc():
               break

      finally:

         if generator is not None:
            generator.close()
            generator = None

         another_db.dont_fetchall = False
         #another_db.curs_recycle()
         another_db.close()

         prog_log.loops_fin(callee='assign_confidences')

   # ***

   #
   def finalize_maker(self):

      self.stats_log()

      log.debug('Saving revision...')

      # This script uses existing stack IDs, so we shouldn't have seen a change
      # in seq_stack_id.
      g.assurt(self.qb.item_mgr.seq_stack_id is None)

      # But we can't say the same about the system ID: when making new
      # branches, we'll save the same node stack ID with the leafy branch ID
      # but we'll need a new system_id.
      # 2013.11.23: No more peeking, so that script don't need to hold on to
      # 'revision' lock forever if they're just adding new items or only
      # competing against themselves.
      #g.assurt((self.qb.item_mgr.seq_system_id is None)
      #         or (self.qb.item_mgr.seq_system_id
      #             > self.qb.db.sequence_peek_next(
      #                  'item_versioned_system_id_seq')))

      if not self.cli_opts.instance_worker:

         changenote = self.cli_opts.changenote or 'node_cache_maker'

         # Save the new revision and finalize the sequence numbers.
         group_names_or_ids = self.cli_args.group_ids
         self.finish_script_save_revision(group_names_or_ids,
                                          self.qb.username,
                                          changenote)

   # ***

   #
   def stats_log(self):

      log.info('Stats for session:')

      log.info(' >> Byway counts, or # of byways attached to each node:')
      keys = self.stats['byway_ct_node_ct'].keys()
      keys.sort()
      for byway_ct in keys:
         node_ct = self.stats['byway_ct_node_ct'][byway_ct]
         log.info('   No. of Nodes with %03d Byways: %d'
                  % (byway_ct, node_ct,))

      try:
         byway_ct_one = self.stats['byway_ct_node_ct'][1]
      except KeyError:
         byway_ct_one = 0
      byway_ct_many = 0
      for byway_ct, node_ct in self.stats['byway_ct_node_ct'].iteritems():
         if byway_ct != 1:
            byway_ct_many += node_ct
      byway_ct_all_p = float(byway_ct_one + byway_ct_many) / 100.0
      if byway_ct_all_p:
         log.info(
            ' >> Byway counts comp.: one: %d (%.2f%%) / many: %d (%.2f%%)'
            % (byway_ct_one, float(byway_ct_one) / byway_ct_all_p,
               byway_ct_many, float(byway_ct_many) / byway_ct_all_p,))

      keys = self.stats['xys_ct_node_ct'].keys()
      keys.sort()
      for xys_ct in keys:
         node_ct = self.stats['xys_ct_node_ct'][xys_ct]
         log.info('   No. of Nodes with %03d distinct XYs: %d'
                  % (xys_ct, node_ct,))

      log.info(' >> Total No. of Newly Inserted Nodes:   %d'
               % (self.stats['node_ct_insertd'],))

      log.info(' >> Subtotal: Retired Nodes')
      log.info('       a/k/a, All byways deleted:        %d'
               % (self.stats['node_ct_retired'],))

      log.info(' >> Subtotal: Orphaned (Widowed?) Nodes')
      log.info('       a/k/a, No byways located:         %d'
               % (self.stats['node_ct_widowed'],))

      log.info(' >> Subtotal: Unexpected Stack IDs:      %d'
               % (self.stats['node_ct_zeroish'],))

      log.info(' >> Subtotal: No. Active Nodes:          %d'
               % (self.stats['node_ct_allgood'],))

      log.info(' >> Subtotal: No. Nodes with Wrong Elev: %d'
               % (self.stats['node_ct_discrep'],))

      tot_xys_ct = self.stats['no_xys_examined']
      log.info(' >> Total No. of Byway Node XYs Xamined: %d'
               % (tot_xys_ct,))
      if tot_xys_ct:
         mult_xys_ct = 0
         for node_ct in self.stats['rounded_dist_node_ct'].itervalues():
            mult_xys_ct += node_ct
         log.info(
            ' >> Number of unique points sharing the same node ID: %d (%.2f%%)'
            % (mult_xys_ct, 100.0 * float(mult_xys_ct) / float(tot_xys_ct),))

      keys = self.stats['rounded_dist_node_ct'].keys()
      keys.sort()
      for dist in keys:
         node_ct = self.stats['rounded_dist_node_ct'][dist]
         log.info(
            '   No. of points w/ == node ID and dist in mm ~%04d: %d'
            % (dist, node_ct,))

   # FIXME: Use used_ct to choose best node_xy for each node_id

# ***

if (__name__ == '__main__'):
   conny_audit = Node_Cache_Maker()
   if True:
      conny_audit.go()
   else:
      conny_audit.cli_args = conny_audit.argparser()
      conny_audit.cli_opts = conny_audit.cli_args.get_opts()
      g.assurt(not self.cli_args.handled)
      conny_audit.query_builder_prepare()
      qb = conny_audit.qb
      node_endpoint.Many.find_nearby(qb, (467755, 4971254), 0.1)
      node_endpoint.Many.find_nearby(qb, (467755.002, 4971254.01), 0.1)
      node_endpoint.Many.find_nearby(qb, (467755, 4971254), 1.0)
      node_endpoint.Many.find_nearby(qb, (485358.15, 4960717.91), 0.1)

# FIXME: I think you need to use the qb, since you need the geometry from
#        a specific revision.... or........

# BUG nnnn: All 20,000 of these node's byway's geometries need to be fixed.
#           When you edit, depending on the vertex you grab, you can pull it
#           apart from the others -- I think this is flashclient's threshold
#           for if it considers geometries connected or not (when you release
#           the mouse; at other times, it uses the node ID).

# NODE 1398437: P(467755, 4971254)
# NODE 1396608: P(485358.15, 4960717.91)

#select
#   *
#, ST_AsText(gf.geometry) AS geometry_wkt
#from geofeature as gf
#join item_versioned as iv using (system_id)
#where (beg_node_id = 1396608 or fin_node_id = 1396608)
#and valid_until_rid = 2000000000;

