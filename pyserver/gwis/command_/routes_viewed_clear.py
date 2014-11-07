# Copyright (c) 2006-2010 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The ClearRouteHistory marks all active routes for a user's route history
# as inactive, effectively clearing the route history list.

import os
import sys

import conf
import g

from gwis import command
from util_ import misc

log = g.log.getLogger('cmd.rthy_clr')

class Op_Handler(command.Op_Handler):

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True

   # ***

   #
   def __str__(self):
      selfie = 'routes_viewed_clear'
      return selfie

   # *** GWIS Overrides

   #
   def fetch_n_save(self):

      # BUG nnnn: When you Clear All from Routes I've Looked At, if there are
      # routes in routes_view but not saved to your library (i.e., no GIA
      # records for you to find them again), you should warn the user that some
      # routes will be lost forever.

      command.Op_Handler.fetch_n_save(self)

      g.assurt(self.req.client.username != conf.anonymous_username)

      # BUG 2688: CcpV1 uses self.req.db.transaction_retryable here.
      success = self.req.db.transaction_retryable(self.attempt_save, self.req)

      if not success:
         log.warning('save: failed!')

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      # NOTE: route_view.active is NOT NULL, and we're setting them all to
      #       FALSE, so no need to WHERE active = TRUE.
      #
      # FIXME: route_view replaced by item_findability...
      #        but route_view table still exists...
      sql = (
         """
         UPDATE
            item_findability
         SET
            show_in_history = FALSE
         WHERE
            username = %s
         """ % (self.req.db.quoted(self.req.client.username),))

      # NOTE: We're just setting all user's rows to FALSE, so no need to lock.
      self.req.db.transaction_begin_rw()
      self.req.db.sql(sql)
      self.req.db.transaction_commit()

   # ***

# ***

