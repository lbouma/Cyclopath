#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Send an e-mail message to all the e-mail addresses in a file, waiting a
# specified number of seconds between each message.

# Usage:
#
#  $ ./spam.py --help
#
# Also:
#
#  $ ./spam.py |& tee 2012.09.12.spam.txt
#

'''

# DEVS: If you use --bcc-size (i.e., use Bcc:), the To: address 
#       is info@cyclopath.org. So the group gets an email while 
#       you test. Also, it makes the message more impersonal, so
#       don't use it.
#   --mail-from "devs.email@gmail.com" \
#   --bcc-size 3

# NOTE: Use single quotes to protect the bang (exclamation mark). If you don't
# escape it, i.e., \!, bash complains, but if you do, the email includes the
# backslash. This usage shows how to use both double and single quotes.
./spam.py \
   --subject "Cyclopath says sorry and invites you to log in again"'!' \
   --recipients "/ccp/bin/ccpdev/schema/runic/2012.09.12/recipient_file" \
   --plain "/ccp/bin/ccpdev/schema/runic/2012.09.12/content_plain" \
   --html "/ccp/bin/ccpdev/schema/runic/2012.09.12/content_html" \
   --delay-time 0.3 \
   --delay-shake

'''

script_name = ('Spam! Lovely Spam!')
script_version = '1.2'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-11-12'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
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

log = g.log.getLogger('spam')

# *** 

import random
import StringIO
import subprocess
from subprocess import Popen, PIPE, STDOUT
import time

from grax.user import User
from util_ import db_glue
from util_ import misc
from util_.emailer import Emailer
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self, exclude_normal=True)

      self.add_argument('--subject', dest='email_subject',
         action='store', default='', type=str, required=True,
         help='the subject of the email')

      #
      self.add_argument('--recipients', dest='recipient_file',
         action='store', default=None, type=str, required=False,
         help='file of user IDs (or maybe usernames or email addresses')
      #
      self.add_argument('--plain', dest='content_plain',
         action='store', default=None, type=str, required=False,
         help='file containing the email plaintext')
      #
      self.add_argument('--html', dest='content_html',
         action='store', default=None, type=str, required=False,
         help='file containing the email html')
      # Or, instead of the last three:
      self.add_argument('--bug-number', dest='bug_number',
         action='store', default=None, type=int, required=False,
         help='the bug number, if you want to use standard paths and names')
      #
      self.add_argument('--file-number', dest='file_number',
         action='store', default=None, type=int, required=False,
         help='the file number of the emails_for_spam-created file')

      #
      self.add_argument('--test', dest='send_test_emails',
         action='store_true', default=False,
         help='if set, send emails to the users listed in the test file')
      #
      self.add_argument('--test-file', dest='test_emails_file',
         action='store', type=str, required=False,
         default='/ccp/bin/ccpdev/schema/runic/spam_test_uids',
         help='the location of the test email user IDs')
      # To test the code without sending even test emails, try this.
      self.add_argument('--do-not-email', dest='do_not_email',
         action='store_true', default=False, required=False,
         help='do not even send test emails, just test the code.')
      # Generally when you test you'll want to ignore dont_study, etc.
      self.add_argument('--ignore-flags', dest='ignore_flags',
         action='store_true', default=False, required=False,
         help='always email, even if dont_study.')

      #
      # MAGIC_NUMBER: 0.3 seconds seems... reasonable. We've not tested
      #               anything smaller (circa 2012.11.12).
      self.add_argument('--delay-time', dest='delay_time',
         action='store', default=0.3, type=float,
         help='if nonzero, wait time between sendmail calls')
      #
      self.add_argument('--dont-shake', dest='dont_shake',
         action='store_true', default=True,
         help='if set, use a variable delay time each time')

      #
      self.add_argument('--mail-from', dest='mail_from',
         action='store', default=conf.mail_from_addr, type=str,
         help='used to override CONFIG.mail_from_addr')
      #
      self.add_argument('--bcc-size', dest='bcc_size',
         action='store', default=0, type=int,
         help='number of recipients to Bcc at once (per sendmail call)')

# FIXME: The plain and html files should allow interpolation, 
# i.e., username, email, etc.

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      #
      if ((self.cli_opts.recipient_file
           or self.cli_opts.content_plain
           or self.cli_opts.content_html)
          and self.cli_opts.bug_number):
         log.error('%s%s'
            % ('Please specify either recipient_file, content_plain, and ',
               'content_html, or --bug-number, not both',))
         ok = False
      elif self.cli_opts.bug_number:
         self.cli_opts.recipient_file = (
            '/ccp/bin/ccpdev/schema/runic/bug_%s/recipient_file'
            % (self.cli_opts.bug_number,))
         if self.cli_opts.file_number:
            self.cli_opts.recipient_file += (
               '.%d' % (self.cli_opts.file_number,))
         self.cli_opts.content_plain = (
            '/ccp/bin/ccpdev/schema/runic/bug_%s/content_plain'
            % (self.cli_opts.bug_number,))
         self.cli_opts.content_html = (
            '/ccp/bin/ccpdev/schema/runic/bug_%s/content_html'
            % (self.cli_opts.bug_number,))
      elif (not (self.cli_opts.recipient_file
                 and self.cli_opts.content_plain
                 and self.cli_opts.content_html)):
         log.error('%s%s'
                   % ('Please specify either --recipient-file, --plain, ',
                      'and --html, or --bug-number.',))
      #
      file_paths = [
         self.cli_opts.recipient_file,
         self.cli_opts.content_plain,
         self.cli_opts.content_html,
         ]
      if self.cli_opts.send_test_emails:
         file_paths.append(self.cli_opts.test_emails_file)
      for fpath in file_paths:
         if not os.path.exists(fpath):
            log.error('File does not exist: "%s"' % (fpath,))
            ok = False
      #
      if self.cli_opts.send_test_emails:
         self.cli_opts.recipient_file = self.cli_opts.test_emails_file
      #
      return ok

   #
   def parse(self):
      Ccp_Script_Args.parse(self)

# *** Ccp_Send_Emails

class Ccp_Send_Emails(Ccp_Script_Base):

   __slots__ = (
      'headers',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      self.headers = ''

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      # Get the content templates.

      content_plain_f = open(self.cli_opts.content_plain)
      content_plain = content_plain_f.read()
      content_plain_f.close()

      content_html_f = open(self.cli_opts.content_html)
      content_html = content_html_f.read()
      content_html_f.close()

      # Assemble the recipients.

      # The file should be of the form
      #
      #   username\temail_address
      #
      # PERFORMANCE: Cyclopath circa 2012 doesn't have that many users (~5,000)
      # so we can load all the emails into memory. If we end up with lots more
      # users, this operation might take a sizeable bite of memory.

      recipients = []
      user_ids = []

      recipients_f = open(self.cli_opts.recipient_file)
      try:
         deprecation_warned = False
         for line in recipients_f:
            line = line.strip()
            # NOTE: Skip comment lines.
            if line and (not line.startswith('#')):
               try:
                  fake_uid = 0
                  username, email = line.split('\t')
                  # NOTE: unsubscribe_proof is unknown since we don't
                  #       select from db, which is why this path is deprecated.
                  unsubscribe_proof = ''
                  recipients.append(
                     (fake_uid, username, email, unsubscribe_proof,))
                  if not deprecation_warned:
                     log.warning('Using username/email file is deprecated.')
                     deprecation_warned = True
               except ValueError:
                  user_id = int(line)
                  user_ids.append(user_id)
      except ValueError:
         log.error('The format of the recipient file is unexpected / line: %s'
                   % (line,))
         raise
      finally:
         recipients_f.close()

      if recipients and user_ids:
         log.error(
            'Please specify only "username, email" or "user IDs" but not both')
         sys.exit(0)

      db = db_glue.new()

      if user_ids:
         extra_where = ("id IN (%s)" % (",".join([str(x) for x in user_ids]),))
         (valid_ids, invalid_ids, not_okay, user_infos, info_lookup) = (
            User.spam_get_user_info(
               db, extra_where, sort_mode='id ASC', make_lookup=True,
               ignore_flags=self.cli_opts.ignore_flags))
         if invalid_ids or not_okay:
            log.error('%s%s'
                      % ('Please recheck the user ID list: ',
                         '%d okay / %d invalid / %d not_okay'
                         % (len(valid_ids), len(invalid_ids), len(not_okay),)))
            log.error('not_okay: %s' % (not_okay,))
            sys.exit(0)
         g.assurt(len(set(valid_ids)) == len(set(user_infos)))
         g.assurt(len(set(valid_ids)) == len(set(user_ids)))
         # Resort according to the input.
         for uid in user_ids:
            # NOTE: info_tuple is formatted: (user_id, username, email,)
            recipients.append(info_lookup[uid])

      all_okay = True
      for info_tuple in recipients:
         if not User.email_valid(info_tuple[2]):
            log.error('Invalid email for user %s: %s'
                      % (info_tuple[1], info_tuple[2],))
            all_okay = False
      if not all_okay:
         sys.exit(0)

      log.debug('Found %d recipients.' % (len(recipients),))
      if not recipients:
         log.info('No one to email. Bye!')
         sys.exit(0)

      # Always send a copy to us, too.
      g.assurt(conf.internal_email_addr)
      unsubscribe_proof = ''
      recipients.append(
         (0, 'Cyclopath Team', conf.internal_email_addr, unsubscribe_proof,))

      # Combine recipients if bcc'ing.

      if self.cli_opts.bcc_size:
         addr_lists = []
         addrs_processed = 0
         while addrs_processed < len(recipients):
            last_index = addrs_processed + self.cli_opts.bcc_size
            bcc_list = recipients[addrs_processed:last_index]
            g.assurt(bcc_list)
            addrs_processed += self.cli_opts.bcc_size
            addr_lists.append(bcc_list)
         recipients = addr_lists
         # 2012.11.12: Using bcc is not cool. Don't do it.
         log.error('BCC is too impersonal. Please consider not using it.')
         g.assurt(False)

      # Process the recipients one or many at a time.

      prompted_once = False

      prog_log = Debug_Progress_Logger(loop_max=len(recipients))
      # MAYBE: Don't log for every email?
      #prog_log.log_freq = prog_log.loop_max / 100.0

      for recipient_or_list in recipients:

         email_unames = []

         # Make the To and Bcc headers.
         if self.cli_opts.bcc_size:
            g.assurt(False) # DEVs: Reconsider using BCC.
                            # Otherwise you cannot personalize messages, i.e.,
                            # with usernames of private UUID links.
            # Use a generic user name, since there are multiple recipients.
            msg_username = 'Cyclopath User'
            # Send the email to ourselves...
            recipient_email = self.cli_opts.mail_from
            recipient_addr = ('"Cyclopath.org" <%s>' 
                              % (self.cli_opts.mail_from,))
            # ...and Bcc everyone else.
            email_addrs = []
            for recipient in recipient_or_list:
               # C.f. emailer.check_email, but using Bcc is deprecated, so
               # don't worry about it.
               msg_username = recipient[1]
               recipient_email = recipient[2]
               really_send = False
               if ((len(conf.mail_ok_addrs) == 1)
                   and ('ALL_OKAY' in conf.mail_ok_addrs)):
                  log.debug('go_main: conf says ALL_OKAY: %s'
                            % (recipient_addr,))
                  really_send = True
               elif recipient_email in conf.mail_ok_addrs:
                  log.debug('go_main: email in mail_ok_addrs: %s'
                            % (recipient_addr,))
                  really_send = True
               elif not conf.mail_ok_addrs:
                  log.error('go_main: mail_ok_addrs is not set: %s'
                            % (recipient_addr,))
               else:
                  # This is a dev. machine and we don't want to email users.
                  log.debug('go_main: skipping non-dev email: %s'
                            % (recipient_addr,))
               if really_send:
                  log.debug('Emailing user at: %s' % (recipient_addr,))
                  email_addr = ('"%s" <%s>' % (msg_username, recipient_email,))
                  email_addrs.append(email_addr)
                  email_unames.append(msg_username)
            addrs_str = ','.join(email_addrs)
            addr_bcc = 'Bcc: %s\n' % (addrs_str,)
            unsubscribe_proof = ''
            unsubscribe_link = ''
         else:
            # This is just a normal, send-directly-to-one-user email.
            msg_username = recipient_or_list[1]
            recipient_email = recipient_or_list[2]
            recipient_addr = ('"%s" <%s>' % (msg_username, recipient_email,))
            email_unames.append(recipient_email)
            addr_bcc = ''
            unsubscribe_proof = recipient_or_list[3]
            unsubscribe_link = Emailer.make_unsubscribe_link(
               'user_unsubscribe', recipient_email, unsubscribe_proof)

            # To test the unsubscribe feature, try a link like this:
# http://ccpv3/gwis?request=user_unsubscribe&email=somewhere@domain.tld&proof=asdasdasd

         db.close()

         the_msg = Emailer.compose_email(
            self.cli_opts.mail_from,
            msg_username,
            recipient_addr,
            unsubscribe_proof,
            unsubscribe_link,
            self.cli_opts.email_subject,
            content_plain,
            content_html,
            addr_bcc)

         if not prompted_once:
            do_send = self.ask_permission(the_msg)
            if not do_send:
               log.warning('Canceled by user. Bye!')
               sys.exit(0)
            prompted_once = True

         # NOTE: Emailer.send_email will check conf.mail_ok_addrs.
         # ALSO: This is the only place/caller/script that uses do_not_email.
         #       It's really just for testing, and this is the last stop.
         if not self.cli_opts.do_not_email:
            Emailer.send_email(
               email_unames,
               the_msg,
               prog_log,
               self.cli_opts.delay_time,
               self.cli_opts.dont_shake)

      # end: for recipient_or_list in recipients.

      prog_log.loops_fin()

   #
   def ask_permission(self, the_msg):

      print ('Please confirm the settings:\n')

      print ('  %s sec. delay' % (self.cli_opts.delay_time,))
      print ('  %s recipient%s per email' 
               % ('1' if self.cli_opts.bcc_size else '0',
                  's' if self.cli_opts.bcc_size else '',))
      print ('  recipient_file: %s' % (self.cli_opts.recipient_file,))
      print ('  content_plain: %s' % (self.cli_opts.content_plain,))
      print ('  content_html: %s' % (self.cli_opts.content_html,))

      print ('\nHere is the first message we will sendmail:\n')
      print (the_msg)
      print ('')

      msg = 'Proceed and send emails?'
      yes = self.ask_yes_no(msg)

      return yes

   # ***

# ***

if (__name__ == '__main__'):
   spam = Ccp_Send_Emails()
   spam.go()

