#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Get and set email flags for a given user

import optparse
import sys

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('email_flags')

# ***

from gwis import user_email
from util_ import db_glue

usage = '''
  $ export PYSERVER_HOME= location of your pyserver directory
 
  View flags:  $./\%prog USER
  Set flags:   $./\%prog --FLAG VALUE EMAIL_ADDRESS|USERNAME

  Flags:

  --enable-email           enable a user to receive emails
  --enable-research-email  enable a user to receive research related emails
  --enable-wr-digest       enable watch region notification daily digests
  --dont-study             exclude a user from analysis (e.g. a Cyclopath dev)
  --bouncing               flag a users email address as bouncing
  --login-permitted        disable login for a user'''

valid_flags = [
   'enable-email',
   'enable-research-email',
   'enable-wr-digest',
   'dont-study',
   'bouncing',
   'login-permitted',
   ]

def main():

   # optparse doesn't support boolean types; this is a work around
   def check_bool(option, opt_str, value, parser):
     value = value.lower()
     if (value not in ['true', 'false', '1', '0']):
        parser.error(opt_str + " must be set to a boolean value.")       
     setattr(parser.values, option.dest, value in ['true','1'])
        
   # parse args   
 
   # SYNC_ME: The option names are mapped to database column names
   #          in user_email.flag_db_map.
   op = optparse.OptionParser(usage=usage)
   op.add_option('-e', '--enable-email', type='string', action='callback', 
                 callback=check_bool, dest='enable-email')
   op.add_option('-r', '--enable-research-email',
                 type='string', action='callback', 
                 callback=check_bool, dest='enable-research-email')
   op.add_option('-d', '--enable-wr-digest', type='string', action='callback', 
                 callback=check_bool, dest='enable-wr-digest')
   op.add_option('-a', '--dont-study', type='string', action='callback', 
                 callback=check_bool, dest='dont-study')
   op.add_option('-b', '--bouncing', type='string', action='callback', 
                 callback=check_bool,  dest='bouncing')
   op.add_option('-l', '--login-permitted', type='string', action='callback', 
                 callback=check_bool,  dest='login-permitted')
 
   (options, args) = op.parse_args()
 
   if (len(args) == 0):
      op.error('USER must be set')

# FIXME: Who else locks this table? what about wiki? you just want to row lock,
# anyway...
   db = db_glue.new()
   db.transaction_begin_rw('user_')
   
   usernames = [args[0]]
   # If arg contains an @ symbol, assume it's an e-mail address and look up
   # the corresponding username(s).
   if (usernames[0].find('@') != -1):
      usernames = user_email.usernames_get(db, usernames[0])

   # set specified flags
   for username in usernames:
      for option in valid_flags:
         value = getattr(options, option)
         if (value is not None):
            user_email.flag_set(db, username, option, value)
            print 'setting %s to %s for %s' % (option, value, username,)

   db.transaction_commit()

   # print flags and their values
   for username in usernames:
      values = user_email.flags_get(db, username)
      print ('flags for %s, %s (db: %s):'
             % (username,
                user_email.addr_get(db, username, False),
                db_glue.DB.db_name,))
      for (key, value) in values.items(): 
         print '  %s = %s' % (key, value,)

   db.close()

if (__name__ == '__main__'):
   main()

