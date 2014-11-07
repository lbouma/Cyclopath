# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from grax.item_manager import Item_Manager
from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item.util import item_factory
from item.util import revision
from item.util.item_type import Item_Type
from util_ import misc

log = g.log.getLogger('cmd.itm_hist')

# MAYBE/BUG nnnn: The item history doesn't include link_value changes.
# E.g., if you change a byway's speed_limit, that change won't be
# revealed via the byway's different versions. We'd need to search
# link_values for the rhs_stack_id of the byway, and then we'd have
# to return all link_values and their versions for the byway... and
# then the client, what, splices all the results together? Or maybe
# we send the link_value history separately...

class Op_Handler(command.Op_Handler):

   # Default page size. You can set this lower for testing,
   # but depending on the client, you'll see varying sizes
   # (e.g., flashclient might show just three results at a
   # time in the item details panel, but in the route details
   # panel, where the history has its own tab, you might twenty
   # results per page... and then, from ccp.py, you might see
   # any number requested, because that's the test interface.
   constraint_versions_max = 100

   __slots__ = (
      'results', # XML etree
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.results = None

   # ***

   #
   def __str__(self):
      selfie = (
         'item_history_get: results: %s'
         % (self.results,))
      return selfie

   # ***

   #
   def decode_request(self):
      log.debug('decode_request')
      command.Op_Handler.decode_request(self)
      g.assurt(self.req.branch.branch_id > 0)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      qb = self.req.as_iqb()

      # If a user has current access to an item, they have historic access.
      # 2014.05.10: We used to use historic group memberships for the user,
      # but this doesn't make sense: permissions are not wikiable.
      g.assurt(isinstance(qb.revision, revision.Current))

      # We except one stack_id, and one stack_id only, and it better be good.
      try:
         item_stack_id = int(qb.filters.only_stack_ids)
         # The search_by_stack_id fcn. doesn't want qb.filters to be set.
         qb.filters.only_stack_ids = ''
      except Exception, e:
         log.error('fetch_n_save: no item stack_id: %s / %s / %s'
                   % (qb.filters, self, self.req,))
         raise GWIS_Error('Please specify one item stack id.')

      # Check/Setup the pagination request.
      if qb.filters.pagin_count:
         if qb.filters.pagin_count > Op_Handler.constraint_versions_max:
            raise GWIS_Error('Please ask for fewer results.')
      else:
         qb.filters.pagin_count = Op_Handler.constraint_versions_max
      # We can ignore pagin_offset; it's 0 unless client cares to set it.
      qb.use_limit_and_offset = True

      (itype_id, lhs_type_id, rhs_type_id,
         ) = Item_Manager.item_type_from_stack_id(qb, item_stack_id)

      if not itype_id:
         # If we assume only our offical clients are calling pyserver, this
         # should not happen.
         log.error('fetch_n_save: item type not found: %s' % (self,))
         # SYNC_ME: Ambiguous not-found or access-denied error msg.
         raise GWIS_Error('Item not found or access denied.')

      itype = Item_Type.id_to_str(itype_id)
      items = item_factory.get_item_module(itype).Many()

      # TESTME: Delete an item, find it in recent changes, look at history,
      #         try to load other versions in diff mode.

      qb.revision.allow_deleted = True
      items.search_by_stack_id(item_stack_id, qb)

      if len(items) == 0:
         # SYNC_ME: Ambiguous not-found or access-denied error msg.
         # This is access denied. The error message is the same as
         # the one for item-type not found (which means the stack ID
         # is invalid) so that a client cannot discern between
         # invalid stack IDs and stack IDs of items to which a user
         # does not have access.
         raise GWIS_Error('Item not found or access denied.')

      g.assurt(len(items) == 1)

      # The user can see the current item, so they can see its version history.

      # Caveat: For truly revisionless items, like routes, the edited_date
      # reflects when the item was last edited, exclusive of permissions
      # changes.

      # The heart of how we fetch: using special sql_clauses_cols_versions.
      sql_clauses = items.sql_clauses_cols_versions

      item_history_sql = (
         """
         SELECT %s
         %s
         WHERE iv.stack_id = %d
           AND iv.branch_id = %d
         ORDER BY iv.version DESC
         """ % (sql_clauses.inner.shared,
                sql_clauses.inner.join,
                item_stack_id,
                qb.branch_hier[0][0],))

      #log.debug('fetch_n_save: %s' % (item_history_sql,))

      self.results = qb.db.table_to_dom('item_history', item_history_sql)

      if ((not self.results)
          or (len(self.results) != int(self.results[0].get('version')))):
         log.error('fetch_n_save: unexpect results len: %s / %s / %s'
                   % (self.results, self.req, self,))

   #
   def prepare_response(self):

      self.doc.append(self.results)

   # ***

# ***

