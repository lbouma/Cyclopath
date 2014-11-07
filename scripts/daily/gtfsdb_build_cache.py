#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script downloads a Google Transit Feed Specification database, builds
# it, and loads it into Cyclopath cache tables.
#
# Usage:
#
#   $ ./gtfsdb_build_cache.py -D -C
#   $ ./gtfsdb_build_cache.py
#
#
# NOTE: If this script takes a while, try 'vacuum analyze'.

script_name = 'Cyclopath Transit Feed Cache Generation Script'
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-08-31'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import datetime
import psycopg2
import re
import shutil
import subprocess
import time
import zipfile

from pkg_resources import require
require("Graphserver>=1.0.0")
from graphserver.compiler.gdb_import_gtfs import GTFSGraphCompiler
from graphserver.ext.gtfs.gtfsdb import GTFSDatabase

# Setup logging first, lest g.log.getLogger return the base Python Logger().
import logging
#from util_ import logging2
from util_.console import Console
# FIXME: Raise logging to WARNING so doesn't appear in cron output
#log_level = logging.WARNING
log_level = logging.INFO
log_level = logging.DEBUG
# FIXME: What does Console say and what happens if this script runs from a
#        terminalless process; cron?
#        2012.03.30: I think it just goes to stdout...
log_to_file = True
# Always log to console, so cron jobs can redirect output to specific logfile
# (to analyze log for ERRORs).
#log_to_console = False
log_to_console = True
log_line_len = None
# Run from cron, $TERM is not set. Run from bash, it's 'xterm'.
if ((os.environ.get('TERM') != 'dumb')
    and (os.environ.get('TERM') is not None)):
   log_to_console = True
   log_line_len = Console.getTerminalSize()[0]-1
conf.init_logging(log_to_file, log_to_console, log_line_len, log_level)

log = g.log.getLogger('gtfsdb_bld_cache')

from item.feat import branch
from item.feat import route
from item.util import ratings
from item.util import revision
import planner.routed_p2.tgraph
from util_ import db_glue
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debugging control

# Developer switches
debug_limit = None

# NOTE: debug_prog_log is not implemented for this script...
debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 2
#debug_prog_log.debug_break_loop_cnt = 10

# NOTE: debug_skip_commit is not implemented for this script...
debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      self.add_argument('-X', '--drop-table', dest='cache_table_drop',
                        default=False, action='store_true',
                        help='Drop the cache tables from the database.',)

      self.add_argument('-C', '--create-table', dest='cache_table_create',
                        default=False, action='store_true',
                        help='Create the cache tables in the database.',)

   #
   def verify(self):
      verified = Ccp_Script_Args.verify(self)
      return verified

   # ***

# *** Cache_Builder

def run_cmd(the_cmd):
   misc.run_cmd(the_cmd, outp=log.debug)

class Cache_Builder(Ccp_Script_Base):

   # In lieu of downloading the gtfs file with Python and having better access
   # to error information, we use wget and parse the output to check for
   # errors. This lookup maps wget versions to regular expressions.

   wget_not_retrieved_res = (
      (re.compile(r'^GNU Wget 1.12'),
         (re.compile(
            # NOTE: The output string from Wget contains curly quotes (which we
            #       can't show herein because Python complains):
            # Server file no newer than local file "/ccp/..." -- not retrieving
            r'^Server file no newer than local file'),
          re.compile(
            # NOTE: The output string from Wget contains curly quotes (which we
            #       can't show herein because Python complains):
            # Server file no newer than local file "/ccp/..." -- not retrieving
            r'^Remote file no newer than local file'),
         ),
      ),
   )

   gtfs_schedule_xml = 'transit_schedule_google_feed.xml'
   gtfs_calendar_txt = 'calendar.txt'

   __slots__ = (
      'dname_gtfsdb',
      'bname_transit_feed',
      'fname_transit_feed',
      'fname_transit_gdb',
      'regex_not_retrieved',
      'tfeed_not_retrieved',
      'tfeed_xmldate',
      'tfeed_calspan',
      'tfeed_zipdate',
      'cache_up_to_date',
      'revision_id',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      # E.g., /ccp/var/transit/metc/
      g.assurt(conf.transitdb_filename)
      self.dname_gtfsdb = os.path.dirname(conf.transitdb_filename)
      # E.g., ftp://gisftp.metc.state.mn.us/google_transit.zip
      source_name = conf.transit_db_source
      g.assurt(source_name)
      # E.g., gisftp.metc.state.mn.us/google_transit.zip
      (source_name, num_subs) = re.subn(r'^ftp://', r'', source_name)
      (source_name, num_subs) = re.subn(r'^http://', r'', source_name)
      # E.g., google_transit.zip
      self.bname_transit_feed = os.path.basename(source_name)
      # E.g., /ccp/var/transit/metc/google_transit.zip
      self.fname_transit_feed = os.path.join(self.dname_gtfsdb,
                                             self.bname_transit_feed)
      # E.g., /ccp/var/transit/metc/minnesota.gdb
      gserver_db_name = os.path.basename(conf.transitdb_filename)
      (gserver_db_name, num_subs) = re.subn(r'\.gtfsdb$', r'.gdb',
                                            gserver_db_name)
      self.fname_transit_gdb = os.path.join(self.dname_gtfsdb, gserver_db_name)
      # NOTE: 2011.06.15 Transit Feed
      #        -rw-rw-r--. 1 pee cyclop 285M Jun 15 15:38 minnesota.gdb
      #       Then, 2011.08.04
      #        -rw-rw-r--. 1 pee cyclop 516M Aug  9 01:31 minnesota.gdb
      #       Then, 2011.08.09? Or did I change something in the import script?
      #        -rw-rw-r--. 1 pee cyclop 743M Aug  9 02:19 minnesota.gdb
      #
      self.regex_not_retrieved = None
      self.tfeed_not_retrieved = True
      self.tfeed_xmldate = None
      self.tfeed_calspan = None
      self.tfeed_zipdate = None
      self.cache_up_to_date = False

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      log.debug('Starting')

      time_0 = time.time()

      if (self.cli_opts.cache_table_drop
          or self.cli_opts.cache_table_create):

         if self.cli_opts.cache_table_drop:
            self.gtfsdb_cache_delete()
         if self.cli_opts.cache_table_create:
            self.gtfsdb_cache_create()

         log.info('Committing transaction [go_main]')
         self.qb.db.transaction_commit()

      else:

         os.chdir(self.dname_gtfsdb)

         self.tools_check()

         # Download the transit archive.
         self.gtfs_download()
         # Get the date. There are three ways we can get it (well, there are
         # up to three different dates we can get). We use the date to compare
         # against saved archives, to know if we really need to update our
         # cache and restart the route planner (i.e., if the archive hasn't
         # changed, we can do nothing).
         self.gtfs_get_feed_dates()
         # If we really downloaded the archive, keep a copy of it.
         if not self.tfeed_not_retrieved:
            self.gtfs_archive()

         self.cache_prepare()

         # If a new transit feed was downloaded, or if the gtfs database or the
         # graphserver database are missing, rebuild the gtfs and gserver dbs.
         if ((not self.tfeed_not_retrieved)
             or (not os.path.exists(conf.transitdb_filename))
             or (not os.path.exists(self.fname_transit_gdb))):
            self.gtfsdb_compile()
            self.graphserver_import()
            self.graphserver_inspect()
         else:
            log.debug('Transit feed up-to-date; skipping compile.')

         self.files_fixperms()

         if not self.cache_up_to_date:
            self.ccp_cache_populate()
            #
            log.info('Vacuuming the database')
            db = db_glue.new(use_transaction=False)
            db.sql("VACUUM ANALYZE;")
            db.close()
         else:
            log.debug('Transit cache up-to-date; skipping cache.')

         log.debug('gtfsdb_build_cache: complete: %s'
                   % (misc.time_format_elapsed(time_0),))

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)
      # We could probably make the cache for whatever rev, but now it's just
      # for Current.
      g.assurt(isinstance(self.qb.revision, revision.Current))
      # Grab the latest revision for now.
      #self.revision_id = conf.rid_inf
      self.revision_id = revision.Revision.revision_max(self.qb.db)
      # MAYBE: Just change to Historic?
      #self.qb.revision = revision.Historic(self.revision_id)

      # FIXME/BUG nnnn: Schedule maintenance window when transit
      #                 source is updated: run script to wget -N
      #                 and see if source is new, then schedule
      #                 maintenance mode, then wait, then update.

      # 2014.09.19: Can we not do this and just assume that cron or a developer
      #             won't overlap calls to this script? We're not touching the
      #             item tables, so we don't need the revision lock.
      # Excessive/bad: revision.Revision.revision_lock_dance(
      #                  self.qb.db, caller='query_builder_prepare')
      self.qb.db.transaction_begin_rw()

   #
   def tools_check(self):
      # FIXME: Is there a better way to do this?
      the_cmd = ('wget --version')
      p = subprocess.Popen([the_cmd,],
                           shell=True,
                           # bufsize=bufsize,
                           stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT,
                           close_fds=True)
      (sin, sout_err) = (p.stdin, p.stdout)

      version_found = False
      while not version_found:
         line = sout_err.readline()
         if not line:
            break
         else:
            line = line.strip()
            for regex_tuple in Cache_Builder.wget_not_retrieved_res:
               # Check for version
               if regex_tuple[0].search(line):
                  self.regex_not_retrieved = regex_tuple[1]
                  version_found = True
                  break
      sin.close()
      sout_err.close()
      p.wait()
      if not version_found:
         log.warning('wget version not found!')
         raise Exception()

#if not retrieved, skip compilation, but still do caching -- or maybe you
#   need a master cache revision indicator, to know what revisions have been
#   cached? or, user,br,rev,+transit_date

   # ***

   #
   def gtfs_download(self):

      # E.g., wget -N --directory-prefix=$ccp/var/transit/metc/ \
      #            ftp://gisftp.metc.state.mn.us/google_transit.zip

      time_0 = time.time()

      local_dir = self.dname_gtfsdb
      remote_file = conf.transit_db_source
      g.assurt(remote_file)

      # FIXME: Instead of using wget, use internal Python functions?
      the_cmd = ('wget -N -P %s %s' % (local_dir, remote_file,))

      log.debug('gtfs_download: downloading: %s' % (the_cmd,))
      p = subprocess.Popen([the_cmd],
                           shell=True,
                           # bufsize=bufsize,
                           stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT,
                           close_fds=True)
      (sin, sout_err) = (p.stdin, p.stdout)

      self.tfeed_not_retrieved = False
      while not self.tfeed_not_retrieved:
         line = sout_err.readline()
         if not line:
            break
         else:
            line = line.strip()
            #log.debug(line)
            for regex in self.regex_not_retrieved:
               if regex.search(line):
                  self.tfeed_not_retrieved = True
                  break
            if self.tfeed_not_retrieved:
               break
      sin.close()
      sout_err.close()
      p.wait()

      log.debug('gtfs_download: %s in: %s'
          % ('downloaded' if not self.tfeed_not_retrieved else 'not retrieved',
             misc.time_format_elapsed(time_0),))

   #
   def gtfs_get_feed_dates(self):

      zfile = None

      try:

         zfile = zipfile.ZipFile(self.fname_transit_feed, 'r')

         # Try the old way: look for an XML metadata file.
         # 2012.sometime: MetC no longer supplies this.
         self.gtfs_get_xmldate(zfile)

         # Try the new way: look at the timestamp of the archive contents.
         self.gtfs_get_zipdate(zfile)

         # Try a third way: peel inside the calendar.txt file.
         # 2012.11.30: Nevermind. Just use the zipfile date.
         # Skipping: self.gtfs_get_calspan(zfile)

      except IOError, e:
         log.warning('Could not open zipfile: %s: %s'
                     % (self.fname_transit_feed, str(e),))
         raise Exception()

      finally:
         if zfile is not None:
            zfile.close()

   #
   def gtfs_get_xmldate(self, zfile):

      try:
         xml_s = zfile.read(Cache_Builder.gtfs_schedule_xml)
         as_xml = etree.XML(xml_s)
         try:
            # E.g., '20110804', from
            #       <metadata>
            #          <idinfo>
            #             <timeperd>
            #                <timeinfo>
            #                   <sngdate>
            #                      <caldate>20110804</caldate>
            #
            self.tfeed_xmldate = (as_xml.xpath('idinfo')[0]
                                          .xpath('timeperd')[0]
                                          .xpath('timeinfo')[0]
                                          .xpath('sngdate')[0]
                                          .xpath('caldate')[0].text)
         except:
            log.warning('Unknown GTFS XML file format.')
            raise Exception()
      except KeyError:
         # 2012.11.30: [lb] has tested gtfsdb_build_cache in a while, and
         # apparently Metro Council doesn't ship the XML metadata file,
         # transit_schedule_google_feed.xml.
         log.debug('gtfs_get_xmldate: XML file not found')

# BUG nnnn: Met Transit feed no longer includes XML file

   #
   def gtfs_get_zipdate(self, zfile):

      try:
         zip_info = zfile.getinfo(Cache_Builder.gtfs_calendar_txt)
         # date_time is a tuple:
         # 0 Year (>= 1980)
         # 1 Month (one-based)
         # 2 Day of month (one-based)
         # 3 Hours (zero-based)
         # 4 Minutes (zero-based)
         # 5 Seconds (zero-based)
         # E.g., (2012, 11, 28, 16, 14, 32)
         self.tfeed_zipdate = '.'.join([str(x) for x in zip_info.date_time])
         # E.g., '2012.11.28.16.14.32'
      except KeyError:
         log.warning('gtfs_get_zipdate: calendar file not found?')

   #
   def gtfs_get_calspan(self, zfile):

      # FIXME: [lb] is not sure we need to get the date this way.
      #        Using the zip date seems... adequate.

      g.assurt(False) # deprecated.

      start_date_i = 8
      final_date_i = 9

      try:
         # If the file we were reading was really large, we might want to
         # consider using extract and then going through the file line by line,
         # but the calendar.txt file is usually just a K or so, so read it into
         # memory.
         txt_s = zfile.read(Cache_Builder.gtfs_calendar_txt)
         lines = txt_s.splitlines()
         # The first line is the column header:
         # 'service_id,
         #  monday,tuesday,wednesday,thursday,friday,saturday,sunday,
         #  start_date,end_date'
         for i in xrange(1, len(lines)):
            cols = lines[i].split(',')
            # E.g., # ['SEP12-Multi-Weekday-01',
            #          '1', '1', '1', '1', '1', '0', '0',
            #          '20121128', '20121207']
            #? cols[start_date_i]
            #? cols[final_date_i]
            #? self.tfeed_calspan =
      except KeyError:
         log.warning('gtfs_get_zipdate: calendar file not found?')

   #
   def gtfs_archive(self):
      '''Make a copy of the transit feed and store it in an archival
      location.'''
      dname_dst = os.path.join(self.dname_gtfsdb, 'archive')
      if not os.path.exists(dname_dst):
         log.info('Creating transit feed archive dir.: %s' % (dname_dst,))
         # NOTE: Don't bother passing mode to mkdir; it doesn't do anything.
         os.mkdir(dname_dst)
         # 2013.05.06: Need to chmod?
         os.chmod(dname_dst, 02775)
      if os.path.isdir(dname_dst):
         # Postfix the filename with today's date, e.g., 2011_08_08
         bname_prefix, bname_ext = self.bname_transit_feed.rsplit('.', 1)
         #bname_postfix = datetime.date.today().strftime('%Y_%m_%d')
         bname_postfix = self.tfeed_zipdate
         bname_archive = ('%s-%s.%s'
                          % (bname_prefix, bname_postfix, bname_ext,))
         fname_dst = os.path.join(dname_dst, bname_archive)
         if os.path.exists(fname_dst):
            log.warning('Transit feed archive already exists!')
            #raise Exception()
         else:
            try:
               shutil.copy(self.fname_transit_feed, fname_dst)
            except IOError, e:
               log.warning('Could not archive transit feed: %s' % (str(e),))
               raise Exception()
      else:
         log.warning('Transit feed archive path exists but not a dir: %s'
                     % (dname_dst,))
         raise Exception()

   # ***

   #
   def gtfsdb_cache_delete(self):

      log.info('Dropping tables.')

      self.qb.db.sql("DROP TABLE IF EXISTS gtfsdb_cache_links")
      self.qb.db.sql("DROP TABLE IF EXISTS gtfsdb_cache_register")

   #
   def gtfsdb_cache_create(self):

      log.info('Creating tables.')

      self.qb.db.sql(
         """
         CREATE TABLE gtfsdb_cache_register (
            username TEXT,
            branch_id INTEGER,
            revision_id INTEGER,
            gtfs_caldate TEXT,
            transit_nedges INTEGER NOT NULL DEFAULT 0
         )
         """)

      self.qb.db.sql(
         """
         ALTER TABLE gtfsdb_cache_register
            ADD CONSTRAINT gtfsdb_cache_register_pkey
            PRIMARY KEY (username, branch_id, revision_id, gtfs_caldate);
         """)

      # FIXME: What does this mean?: FIXME: I'm not sure what edge is!
      self.qb.db.sql(
         """
         CREATE TABLE gtfsdb_cache_links (
            username TEXT,
            branch_id INTEGER,
            revision_id INTEGER,
            gtfs_caldate TEXT,
/* FIXME: Why is this TEXT? */
            node_stack_id TEXT,
--            node_stack_id INTEGER,
            transit_stop_id TEXT
         )
         """)

      self.qb.db.sql(
         """
         ALTER TABLE gtfsdb_cache_links
            ADD CONSTRAINT gtfsdb_cache_links_pkey
            PRIMARY KEY (username, branch_id, revision_id, gtfs_caldate,
                         node_stack_id, transit_stop_id);
         """)

   # ***

   #
   def cache_prepare(self):

      #db_cyclopath = db_glue.new()
# FIXME: Hard-coding this... maybe make cols for these?
#      username = conf.anonymous_username
#      branch_id = branch.Many.baseline_id(db_cyclopath)
#      rid_max = revision.Revision.revision_max(db_cyclopath)
#      rev = revision.Historic(rid_max)
#      qb = Item_Query_Builder(db_cyclopath, username, [branch_id,], rev)
#      Query_Overlord.finalize_query(qb)

      # If new transit feed, always update; if old trans feed, only update if
      # new revision. Also check database to see if update already performed.

      nregistered = self.cache_count_sql('gtfsdb_cache_register')

      if self.tfeed_not_retrieved:
         if nregistered == 1:
            log.debug('cache_prepare: feed not downloaded and cache exists')
         else:
            g.assurt(nregistered == 0)
            log.debug("cache_prepare: feed not dl'ed and cache does not exist")

      if nregistered == 1:
         if not self.tfeed_not_retrieved:
            log.warning("cache_prepare: feed dl'ed, but cache already exists?")
         self.cache_up_to_date = True
      else:
         g.assurt(nregistered == 0)
         log.debug('cache_prepare: feed downloaded and cache does not exist')

      # Clear the db handle for now, since the next operations take a long time

      log.info('Committing transaction [cache_prepare]')
      self.qb.db.transaction_commit()
      self.qb.db = None

   #
   def gtfsdb_compile(self):

      # E.g., gs_gtfsdb_compile google_transit.zip minnesota.gtfsdb

      the_cmd = ('gs_gtfsdb_compile %s %s' % (self.fname_transit_feed,
                                              conf.transitdb_filename))

      run_cmd(the_cmd)

      # FIXME: Parse command output for errors

      # This leaves a very large file, e.g. $ccp/var/transit/metc/minnesota.gdb

      # FIXME: The command moves old gdbs, e.g., minnesota.gdb-2011.06.15

   #
   def graphserver_import(self):

      # E.g., gs_import_gtfs minnesota.gdb minnesota.gtfsdb

      the_cmd = ('gs_import_gtfs %s %s' % (self.fname_transit_gdb,
                                           conf.transitdb_filename))

      run_cmd(the_cmd)

      # FIXME: Parse command output for errors

   #
   def graphserver_inspect(self):

      # E.g., gs_gdb_inspect minnesota.gdb sta-3622

      the_cmd = ('gs_gdb_inspect %s %s' % (self.fname_transit_gdb,
                                           'sta-3622'))

      run_cmd(the_cmd)

      # FIXME: Parse command output for errors

   #
   def files_fixperms(self):

      # E.g., fixperms --public /ccp/var/transit/metc/

      #the_cmd = ('/ccp/bin/ccpdev/bin/fixperms --public %s'
      #           % (self.dname_gtfsdb))
      the_cmd = ('/ccp/dev/cp/scripts/util/fixperms.pl --public %s/'
                 % (self.dname_gtfsdb))

      run_cmd(the_cmd)

   #
   def ccp_cache_populate(self):

      # We cleared the db handle earlier, so get a new one, and lock it.
      g.assurt_soft(self.qb.db is None)
      self.qb.db = db_glue.new()
      # FIXME: What's gtfsdb_cache_edges? Or don't we care?
      #self.qb.db.transaction_begin_rw('gtfsdb_cache_edges',
      #                                'gtfsdb_cache_links')
      # EXPLAIN: Who are we competing with? Just other instances of this
      #          script?
      locked = self.qb.db.transaction_lock_try('gtfsdb_cache_links',
                                               caller='gtfsdb_build_cache')
      g.assurt(locked)

      self.qb.db.insert(
         'gtfsdb_cache_register', {
            'username': self.qb.username,
            'branch_id': self.qb.branch_hier[0][0],
            'revision_id': self.revision_id,
            'gtfs_caldate': self.tfeed_zipdate,
         }, {})

      self.ccp_clear_cache()

      self.ccp_save_cache()

      log.info('Committing transaction [ccp_cache_populate]')
      self.qb.db.transaction_commit()
      self.qb.db.close()
      self.qb.db = None

   # A lot of the following C.f. pyserver.planner.routed_p2.tgraph.py.

   #
   def ccp_clear_cache(self):
      # NOTE: This should be a no-op, unless a developer cleared a row from
      # gtfsdb_cache_register, in which case the cache is re-populated.
      delete_criteria = {
         'username' : self.qb.username,
         'branch_id' : self.qb.branch_hier[0][0],
         'revision_id' : self.revision_id,
         }
      # FIXME: What's gtfsdb_cache_edges?
      #self.qb.db.delete('gtfsdb_cache_edges', delete_criteria)
      self.qb.db.delete('gtfsdb_cache_links', delete_criteria)

   #
   def ccp_save_cache(self):

      time_0 = time.time()

      log.debug('ccp_save_cache: loading the transit database')
      db_transit = GTFSDatabase(conf.transitdb_filename)

      # NOTE: Cannot cache edges, since they are C-objects. See usages of
      #       compiler.gtfsdb_to_edges(maxtrips). We can, however, at least
      #       count the edges....
      self.cache_edges(db_transit)

      log.debug('ccp_save_cache: making the transit graph link cache')
      self.cache_links(db_transit)

      log.debug('ccp_save_cache: done: %s'
                % (misc.time_format_elapsed(time_0),))

   # *** Helper functions: load the transit data and link with Cyclopath data.

   # Similar to: planner.routed_p2.tgraph.load_transit()
   def cache_edges(self, db_transit):

      # load the transit info
      agency_id = None
      reporter = None # sys.stdout # FIXME: Can we pass in log.debug somehow?
                                   #    I think we just need to support write()
      maxtrips = None

      # C.f. graphserver/pygs/build/lib/graphserver/compiler.py
      #         ::graph_load_gtfsdb
      log.debug('load_transit: loading compiler')
      compiler = GTFSGraphCompiler(db_transit, conf.transitdb_agency_name,
                                   agency_id, reporter)

      time_0 = time.time()
      log.debug('load_transit: loading vertices and edges')
     #for (fromv_label, tov_label, edge) in compiler.gtfsdb_to_edges(maxtrips):
      for i, (fromv_label, tov_label, edge) in enumerate(
                                          compiler.gtfsdb_to_edges(maxtrips)):
         if (i % 25000) == 0:
            log.debug('load_transit: progress: on edge # %d of unknown...'
                      % (i,))
            #log.debug(' >> fromv_label: %s / tov_label: %s / edge: %s'
            #          % (fromv_label, tov_label, edge,))
            # NOTE: fromv_label is unicode, tov_label str, and edge
            #       graphserver.core.TripBoard/TripAlight/Etc.
            # FIXME: Why is fromv_label unicode?

      self.qb.db.sql(
         """
         UPDATE
            gtfsdb_cache_register
         SET
            transit_nedges = %d
         WHERE
            username = %s
            AND branch_id = %d
            AND revision_id = %d
            AND gtfs_caldate = %s
         """ % (i + 1,
                self.qb.db.quoted(self.qb.username),
                self.qb.branch_hier[0][0],
                self.revision_id,
                self.qb.db.quoted(self.tfeed_zipdate),))

      log.debug('load_transit: loaded %d edges in %s'
                % (i + 1, misc.time_format_elapsed(time_0),))

   # C.f. graphserver/pygs/build/lib/graphserver/compiler/gdb_link_osm_gtfs
   def cache_links(self, db_transit):

      log.debug('cache_links: caching transit node/cyclopath node pairs')

      time_0 = time.time()

      # NOTE: We load all byways into the graph, including those tagged
      # 'prohibited' and 'closed', but we only ever link those not tagged as
      # such with transit stops.

      # MAGIC HACK ALERT
      #revision = revision.Historic(self.revision_id)
      #model = ratings.Predictor(self.qb.branch_hier[0][0],
      #                          #self.revision_id)
      #                          revision)
      #model.load(self.qb)
      #
      route_daemon = None
      ccp_graph = planner.routed_p2.tgraph.Trans_Graph(route_daemon,
         self.qb.username, self.qb.branch_hier, self.qb.revision)
      ccp_graph.load(self.qb.db)
      #
      tagprefs = {}
      tagprefs['prohibited'] = ratings.t_avoid
      tagprefs['closed'] = ratings.t_avoid
      #
      rating_func = ccp_graph.ratings.rating_func(self.qb.username, tagprefs,
                                                  ccp_graph)
      # MAGIC NUMBER: Min rating.
      rating_min = 0.5
      # The transit data is lat,lon, as opposed to SRID-encoded x,y.
      is_latlon = True

      n_stops = db_transit.count_stops()

      # NOTE: 2011.06.26: This loops takes a while. For me [lb], 55 secs.
      # NOTE: 2011.08.08: Find nearest node using GRAC SQL is time consuming!
      #                   On the order of minutes and minutes...
      #                   Can you cache the nearest nodes, maybe? At least for
      #                   anon user in public branch and current revision?
      #       byway.transit_stops ?? list of transit IDs?

      for i, (stop_id, stop_name, stop_lat, stop_lon) in enumerate(
                                                           db_transit.stops()):
         # Every once in a while, print a debug message
         # FIXME: Replace with prog logger
         if i and ((i % 25) == 0):
            log.debug('link_graphs: progress: on stop # %d of %d...'
                      % (i, n_stops,))
            #log.debug(' >> id: %s / name: %s / lat: %s / lon: %s'
            #          % (stop_id, stop_name, stop_lat, stop_lon,))
            #log.debug(' >> id: %s / name: %s / lat: %s / lon: %s'
            #          % (type(stop_id), type(stop_name), type(stop_lat),
            #             type(stop_lon),))
         # NOTE: The (x,y) point is lon first, then lat.
         stop_xy = (stop_lon, stop_lat,)
# 2012.03.05: This is taking wayyy tooooo long.
         nearest_byway = route.One.byway_closest_xy(
            self.qb, stop_name, stop_xy, rating_func, rating_min, is_latlon)
         nearest_node = nearest_byway.nearest_node_id()
# FIXME: What if the node is on a one-way? What if the node is tagged with
# something that the user marks 'avoid'? In both cases, transit stop might be
# Unreachable.
# 2012.01.09: Get m-value and send to client.
         if nearest_node is not None:
            node_id = str(nearest_node)
            # NOTE: If we don't cast to string, it's unicode, and db.insert
            # doesn't quote it.
            stop_id = 'sta-%s' % (str(stop_id),)
            if node_id != '':
               self.qb.db.insert(
                  'gtfsdb_cache_links', {
                     'username': self.qb.username,
                     'branch_id': self.qb.branch_hier[0][0],
                     'revision_id': self.revision_id,
                     'gtfs_caldate': self.tfeed_zipdate,

# FIXME: This is a string? See above...
                     'node_stack_id': node_id,
## Bug nnnn:
#                     'byway_m_value':

                     'transit_stop_id': stop_id,
                  }, {})
            else:
               log.warning(
                  'link_graphs: no node name?!: node_id: %s / stop_id: %s'
                  % (node_id, stop_id,))
         else:
            log.warning(
               'link_graphs: no nearest node?!: node_id: %s / stop_id: %s'
               % (node_id, stop_id,))
            log.warning(' >> lat, lon: (%s, %s)' % (stop_lat, stop_lon))
      nlinks = self.cache_count_sql('gtfsdb_cache_links')
      g.assurt(nlinks == n_stops)
      # 2011.08.08: 1570.29 secs (26 minutes)
      # 2011.08.09: 1270.86 secs (21 minutes)
      log.debug('link_graphs: linked: %d transit stops in %s'
                % (n_stops, misc.time_format_elapsed(time_0),))

   def cache_count_sql(self, table_name):
      count_sql = (
         """
         SELECT
            COUNT(*)
         FROM
            %s
         WHERE
            username = '%s'
            AND branch_id = %d
            AND revision_id = %d
            AND gtfs_caldate = '%s'
         """ % (table_name,
                self.qb.username,
                self.qb.branch_hier[0][0],
                self.revision_id,
                self.tfeed_zipdate,))
      return self.qb.db.sql(count_sql)[0]['count']

# ***

if (__name__ == '__main__'):
   cb = Cache_Builder()
   cb.go()

