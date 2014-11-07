# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command

log = g.log.getLogger('cmd.route_fb_put')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'route_id',
      'route_version',
      'purpose',
      'satisfaction',
      'comments',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.route_id = None
      self.route_version = None
      self.purpose = None
      self.satisfaction = None
      self.comments = None

   # ***

   #
   def __str__(self):
      selfie = (
         'rte_fdbck_unedited: rte: %s.%s / purp: %s / satisf: %s / cmmts: %s'
         % (self.route_id,
            self.route_version,
            self.purpose,
            self.satisfaction,
            self.comments,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      fb = self.req.doc_in.find('feedback')
      self.route_id = int(fb.get('id'))
      self.route_version = int(fb.get('version'))
      # 2012.08.16: From Route_Feedback_Popup, here are the "purpose"s:
      #  'exercise', 'recreation', 'commute', 'transport', 'other'
      self.purpose = fb.get('purpose')
      self.satisfaction = int(fb.get('satisfaction'))
      self.comments = fb.text

   #
   def fetch_n_save(self):

      command.Op_Handler.fetch_n_save(self)

      success = self.req.db.transaction_retryable(self.attempt_save, self.req)

      if not success:
         log.warning('save: failed!')

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      # No need to lock tables, as we only INSERT. The worst that'll happen is
      # multiple, duplicate rows, since route_feedback is primary keyed by an
      # id sequence.
      self.req.db.transaction_begin_rw()

      #if self.req.client.username == conf.anonymous_username:
      #   username = req.client.ip_addr
      #else:
      #   username = self.req.client.username
      #
      # VERIFY: [lb:] You must be be logged in to provide feedback, right?
      g.assurt(self.req.client.username != conf.anonymous_username)

      username = self.req.client.username

      self.req.db.insert('route_feedback',
                         { 'route_id': self.route_id,
                           'route_version': self.route_version,
                           'username': username },
                         { 'purpose': self.purpose,
                           'satisfaction': self.satisfaction,
                           'comments': self.comments })
      
      self.req.db.transaction_commit()

   # ***

# ***

