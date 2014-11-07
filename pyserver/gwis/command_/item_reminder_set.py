# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item import item_user_access
from item.feat import route
from item.util import revision
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency
from item.util.watcher_parts_base import Watcher_Parts_Base
from util_ import misc

log = g.log.getLogger('cmd.rtre_ask')

# BUG nnnn: [lb] updated this file to CcpV2, but since Route Reactions
#           is disabled, I haven't tested it... so if/when Route
#           Reactions is implemented, don't be surprised if this
#           module has a bug or three. Nonetheless, it's a simple
#           module, and it looks like it's implemented well....

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'item_stack_id',
      'item_type_id',
      'psql_ts_delay',
      )

   remind_when_to_ts_delay = {
      'Tomorrow': '1 day',
      'In a week': '1 week',
      }

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.item_stack_id = None
      self.item_type_id = None
      self.psql_ts_delay = None

   # ***

   #
   def __str__(self):
      selfie = (
         'item_reminder_set: sids: %s / itm_typ_id: %s / psql_ts_delay: %s'
         % (self.item_stack_id,
            self.item_type_id,
            self.psql_ts_delay,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

      self.item_stack_id = self.decode_key('sid', None)
      if not self.item_stack_id:
         raise GWIS_Error('Missing mandatory param: sid')

      # Reminders can only be set of routes. E.g., request a new
      # route, and then we'll ask you later to come back and
      # review the route.
      #
      # We could support other item types, but there's not a good
      # use case (e.g., create a new byway and then we'll ask you
      # later about it? that does not seem interesting).
      item_type_str = self.decode_key('type', None)
      if not item_type_str:
         raise GWIS_Error('Missing mandatory param: type')
      try:
         self.item_type_id = Item_Type.str_to_id(item_type_str)
      except KeyError:
         raise GWIS_Error('Unknown item type: %s' % (item_type_str,))
      if self.item_type_id != Item_Type.ROUTE:
         raise GWIS_Error('Item reminders can only be set on routes')

      remind_when = self.decode_key('when', None)
      if not remind_when:
         raise GWIS_Error('Missing mandatory param: when')
      try:
         self.psql_ts_delay = Op_Handler.remind_when_to_ts_delay[remind_when]
      except KeyError:
         raise GWIS_Error('Unknown reminder time: %s' % (remind_when,))

   #
   def fetch_n_save(self):

      command.Op_Handler.fetch_n_save(self)

      g.assurt(self.item_stack_id)
      g.assurt(self.item_type_id)
      g.assurt(self.remind_when)

      qb = self.req.as_iqb(addons=False)
      g.assurt(qb.filters == Query_Filters(None))
      items_fetched = item_user_access.Many()
      #qb.filters.include_item_stack = True
      qb.filters.dont_load_feat_attcs = True
      #qb.filters.min_access_level = Access_Level.viewer # default: client
      items_fetched.search_by_stack_id(self.item_stack_id, qb)
      if not items_fetched:
         raise GWIS_Error('Item stack ID not found or permission denied: %d'
                          % (self.item_stack_id,))
      g.assurt(len(items_fetched) == 1)
      item = items_fetched[0]
      log.debug('fetch_n_save: fetched: %s' % (str(item),))
      g.assurt(not item.fresh)
      g.assurt(not item.valid)

      success = self.req.db.transaction_retryable(
         self.attempt_save, self.req, item)

      if not success:
         log.warning('fetch_n_save: failed')

   #
   def attempt_save(self, db, item):

      g.assurt(id(db) == id(self.req.db))

      self.req.db.transaction_begin_rw()

      # NOTE: We'll verify access to the route when we compose the email.
      #       If the route is deleted or no longer accessible, we won't
      #       email the user.
      #
      # Also, in CcpV1, when a reminder was set, we'd make sure to make
      # the route hash ID (the stealth secret UUID), but in CcpV2 the
      # deep link feature can link to stack IDs, too. (And since this
      # is a reminder for a specific user, we can use the 'private'
      # deep link, to make sure the user is logged on before the stack
      # ID is fetched (to make the user has appropriate permissions).)

      # BUG nnnn/FIXME: The reaction_reminder table is no longer used. We could
      #                 probably just delete it, or if we care about its measly
      #                 contents, we could copy its rows to item_event_alert
      #                 (though the minnesota.reaction_reminder table is just
      #                 38 records of people previously reminded about their
      #                 routes).
      #

      sql = (
         """
         INSERT INTO item_event_alert
            (username,
             latest_rid,
             item_id,
             item_stack_id,
             msg_type_id,
             service_delay,
             branch_id,
             watcher_stack_id,
             ripens_at)
         VALUES
            (%s, -- username
             %d, -- latest_rid
             %d, -- item_id
             %d, -- item_stack_id
             %d, -- msg_type_id
             %d, -- service_delay
             %d, -- branch_id
             %d, -- watcher_stack_id
             NOW() + INTERVAL '%s')
         """ % (self.req.db.quoted(self.req.client.username),
                revision.Revision.revision_max(self.req.db),
                item.system_id,
                item.stack_id,
                Watcher_Parts_Base.MSG_TYPE_RTE_REACTION,
                Watcher_Frequency.ripens_at,
                item.branch_id,
                0, # This was not set via item watcher, so no watcher_stack_id.
                self.psql_ts_delay,
                ))

      self.req.db.sql(sql)

      self.req.db.transaction_commit()

   # ***

# ***

