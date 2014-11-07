# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import smtplib

import conf
import g

from util_ import db_glue
import VERSION

log = g.log.getLogger('user_email')

# FIXME Class-ify module?

# Map flag names to database columns.
flag_db_map = {
   'enable-email': 'enable_email',
   'enable-research-email': 'enable_email_research',
   'enable-wr-digest': 'enable_watchers_digest',
   'dont-study': 'dont_study',
   'bouncing': 'email_bouncing',
   'login-permitted': 'login_permitted',
   }

def flags_get(db, username):
   'Return dictionary of e-mail flags and their values for username.'
   log.verbose('flags_get: user %s' % (username,))
   results = db.sql((
      """
      SELECT %s
      FROM user_
      WHERE username = %s
      """ % (", ".join(flag_db_map.values()), db.quoted(username),)))
   g.assurt(len(results) == 1)
   d = dict()
   for key in flag_db_map.keys():
      d[key] = results[0][flag_db_map[key]]
   return d

def flag_get(db, username, flag):
   'Return true if e-mail flag flag is set for user username, false otherwise.'
   return flags_get(db, username)[flag]
    

def flag_set(db, username, flag, value):
   'Set e-mail flag flag for username to value.'
   db.sql(("UPDATE user_ SET %s = %%s WHERE username = %%s"
           % (flag_db_map[flag],)),
          (value, username,))

def addr_get(db, username, validate=True):
   '''Return the e-mail address for username. If validate is true and e-mail
      to the user is not permitted, return None.'''
   rows = db.sql(
      """
      SELECT
         email,
         login_permitted,
         email_bouncing,
         enable_email
      FROM
         user_
      WHERE
         username = %s
      """, (username,))
   g.assurt(len(rows) == 1)
   user = rows[0]
   if (validate and (not user['login_permitted']
                     or user['email_bouncing']
                     or not user['enable_email']
                     or (user['email'] == ''))):
      return None
   return user['email']

# FIXME: 2012.08.16. This whole file needs to be a class. Needs To Be.

#
def send(db, touser, toaddr, subject, body):
   '''Send an e-mail to username touser at address toaddr.

      If toaddr is None, look it up in the database db. Otherwise, sent to the
      given toaddr regardless of the address's valididy or whether or not the
      user wants e-mail (use with caution!).'''

# Bug 2717 - Security Problem: Server Blindly Accepts Usernames to Email
# FIXME: Can we add extra constraints herein so we don't get hacked and 
#        email 100s of people?

   g.assurt(False) # Deprecated: See: util_.emailer.Emailer.send_email.

   fromaddr = conf.mail_from_addr
   if (toaddr is None):
      toaddr = addr_get(db, touser)
      if (toaddr is None):
         log.info("can't send e-mail to %s by prefs" % (touser))
         return
   version = VERSION.major

   server_addy = conf.server_name
   contact_addy = conf.mail_from_addr

   msg = ('''\
To: %(toaddr)s
From: %(fromaddr)s
Subject: %(subject)s
X-Cyclopath-Flamingo: Yes
X-Cyclopath-User-To: %(touser)s

%(body)s

Thank you,
Cyclopath

This email was automatically sent to you because you are a Cyclopath user and your user preferences indicate that you would like to receive these types of email. You can change your preferences at http://%(server_addy)s or you can email %(contact_addy)s.
--
Sent by Cyclopath server software version %(version)s
''' % locals())
# FIXME: See where else the server addy is hard-coded and use conf.server_name
#        instead. Do the same for info@cyclopath.org.


   g.assurt(False) # See: Emailer.send_email. And: mail_ok_addrs: ALL_OKAY
   if ((conf.mail_ok_addrs is None) or (toaddr in conf.mail_ok_addrs)):
      server = smtplib.SMTP(conf.mail_host)
      server.sendmail(fromaddr, toaddr, msg)
      server.quit()
      log.info('e-mail sent: %s/%s %s' % (touser, toaddr, subject))
   else:
      log.warning('e-mail suppressed: %s/%s %s' % (touser, toaddr, subject))

def usernames_get(db, email):
   '''Return a (perhaps empty) iterable of usernames corresponding to the
      email address email.'''
   rows = db.sql("SELECT username FROM user_ WHERE email = %s", (email,))
   return [row['username'] for row in rows]

if (__name__ == '__main__'):
   import sys
   db = db_glue.new()
   toaddr = None if (sys.argv[2] == '') else sys.argv[2]
   print '-> %s %s; subj "%s"' % (sys.argv[1], toaddr, sys.argv[3])
   send(db, sys.argv[1], toaddr, sys.argv[3], 'this is a test')
   db.close()

