# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import signal
import sys
import traceback

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
from grax.grac_error import Grac_Error
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from gwis import command
from gwis import command_base
from gwis.query_filters import Query_Filters
from gwis.query_overlord import Query_Overlord
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import attachment
from item import geofeature
from item import grac_record
from item import item_base
from item import item_user_access
from item import item_versioned
from item import link_value
from item import nonwiki_item
#from item.attc import attribute
from item.attc import post
from item.attc import thread
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.feat import track
from item.grac import group
from item.grac import group_item_access
from item.util import item_factory
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency
from util_ import db_glue
from util_ import misc

# 2011.04.13: An example commit packet:
#
# <data>
#   <metadata request_is_a_test="0">
#     <changenote>Blah</changenote>
#     <user name="landonb" token="sdfdsfdsfdsfsd"/>
#   </metadata>
#   <ratings/>
#   <watchers/>
#   <items>
#     <point 
#        stack_id="-3" 
#        version="0" 
#        name="sdfds" 
#        deleted="0" 
#        geofeature_layer_id="103" 
#        z="140">
#           456734.8125 4993016.037500001</point>
#     <attribute .../>
#     <work_item .../>
#     <etc .../>
#   </items>
#   <accesses>
#     <item stack_id="-3">
#       <gia grp_id="2365741" access="3"/>
#       <gia grp_id="2359965" access="3"/>
#     </item>
#   </accesses>
# </data>

log = g.log.getLogger('cmd.commit')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      #
      'qb',                # The query builder.
      'qb2',               # The query builder, twoo.
      #
      'needs_new_revision', # True if items being committed are not nonwiki.
      'rev_groups',        # Group IDs to make group_revision records.
      # Unvetted item objects hydrated from XML.
      'changenote',        # The reason for the commit.
      'all_items_cnt',     # Count of all items from the XML.
      'non_link_items',    # Hydrated geofeatures and attachments.
      'link_val_items',    # Hydrated link_values.
      'split_into_sids',   # Byway helpers... ug: byways <sigh>.
      'split_from_grps',   # dict of split_from_stack_id => list of split-intos
      'reject_items',
      'reject_item_sids',
      'deleted_lvals',
      'deleted_items',
      'accesses_items',
      'schanges_items',
      # Unvetted non-item objects hydrated from XML.
      'ratings_byways',
      'attr_alert_email',  # for item watchers
      #
      'processed_items',   # 
      # Processed items, verified, ready to be saved.
      'commit_accesses',   # groups_access changes.
      'rating_inserts',    # item ratings.
      #'rating_updates',    # item ratings.
      'commit_item_stack_ids', # Collection of item stack IDs from user

      #
      'split_into_done',   # list of client split-into byway stack IDs
      'byways_updated',    # so we can re-calculate ratings
      'split_from_byways', # split-from byways are extra special
      'split_into_lvals',  # as are new split-into byways' new link_values
      #
      # 'new_item_cache',  # moved; see: item_mgr.item_cache
      'aux_item_cache',    # for ratings and watchers
      # Deprecated: See item_manager.client_id_map:
      #  'new_item_ids',   # map of request client IDs => newly saved item IDs
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      # Tell parent class that user wants to make a new revision
      self.branch_update_enabled = True
      # NOTE: I don't think we need to know the client's working revision ID.
      #       We have to compare against Current() and we'll complain on
      #       conflict, so knowing the working revision ID seems pointless.
      # Skipping: self.filter_rev_enabled = True
      #
      self.qb = None
      self.qb2 = None
      self.needs_new_revision = None
      self.rev_groups = None
      self.changenote = None
      self.all_items_cnt = None
      self.non_link_items = None
      self.link_val_items = None
      self.split_into_sids = None
      self.split_from_grps = None
      self.deleted_lvals = None
      self.deleted_items = None
      self.reject_items = None
      self.reject_item_sids = None
      self.accesses_items = None
      self.schanges_items = None
      self.ratings_byways = None
      self.attr_alert_email = None
      self.processed_items = None
      self.commit_accesses = None
      self.rating_inserts = None
      #self.rating_updates = None
      self.commit_item_stack_ids = set()
      self.split_into_done = None
      self.byways_updated = None
      self.split_from_byways = None
      self.split_into_lvals = None
      #self.new_item_cache = None
      self.aux_item_cache = None
      #self.new_item_ids = None

   # ***

   #
   def __str__(self):
      selfie = (
         'commit: cnt: %s / newrev?: %s / chngnt: %s / non-lval: %s'
         % (self.all_items_cnt,
            self.needs_new_revision,
            self.changenote or '(empty)',
            'none' if not self.non_link_items
                   else '1st of %d: %s'
                        % (len(self.non_link_items),
                           self.non_link_items[0],),
            ))
      return selfie

   # *** Initializers

   #
   def init_commit(self):
      # The query builder.
      self.qb = None
      self.qb2 = None
      # The revision ID: either the latest RID or the latest plus one.
      self.needs_new_revision = False
      self.rev_groups = set()
      # Variables to store hydrated, unprocessed data and items from the XML.
      self.changenote = ''
      #
      self.all_items_cnt = 0
      self.non_link_items = []
      self.link_val_items = []
      self.split_into_sids = []
      self.split_from_grps = {}
      self.deleted_lvals = {}
      self.deleted_items = {}
      self.reject_items = []
      self.reject_item_sids = set()
      #
      self.accesses_items = {}
      self.schanges_items = {}
      # Non-item saveables.
      self.ratings_byways = {}
      self.attr_alert_email = None
      #
      self.processed_items = {}
      # Collections to manage items and data being saved to the database.
      self.commit_accesses = {}
      self.rating_inserts = []
      #self.rating_updates = []
      # Special collections for handling split-from and split-into byways.
      self.split_into_done = []
      self.byways_updated = set()
      self.split_from_byways = set()
      self.split_into_lvals = {}
      # Cache collections.
      self.aux_item_cache = {}

   # *** GWIS Overrides

   # 
   def decode_request(self):

      # The base class checks the user's credentials.
      command.Op_Handler.decode_request(self)

      # Prepare our collections before parsing.
      self.init_commit()

      # Parse the incoming XML... but don't process it too much yet.
      try:

         log.debug('decode_request: Processing GWIS request')

         # Make the query builder.
         self.prepare_qb()

         # 2013.06.02: No longer allow mixed commits. Client should send map
         #             save separate from private userish things.
         wiki_item_count = 0
         map_save_count = 0
         personal_count = 0

         # Preprocess the request: consume item XML and make item objects.
         wiki_item_count += self.hydrate_items()
         map_save_count += wiki_item_count
         map_save_count += self.hydrate_accesses()
         map_save_count += self.hydrate_schanges()

         # Preprocess the rest of the XML (ratings, read events, watchers).
         # Some of these are trigger out-of-wiki experiences. E.g., if you 
         # save one item watcher and then save another item watcher, it won't
         # bump the branch revision, but it will create a new link_value
         # version. This is legal for wiki changes that are private -- see
         # BUG nnnn: Private changelog for revision-less commits.
         personal_count += self.hydrate_ratings()
         personal_count += self.hydrate_watchers()

         n_items = (  len(self.deleted_items)
                    + len(self.deleted_lvals)
                    + len(self.split_into_sids)
                    + len(self.non_link_items)
                    + len(self.link_val_items))
         g.assurt(n_items == self.all_items_cnt)

         # Ratings and Watchers are queued for map save for fresh items,
         # otherwise they come independently (and revisionlessly). So don't
         # bother enforcing this:
         #  if map_save_count and personal_count:
         #     raise GWIS_Error('NOTE TO DEV: Cannot save map and personalia.')

         if map_save_count:
            # If the commit is for real wiki items, look for a changenote.
            if self.needs_new_revision:
               g.assurt(wiki_item_count)
               # NOTE: If the changenote is not attached, we just set it NULL.
               # MAYBE: Require that the client always includes a comment?
               self.hydrate_changenote()
            # else, wiki_item_count is 0 if we're just saving ratings, etc.,
            #       and wiki_item_count is > 0 if saving nonwiki_item, like
            #       work_item.
         else:
            if not personal_count:
               # 2014.09.09: [lb] saw this fire Sep-09 05:48:33.
               log.error('decode_request: nothing to commit: doc_in: %s'
                  % (etree.tostring(self.req.doc_in, pretty_print=False),))
               raise GWIS_Error('Nothing to commit.')
            g.assurt(not self.needs_new_revision)

         # See if the commit is anonymous-able.
         if personal_count > 0:
            # User must be logged in. Client should prevent this.
            if ((not self.qb.username) 
                or (self.qb.username == conf.anonymous_username)):
               raise GWIS_Error('Please logon to save personalia.')

         # Check that there's really something to do.
         n_objects_to_save = map_save_count + personal_count
         if not (n_objects_to_save > 0):
            # NOTE: Using GWIS_Error since this seems like a client issue.
            raise GWIS_Error('Cannot commit: Nothing to save.')

         # Check if the XML has errors.
         if self.qb.grac_mgr.grac_errors:
            # NOTE: Using GWIS_Error so we see this in logcheck, since this
            #       should be a programmer error (I think).
            raise GWIS_Error('Cannot commit: Errors during decode_request.')

         # I'm [lb] not sure if this code'll run -- we don't have a problem
         # with banned users and we don't really test the site while
         # impersonating a banned user (lazy, I know) -- but the intent is to
         # restrict banned users from contributing publically.
         if self.user_client_ban.is_full_banned():
            # NOTE: Using GWIS_Error so this error is flagged by logcheck.
            barf = GWIS_Error('Not allowed to save anything when fully banned')

      except GWIS_Warning, e:
         self.gwis_error_append_errs(e)
         raise

      except Exception, e:
         raise

   #
   def fetch_n_save(self):

      # The base class just sets self.doc to the incoming XML document.
      command.Op_Handler.fetch_n_save(self)

      # At this point, we've checked the user's credentials and have asserted
      # that the user has view-access-or-better to the branch item. We don't
      # know about the user's access to existing items or if they have rights
      # to create new items of particular types. We'll figure that out
      # individually for each item the user is committing.

      try:

         # If we're not committing any items, we don't have to lock the
         # revision table (for things like ratings). But if we're saving items
         # -- even Nonwiki items, which need stack and system IDs -- we have to
         # lock the revision table.
         self.save_get_revision()

         # Save all the items (incl. non-wiki work items).
         self.save_all_items()

         # Check if the XML has errors.
         if self.qb.grac_mgr.grac_errors:
            # NOTE: Using GWIS_Error so we see this in logcheck, since this
            #       should be a programmer error (I think).
            raise GWIS_Error('Cannot commit: Errors during fetch_n_save.')

         # Save the new revision rows.
         self.save_new_revision()

         # Check that the client didn't send new attachments without 
         # link_values, or new link_values without real lhs and rhs items.
         self.clean_orphans()

         # Save groups_access records that weren't processed with the items.
         self.process_accesses()
         # Same for style changes that didn't come with corresponding items.
         self.process_schanges()

         # 2012.07.20: This is a late check to see if the user is banned, or if
         # the site is in semi-protected mode, but we allow saving of private 
         # data (ratings, watchers, etc.) (which seems weird to do when someone
         # is banned...) so we have to hydrate and process items before we can
         # make this check.
         self.process_cleanup_check_semiprotect()

         if self.qb.grac_mgr.grac_errors:
            # BUG nnnn: Returning list of errors to the user. Pyserver does
            # this, but flashclient doesn't do anything with it (other than to
            # show it to the user in a popup). Integrate this into the branch
            # conflicts resolver (the idea is basically the same -- there's a
            # conflict).
            raise GWIS_Error('Cannot commit: one or more errors.')

         # Commit so we give up the table lock if we saved items or accesses; 
         # if we only have ratings/readers/watchers we didn't lock 'revision'.
         self.commit_maybe(is_for_real=True, final_commit=False)

         # NOTE: If we're here, we may have committed a new revision. But we're
         #       not doing processing yet, and if we accumulate any errors
         #       henceforth, we need to suppress them, because if we return
         #       any gwis errors, the client won't think we saved the map
         #       successfully, and we won't send back the client ID to
         #       permanent ID map.

         # Process user ratings. If the user sends a stack ID that we can't
         # translate or to which they don't have permissions to view, we
         # silently log an error but still return success to the client. This
         # is because of what is stated in the last comment: if we just
         # committed a new revision, we don't want to return error codes to the
         # client, but we want to make sure to return the client id map.
         self.save_non_items()

         # Don't commit, unless we're testing, in which case, rollback the db.
         self.commit_maybe(is_for_real=False, final_commit=True)

      except GWIS_Warning, e:

         revision.Revision.transaction_rollback(self.qb.db)
         self.gwis_error_append_errs(e)
         raise

      except Exception, e:
         # If you have Python runtime errors, they show up here, but sometimes
         # we have two cursors open... because we cloned one...
         #import rpdb2;rpdb2.start_embedded_debugger('password',fAllowRemote=True)
         if self.qb2 is not None:
            self.qb2.db.close()
            self.qb2 = None

         revision.Revision.transaction_rollback(self.qb.db)
         raise

      # If there are permissions or other errors, we should've bailed by now.
      # MAYBE: What about save_non_items errors?? How do we process those?
      #        We would've saved those by now... so any errors we saw would be
      #        unrecoverable...
      # All that's left is to kick Mr. Do! and wake up routed, so there's no
      # need to assert... though we could do a soft assert...
      #g.assurt(len(self.qb.grac_mgr.grac_errors) == 0)

      # In CcpV1, at this point -- after committing the new revision -- we'd
      # email users that are watching any items that were just edited. But we
      # shouldn't send emails during an HTTP request, since we'll just keep
      # the client waiting on the commit success. So we use cron to email
      # users- see script/daily/watchers_email.sh.

      # In CcpV2, the post commit fcn. is very simple -- it just kicks Mr. Do!.
      #self.qb.item_mgr.do_post_commit(self.qb, self.processed_items)
      self.qb.item_mgr.do_post_commit(self.qb)

      # Tell routed to reload.
      if self.needs_new_revision or self.rating_inserts:
         self.routed_hup(self.qb.db)
      # NOTE: An Apache cron job calls mapserver/check_cache_now.sh every min.
      #       MAYBE: Is there a way to have that script run more immediately?
      #       MAYBE: Make a mapserver daemon so tiles are rebuilt immediately?
      # MAYBE: Make a watcher daemon rather than running the watcher cron.
      # if self.needs_new_revision:
      #    self.watcherd_hup()

      log.debug('save: done.')

   #
   def prepare_metaresp(self):
      command.Op_Handler.prepare_metaresp(self)

   #
   def prepare_response(self):

      log.debug('prepare_response')

      ids_doc = etree.Element('result')

      for cli_id, new_id in self.qb.item_mgr.client_id_map.iteritems():

         # We may have made up some client IDs that the flashclient doesn't
         # know about, and the flashclient may have client IDs with matching
         # values, so don't send information for those items.

         if cli_id in self.commit_item_stack_ids:

            id_doc = etree.Element('id_map')

            misc.xa_set(id_doc, 'cli_id', cli_id)
            misc.xa_set(id_doc, 'new_id', new_id)

            item = self.qb.item_mgr.item_cache[new_id]
            g.assurt(item is not None)
            # This is a little coupled: if a byway, add the endpoint IDs.
            if isinstance(item, byway.One):
               misc.xa_set(id_doc, 'beg_nid', item.beg_node_id)
               misc.xa_set(id_doc, 'fin_nid', item.fin_node_id)
            # Always add the new version.
            misc.xa_set(id_doc, 'new_vers', item.version)
            misc.xa_set(id_doc, 'new_ssid', item.system_id)
            # 2013.12.20: Send back access records so flashclient doesn't
            # have to re-request or to do the math itself (which is more
            # dangerous, because then we end up duplicating important code
            # in the server and the client, and the server should always
            # be right, even when it's wrong).
            misc.xa_set(id_doc, 'acif', item.access_infer_id)
            misc.xa_set(id_doc, 'alid', item.access_level_id)

            # This is what gwis.command_.grac_get.prepare_response does:
            grac_doc = etree.Element('access_control')
            misc.xa_set(grac_doc, 'control_type', 'group_item_access')
            if item.groups_access is not None:
               for grpa in item.groups_access.itervalues():
                  # [lb] seeing version = 1 and name = item's name
                  # for gia records, where item version > 1, also, gia records
                  # are not named... for now, masking the issue, and only
                  # sending the data we need.
                  # TMI: grpa.append_gml(grac_doc, need_digest=False)
                  gia_doc = etree.Element(
                              group_item_access.One.item_gwis_abbrev)
                  misc.xa_set(gia_doc, 'gpid', grpa.group_id)
                  misc.xa_set(gia_doc, 'alid', grpa.access_level_id)
                  # Probably not needed or possibly wrong:
                  #  misc.xa_set(gia_doc, 'v', grpa.version)
                  #  misc.xa_set(gia_doc, 'aclg', grpa.acl_grouping)
                  grac_doc.append(gia_doc)
            id_doc.append(grac_doc)

            log.debug(
               'prep_resp: cli_id: %s / new_id: %s / vers: %s / aifr: %s'
               % (cli_id, new_id, item.version, item.access_infer_id,))

            ids_doc.append(id_doc)

      # NOTE: In CcpV1, wfs_ShareRoute is basically a specialized
      #       wfs_PutFeature, which is why in CcpV2 sharing a route is done
      #       simply by committing an item.
      #       But in CcpV1, ShareRoute clones the route (deleting the old one
      #       and creating a new one with new permissions) and then returns the
      #       new route. [lb] doesn't like this; I think those are two separate
      #       operations: if the client wants the saved route, it should just
      #       send a Checkout command.

      self.doc.append(ids_doc)

   # *** Helpers -- decode_request()

   #
   def prepare_qb(self):

      username = None
      user_group_id = None

   # FIXME: Do I need to findall() or anything?
      anon_coward = self.req.doc_in.get('anon_coward', False)
      # Etymology: 'Anonymous Coward': Yes, [lb] ripped off /.
      # For a logged-in user who wants to disassociate.
      # Not-so-anonymous-but-mostly cowards: since at least the server knows
      # who they are, even if we don't save that information to the public
      # wiki.
      if anon_coward:
         username = conf.anonymous_username
         # MAYBE: Is it okay to steal the request's db?
         user_group_id = group.Many.public_group_id(self.req.db)

      # Assemble the qb from the request.
      self.qb = self.req.as_iqb(addons=False,
                                username=username,
                                user_group_id=user_group_id)

      # Note that commit always happens against the Current revision. And we
      # don't need an historic revision for the user's working copy: we'll see
      # if there are conflicts by inspecting each item-being-committed's 
      # version.
      g.assurt(isinstance(self.qb.revision, revision.Current))

      # 2013.09.12: We always want the item_stack stuff, right?
      self.qb.filters.include_item_stack = True

      # The grac mgr gets row shares on the policies, so start the transaction.
      # 2012.09.25: No longer true: grac_mgr no longer row locks...
      self.qb.db.transaction_begin_rw()

      # The Item mgr was setup by as_iqb.
      g.assurt(self.qb.item_mgr is not None)
      # We're starting fresh.
      #self.qb.item_mgr.item_cache_reset()
      g.assurt(len(self.qb.item_mgr.item_cache) == 0)

      # The Grac mgr is not setup by as_iqb, because it's much less frequently 
      # used. The Grac mgr loads the user's NIPs and Group Memberships.
      self.qb.grac_mgr = Grac_Manager()
      self.qb.grac_mgr.prepare_mgr('user', self.qb)

      # as_iqb already finalized the query, but it doesn't hurt to do it again.
      Query_Overlord.finalize_query(self.qb)

   # *** Helpers -- commit_maybe()

   #
   def commit_maybe(self, is_for_real, final_commit):
      g.assurt(is_for_real ^ final_commit)
      # If we're fake-committing (just testing the request), only do one final
      # commit, otherwise the non-wiki transaction won't see any new items from
      # the first transaction.
      dont_really_commit = self.qb.request_is_a_test or conf.commit_to_testing
      if not dont_really_commit:
         log.debug('commit_maybe: committing transaction...')
         revision.Revision.transaction_commit(self.qb.db)
         log.debug('commit_maybe: committed.')
      elif final_commit:
         if not conf.commit_to_testing:
            log.warning('save: just testing: rolling back!')
            revision.Revision.transaction_rollback(self.qb.db)
         else:
            raise GWIS_Error(
               'Your map save would have worked! '
               + 'But we are only in test mode. '
               + 'Thank you for helping us test!')
      # else, don't commit or raise yet if just testing,
      #       so that save_non_items works.

   # *** decode_request: hydrate_items

   #
   def hydrate_items(self):

      # Get the list of items being saved
      items_xml_elems = self.req.doc_in.findall('./items/*')

      if items_xml_elems:
         items_hydrated = self.hydrate_item_from_xml(items_xml_elems,
                                                     for_map_save=True)
         n_items = len(items_hydrated)
      else:
         # This is not a map save.
         n_items = 0

      return n_items

   #
   def hydrate_item_from_xml(self, items_xml_elems, for_map_save):

      log.debug('hydrate_item_from_xml: u: %s / br: %s / rev: %s' 
                % (self.qb.username, self.qb.branch_hier[0][0], 
                   self.qb.revision,))

      items_hydrated = []

      # 2012.07.16: Historically, we've just sorted the items list and 
      # processed attachments and geofeatures first and link_values last. 
      # But we need to do some additional processing after handling nonlinks,
      # before processing link_values. This is because splitting a byway
      # requires a lot of additional processing.
      # 2012.08.16: Also, we need to save a new thread before we can save a 
      # post, since the post needs the thread's permanent ID. We already make
      # three collections of items here byways, non-link_values, and
      # link_values -- so we could make a fourth collection for threads, or 
      # we could let the item classes define their sort order and sort the 
      # non-link_value collection using that. For now, trying the latter; 
      # see later re: item_save_order.

      # Go through the XML, hydrate objects, and populate some lists.

      # We need to check that the client isn't mixing nonwiki and wiki items.
      n_nonwiki_items = 0

      # Some item types can be saved reviosionlessly.
      n_revisionless_items = 0      

      # We need to update the item_manager's client_id with the lowest of the
      # low, plus minus one.
      #client_id_min = -1
      client_id_min = self.qb.item_mgr.next_client_id
      log.debug('hydrate_item_from_xml: old client_id: %s' % (client_id_min,))

      for item_elem in items_xml_elems:

         # NOTE: Henceforth, item_elem.tag is the XML attribute, not the
         #  item's tag attachment... just an fyi, so you don't get confused....
         log.debug('hydrate_item_from_xml: item_elem.tag: %s' 
                   % (item_elem.tag,))

         # Get a handle to the item class and create a new item.
         # This raises if the item XML does not specify a known item type.
         item_module = item_factory.get_item_module(item_elem.tag)
         item = item_module.One(qb=self.qb, req=self.req)

         # Setup the new item using the item XML.
         suc = item.from_gml(self.qb, item_elem)

         if suc is False:

            # BUG nnnn: 2014.09.17: [lb] created intersection at S Lake Blvd NE
            # at 117th La NE and the client split existing byway into two
            # segments, but one of the new segments reduces to a point. So
            # adding reject_items, so we can ignore these byways and their
            # link_values and style changes.
            log.warning('hydrate_item_from_xml: bad gml: %s' % (item,))
            self.reject_items_add(item)

         else:

            items_hydrated.append(item)

            # See if this is the new minimum client ID.
            if item.stack_id <= client_id_min:
               client_id_min = item.stack_id - 1

            # Send a commit id_map response for this item.
            self.commit_item_stack_ids.add(item.stack_id)

            # Add the item to one or more processing lists.
            if item.deleted:
               log.debug('hydrate_item_from_xml: deleting: item: %s' % (item,))
               if not isinstance(item, link_value.One):
                  self.deleted_items[item.stack_id] = item
               else:
                  self.deleted_lvals[item.stack_id] = item
            elif not isinstance(item, link_value.One):
               # This is an attachment, geofeature, or nonwiki_item.
               if isinstance(item, byway.One):
                  # For split-from byways, process their split-intos en masse.
                  # NOTE: The client might not send all the split segments,
                  #       e.g., if the user deleted one of them. Deal with it.
                  if item.split_from_stack_id is not None:
                     g.assurt(item.stack_id is not None) # b/c None < 0 is True
                     g.assurt(item.stack_id < 0)
                     # Too harsh: g.assurt(item.split_from_stack_id > 0)
                     if item.split_from_stack_id <= 0:
                        log.error(
                           'hydrate_item_from_xml: bad split_from_stack_id: %s'
                           % (str(item),))
                        self.qb.grac_mgr.grac_errors_add(
                           item.split_from_stack_id, 
                           Grac_Error.invalid_item,
                           '/byway/split_from_stack_id')
                     g.assurt(item.stack_id not in self.split_into_sids)
                     self.split_into_sids.append(item.stack_id)
                     misc.dict_list_append(self.split_from_grps, 
                                           item.split_from_stack_id,
                                           item)
                  else:
                     # For byways not being split, process normally.
                     g.assurt(not item.split_from_stack_id)
                     self.non_link_items.append(item)
               else:
                  # For all other non-link_value items, process normally.
                  self.non_link_items.append(item)
                  if (   isinstance(item, route.One)
                      # FIXME/BUG nnnn: Revisionless tracks.
                      #or isinstance(item, track.One)
                      or isinstance(item, thread.One)
                      or isinstance(item, post.One)):
                     n_revisionless_items += 1
                  elif isinstance(item, nonwiki_item.One):
                     n_nonwiki_items += 1
            else:

               # A link_value.
               self.link_val_items.append(item)

               # Consider map items linked to posts as revisionless.
               # Include threads as well, for completeness.
               # Note that for /item/alert_email, lhs is the attribute
               # and rhs is a thread, geofeature, route, or revision.
               # In this case, for_map_save is False, so we won't save a new
               # revision (and we don't bother inc'ing n_revisionless_items).
               if (   (item.link_lhs_type_id == Item_Type.POST)
                   or (item.link_lhs_type_id == Item_Type.THREAD)):
                  n_revisionless_items += 1

      # end: for item_elem in items_xml_elems

      # Increment the all-items count.
      n_items = len(items_hydrated)
      self.all_items_cnt += n_items

      # We're not expecting a mix of wiki and nonwiki items, and only wiki
      # items are revisioned.

      if n_nonwiki_items > 0:
         g.assurt(not self.needs_new_revision)
         if n_nonwiki_items != n_items:
            # This is a programmer or client error.
            raise GWIS_Error('Please do not mix Nonwiki and Wiki commits.')
      elif n_items:
         if for_map_save and (n_revisionless_items < n_items):
            # This is a real map save.
            self.needs_new_revision = True
         # else, this is just link_values for personalia, or a route.

      # Update the item_manager's client ID sequence.
      log.debug('hydrate_item_from_xml: new client_id: %s' % (client_id_min,))
      self.qb.item_mgr.next_client_id = client_id_min

      return items_hydrated

   # *** decode_request: hydrate_access

   #
   #   <accesses>
   #     <item stid="-3">
   #       <gia gpid="2354349" alid="3"/>
   #       <gia gpid="2359855" alid="3"/>
   #     </item>
   #  </accesses>
   def hydrate_accesses(self):
      log.debug('hydrate_accesses')
      # Get the list of accesses.
      accesses_xml_elems = self.req.doc_in.findall('./accesses/*')
      if accesses_xml_elems:
         # Create group_item_access objects for each
         for access_elem in accesses_xml_elems:
            g.assurt(access_elem.tag == 'item')
            #log.debug('hydrate_accesses: %s' % etree.tostring(access_elem))
            # NOTE: This raises if the 'stid' attr is missing. If a problem, 
            # we'll want to add to grac_error instead, but this should just be
            # a programmer error in the client.
            # MAYBE: This is the only place in commit that uses
            #        from_gml_required... seems weird.
            stack_id = int(item_base.One.from_gml_required(
                                    access_elem, 'stid'))
            self.accesses_items[stack_id] = access_elem
         # NOTE: Not setting needs_new_revision: GIA changes alone can use the 
         # acl_grouping to change accesses without creating a new revision or
         # incrementing item versions.
      return len(self.accesses_items)

   # *** decode_request: hydrate_schanges

   #
   #   <schanges>
   #     <item sid="-3" schg="3"/>
   #     ...
   #  </schanges>
   def hydrate_schanges(self):
      log.debug('hydrate_schanges')
      # Get the list of schanges.
      schanges_xml_elems = self.req.doc_in.findall('./schanges/*')
      if schanges_xml_elems:
         log.debug('hydrate_schanges: %s' % (schanges_xml_elems,))
         for schange_elem in schanges_xml_elems:
            g.assurt(schange_elem.tag == 'item')
            stack_id = int(
               item_base.One.from_gml_required(schange_elem, 'stid'))
            style_change = int(
               item_base.One.from_gml_required(schange_elem, 'schg'))
            self.schanges_items[stack_id] = style_change
            log.debug('hydrate_schanges: %d / %d' % (stack_id, style_change,))
      return len(self.schanges_items)

   # *** decode_request: hydrate_ratings

   #
   def hydrate_ratings(self):
      log.debug('hydrate_ratings')
      # Decode byway ratings.
      ratings_xml_elems = self.req.doc_in.findall('./ratings/*')
      if ratings_xml_elems:
         for rating_elem in ratings_xml_elems:
            item_stack_id = int(rating_elem.get('stack_id'))
            rating = float(rating_elem.get('value'))
            g.assurt(-1 <= rating <= 4) # FIXME: magic number
            self.ratings_byways[item_stack_id] = rating
      return len(self.ratings_byways)

   # *** decode_request: hydrate_watchers

   #
   def hydrate_watchers(self):

      log.debug('hydrate_watchers')

      # CcpV2: Watchers are private attribute link_values. We can save this
      #        out-of-band, so to speak, and use the current Cyclopath rev.
      #        In CcpV1 these were special little tuples that had their own
      #        table.

      watchers_xml_elems = self.req.doc_in.findall('./watchers/*')

      if watchers_xml_elems:

         # Clients only commit watchers individually. We don't support
         # committing other item edits at the same time because of how
         # we manage item lists in this class. There's also not a big
         # reason to do so: configuring item watching is not revisiony,
         # and item watching is a singular, immediate UI operation.
         items_hydrated = self.hydrate_item_from_xml(watchers_xml_elems,
                                                     for_map_save=False)
         n_items = len(items_hydrated)

         if n_items:

            internal_name = '/item/alert_email'

            # We can call attribute.Many.get_system_attr, or we can thunk it.
            aaemail = self.qb.item_mgr.get_system_attr(self.qb, internal_name)
            g.assurt(aaemail is not None)
            self.attr_alert_email = aaemail
            self.qb.item_mgr.item_cache_add(aaemail)

            for lval in items_hydrated:
               if lval.lhs_stack_id != self.attr_alert_email.stack_id:
                  raise GWIS_Error('Unexpected lval watcher: %s.'
                                   % (lval.lhs_stack_id,))

      else:
         n_items = 0

      return n_items

   # *** decode_request: hydrate_changenote

   #
   def hydrate_changenote(self):
      # Process changenote
      # FIXME: If this isn't specified in the GML, this fails. S'okay?
      # NOTE: For find(), ./something is same as ./something/ and something
      try:
         self.changenote = self.req.doc_in.find('./metadata/changenote').text
         log.debug('changenote: %s' % (self.changenote,))
      except AttributeError:
         self.changenote = None
         # Lots of people seem to make small changes without a changenote.
         # It's not bad, but maybe the client could put something in italic,
         # like, 'no changenote'.
         log.debug('hydrate_changenote: No changenote.')

   # *** save: save_get_revision

   #
   def save_get_revision(self):

      # BUG nnnn: MAYBE (P4/5): Saving Nonwiki items competes with Wiki items.
      # Nonwiki items use stack and system IDs because they have GIA
      # records. This means that creating new Nonwiki items blocks if a
      # commit is outstanding. This will normally not be an issue, but if
      # it becomes an issue (i.e., high-traffic site), you might be able to
      # queue the work item request so you can complete the apache request and
      # then add the nonwiki item for real once the 'revision' table lock is
      # available. (Another option is to make a separate GIA table for Nonwiki
      # items but that seems more tedious, since you'd have to make Nonwiki
      # checkouts use a different GIA table, and it still doesn't solve the
      # problem of overlapped commits: seems the best option is to queue
      # commits to be processed like work item jobs: tell the user their commit
      # is pending and let the user cancel at any time until it's started to be
      # processed. Using a job queue for commits might also make dealing with
      # imports easier, since committers would see jobs ahead of theirs, maybe;
      # also, this would maybe solve the problem of how we react when there are
      # conflicts -- if there was a job list, and if a commit failed, we could 
      # link to the branch conflicts widget.)

      # FIXME: Do access changes always mean getting a new revision? Probably
      #        not... they would mean locking the revision table, at least.
      if self.all_items_cnt or len(self.accesses_items):
         # Lock the revision table.
         # BUG nnnn: Timeout waiting for revision lock and tell user to try 
         # (closed/  again. rather than letting the Apache request timeout
         #   fixed)  after a minute or whatever, we can use NOWAIT to try
         #           locking the table and bail earlier. E.g., try to get the
         #           lock for ten seconds and then give up and tell the user
         #           to try again. While in CcpV1 it's not likely that any one
         #           process will have a lock on the table for very long, in
         #           CcpV2 we have to worry about import jobs. And we shouldn't
         #           leave things up to chance, anyway: it's better to be
         #           proactive.
         indeliberate = not self.qb.cp_maint_lock_owner
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='save_get_revision', indeliberate=indeliberate)

         # If we're here, we've got the revision table lock.

         # Unless we're just committing a new job, get a new revision ID.
         use_latest_rid = not self.needs_new_revision
         # Peek at the next revision ID.
         # Fixed: BUG nnnn: Do not burn sacred IDs (from sequences).
         #        (Meaning, we peak at the revision number, so in case
         #        we fail, the revision number won't have been claimed.)
         self.qb.item_mgr.start_new_revision(self.qb.db, use_latest_rid)
         log.debug('save: Using %s revision: %d' 
                   % ('next' if not use_latest_rid else 'same', 
                      self.qb.item_mgr.rid_new,))

      # else, we aren't saving a new revision.

      if not self.qb.item_mgr.rid_new:
         g.assurt(not self.needs_new_revision)
         # Set the 'new' revision ID to the latest one in the database.
         # Call item_mgr so it configures itself properly.
         #self.qb.item_mgr.rid_new = revision.Revision.revision_max(self.qb.db)
         use_latest_rid = True # I.e., don't get a new revision.
         self.qb.item_mgr.start_new_revision(self.qb.db, use_latest_rid)
         log.debug('save: Using latest revision: %d'
                   % (self.qb.item_mgr.rid_new,))

   # *** save: save_all_items

   #
   def save_all_items(self):

      log.debug('save_all_items: saving items')

      # We don't always call load_feats_and_attcs, so ensure cache is loaded.
      self.qb.item_mgr.load_cache_attachments(self.qb)

      # Save all other non-link_value items.
      if self.non_link_items:
         self.save_non_split_non_lvals()
         # ... which calls: process_item_hydrated.

      # Process all split-from and split-into byways. This bulk-loads the
      # split-from byways and uses the split-into gml from the client.
      if self.split_from_grps:
         self.save_split_byways()
         # ... which calls: process_item_hydrated via process_split_from.

      # Save link_values, now that the items that they link exist,
      # and any new attachments exist.
      if self.link_val_items:
         self.save_link_values()
         # ... which calls: process_item_hydrated.

      # Delete link_values.
      if self.deleted_lvals:
         self.delete_link_values()
         # ... which calls: mark_deleted (see also: f_process_item_hydrated).

      # Delete non link_values.
      if self.deleted_items:
         self.delete_non_lvalues()
         # ... which calls: mark_deleted.

      # Finish off the split-froms.
      if self.split_from_byways:
         self.delete_split_froms()
         # ... which calls: mark_deleted.

   # *** save_all_items: the common processing routine

   #
   def process_item_hydrated(self, qb, item, ref_byway=None):

      success = False

      # We expect split-into byways to come with their split-from.
      # Note that existing byways can still have split_from_stack_id
      # set, so we only care if the item being saved is fresh.
      g.assurt(item.stack_id is not None)
      if ((isinstance(item, byway.One))
          and (item.split_from_stack_id)
          and (item.stack_id < 0)):
         g.assurt(ref_byway is not None)
      else:
         g.assurt(ref_byway is None)

      client_id = item.stack_id

      # See if the item is a link_value for a split-into byway. For split
      # byways, the split-into byways save new link_values when they're
      # initially split 'n saved. So if the client sends a
      # split-into's link_values, those link_value client IDs won't match.
      updated = None
      prepared = False
      if isinstance(item, link_value.One):
         if item.fresh:
            updated = item.update_if_split_into(qb, self.split_into_lvals)
            if updated is not None:
               # We'll skip all the code below, the only bit of which we might
               # want is the style_change or gia change, but so far link_values
               # access_level_ids are software-bound, so no client would ever
               # specify access changes.
               # Also, the want to forget about the client's item: we just
               # cloned it into the split-into link_value, so use that one.
               item = updated
               try:
                  permanent_id = self.qb.item_mgr.client_id_map[client_id]
                  g.assurt(permanent_id == item.stack_id)
               except KeyError:
                  pass
               log.debug('process_item_hydrated: client_id_map.1: %d ==> %d'
                           % (client_id, item.stack_id,))
               qb.item_mgr.item_cache_add(item, client_id)
               try:
                  del self.schanges_items[client_id]
               except KeyError:
                  pass

      if updated is None:

         # Check the Stack ID sent from the client. If it's negative, it means
         # the item was created in the user's working copy, and we need to
         # make a new ID for it, or look up the existing ID. If this is a
         # link_value, it'll correct the client IDs of its lhs/rhs_stack_ids,
         # but we already did that in update_if_split_into.
         item.stack_id_correct(qb)
         g.assurt(item.stack_id > 0)

         try:
            permanent_id = self.qb.item_mgr.client_id_map[client_id]
            g.assurt(permanent_id == item.stack_id)
         except KeyError:
            pass

         # Cache the new item.
         log.debug('process_item_hydrated: client_id_map.2: %d ==> %d'
                     % (client_id, item.stack_id,))
         qb.item_mgr.item_cache_add(item, client_id)

         # Prepare the item. This checks permissions and creates new GIA
         # records or copies existing ones. This also calls validize to setup
         # the new item. We'll also copy any values that the client didn't
         # specify in the XML; the client has to be explicit when deleting
         # values, otherwise we'll just maintain existing item members that
         # aren't in the XML.

         # Get the style change, maybe.
         try:
            log.debug('process_item_hydrated: client: %d / item.stack_id: %d'
                      % (client_id, item.stack_id,))
            item.style_change = self.schanges_items[client_id]
            del self.schanges_items[client_id]
            item.dirty_reason_add(item_base.One.dirty_reason_grac_user)
            log.debug('process_item_hydrated: stack_id: %d / style_change: %d'
                      % (item.stack_id, item.style_change,))
         except KeyError:
            pass

         # This is so anonymous users can save changes to their route.
         # MAYBE: Just call prepare and catch GWIS_Error and then try sess ID?
         qb.filters.gia_use_sessid = self.req.filters.gia_use_sessid

         # MAYBE: Bulk-load. The grac_mgr calls the item's validate(),
         # which uses its own stack ID or ref_byway's stack ID to load
         # the groups_access to be copied to the new item. This could be
         # inefficient for large commits...

         if not item.valid:
            prepared = qb.grac_mgr.prepare_item(qb,
               item, Access_Level.editor, ref_byway)
         else:
            prepared = True

         # GrAC Mgr always sets the item dirty....
         g.assurt((not prepared)
                  or (item.dirty != item_base.One.dirty_reason_none))

         qb.filters.gia_use_sessid = False

      if (updated is None) and prepared:

         # Place the new item on the queue. We'll save() it later, or return a
         # list of errors (if one or more errors occurred in prepare_item).

         # The item should have valid permissions now.
         g.assurt(isinstance(item, grac_record.One) or item.groups_access)

         if item.stack_id in self.processed_items:
            # This should be a programmer error.
            log.warning('Duplicate stack_id being saved? %s and %s' 
                        % (item, self.processed_items[item.stack_id]))
            #raise GWIS_Error(
            #   'Cannot commit item(s): Same stack ID seen multiple times.')
            qb.grac_mgr.grac_errors_add(client_id, 
               Grac_Error.duplicate_item,
               '/byway/duplicate_stack_id')
            prepared = False
            item.valid = False

         if not item.valid:
            # This should be a programmer error.
            log.error('process_item_hydrated: not valid: %s' % (str(item),))
            #raise GWIS_Error('Cannot commit item(s): Internal failure.')
            qb.grac_mgr.grac_errors_add(client_id, 
               Grac_Error.invalid_item,
               '/byway/invalid_item')
            prepared = False

      if (updated is None) and prepared:

         # Look for access records from the client for this item. Only classes
         # derived from item_user_access do this; grac_record classes skip it.
         g.assurt((isinstance(item, grac_record.One))
                  or (item.access_style_id))

         if item.access_style_id and item.valid:
            try:
               accesses_elem = self.accesses_items[client_id]
               if item.style_change:
                  raise GWIS_Error(
                     'Please do not specify style_change and GIA accesses.')
               if item.access_style_id != Access_Style.permissive:
                  raise GWIS_Error(
                     'You can only use GIA accesses with permissive style.')
               # Load the GML. This checks that the user can arbit the item
               # and that the item access style is permissive.
               log.debug('process_item_hydrated: processing groups_access')
               item.groups_access_load_from_gml(qb, accesses_elem)
               # Whether prepared or not, remove the access entry; later, we'll
               # process self.accesses_items, which will be access-only
               # changes, i.e., client didn't send GML for any item changes.
               del self.accesses_items[client_id]
            except KeyError:
               # The user did not send GIA access records for this item.
               # See if the user requested an access_level state transition.
               # Note that if we called prepare_item earlier for 'acl_choice',
               # grac_manager clearer item.style_change. This is only for
               # 'restricted'. And maybe 'permissive'... or maybe for cloning
               # items...
               if item.style_change:
                  log.debug('process_item_hydrated: groups_access_style_chang')
                  item.groups_access_style_change(qb)

         # Update the database.
         if item.valid:
            success = True
            if item.is_dirty():
               self.save_item_to_db(qb, item)
               # Remember which groups need a group revision for the update. 
               # Always include the private group ID of the user making the 
               # change, and also see with which group IDs the item associates.
               # 2013.03.28: No: self.rev_groups.add(qb.user_group_id)
               item.group_ids_add_to(self.rev_groups, self.qb.item_mgr.rid_new)
               # If this is a fresh split-into byway, add its link_values to
               # a lookup that we'll use later to correct the client's
               # link_values' client IDs.
               if ref_byway is not None:
                  for lval in item.link_values.itervalues():
                     g.assurt(lval.rhs_stack_id == item.stack_id)
                     misc.dict_dict_update(self.split_into_lvals,
                                           lval.rhs_stack_id,
                                           lval.lhs_stack_id,
                                           lval)
               # Is this a good spot for this? If this is a branch...
               if isinstance(item, branch.One):
                  log.debug('process_item_hydrated: branch: %s' % (item,))
                  rid = self.qb.item_mgr.rid_new
                  byway.Many.branch_coverage_area_update(qb.db, item, rid)
            else:
               # FIXME: Does this happen?
               log.error('process_item_hydrated: not dirty?: %s'
                         % (str(item),))
         # else, no-op; we'll keep processing items but we'll eventually return
         #              an error to the user.

      # else, updated is not None and not prepared,
      #       and prepare_item added an error.

      self.processed_items[item.stack_id] = item

      return success

   #
   def save_item_to_db(self, qb, item):

      # Remember byways whose byway or tags or attrs changed
      # so can recalculate their generic ratings.
      self.remember_updated_byway_maybe(item)

      # FIXME: This check seems... silly. Why are we double-checking
      # explicitly here? Seems we should have already guaranteed this.
      qb.grac_mgr.verify_access_item_update(item)
      g.assurt(item.valid)

      if item.dirty != item_base.One.dirty_reason_none:
         # For versioned wiki items, this'll update the old/existing row and
         # reset its max rev id (from inf to rid).

         #same_version = False
         same_version = (not self.needs_new_revision)
         same_revision = (not self.needs_new_revision)
         if (item.dirty & (  item_base.One.dirty_reason_item_auto
                           | item_base.One.dirty_reason_item_user)):
            # You can only use acl_grouping if the item is not being edited.
            # E.g., routes can be edited and saved using the same map revision
            #       but the new route should have a new version, not a new
            #       acl_grouping.
            if not isinstance(item, nonwiki_item.One):
               same_version = False
            # else, a Nonwiki item is always version 1.
         item.version_finalize_and_increment(qb, qb.item_mgr.rid_new,
                                             same_version, same_revision)
      else:
         log.warning('commit: skipping non-dirty item? %s' % (item,))

      log.debug('commit: saving item: %s' % (item,))

      # Call save, which only saves the item if it's dirty, and also 
      # saves any related items, like groups accesses.
      log.debug('save_item_to_db: saving item: %s' 
                % (item.__str_abbrev__(),))

      item.save(qb, qb.item_mgr.rid_new)

      # FIXME: Do we call some byway's wire_lval() if this is a link_value?

   #
   def remember_updated_byway_maybe(self, item):
      if isinstance(item, byway.One):
         self.byways_updated.add(item.stack_id)
# FIXME_2013_06_11
# FIXME: What about checking link_geofeature.One?
      elif (isinstance(item, link_value.One)
            and (item.link_rhs_type_id == Item_Type.BYWAY)
            and ((item.link_lhs_type_id == Item_Type.ATTRIBUTE)
                 or (item.link_lhs_type_id == Item_Type.TAG))):
            self.byways_updated.add(item.rhs_stack_id)

   # *** save_all_items: save_split_byways

   #
   def save_split_byways(self):

      self.split_into_done = []

      log.debug('save_split_byways: Processing split-from groups...')

      # Clone the database connection.
      g.assurt(self.qb2 is None)
      self.qb2 = self.qb.clone(skip_clauses=True, skip_filtport=True,
                               db_clone=True)

      # Build the intermediate table.
      self.qb2.load_stack_id_lookup('commit', self.split_from_grps)

      log.debug('save_split_byways: split_from_grps: %s'
                % (self.split_from_grps,))

      self.qb2.filters.include_item_stack = True

      # Process split-from byway groups.
      # NOTE: Cannot use userless_qb because we need to verify that user can
      #       edit these items... though really we want all link_values...
      self.qb2.item_mgr.load_feats_and_attcs(
         self.qb2,
         byway,
         # MAYBE: I don't think this needs to be search_by_network.
         feat_search_fcn='search_for_items',
         processing_fcn=self.process_split_from,
         # 2013.07.16: Fixed 'heavyweight' so it gets the full link_value
         #             record, and the link_value GIA records.
         prog_log=None,
         heavyweight=True,
         fetch_size=0,
         keep_running=None,
         diff_group=None,
         # Load the GIA records for the byway so we can copy these to each
         # split-into.
         load_groups_access=True)

      g.assurt(self.qb2.filters.stack_id_table_ref)
      self.qb2.db.sql("DROP TABLE %s" % (self.qb2.filters.stack_id_table_ref,))

      # See that all split-intos were processed.
      # NOTE: self.split_into_sids will have the same or more IDs than
      # split_into_done, if any split_from_stack_id was not found,
      # so that goes first in the difference (e.g., because 
      # set([]).difference(set([1,])) returns the empty set).
      split_diff = set(self.split_into_sids).difference(
                              set(self.split_into_done))
      if split_diff:
         # This is a client error.
         log.warning('save_split_byways: missing split items: %s' 
                     % (str(split_diff),))
         for split_from_stack_id in split_diff:
            self.qb.grac_mgr.grac_errors_add(split_from_stack_id, 
               Grac_Error.unknown_item,
               '/byway/split_from_stack_id')

      self.qb2.db.close()
      self.qb2 = None

   #
   def process_split_from(self, qb, bway, prog_log):

      # NOTE: Ignoring qb; using self.qb instead.

      # You can't split a deleted byway.
      if bway.deleted:
         log.error('process_split_from: bway already marked deleted: %s'
                   % (str(bway),))
         self.qb.grac_mgr.grac_errors_add(bway.stack_id, 
            Grac_Error.invalid_item,
            '/byway/process_split_from')

      # The user can also send the split-from byway and mark it deleted, for
      # completeness, but we just loaded the byway from the database, so use
      # that one. And we store it in a different collection.
      try:
         del self.deleted_items[bway.stack_id]
         log.debug('process_split_from: removed from deleted_items: %s'
                   % (bway,))
      except KeyError:
         pass

      # Remember the split-from so we can delete it.
      self.split_from_byways.add(bway)
      # Keep prepare_item_ensure_cached from creating its own item,
      # which happens because we process the split-from link_values
      # before processing the split-from byway.
      log.debug('process_split_from: item_cache: %s' % (bway,))
      self.qb.item_mgr.item_cache_add(bway)

      # Maintain a lookup of link_values but what's linked.
      lval_lookup = {}

      # Get the collection of hydrated split-intos.
      split_into_items = self.split_from_grps[bway.stack_id]
      g.assurt(split_into_items)

      # Setup and save the new split-intos items.
      for split_into in split_into_items:

         g.assurt(split_into.stack_id is not None)
         g.assurt(split_into.stack_id < 0)
         client_id = split_into.stack_id

         g.assurt(not split_into.valid)
         suc = self.process_item_hydrated(self.qb, split_into, ref_byway=bway)

         g.assurt(client_id not in self.split_into_done)
         self.split_into_done.append(client_id)

      # Later, we delete the split_from byway (using bway.mark_deleted).

   # *** save_all_items: save_non_split_non_lvals

   #
   def save_non_split_non_lvals(self):

      log.debug('save_non_split_non_lvals: Saving non-split-from non-links.')

      # 2012.08.16: Process threads first. Now I [lb] know why there was 
      # specialty code in CcpV1's PutFeature. But I'd rather not couple this
      # class too much to specific item types (I'm already so-so about how we 
      # handle split byways, but that's a toughy, anyway; where else would that
      # code go?). But here we can use the same trick that CcpV1 did: use a
      # sort order defined by type. But in CcpV2, the sort order value is
      # stored in the item class.
      # 
      # NOTE: The subtraction puts items with a larger item_save_order at the
      #       start of the list, meaning the largest item_save_order goes
      #       first, i.e., threads are processed before posts.

      self.non_link_items.sort(
         lambda x, y: (x.item_save_order - y.item_save_order), reverse=False)

      for item in self.non_link_items:
         g.assurt(not item.valid)
         suc = self.process_item_hydrated(self.qb, item)

   # *** save_all_items: delete_split_froms

   #
   def delete_split_froms(self):

      # Delete the split-from byways. We save a new version of the item first,
      # using process_item_hydrated, because item's mark_deleted just sets the
      # deleted column on existing rows in the database.

      log.debug('delete_split_froms: deleting split-from byways')

      for split_from in self.split_from_byways:
         try:
            processed_item = self.processed_items[split_from.stack_id]
            # If we're here, the user sent the split_from byway, but it wasn't
            # marked deleted (otherwise it would've ended up on deleted_items).
            # So spit out an error, since the client isn't making sense.
            log.error('delete_split_froms: sent from client: %s'
                      % (processed_item,))
            self.qb.grac_mgr.grac_errors_add(split_from.stack_id, 
               Grac_Error.invalid_item, '/byway/split_from')
         except KeyError:
            g.assurt(not split_from.deleted)
            g.assurt(not split_from.valid)
            split_from.mark_deleted(self.qb, self.process_item_hydrated)
            self.processed_items[split_from.stack_id] = split_from

      # FIXME: Make sure import handles split-froms similiarially

   # *** save_all_items: save_link_values

   #
   def save_link_values(self):

      # FIXME: Make sure link_values don't reference deleted byways.

      log.debug('save_link_values: Processing link_values...')

      # Process incoming link_value records. Even though we might have already
      # loaded tag and attribute link_values for byways we've already
      # processed, we'll reload everything fresh here.
      #
      for item in self.link_val_items:

         # This fcn., save_link_values, is called after save_split_byways,
         # which creates link_values for the split-into byways, for which
         # the client might also have sent link_values.

         # Except for Attributes with multiple_allowed set, all Attachments
         # have a 1-to-1-to-1 relationship between themselves, a link_value,
         # and a geofeature. I.e., the same note is only linked once to the
         # same geofeature; same for the same tag, or same post; but for
         # attributes, some attributes -- the 'private' attributes, like item
         # watchers -- can be linked between the same attribute and geofeature,
         # but each link_value is for a specific user, but other attributes,
         # like speed limit, et al, are only linked once to any one geofeature.

         # 2014.09.17: flashclient create-intersection tool sometimes makes
         # points, i.e., byway with two x,ys that devolve to a point because
         # they're within a meter or so of each other.
         if (    (item.lhs_stack_id not in self.reject_item_sids)
             and (item.rhs_stack_id not in self.reject_item_sids)):
            g.assurt(not item.valid)
            suc = self.process_item_hydrated(self.qb, item)
         else:
            self.reject_items_add(item)

   # *** save_all_items: delete_link_values

   #
   def delete_link_values(self):

      for del_lval in self.deleted_lvals.itervalues():

         log.debug('delete_link_values: del_lval: %s' % (del_lval,))

         # The mark_deleted fcn. expects deleted is unset, but from_gml will
         # have set deleted, since that's what the client indicated.
         del_lval.deleted = False
         del_lval.fresh = False

         g.assurt(not del_lval.valid)
         del_lval.mark_deleted(self.qb, self.process_item_hydrated)

   # *** save_all_items: delete_non_lvalues

   #
   def delete_non_lvalues(self):

      for del_item in self.deleted_items.itervalues():

         log.debug('delete_non_lvalues: del_item: %s' % (del_item,))

         # The client sends del_item with deleted indicated but our fcns. don't
         # like it that way, so reset deleted and let the item class be the
         # final decider.
         del_item.deleted = False
         del_item.fresh = False

         g.assurt(not del_item.valid)
         del_item.mark_deleted(self.qb, self.process_item_hydrated)

   # *** save_all_items: process_accesses

   #
   # 2012.05.27: We need to test this fcn.
   # 2013.04.18: [lb] notes that longform GIA accesses ('permissive' access
   #             style) only applies to branches, and flashclient does not
   #             currently support permissive style changes. So this fcn. may
   #             work, but the only way to test is via ccp.py.
   def process_accesses(self):

      log.debug('process_accesses')

      for stack_id, accesses_elem in self.accesses_items.iteritems():

         # [lb] thinks only changes branch permissions for users (e.g.,
         # adding arbiters) would trigger this. Or maybe this code isn't
         # ever executed?
         log.warning('EXPLAIN: process_accesses: who calls us?')

         log.verbose('process_accesses: stack_id: %d' % (stack_id,))

         # Get the item, making sure the user can at least see the item.
         # When we call the item class to load the GML, it'll check for
         # proper permissions (i.e., user's generally have to be owners of
         # an item to be able to change its default permissions).

         try:
            item = self.item_load_for_groups_access_update(stack_id)
         except GWIS_Error, e:
            self.qb.grac_mgr.grac_errors_add(stack_id, 
               Grac_Error.unknown_item,
               '/commit/process_accesses')
            # Haha, this is just as bad a short-circuit return or a GOTO:
            continue

         if item is not None:
            if item.valid:
               # Look for state change GIA, not complete record.
               style_change = accesses_elem.get('ascx', None)
               if style_change:
                  g.assurt(False) # The client never sends 'ascx'.
                  item.style_change = style_change
                  item.groups_access_style_change(qb)
               else:
                  # This fcn. adds an error if the user doesn't have 
                  # arbit/owner access or if they're setting permissions 
                  # greater than their own, or if the item access_style is 
                  # not permissive.
                  item.groups_access_load_from_gml(self.qb, accesses_elem)
               # Increment the item's acl_grouping, since we want to save new
               # records.
               # NOTE: We don't care whether self.needs_new_revision, since
               #       items that are not being edited but have their
               #       permissions changed do not need a new item version.
               if item.valid:
                  g.assurt(item.dirty
                           & (item_base.One.dirty_reason_grac_user
                              | item_base.One.dirty_reason_grac_auto))
                  g.assurt(not (item.dirty
                                & (item_base.One.dirty_reason_item_auto
                                   | item_base.One.dirty_reason_item_user)))
                  item.version_finalize_and_increment(
                     self.qb, self.qb.item_mgr.rid_new, same_version=True)
               else:
                  # This means there was an error in groups_access_style_change
                  # and we've added a grac_error. Remove the item from the
                  # commit list and keep processing (and potentially adding
                  # more errors) until we return all the errors to the client.
                  del self.commit_accesses[item.stack_id]
            else:
               pass # not valid; We already added a grac_error for this item.
         else:
            pass # is None; We already added a grac_error for this item.

      self.save_perms_to_db()

   #
   def process_schanges(self):

      log.debug('process_schanges')

      # We call process_item_hydrated, which modifies self.schanges_items,
      # so we can't use iteritems. But keys() makes a copy of the keys, which
      # is okay.
      # Instead of:
      #   for stack_id, style_change in self.schanges_items.iteritems():
      # use keys():
      stack_ids = [x for x in self.schanges_items.keys()
                      if x not in self.reject_item_sids]

      for stack_id in stack_ids:

         style_change = self.schanges_items[stack_id]
         log.verbose('process_schanges: stack_id: %d / style_change: %d'
                     % (stack_id, style_change,))

         permanent_id = 0
         try:
            permanent_id = self.qb.item_mgr.stack_id_translate(
                              self.qb, stack_id, must_exist=True)
            g.assurt(permanent_id > 0)
         except GWIS_Error, e:
            # The client can send client_ids, but only when also sending the
            # item, which is processed by process_item_hydrated. So this is
            # a client error.
            log.error('process_schanges: no permanent id: %d' % (stack_id,))
            self.qb.grac_mgr.grac_errors_add(stack_id,
               Grac_Error.unknown_item, '/commit/process_schanges/1')

         item = None
         if permanent_id > 0:

            try:
               item = self.processed_items[permanent_id]
               del self.processed_items[permanent_id]
            except KeyError:
               item = self.qb.grac_mgr.prepare_existing_from_stack_id(
                  self.qb, permanent_id)

            # MAYBE: For items whose groups_access the user is not changing,
            # [lb] thinks we might be doing extra work here. E.g., when
            # splitting a parent byway into a child branch, each new item
            # has its groups_access set and saved, but then I think maybe
            # the code comes through here and we set and save groups_access
            # again. It's probably not a big deal, so long as whatever's
            # finally saved to the database looks good. The only real problem
            # would be if the SELECT statement below makes commit take even
            # longer, and we could make it quicker by fixing this issue.
            #  MAYBE: if style_change is the same as access_infer_id,
            #         we can short-circuit return right here?

            if item is None:
               log.error('process_schanges: not found: %d' % (permanent_id,))
               self.qb.grac_mgr.grac_errors_add(
                  permanent_id,
                  Grac_Error.unknown_item,
                  '/commit/process_schanges/2')
            else:
               # Don't worry about qb.item_mgr.start_new_revision.
               # It gets called by save_get_revision.

               # prepare_existing_from_stack_id figures out the item's
               # item_type_id and makes a real item (we'll double check
               # here anyway) but really we want to support link_values
               # (though flashclient doesn't send schanges for links).
               # So this is probably a no-op.
               (itype_id, lhs_type_id, rhs_type_id,
                  ) = Item_Manager.item_type_from_stack_id(self.qb,
                                                           item.stack_id)
               g.assurt(itype_id is not None)
               g.assurt(item.item_type_id == itype_id)
               if lhs_type_id:
                  item.link_lhs_type_id = lhs_type_id
               if rhs_type_id:
                  item.link_rhs_type_id = rhs_type_id

         if item is not None:
            log.debug('process_schanges: processing item: %s' % (str(item),))
            g.assurt(item.valid) # The only caller with a valid item.
            suc = self.process_item_hydrated(self.qb, item, ref_byway=None)

   #
   def save_perms_to_db(self):

      for item in self.commit_accesses.itervalues():
         if item.valid and item.is_dirty():
            item.save(self.qb, self.qb.item_mgr.rid_new)
            # Remember which groups need a group revision for the update.
            # 2013.03.28: No: self.rev_groups.add(self.qb.user_group_id)
            item.group_ids_add_to(self.rev_groups, self.qb.item_mgr.rid_new)
         else:
            # This should be a programmer error.
            log.error('save_perms_to_db: not valid or dirty: %s'
                      % (str(item),))

   #
   def item_load_for_groups_access_update(self, stack_id):

      # NOTE: This raises GWIS_Error if client ID unresolveable.
      permanent_id = self.qb.item_mgr.stack_id_translate(
                        self.qb, stack_id, must_exist=True)
      log.debug('_load_for_groups_access_update: stack_id: %d / perm. ID: %d' 
                % (stack_id, permanent_id,))
      g.assurt(permanent_id > 0)

      item = None
      try:
         item = self.processed_items[permanent_id]
         # 2012.07.24: We look for accesses when saving items, so we should
         # have processed this groups_access by now.
         g.assurt(False)
      except KeyError:
         # NOTE: We're calling grac_mgr, instead of just using Many() (e.g., by
         # calling get_existing_item), because we want the grac_mgr to load
         # item.groups_access, since we eventually want to save this item's
         # groups_access.
         # MAYBE: Bulk-load. See comments elsewhere. Can we bulk-load items and
         # groups_access? (2013.07.18: Yes, you can, using heavyweight.)
         grac_mgr = self.qb.grac_mgr
         item = grac_mgr.prepare_existing_from_stack_id(self.qb, permanent_id)

      if item is not None:
         # The item is valid because it's prepped to be saved.
         g.assurt(item.valid)
         # But the item is not dirty because we haven't finalized it yet, which
         # would bump its version number.
         g.assurt(item.dirty == item_base.One.dirty_reason_none)
         # Don't put on the processed_items list because we don't need to save
         # a new version of the item if the user is not editing the item.
         self.commit_accesses[permanent_id] = item
         log.debug('  >> found: %s' % (item,))
         if not item.valid:
            # EXPLAIN: Why would this happen?
            g.assurt(False)
            log.warning('_load_for_groups_access_update: invalid: %s' 
                        % (str(item),))
            self.qb.grac_mgr.grac_errors_add(stack_id,
               Grac_Error.invalid_item, '/group_access/update')
         # NOTE: We'll check that the user is arbiter or owner later.
      else:
         log.debug('_load_for_groups_access_update: no item: %d' % (stack_id,))
         self.qb.grac_mgr.grac_errors_add(stack_id,
            Grac_Error.unknown_item, '/group_access/update')

      return item

   # *** Helpers -- save() -- save_new_revision

   #
   def save_new_revision(self):

      # This is similar to script_base.finish_script_save_revision.

      # Save the new revision.
      if self.needs_new_revision:
         g.assurt(self.qb.username == self.req.client.username)
         host = self.req.client.remote_host_or_remote_ip()
         activate_alerts = self.req.doc_in.get('alert_on_activity', False)
         Item_Manager.revision_save(self.qb,
                                    self.qb.item_mgr.rid_new,
                                    self.qb.branch_hier,
                                    host,
                                    self.qb.username,
                                    self.changenote,
                                    self.rev_groups,
                                    activate_alerts,
                                    self.processed_items,
                                    reverted_revs=None,
                                    skip_geometry_calc=False)
         # Finally claim the revision ID, for real, now that we're sure the
         # commit is going to succeed.
         revision.Revision.revision_claim(self.qb.db, self.qb.item_mgr.rid_new)

      # Even if we didn't use a new revision, we may have generated new stack
      # and system IDs, so commit the new sequence value now.
      #
      # 2013.09.17: It should always be safe to call this fcn., and [lb]
      # worries about accidentally not calling it (though we'd probably
      # start getting duplicate key errors... hopefully).
      #  if self.all_items_cnt or len(self.accesses_items):
      #     self.qb.item_mgr.finalize_seq_vals(self.qb.db)
      self.qb.item_mgr.finalize_seq_vals(self.qb.db)

   # *** save: clean_orphans

   #
   def clean_orphans(self):

#
      log.info('clean_orphans: FIXME: Not implemented')

      # Bug nnnn: Orphaned link_values, and those with a 0 lhs_ or rhs_stack_id
      #
      # [lb] notes that orphan link_values should not cause any issues for
      # users, so, maybe sometimes we can search for search link_values and
      # see if it's worth our time to clean them up.

# BUG nnnn: link_values to 0.
# This search reveals lhs_stack_id of 0:
#     select * from link_value where stack_id = 1518270;
# 20111006 Above comment is still valid.
# 2013.10.09: This is a waypoint for 'The Nook'.
# So maybe adding looking for linked stack ids of 0...
# select * from link_value where lhs_stack_id = 0; -- Just 3 rows... so far

# ccpv1_live=> select * from point where id = 1365270;
#    id    | version | deleted |   name   | type_code | valid_starting_rid | valid_before_rid |                      geometry                      |       comments       |  z  
# ---------+---------+---------+----------+-----------+--------------------+------------------+----------------------------------------------------+----------------------+-----
#  1365270 |       1 | f       | The_Nook |         2 |               3540 |             3600 | 01010000202369000000000000C8C31D41000000802DFA5241 |                      | 140
#  1365270 |       2 | f       | The Nook |         2 |               3600 |             3648 | 01010000202369000000000000C8C31D41000000802DFA5241 | Best burgers around. | 140
#  1365270 |       3 | f       | The Nook |         2 |               3648 |       2000000000 | 010100002023690000000000004EC31D410000004035FA5241 | Best burgers around. | 140

# ccpv1_live=> select * from tag_point where point_id = 1365270;
#    id    | version | deleted | tag_id  | point_id | valid_starting_rid | valid_before_rid 
# ---------+---------+---------+---------+----------+--------------------+------------------
#  1518223 |       1 | f       | 1518211 |  1365270 |              13749 |       2000000000

# ccpv1_live=> select * from tag where id = 1518211;
#    id    | version | deleted |   label   | valid_starting_rid | valid_before_rid 
# ---------+---------+---------+-----------+--------------------+------------------
#  1518211 |       1 | f       | destroyed |              13749 |       2000000000

# ccpv3_demo=> select stack_id, lhs_stack_id, rhs_stack_id from link_value where rhs_stack_id = 1365270;
#  stack_id | lhs_stack_id | rhs_stack_id 
# ----------+--------------+--------------
#   1518223 |      1518211 |      1365270 -- destroyed tag
#   1518226 |      1518225 |      1365270 -- a post
#   1518270 |            0 |      1365270 -- FIXME: Who cares? Just mark all versions of these deleted? (And make sure reverted ignores.)
#   2499520 |      2499519 |      1365270 -- the comments

# select * from item_versioned where stack_id = 1518270;
#  stack_id | version | deleted | reverted | name | valid_start_rid | valid_until_rid | system_id | branch_id | tsvect_name 
# ----------+---------+---------+----------+------+-----------------+-----------------+-----------+-----------+-------------
#   1518270 |       1 | f       | f        |      |           13751 |      2000000000 |    402864 |   2500677 | 

# Yup, this is a CcpV1 bug:
#
#  ccpv1_live=> select * from post_point where point_id = 1365270;
#    id    | version | deleted | post_id | point_id | valid_starting_rid | valid_before_rid 
# ---------+---------+---------+---------+----------+--------------------+------------------
#  1518226 |       1 | f       | 1518225 |  1365270 |              13750 |       2000000000
#  1518270 |       1 | f       |       0 |  1365270 |              13751 |       2000000000

# ccpv3_demo=> select * from _rev where id = 13751;
#   id   |       timestamp        |     host      |     user      |            comment             | bbox_perim | gsum_perim | geom_perim |  br_id  | rvtok | rvtct | lcktm 
# -------+------------------------+---------------+---------------+--------------------------------+------------+------------+------------+---------+-------+-------+-------
#  13751 | 2010-12-15 21:07:14-06 | 75.72.227.203 | tobymarkowitz | better cp by spring assignment | 7929.9     | 8396.9     | 7927.8     | 2500677 | t     |     0 |      

# So... yeah...

      # BUG nnnn: Re-implement the CcpV1 check-orphan code.
      #           But test it first, or search the database and find
      #           evidence that it's happening, i.e., rather than just
      #           integrating this code -- which is implemented but is
      #           not tested -- wait to figure out how to recreate the
      #           orphan scenario and then enable and test this feature.
      #           [lb] is pretty sure that orphaned records won't haunt us.
      return # FIXME: BUG nnnn

      # After updating existing items and saving new items to the database,
      # check for orphan items, i.e., those items the client sent that really
      # don't make sense being saved. For example, if the user creates a new
      # geofeature, annotates it, then deletes the geofeature, the commit
      # operation might save the annotation (and the link_value), but since
      # it's not linked to anything, we really shouldn't save it. (I [lb]
      # would rather we check before saving, but this approach seems simpler
      # to implement -- we only have to run one SQL query, whereas if we
      # checked before saving, we'd have to check the database and also walk
      # self.processed_items.)
      # For attcs and feats being marked deleted, mark their links deleted
      self.clean_orphans_by_type(link_value)
      # Also cleanup any attachments now abandoned because all their
      # geofeatures are marked deleted. This applies to annotations, but not
      # to tagsor attributes.
      # FIXME Cleanup post/threads no longer attached to un-deleted feats?
      self.clean_orphans_by_type(annotation)
      # NOTE: We don't clean up tag orphans, since tags can exist without being
      #       linked to anything. Likewise, we don't clean up attributes, or 
      #       any geofeature.
      # FIXME: If we ever allow deleting threads or posts:
      #self.clean_orphans_by_type(post)
      #self.clean_orphans_by_type(thread)

   #
   def clean_orphans_by_type(self, item_module):
      log.debug('clean_orphans_by_type: len(self.processed_items): %s' 
                % (len(self.processed_items),))
      many = item_module.Many()
      # NOTE: This takes a while (it finds a lot of orphans) the first time
      # you save in an anonymized database. Are the anonymizer scripts missing
      # something?
      log.debug('clean_orphans_by_type: begin: searching for orphans')
      many.search_for_orphan_query(self.qb)
      log.debug('clean_orphans_by_type: done: searching for orphans')
      for item in many:
         log.debug('clean_orphans_by_type: item: %s' % (item,))
         try:
            item_from_user = self.processed_items[item.stack_id]
            # FIXME: Does this just mark the orphan deleted but leave it in the
            #        database?
            g.assurt(item_from_user.branch_id == self.qb.branch_hier[0][0])
            g.assurt(not item_from_user.valid)
            item_from_user.mark_deleted(self.qb, self.process_item_hydrated)
            # BUG nnnn: Do we double-check that the client marks split-from 
            #           byways as deleted?
         except KeyError:
            # Use prepare_existing, which calls many.search_by_stack_id(), and
            # then grac_mgr.prepare_existing().
            item_from_db = self.qb.grac_mgr.prepare_existing_from_stack_id(
                                                      self.qb, item.stack_id)
            # The user did not send us this item... so where did it come from?
            log.warning('EXPLAIN: deleting orphan not sent from client: %s'
                        % (item_from_db,))
            # We deleted something which left something else orphaned, so bump 
            # the existing thing's version and mark it deleted.
            item_from_db.version_finalize_and_increment(self.qb, 
                                       self.qb.item_mgr.rid_new)
            # FIXME: What about calling mark_deleted? That's what updates the
            # tables...
            #?: item_from_db.mark_deleted(self.qb, self.process_item_hydrated)
            item_from_db.deleted = True
            item_from_db.save(self.qb, self.qb.item_mgr.rid_new)

   # *** save: save_non_items

   #
   def save_non_items(self):

      log.debug('save_non_items: saving data objects (non-items)')

      # BUG nnnn: Timeline for non-revision commits. I.e., you rated some
      # blocks at 12:23, etc. See date_created in group_revision table.
      # So, here, make a changenote for the group_revision.

      if not self.qb.request_is_a_test:
         self.qb.db.transaction_begin_rw()
      # else, we didn't just commit the last transaction.

      self.process_ratings()

      # MEH: [lb] long ago thought about making item_readers another part of
      #      commit -- instead of a separate item_read_event_put command and
      #      item_read_event table, clients would just call commit and we'd
      #      make link_values for the read event. But link_values are costly,
      #      both in terms of data storage and in terms of code overhead
      #      (link_value code tends to be more complicated to maintain and
      #      tends to take longer to run). So using a dedicated table and a
      #      dedicated command seems to make more sense than making another
      #      link_value-attribute. (Which isn't to say that I don't like
      #      /item/alert_email, because I do: I just think that private
      #      link-attrs that users can edit are different enough from
      #      automatic events that we record on the user's behalf. So maybe
      #      that's the way to determine if a piece of data should be a
      #      link_value or its own entity: if it's editable, it's a link_value,
      #      but if it's just an automatically recorded piece of data, it
      #      should be stored elsewhere and not treated as a link_value.)

      # NOTE: Item watchers are saved specially, as revision-free
      #       private link_values.
      #
      # BUG nnnn: For Statewide, [lb] and [mm] talked about an in-client
      #           notification system. E.g., instead of always emailing users
      #           about stuff, we can alert them in the app. [lb] got as far
      #           as making the item_event_alert table, which we use to manage
      #           sending user emails, but there's no in-app notification yet.
      #           See also: the other item_event_* tables, and also the
      #                     /item/alert_email attribute

   # *** decode_request: Nonwiki hydrate_* helpers

   #
   def commit_list_verify_add_op_viewer(self, commit_list, item_stack_id, 
                                              item_prop_list, commit_op,
                                              only_item_type=None):
      # We're only verifying the user's access to the item, i.e., to set
      # ratings or watchers, which happens after items may have been edited. So
      # this item may exist as a to-be-committed item, or we might have to look
      # ip up.
      try:
         # See if the user edited the item.
         item = self.processed_items[item_stack_id]
      except KeyError:
         try:
            # See if the user changed the item's permissions.
            item = self.commit_accesses[item_stack_id]
         except KeyError:
            item = None
      if item is not None:
         # The referenced item is also being edited by the user.
         g.assurt(item is not None)
         g.assurt(item.can_edit())
         g.assurt(item.valid)
      else:
         item = self.get_existing_item(item_stack_id, only_item_type,
                                       view_only_ok=True)
         # The get_existing_item fcn. adds a grac error if user cannot view or
         # know about the item. E.g.,
         #  grac_errors_add(item_stack_id, Grac_Error.permission_denied...)
      if item is not None:
         g.assurt(item.can_view)
         item_prop_list.insert(0, item)
         commit_list.append(item_prop_list)
      return item

   # *** Helpers for save_non_items()

   #
   def process_ratings(self):

      log.debug('process_ratings')

      ratings = {}

      for client_id, byway_rat in self.ratings_byways.iteritems():
         try:
            permanent_id = self.qb.item_mgr.stack_id_translate(
                              self.qb, client_id, must_exist=True)
            g.assurt(permanent_id > 0)
            ratings[permanent_id] = byway_rat
         except GWIS_Error, e:
            # 2013.10.17: If we've already saved the commit, don't record
            # errors, otherwise the client won't think the save worked.
            # BUG nnnn: Send back errors collected after a successful commit?
            #   self.qb.grac_mgr.grac_errors_add(client_id,
            #      Grac_Error.unknown_item,
            #      '/commit/process_ratings')
            # This is hopefully a DEV problem: Either the client has a bug or
            # someone is hacking the URL.
            log.error('process_ratings: Unexpected: Bad Stack Id: %d'
                      % (client_id,))

      self.ratings_byways = ratings

      if self.ratings_byways:

         # Clone the database connection.

         g.assurt(self.qb2 is None)
         self.qb2 = self.qb.clone(skip_clauses=True, skip_filtport=True,
                                  db_clone=True)
         # Build the intermediate table.
         self.qb2.load_stack_id_lookup('ratings', self.ratings_byways)
         #
         # FIXME: heavyweight=None to say skip all links (attrs and tags)?
         #        For now, the bulk processing here wastes a little extra 
         #        time getting attrs and tags.
         #
         # MAYBE: We reload all byways, even byways the user may have otherwise
         #        edited that might be in the cache.
         #
         self.qb2.item_mgr.load_feats_and_attcs(
            self.qb2,
            byway,
            feat_search_fcn='search_for_items',
            processing_fcn=self.process_byway_rating,
            prog_log=None,
            heavyweight=False,
            fetch_size=0,
            keep_running=None,
            diff_group=None,
            load_groups_access=False)

         g.assurt(self.qb2.filters.stack_id_table_ref)
         self.qb2.db.sql(
            "DROP TABLE %s" % (self.qb2.filters.stack_id_table_ref,))

         self.qb2.db.close()
         self.qb2 = None

      # For any byway that was edited or had a link_value edited, recalculate
      # its rating.
      self.save_commit_ratings()

   #
   def process_byway_rating(self, qb, bway, prog_log):

      g.assurt(bway.can_view())

      rating = self.ratings_byways[bway.stack_id]

      self.rating_inserts.append("('%s', %d, %d, %d)"
                                 % (qb.username,
                                    qb.branch_hier[0][0],
                                    bway.stack_id,
                                    rating,))

      #self.rating_updates.append("(%d, %d)" % (bway.stack_id, rating,))

      # Remember this byway so we can recalculate its generic rating
      self.byways_updated.add(bway.stack_id)

   #
   def save_commit_ratings(self):

      # Save ratings
      # MAYBE: Save ratings like item_watchers are saved:
      #        as revisionless attributes. Make a new attribute
      #        and a new_item_policy, etc. emulate: /item/alert_email

      if self.rating_inserts:
         #g.assurt(self.rating_updates)
         # Historic ratings table (ratings log / count_ratings.dat).
         self.rating_events_insert()
         # Current ratings table.
         #self.ratings_bulk_update()
         self.byway_ratings_insert()

      if self.byways_updated:
         self.byway_ratings_update()

   #
   def byway_ratings_update(self):

      # Remember the byways that get edited; we need to recalculate their
      # generic rating. Edits that affect the rating calculation are:
      # the byways's type, i.e., bike trail or road, etc.; the attributes of
      # the byway, like shoulder width; and the tags applied to the byway.
      # FIXME: For now, we fudge and add any byways that get edited, and any
      #        byways that have an attribute or tag updated. Ideally, we 
      #        should only update the ratings for a byway if one of the 
      #        aforementioned values changes. For now, it's easiest to always
      #        do it.

      userless_qb = None

      try:

         # Clone the database connection.
         username = ''
         userless_qb = Item_Query_Builder(self.qb.db.clone(),
                                          username,
                                          self.qb.branch_hier,
                                          self.qb.revision)
         userless_qb.request_is_local = True
         userless_qb.request_is_script = True
         userless_qb.filters.gia_userless = True
         g.assurt(not userless_qb.revision.allow_deleted)
         userless_qb.grac_mgr = self.qb.grac_mgr
         userless_qb.item_mgr = self.qb.item_mgr
         #
         # Build the intermediate table.
         userless_qb.load_stack_id_lookup('gen_rats', self.byways_updated)

         # NO?: Query_Overlord.finalize_query(userless_qb)

         # FIXME: Make sure this loads all byways and all links without
         # checking for permissions, since this is a user-agnostic (userless?)
         # operation.
         userless_qb.item_mgr.load_feats_and_attcs(userless_qb, byway,
            feat_search_fcn='search_for_items',
            processing_fcn=self.process_generic_rating,
            prog_log=None, heavyweight=False, fetch_size=0,
            keep_running=None, diff_group=None,
            load_groups_access=False)

         g.assurt(userless_qb.filters.stack_id_table_ref)
         userless_qb.db.sql(
            "DROP TABLE %s" % (userless_qb.filters.stack_id_table_ref,))

      finally:

         if userless_qb is not None:
            userless_qb.db.close()
            userless_qb = None

   #
   def process_generic_rating(self, qb, bway, prog_log):

      log.debug('process_generic_rating: bway: %s' % (bway,))
      bway.refresh_generic_rating(self.qb)

   #
   def rating_events_insert(self):
      insert_sql = (
         """
         INSERT INTO byway_rating_event
            (username,
             branch_id,
             byway_stack_id,
             value)
         VALUES
            %s
         """ % (','.join(self.rating_inserts),))
      rows = self.qb.db.sql(insert_sql)
      g.assurt(rows is None)

   #
   def ratings_bulk_update(self):
      g.assurt(False) # This is wrong. We need to insert if ratings don't
                      # exist, so we should delete/insert instead.
      g.assurt(self.rating_updates)
      # Format is, e.g.,
      #    UPDATE 
      #       tbl_1 
      #    SET 
      #       col1 = t.col1 
      #    FROM (
      #       VALUES
      # 	        (25, 3)
      # 	        (26, 5)
      #       ) AS t(id, col1)
      #    WHERE tbl_1.id = t.id;
      update_sql = (
         """
         UPDATE
            byway_rating AS brat
         SET
            value = foo.value
         FROM 
            (VALUES %s) AS foo(byway_stack_id, value)
         WHERE
                brat.username = '%s'
            AND brat.branch_id = %d
            AND brat.byway_stack_id = foo.byway_stack_id
         """ % (','.join(self.rating_updates),
                self.qb.username,
                self.qb.branch_hier[0][0],
                ))
      rows = self.qb.db.sql(update_sql)
      g.assurt(rows is None)

   #
   def byway_ratings_insert(self):

      g.assurt(self.ratings_byways)
      delete_sql = (
         """
         DELETE FROM byway_rating
         WHERE
                username = '%s'
            AND branch_id = %d
            AND byway_stack_id IN (%s)
         """ % (self.qb.username,
                self.qb.branch_hier[0][0],
                ','.join([str(x) for x in self.ratings_byways.keys()]),))
# FIXME: The insert is failing on dupl key error, so what is not being deleted?
      log.debug('byway_ratings_insert: delete_sql: %s' % (delete_sql,))
      rows = self.qb.db.sql(delete_sql)
      g.assurt(rows is None)

      g.assurt(self.rating_inserts)
      insert_sql = (
         """
         INSERT INTO byway_rating
            (username,
             branch_id,
             byway_stack_id,
             value)
         VALUES
            %s
         """ % (','.join(self.rating_inserts),))
# FIXME: This fails via mobile on dupl key error.
      log.debug('byway_ratings_insert: insert_sql: %s' % (insert_sql,))
      rows = self.qb.db.sql(insert_sql)
      g.assurt(rows is None)

   # *** Helpers -- Miscellaneous

   # C.f. import_base.get_source_byway
   def get_existing_item(self, stack_id, only_item_type=None, 
                               view_only_ok=False):
      try:
         item = self.aux_item_cache[stack_id]
      except KeyError:
         try:
            # NOTE: If the old byway has since been deleted, this fcn. won't
            # find it. But commit is only called to save the next revision
            # following the latest revision, unlike the import code, whose
            # items need to be checked out from a historic revision.
            # PERFORMANCE: It's slow to get items one-by-one. But commit
            # operations from flashclient are generally not that large, so 
            # it's not worth our time to recode to do a bulk load of items.
            if only_item_type is None:
               only_item_type = item_user_access.Many
            # FIXME: This is not named well: ccp_get_gf might be called for
            #        non-gf? I.e., for watchers? Or do we only set watchers on
            #        gfs?
            item = Grac_Manager.ccp_get_gf(only_item_type(), stack_id, self.qb)
            self.aux_item_cache[stack_id] = item
         except Exception, e:
            item = None
            log.debug('get_existing_item: not found: stack id: %d / %s' 
                      % (stack_id, str(e),))
            self.qb.grac_mgr.grac_errors_add(stack_id,
               Grac_Error.unknown_item,
               '/byway/get_existing')
      if item is not None:
         # For split-from byways, the user needs editor access, since we're
         # modifying the split-from byway. For ratings and watchers, user just
         # needs viewer access.
         permitted = ((view_only_ok and item.can_view())
                      or (item.can_edit()))
         if not permitted:
            log.debug('get_existing_item: permission denied: %s' 
                      % (str(item),))
            self.qb.grac_mgr.grac_errors_add(stack_id, 
               Grac_Error.permission_denied,
               '/byway/get_existing')
      return item

   # *** fetch_n_save: process_cleanup_check_semiprotect

   #
   def process_cleanup_check_semiprotect(self):
      semiprotect_wait = (self.semiprotect_wait() != 0)
      user_is_banned = self.user_client_ban.is_banned()
      if semiprotect_wait or user_is_banned:
         # MAYBE: 2012.07.20. Semi-protected and banned isn't used, is it?
         # MAYBE: Just a word to the wise... this code is untested.
         log.warning(
            '_cleanup_check_semiprotect: this is code is not tested well.')
         # If the user or site is being semi-protected, the user can only save
         # private items, and also ratings and watchers; but not public or
         # shared items.
         for gaited_items in (self.processed_items, self.commit_accesses,):
            committable = dict()
            for item in gaited_items.itervalues():
               scope = item.get_access_infer(self.qb)
               if not (scope & ~Access_Infer.usr_mask):
                  committable[item.stack_id] = item
               else:
                  # FIXME: The client can handle two errors on same item, 
                  #        right?
                  if semiprotect_wait:
                     self.qb.grac_mgr.grac_errors_add(item.stack_id, 
                        Grac_Error.semi_protected, '/item/update')
                  if user_is_banned:
                     self.qb.grac_mgr.grac_errors_add(item.stack_id, 
                        Grac_Error.user_is_banned, '/item/update')
#            gaited_items = committable
      # FIXME: These errors should be moved to flashclient
      #        raise GWIS_Warning("Cyclopath is in semi-protected mode, and your save contains public changes.\n\nCurrently, anonymous users and accounts younger than %d hours cannot save public changes. You can still experiment with the editing tools, but you won't be able to save.\n\nAll logged-in users can still save private changes such as ratings." % (wait))
      #        raise GWIS_Warning("Can't save public changes while banned")

   # ***

   #
   # Bug nnnn: Bugfix workaround: Flashclient create-intersection tool makes
   #           tiny byway segments. E.g., consider an East-West road that's
   #           split in the middle, so it's two byway segments, and consider
   #           a North-South road that's one line segment that crosses over
   #           the East-West at the split, above the node endpoint. The create
   #           intersection tool will split the N-S segment into two at the
   #           endpoint, but it sometimes also splits one of the E-W segments
   #           and makes a tiny byway who's two endpoint are within one meter
   #           of one another and are considered the same, i.e., the byway
   #           devolves to a point.
   def reject_items_add(self, item):
      self.reject_items.append(item)
      self.reject_item_sids.add(item.stack_id)
      try:
         del self.schanges_items[item.stack_id]
      except KeyError:
         pass
      try:
         self.commit_item_stack_ids.remove(item.stack_id)
      except KeyError:
         pass

   # *** Error handlers

   #
   def gwis_error_append_errs(self, ge):
      for client_id_errs in self.qb.grac_mgr.grac_errors.itervalues():
         for gerr in client_id_errs.itervalues():
            log.warning('  >> Error: %s' % (str(gerr),))
            ge.gerrs.append(gerr)

   # ***

# ***

# fixme: is nip_choice implemented?
#      
# here: process attcs and feats and save them, so that split-intos are setup
# correctly. for GIA, check access_style... for "permissive", user can specify
# any records but not their own. for "usr_choice", user can specify themself as
# editor
# or the public. for the other styles, user should not specify anything.
# maybe for "usr_choice" we can embed the desired permissions in the item XML?
# nip_choice="usr_editor" or nip_choice="pub_editor"?
# for "permissive", process accesses after processing items, save items, then 
# you can process link_values -- and the lhs and rhs items should all exist.
# note that access records should not be specified for any type except
# "permissive". note also that the item classes do not care, do they? it is
# up to commit or import scripts to enforce these rules (or maybe grac_mgr...
# except import script does not use grac_mgr quite like commit does).

# ***

