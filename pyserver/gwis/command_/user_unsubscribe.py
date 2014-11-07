# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# For use with the spam.py script, uses a UUID to unsubscribe users from mails.

import os
import sys
import uuid

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
#from util_ import misc

log = g.log.getLogger('cmd.unsbscrb')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'email_supplied',
      'proof_supplied',
      'unsubscribe_ok',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.email_supplied = None
      self.proof_supplied = None
      self.unsubscribe_ok = None

   # ***

   #
   def __str__(self):
      selfie = (
         'user_unsubscrb: email_sppld: %s / proof_sppld: %s / unsubscrb_ok: %s'
         % (self.email_supplied,
            self.proof_supplied,
            self.unsubscribe_ok,))
      return selfie

   # ***

   #
   def pre_decode(self):
      command.Op_Handler.pre_decode(self)

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self, expect_no_token=True)
      g.assurt(not self.req.client.username)
      self.req.client.username = conf.anonymous_username
      self.email_supplied = self.decode_key('email')
      self.proof_supplied = self.decode_key('proof')
      # Verify that the UUID is a UUID.
      try:
         just_testing = uuid.UUID(self.proof_supplied)
      except ValueError, e:
         raise GWIS_Error('The indicated UUID is not formatted correctly.')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      # Verify the email and UUID.
      proven_sql = (
         "SELECT * FROM user_ WHERE email = '%s' AND unsubscribe_proof = '%s'"
         % (self.email_supplied, self.proof_supplied,))
      rows = self.req.db.sql(proven_sql)
      if rows:
         g.assurt(len(rows) == 1)
         success = self.req.db.transaction_retryable(self.attempt_save,
                                                     self.req)
         self.unsubscribe_ok = True
         # Not really a warning but [lb] wants a logcheck email.
         log.error('fetch_n_save: unsubscribed email: %s'
                   % (self.email_supplied,))
      else:
         self.unsubscribe_ok = False
         log.error('fetch_n_save: cannot unsubscribe: %s'
                   % (self.email_supplied,))

   #
   def prepare_response(self):
      log.verbose('prepare_response')
      html_header = (
"""<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>Cyclopath Geowiki: Unsubscribe</title>
</head>
<body>""")
      html_footer = (
"""</body>
</html>""")
      if self.unsubscribe_ok:
         self.req.htmlfile_out = (
"""%s
<p><b>Unsubscribed</b><br/></p>
<p>Your email address, <i>%s</i>, has been removed
from the Cyclopath mailing list.<br/></p>
%s
""" % (html_header, self.email_supplied, html_footer,))
         # BUG nnnn: How does a user resubscribe?
         #           We need user pref option in flashclient.
# <p>
# If you'd like to resubscribe, please visit Cyclopath and change your
# <a href="http://%s/#user_prefs">user preferences</a>.
# </p>
         #
      else:
         self.req.htmlfile_out = (
"""%s
<p><b>Cannot Unsubscribe</b><br/></p>
<p>The specified email address, <i>%s</i>, could not be removed from the
Cyclopath mailing list: either the email is not attached to any user account,
or the unsubscribe link you're using is broken.<br/></p>
<p>Please email <a href="mailto:%s">%s</a> if you would like further
assistance.</p>
%s
""" % (html_header,
       self.email_supplied,
       conf.mail_from_addr,
       conf.mail_from_addr,
       html_footer,))
      log.error('prepare_response: self.req.htmlfile_out: %s'
                % (self.req.htmlfile_out,))

   # ***

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      db.transaction_begin_rw()

      # In lieu of user_email.flag_set(db, username, option, value), which
      # just updates one user by username, update all users with this email
      # address.
      update_sql = (
         """
         UPDATE user_ SET enable_email = FALSE,
            enable_email_research = FALSE WHERE email = '%s'
         """ % (self.email_supplied,))

      db.sql(update_sql)

      log.debug('fetch_n_save: unsubscribe email: %s / count: %d'
                % (self.email_supplied, db.curs.rowcount,))

      db.transaction_commit()

   # ***

# ***

