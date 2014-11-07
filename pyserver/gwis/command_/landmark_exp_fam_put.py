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

log = g.log.getLogger('cmd.lmrk.famp')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'route_system_id',
      'val',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.route_system_id = None
      self.val = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_fam_put: rte_sys_id: %s / val: %s'
         % (self.route_system_id,
            self.val,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      try:
         self.route_system_id = int(self.decode_key('route_system_id'))
         self.val = int(self.decode_key('fam'))
      except Exception, e:
         raise GWIS_Error('route_system_id and/or val not valid int(s).')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         # See login_required: this should never happen.
         raise GWIS_Error('User must be logged in.')
      else:
         sql = (
            """
            UPDATE landmark_exp_route
            SET familiarity = %d,
                done = 't',
                last_modified = now()
            WHERE username = %s
              AND route_system_id = %d
            """) % (self.val,
                    self.req.db.quoted(self.req.client.username),
                    self.route_system_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()

   # ***

# ***

