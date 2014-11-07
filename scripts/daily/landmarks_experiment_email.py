#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script sends email reminders for the landmarks experiment.

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
#print 'curdir: %s' % (os.curdir,) # .
#print 'abspath: %s' % (os.path.abspath(os.curdir),) # my home dir...
pyglue_path = os.path.abspath('%s/../util' % (os.path.abspath(os.curdir),))
#print 'pyglue_path: %s' % (pyglue_path,) # .
sys.path.insert(0, pyglue_path)

import pyserver_glue

import conf
import g

# Setup logging first, lest g.log.getLogger return the base Python Logger().
import logging
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
log = g.log.getLogger('lndmrksEmail')

from util_ import db_glue
from util_.emailer import Emailer

# ***

if (__name__ == '__main__'):

   # TEST_ME: 2013.11.08: [lb] updated this to use Emailer.send, so that
   # CONFIG.mail_ok_addrs is checked, and to use HTML, so that the link
   # is clickable, and to get the email address, but the experiment has been
   # disabled. So this changed code is untested...

   db = db_glue.new()

   res = db.sql(
      """
      SELECT
         lt.username,
         lt.trial_num,
         u.email
         -- Skipping: enable_email, enable_email_research, email_bouncing
      FROM
         landmark_trial AS lt
      JOIN
         user_ AS u ON (lt.username = u.username)
      WHERE
         condition = 'later'
         AND (track_id > 0)
         AND (NOT email_sent)
         AND ((trial_time + interval '1 hour') < now())
      """
   )

   email_subject = (
      'Cyclopath notice: Please help us by adding landmarks along your ride')

   for row in res:

      link_uri = ('http://%s#landmarks?trial=%s'
                  % (conf.server_names[0], # E.g., cycloplan.cyclopath.org
                     row['trial_num'],))

      msg_text = ('''\
Hi,

Earlier today we asked you to look out for useful navigation landmarks while
you recorded your bike ride. To add the landmarks, please visit the following
link:

%s

You can open the link in either the web browser or the mobile app. In order to
make the process easier for you, we will show you your ride and the locations
where we prompted you to look for landmarks.

Thank you for helping us test this feature!
      ''' % (link_uri,))

      msg_html = ('''\
<p>
Hi,
</p>

<p>
Earlier today we asked you to look out for useful navigation landmarks while
you recorded your bike ride. To add the landmarks, please visit the following
link:
</p>

<p>
<a href="%s">%s</a>
</p>

<p>
You can open the link in either the web browser or the mobile app. In order to
make the process easier for you, we will show you your ride and the locations
where we prompted you to look for landmarks.
</p>

<p>
Thank you for helping us test this feature!
</p>
      ''' % (link_uri,
             link_uri,))

      unsubscribe_proof = None
      unsubscribe_link = None
      the_msg = Emailer.compose_email(
         conf.mail_from_addr,
         row['username'],
         row['email'],
         unsubscribe_proof,
         unsubscribe_link,
         email_subject,
         msg_text,
         msg_html)

      Emailer.send_email(
         [row['email'],],
         the_msg,
         prog_log=None,
         delay_time=None,
         dont_shake=None)

      # After sending summary email, delete the entries from the pending table.
      db.sql(
         """
         UPDATE landmark_trial
         SET email_sent = 't'
         WHERE username = '%s'
            AND trial_num = %s
         """ % (row['username'], row['trial_num'],))

   # end: for

   db.transaction_commit()

   db.close()

   # ***

# ***

