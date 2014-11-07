# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import random
import sys
import time

import conf
import g

from gwis import command
from util_ import misc

log = g.log.getLogger('cmd.lmrk.tput')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'trial_num',
      'track_id',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.trial_num = None
      self.track_id = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_trial_put: trial_num: %s / track_id: %s'
         % (self.trial_num,
            self.track_id,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.trial_num = self.decode_key('trial_num')
      self.track_id = self.decode_key('tid')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      if ((self.req.client.username)
          and (self.req.client.username != conf.anonymous_username)):

         sql = (
            """
            UPDATE landmark_trial
            SET
               track_id = %s
            WHERE
               username = %s
               AND trial_num = %s
            """) % (self.track_id,
                    self.req.db.quoted(self.req.client.username),
                    self.trial_num,)
         log.debug(sql)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()

   # ***

# ***

