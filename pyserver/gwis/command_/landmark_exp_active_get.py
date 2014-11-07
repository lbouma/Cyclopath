# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# DEVs: To reset the experiment for testing, try:
#        SELECT cp_experiment_landmarks_reset_user('yourname');

from lxml import etree
import os
import random
import sys
import time

import conf
import g

from gwis import command
from util_ import misc

log = g.log.getLogger('cmd.lmrk.aget')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'xml',
      'experiment_part',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.xml = None
      self.experiment_part = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_exp_active_get: experiment_part: %s'
         % (self.experiment_part,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      try:
         self.experiment_part = int(self.decode_key('exp_part', 1))
      except ValueError:
         raise GWIS_Error('experiment_part not a valid int.')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      self.xml = etree.Element('lmrk_exp')

      misc.xa_set(self.xml, 'active', conf.landmarks_experiment_active)

      if ((conf.landmarks_experiment_active)
          and (self.req.client.username)
          and (self.req.client.username != conf.anonymous_username)):
         self.get_existing_trial_route_count_remaining()

   #
   def get_existing_trial_route_count_remaining(self):

      # Send count of remaining routes and completed routes to client.

      route_xml = etree.Element('route')

      sql = (
         """
         SELECT COUNT(route_system_id) AS count
         FROM landmark_exp_route AS r
         WHERE
            r.username = %s
            AND NOT r.done
            AND part = %d
         """ % (self.req.db.quoted(self.req.client.username),
                self.experiment_part,))
      rows = self.req.db.sql(sql)
      g.assurt(len(rows) == 1)
      misc.xa_set(route_xml, 'routes_togo', rows[0]['count'])
      self.xml.append(route_xml)

      sql = (
         """
         SELECT COUNT(route_system_id) AS count
         FROM landmark_exp_route AS r
         WHERE
            r.username = %s
            AND r.done
            AND part = %d
         """ % (self.req.db.quoted(self.req.client.username),
                self.experiment_part,))
      rows = self.req.db.sql(sql)
      g.assurt(len(rows) == 1)
      misc.xa_set(route_xml, 'routes_done', rows[0]['count'])
      self.xml.append(route_xml)

      sql = (
         """
         SELECT COUNT(feedback)
         FROM landmark_exp_feedback AS r
         WHERE r.username = %s
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)
      g.assurt(len(rows) == 1)
      misc.xa_set(route_xml, 'user_done', rows[0]['count'])
      self.xml.append(route_xml)

   #
   def prepare_response(self):
      self.doc.append(self.xml)

   # ***

# ***

