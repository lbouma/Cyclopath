# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: This class is used by android, but not by flashclient.

from lxml import etree
import os
import random
import sys
import time

import conf
import g

from gwis import command
from item.feat import branch
from util_ import misc

log = g.log.getLogger('cmd.lmrk.need')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'xml',
      'x',
      'y',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.xml = None
      self.x = None
      self.y = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_need_get: x: %s / y: %s'
         % (self.x,
            self.y,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.x = self.decode_key('x')
      self.y = self.decode_key('y')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      self.xml = etree.Element('lmrk_need')
      if (conf.landmarks_experiment_active):

         sql = (
            """
            SELECT distinct n.stack_id, ST_AsText(nxy.endpoint_xy) as geo,
                   (SELECT count(*)
                     FROM geofeature
                        JOIN group_item_access as gia
                           ON (geofeature.stack_id = gia.stack_id
                               AND geofeature.version = gia.version)
                        WHERE geofeature_layer_id=103
                        AND ST_Distance(nxy.endpoint_xy, geofeature.geometry)
                            < 50
                        AND NOT deleted
                        AND valid_until_rid = %d
                        AND gia.branch_id = %d) as points_nearby
            FROM node_endpoint as n
            JOIN node_endpt_xy as nxy ON (n.stack_id = nxy.node_stack_id)
            WHERE ST_Distance(nxy.endpoint_xy,
                              ST_SetSRID(ST_Point(%s, %s), %d)) < 500
               AND reference_n > 2
            """ % (conf.rid_inf,
                   branch.Many.baseline_id(self.req.db),
                   self.x, self.y, conf.default_srid,))

         # TODO: get only stuff in current branch
         rows = self.req.db.sql(sql)
         for row in rows:
            if (row['points_nearby'] == 0):
               need_xml = etree.Element('need')
               misc.xa_set(need_xml, 'nid', row['stack_id'])
               misc.xa_set(need_xml, 'geometry', row['geo'][6:-1])
               self.xml.append(need_xml)

   #
   def prepare_response(self):
      self.doc.append(self.xml)

   # ***

# ***

