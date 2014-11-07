#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.
#
# This script populates apache_event_sessions using a simple heuristic: we
# assume that each hit indicates application use starting at the time of the
# hit plus n seconds. The intersection of these microsessions is one session.
#
# Usage:
#
#   $ export PYSERVER_HOME=/...
#   $ ./apache_event_sessions_compute.py

# 2013.05.27: NOTE: This script is not called. Even in the production database
#                   apache_event_session is an empty table. [lb] wonders if
#                   maybe this script was never finished, so it was never added
#                   to the daily cron job.

# How long is a microsession, in seconds?
MICROSESSION_DURATION = 30

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue
import util

db = db_glue.new()
db.transaction_begin_rw()

print 'Microsession duration is %d seconds' % (MICROSESSION_DURATION)

print 'Truncating apache_event_session'
db.sql("TRUNCATE apache_event_session")

print 'Loading apache_event'
# NOTE: We use an explicit cursor to avoid loading the whole result set, which
# is quite huge, into memory.
curs = db.conn.cursor()
curs.execute("""SELECT
                   COALESCE(username, client_host) as user_,
                   timestamp_tz as time_start,
                   timestamp_tz + '%d seconds'::interval as time_end
                FROM apache_event
                ORDER BY user_, time_start""" % (MICROSESSION_DURATION))

print 'Working ',
pr = util.Progress_Bar(curs.rowcount)
session = None
while True:
   row = curs.fetchone()
   if (row is None):
      break
   user_ = row[0]
   start = row[1]
   end = row[2]
   if (session is not None
       and session['user_'] == user_
       and start <= session['end']):
      # current hit part of current session; extend session
      session['end'] = end
      session['count'] += 1
   else:
      # current hit not part of current session
      if (session is not None):
         # write out current session to the database
         db.sql("""INSERT INTO apache_event_session
                          (user_,     hit_count, time_start, time_end)
                   VALUES (%(user_)s, %(count)s, '%(start)s',  '%(end)s')""",
                session)
      # init new session
      session = {'user_': user_, 'start': start, 'end': end, 'count': 1}
   pr.inc()
print

print ('Found %d sessions'
       % (db.sql("""SELECT count(*)
                    FROM apache_event_session""")[0]['count']))
print ('Found %d sessions w/ at least 10 hits'
       % (db.sql("""SELECT count(*)
                    FROM apache_event_session
                    WHERE hit_count >= 10""")[0]['count']))

print 'Committing'
db.transaction_commit()

print 'ANALYZEing'
db.sql("ANALYZE apache_event_session")

db.close()

