#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Prints out a list of all user e-mail addresses which are valid and to which
# we have permission to send research emails (solicitations, etc.). You can
# then use spam.py (not part of Cyclopath) on this list.
#
# Usage example:
#
#   $ emails_for_spam.py [list of usernames to double-check]

script_name = ('Emails for Spam')
script_version = '1.2'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-11-12'

# This script was updated on 2012.11.12 to write user IDs instead of usernames,
# and to standardize the /ccp/bin/ccpdev/schema/runic/bug_xxxx directory.
# See Bug 2756 - Emailing Users: Formal Instructions, Script Updates
#   http://bugs.grouplens.org/show_bug.cgi?id=2756

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import socket

import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('spamails')

# ***

import re
import time

from grax.user import User
from util_ import db_glue
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

VERBOSE = False

# *** Cli arg. parser

# BUG nnnn: Add switch to allow/disallow sending multiple emails to the same
# email address. E.g., if two accounts use the same email address, do we send
# two emails (one for each username), or do we just send one email?

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self, exclude_normal=True)
      #
      self.add_argument('--emails', dest='email_addrs',
         action='store', default=[], type=str, nargs='*', required=False,
         help='a list of email addresses to verify, or none if you want all')
      #
      self.add_argument('--usernames', dest='usernames',
         action='store', default=[], type=str, nargs='*', required=False,
         help='a list of usernames to verify, or none if you want all')
      #
      self.add_argument('--userids', dest='userids',
         action='store', default=[], type=str, nargs='*', required=False,
         help='a list of userids to verify, or none if you want all')
      #
      self.add_argument('--output', dest='recipient_file',
         action='store', default=None, type=str, required=False,
         help='the file in which to store the list of emails okay to email')
      #
      self.add_argument('--bug-number', dest='bug_number',
         action='store', default=None, type=int, required=False,
         help='the bug number, if you want to use standard paths and names')
      #
      self.add_argument('--split-count', dest='split_count',
         action='store', default=1, type=int, required=False,
         help='the number of output files to create')
      #
      self.add_argument('--force', dest='force_overwrite',
         action='store_true', default=False, required=False,
         help='overwrite the output file(s), if they exist')
      #
      self.add_argument('--sort-mode', dest='sort_mode',
         action='store', default='', type=str, required=False,
         choices=('id ASC', 'id DESC', 'email ASC', 'email DESC', 
                  'username ASC', 'username DESC', 'RANDOM()',),
         help='how to order the results')
      # If you're testing, you may want to ignore dont_study, etc.
      self.add_argument('--ignore-flags', dest='ignore_flags',
         action='store_true', default=False, required=False,
         help='always email, even if dont_study.')

      # BUG nnnn: We need an option to exclude emails, e.g.,
      #           consider emailing 500 users, and then
      #           the next day emailing the remaining 2000.
      #           For now, we do it by hand, using Python
      #           set.difference (see the email README.txt
      #           files in ccpdev).

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      if self.cli_opts.recipient_file and self.cli_opts.bug_number:
         log.error(
            'Please specify either --output or --bug-number, not both')
         ok = False
      elif self.cli_opts.bug_number:
         # Use the server name in the path.
         hostname = socket.gethostname() # E.g., 'runic', 'my.home.domain'
         dot_index = hostname.find('.')
         if dot_index > 0:
            hostname = hostname[0:dot_index]
         # else, dot_index is 0 (unexpected, e.g., ".home.domain"?)
         #    or dot_index is -1 (not found)
         self.cli_opts.recipient_file = (
            #'/ccp/bin/ccpdev/private/runic/schema/bug_%s/recipient_file'
            '/ccp/bin/ccpdev/private/%s/schema/bug_%s/recipient_file'
            % (socket.gethostname(), self.cli_opts.bug_number,))
      elif not self.cli_opts.recipient_file:
         log.error('Please specify either --output or --bug-number.')
         ok = False
      num_inputs = 0
      num_inputs += 1 if self.cli_opts.email_addrs else 0
      num_inputs += 1 if self.cli_opts.usernames else 0
      num_inputs += 1 if self.cli_opts.userids else 0
      if num_inputs > 1:
         log.error(
            'Cannot specify more than one of --emails, --usernames, --userids')
         ok = False
      g.assurt(self.cli_opts.split_count >= 1)
      return ok

   #
   def parse(self):
      Ccp_Script_Args.parse(self)

# *** Ccp_Cull_Emails

class Ccp_Cull_Emails(Ccp_Script_Base):

   __slots__ = (
      'not_okay',
      'user_ids',
      'invalid_ids',
      'user_infos',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      self.user_ids = []
      self.invalid_ids = []
      self.not_okay = []
      self.user_infos = []

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      self.compile_user_ids()
      try:
         last_index = 0
         # Figure out how many user IDs to record per file.
         ids_per_file = int(float(len(self.user_ids))
                            / float(self.cli_opts.split_count))
         # Create the file(s) using a 1-based naming scheme.
         for file_num in xrange(1, self.cli_opts.split_count+1):
            output_file = self.cli_opts.recipient_file
            # Add a postfix if we're creating multiple files.
            if self.cli_opts.split_count > 1:
               output_file += '.%d' % (file_num,)
            # Ask the user to overwrite existing file.
            if ((not self.cli_opts.force_overwrite)
                and os.path.exists(output_file)):
               ok = self.ask_yes_no('Overwrite existing file at "%s"?'
                                    % (output_file,))
               if not ok:
                  log.error('Please choose a different output file.')
                  sys.exit(0)
            # Open the output file and record the appropriate (sub-)set of user
            # IDs.
            output_f = open(output_file, 'w')
            if file_num < self.cli_opts.split_count:
               next_index = ids_per_file * file_num
            else:
               next_index = len(self.user_ids)
            for user_id in self.user_ids[last_index:next_index]:
               output_f.write('%d\n' % (user_id,))
            last_index = next_index
            #
            output_f.close()
      except IOError, e:
         log.error('Unable to open output file: %s' % (str(e),))

   #
   def compile_user_ids(self):

      db = db_glue.new()

      input_count = (len(self.cli_opts.email_addrs)
                     + len(self.cli_opts.usernames)
                     + len(self.cli_opts.userids))

      if self.cli_opts.email_addrs:
         self.get_user_ids_by_email_addr(db, self.cli_opts.email_addrs)
      if self.cli_opts.usernames:
         self.get_user_ids_by_username(db, self.cli_opts.usernames)
      if self.cli_opts.userids:
         self.get_user_ids_by_userid(db, self.cli_opts.userids)

      if input_count:
         log.debug('User supplied %d users / %d users okay to spam.'
                   % (input_count, len(self.user_ids),))
      else:
         # Get all IDs from the database.
         log.debug('Getting all emails from database!')
         self.get_all_user_ids(db)

      if self.invalid_ids:
         log.debug('%d users have invalid email addresses: %s'
                   % (len(self.invalid_ids), self.invalid_ids,))

      if self.not_okay:
         log.debug('%d users are not to be emailed: %s'
                   % (len(self.not_okay), self.not_okay,))

      if not self.user_ids:
         log.error('No users are okay to spam.')
         sys.exit(0)

      seen_id = set()
      culled = []
      for user_id in self.user_ids:
         if user_id not in seen_id:
            seen_id.add(user_id)
            culled.append(user_id)
         else:
            log.debug('Ignoring duplicate user_id: %d' % (user_id,))

      self.user_ids = culled

      db.close()

   #
   def get_all_user_ids(self, db):
      self.get_user_ids_by_where(db)

   #
   def get_user_ids_by_email_addr(self, db, email_addrs):
      g.assurt(email_addrs)
      if self.cli_opts.sort_mode:
         extra_where = ("email IN ('%s')"
                        % ("','".join(email_addrs),))
         self.get_user_ids_by_where(db, extra_where)
      else:
         # If the user didn't specify a sort order, use the order of the
         # email_addys on the command line.
         for email_addr in email_addrs:
            extra_where = "email = '%s'" % (email_addr,)
            self.get_user_ids_by_where(db, extra_where)

   #
   def get_user_ids_by_username(self, db, usernames):
      g.assurt(usernames)
      if self.cli_opts.sort_mode:
         extra_where = ("username IN ('%s')"
                        % ("','".join(usernames),))
         self.get_user_ids_by_where(db, extra_where)
      else:
         # If the user didn't specify a sort order, use the order of the
         # usernames from the command line.
         for username in usernames:
            extra_where = "username = '%s'" % (username,)
            self.get_user_ids_by_where(db, extra_where)

   #
   def get_user_ids_by_userid(self, db, userids):
      g.assurt(userids)
      if self.cli_opts.sort_mode:
         extra_where = ("id IN (%s)" % (",".join(userids),))
         self.get_user_ids_by_where(db, extra_where)
      else:
         # If the user didn't specify a sort order, use the order of the
         # userids from the command line.
         for userid in userids:
            extra_where = "id = '%s'" % (userid,)
            self.get_user_ids_by_where(db, extra_where)

   #
   def get_user_ids_by_where(self, db, extra_where=''):

      (user_ids, invalid_ids, not_okay, user_infos, info_lookup,
         ) = User.spam_get_user_info(db,
                                     extra_where,
                                     self.cli_opts.sort_mode,
                                     make_lookup=False,
                                     ignore_flags=self.cli_opts.ignore_flags)

      self.user_ids += user_ids
      self.invalid_ids += invalid_ids
      self.not_okay += not_okay
      self.user_infos += user_infos

   # ***

# ***

if (__name__ == '__main__'):
   cull = Ccp_Cull_Emails()
   cull.go()

