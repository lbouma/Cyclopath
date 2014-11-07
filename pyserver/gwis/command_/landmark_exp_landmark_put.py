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
      'landmarks',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.route_system_id = None
      self.landmarks = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_landmark_put: rte_sys_id: %s / landmarks: %s'
         % (self.route_system_id,
            self.landmarks,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      try:
         self.route_system_id = int(self.decode_key('route_system_id'))
      except Exception, e:
         raise GWIS_Error('route_system_id not a valid int.')
      self.landmarks = list()
      for l_xml in self.req.doc_in.findall('./lmrk'):
         geo = l_xml.get('geometry')
         if geo == '':
            geo = None
         self.landmarks.append(Landmark(l_xml.get('name'),
                                        l_xml.get('item_id'),
                                        l_xml.get('type_id'),
                                        geo,
                                        l_xml.get('step')))

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         raise GWIS_Error('User must be logged in.')
      else:
         # 'erase' previous landmarks
         sql = (
            """
            UPDATE landmark_exp_landmarks
            SET current = '%s'
            WHERE username = %s
              AND route_system_id = %d
            """) % ('f',
                    self.req.db.quoted(self.req.client.username),
                    self.route_system_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()

         for l in self.landmarks:
            if l.geometry:
               xys = gml.flat_to_xys(l.geometry)
               if len(xys) > 2:
                  l.geometry = "SRID=%s;LINESTRING(%s)" % (conf.default_srid,
                                                           l.geometry,)
               else:
                  l.geometry = "SRID=%s;POINT(%s)" % (conf.default_srid,
                                                      l.geometry,)
            sql = """
            INSERT INTO landmark_exp_landmarks
               (username,
                route_system_id,
                landmark_id,
                landmark_type_id,
                landmark_name,
                landmark_geo,
                step_number,
                created)
            VALUES
               (%s, %s, %s, %s, %s, %s, %s, now())
            """
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql,
               (self.req.db.quoted(self.req.client.username),
                self.route_system_id,
                l.item_id,
                l.type_id,
                l.name,
                l.geometry,
                l.step_number,))
            self.req.db.transaction_commit()

         sql = (
            """
            UPDATE landmark_exp_route
            SET done = 't',
                last_modified = now()
            WHERE username = %s
              AND route_system_id = %d
            """) % (self.req.db.quoted(self.req.client.username),
                    self.route_system_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()

   # ***

# ***

