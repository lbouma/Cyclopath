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
from util_ import misc

log = g.log.getLogger('cmd.lmrk.bgin')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'xml',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.xml = None

   # ***

   #
   def __str__(self):
      selfie = 'landmark_exp_begin'
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      self.xml = etree.Element('lmrk_exp')
      if ((not self.req.client.username)
          or (self.req.client.username == conf.anonymous_username)):
         raise GWIS_Error('User must be logged in.')
      else:
         self.get_trial()

   #
   def get_trial(self):
      # search for username in experiment table
      sql = (
         """
         SELECT username
         FROM landmark_experiment AS e
         WHERE e.username = %s
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)

      # if exists, get existing trial
      if len(rows) > 0:
         self.get_existing_trial()
      # otherwise, begin a new trial
      else:
         self.begin_new_trial()

   #
   def get_existing_trial(self):

      # Check that the user hasn't completed the experiment previously.
      sql = (
         """
         SELECT COUNT(feedback)
         FROM landmark_exp_feedback AS r
         WHERE r.username = %s
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)
      g.assurt(len(rows) == 1)
      if rows[0]['count'] == 0:

         # find out which routes this user has not finished
         sql = (
            """
            SELECT route_system_id
            FROM landmark_exp_route AS r
            WHERE r.username = %s
              AND NOT r.done
            """ % (self.req.db.quoted(self.req.client.username),))
         rows = self.req.db.sql(sql)

         # send list of routes to client
         for row in rows:
            route_xml = etree.Element('route')
            misc.xa_set(route_xml, 'route_system_id', row['route_system_id'])
            self.xml.append(route_xml)

   #
   def begin_new_trial(self):

      # save username and trial time to db
      sql = (
         """
         INSERT INTO landmark_experiment
            (username, trial_time)
         VALUES
            (%s, now())
         """) % (self.req.db.quoted(self.req.client.username),)
      self.req.db.transaction_begin_rw()
      self.req.db.sql(sql)
      self.req.db.transaction_commit()

      # choose 5 random routes from list
      routes = random.sample(conf.landmarks_exp_rt_system_ids,
                             Landmark.experiment_count)

      # save routes to db
      for sys_id in routes:
         sql = (
            """
            INSERT INTO landmark_exp_route
               (username, route_system_id, last_modified)
            VALUES
               (%s, %d, now())
            """) % (self.req.db.quoted(self.req.client.username), sys_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()
         # send route to client
         route_xml = etree.Element('route')
         misc.xa_set(route_xml, 'route_system_id', sys_id)
         self.xml.append(route_xml)

   #
   def prepare_response(self):
      self.doc.append(self.xml)

   # ***

# ***

