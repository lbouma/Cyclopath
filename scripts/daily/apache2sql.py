#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script adds any Apache log lines presented on standard input which are
# not already in the apache_event table to that table.
#
# Usage example (requires bash):
#
#   $ export PYSERVER_HOME=/whatever
#   $ cat /var/log/apache2/access.log{.1,} | ./apache2sql.py
#
# WARNING: Correct functioning of this script depends on log lines being
# presented in increasing temporal order (i.e., later lines come after earlier
# ones). We don't sort them.
#
# WARNING: This script will not import lines which precede the last line in
# the database. This means that multiple runs must be carefully ordered.
#
# WARNING: This script uses "local time" everywhere, but it's actually UTC. We
# do this to avoid Python converting to/from UTC in ways we don't want.
#
# WARNING: We do not guarantee that every line in the Apache logs will appear
# in the database table, nor that log lines won't be duplicated. This is
# because log lines have no unique identifier. Duplication and/or missing
# lines will occur if multiple log lines with all fields equal to the fields
# of the last event in the database occur. We believe this is rare.
#
# FIXME: The following features would be nice:
#
#   1. Unpacking packed client log stuff (probably need different table).

# HOW TO REBUILD FROM SCRATCH: If your cron job fails and you don't fix it
# before logrotate moves the apache file, you can rebuild from all of the
# archived log files. It just takes a half a day.
# See: run_apache2sql_instance
#  in: /ccp/bin/ccpdev/daily/upgrade_ccpv1-v2.sh

# USED_BY: Production server nightly cronjob.

script_name = 'apache2sql'
script_version = '2.3'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-05-27'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import os
import psycopg2
import re
import sys
import time

# Setup logging first, lest g.log.getLogger return the base Python Logger().
import logging
#from util_ import logging2
from util_.console import Console
# FIXME: Raise logging to WARNING so doesn't appear in cron output
#log_level = logging.WARNING
log_level = logging.INFO
# [rp]: True if you want inane blather while script runs.
# [lb]: Why is log trace inane? Or, "Silly; stupid; not significant".
#       I find log statements extremely helpful for de-veloping/-bugging.
log_level = logging.DEBUG
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

log = g.log.getLogger('apache2sql.py')

from util_ import db_glue
from util_ import misc
from util_ import rect
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debugging control

# Developer switches
debug_limit = None

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

      self.add_argument(
         '--access-log', dest='access_log',
         default=None, action='store',
         help='Use the specified logfile instead of access.log.',)

      self.add_argument(
         '--skip-date-check', dest='skip_date_check',
         default=False, action='store_true',
         help='Import all records, regardless of timestamp.',)

      self.add_argument(
         '--skip-analyze', dest='skip_analyze',
         default=False, action='store_true',
         help='Skip vacuum analyze.',)

   #
   def verify(self):
      verified = Ccp_Script_Args.verify(self)
      return verified

   # ***

# *** Apache2Sql

class Apache2Sql(Ccp_Script_Base):


   # Complain if more than this many unparseable lines.
   unparseable_complaint_threshold = 10
   # 2012.10.03: Why's there a threshold? Shouldn't all lines be parseable,
   #             i.e., how logcheck is strick about lines for which it
   #             doesn't have exceptions.
   unparseable_complaint_threshold = 0

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def go_main(self):

      log.debug('Starting')

      time_0 = time.time()

      log.debug('Starting db transaction...')

      #db = db_glue.new()
      self.qb.db.transaction_begin_rw()

      if not self.cli_opts.skip_date_check:
         self.last_logged = self.get_last_logged()
      else:
         self.last_logged = None

      #prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      #prog_log.loop_max = len(rev_rows)
      #prog_log.log_freq = 25

      self.parse_logs()

      #prog_log.loops_fin()

#      if not debug_skip_commit:
#         log.info('Committing transaction...')
#         self.qb.db.transaction_commit()
#      else:
#         db.transaction_rollback()
#      self.qb.db.close()
      self.query_builder_destroy(do_commit=(not debug_skip_commit))

      log.debug('gtfsdb_build_cache: complete: %s'
                % (misc.time_format_elapsed(time_0),))

   #
   def get_last_logged(self):

      # MAYBE: Rename apache_event.wfs_request to gwis_request?
      rows = self.qb.db.sql(
         """
         SELECT
            client_host,
            username,
            timestamp_tz AT TIME ZONE 'UTC' AS ts_utc,
            request,
            wfs_request,
            status,
            size,
            time_consumed,
            browid,
            sessid
         FROM apache_event
         ORDER BY id DESC
         LIMIT 1
         """)
      line_max = Apache_Line(rows[0]) if (len(rows) > 0) else None

      log.debug('===== line_max: %s' % (line_max,))
      try:
         log.debug('get_last_logged: ... rows[0]: %s' % (rows[0],))
         #log.debug('... rows[-1]: %s' % (rows[-1],))
      except IndexError, e:
         log.debug('get_last_logged: no rows')

      return line_max

   #
   def parse_logs(self):

      log.debug('parsing Apache lines')

      lines_valid = list()
      lines_invalid = list()

      # For "known issues", we copy log lines to a separate log file that we
      # don't logcheck but that we keep for engineers who are diagnosing bugs.
      #
      # FIXME: For CcpV1, [lb] is hard-coding this location here.
      #        MAGIC_NUMBER: For CcpV2, we should derive this script from
      #        Script_Args/Script_Base and then add a logfile command line
      #        option, and then cron can specify it.
      #
      known_issues_log_name = '/ccp/var/log/apache2/known_issues.log'
      #
      try:
         known_issues_f = open(known_issues_log_name, 'a')
      except IOError, e:
         known_issues_f = None
         log.error('Unable to open logfile: %s: %s'
                   % (known_issues_log_name, str(e),))

      # NOTE: This script excepts the apache log to be piped to it.
      # BUG 2736: This should not come from stdin, so we can run pdb.
      #           FIXME: Make this a command line argument.
      #                  For now, hard coding!
      #for line in [Apache_Line(x) for x in sys.stdin.readlines()]:
      if self.cli_opts.access_log:
         access_logs = [self.cli_opts.access_log,]
      else:
         # NOTE: Order is important. The very oldest event is at the start of
         #       access.log.1, then the end of access.log.1 precedes the start
         #       of access.log, and finally the end of that file is the
         #       freshest event.
         access_logs = ['/ccp/var/log/apache2/access.log.1',
                        '/ccp/var/log/apache2/access.log',]
      for access_log in access_logs:
         self.parse_a_log(access_log, lines_valid, lines_invalid,
                          known_issues_f)

      if known_issues_f is not None:
         known_issues_f.close()

      # 2012.10.17: The complaint threshold is now 0; this script behaves like
      #             logcheck now: it's either a bug, or it's not.
      if len(lines_invalid) > Apache2Sql.unparseable_complaint_threshold:
         # FIXME: For upgrade_ccpv1-v2.sh, do not log error, or the cron job
         #        stops. These logs are saved, so we should go through 'em and
         #        fix the unparseable lines.
         #log.error('Unparseable Apache lines:\n%s'
         #          % (''.join(lines_invalid),))
         log.warning('Unparseable Apache lines:\n%s'
                     % (''.join(lines_invalid),))

      log.debug('Parseable %d lines.' % (len(lines_valid),))
      log.debug('Unparseable %d lines.' % (len(lines_invalid),))

      skip_ct = 0
      if self.last_logged is not None:
         # Search forwards so equal lines will be duplicated, not skipped. This
         # has to be a linear search because Apache log line timestamps do not
         # increase monotonically [rp].
         line_max_i = -1
         for i in xrange(len(lines_valid)):
            if lines_valid[i] == self.last_logged:
               line_max_i = i
               self.last_logged = None
               break
         # Discard lines already in the database.
         skip_ct = line_max_i + 1
         lines_valid = lines_valid[skip_ct:]

      if lines_valid:
         log.debug('inserting %d lines, skipping %d'
                   % (len(lines_valid), skip_ct,))
         num_inserted = 0
         for line in lines_valid:
            # MAYBE: Do a bulk insert, which is quicker. But this is still
            #        pretty quick, probably because we don't have an
            #        constraints on this table.
            try:
               sql_stmt = (
                  'apache_event',
                  {},
                  {'client_host': line.client_host,
                   'username': line.user,
                   'timestamp_tz': misc.timestamp_tostring(line.ts_utc),
                   'request': line.request,
                   #'wfs_request': line.wfs_request,
                   'wfs_request': line.gwis_request,
                   'geometry': line.bbox,
                   'status': line.status,
                   'size': line.size,
                   'time_consumed': line.time_consumed,
                   'browid': line.browid,
                   'sessid': line.sessid,},)
               self.qb.db.insert(*sql_stmt)
            except psycopg2.DataError, e:
               # 2014.01.30: psycopg2.DataError: integer out of range.
               #             EXPLAIN: Not sure yet...
               log.error('Bad apache log line: %s / %s'
                         % (str(e), sql_stmt,))
               # FIXME: We should probably rollback. I'll guess we'll test
               #        without and see what happens...

            # FIXME: Add log_progger to this script and print out progress...
            num_inserted += 1
            if (num_inserted % 20000) == 0:
               log.debug('num_inserted: %7d' % (num_inserted,))

         # FIXME: Doesn't this normally come after a commit??
         if not self.cli_opts.skip_analyze:
            log.debug('Analyzing database; please wait...')
            self.qb.db.sql("ANALYZE apache_event;")

      else:

         log.debug('nothing to insert; skipping %d lines' % (skip_ct,))

      log.debug('All done!')

   #
   def parse_a_log(self, access_log, lines_valid, lines_invalid,
                         known_issues_f):
      try:
         access_log_f = open(access_log, 'r')
         log.debug('Opened logfile: %s' % (access_log,))
         num_lines = 0
         # NOTE: The old script loaded everything into memory but this seems
         #       unnecessary and memory-expensive (i.e., runs okay on the
         #       production machine but not so much on dev machines). [lb]
         #       thinks this is just another potential Python trap: writing
         #       code one way because Python is flexible and can be easy to
         #       hack, but not understanding the how Python ultimately runs
         #       code, which affects memory usage and performance (or maybe
         #       it's just because I come from an embedded device background
         #       that I care).
         # FIXME: STYLE_GUIDE: Add the above note to the style guide.
         # NO:
         #  for line in [Apache_Line(x) for x in access_log_f.readlines()]:
         log_line = access_log_f.readline()
         while log_line:
            a_line = Apache_Line(log_line)
            if a_line.valid:
               lines_valid.append(a_line)
            elif a_line.http_method:
               # This request is a valid GET or POST but parsing failed, so
               # this is a bug. (As opposed to a request without a valid GET
               # or POST, which is a malformed request we can ignore; but
               # see the next bit of code, where we log malformed requests
               # to an archived logfile.)
               # 2013.05.28: Last comment is kind of a lie. If regex we use
               # looks for [A-Z]+ and then everything after is optional. So,
               # e.g., I'm seeing "HELP", and nothing else, so HELP Is
               # http_method... haha.
               #
               #lines_invalid.append(a_line.raw)
               #log.error('WARNING: EXPLAIN: http_method: %s / a_line: %s'
               #          % (a_line.http_method, a_line,))
               log.warning('WARNING: EXPLAIN: http_method: %s / a_line: %s'
                           % (a_line.http_method, a_line,))
            else:
               # E.g., a_line: invalid: 77.96.113.81 - -
               #        [25/May/2013:01:33:46 -0500]
               #        "ad_type=general&unread_only=0&wr=0&near_edits=0
               #        &browid=7BD9B322-9632-AFEA-5B47-DA641289A8C3
               #        &sessid=D67080F4-BA65-6139-D6C8-DA6409A07947
               #        &body=yes HTTP/1.1" 400 340 "-" "-" -
               # DEVS: You must deal with this.
               #log.error('EXPLAIN: a_line: %s' % (a_line,))
               log.warning('EXPLAIN: a_line: %s' % (a_line,))
               log.warning(' .. http_method: %s / valid: %s'
                           % (a_line.http_method, a_line.valid,))

            # A line that's marked valid might not specify a valid HTTP
            # method.  These should be known issues -- either our own bugs
            # or problems with external services sending us malformed HTTP
            # that we can safely ignore -- but we still record these lines
            # to a logfile.  The logfile won't be checked by logcheck,
            # but we can use it to see how often these problems are
            # occurring. This is because access.log grows very fast and is
            # rotated and gzip'ed often, so it's tedious to search backlogs
            # (though there's probably an egrep/gunzip command line that
            # could do it quickly... but I [lb] like to use vim to peruse
            # log files, and I want it to be simple to persuse logfiles, so
            # we'll just log these lines... for now).
            #
            # FIXME: 2013.04.22: This file is 4 Gb. Two months of logs to
            # itamae:/export/scratch/reid/logs/apache/known_issues.log
            # and being backed up also caused gl15 to fill up, at:
            # /project/gl15/landonb/itamae-export-scratch-reid.bak/logs/apache
            # And then you have to manually cleanup the backup directory...
            #
            if (not a_line.http_method) and (known_issues_f is not None):
               known_issues_f.write(a_line.raw)

            # FIXME: Add log_progger to this script and print out progress.
            num_lines += 1
            if (num_lines % 22500) == 0:
               log.debug('.')

            log_line = access_log_f.readline()

         access_log_f.close()

         log.debug('Processed %d lines (%d lines_valid / %d lines_invalid)'
             % (num_lines, len(lines_valid), len(lines_invalid),))

         log.debug('lines_valid[-1]: %s' % (lines_valid[-1],))

      except IOError, e:
         log.debug('Access log not found: %s / %s' % (access_log, str(e),))

# *** Support classes: Apache_Line

class Apache_Line(object):

   __slots__ = (
      'raw',
      'valid',
      'http_method',
      'client_host',
      'user',
      'ts_utc', # time stamp in UTC seconds
      'request',
      #'wfs_request',
      'gwis_request',
      'bbox',
      'status',
      'size',
      'referrer',
      'user_agent',
      'time_consumed',
      'browid',
      'sessid',
      )

   # Bug 2736: Circa 2012: We've been getting some oddly-formatted requests.
   # The regex to parse an apache line used to expect the request to start
   # with [A-Z]+, i.e., POST, but we get some weird looking requests from
   # what are probably Web crawlers and robots.
   # HINT: Normal requests start with "GET" or "POST" and end with "HTTP/1.1".
   #  157.55.34.106 - - [10/Sep/2012:10:31:19 -0500] "t: magic.cyclopath.org" 400 340 "-" "-" -
   #  157.55.34.106 - - [10/Sep/2012:10:31:22 -0500] "(direct)|utmcmd=(none)" 501 348 "-" "-" -
   #  157.55.34.106 - - [10/Sep/2012:10:31:25 -0500] "" 501 326 "-" "-" -
   #  157.55.34.106 - - [10/Sep/2012:10:31:25 -0500] "" 414 364 "-" "-" -
   # This is fixed so the script doesn't complain: added ()? around [A-Z]+\s,
   # and adding ? after the <request> parens. We still parse the request to see
   # if it's GWIS.

   # 2013.05.25: FIXME: What chars are in usernames?
   # We weren't parsing for periods!
   #  (?P<user>[\w-]+)
   #  \w: [a-zA-Z0-9_]
   # 2013.09.24: [lb] is seeing a different time format: 5.76e+03

   RE_VALID = re.compile(
      r'''^
     (?P<client_host>[\w.-]+)
     \s
     - # remote username; always hyphen
     \s
     (?P<user>[-._a-zA-Z0-9]+)
     \s
     \[(?P<timestamp>[\w\/:]+)\s(?P<ts_offset>[+-]\d{4})\]
     \s
     "(?P<http_method>[A-Z]+)?\s?(?P<request>.+?)?(?:\sHTTP/[\d.]+)?"
     \s
     (?P<status>\d+)
     \s
     (?P<size>[\d-]+)
     \s
     "(?P<referrer>.*)"
     \s
     "(?P<user_agent>.+)"
     (?:\s
        (?P<time_consumed>[\d\.\-\+e]+))?
     $''', re.VERBOSE)

   #  "([A-Z]+\s)?(?P<request>.+?)?(?:\sHTTP/[\d.]+)?"
   #  "(?P<http_method>[A-Z]+)?\s?(?P<request>.+?)?(?:\sHTTP/[\d.]+)?"


   # SYNC_ME: Search: gwis prefix (see: flashclient, android, and apache conf).
   #
   # Don't be strict about request always being first...
   # Too strict: RE_WFS = re.compile(r'/wfs\?request=(\w+)')
   RE_WFS = re.compile(r'/wfs\?.*&?request=(\w+)')
   #
   #RE_GWIS = re.compile(r'/gwis\?request=(\w+)')
   #RE_GWIS = re.compile(r'/gwis\?rqst=(\w+)')
   # Well, maybe we shouldn't be strict about rqst always being first...
   RE_GWIS = re.compile(r'/gwis\?.*&?rqst=(\w+)')

   RE_BBOX = re.compile(r'&bbox=([\d.]+,[\d.]+,[\d.]+,[\d.]+)')

   # Bug 2736: 2012.10.17: Parsing browser and session IDs broken: this regex
   # used to just use uppercase, but what's in access.log is lowercase. For
   # sake of being compatible with either, adding lowercase, too, and keeping
   # uppercase.
   # BUG nnnn: FIXME: Write code to unpack all past apache logs and fix the
   #                  missing browser ID and session ID values.
   RE_BROWID = re.compile(r'&browid=([a-fA-F0-9-]+)')
   RE_SESSID = re.compile(r'&sessid=([a-fA-F0-9-]+)')

   def __init__(self, init):
      #
      self.valid = False
      self.http_method = False
      #
      if (isinstance(init, str)):
         self.init_from_log_text(init)
      else:
         self.init_from_db_row(init)

   #
   def __eq__(self, other):
      return (    self.valid == other.valid
              and self.http_method == other.http_method
              and self.client_host == other.client_host
              and self.user == other.user
              and self.ts_utc == other.ts_utc
              and self.request == other.request
              #and self.wfs_request == other.wfs_request
              and self.gwis_request == other.gwis_request
              and self.status == other.status
              and self.size == other.size
              and self.time_consumed == other.time_consumed
              and self.browid == other.browid
              and self.sessid == other.sessid)

   #
   def __str__(self):
      the_str = ''
      newlines_okay = False
      if not self.valid:
         the_str = 'invalid: %s' % (self.raw)
      elif newlines_okay:
         the_str = '===Apache_Line===\n'
         for attr in Apache_Line.__slots__:
            attr_name = attr + ':'
            the_str += ('%-16s%s\n'
                        % (attr_name,
                           getattr(self, attr, None),))
      else:
         attr_kvs = []
         for attr in Apache_Line.__slots__:
            attr_val = getattr(self, attr, None)
            if attr_val:
               try:
                  # Remove newline.
                  attr_val = attr_val.strip()
               except AttributeError:
                  pass
            attr_kvs.append((attr, attr_val,))
         the_str = ('apache line: %s'
                    % (' / '.join(['%s: %s' % attr_kv
                                   for attr_kv in attr_kvs]),))
      return the_str

   #
   def cleanse(self, text, type_=str):
      if type_ is None:
         type_ = str
      if (text is None) or (text == '-'):
         return None
      else:
         return type_(text)

   #
   def init_from_db_row(self, row):

      # WARNING: This does not parse bbox.
      self.valid = True
      self.client_host = row['client_host']
      self.user = row['username']

      # This is in the CcpV1 code. But psycopg must not be converting to
      # something other than psycopg2, because in CcpV2 we get a
      # datetime.datetime, which doesn't know what ticks is.
      #  itamae: self.ts_utc = int(row['ts_utc'].ticks())
      self.ts_utc = int(time.mktime(row['ts_utc'].timetuple()))

      self.request = row['request']
      #self.wfs_request = row['wfs_request']
      self.gwis_request = row['wfs_request']
      self.status = row['status']
      self.size = row['size']
      self.time_consumed = row['time_consumed']
      self.browid = row['browid']
      self.sessid = row['sessid']

   #
   def init_from_log_text(self, text):

      self.raw = text

      m = self.RE_VALID.search(self.raw)

      if m is not None:

         # See if this is a well-formatted request.
         self.request = m.group('request')
         self.http_method = m.group('http_method')
         if self.http_method:
            # Haha. '218.18.44.186 - - [21/Jun/2012:09:14:07 -0500] "HELP"
            #       501 330 "-" "-" -\n'
            # It thinks HELP is the HTTP method. And self.request is None.
            self.parse_valid_re_match(m)
         #
         else:
            # MAYBE: Look for the normal suspects but complain to cron
            #        if there's a new one.
            #  if self.request not in (
            #     '', # 414 364
            #     '', # 501 326
            #     '(direct)|utmcmd=(none)', # 501 348
            #     't: magic.cyclopath.org', # 400 340
            #     )
            # Do what now?
            pass
#      # MAYBE: BUG 2725 might mask URL problems, so we should parse here for
#      #        specific URLs we know we don't care about (like the ones
#      #        containing "utmcmd", but not for the ones that pack the
#      #        message content before the POST, i.e., the mobile request=Log
#      #        problem).
#      # MAYBE: This seems like such a hack...!
##      if self.wfs_request is None:
#      if self.gwis_request is None:
#         if not self.request:
#            # Expect HTTP 414 and 364 bytes or HTTP 501 and 326 bytes.
#            if (not (((self.status == 414) and (self.size == 364))
#                     or ((self.status == 501) and (self.size == 326)))):
#               self.valid = False
#         elif self.request == '(direct)|utmcmd=(none)':
#            if not ((self.status == 501) and (self.size == 348)):
#               self.valid = False
#         elif self.request == 't: magic.cyclopath.org':
#            if not ((self.status == 400) and (self.size == 340)):
#               self.valid = False
#         else:
#            self.valid = False

   #
   def parse_valid_re_match(self, m):

      # FIXME: What should we do w/ malformed requests?
      # Currently, the request column has a non-null constraint. So don't try
      # to save records without valid request strings.
      #self.valid = True
      if self.request is not None:
         self.valid = True

      self.client_host = m.group('client_host')

      self.user = self.cleanse(m.group('user'))

      self.ts_utc = None
      timestamp = m.group('timestamp')
      ts_offset = m.group('ts_offset')
      if ((timestamp is not None) and (ts_offset is not None)):
         self.ts_utc = misc.timestamp_parse(timestamp, ts_offset)

      # See if this is a WFS or GWIS POST request.
      # The self.request is None if this is not a GWIS req. or is malformed.
      wm = None
      if self.request is not None:
         wm = self.RE_GWIS.search(self.request)
         if wm is None:
            wm = self.RE_WFS.search(self.request)
      if wm is None:
         #self.wfs_request = None
         self.gwis_request = None
         self.bbox = None
         # This is either a GET request, i.e., for tiles, or this is a
         # POST request that's not a WFS/GWIS command, e.g., a ping
         # from mon.itor.us.
      else:
         #self.wfs_request = wm.group(1)
         self.gwis_request = wm.group(1)
         bm = self.RE_BBOX.search(self.request)
         if bm is None:
            self.bbox = None
         else:
            bbox = rect.Rect()
            bbox.parse_str(bm.group(1))
            self.bbox = bbox.as_wkt()

      try:
         self.status = int(m.group('status'))
      except TypeError, e:
         self.status = None

      self.size = self.cleanse(m.group('size'), int)

      # 2013.09.24: [lb] is seeing a different time format: 5.76e+03
      #             Fortunately, float() accepts that format.
      self.time_consumed = self.cleanse(m.group('time_consumed'), float)

      # The browid and/or sessid might be set even if the request is missing,
      # e.g., in 2013.08.19.gz, you'll find
      # '166.137.88.19 - - [15/Aug/2012:19:56:57 -0500]
      # "POST /wfs?request=&browid=aa2ecda9-ee9e-4066-9e60-
      #  e77052bcb127&sessid=dfe5f360-9361-4df1-adde-b7cfdc75da89
      #  &android=true HTTP/1.1" 200 59 "-" "Dalvik/1.4.0 (Linux; U; Android
      #  2.3.5; Desire HD Build/GRJ90)" 0.000204\n'

      self.browid = None
      if self.request is not None:
         browid = self.RE_BROWID.search(self.request)
         if browid is not None:
            self.browid = browid.group(1)
            # See Bug 2725: This should be a POST request, but there's a bug
            # where the URI is malformed... so it's either POST or nothing.

      self.sessid = None
      if self.request is not None:
         sessid = self.RE_SESSID.search(self.request)
         if sessid is not None:
            self.sessid = sessid.group(1)
            # This could be Googlebot doing a GET GWIS, which doesn't mean
            # anything.
            # FIXME: Should we look for, e.g., Googlebot, and others?
            #        The problem is that it's hard to detect when this script
            #        is broken if we're already ignoring things so readily.
            #        I.e., the things we ignore we should classify first
            #        before ignoring them. That is, a Googlebot request looks
            #        almost real, but it's not, it's actually malformed, but
            #        if it were flashclient, we'd want to alert ourselves, but
            #        for Googlebot, we want to ignore it...
            # BUG nnnn: Better parsing of apache file to filter out garbage but
            #           to be more confident that what we're filtering is
            #           actually garbage. Maybe also make stats on garbage; are
            #           we curious how often and what bots are trying to crawl
            #           us?

      #if (self.browid or self.sessid) and (not self.gwis_request):
      #   log.debug('HELP: %s' % (self.raw,))
      #   print 'Breaking into pdb...'
      #   import pdb; pdb.set_trace()
      #   # or, conf.break_here('ccpv3')

      # Yipes: A google Bot trying to GET a GWIS! Hahaha, we're so
      #        non-HTTP-complient. Request is, e.g.,
      #   '66.249.73.100 - - [19/May/2013:21:33:55 -0500]
      #    "GET /wfs?request=GetFeature&typename=region&rev=
      #     &bbox=483236,4966948,487908,4992484
      #     &browid=41881E64-2744-5B4E-5615-5BFDB457AD20
      #     &sessid=CD1AB58E-3289-2581-FE34-5BFDB4538991&body=yes
      #     HTTP/1.1" 200 14202 "-"
      #     "Mozilla/5.0 (compatible; Googlebot/2.1;
      #      +http://www.google.com/bot.html)" 0.121\n'

      # Here's another odd one: There's no sessid, but it's a GeoGeocode...
      #  '71.195.16.40 - - [20/May/2013:10:09:55 -0500]
      #  "POST /wfs?request=GetGeocode&addr=3%20st.%20 HTTP/1.1"
      #  200 141 "http://magic.cyclopath.org/main.swf" "Mozilla/5.0
      #  (Windows NT 6.1; WOW64; rv:21.0) Gecko/20100101 Firefox/21.0"
      #  3.47\n'
      # Yipes: E.g.,
      #   http://m.odnoklassniki.ru/dk?bk=GuestMain&st.cmd=main&tkn=5372

# *** Unit test.

def test_1():

   pass

   # BUG 2736: Scripts: Apache2sql.py: Needs exceptions like logcheck.
   # The 'utmcmd' text maybe indicates this is a Google Analytics request.
   # The I.P. address is owned by MS in Beverly Hills? MS Broadband?
   #   http://www.sitepoint.com/forums/showthread.php?643132-utmcsr-utmccn-utmcmd-questions
   # 157.55.34.93: msnbot-157-55-34-93.search.msn.com
   # 157.56.92.151: msnbot-157-56-92-151.search.msn.com, Kansas
   # 157.55.34.97: msnbot-157-55-34-97.search.msn.com
   #NetRange:       157.54.0.0 - 157.60.255.255
   #CIDR:           157.54.0.0/15, 157.56.0.0/14, 157.60.0.0/16
   #OriginAS:       AS8075
   #NetName:        MSFT-GFS
   # https://en.wikipedia.org/wiki/Msnbot
   # https://en.wikipedia.org/wiki/Bingbot
   # 2012.09.29: I [lb] added a robots.txt file, but it didn't help...
   #
   """
from apache2sql import Apache_Line
line = '157.55.34.106 - - [10/Sep/2012:10:31:19 -0500] "t: magic.cyclopath.org" 400 340 "-" "-" -'
a = Apache_Line(line)
a.RE_VALID.search('157.55.34.106 - - [10/Sep/2012:10:31:19 -0500] "t: magic.cyclopath.org" 400 340 "-" "-" -')
a.RE_VALID.search('157.55.34.106 - - [10/Sep/2012:10:31:22 -0500] "(direct)|utmcmd=(none)" 501 348 "-" "-" -')
a.RE_VALID.search('157.55.34.106 - - [10/Sep/2012:10:31:25 -0500] "" 501 326 "-" "-" -')
a.RE_VALID.search('157.55.34.106 - - [10/Sep/2012:10:31:25 -0500] "" 414 364 "-" "-" -')
   """

   # 2012.10.17: We get packets with a length specified but no body. Peaking in
   #             /var/log/apache2/access.log shows that the XML is being
   #             prepended to the URI.
   #
   # See Bug 2725: Sometimes the XML content body is packed into
   # and Bug 1656        the URI before the POST and the request.
   #
   """
from apache2sql import Apache_Line
ccpv1_line = '174.157.204.154 - - [07/Oct/2012:15:26:04 -0500] "<data><metadata><device is_mobile=\"True\" /></metadata><event facility=\"mobile/build_info\" timestamp=\"2012-10-07 15:25:33-0500\"><param key=\"tags\">release-keys</param><param key=\"product\">htc_supersonic</param><param key=\"id\">GRJ90</param><param key=\"fingerprint\">sprint/htc_supersonic/supersonic:2.3.5/GRJ90/356670.1:user/release-keys</param><param key=\"model\">PC36100</param><param key=\"device\">supersonic</param><param key=\"brand\">sprint</param><param key=\"device-id\">109c4a08a67ac0a4</param><param key=\"sdk\">10</param><param key=\"incremental\">356670.1</param><param key=\"board\">supersonic</param><param key=\"release\">2.3.5</param></event></data>POST /wfs?request=Log&browid=2db4b582-a0df-4100-8de1-6636262fb5a7&sessid=6b720bf0-8072-43b0-9f1b-ccf22a5b9075&config=yes&android=true HTTP/1.1" 400 268 "-" "Dalvik/1.4.0 (Linux; U; Android 2.3.5; PC36100 Build/GRJ90)" -'
line = '174.157.204.154 - - [07/Oct/2012:15:26:04 -0500] "<data><metadata><device is_mobile=\"True\" /></metadata><event facility=\"mobile/build_info\" timestamp=\"2012-10-07 15:25:33-0500\"><param key=\"tags\">release-keys</param><param key=\"product\">htc_supersonic</param><param key=\"id\">GRJ90</param><param key=\"fingerprint\">sprint/htc_supersonic/supersonic:2.3.5/GRJ90/356670.1:user/release-keys</param><param key=\"model\">PC36100</param><param key=\"device\">supersonic</param><param key=\"brand\">sprint</param><param key=\"device-id\">109c4a08a67ac0a4</param><param key=\"sdk\">10</param><param key=\"incremental\">356670.1</param><param key=\"board\">supersonic</param><param key=\"release\">2.3.5</param></event></data>POST /wfs?rqst=Log&browid=2db4b582-a0df-4100-8de1-6636262fb5a7&sessid=6b720bf0-8072-43b0-9f1b-ccf22a5b9075&config=yes&android=true HTTP/1.1" 400 268 "-" "Dalvik/1.4.0 (Linux; U; Android 2.3.5; PC36100 Build/GRJ90)" -'
a = Apache_Line(line)
m = a.RE_VALID.search(line)
m.group(6)
   """

# ***

if (__name__ == '__main__'):
   a2s = Apache2Sql()
   a2s.go()



if False:
  # FIXME: Use this:
  __nothing__ = """
http://www.dabeaz.com/generators/Generators.pdf

Tuples to Dictionaries

• Let's turn tuples into dictionaries
colnames = ('host','referrer','user','datetime',
            'method','request','proto','status','bytes')
log = (dict(zip(colnames,t)) for t in tuples)

• This generates a sequence of named fields
{ 'status' : '200',
'proto' : 'HTTP/1.1',
'referrer': '-',
'request' : '/ply/ply.html',
'bytes' : '97238',
'datetime': '24/Feb/2008:00:08:59 -0600',
'host' : '140.180.132.213',
'user' : '-',
'method' : 'GET'}

def field_map(dictseq,name,func):
   for d in dictseq:
      d[name] = func(d[name])
      yield d

import os
import fnmatch
def gen_find(filepat,top):
   for path, dirlist, filelist in os.walk(top):
      for name in fnmatch.filter(filelist,filepat):
         yield os.path.join(path,name) 

import gzip, bz2
def gen_open(filenames):
   for name in filenames:
      if name.endswith(".gz"):
         yield gzip.open(name)
      elif name.endswith(".bz2"):
         yield bz2.BZ2File(name)
      else:
         yield open(name)

def gen_cat(sources):
   for s in sources:
      for item in s:
      yield item

def lines_from_dir(filepat, dirname):
   names = gen_find(filepat,dirname)
   files = gen_open(names)
   lines = gen_cat(files)
   return lines

def apache_log(lines):
   groups = (logpat.match(line) for line in lines)
   tuples = (g.groups() for g in groups if g)
   colnames = ('host', 'referrer', 'user', 'datetime', 'method',
               'request', 'proto', 'status', 'bytes')
   log = (dict(zip(colnames,t)) for t in tuples)
   log = field_map(log, "bytes", lambda s: int(s) if s != '-' else 0)
   log = field_map(log, "status", int)

lines = lines_from_dir("access-log*","www")
log = apache_log(lines)
for r in log:
   print r

# You may need to pre-filter if you're just looking for specific lines,
# e.g., rather than
addrs = set(r['host'] for r in log if 'robots.txt' in r['request'])
# you'll want to do something line
lines = lines_from_dir("big-access-log",".")
lines = (line for line in lines if 'robots.txt' in line)
log = apache_log(lines)
# etc...




"""


