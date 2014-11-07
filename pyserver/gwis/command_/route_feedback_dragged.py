# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# SYNC_ME: flashclient/gwis/GWIS_Route_Feedback_Drag.as
#          pyserver/gwis/command_/route_put_feedback_drag.py
#
# Data packet format:
#
# <gwis>
#    <old id=X version=X>
#       old_reason
#    </old>
#    <new id=X version=X>
#       new_reason
#    </new>
#    <byways>
#       <byway id=X />
#       <byway id=X />
#       ...
#    </byways>
# </gwis>

import os
import sys

import conf
import g

from gwis import command
from util_ import misc

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'old_route_id',
      'old_route_version',
      'new_route_id',
      'new_route_version',
      'old_reason',
      'new_reason',
      'byway_ids',
      'change',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.old_route_id = None
      self.old_route_version = None
      self.new_route_id = None
      self.new_route_version = None
      self.old_reason = None
      self.new_reason = None
      self.byway_ids = None
      self.change = None

   # ***

   #
   def __str__(self):
      selfie = (
         'rte_fdbck_drggd: old: %s.%s / new: %s.%s / %s / %s'
         % (self.old_route_id,
            self.old_route_version,
            self.new_route_id,
            self.new_route_version,
            self.old_reason,
            self.new_reason,
            #self.byway_ids,
            #self.change,
            ))
      return selfie

   # *** GWIS Overrides

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

      # Old route + reason.
      old_route_xml = self.req.doc_in.find('old')
      self.old_route_id      = int(old_route_xml.get('id'))
      self.old_route_version = int(old_route_xml.get('version'))
      self.old_reason        = old_route_xml.text

      # New route + reason.
      new_route_xml = self.req.doc_in.find('new')

# Bug 2817 - Ccpv1 Route Feedback: Trying to save Client ID to database
# This happens if you provide feedback before saving route to library?
#  [lb] doesn't really know but hopes it goes away in CcpV2... which it
#       will, probably, since route feedback will be turned off?
# FIXME: Should this be 'stack_id' and not just get 'id'?
      self.new_route_id      = int(new_route_xml.get('id'))

      self.new_route_version = int(new_route_xml.get('version'))
      self.new_reason        = new_route_xml.text

      # Stretches.
      self.byway_ids = list()
      byways = self.req.doc_in.find('./byways')
      if byways:
         for e in byways:
            self.byway_ids.append(e.get('id'))

      # Change.
      self.change = int(self.decode_key('change', False))

   #
   def fetch_n_save(self):

# FIXME: route reactions. this whole file is new. esp. this fcn.

      command.Op_Handler.fetch_n_save(self)

      feedback_drag_id = self.req.db.sequence_get_next(
                           'route_feedback_drag_id_seq')

      qb = self.req.as_iqb()

      # No need to lock tables, as we only INSERT.
      qb.db.transaction_begin_rw()

      qb.db.insert('route_feedback_drag',
                   {'id': feedback_drag_id,},
                   {'old_route_id':      self.old_route_id,
                    'old_route_version': self.old_route_version,
                    'new_route_id':      self.new_route_id,
                    'new_route_version': self.new_route_version,
                    'username':          self.req.username,
                    'old_reason':        self.old_reason,
                    'new_reason':        self.new_reason,
                    'change':            self.change,})

      for byway_id in self.byway_ids:
         qb.db.insert('route_feedback_stretch',
                      {},
                      {'feedback_drag_id': feedback_drag_id,
                       'byway_id':         byway_id,})

      qb.db.commit()

   # ***

# ***

