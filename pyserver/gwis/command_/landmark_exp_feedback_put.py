# Copyright (c) 2006-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import random
import sys
import time

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from util_ import misc

log = g.log.getLogger('cmd.lmrk.fbkp')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'feedback',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.feedback = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_feedback_put: feedback: %s'
         % (self.feedback,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.feedback = self.req.doc_in.findall('./feedback')[0].text

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         raise GWIS_Error('User must be logged in.')
      else:
         sql = (
            """
            INSERT INTO landmark_exp_feedback
               (username, feedback, time_submitted)
            VALUES
               (%s, %s, now())
            """)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql, (self.req.client.username, self.feedback,))
         self.req.db.transaction_commit()

   # ***

# ***

