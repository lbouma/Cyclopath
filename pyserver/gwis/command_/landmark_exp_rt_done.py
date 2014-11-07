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

log = g.log.getLogger('cmd.lmrk.done')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'route_system_id',
      'route_user_id',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.route_system_id = None
      self.route_user_id = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_rt_done: rte_sys_id: %s / route_user_id: %s'
         % (self.route_system_id,
            self.route_user_id,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      try:
         self.route_system_id = int(self.decode_key('route_system_id'))
      except Exception, e:
         raise GWIS_Error('route_system_id not a valid int.')
      self.route_user_id = self.decode_key('route_user_id', None)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         raise GWIS_Error('User must be logged in.')
      else:
         log.debug('fetch_n_save: user finished route: %s / %s'
                   % (self.req.client.username, self.route_system_id,))
         if (self.route_user_id is None):
            sql = (
               """
               UPDATE landmark_exp_route
               SET done = 't',
                   last_modified = now()
               WHERE
                  username = %s
                  AND route_system_id = %s
               """) % (self.req.db.quoted(self.req.client.username),
                       self.route_system_id,)
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql)
            self.req.db.transaction_commit()
         else:
            sql = (
               """
               UPDATE landmark_exp_route_p2_users
               SET done = 't'
               WHERE
                  username = %s
                  AND route_system_id = %s
                  AND route_user_id = %s
               """) % (self.req.db.quoted(self.req.client.username),
                       self.route_system_id,
                       self.route_user_id,)
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql)
            self.req.db.transaction_commit()
         

   # ***

# ***

