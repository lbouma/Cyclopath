# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from grax.access_level import Access_Level
from grax.user import User
from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_error import GWIS_Warning
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from gwis.query_filters import Query_Filters
from item import item_user_access
from item.feat import route
from util_ import misc

log = g.log.getLogger('cmd.fdbl_get')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'itmf_xml',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.itmf_xml = None

   # ***

   #
   def __str__(self):
      selfie = (
         'item_findability_get: fbil_sids: %s'
         % (etree.tostring(self.req.doc_in.find('./fbil_sids'),
                           pretty_print=False),))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      # Assemble the qb from the request.
      qb = self.req.as_iqb(addons=False)
      g.assurt(qb.filters == Query_Filters(None))

      item_stack_ids = qb.filters.decode_ids_compact('./fbil_sids',
                                                     self.req.doc_in)
      if ((not item_stack_ids) or (item_stack_ids.find(',') != -1)):
         raise GWIS_Error('Expecting one stack ID in fbil_sids doc.')

      items = item_user_access.Many()
      g.assurt(qb.sql_clauses is None)
      qb.sql_clauses = item_user_access.Many.sql_clauses_cols_all.clone()
      qb.filters.dont_load_feat_attcs = True
      qb.filters.only_stack_ids = item_stack_ids
      sql_many = items.search_get_sql(qb)

      sql_itmf = (
         """
         SELECT
            itmf.item_stack_id
            , itmf.username
            -- , itmf.user_id
            , itmf.library_squelch
            , itmf.show_in_history
            -- , itmf.last_viewed
            -- , itmf.branch_id
         FROM (%s) AS gia
         JOIN item_findability AS itmf
            ON (gia.stack_id = itmf.item_stack_id)
         WHERE
            (       (itmf.username = %s)
                AND (gia.access_level_id <= %d))
            OR (    (itmf.username = %s)
                AND (gia.access_level_id <= %d))
         """ % (sql_many,
                qb.db.quoted(conf.anonymous_username),
                Access_Level.arbiter,
                qb.db.quoted(qb.username),
                Access_Level.viewer,))

      rows = qb.db.sql(sql_itmf)

      if len(rows) == 0:
         raise GWIS_Warning('No item_findability for user-item.')

      # We'll find one or two records: one for the user, and one for the
      # public.
      # EXPLAIN: What records exist for anon route request?
      #          [lb] thinks it's a GIA record with a stealth secret,
      #               but probably not an item_findability record.
      #
      #          FIXME: TEST: anon get route, log in, save route
      #
      fbilities = etree.Element('fbilities')
      for row in rows:
         fbility = etree.Element('fbility')
         misc.xa_set(fbility, 'sid', row['item_stack_id'])
         if row['username'] == conf.anonymous_username:
            # MAGIC_NUMBER: Usernames prefixed with a floorbar are special.
            username_hacked = '_anonymous'
         else:
            username_hacked = row['username']
         misc.xa_set(fbility, 'unom', username_hacked)
         #misc.xa_set(fbility, 'uid', row['user_id'])
         misc.xa_set(fbility, 'sqel', row['library_squelch'])
         misc.xa_set(fbility, 'hist', row['show_in_history'])
         #misc.xa_set(fbility, 'lstv', row['last_viewed'])
         #misc.xa_set(fbility, 'brid', row['branch_id'])
         fbilities.append(fbility)
      self.itmf_xml = fbilities

   #
   def prepare_response(self):
      self.doc.append(self.itmf_xml)

   # ***

# ***

