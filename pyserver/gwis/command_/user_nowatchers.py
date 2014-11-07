# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# C.f. pyserver/gwis/command/user_unsubscribe.py

import os
import sys
import uuid

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item.util.watcher_frequency import Watcher_Frequency
#from util_ import misc

log = g.log.getLogger('cmd.nowtchrs')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'email_supplied',
      'proof_supplied',
      'no_watchers_ok',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.email_supplied = None
      self.proof_supplied = None
      self.no_watchers_ok = None

   # ***

   #
   def __str__(self):
      selfie = (
         'usr_nowtchrs: email_sppld: %s / proof_sppld: %s / no_watchers_ok: %s'
         % (self.email_supplied,
            self.proof_supplied,
            self.no_watchers_ok,))
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
         self.no_watchers_ok = True
      else:
         self.no_watchers_ok = False

   #
   def prepare_response(self):
      log.verbose('prepare_response')
      html_header = (
"""<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>Cyclopath Geowiki: Disable Item Alerts</title>
</head>
<body>""")
      html_footer = (
"""</body>
</html>""")
      if self.no_watchers_ok:
         self.req.htmlfile_out = (
"""%s
<p><b>Disabled Watchers</b><br/></p>
<p>All item alerts with your email address, <i>%s</i>, have been
disabled. You can re-enable item alerts by logging on to Cyclopath
and re-enabling alerts in your Item Alerts options.<br/></p>
%s
""" % (html_header, self.email_supplied, html_footer,))
         #
      else:
         self.req.htmlfile_out = (
"""%s
<p><b>Cannot Disable Watchers</b><br/></p>
<p>Item watchers for the specified email address, <i>%s</i>, could not be 
disabled: either the email is not attached to any user account,
or the hyperlink you've just used is broken.<br/></p>
<p>Please email <a href="mailto:%s">%s</a> if you need more help.</p>
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

      # MAYBE/BUG nnnn: Make it easier to reenable watchers? For, from the Item Alerts
      #                 panel, users can open each item's panel and modify watchers
      #                 from there.
      update_sql = (
         """
         UPDATE user_ SET enable_watchers_email = FALSE WHERE email = '%s'
         """ % (self.email_supplied,))

      db.sql(update_sql)

      log.debug('fetch_n_save: unsubscribe email: %s / count: %d'
                % (self.email_supplied, db.curs.rowcount,))

      db.transaction_commit()

   # ***

# ***

