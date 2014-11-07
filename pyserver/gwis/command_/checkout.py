# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from item import link_value
from item import item_versioned
from item.util import item_factory
from item.util import revision
from util_ import misc

log = g.log.getLogger('cmd.checkout')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      # Values (possibly) in the GML request (else we'll set):
      'item_type',      # Item class name
      #'item_layer',    # Deprecated
      'item_attc_type', # Item attachment class name, if type is link_value
      'item_feat_type', # Item geofeature class name, if type is link_value
      # Internal class values:
      'items_fetched',  # List of items fetched from database
      )

   # Depending on the item type, we may or may not require the client to
   # confine their request, lest we end up fetching hundreds or thousands of
   # records.
   # FIXME: For item types that do not require a constraint, if the number of 
   # items of any of these types grows, you'll want to consider enforcing 
   # pagination.
   # NOTE: 'cons' means constraint.
   cons_none = 0x0000
   cons_bbox = 0x0001
   cons_sids = 0x0002 # FIXME: This should always make request pass.
                      # in fact, you could rank requests:
                      #   none, bbox, sids, page, solo
                      # so if you check solo and it passes, ok, 
                      # if you then check page, sids, bbox, etc., until the
                      #   policy hits, you know if it passes easily
   cons_page = 0x0004
   cons_solo = 0x0008
   cons_bbx2 = 0x0010

   # SYNC_ME: Search: Item_Type table.
   constraint_policy = {
      # attachment
      'geofeature' : cons_sids,
      'link_value' : cons_sids,
      'annotation' : cons_bbox | cons_sids, # FIXME: Should be cons_sids?
      'attribute' : cons_none, # FIXME: Should be 'page'?
      'branch' : cons_none, # FIXME: Make this 'page'.
      'byway' : cons_bbox | cons_sids,
      'post' : cons_page | cons_sids,
      'region' : cons_none, # FIXME: Watch this item type....
      # FIXME: [lb] is not sure about cons_bbx2. Flashclient gets routes when
      #        the user is in Historic mode and the user pans the map...
      #        We could get routes at all zoom levels, but this seems costly...
      #        but leaving in for now, so we can explore the feature better.
      'route' : cons_page | cons_sids | cons_bbox | cons_bbx2,
      'tag' : cons_none, # 
      'terrain' : cons_bbox | cons_sids,
      'thread' : cons_page | cons_sids,
      'waypoint' : cons_bbox | cons_sids,
      # workhint
      # 'group_membership' : cons_none,
      # 'new_item_policy' : cons_none,
      # group
      # route_step
      # group_revision
      'track' : cons_page | cons_sids | cons_bbox | cons_bbx2,
      # track_point
      # addy_coordinate
      # addy_geocode
      # item_name
      # grac_error
      'work_item' : cons_page,
      # nonwiki_item
      'merge_job' : cons_page,
      'route_analysis_job' : cons_page,
      # job_base
      # work_item_step
      'merge_job_download' : cons_solo,
      # group_item_access
      ## DEPRECATED: item_watcher (replaced by private link_attributes)
      ## 'item_event_alert' : cons_none,
      ## 'item_watcher_change' : cons_none,
      # 'item_event_alert' : cons_none,
      ## DEPRECATED: byway_node (replaced by node_endpoint).
      ##  byway_node
      ## DEPRECATED: route_waypoint (renamed to route_stop).
      ##  route_waypoint
      'route_analysis_job_download' : cons_solo,
      # hmmm... 'branch_conflict' : cons_solo,
      'merge_export_job' : cons_page,
      'merge_import_job' : cons_page,
      # node_endpoint
      # node_byway
      # node_traverse
      # route_stop
      # item_stack
      # item_versioned
      # To get access_style_id or stealth_secret:
      'item_user_access' : cons_sids,
      # item_user_watching
      # link_geofeature
      'conflation_job' : cons_solo,
      # link_post
      # link_attribute
      # landmark
      # landmark_t
      # landmark_other
      # item_revisionless
      }

   # FIXME: For now, region link_values can be fetched altogether.
   #        For Statewide, this will not stand, [lb] don't think.
   constraint_links = {
      'tag' : (cons_bbox | cons_sids, { 
         'region' : cons_none,
         },),
      'annotation' : (cons_bbox | cons_sids, { 
         #'region' : cons_none,
         },),
      }

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      # Tell the ancestor classes to look for things in the request URL
      self.filter_rev_enabled = True # Look for a revision ID
      self.filter_geo_enabled = True # Look for a bbox
      self.item_type = None
      #self.item_layer = None
      self.item_attc_type = None
      self.item_feat_type = None
      self.items_fetched = None

   # ***

   #
   def __str__(self):
      selfie = (
         'checkout: item_type: %s / attc_t: %s / feat_t: %s'
         % (self.item_type,
            self.item_attc_type,
            self.item_feat_type,
            #self.items_fetched,
            ))
      return selfie

   # *** Base class overrides

   #
   def decode_request(self):
      '''Validate and decode the incoming request.'''
      command.Op_Handler.decode_request(self)
      # Item(s) to fetch (required). This throws GWIS_Error if the item type is
      # bogus.
      self.decode_request_item_type()

   #
   def fetch_n_save(self):
      # Check the user's credentials and access to the branch, and set up
      # query_filters.
      command.Op_Handler.fetch_n_save(self)
      # Check that the constraints are met. I.e., for geographic features, we
      # require a bbox so we don't return too many records.
      cpolicy = None
      try:
         if ((self.item_type == 'link_value')
             or (self.item_type == 'link_geofeature')):
            atype_policy, ftype_lookup = (Op_Handler.constraint_links
                                                [self.item_attc_type])
            cpolicy = atype_policy
            # See if there's a more specific policy
            cpolicy = ftype_lookup[self.item_feat_type]
      except KeyError:
         pass
      # 
      if cpolicy is None:
         try:
            cpolicy = Op_Handler.constraint_policy[self.item_type]
         except KeyError:
            # FIXME: All the GWIS_Errors are programmer errors but are sent
            # to the client, presumably for the benefit of the developer. The
            # client should distinguish btw GWIS_Warning and GWIS_Error so user
            # knows when it's their fault and when it's not.
            raise GWIS_Error('The specified item type is not recognized (%s).' 
                             % (self.item_type,))
      # Check the one or more policies that may be set.
      if cpolicy != Op_Handler.cons_none:
         gwis_errs = []
         num_policies = 0
         if cpolicy & Op_Handler.cons_bbox:
            num_policies += 1
            if (not self.req.viewport) or (not self.req.viewport.include):
               gwis_errs.append('No window specified.')
            elif self.req.viewport.include.area() > conf.constraint_bbox_max:
               # See comments above. You can fetch 'route' items with any
               # bbox... which means you could potentially fetch all routes
               # ever anywhere and bog down the server while it processes your
               # request.
               if not (cpolicy & Op_Handler.cons_bbx2):
                  gwis_errs.append('%s %s %s.'
                     % ('Window size too large for item request.',
                        'Please resize your browser window and complain to',
                        conf.mail_from_addr,))
               else:
                  log.warning('fetch_n_save: Op_Handler.cons_bbx2 is Bad.')
         if cpolicy & Op_Handler.cons_page:
            num_policies += 1
            # FIXME: Limit the size of the page!
            if self.req.filters.pagin_total:
               if self.req.filters.pagin_count != 0:
                  gwis_errs.append('Cannot mix pagination and counts (%s).'
                                   % (self.item_type,))
            elif self.req.filters.pagin_count == 0:
               gwis_errs.append('Item type requires pagination (%s).'
                                % (self.item_type,))
            elif self.req.filters.pagin_count > conf.constraint_page_max:
               gwis_errs.append('Count too large for item request (%s).'
                                % (self.item_type,))
         if cpolicy & Op_Handler.cons_sids:
            num_policies += 1
            # NOTE: We only check the existance of strings here. Later, we'll
            # see if the strings contain integers or not.
            id_count = self.req.filters.get_id_count(self.item_type, gwis_errs)
            if id_count == 0:
               gwis_errs.append('Stack IDs missing from request (%s).'
                                % (self.item_type,))
            elif id_count > conf.constraint_sids_max:
               gwis_errs.append('Too many stack IDs in request (%s).'
                                % (self.item_type,))
         if cpolicy & Op_Handler.cons_solo:
            num_policies += 1
            try:
               stack_id = int(self.req.filters.only_stack_ids)
            except ValueError:
               gwis_errs.append('Expected one and only one stack ID.')
         # If at least one of the policies is satisfied, we're satisfied.
         if len(gwis_errs) == num_policies:
            err_str = ' / '.join(gwis_errs)
            log.debug('fetch_n_save: err_str: %s' % (err_str,))
            raise GWIS_Error(err_str)
         else:
            #log.error('PROBLEM [%d] %s' % (num_policies, ','.join(gwis_errs)))
            g.assurt(len(gwis_errs) < num_policies)
      # Make an instance of the item type's Many class.
      if ((self.item_type == 'link_value')
          or (self.item_type == 'link_geofeature')):
         # FIXME: Don't do geometric link_value fetches anymore. Require
         # rhs_stack_ids.
         self.items_fetched = item_factory.get_item_module(
                                 self.item_type).Many(self.item_attc_type,
                                                      self.item_feat_type)
      else:
         self.items_fetched = item_factory.get_item_module(
                                 self.item_type).Many()

      log.verbose1('fetch_n_save: for: %s'
                   % (self.items_fetched.one_class,))

      try:

         # Make the query builder object from the request object.
         qb = self.req.as_iqb()

         # Fetch the items.

         # At this point, the user has view-access or better to the
         # branch. Next, we search for items, but we leave it up to the item
         # class to enforce permissions on the items (that is, to only fetch
         # items to which the user has view access or better).

         # The clever search includes auxiliary data, e.g., if we're checking
         # out geofeatures, it'll collect tags and attributes attached to the
         # geofeatures. Obviously, if we're just getting the query count, we
         # don't need the extra goodies.
         if qb.filters.pagin_total:
            self.items_fetched.search_for_items_simple(qb)
         else:
            self.items_fetched.search_for_items_clever(qb)

      except GWIS_Nothing_Found, e:
         # This is so we can short-circuit if we know nothing will be found.
         log.debug('fetch_n_save: GWIS_Nothing_Found: nothing found')
         pass

   #
   def prepare_metaresp(self):
      command.Op_Handler.prepare_metaresp(self)

   #
   def prepare_response(self):
      log.verbose('prepare_response')
      sub_doc = self.items_fetched.prepare_resp_doc(self.doc, self.item_type)
      need_digest = isinstance(self.req.revision.rev, revision.Diff)
      self.items_fetched.append_gml(sub_doc, need_digest)
      # This is a hacky way to set strings without using returns.
      extras = [self.req.sendfile_out,]
      self.items_fetched.postpare_response(self.doc, sub_doc, extras)
      self.req.sendfile_out = extras[0]
      log.debug('prepare_response: self.req.sendfile_out: %s'
                % (self.req.sendfile_out,))

   # *** Protected Interface

   #
   def decode_request_item_type(self):
      '''
      Checks that item_type is a valid geofeature, attachment, or
      link_value. Since link_value is a factory class (of sorts), we also
      check that the geofeature and attachment types it references are
      valid.
         
      NOTE We could defer this check and the subsequent GWIS_Error to the
           link_value class constructor, but we do it here so we have the
           attachment and geofeature class handles handy for the link_value
           constructor (which also relieves the link_value class of having
           to verify the class types, which may or may not be a Good Thing).
      '''
      success = True
      # Every GML GetItem request requires an item_type
      self.item_type = self.decode_key('ityp')
      if ((self.item_type == 'link_value')
          or (self.item_type == 'link_geofeature')):
         # The link_value joins attachments and geofeatures; check that both
         # exist.
         # MAYBE: Let client specify item types by int ID, rather than string.
         self.item_attc_type = self.decode_key('atyp', None)
         self.item_feat_type = self.decode_key('ftyp', None)
         success = (
            item_factory.is_item_valid(self.item_attc_type)
            and item_factory.is_item_valid(self.item_feat_type))
         # Check for success; throw now before further processing.
         if (not success):
            raise GWIS_Error(
               'Invalid link_value type(s): attc: %s / feat: %s' 
               % (self.item_attc_type, self.item_feat_type,))
      else:
         # Otherwise, item_type is a module in the item/ package.
         self.item_attc_type = None
         self.item_feat_type = None
         success = item_factory.is_item_valid(self.item_type, True)
         # Reid says, Barf on error.
         if not success:
            raise GWIS_Error('Invalid item type: ' + self.item_type)

      log.verbose1('decode_request_item_type: %s / lhs: %s / rhs: %s' 
         % (self.item_type, self.item_attc_type, self.item_feat_type,))

   # ***

# ***

