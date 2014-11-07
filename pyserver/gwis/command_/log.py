# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from util_ import misc

log = g.log.getLogger('cmd.log')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'events',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.events = None

   # ***

   #
   def __str__(self):
      selfie = (
         'log: events: %s'
         % (self.events,))
      return selfie

   # ***

   #
   def decode_request(self):

      command.Op_Handler.decode_request(self)

      # BUG 2725: 2012.09.11: [lb] added code in gwis_mod_python to check that 
      #           doc_in isn't ever None, which causes an AttributeError.
      #           2012.10.03: But this is still happening...
      #             assert(self.req.doc_in is not None)
      if self.req.doc_in is None:
         # 2014.09.23: This rarely happens, and when it does, android=true,
         #             so not a bug of big importance.
         log.info(
            'decode_request: Missing doc_in: read_len: %s / req: %s / hdr: %s'
            % (self.req.areq.read_length,
               self.req.areq.the_request,
               self.req.areq.headers_in,))
         # FIXME: Does Android display an error when this happens to GWIS_Log,
         #        or does it silently fail?
         # FIXME: [lb]: What's my phone's IP addy so I can search the log,
         #              so I can try to figure out what causes this?
         # FIXME: Should we even bother raising? It's just a Log event...
         #raise GWIS_Error('Log missing content body.')

      self.events = list()

      if self.req.doc_in is not None:
         ev = self.req.doc_in.findall('event')
         for e in ev:
            self.events.append(Event(e))

   #
   def fetch_n_save(self):

      # The base class just sets self.doc to the incoming XML document.
      command.Op_Handler.fetch_n_save(self)

      success = self.req.db.transaction_retryable(self.attempt_save, self.req)

      if not success:
         log.warning('fetch_n_save: failed!')

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      # [rp] says, INSERT only, so no locking needed.
      # [lb] says, the log_event table's primary key is id which uses a default
      #            sequence generator. So if the same log event is sent twice, 
      #            it'll get inserted twice, each time with a unique id, albeit
      #            created and timestamp_client will be the same (but how
      #            fine-grained are timestamps, anyway? they might be hard to
      #            weed-out if other disparate log events actually do share the
      #            same timestamps). In any case, the worst that'll happen here
      #            is log-duplication, but this transaction shouldn't ever
      #            fail, since we no longer use serializable anywhere (see 
      #            Bug 2688).

      if self.events:

         self.req.db.transaction_begin_rw()

         # Insert all events
         for e in self.events:
            e.insert(self.req)

         self.req.db.transaction_commit()

   # ***

# ***

class Event(object):

   __slots__ = (
      'facility',
      'timestamp',
      'params', # dict()
      )

   def __init__(self, el):
      self.facility = el.get('facility')
      self.timestamp = el.get('timestamp')
      self.params = dict()
      for kvp in el:
         self.params[kvp.get('key')] = kvp.text

   #
   def insert(self, req):
      #FIXME Base class already set req?
      # FIXME there is no self.req....... probably ok, so just del this comment
      #g.assurt(req == self.req) # FIXME don't need req
      # Get a new id now, since we want to pass it to each inserted kvp
      id_ = req.db.sequence_get_next('log_event_id_seq')
      req.db.insert('log_event', { 'id': id_ },
                    { 'client_host': req.client.ip_addr,
                      'username': req.client.username,
                      'browid': req.client.browser_id,
                      'sessid': req.client.session_id,
                      'timestamp_client': self.timestamp,
                      'facility': self.facility })
      # The log message might include one or more key-value pairs, which 
      # we add to the database, along with the log event ID
      for k in self.params:
         req.db.insert('log_event_kvp', {},
            { 'event_id': id_, 'key_': k, 'value': self.params[k] })

      # 2014.09.09: Log warning so logcheck complains about flashclient
      #             errors, regardless of whether or not log_event_check.sh
      #             is cronning.
      if self.facility.startswith('error'):
         log.warning(
            'log: client error: uname: %s / facil: %s / ts: %s / %s'
            % (req.client.username,
               self.facility,
               self.timestamp,
               self.params,))

   # ***

# ***

