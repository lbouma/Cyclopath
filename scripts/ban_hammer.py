#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.
#
# This file provides command-line functionality to ban users and ip addresses
# for cyclopath users.

usage = '''

Depending on shell:
      $ export PYSERVER_HOME=/export/scratch/reid/cyclingproject/pyserver
      $ export LD_LIBRARY_PATH=/export/scratch/reid/python/lib:$LD_LIBRARY_PATH
   or
      $ setenv PYSERVER_HOME "..."
      $ setenv LD_LIBRARY_PATH=...
   $./ban_hammer.py OPTIONS

examples:
   Give a user a full ban for 1 year:
      ./ban_hammer.py --ban full --user mludwig --year 1
   View active bans for a user and ip address:
      ./ban_hammer.py --active --user mludwig --ip 127.0.0.1
   Remove all bans for an ip address (inluding bans that include an username):
      ./ban_hammer.py --remove --ip 127.0.0.1

options:

  -h --help

     Print this help.

  You must specify exactly one of the following:

  -b --ban SCOPE

     Will ban the given user and/or ip address for the given type of
     activity (determined by SCOPE). SCOPE can be 'public',  or 'full'.
     Requires at least one of --user or --ip. If none of --year, --day,
     --minute are given, the ban is a permanent ban.

     A full ban prevents a user/ip from performing any edits.  A public ban
     allows user/ip to save ratings and watch regions, but no public changes.

  -a --active

     Displays active bans depending on -u or -i. If both are set, shows only
     bans that have both -u and -i matching. If only one is set, shows active
     bans for that user or ip address. If neither are present, lists all
     active bans. This is the default operation.

  -g --get

     Same behavior as --active except it displays bans over any time period.
 
  -r --remove

     Will end bans for the given user and/or ip address. If both are given,
     it only ends bans that have both user and ip matching the arguments.
     If only one is given, deactivates bans that match that value (even if
     the other property was also banned).
     Requires at least one of -u or -i given.

  Additional parameters:

  -u --user USERNAME

     Specifies the username for --ban, --active, --get, and --remove
     operations.

  -i --ip IPADDR

     Specifies the ip address for --ban, --active, --get, and --remove
     operations.

  -y --year COUNT

     Causes a ban to be at least COUNT years long. Can be used with --minute
     and --day for more specific ban durations. Not allowed if --ban isn't
     present. A year is treated as 365 days. The total of --year and --day
     will be clamped to 999999999.

  -d --day COUNT

     Causes a ban to be at least COUNT days long. Can be used with --year and
     --minute for more specific ban durations. Not allowed if --ban isn't
     present. The total of --year and --day will be clamped to 999999999.

  -m --minute COUNT

     Causes a ban to be at least COUNT minutes long. Can be used with --year
     and --day for more specific ban durations. Not allowed if --ban isn't
     present.  

'''

import optparse
import os
import sys

import datetime
import time

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue
import client_ban

def main():

   db = db_glue.new()
   db.transaction_begin_rw()

   # Handle db locking?

   # Parse args
   op = optparse.OptionParser(usage=usage)
   op.add_option('-u', '--user', dest='user')
   op.add_option('-i', '--ip', dest='ip')
   op.add_option('-y', '--year', type='int', dest='year')
   op.add_option('-m', '--minute', type='int', dest='minute')
   op.add_option('-d', '--day', type='int', dest='day')

   op.add_option('-b', '--ban', dest='ban')
   op.add_option('-a', '--active', action='store_true', dest='active')
   op.add_option('-g', '--get', action='store_true', dest='get')
   op.add_option('-r', '--remove', action='store_true', dest='rem')
   op.set_defaults(ban=None,
                   active=False,
                   get=False,
                   rem=False,
                   user=None,
                   ip=None,
                   year=None,
                   minute=None,
                   day=None)

   (clopts, args) = op.parse_args()

   if (clopts.ban is None and (clopts.year is not None
                               or clopts.day is not None
                               or clopts.minute is not None)):
      op.error('--year, --day and --minute are only allowed if --ban is used');
      
   # delegate command options
   if (clopts.ban is not None):
      if (clopts.year is None and clopts.day is None
          and clopts.minute is None): # permanent ban
         end_date = datetime.timedelta(days=999999999)
      else:
         days = 0
         minutes = 0
         if (clopts.minute is not None):
            minutes = clopts.minute
         if (clopts.day is not None):
            days = clopts.day
         if (clopts.year is not None):
            days += 365 * clopts.year
         end_date = datetime.timedelta(days=days, minutes=minutes)
      
      if (clopts.ban != 'full' and clopts.ban != 'public'):
         op.error("--ban argument SCOPE must be 'public', or 'full'")
      if (clopts.user is None and clopts.ip is None):
         op.error('Must specify at least one of --user or --ip')
         
      do_ban(db, clopts.user, clopts.ip, clopts.ban, end_date)
   elif (clopts.rem):
      if (clopts.user is None and clopts.ip is None):
         op.error('Must specify at least one of --user or --ip')
         
      do_clear_ban(db, clopts.user, clopts.ip, clopts.rem)
   else:
      
      do_get(db, clopts.user, clopts.ip, not clopts.get)

   db.transaction_commit()
   db.close()

def do_ban(db, username, ip_addr, scope, end_delta):
   try:
      expires = datetime.datetime.now() + end_delta
   except OverflowError, e:
      expires = datetime.datetime(datetime.MAXYEAR, 12, 31)
   end = expires.strftime("%Y-%m-%d %H:%M:%S")

   public_ban = scope == 'public'
   full_ban = not public_ban  

   who_name = list()
   who_val = list()
   if (username is not None):
      who_name.append('username')
      who_val.append("'%s'" % (username))
   if (ip_addr is not None):
      who_name.append('ip_address')
      who_val.append("'%s'" % (ip_addr))

   db.sql("""INSERT INTO ban (%s, public_ban, full_ban, activated, expires)
   VALUES (%s, %s, %s, true, TIMESTAMP '%s')""" % (','.join(who_name),
                                                   ','.join(who_val),
                                                   public_ban, full_ban, end))

   print 'Banned %s | %s | Expires: %s' % (','.join(who_val),
                                           scope, end)

def do_clear_ban(db, username, ip_addr, scope):
   print 'Removing the following bans:'
   do_get(db, username, ip_addr, True)
   
   if (username is not None and ip_addr is not None):
      where = """username = '%s' AND ip_address = INET '%s'""" % (username,
                                                                  ip_addr)
   elif (username is not None):
      where = """username = '%s'""" % (username)
   else:
      where = """ip_address = INET '%s'""" % (ip_addr)

   db.sql("""UPDATE ban SET activated = false
             WHERE %s
             AND activated
             AND (created, expires)
                  OVERLAPS (now(), now())""" % (where))

   print 'Bans removed'

def do_get(db, username, ip_addr, active):
   if (username is not None and ip_addr is None):
      sql = client_ban.build_sql("username = '%s'" % (username), active)
   elif (ip_addr is not None and username is None):
      sql = client_ban.build_sql("ip_address = INET '%s'" % (ip_addr), active)
   elif (ip_addr is not None and username is not None):
      sql = client_ban.build_sql("username = '%s' AND ip_address = INET '%s'" %
                                 (username, ip_addr), active)
   else:
      sql = client_ban.build_sql("true", active)

   rows = db.sql(sql)

   count = 1
   
   for row in rows:
      print_ban(row, count)
      print ''
      count += 1
   if (active):
      print 'Total active bans: %d' % (len(rows))
   else:
      print 'Total bans: %d' % (len(rows))

def parse_timedelta(option, duration):
   try:
      p = time.strptime(duration, "%d:%H:%M")[2:5]
      return datetime.timedelta(days=p[0], hours=p[1], minutes=p[2])
   except ValueError, e:
      option.error('Invalid format for LENGTH in --ban')

def print_ban(r, count):
   if (r['username'] is None):
      who = r['ip_address']
   elif (r['ip_address'] is None):
      who = r['username']
   else:
      who = '%s, %s' % (r['username'], r['ip_address'])

   start = r['created']
   end = r['ban_end']

   if (bool(int(r['full_ban']))):
      ban_type = 'full'
   else:
      ban_type = 'public'

   activated = bool(int(r['activated']))

   print """Ban %d%s: %s | %s
   Created: %s | Ends: %s""" % (count, '' if activated else ' (DEACTIVATED)',
                                who, ban_type, start, end)

if (__name__ == '__main__'):
   main()

