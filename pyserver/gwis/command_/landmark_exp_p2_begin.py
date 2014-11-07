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

log = g.log.getLogger('cmd.lmrk.2beg')

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
      selfie = 'landmark_exp_p2_begin'
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
   
      # get routes from pt 1
      routes_p1 = list()
      sql = (
         """
         SELECT route_system_id
         FROM landmark_exp_route AS r
         WHERE r.username = %s
           AND part = 1
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)
      for row in rows:
         routes_p1.append(row['route_system_id'])
   
      # get pt 2 routes
      sql = (
         """
         SELECT u.route_system_id, u.route_user_id, u.done
         FROM landmark_exp_route AS r
            LEFT JOIN landmark_exp_route_p2_users as u
            ON (u.username = r.username
                AND u.route_system_id = r.route_system_id)
         WHERE
            r.username = %s
            AND part = 2
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)
      
      routes_p2 = list()
      # if list is empty, generate new routes
      if len(rows) == 0:
         routes_p2 = self.generate_new_routes(routes_p1)
      else:
         # keep only new routes
         for r in rows:
            if (not r['done']):
               routes_p2.append((r['route_system_id'], r['route_user_id'],))
         
      
      # send list of routes to client
      for r_id in routes_p1:
         route_xml = etree.Element('route_p1')
         misc.xa_set(route_xml, 'route_system_id', r_id)
         self.xml.append(route_xml)
      for rt in routes_p2:
         route_xml = etree.Element('route_p2')
         misc.xa_set(route_xml, 'route_system_id', rt[0])
         misc.xa_set(route_xml, 'route_user_id', rt[1])
         self.xml.append(route_xml)

   #
   def generate_new_routes(self, routes_p1):
      
      new_routes = list()
      available_routes = list()
      for sys_id in conf.landmarks_exp_rt_system_ids:
         if not sys_id in routes_p1:
            available_routes.append(sys_id)

      # choose random routes from list
      if len(available_routes) > 5:
         routes = random.sample(available_routes, 5)
      else:
         routes = random.sample(available_routes, len(available_routes))
      
      # save routes to db
      for sys_id in routes:
         # get 3 random users who did this route
         sql = (
            """
            SELECT r.username
            FROM landmark_exp_route AS r
            WHERE r.route_system_id = %s
               AND part = 1
               AND done
               AND (SELECT count(*)
                     FROM landmark_exp_landmarks as l
                     WHERE l.username LIKE '%%'  || r.username || '%%'
                        AND r.route_system_id = l.route_system_id) > 0
            GROUP BY r.username
            ORDER BY RANDOM()
            LIMIT 3
            """ % (sys_id,))
         rows = self.req.db.sql(sql)
         
         # update main routes table
         sql = (
            """
            INSERT INTO landmark_exp_route
               (username, route_system_id, part, last_modified)
            VALUES
               (%s, %d, 2, now())
            """) % (self.req.db.quoted(self.req.client.username), sys_id,)
         self.req.db.transaction_begin_rw()
         self.req.db.sql(sql)
         self.req.db.transaction_commit()
         index = 0
         for row in rows:
            sql = (
               """
               INSERT INTO landmark_exp_route_p2_users
                  (username, route_system_id, route_user, route_user_id)
               VALUES
                  (%s, %d, %s, %d)
               """) % (self.req.db.quoted(self.req.client.username),
                       sys_id,
                       self.req.db.quoted(row['username']),
                       index,)
            self.req.db.transaction_begin_rw()
            self.req.db.sql(sql)
            self.req.db.transaction_commit()
            new_routes.append((sys_id, index))
            index += 1
            
      return new_routes

   #
   def prepare_response(self):
      self.doc.append(self.xml)

   # ***

# ***

