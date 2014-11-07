# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command
from util_ import misc

# MAYBE: Rename: The table is item_event_read, so cmd should be
#                 item_read_event_put.

log = g.log.getLogger('cmd.itm_rd_ev_put')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'system_ids',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.system_ids = list()

   # ***

   #
   def __str__(self):
      selfie = (
         'item_read_event_put: system_ids: %s'
         % (self.system_ids,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      for e in self.req.doc_in.find('./items_read'):
         self.system_ids.append(int(e.get('ssid')));

   #
   def fetch_n_save(self):

      # The base class just sets self.doc to the incoming XML document.
      command.Op_Handler.fetch_n_save(self)

      if ((self.system_ids is not None)
          and (len(self.system_ids) > 0)
          and (self.req.client.username != conf.anonymous_username)):

         # MAYBE: Do we need to use transaction_retryable?
         success = self.req.db.transaction_retryable(
            self.attempt_save, self.req)

         if not success:
            log.warning('fetch_n_save: failed')

   #
   def attempt_save(self, db, *args, **kwargs):

      # NOTE: The current implementation captures a complete log of
      #       read events: clients can send as many read events for
      #       the same item at the same revision as they like, and
      #       since we use a serial id, we'll just keep making records
      #       with unique timestamps. But when pyserver fetches items
      #       for the client, we just care about the latest revision
      #       for any (username, item_id) pair. So this table has the
      #       potential of growing large, but it probably won't (threads
      #       are not very active, which is all that uses item_event_read),
      #       we use indices to ensure fast sql responses, and if we
      #       really cared about space, we'd do something about the apache
      #       event table (like archiving records? but then there's the
      #       whole point that developers should really have access to
      #       a simplified map so that route finders can be loaded into
      #       memory quickly, i.e., working with the production database,
      #       even sans apache event tables, still slows down development).

      # Note also that we don't store stack IDs. By using system IDs instead,
      # a read event applies to a specific version and branch of an item,
      # rather than the entire item history. This makes it easier to join
      # the table: when can ignore stack ID and revision or version and
      # just join on system ID.

      g.assurt(id(db) == id(self.req.db))

      self.req.db.transaction_begin_rw()

      # MEH: Will SQL complain if system_ids aren't valid system_ids? Or
      # should we not care? Testing should reveal if the client is sending,
      # e.g., stack IDs by mistake, so there's probably no reason to care if
      # these IDs are wrong.
      for system_id in self.system_ids:
         self.req.db.insert(
            'item_event_read',
            # MAYBE: We should get in the habit of storing user IDs instead?
            #        Seems more secure (or at least more obfuse) than storing
            #        usernames.
            { 'username': self.req.client.username,
              'item_id' : system_id,
              # NOTE: The database has a trigger to set the revision id
              #       using cp_set_created_rid().
            },
            {})


# BUG_FALL_2013: FIXME: PROBABLY need to set read events on all posts, too
#          TEST: Delete previous versions in the same branch
         event_update_sql = (
            """
            UPDATE item_event_alert SET date_alerted = NOW()
            WHERE username = '%s'
              AND date_alerted IS NULL
              AND item_id IN (
                  SELECT system_id FROM item_versioned AS iv
                  WHERE iv.branch_id = (SELECT branch_id
                           FROM item_versioned WHERE system_id = %d)
                    AND iv.stack_id = (SELECT stack_id
                           FROM item_versioned WHERE system_id = %d)
                    AND iv.system_id <= %d)
            """ % (self.req.client.username,
                   system_id,
                   system_id,
                   system_id,))
         self.req.db.sql(event_update_sql)

      self.req.db.transaction_commit()

   # ***

# ***

