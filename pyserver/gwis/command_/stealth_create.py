# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys
import uuid

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
from grax.user import User
from gwis import command
from gwis.command_ import commit
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_error import GWIS_Warning
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from gwis.query_filters import Query_Filters
from item import item_user_access
from item.feat import route
from util_ import misc

log = g.log.getLogger('cmd.stlth_cr')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'ssec_xml',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = False
      self.ssec_xml = None

   # ***

   #
   def __str__(self):
      selfie = (
         'stealth_create: ssec_xml: %s'
         % (self.ssec_xml,))
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

      item_stack_ids = qb.filters.decode_ids_compact('./ssec_sids',
                                                     self.req.doc_in)
      if ((not item_stack_ids) or (item_stack_ids.find(',') != -1)):
         raise GWIS_Error('Expecting one stack ID in ssec_sids doc.')

      item_stack_id = int(item_stack_ids)
      if item_stack_id <= 0:
         raise GWIS_Error('Expecting positive valued stack ID.')

      items_fetched = item_user_access.Many()
      # So we get access_infer, etc.
      qb.filters.include_item_stack = True
      # Don't forget to maybe use the session ID.
      qb.filters.gia_use_sessid = self.req.filters.gia_use_sessid
      items_fetched.search_by_stack_id(item_stack_id, qb)

      if not items_fetched:
         raise GWIS_Error('Item stack ID not found or you cannot access: %d'
                          % (item_stack_id,))

      g.assurt(len(items_fetched) == 1)
      item = items_fetched[0]
      log.verbose1('verify_access: fetched: %s' % (str(item),))
      g.assurt(not item.fresh)
      g.assurt(not item.valid)

      # What's the policy for who can make stealth secret values?
      # They're not really that special, but if every item in the database
      # had one, that's a lotta mozzarrella.
      #
      # Users should at least be able to edit: for example, if an owner of a
      # route linked to a route in a discussion, the public has view access
      # to the route based on the discussion, but we wouldn't want someone
      # with view access to create a stealth secret, since the owner should
      # actively manage the stealth secret access via the gia sharing widget.

      #  item.groups_access_load_from_db(qb)
      #  g.assurt(item.groups_access) # else, stealth to permissions_free?
      #  access_infer_id = item.get_access_infer(qb)
      if item.access_style_id == Access_Style.pub_editor:
         # Re prev. comments, ability to edit includes ability to make ssecs.
         if not item.can_edit():
            raise GWIS_Error(
               'You must be editor of public item to create link: %d'
               % (item_stack_id,))
      elif item.access_style_id == Access_Style.usr_editor:
         g.assurt(item.can_edit())
      elif item.access_style_id == Access_Style.restricted:
         # Restricted item types, like routes and track, can only have stealth
         # access created by their arbiters and owners.
         if not item.can_arbit():
            raise GWIS_Error(
               'You must be arbiter of restricted item to create link: %d'
               % (item_stack_id,))
         # This is the path when an anonymous user gets a route and makes a
         # link for it. We'll call add_stealth_gia to make sure user has access
         # to the stealth secret.
      else:
         raise GWIS_Error('What you are trying to do is not supported.')

      if item.stealth_secret:
         new_stealth_secret = False
         stealth_secret = item.stealth_secret
         log.warning('fetch_n_save: Item already has link: %d'
                     % (item_stack_id,))
      else:
         new_stealth_secret = True
         stealth_secret = self.make_stealth_secret(item)
         # See also route_get: Maybe we should just INSERT INTO
         # group_item_access ourselves, but instead we sneakily
         # use the commit command to process a style_change.
         if ((qb.filters.gia_use_sessid)
             and (qb.username == conf.anonymous_username)):
            item_arr = [item,]
            self.req.db.transaction_retryable(self.add_stealth_gia,
                                              self.req, item_arr)
            item = item_arr[0]

      # The outermost document.
      ssecrets = etree.Element('ssecrets')
      # The response document.
      ssecret = etree.Element('ssecret')
      misc.xa_set(ssecret, 'stack_id', item.stack_id)
      misc.xa_set(ssecret, 'ssecret', stealth_secret)
      # Include the possibly changed access_infer_id.
      if new_stealth_secret:
         misc.xa_set(ssecret, 'acif', item.access_infer_id)
         # Include the possibly new and changed grac records.
         if item.groups_access is None:
            item.groups_access_load_from_db(qb)
         log.debug('fetch_n_save: no. groups_access: %d'
                   % (len(item.groups_access),))
         grac_doc = etree.Element('access_control')
         misc.xa_set(grac_doc, 'control_type', 'group_item_access')
         for grpa in item.groups_access.itervalues():
            grpa.append_gml(grac_doc, need_digest=False)
         ssecret.append(grac_doc)
      # Bundle it up.
      ssecrets.append(ssecret)
      # And we're done.
      self.ssec_xml = ssecrets

   #
   def prepare_response(self):
      self.doc.append(self.ssec_xml)

   # ***

   #
   def add_stealth_gia(self, db, item_arr):

      g.assurt(len(item_arr) == 1)
      item = item_arr[0]

      # Implicitly give stealth secret holder... editor access?
      # Viewer doesn't make sense... if a user wants to restrict
      # access, they should login and save the route, eh.
      #
      # HACK ATTACK: All the good code is in commit...
      commit_cmd = commit.Op_Handler(self.req)
      commit_cmd.init_commit()
      #commit_cmd.qb = self.req.as_iqb(addons=False)
      commit_cmd.prepare_qb()

      # The item should default to Access_Infer.sessid_arbiter.
      if item.access_infer_id != Access_Infer.sessid_arbiter:
         log.warning('add_stealth_gia: unexpected access_infer_id: %d / %s'
                     % (item.access_infer_id, item,))
      style_change = item.access_infer_id | Access_Infer.stealth_editor
      commit_cmd.schanges_items[item.stack_id] = style_change

      use_latest_rid = True # I.e., don't get a new revision.
      commit_cmd.qb.item_mgr.start_new_revision(commit_cmd.qb.db,
                                                use_latest_rid)

      commit_cmd.qb.filters.gia_use_sessid = True

      log.debug('add_stealth_gia: style_change: %d / %s'
                % (style_change, item,))

      commit_cmd.process_schanges()

      # We probably don't need this:
      commit_cmd.qb.item_mgr.finalize_seq_vals(commit_cmd.qb.db)

      commit_cmd.qb.db.transaction_commit()

      # We didn't pass the item to the commit command -- just its stack ID --
      # so the commit command's item is up to date and ours is stale.

      item_arr[0] = commit_cmd.processed_items[item.stack_id]

   #
   def make_stealth_secret(self, item):

      # C.f. pyserver/gwis/query_client.py.

      num_tries = 1
      found_unique = False

      # This isn't already set, it it? If so, we'd want to reset it.
      if self.req.db.integrity_errs_okay:
         log.warning('make_stealth_secret: unexpected integrity_errs_okay')
      self.req.db.integrity_errs_okay = True

      while not found_unique:
         stealth_secret = str(uuid.uuid4())
         # For now, test the same one and see what server throws
         log.debug('make_stealth_secret: trying: %s' % (stealth_secret,))
         if num_tries > 99:
            raise GWIS_Error('stealth_secret: Too many tries!')
         try:
            self.req.db.transaction_begin_rw()
            res = self.req.db.sql(
               """
               UPDATE item_stack SET stealth_secret = '%s' WHERE stack_id = %d
               """
               % (stealth_secret, item.stack_id,))
            g.assurt(res is None)
            found_unique = True
            # BUG 2688: Use transaction_retryable?
            self.req.db.transaction_commit()
         except psycopg2.IntegrityError, e:
            # IntegrityError: duplicate key value violates unique constraint
            # "user__token_pkey"\n
            log.debug('token_gen: IntegrityError: %s' % (str(e),))
            g.assurt(str(e).startswith('duplicate key value violates'))
            num_tries += 1 # Try again
            self.req.db.transaction_rollback()

      self.req.db.integrity_errs_okay = False

      return stealth_secret

   # ***

# ***

