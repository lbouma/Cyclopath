#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script processes pending item watcher emails.
#
# DEVs: Schedule the wrapper, watchers_emailer.sh, to run via cron.
#
# Usage:
#
#   $ PYSERVER_HOME=/path/to/pyserver INSTANCE={instance} ./watchers_emailer.py

script_name = 'Cyclopath Item Watchers Emailer Script'
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-10-18'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import datetime
import time
import traceback

import conf
import g

import logging
from util_.console import Console
log_level = logging.DEBUG
log_to_file = True
log_to_console = True
log_line_len = None
if ((os.environ.get('TERM') != 'dumb')
    and (os.environ.get('TERM') is not None)):
   log_to_console = True
   log_line_len = Console.getTerminalSize()[0]-1
conf.init_logging(log_to_file, log_to_console, log_line_len, log_level)
log = g.log.getLogger('wtchrs_emalr')

from item.util.watcher_frequency import Watcher_Frequency
from item.util.watcher_watcher import Watcher_Watcher
from util_ import db_glue
from util_ import misc
from util_.emailer import Emailer
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

   # ***

# *** Watchers_Emailer

class Watchers_Emailer(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      #log.debug('go_main: self.qb.db.curs: %s' % (id(self.qb.db.curs),))

      time_0 = time.time()

      do_commit = False

      # A quick datetime refresher:
      # str(datetime.date.today())
      #  '2013-10-20'
      # str(datetime.date.weekday(datetime.date.today()))
      #  '6' # Sunday
      # str(datetime.datetime.fromtimestamp(float('%.6f' % (time.time(),))))
      #  '2013-10-20 13:25:51.748303'

      now = datetime.datetime.now()

      service_delays = []

      # SYNC_ME: See Watcher_Frequency's list of delay options.

      # We always check for: Watcher_Frequency.ripens_at
      service_delays.append(Watcher_Frequency.ripens_at)

      # We always check for: Watcher_Frequency.immediately
      service_delays.append(Watcher_Frequency.immediately)

      # Check if we should send the watchers on a daily schedule.
      last_time = self.get_last_watcher_activity(Watcher_Frequency.daily)
      if last_time is not None:
         # See if it's another day that we last sent the dailys.
         if last_time.day != now.day:
            # And then check that it's past noon and not too late to email.
            # DEVS: The cron job should run at least as frequently as the
            # smallest time window defined herein.
            # MAGIC_NUMBER: Send email at noon, but no later than 4 PM C*T.
            if ((now.hour >= 12) and (now.hour < 16)):
               tdelta = now - last_time
               log.debug('go_main: adding "daily": days since: %d'
                         % (tdelta.days,))
               service_delays.append(Watcher_Frequency.daily)
      else:
         # Daily alerts have never been sent. If you haven't
         # run the script from cron in a while... this'll
         # flush the queue of pending daily event alerts.
         service_delays.append(Watcher_Frequency.daily)

      # Check if we should send the watchers on a weekly schedule.
      last_time = self.get_last_watcher_activity(Watcher_Frequency.weekly)
      if last_time is not None:
         tdelta = now - last_time
         # MAGIC_NUMBER: We check that at least six days have passed, and not
         # seven, because if a script one week runs at 2:02 PM and the week
         # the script runs at 2:01 PM, the latter script won't run the
         # weeklies. So then the script runs again at 2:03 PM and runs the
         # weeklies, but then the next week it waits until 2:05 PM, etc...
         # until eventually there's one week where the time window is not
         # open and we don't send weeklies at all. So check one less day
         # than a week, and then check the time window.
         if tdelta.days >= 6:
            # MAGIC_NUMBER: Send weeklies on Sunday at 2 PM. (6 is Sunday).
            if now.weekday() == 6:
               # Send emails at 2 PM but no later than 6.
               if ((now.hour >= 14) and (now.hour < 18)):
                  log.debug('go_main: adding "weekly": weeks since: %.2f'
                            % (tdelta.days / 7.0,))
                  service_delays.append(Watcher_Frequency.weekly)
      else:
         # Weekly-alert emails have never been sent; i.e.,
         # there's no row in key_value_pair for the weekly event.
         service_delays.append(Watcher_Frequency.weekly)

      # Check if we should send the watchers on a nightly schedule.
      # C.f. the block above for Watcher_Frequency.daily.
      last_time = self.get_last_watcher_activity(Watcher_Frequency.nightly)
      if last_time is not None:
         if last_time.day != now.day:
            # MAGIC_NUMBER: Send nightlies between 6 and 10.
            if ((now.hour >= 18) and (now.hour < 22)):
               tdelta = now - last_time
               log.debug('go_main: adding "nightly": nights since: %d'
                         % (tdelta.days,))
               service_delays.append(Watcher_Frequency.nightly)
      else:
         service_delays.append(Watcher_Frequency.nightly)

      # Check if we should send the watchers on a morningly schedule.
      # C.f. the block above for Watcher_Frequency.daily.
      last_time = self.get_last_watcher_activity(Watcher_Frequency.morningly)
      if last_time is not None:
         if last_time.day != now.day:
            # MAGIC_NUMBER: Send morninglies between 6 and 10.
            if ((now.hour >= 6) and (now.hour < 10)):
               tdelta = now - last_time
               log.debug('go_main: adding "morningly": nights since: %d'
                         % (tdelta.days,))
               service_delays.append(Watcher_Frequency.morningly)
      else:
         service_delays.append(Watcher_Frequency.morningly)

      try:

         watcher = Watcher_Watcher(self.qb)

         # Send one group of alert types at a time.
         # If we sent, e.g., an immediate alert along with weekly alerts, users
         # might not pay attention (because users would set weekly alerts on
         # items they don't care much about, but immediate alerts on items they
         # care about, so let's not miss the two types of events in one email).
         for service_delay in service_delays:
            watcher.send_alerts(service_delay)

         now_ts = time.time()
         for wfreq in service_delays:
            self.set_last_watcher_activity(wfreq, now_ts)

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

      log.debug('watchers_email: complete: %s'
                % (misc.time_format_elapsed(time_0),))

   # ***

   kvp_watcher_prefix = 'watcher-'

   #
   def get_key_name(self, watcher_freq):

      # E.g., 'watcher-last_activity-weekly' ==> datetime
      key_name = ('%slast_activity-%s'
         % (Watchers_Emailer.kvp_watcher_prefix,
            Watcher_Frequency.get_watcher_frequency_name(watcher_freq),))

      return key_name

   #
   def get_last_watcher_activity(self, watcher_freq):

      key_name = self.get_key_name(watcher_freq)

      rows = self.qb.db.sql(
         "SELECT value FROM key_value_pair WHERE key = '%s'"
         % (key_name,))

      if rows:
         g.assurt(len(rows) == 1)
         # The time is stored as a time.time() string, e.g.,
         # '1382293655.514883'.
         last_time_time = float(rows[0]['value'])
         g.assurt(last_time_time > 0)
         last_time = datetime.datetime.fromtimestamp(last_time_time)
      else:
         last_time = None

      return last_time

   #
   def set_last_watcher_activity(self, watcher_freq, now_ts):

      key_name = self.get_key_name(watcher_freq)

      delete_sql = ("DELETE FROM key_value_pair WHERE key = '%s'"
                    % (key_name,))
      rows = self.qb.db.sql(delete_sql)

      update_sql = (
         "INSERT INTO key_value_pair (key, value) VALUES ('%s', '%.6f')"
         % (key_name, now_ts,))
      rows = self.qb.db.sql(update_sql)

   # ***

# ***

if (__name__ == '__main__'):
   we = Watchers_Emailer()
   we.go()

