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

log = g.log.getLogger('cmd.lmrk.plog')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'trial_num',
      'node_id',
      'p_num',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.trial_num = None
      self.node_id = None
      self.p_num = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_prompt_log: trial_num: %s / node_id: %s / p_num: %s'
         % (self.trial_num,
            self.node_id,
            self.p_num,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.trial_num = self.decode_key('trial_num')
      self.node_id = self.decode_key('nid')
      self.p_num = self.decode_key('p_num')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      if ((self.req.client.username)
          and (self.req.client.username != conf.anonymous_username)):

         sql = (
            """
            INSERT INTO landmark_prompt
               (username, trial_num, prompt_num, prompt_time, node_id)
            VALUES
               (%s, %s, %s, now(), %s)
            """) % (self.req.db.quoted(self.req.client.username),
                    self.trial_num,
                    self.p_num,
                    self.node_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()

   # ***

# ***

