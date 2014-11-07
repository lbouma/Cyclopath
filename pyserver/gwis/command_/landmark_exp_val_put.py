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
from item.util.landmark import Landmark
from util_ import gml
from util_ import misc

log = g.log.getLogger('cmd.lmrk.lput')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'route_system_id',
      'rating',
      'landmark',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.route_system_id = None
      self.rating = None
      self.landmark = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_val_put: rte_sys_id: %s / rating: %s / landmark: %s'
         % (self.route_system_id,
            self.rating,
            self.landmark,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      try:
         self.route_system_id = int(self.decode_key('route_system_id'))
         self.rating = int(self.decode_key('rating'))
      except Exception, e:
         raise GWIS_Error('route_system_id and/or val not valid int(s).')
      for l_xml in self.req.doc_in.findall('./lmrk'):
         self.landmark = Landmark(l_xml.get('name'),
                                  l_xml.get('item_id'),
                                  l_xml.get('type_id'),
                                  None,
                                  l_xml.get('step'))

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         raise GWIS_Error('User must be logged in.')
      else:
      
         sql = """
         SELECT count(*) as ct
            FROM landmark_exp_validation
            WHERE username = %s
               AND route_system_id = %s
               AND landmark_id = %s
               AND landmark_type_id = %s
               AND step_number = %s
         """
         rows = self.req.db.sql(sql,
            (self.req.client.username,
             self.route_system_id,
             self.landmark.item_id,
             self.landmark.type_id,
             self.landmark.step_number,))
         if (len(rows) > 0) and (rows[0]['ct'] > 0):
            sql = """
            UPDATE landmark_exp_validation
            SET rating = %s
            WHERE
               username = %s
               AND route_system_id = %s
               AND landmark_id = %s
               AND landmark_type_id = %s
               AND step_number = %s
            """
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql,
               (self.rating,
                self.req.client.username,
                self.route_system_id,
                self.landmark.item_id,
                self.landmark.type_id,
                self.landmark.step_number,))
            self.req.db.transaction_commit()
         else:
            sql = """
            INSERT INTO landmark_exp_validation
               (username,
                route_system_id,
                rating,
                landmark_id,
                landmark_type_id,
                landmark_name,
                step_number,
                created)
            VALUES
               (%s, %s, %s, %s, %s, %s, %s, now())
            """
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql,
               (self.req.client.username,
                self.route_system_id,
                self.rating,
                self.landmark.item_id,
                self.landmark.type_id,
                self.landmark.name,
                self.landmark.step_number,))
            self.req.db.transaction_commit()

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

   # ***

# ***

