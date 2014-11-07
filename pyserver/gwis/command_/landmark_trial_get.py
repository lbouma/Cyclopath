# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import random
import sys
import time

import conf
import g

from gwis import command
from util_ import misc

log = g.log.getLogger('cmd.lmrk.tget')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'xml',
      'trial_num'
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.xml = None
      self.trial_num = None

   # ***

   #
   def __str__(self):
      selfie = (
         'landmark_trial_get: trial_num: %s'
         % (self.trial_num,))
      return selfie

   # *** Public Interface

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.trial_num = self.decode_key('trial_num', None)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      self.xml = etree.Element('lmrk_trial')
      if (not conf.landmarks_experiment_active):
         misc.xa_set(self.xml, 'cond', 'exp-off')
      else:
         if ((not self.req.client.username)
             or (self.req.client.username == conf.anonymous_username)):
            misc.xa_set(self.xml, 'cond', 'no-usr')
         elif (self.trial_num is not None):
            self.get_previous_trial()
         else:
            self.set_new_trial()

   #
   def get_previous_trial(self):
      # We need the track id and the landmark prompt locations
      sql = (
         """
         SELECT track_id, condition
         FROM landmark_trial AS t
         WHERE
            t.username = %s
            AND t.trial_num = %s
         """ % (self.req.db.quoted(self.req.client.username),
                self.trial_num,))
      rows = self.req.db.sql(sql)
      misc.xa_set(self.xml, 'tid', rows[0]['track_id'])
      misc.xa_set(self.xml, 'cond', rows[0]['condition'])

      sql = (
         """
         SELECT n.node_stack_id, ST_AsText(n.endpoint_xy) as geo
         FROM landmark_prompt AS p
         JOIN node_endpt_xy as n ON (p.node_id = n.node_stack_id)
         WHERE
            p.username = %s
            AND p.trial_num = %s
         """ % (self.req.db.quoted(self.req.client.username),
                self.trial_num,))
      rows = self.req.db.sql(sql)

      for row in rows:
         prompts_xml = etree.Element('prompt')
         misc.xa_set(prompts_xml, 'nid', row['node_stack_id'])
         misc.xa_set(prompts_xml, 'geometry', row['geo'][6:-1])
         self.xml.append(prompts_xml)

   #
   def set_new_trial(self):
      conditions = { 'now-low': 0,
                     'now-high': 0,
                     'later-low': 0,
                     'later-high': 0,}
      # get trial history (what condition and how many prompts)
      sql = (
         """
         SELECT condition, count(*) AS ct
         FROM landmark_trial AS t
         JOIN landmark_prompt AS p ON (t.username = p.username
                                       AND t.trial_num = p.trial_num)
         WHERE
            t.username = %s
            AND track_id IS NOT NULL
            AND NOT track_id = -1
         GROUP BY condition
         """ % (self.req.db.quoted(self.req.client.username),))
      rows = self.req.db.sql(sql)

      # get highest trial number
      sql = (
         """
         SELECT MAX(trial_num) AS num
         FROM landmark_trial AS t
         WHERE t.username = %s
         """ % (self.req.db.quoted(self.req.client.username),))
      max_trial_num = -1
      num_trial_rows = self.req.db.sql(sql)
      if (len(num_trial_rows) > 0):
         max_trial_num = num_trial_rows[0]['num']
      if max_trial_num is None:
         max_trial_num = -1
      new_trial_num = max_trial_num + 1

      if (new_trial_num > 0):
         # Check whether the last trial was incomplete
         sql = (
            """
            SELECT condition
            FROM landmark_trial AS t
            WHERE
               t.username = %s
               AND track_id = -1
               AND trial_num = %d
            GROUP BY condition
            """ % (self.req.db.quoted(self.req.client.username),
                   max_trial_num,))
         p_rows = self.req.db.sql(sql)
         if (len(p_rows) > 0 and p_rows[0]['condition'] is not None):
            # This will give priority to retrying previous incomplete condition
            conditions[(p_rows[0]['condition'] + '-low')] -= 100
            conditions[(p_rows[0]['condition'] + '-high')] -= 100

      if (len(rows) == 0):
         # if no history, get first trial conditions for all users
         sql = (
            """
            SELECT t.username, condition, count(*) AS ct
            FROM landmark_trial AS t
            JOIN landmark_prompt AS p ON (t.username = p.username
                                          AND t.trial_num = p.trial_num)
            WHERE
               t.trial_num = 0
            GROUP BY t.username, condition
            """)
         rows = self.req.db.sql(sql)
      # get counts for conditions and choose lowest (random if more than
      # one with the lowest count)
      for row in rows:
         if row['ct'] < 4:
            conditions[(row['condition'] + '-low')] += 1
         else:
            conditions[(row['condition'] + '-high')] += 1
      # decide on new conditions and save
      condition_keys= ['now-low','now-high','later-low','later-high']
      min_conds = [condition_keys[0]]
      min_ct = conditions[min_conds[0]]
      for i in xrange(1, len(condition_keys)):
         if (conditions[condition_keys[i]] <  min_ct):
            min_conds = [condition_keys[i]]
            min_ct = conditions[min_conds[0]]
         elif (conditions[condition_keys[i]] ==  min_ct):
            min_conds.append(condition_keys[i])
      final_condition = 'none'
      if (len(min_conds) == 1):
         # we have our condition
         final_condition = min_conds[0]
      else:
         # We need to assing one randomly
         random.seed(time.time())
         final_condition = min_conds[random.randint(0,len(min_conds)-1)]
      misc.xa_set(self.xml, 'cond', final_condition)
      misc.xa_set(self.xml, 'trial_num', new_trial_num)

      # Save trial information
      sql = (
         """
         INSERT INTO landmark_trial
            (username, trial_num, trial_time,
             condition, track_id, email_sent)
         VALUES
            (%s, %d, now(), '%s', %d, '%s')
         """) % (self.req.db.quoted(self.req.client.username),
                 new_trial_num,
                 str.split(final_condition, '-')[0],
                 -1,
                 False,)
      self.req.db.transaction_begin_rw()
      self.req.db.sql(sql)
      self.req.db.transaction_commit()

   #
   def prepare_response(self):
      self.doc.append(self.xml)

   # ***

# ***

