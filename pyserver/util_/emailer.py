# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import random
import subprocess
import time
import urllib
import uuid

import g
import conf

log = g.log.getLogger('util_.emailer')

# ***

class Emailer(object):

   # ***

   def __init__(self):
      g.assurt(False) # Not instantiated.

   # ***

   #
   @staticmethod
   def make_unsubscribe_link(request_cmd, email_addy, unsubscribe_proof):

      # E.g., 'http://cycloplan.cyclopath.org/gwis?
      #           request=user_nowatchers&email=someone%40gmail.com&proof=...'

      unsubscribe_link = ('http://%s/gwis?%s'
                          % (conf.server_name,
                             urllib.urlencode({
                              'request': request_cmd,
                              'email': email_addy,
                              'proof': unsubscribe_proof,}),))

      # 2014.04.24: [lb] finds that this replace() fcn is incorrect, but
      # I'm leaving the old code commented out (as opposed to deleted)
      # until I'm more confident that wasn't fixing some other problem...
      # but I just tested some emails and this code causes my email to
      # encode as %%40gmail.com which unencodes to blah%@gmail.com, and
      # then the GWIS unsubscribe command fails.
      #  # When the caller calls compose_email, we interpolate the string again,
      #  # so we have to double-down on the escape symbol.
      #  unsubscribe_link = unsubscribe_link.replace('%', '%%')

      return unsubscribe_link

   # ***

   #
   @staticmethod
   def compose_email(mail_from,
                     msg_username,
                     recipient_addr,
                     unsubscribe_proof,
                     unsubscribe_link,
                     content_subject,
                     content_plain,
                     content_html,
                     addr_bcc=''):

      # Make a dict. for string interpolation of the subject and email
      # bodies.
      body_vars = {
         'username': msg_username,
         'user_email': recipient_addr,
         'unsubscribe_proof': unsubscribe_proof,
         'unsubscribe_link': unsubscribe_link,
         }

      addr_to = 'To: %s' % (recipient_addr,)

   # FIXME: We currently hard-code Cyclopath.org
   # and don't just quote an email, or CS will postpend @cs.umn.edu, e.g.,
      # From: "info@cyclopath.org"@cs.umn.edu
      # Reply-To: "info@cyclopath.org"@cs.umn.edu

      # Make the other headers.
      addr_from = 'From: "Cyclopath.org" <%s>' % (mail_from,)
      # MAYBE: Do we need From or just Reply-To?
      addr_reply_to = ('Reply-To: "Cyclopath.org" <%s>' % (mail_from,))
      addr_subject = ('Subject: %s' % (content_subject % body_vars,))
      # Add the List-Unsubscribe indicator, which most email clients recognize.
      # See: http://www.list-unsubscribe.com/
      # We use just the http unsubscribe option.
      # List-Unsubscribe: <mailto:...>, <http://...>
      list_unsubscribe = ('List-Unsubscribe: <%s>' % (unsubscribe_link,))

      # Make the headers string.
      headers = ('%s\n%s\n%s\n%s%s\n%s\n'
                 % (addr_from,
                    addr_reply_to,
                    addr_to,
                    addr_bcc, # includes its own newline, unles it's blank.
                    addr_subject,
                    list_unsubscribe,))

      boundary_outer = 'Cyclopath==Outer==%s' % (str(uuid.uuid4()),)
      boundary_inner = 'Cyclopath==Inner==%s' % (str(uuid.uuid4()),)

      # Add the mime header, multipart delimiters, and content body.
      #
      # NOTE: Skipping the 'Bounces-to' header.
      #
      # NOTE: The '--' is special!
      #
      # 2013: [lb] had a problem w/ having "boundary" on a separate
      # 0524  line (in another script, publish_ccpv1-v2.sh) -- I had
      #       tried using no preceeding whitespace, spaces, a tab (like
      #       we originally used here, and which I think is what you
      #       should use), but the U of MN mail server kept delivering
      #       my email marked as spam (and excluding the content).
      #       So, just to be safe, moving boundary to same line as Type.
      #
      #         Content-Type: multipart/mixed; 
      #         	boundary="==%s=="
      #         
      #         --==%s==
      #         Content-Type: multipart/alternative; 
      #         	boundary="==%s=="
      #
      the_msg = (
'''%sMIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==%s=="

--==%s==
Content-Type: multipart/alternative; boundary="==%s=="

--==%s==
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 7bit

%s
--==%s==
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit

<html>
  <head>
    <title></title>
  </head>

  <body>
%s
  </body>
</html>
--==%s==--

--==%s==--
'''
         % (headers,
            boundary_outer,
            boundary_outer,
            boundary_inner,
            boundary_inner,
            content_plain % body_vars,
            boundary_inner,
            content_html % body_vars,
            boundary_inner,
            boundary_outer,
            ))

      return the_msg

   #
   @staticmethod
   def check_email(email_address):

      really_send = False

      if ((len(conf.mail_ok_addrs) == 1)
          and ('ALL_OKAY' in conf.mail_ok_addrs)):
         log.debug('check_email: conf says ALL_OKAY: %s'
                   % (email_address,))
         really_send = True

      elif email_address in conf.mail_ok_addrs:
         log.debug('check_email: email in mail_ok_addrs: %s'
                   % (email_address,))
         really_send = True

      elif not conf.mail_ok_addrs:
         log.error('check_email: mail_ok_addrs is not set: %s'
                   % (email_address,))

      else:
         # This is a dev. machine and we don't want to email users.
         log.debug('check_email: skipping non-dev email: %s'
                   % (email_address,))

      return really_send

   #
   @staticmethod
   def send_email(emailees, the_msg, prog_log, delay_time, dont_shake):

      # DEPRECATED: Using Bcc: in an email. So emailees should be a list of 1.
      g.assurt(len(emailees) == 1)
      the_emailee = emailees[0]
      log.debug('Emailing user at: %s' % (the_emailee,))

      # If this is a DEV machine, CONFIG should only let YOUR email through.
      if Emailer.check_email(the_emailee):

         Emailer.send_email_(the_msg, prog_log, delay_time, dont_shake)

   #
   @staticmethod
   def send_email_(the_msg, prog_log, delay_time, dont_shake):

      #new_stdin = StringIO.StringIO(the_msg)
      #sys.stdin = new_stdin

      try:

         # Tell sendmail to make the recipients from the headers, otherwise
         #  it'll complain "Recipient names must be specified" (-t).
         #  From man: "-t Read  message for recipients. To:, Cc:, and Bcc:
         #             lines will be scanned for recipient addresses. The
         #             Bcc: line will be deleted before transmission."
         extract_recipients = '-t'

         # The original spam.py uses check_call, to which cannot be piped.
         #   subprocess.check_call(['sendmail',], stdin=some_file)
         p = subprocess.Popen(['sendmail', extract_recipients,], 
                              shell=False, # FIXME: Elsewhere in Ccp is True
                              # bufsize=bufsize,
                              stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,
                              close_fds=True
                              )
         (sin, sout_err) = (p.stdin, p.stdout)
         # Quack like a duck -- make the string into a true pipe.
         #   http://stackoverflow.com/questions/163542/python-how-do-i-pass-a-string-into-subprocess-popen-using-the-stdin-argument
         #the_msg += '\n'
         # So, communicate what's for the process to exit, but it doesn't,
         # so this hanges.
         #   http://stackoverflow.com/questions/2408650/why-does-python-subprocess-hang-after-proc-communicate
         #resp = p.communicate(input=the_msg)
         #resp_stdout = resp[0]
         #resp_stderr = resp[1]
         # The Python docs warn about writing to stdin -- if we send too
         # much data and fill up stdin, we'll deadlock, because we won't
         # give the process we're calling time to empty the buffer. So let's
         # just hope our emails are of reasonable size, eh?
         log.debug('Writing to process: %s' % (the_msg,))
         p.stdin.write(the_msg)
         # 2012.11.12: [lb] has to do this on his laptop (Fedora, with sendmail
         # linked to gmail SMTP, instead). He doesn't quite remember but
         # doesn't remember this being necessary when he's run the script on
         # huffy (Ubuntu, on the CS network).
         p.stdin.close()
         # NOTE: Do not read p.stdout. It'll hang or throw an error.
         # NO: resp_stdout = p.stdout.read()
         g.assurt(p.stderr is None)
         # FIXME: Do we need to readline?
         while True:
            line = sout_err.readline()
            if not line:
               break
            log.warning('sendmail: %s' % (line,))
         sin.close()
         sout_err.close()
         p.wait()
      except subprocess.CalledProcessError, e:
         log.error('check_call failed: %s' % (str(e),))
         raise
      #finally:
      #   sys.stdin = sys.__stdin__

      if prog_log is not None:
         prog_log.loops_inc()

      if delay_time:
         if not dont_shake:
            # The random fcn. returns a value in the range [0.0, 1.0).
            mod_by = 0.5 - random.random()
            # We have a number [-0.5, 0.5).
            delay_time = (delay_time + (delay_time * mod_by))
         time.sleep(delay_time)

   # ***

# ***

