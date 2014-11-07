#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Run the scripts in schema/ necessary to bring the database schema full up to
# date (i.e., run all available scripts that have not yet been run).
#
# Note: SQL scripts are run using psql, *not* the database connection opened
# by this script. pyserver and CONFIG are ignored, so DBNAME must be specified.
#
# Usage: ./schema-upgrade.py --help
#
# Scripts should specify a schema search path to ensure they're run on the
# correct instances; see below.
#
# There are also keywords to control some script behavior:
#
#   @run-as-superuser   Run as "postgres", not "cycling".
#
#   @once-per-instance  Run once per Cyclopath instance (e.g., it's something
#                       to be done for both Colorado and Minnesota data).
#
#   @manual-upgrade     Do not run the script. Not all scripts can be run
#                       using this wrapper, and this is how that's indicated.
#
# Example script contents:
#
#   0xx-do-something.sql
#   /*
#     This script does something.
#     @run-as-superuser
#     @once-per-instance
#   */
#   BEGIN TRANSACTION;
#   SET search_path TO @@@instance@@@, public;
#   ...
#   COMMIT;

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import glob
import psycopg2
import re
import subprocess
import time
import traceback

# NOTE: This has to come before importing other Cyclopath modules, otherwise
#       g.log.getLogger returns the base Python Logger() and not our MyLogger()
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE1
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('schema-up')

# FIXME: TESTING. See logging2.config_line_format. Maybe don't word wrap.
# FIXME: For cron, this is 79.
log.debug('getTerminalSize: %d' % (Console.getTerminalSize()[0]-1,))
log.debug('os.getenv("LOGNAME"): %s' % (os.getenv('LOGNAME'),))
log.debug('os.environ.get("TERM"): %s' % (os.environ.get('TERM'),))
#Apr-20 20:40:20  DEBG         schema-up  #  getTerminalSize: 109
#Apr-20 20:40:20  DEBG         schema-up  #  os.getenv("LOGNAME"): landonb
#Apr-20 20:40:20  DEBG         schema-up  #  os.environ.get("TERM"): xterm

from util_ import db_glue
from util_ import misc
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

script_name = 'schema-upgrade.py'
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-04-18'

# E.g.,
# ERROR:  constraint "track_point_pkey" does not exist
# WARNING:  there is no transaction in progress
# WARNING:  skipping "[tbl]" --- only table or database owner can analyze it
fatal_error_re_in = (
   re.compile(r'^ERROR:'),
   re.compile(r'^WARNING:'),
   )
fatal_error_re_ex = (
   re.compile(r'^WARNING:\W+skipping \"[^\"]+\" --- only table or database owner can analyze it'),
   )

big_warning = (
'''WARNING: The last upgrade above has NOT been recorded. You
must manually reverse any partial changes before trying again.''')

error_text = '\nOne or more fatal errors or warnings detected.\n'

# FIXME: Replace yesall with, e.g., require-confirmation, or something
#        and use script exit status to look for errors and to decide to
#        continue running sql. That is, yes-all isn't what this mechanism
#        should be called, since the script is smart enough to detect errors
#        now.

# *** Cli Parser class

default_schema_dir = '../scripts/schema'

class ArgParser_Script(Ccp_Script_Args):

   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version,
                                     usage=None)

   #
   def prepare(self):
      '''Defines the CLI options for this script'''

      Ccp_Script_Args.prepare(self)

      self.add_argument('-d', '--scripts-dir', dest='scripts_dir',
         action='store', default=default_schema_dir, type=str,
         help='relative path of dir containing the schema scripts')

      self.add_argument('-I', '--run-all', dest='run_all',
         action='store_true', default=False,
         help='run all scripts, from #1, ignore upgrade_event table')

      # yesall has the same meaning as --non-interactive
      self.add_argument('-y', '--yes-all', dest='do_yesall',
         action='store_true', default=False,
         help='run all scripts without prompting (unless one fails)')

      self.add_argument('--revert', dest='do_revert',
         action='store_true', default=False,
         help='revert previous script (if revert script available)')

      self.add_argument('--noerrs', dest='do_noerrs',
         action='store_true', default=False,
         help='always ask user to check output between scripts')

      self.add_argument('--novacu', dest='do_novacu',
         action='store_true', default=False,
         help='skip vacuuming after every script (experimental)')

      self.add_argument('--dovacu', dest='do_dovacu',
         action='store_true', default=False,
         help='vacuum database after every script (experimental)')

      self.add_argument('--stopon', dest='stop_on_script',
         action='store_true', default=False,
         help='stop if the named script is next to run')

   #
   def verify(self):
      verified = Ccp_Script_Args.verify(self)

   #
   def verify_handler(self):
      # Called by verify(). If we let the base class go, it'll try verifying
      # the username, password, revision, branch id, change note, and group ID.
      # But if we're updating from V1 to V2, then the item table is missing
      # some columns, like the item 'reverted' column. And these are all unset,
      # anyway, so don't bother verifying any of these.
      # NO: Ccp_Script_Args.verify_handler(self)
      ok = True
      return ok

# ***

# Return the list of instance-specific schemas (e.g. minnesota, colorado)
def instance_list(db):

   # NOTE: See also: pyserver/conf.server_instances

   # NOTE: Order by DESC so minnesota goes before colorado, since minnesota has
   #       a higher probability of failing, since it's more populated/used.
# FIXME: For this to work, when you implement this, the previous script must be
# an instance script, i.e., on the public schema.
   # 2013.11.03: PostGIS 2.x adds a new schema: topology.
   rows = db.sql(
      """
      SELECT
         nspname
      FROM
         pg_namespace
      WHERE
             nspname NOT LIKE 'pg_%%'
         AND nspname NOT LIKE 'archive_%%'
         AND nspname NOT IN ('information_schema', 'public', 'topology')
      ORDER BY
         nspname DESC
      """)
   instances = [row['nspname'] for row in rows]
   log.debug('instance_list: found %d instances: %s.'
             % (len(instances), instances,))
   return instances

def yn_get(x):
   # If you paste commands into the terminal, i.e., you copy and paste from a
   # Wiki article to run this and other commands, when you're prompted, the
   # input is empty, so the array index raises an exception.
   try:
      got_y = (raw_input('%%% ' + x + ' (y/n) ').lower()[0] == 'y')
   except IndexError:
      #got_y = False
      raise Exception("Try again, buddy; I'm not your buddy, fhwend.")
   return got_y

class Schema_Upgrade(Ccp_Script_Base):

   #
   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      # Tell Ccp_Script_Base not to make the query builder. This prevents two
      # issues: 1. when we first run this script, the database might not be
      # CcpV2-compliant, so we won't be able to make a qb; and 2. the qb
      # starts a database transaction, and we don't want it locking our tables
      # (or we don't want to have to close the transaction in go_main).
      self.skip_query_builder = True

   # *** The 'go' method

   # This script's main() calls our base class's go(), which reads the user's
   # command line arguments and thunks to us here, at go_main().

   #
   def go_main(self):

      # NOTE: You can override the default database (set in CONFIG) if you
      #       set self.cli_opts.database, which calls db_glue.DB.set_db_name.

      log.info('Schema-upgrade started on %s...' % (db_glue.DB.db_name,))

      # This is the user's connection.
      self.db = db_glue.new()

      # This is the admin's connection.
      self.pg_db = db_glue.new(conf.db_owner, use_transaction=False)

      # This is the list of schemas.
      self.schemas = instance_list(self.db)

      # When we imported pyserver above, we switched to the pyserver directory.
      # Switch to the directory where we'll find the '[0-9][0-9][0-9]-*.sql'
      # scripts.
      log.debug('go_main: changing to dir: %s' % (self.cli_opts.scripts_dir,))
      os.chdir(self.cli_opts.scripts_dir)

      # Is the database sufficiently new for us? If not, complain.
      if (len(self.db.table_columns('upgrade_event')) == 0):
         log.error('ERROR: table upgrade_event not found.')
         log.error('Upgrade through 083-upgrade_event.sql manually.')
         sys.exit(1)

      self.recently_vacuumed = False

      script_ct = 0

      time_0 = time.time()

      try:

         self.next_script = None
         self.next_schema = None

         self.setup_next_script()

         while self.next_script:

            script_ct += 1

            self.run_script()

            # Find the next script to run and the schema to run against.
            self.setup_next_script()

         self.vacuum_finally_maybe()

      except Exception, e:

         log.info('Exception: "%s" / %s' % (e, traceback.format_exc(),))
         sys.exit(1)

      finally:

         if self.db.transaction_in_progress():
            self.db.transaction_rollback()

         self.db.close()
         self.pg_db.close()

      log.info('Ran %d schema upgrade scripts; exiting. Took: %s'
               % (script_ct,
                  misc.time_format_elapsed(time_0),))

   #
   def setup_next_script(self):

      self.last_script = self.next_script

      self.next_script = None
      self.orig_script = None

      # Ideally, we'd do some table locking to ensure that no one else is
      # manipulating the database. But this isn't manageable -- we invoke the
      # SQL scripts as separate processes, so we can't have table locks or we
      # might cause a script to deadlock (e.g., if we lock the 'revision' table
      # and then a script tries to update that table). Usually, we'll be fine:
      # we use transactions, so, worst case scenario, either the script fails
      # or a user's transaction fails. Just depends how serious your changes
      # are and whether you've used litemaint.sh to keep the site alive while
      # you update, or whether you've brought the site down with maint.sh.

      log.debug('setup_next_script: getting a rw lock...')
      self.db.transaction_begin_rw()
      # NO: revision.Revision.revision_lock_dance(
      #        self.db, caller='schema-upgrade.py')

      # The best we can do is to remind the developer if s/he forget to enter
      # maint mode.
      sql_tstamp_beg = (
         "SELECT value FROM key_value_pair WHERE key = 'cp_maint_beg'")
      rows = self.db.sql(sql_tstamp_beg)
      cp_maint_beg = None
      if rows:
         g.assurt(len(rows) == 1)
         cp_maint_beg = rows[0]['value']
      if cp_maint_beg and (cp_maint_beg != '0'):
         beg_age = misc.timestamp_age(self.db, cp_maint_beg)
         # If the cp_maint_beg is passed, it's a negative time, so
         # beg_age.days will be nonnegative, as well as beg_age.total_seconds,
         # and one or more of beg_age.min/.seconds/.microseconds might
         # also be nonzero.
         if beg_age.days >= 0:
            log.warning(
               '=============================================================')
            log.warning('The maintenance message window is still open: %s'
                        % (beg_age,))
            if not yn_get('Continue anyway?'):
               raise Exception('Aborting.')
         # else, the client message indicates we're in lite maintenance mode.
      else:
         # NOTE: If you run
         #         ./maint.sh maintenance
         #        you can disable the whole site (we show a static image
         #        and don't serve the flashclient, and the mobile app won't
         #        even try to find routes but we also just show a static,
         #        "We're down for maintenance" image and note.
         #       You can also just disable Edit mode in the application, and
         #        you can warn users ahead of time, e.g., to indicate that the
         #        site will be entering read-only mode in thirty minutes and
         #        will be in said mode for 2-1/2 hours, run,
         #         ./litemaint.sh '30 mins' '2.5 hours'
         #       If you do neither of these, this script will harrass you.
         # SYNC_ME: Search: Apache maintenance conf.
         if not os.path.exists('/etc/apache2/sites-enabled/maintenance'):
            log.warning('====================================================')
            log.warning('The maintenance msg. window is empty (cp_maint_beg).')
            if not yn_get('Continue anyway?'):
               raise Exception('Aborting.')

      # Find available scripts.
      avail = sorted(
         [i for i in glob.glob('[0-9][0-9][0-9]-*.sql')
          if i.endswith('.sql') and not i.endswith('revert.sql')])

      log.debug('setup_next_script: found %d schema scripts.' % (len(avail),))

      # Determine the script and schema to run.
      if not self.cli_opts.run_all:
         self.setup_next_script_indb(avail)
      else:
         self.setup_next_script_ooob(avail)

      if self.next_script:
         if (self.cli_opts.stop_on_script
             and (self.cli_opts.stop_on_script == self.next_script)):
            log.info('Encountered stop_on_script, stopping!')
            self.next_script = None

   #
   def setup_next_script_indb(self, avail):

      self.next_schema = None

      # Check the database to see what scripts and schemas we've already run
      rows = self.db.sql(
         """
         SELECT
            script_name, schema
         FROM
            upgrade_event
         ORDER BY id ASC
         """)
      # indb groups by script name, so the results are similar to,
      #   SELECT script_name FROM upgrade_event
      #   WHERE schema IN ('minnesota', 'public');
      indb = set([row['script_name'] for row in rows])
      tups = []
      ignored_tups = set()
      schemas_and_public = ['public',]
      schemas_and_public.extend(self.schemas)
      for row in rows:
         if row['schema'] in schemas_and_public:
            new_tup = (row['script_name'], row['schema'],)
            tups.append(new_tup)
         else:
            ignored_tups.add(row['schema'])
      if ignored_tups:
         # This happens if a dev has a so-called lite database installed
         # (for Univ of MN devs, there's a 'minnesota' and a 'colorado'
         # schema, but the lite dump only contains the minnesota schema).
         log.debug('setup_next_script_indb: skipping missing schema(s): %s'
                   % (', '.join(list(ignored_tups)),))

      # NOTE: CcpV1 scripts moved to scripts/schema/ccpv1; count those.
      # 2013.11.11: Moved the CcpV1->CcpV2 upgrade scripts to ccpv2/.
      try:
         # We've already chdir'd to scripts/schema.
         archived_scripts = sorted(
            [i for i in glob.glob('ccpv*/[0-9][0-9][0-9]-*.sql')
             if i.endswith('.sql') and not i.endswith('revert.sql')])
         archive_count = len(archived_scripts)
      except OSError, e:
         # This happens if user specifies --scripts-dir... or if we ever get
         # rid of or move the scripts/schema/ccpv1 directory...
         if self.cli_opts.scripts_dir == default_schema_dir:
            log.warning('Could not find ccpv1 subdirectory? %s' % (str(e),))
         archive_count = 0
      nscripts = archive_count + len(avail)
      log.info('Upgrade scripts: completed: %d / total: %d / remain: %d'
          % (len(indb), nscripts, nscripts - len(indb),))

      if self.cli_opts.do_revert:

         try:

            log.info('WARNING: Revert requested!!')

            self.next_script = tups[-1][0]
            self.next_schema = tups[-1][1]

            revert_script = re.sub(r'.sql$', r'-revert.sql', self.next_script)
            if os.path.exists(revert_script):
               self.orig_script = self.next_script
               self.next_script = revert_script
            else:
               log.error('Error: No revert script for %s.'
                         % (self.next_script,))
               self.next_script = None

         except KeyError:
            log.warning('Nothing to revert! No upgrade_events found.')

      else:

         # The db list of scripts already run is sorted, so iterate until you
         # find a script that hasn't been run.
         self.last_script = None
         for script in avail:
            if script not in indb:
               self.next_script = script
               break
            else:
               self.last_script = script

         if self.next_script:
            if self.last_script is not None:
               g.assurt(tups)
               last_schema = tups[-1][1]
               if ((last_schema == self.schemas[-1])
                   or (last_schema == 'public')):
                  # The last recorded script was for the last schema in the
                  # list, so we expect to be running a new script.
                  if self.last_script == self.next_script:
                     log.error('Expected to be running a new script, not %s.'
                               % (self.next_script,))
                     self.next_script = None
               else:
                  # We're still running through the schemas.
                  self.next_script = self.last_script
                  index = self.schemas.index(last_schema)
                  self.next_schema = self.schemas[index + 1]
            # else, this is our first time running a script for this script,
            #       so keep self.next_script.
         else:
            # Check that we're not still bustling through schemas.
            if tups:
               last_schema = tups[-1][1]
               if ((last_schema != self.schemas[-1])
                   and (last_schema != 'public')):
                  self.next_script = tups[-1][0]
                  index = self.schemas.index(last_schema)
                  self.next_schema = self.schemas[index + 1]

         if self.next_script:
            manual = False
            for line in open(self.next_script):
               if '@manual-upgrade' in line:
                  manual = True
                  break
            if manual:
               log.info(
                '%s must be run manually. Please see script comments for more.'
                % (self.next_script,))
               self.next_script = None

         if not self.next_script:
            # Nothing to do! All done running scripts.
            log.info('All done running scripts.')

   #
   def setup_next_script_ooob(self, avail):

      last_schema = self.next_schema
      self.next_schema = None

      g.assurt(not self.cli_opts.do_revert)

      # We're running all of the scripts. Get the next one.
      if self.last_script is None:
         self.next_script = avail[0]
      else:
         if ((last_schema == self.schemas[-1])
             or (last_schema == 'public')):
            index = avail.index(self.last_script)
            try:
               self.next_script = avail[index + 1]
            except IndexError:
               # All done
               pass
         else:
            self.next_script = self.last_script
            index = self.schemas.index(last_schema)
            self.next_schema = self.schemas[index + 1]

   #
   def run_script(self):

      g.assurt(self.next_script)

      if self.next_schema is None:
         self.next_schema = 'public'
         for line in open(self.next_script):
            if '@once-per-instance' in line:
               self.next_schema = self.schemas[0]
               break

      # Confirm
      if ((self.next_schema != 'public')
          and (self.next_schema not in conf.server_instances)):
         log.info("Not running '%s' on missing schema: '%s'"
                  % (self.next_script, self.next_schema,))
         self.db.transaction_rollback()
      elif self.cli_opts.do_yesall:
         log.info("Auto-running %s on '%s' on '%s'\n"
            % (self.next_script, self.next_schema, db_glue.DB.db_name,))
         self.run_script_()
      elif not yn_get("Run %s on '%s' on '%s' now?"
                  % (self.next_script, self.next_schema, db_glue.DB.db_name,)):
         self.db.transaction_rollback()
         raise Exception('Aborting.')
      else:
         self.run_script_()

      # Record that we ran it
      if not self.cli_opts.do_revert:
         self.db.sql(
            """
            INSERT INTO upgrade_event (script_name, schema)
            VALUES (%s, %s)
            """, (self.next_script, self.next_schema))
         log.info("Recorded successful run of %s on '%s' schema."
                  % (self.next_script, self.next_schema,))
      else:
         self.db.sql(
            """
            DELETE FROM upgrade_event
            WHERE (script_name = %s AND schema = %s)
            """, (self.orig_script, self.next_schema,))
         log.info("Recorded successful revert of %s on '%s' schema."
                  % (self.orig_script, self.next_schema,))

      # BUG nnnn: Fixed: Record successful runs of each schema script.
      # Make sure we record a successful run of each schema script.
      # This commits and recycles the cursor. We don't have to worry
      # about use_transaction because that's set on the connection.
      self.db.transaction_commit()

      # Always vacuum and analyze the database after an update.
      if (((self.cli_opts.do_dovacu)
           or (os.environ.get("TERM") != 'xterm'))
          and (not self.cli_opts.do_novacu)
          and ((self.next_schema == self.schemas[-1])
               or (self.next_schema == 'public'))):
         log.info('Vacuuming...')
         vacuum_time_0 = time.time()
         self.pg_db.sql("VACUUM ANALYZE;")
         log.info('Vacuumed database in %s'
                  % (misc.time_format_elapsed(vacuum_time_0),))
         self.recently_vacuumed = True

   #
   def run_script_(self):

      # Record the time for each script.
      instance_time_0 = time.time()

      db_user = conf.db_user
      for line in open(self.next_script):
         if '@run-as-superuser' in line:
            db_user = conf.db_owner
            break

      # Run the script
      the_cmd = ('sed s/@@@instance@@@/%s/g %s | psql -U %s -d %s'
              % (self.next_schema,
                 self.next_script,
                 db_user,
                 db_glue.DB.db_name,))
      # If the SQL fails but yesall is enabled, we'll keep running scripts,
      # which leaves the upgrade in an unknown state. For the V1->V2 upgrade
      # scripts, this means you have to restart a cron job that takes 12
      # hours to run. So how do you detect errors?  The SQL outputs ERROR:
      # and WARNING: when things are awry.  Errors are always show-stoppers;
      # Warnings not necessarily so.  Note that os.system returns 0 if the cmd
      # returns 0, otherwise something nonzero and undefined. At least that's
      # been my [lb's] observation testing a python script. As for running the
      # sed command above, the exit_status is always 0.  Fortunately, popen4
      # lets us read the output, so we can grep for problems and say no to
      # yesall. The os.system method:
      #    exit_status = os.system(the_cmd)
      #    log.info('exit_status: %s' % (exit_status,))
      # The popen4 method:
      #   (sin, sout_err) = popen2.popen4(the_cmd)
      # Which I forgot is an Oops:
      #   DeprecationWarning: The popen2 module is deprecated.
      #   Use the subprocess module.
      # So use the subprocess module:
      log.debug('run_script: Popen: the_cmd: %s'
                % (the_cmd.replace('\n', ' || '),))
      p = subprocess.Popen([the_cmd],
                           shell=True,
                           # bufsize=bufsize,
                           stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT,
                           close_fds=True)
      (sin, sout_err) = (p.stdin, p.stdout)

      error_detected = False
      while True:
         line = sout_err.readline()
         if not line:
            break
         else:
            line = line.strip()
            # Print to stdout. Don't use log, which prepends output
            #print line
            # [lb] is have interleaving issues, so trying log.
            # Also, logcheck is spewing all of this gunk. Grr.
            # But, I do like that the SQL lines are now timestamped.
            log.debug(line)
            if not error_detected:
               # See if the line matches an ERROR: or WARNING:.
               for regex_in in fatal_error_re_in:
                  #log.verbose('regex_in: %s' % (regex_in,))
                  if regex_in.search(line):
                     error_detected = True
                     # See if the WARNING: isn't fatal.
                     for regex_ex in fatal_error_re_ex:
                        #log.verbose('regex_ex: %s' % (regex_ex,))
                        if regex_ex.search(line):
                           # Ignore this false-positive
                           error_detected = False
                           break
                     # If a fatal ERROR: or WARNING:, bail.
                     if error_detected:
                        log.error(error_text)
                        break
      sin.close()
      sout_err.close()
      p.wait()
      # Display the time it took to run the script
      log.info('Ran script %s on instance %s in %s'
          % (self.next_script,
             self.next_schema,
             misc.time_format_elapsed(instance_time_0),))
      # Ask if all is well.
      # FIXME: If the grepping for errors above works, maybe get
      #        rid of yesall and asking yn_get?
      if ((error_detected and not self.cli_opts.do_noerrs)
          or (not self.cli_opts.do_yesall
              and not yn_get(
                  'Continue (i.e., was everything OK above)?'))):
         log.error('ERROR: Script failed!')
         log.error('(Check last script output for ERROR or WARNING.)')
         log.error(big_warning)
         raise Exception('Aborting: Script failed!')

   #
   def vacuum_finally_maybe(self):

      if not self.recently_vacuumed:
         do_vacuum = False
         if self.cli_opts.do_yesall:
            do_vacuum = True
            log.info('Auto-Vacuuming...')
         else:
            do_vacuum = yn_get('Vacuum database now?')
         if do_vacuum:
            vacuum_time_0 = time.time()
            self.pg_db.sql("VACUUM ANALYZE;")
            log.info('Vacuumed database in %s'
               % (misc.time_format_elapsed(vacuum_time_0),))
            self.recently_vacuumed = True

# *** Main thunk

#
if (__name__ == '__main__'):
   schup = Schema_Upgrade()
   schup.go()

