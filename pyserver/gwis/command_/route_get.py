# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The GetRoute request calculates a route from one address to another, or
# reads in a previously computed route from the database

import datetime
from lxml import etree
import os
import socket
import sys
import time

import conf
import g

from grax.access_infer import Access_Infer
from grax.grac_manager import Grac_Manager
from grax.library_squelch import Library_Squelch
from gwis import command
from gwis.command_ import commit
from gwis.exception.gwis_error import GWIS_Error
from item.feat import route
from item.feat import route_step
from item.grac import group
from item.util import landmark
from item.util import revision
from planner.problem_base import Problem_Base
from planner.routed_p3 import tgraph as routed_p3_tgraph
from planner.travel_mode import Travel_Mode
from util_ import misc
from util_.routed_ports import Routed_Ports

log = g.log.getLogger('cmd.route_get')

class Op_Handler(command.Op_Handler):

   # If route_stack_id is not None, then
   #  beg_addr, beg_ptx, beg_pty, fin_addr, fin_ptx, fin_pty,
   #  p1_priority, rating_min, tag_prefs, tags_use_defaults 
   # are ignored.
   __slots__ = (
      'qb',
      #
      'xml',
      'routed_port',
      #
      'route_stack_id',
      # Skipping 'route_system_id; using qb.filters.only_system_id instead.
      #
      'caller_source',
      #
      'beg_addr',
      'beg_ptx',
      'beg_pty',
      'fin_addr',
      'fin_ptx',
      'fin_pty',
      #
      'travel_mode',
      #
      'p1_priority',
      #
      'p2_depart_at',
      'p2_transit_pref',
      #
      'p3_weight_attr',
      'p3_weight_type',
      'p3_rating_pump',
      'p3_burden_pump',
      'p3_spalgorithm',
      #
      # tags_use_defaults means avoid edges tagged 'impassable' or 'closed',
      # if the request is a personalized route; tag preferences are ignored
      # for non-personalized routes.
      'rating_min',
      'tag_prefs',
      'tags_use_defaults',
      #
      'compute_landmarks',
      'as_gpx',
      'dont_save',
      'check_invalid',
      'exp_landmarks_uid',
      #
      )

   error_message = ('%s%s%s%s'
      # E.g., First %s is 'No response from' or 'Error connecting to'.
      # Second %s is the error message.
      % ('%s routing server. ',
         'The Cyclopath team is working on the problem. ',
         'We apologize for the inconvenience! ',
         '%s',))

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      # Look for a revision ID or fetch by system ID.
      self.filter_rev_enabled = True
      #
      self.qb = None
      self.xml = None
      self.routed_port = None
      self.route_stack_id = None
      #self.route_system_id = None
      self.caller_source = None
      self.xml = None
      self.beg_addr = None
      self.beg_ptx = None
      self.beg_pty = None
      self.fin_addr = None
      self.fin_ptx = None
      self.fin_pty = None
      self.travel_mode = None
      self.p1_priority = None
      self.p2_depart_at = None
      self.p2_transit_pref = None
      self.p3_weight_attr = None
      self.p3_weight_type = None
      self.p3_rating_pump = None
      self.p3_burden_pump = None
      self.p3_spalgorithm = None
      self.rating_min = None
      self.tag_prefs = None
      self.tags_use_defaults = None
      self.compute_landmarks = None
      self.as_gpx = None
      self.dont_save = None
      self.check_invalid = None
      self.exp_landmarks_uid = None

   # ***

   #
   def __str__(self):
      selfie = (
         'route_get: %s / %s / %s / p3: atr %s / typ %s / rpmp %s / bpmp %s%s'
         % (#self.qb,
            #self.xml,
            #self.routed_port,
            #self.route_stack_id,
            #self.caller_source,
            'beg: %s (%s, %s)' % (self.beg_addr,
                                  self.beg_ptx,
                                  self.beg_pty,),
            'fin: %s (%s, %s)' % (self.fin_addr,
                                  self.fin_ptx,
                                  self.fin_pty,),
            Travel_Mode.get_travel_mode_name(self.travel_mode)
               if Travel_Mode.is_valid(self.travel_mode)
               else 'unknown mode',
            #self.p1_priority,
            #self.p2_depart_at,
            #self.p2_transit_pref,
            self.p3_weight_attr,
            self.p3_weight_type,
            self.p3_rating_pump,
            self.p3_burden_pump,
            ' / deeplink' if (    (self.qb is not None)
                              and (self.qb.filters.use_stealth_secret))
                          else '',
            #self.p3_spalgorithm,
            #self.rating_min,
            #self.tag_prefs,
            #self.tags_use_defaults,
            #self.compute_landmarks,
            #self.as_gpx,
            #self.dont_save,
            #self.check_invalid,
            #self.exp_landmarks_uid,
            ))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

      self.qb = self.req.as_iqb()

      self.xml = None
      self.routed_port = None
      self.caller_source = self.decode_key('source') # NOTE: required.
      #
      self.route_stack_id = int(self.decode_key('rt_sid', 0))
      if self.route_stack_id and self.qb.filters.only_system_id:
         raise GWIS_Error('Please try just one of stack ID(s) or system ID.')

      self.compute_landmarks = self.decode_key_bool('add_lmrks')

      # Oopsbroke r30747 13/9/24 to r31652 14/4/25 (live 4/14)- Thanks, user!:
      self.as_gpx = self.decode_key_bool('asgpx')
      self.exp_landmarks_uid = self.decode_key('exp_landmarks_uid', -1)

      # The client sets check_invalid when it wants us to fix a broken route,
      # i.e., if an old byway uses byways that have been edited, recalculate
      # the route. This adds time to what could be a fast checkout of an
      # existing route, so the client can let the user choose if and when
      # to fix broken routes. And not that check_invalid is considered
      # false if asgpx=true.
      self.check_invalid = self.decode_key_bool('checkinvalid')

      # MAYBE: If check_invalid, should we automatically set dont_save=True?
      self.dont_save = self.decode_key_bool('dont_save')

      if (not self.route_stack_id) and (not self.qb.filters.only_system_id):
         # This is a new route request. Compute a new route.
         self.decode_request_prepare_new_route()

   #
   def decode_request_prepare_new_route(self):

      self.beg_ptx = self.decode_key('beg_ptx')
      self.beg_pty = self.decode_key('beg_pty')
      self.fin_ptx = self.decode_key('fin_ptx')
      self.fin_pty = self.decode_key('fin_pty')

      # The beg_addr and fin_addr parameters are just names, so they're not
      # required.
      self.beg_addr = self.decode_key('beg_addr', None)
      self.fin_addr = self.decode_key('fin_addr', None)

      self.travel_mode = self.decode_key('travel_mode', 'wayward')
      # Determine which route daemon to contact.
      self.routed_port_set(self.travel_mode)

      # Classic p1 planner options.
      # MAGIC NUMBERS. The default preference values are usually
      #                overwritten by the client request, but we
      #                supply some defaults nonetheless.
      #                The priority ranges from 0 to 1 and indicates
      #                how much to base a byway's cost on the rating.
      #                The min rating is 1/2 on a scale of 0 to 5;
      #                0 being an impassably-rated byway, and 5
      #                being an impossibly awesomely-rated byway.
      self.p1_priority = 0.5

      # Multimodal p2 planner options.
      self.p2_depart_at = ''
      self.p2_transit_pref = 0

      # Static p3 planner options.
      self.p3_weight_attr = ''
      self.p3_weight_type = ''
      # MAGIC_NUMBERS: Defaults used in ccp.py, Conf.as, route_get.py,
      #                and 234-byway-is_disconnected.sql; see the value
      #                sets, pyserver/planner/routed_p3/tgraph.py's
      #                Trans_Graph.rating_pows and burden_vals.
      self.p3_rating_pump = 0
      self.p3_burden_pump = 0
      self.p3_spalgorithm = ''

      # Shared p1 and p3 planner options.
      self.rating_min = 0.5
      self.tags_use_defaults = True
      self.tag_prefs = list()

      if self.req.doc_in is not None:
         self.decode_request_process_doc_in()
      # else, EXPLAIN: Does this matter? Are we just using defaults?

   #
   def decode_request_process_doc_in(self):

      e = self.req.doc_in.find('preferences')
      if e is None:
         raise GWIS_Error('Route request missing "preferences".')

      if self.travel_mode == Travel_Mode.wayward:

         # Skipping: not sent from client: p3_weight_attr

         p3_weight_type = e.get('p3_wgt')
         if p3_weight_type is not None:
            if (p3_weight_type
                in routed_p3_tgraph.Trans_Graph.weight_types):
               self.p3_weight_type = p3_weight_type
            else:
               raise GWIS_Error('p3_weight_type not a valid value: %s.'
                                % (p3_weight_type,))

         p3_spalgorithm = e.get('p3_alg')
         if p3_spalgorithm is not None:
            if (p3_spalgorithm
                in routed_p3_tgraph.Trans_Graph.algorithms):
               self.p3_spalgorithm = p3_spalgorithm
            else:
               raise GWIS_Error('p3_spalgorithm not valid: %s.'
                                % (p3_spalgorithm,))

         p3_rating_pump = e.get('p3_rgi')
         if p3_rating_pump is not None:
            try:
               p3_rating_pump = int(p3_rating_pump)
               if (p3_rating_pump
                   in routed_p3_tgraph.Trans_Graph.rating_pows):
                  self.p3_rating_pump = p3_rating_pump
               else:
                  raise GWIS_Error('p3_rating_pump not valid: %s.'
                                   % (p3_rating_pump,))
            except ValueError:
               raise GWIS_Error('p3_rating_pump not a valid int: %s.'
                                % (p3_rating_pump,))

         p3_burden_pump = e.get('p3_bdn')
         if p3_burden_pump is not None:
            try:
               p3_burden_pump = int(p3_burden_pump)
               if (p3_burden_pump
                   in routed_p3_tgraph.Trans_Graph.burden_vals):
                  self.p3_burden_pump = p3_burden_pump
               else:
                  raise GWIS_Error('p3_burden_pump not valid: %s.'
                                   % (p3_burden_pump,))
            except ValueError:
               raise GWIS_Error('p3_burden_pump not a valid int: %s.'
                                % (p3_burden_pump,))

      elif self.travel_mode == Travel_Mode.transit:

         # This is the still-surviving multimodal finder. Which needs a
         # lot of help. You can access it from flashclient. Or ccp.py.

         self.p2_depart_at = self.decode_key('p2_depart', '')

         try:
            self.p2_transit_pref = int(self.decode_key('p2_txpref', 0))
         except ValueError:
            raise GWIS_Error('p2_transit_pref not a valid int.')

      elif self.travel_mode in (Travel_Mode.bicycle,
                                Travel_Mode.classic,):

         p1_priority = e.get('p1_priority')
         if p1_priority is not None:
            try:
               self.p1_priority = float(p1_priority)
            except ValueError:
               raise GWIS_Error('p1_priority not a valid float.')

      if ((self.travel_mode in (Travel_Mode.bicycle,
                                Travel_Mode.classic,))
          or (self.p3_weight_type
              in routed_p3_tgraph.Trans_Graph.weights_personal)):

         # tags_use_defaults defaults to True. flashclient always unsets
         # it once tags have been loaded in the client... because
         # otherwise the client will send the list of tag preferences.
         # Okee dokie!
         # Note that the protocol using the old name 'use_defaults',
         # but [lb] changed the name in pyserver to be more precise
         # ('use_defaults' seems like it would apply to all options).
         if e.get('use_defaults') and (e.get('use_defaults') != 'true'):
            self.tags_use_defaults = False

         if self.tags_use_defaults:
            res = self.req.db.sql(
               ("SELECT * FROM tag_preference WHERE username = '%s'"
                % (conf.generic_rater_username,)))
            for row in res:
               self.tag_prefs.append((row['tag_stack_id'],
                                      row['tpt_id'],))
         else:
            # tag_pref_types: 0, ignore; 1, bonus; 2, penalty; 3, avoid.
            res = self.req.db.sql("SELECT * FROM tag_preference_type")
            for row in res:
               vals = e.get(row['text'])
               if vals is not None:
                  for v in vals.split(','):
                     self.tag_prefs.append((v, int(row['id'])))

   # ***

   #
   def fetch_n_save(self):

      time_start = time.time()

      command.Op_Handler.fetch_n_save(self)

      # MAYBE: CcpV1 calls transaction_retryable here. We don't.

      if (not self.route_stack_id) and (not self.qb.filters.only_system_id):

         # Use the route daemon to compute a new route.
         # Note that some options, like as_gpx, don't apply to new routes.
         save_route = not self.dont_save
         self.xml = self.routed_fetch(save_route)

         # Complain if fetching an existing route took a long time.
         # 2014.09.09: [lb] feels like triggering logcheck emails is not
         #             useful.
         #             BUG nnnn: Add a compute time to route table, or
         #                       just parse the minnesota-apache.log files,
         #                       and make a chart of the average route
         #                       compute times. You could also include
         #                       route distance, since longer routes
         #                       take longer to compute.
         # 2014.09.09: Let's start with a three minute threshold.
         over_time = misc.time_complain('fetch_n_save: new route',
                                        time_start,
                                        threshold_s=180.0,
                                        at_least_debug=True,
                                        debug_threshold=0.0,
                                        info_threshold=30.0)
         if over_time:
            log.warning('fetch_n_save: slow route computation: %s' % (self,))

      else:

         # BUG nnnn: 2012.05.05. [lb] requested a route in the basemap, then
         # changed to the metc branch and it came back with a route: maybe
         # routes should be branch-specific, though?

         routes = route.Many()

         if self.as_gpx:
            self.qb.filters.include_item_aux = True

         if ((self.qb.filters.gia_use_sessid)
             and (self.qb.username != conf.anonymous_username)):
            ensure_usr_arbiter = True
            self.qb.filters.include_item_stack = True
         else:
            ensure_usr_arbiter = False
         log.debug('fetch_n_save: ensure_usr_arbiter: %s'
                   % (ensure_usr_arbiter,))

         time_0 = time.time()

         if self.route_stack_id:
            routes.search_by_stack_id(self.route_stack_id, self.qb)
         else:
            #self.qb.revision = revision.Comprehensive(
            #                     gids=self.qb.revision.gids)
            #self.qb.branch_hier[0] = (self.qb.branch_hier[0][0],
            #                          self.qb.revision,
            #                          self.qb.branch_hier[0][2],)
            g.assurt(isinstance(self.qb.revision, revision.Comprehensive))
            g.assurt(self.qb.filters.only_system_id)
            routes.sql_clauses_cols_setup(self.qb)
            routes.search_get_items(self.qb)

         misc.time_complain(
            'fetch_n_save: found %d routes' % (len(routes),),
            time_0, threshold_s=17.5, at_least_debug=True, debug_threshold=0)

         if len(routes):

            rt = routes[0]

            # If an anonymous user requests a route and then logs in, we give
            # the real user arbiter rights to the item.
            # MAYBE: If other items work like routes, we'll want this behavior
            #        to apply to those items... like, can anonymous users
            #        generate tracks and then login and save them?
            if ensure_usr_arbiter:

               log.debug('fetch_n_save: user: %s / acc_infer: %s / %s'
                         % (self.qb.username, hex(rt.access_infer_id), rt,))

               time_0 = time.time()

               # The route has one gia record: the session ID's arbiter record.
               g.assurt(not rt.groups_access)

               rt.groups_access_load_from_db(self.qb)

               do_sneaky_update = True

               # New routes by anon users are session ID arbitered...
               if ((rt.access_infer_id != Access_Infer.sessid_arbiter)
                   # and if the deep link is created, stealth ID editored.
                   and (rt.access_infer_id !=
                        (Access_Infer.sessid_arbiter
                         | Access_Infer.stealth_editor))):
                  do_sneaky_update = False
                  log.error(
                     'fetch_n_save: unexpected rt.access_infer_id: %s / %s'
                     % (hex(rt.access_infer_id), rt,))
               #elif len(rt.groups_access) != 1:
               #   do_sneaky_update = False
               #   log.error(
               #      'fetch_n_save: unexpected rt.groups_access: %s / %s'
               #      % (rt.groups_access, rt,))
               else:
                  session_id_group = group.Many.session_group_id(self.qb.db)
                  try:
                     session_gia = rt.groups_access[session_id_group]
                  except KeyError, e:
                     do_sneaky_update = False
                     log.error(
                        'fetch_n_save: no sess rec in groups_access: %s / %s'
                        % (rt.groups_access, rt,))

               # NOTE: Since we update the existing records, we won't know that
               #       the user originally created the route anonymously. But
               #       if we care about that data, we should probably do it
               #       another way...

               if do_sneaky_update:

                  success = self.qb.db.transaction_retryable(
                     self.userify_anon_records, self.qb, rt)

                  if not success:
                     log.warning('fetch_n_save: failed!')

               misc.time_complain('fetch_n_save: ensure_usr_arbiter', time_0,
                                  threshold_s=5.0, at_least_debug=True,
                                  debug_threshold=0)

            # end: if ensure_usr_arbiter

         # end: if len(routes)

         else:
            # EXPLAIN: Is this very common? Are we missing anything?
            log.error(
               'fetch_n_save: denied: qb: %s / flt: %s / stk: %s / sys: %s'
               % (str(self.qb),
                  str(self.qb.filters),
                  self.route_stack_id,
                  self.qb.filters.only_system_id,))
            # SYNC_ME: Ambiguous not-found or access-denied error msg.
            raise GWIS_Error('Route not found or access denied.')

         g.assurt(rt.can_know())

         alternate_enabled = False
         if ((not self.as_gpx)
             and (rt.travel_mode != Travel_Mode.transit)
             and (self.check_invalid)):
            alternate_enabled = True

         # Get landmarks that the client can show within the cue sheet.
         # MAYBE: This can take a few seconds, so we might want to revisit it,
         #        like, only enable for certain types of routes, or only enable
         #        if the user opts-in, or maybe we can speed up the algorithm.
         #        Or maybe it's only slow on [lb]'s dev. machine and it'll
         #        be just fine on the server.
         if ((not alternate_enabled)
             and (self.compute_landmarks
                  or (rt.system_id in conf.landmarks_exp_rt_system_ids))):
            time_0 = time.time()
            # MAYBE: Just use self.qb?
            if self.exp_landmarks_uid >= 0:
               landmark.landmarks_exp_retrieve(rt,
                                               self.req.as_iqb(),
                                               self.req.client.username,
                                               self.exp_landmarks_uid)
            else:
               landmark.landmarks_compute(rt.rsteps, self.req.as_iqb())
            misc.time_complain('fetch_n_save: landmarks_compute',
                               time_0,
                               threshold_s=15.0,
                               at_least_debug=True,
                               debug_threshold=0.0,
                               info_threshold=5.0)

         # BUG nnnn: Similar feature to fix multimodal routes... after fixing
         #           multimodal route finder....
         # Recompute the route if broken and so requested.
         alternate_geo = None
         if alternate_enabled and (rt.stale_nodes > 0):
            time_0 = time.time()
            alternate_geo = self.xml_alt_geo(rt)
            misc.time_complain('fetch_n_save: xml_alt_geo', time_0,
                               threshold_s=5.0, at_least_debug=True,
                               debug_threshold=0)

         time_0 = time.time()
         # Maybe insert the alternate geometry into the route xml.
         # EXPLAIN: alternate_geo is appended to the existing route_steps?
         #          So the client shows both versions of the route?
         #          Examine a Wireshark trace.
         self.xml = rt.as_xml(self.req.db,
                              self.as_gpx,
                              appendage=alternate_geo,
                              appage_nom='./route')
         misc.time_complain('fetch_n_save: rt.as_xml', time_0,
                            threshold_s=5.0, at_least_debug=True,
                            debug_threshold=0)

         # Complain if fetching an existing route took a long time.
         misc.time_complain('fetch_n_save: existing route', time_start,
                            threshold_s=30.0, at_least_debug=True,
                            debug_threshold=0)

   #
   def prepare_metaresp(self):
      # Only do super's fetch when not a gpx request:
      #   super assumes that we have a <data> element and will
      #   cause errors if it's just gpx text.
      if not self.as_gpx:
         command.Op_Handler.prepare_metaresp(self)

   #
   def userify_anon_records(self, db, rt):

      log.debug('userify_anon_records: rt: %s' % (rt,))

      g.assurt(id(db) == id(self.qb.db))

      commit_cmd = commit.Op_Handler(self.req)
      commit_cmd.init_commit()
      #commit_cmd.qb = self.req.as_iqb(addons=False)
      commit_cmd.prepare_qb()

      style_change = rt.access_infer_id

      style_change &= ~Access_Infer.sessid_mask
      style_change |= Access_Infer.sessid_denied

      style_change &= ~Access_Infer.usr_mask
      style_change |= Access_Infer.usr_arbiter

      commit_cmd.schanges_items[rt.stack_id] = style_change

      use_latest_rid = True # I.e., don't get a new revision.
      commit_cmd.qb.item_mgr.start_new_revision(commit_cmd.qb.db,
                                                use_latest_rid)

      commit_cmd.qb.filters.gia_use_sessid = True

      log.debug('userify_anon_records: style_change: %s / %s'
                % (hex(style_change), rt,))

      commit_cmd.process_schanges()

      # Sneak in this cheat.
      sql_update_itm_rless = (
         """
         UPDATE item_revisionless
         SET edited_user = %s
         WHERE system_id = %d
         -- AND acl_grouping = %d
         """ % (commit_cmd.qb.db.quoted(commit_cmd.qb.username),
                rt.system_id,
                rt.acl_grouping,))
      commit_cmd.qb.db.sql(sql_update_itm_rless)
      # Correct the route, too, since we'll send it back to the client.
      rt.edited_user = commit_cmd.qb.username
      # Skipping:
      #  edited_date, edited_addr, edited_host, edited_note, edited_what

      # Sneak in an item_findability record so the route doesn't show up
      # in the user's library by default.
      rt.save_init_item_findability(commit_cmd.qb,
                                    commit_cmd.qb.username,
                                    commit_cmd.qb.user_id)

      # We probably don't need this:
      commit_cmd.qb.item_mgr.finalize_seq_vals(commit_cmd.qb.db)

      commit_cmd.qb.db.transaction_commit()

   # ***

      # NOTE: In the next function, CcpV1 would auto-save
      #       a new version of the route if it found that
      #       the connectivity hadn't changed.  CcpV2
      #       calculates the changes more precisely, so
      #       it knows when connectivity is actually
      #       different.  That is, CcpV1 would save a
      #       version of a route and claim a new revision
      #       if a byway along a route had been edited but
      #       whose nodes were unchanged, so that the next
      #       time the route was analyzed, CcpV1 would know
      #       the byways hadn't been changed. But the check
      #       itself should have been better. As a result
      #       of this odd approach, CcpV1 burned through
      #       a bunch of auto-route-save revisions, which
      #       unfortunately consumed most of the previous
      #       entries in the recent history list, which
      #       only showed the last 200 revisions (alas, it
      #       had no pageinator).

   #
   def xml_alt_geo(self, rt):

      log.debug('xml_alt_geo: rt.stop_steps_stale: %s'
                % (rt.stop_steps_stale,))

      time_0 = time.time()

      # Prepare this command like it was when the route was first requested.
      self.repair_broken_route_prepare_finder(rt)

      alt_rt = route.One()
      alt_rt.rsteps = route_step.Many()

      segs_recomputed = 0

      for stop_num in xrange(len(rt.rstops)-1):

         beg_rstop = rt.rstops[stop_num]
         fin_rstop = rt.rstops[stop_num+1]

         stale_sids = rt.stop_steps_stale[stop_num]

         log.debug('xml_alt_geo: stop_num: %d / no. stales: %d'
                   % (stop_num, len(stale_sids),))

         if stale_sids:

            inner_0 = time.time()

            sub_rt = self.get_sub_route_steps(rt, beg_rstop, fin_rstop)

            alt_rt.rsteps.extend(sub_rt.rsteps)
            segs_recomputed += 1

            misc.time_complain('xml_alt_geo: %d sub_rt steps (was %d steps)'
                               % (len(sub_rt.rsteps),
                                  fin_rstop.stop_step_number
                                  - beg_rstop.stop_step_number,),
                               inner_0, threshold_s=5.0, at_least_debug=True,
                               debug_threshold=0)

         else:

            splice_me = rt.rsteps[beg_rstop.stop_step_number:
                                  fin_rstop.stop_step_number]
            alt_rt.rsteps.extend(splice_me)

            log.debug('xml_alt_geo: keeping %d old steps' % (len(splice_me),))

      # end: for beg_stop_num, byway_sids in rt.stop_steps_stale.iteritems()

      alternate_geo = etree.Element('alternate')
      for step in alt_rt.rsteps:
         step.append_gml(alternate_geo)

      misc.time_complain(
         'xml_alt_geo: %d segments recomputed' % (segs_recomputed,),
         time_0, threshold_s=5.0, at_least_debug=True, debug_threshold=0)

      return alternate_geo

   # ***

   #
   def route_autoresolve_commit(self, rt):
      '''Save the current state of the route with a revision and a polite
         change message explaining why this is automatically happening.'''

      g.assurt(False) # No longer called. But long comments might be useful.

      log.error('route_autoresolve_commit: DEPRECATED')

      # Do a revisionless versioned save.
      # NOTE: In a Wiki, it might seem weird to save items that don't bump the
      #       revision. But their are many reasons to do this:
      #       1. You cannot revert a route.
      #       2. A route does not affect "map items", i.e., byways or their
      #          link_values.
      #       3. Routes are often private, and requesting and viewing routes is
      #          a very frequent activity. Do we really want to give up lots of
      #          revision numbers, especially when revision ID gaps will be a
      #          common sight it users' revision history? (That is, revision
      #          IDs are sacred, and have lots of meaning, and should change
      #          only when the map really changes.)

      # FIXME: Discussions should probably be revisionless, too, since they're
      #        not revertable and don't affect the map, but they steal revision
      #        numbers from recent changes (or do they appear in recent
      #        changes, so maybe we should just move them to a Discussions
      #        timeline?). (BUG nnnn?)
      #        WAIT: In CcpV1, can you revert discussions or see them in
      #              the revision list?

      rt.prepare_and_commit_revisionless(self.qb, Grac_Manager())

   # ***

   #
   def repair_broken_route_prepare_finder(self, rt):

      # Determine which route daemon to contact.
      g.assurt(rt.travel_mode)
      g.assurt(not self.routed_port)
      self.travel_mode = rt.travel_mode

      self.p1_priority = rt.p1_priority

      self.tags_use_defaults = rt.tags_use_defaults

      # This is a saved route, i.e., not a new route request, so the client
      # didn't specify any tag preferences (or we're ignoring them here).
      self.tag_prefs = list()
      for tp in rt.tagprefs:
         self.tag_prefs.append((tp, rt.tagprefs[tp],))

      # BUG nnnn: Support for stitching/repairing multimodal route.
      self.p2_depart_at = ''
      self.p2_transit_pref = 0
      self.rating_min = 0.5

      self.p3_weight_attr = rt.p3_weight_attr
      self.p3_weight_type = rt.p3_weight_type
      self.p3_rating_pump = rt.p3_rating_pump
      self.p3_burden_pump = rt.p3_burden_pump
      self.p3_spalgorithm = rt.p3_spalgorithm

      self.routed_port_set(self.travel_mode)

   #
   def get_sub_route_steps(self, rt, beg_pt, fin_pt):
      '''Replace current route configuration with the values held within route
         and use routed_fetch to get a new geometry, without saving
         the route.'''

      self.beg_ptx = beg_pt.x
      self.beg_pty = beg_pt.y
      self.fin_ptx = fin_pt.x
      self.fin_pty = fin_pt.y

      self.beg_addr = beg_pt.name
      self.fin_addr = fin_pt.name

      # Recompute the route between the two stops within the route -- this is,
      # we're recomputing a subset of the route. Obviously, we don't want to
      # save this sub-route.
      route_xml = self.routed_fetch(save_route=False)
      new_rt_xml = etree.fromstring(route_xml).find('./route')

      # HACK: We update the XML so from_gml doesn't complain.
      #       We use fake IDs... but we're just returning the route steps, so
      #       this shouldn't adversely affect anything.
      # MAYBE: Are these silly IDs really necessary? What about 'analysis',
      #        which doesn't save routes.
      # No: Illegal input attr: "..."
      #  misc.xa_set(new_rt_xml, 'system_id', -1)
      #  misc.xa_set(new_rt_xml, 'branch_id', -2)
      #  misc.xa_set(new_rt_xml, 'stack_id', -3)
      #  misc.xa_set(new_rt_xml, 'version', 0)
      #  misc.xa_set(new_rt_xml, 'acl_grouping', 1)
      #  misc.xa_set(new_rt_xml, 'deleted', False)
      #  misc.xa_set(new_rt_xml, 'reverted', False)

      # Extract the route steps from the route.

      # FIXME: Implement local_defns' reqv=3: check self.qb.request_is_local.
      g.assurt(not self.qb.request_is_local)
      self.qb.request_is_local = True

      new_rt = route.One()

      new_rt.from_gml(self.qb, new_rt_xml)
      #
      self.qb.request_is_local = False

      return new_rt
   
   #
   def routed_port_set(self, travel_mode):

      # Each route_get request only talks to one route server.

      g.assurt(travel_mode)

      if not self.routed_port:

         try:
            self.travel_mode = int(travel_mode)
         except ValueError:
            try:
               self.travel_mode = Travel_Mode.lookup[travel_mode]
            except KeyError:
               raise GWIS_Error('Unknown travel_mode: %s' % (travel_mode,))
         g.assurt(Travel_Mode.is_valid(self.travel_mode))

         if self.travel_mode not in Travel_Mode.px_modes:
            raise GWIS_Error('Not a planner travel_mode: %s' % (travel_mode,))

         # Query the database for a running routed for this branch/instance.
         # Since the client didn't specify the port, we assume they want the
         # 'general' route finder personality, i.e., not an analytics route 
         # finder personality.
         if self.travel_mode in Travel_Mode.p3_modes:
            # Travel_Mode.wayward, Travel_Mode.bicycle
            routed_pers = 'p3'
         elif self.travel_mode in Travel_Mode.p2_modes:
            # Travel_Mode.transit
            routed_pers = 'p2'
         elif self.travel_mode in Travel_Mode.p1_modes:
            # Travel_Mode.classic
            routed_pers = 'p1'
         else:
            g.assurt(False)

      # self.qb isn't set, so neither is self.qb.request_is_local.
      if ((self.req.client.request_is_local)
          and (conf.remote_routed_role == 'client')):
         self.routed_port = conf.remote_routed_port
      else:
         # This raises if the route finder is not running.
         self.routed_port = Routed_Ports.find_routed_port_num(
            self.req.db, self.req.branch.branch_id, routed_pers, 'general',
            self)

   #
   def routed_fetch(self, save_route):

      sock = None
      sockf = None

      try:

         # DEVS: Cross-domain route finder usage/testing.
         #
         #       To use: set CONFIG.remote_routed_role = 'server'
         #       in your server config and restart apache, set
         #       CONFIG.remote_routed_role on your dev server and
         #       restart apache, start the route finder on the remote
         #       server, load flashclient locally, and request a route.
         #
         #       If you're using ssh, use -L to map the port and then
         #       the remote host is really just localhost.
         #
         #       Benefits:
         #       1. Booting the route finder on the server is generally faster.
         #       2. The server has loads more memory. Oftentimes, dev machines
         #          have to use virtual memory to load the route finder.
         #       3. If you're not messing with the route finder but need to use
         #          it to develop, using a route finder that's always running
         #          saves time.

         # self.qb is now set, though we could still just use self.req.client.
         if ((self.qb.request_is_local)
             and (conf.remote_routed_role == 'client')):
            routed_host = conf.remote_routed_host
            # We already set the port, in routed_port_set().
            g.assurt(self.routed_port == conf.remote_routed_port)
            routed_port = conf.remote_routed_port
         else:
            routed_host = 'localhost'
            routed_port = self.routed_port

         log.debug('routed_fetch: daemon: %s:%d' % (routed_host, routed_port,))
         g.assurt(routed_port > 0)

         # Open connection
         sock = socket.socket()

         sock.connect((routed_host, routed_port,))
         sockf = sock.makefile('r+')

         # Write commands

         # SYNC_ME: pyserver.gwis.command_.route_get.routed_fetch sockf()s
         #          and services.route_analysis.route_analysis.route_evaluate.

         # This is a little weird: This is a *trusted* pipe, and we pipe along,
         # within, it the user making the request and their client's net deets.
         if self.req.client.username != conf.anonymous_username:
            sockf.write('user %s\n' % (self.req.client.username,))
         if self.req.client.remote_ip is not None:
            sockf.write('ipaddy %s\n' % (self.req.client.remote_ip,))
         if self.req.client.remote_host is not None:
            sockf.write('host %s\n' % (self.req.client.remote_host,))
         sockf.write('session_id %s\n' % (self.req.client.session_id,))
         sockf.write('source %s\n' % (self.caller_source,))

         sockf.write('beg_addr %s\n' % (self.beg_addr,))
         sockf.write('beg_ptx %s\n' % (self.beg_ptx,))
         sockf.write('beg_pty %s\n' % (self.beg_pty,))
         # Skipping: 'beg_nid %s' (since we're sending x,y and addr)

         sockf.write('fin_addr %s\n' % (self.fin_addr,))
         sockf.write('fin_ptx %s\n' % (self.fin_ptx,))
         sockf.write('fin_pty %s\n' % (self.fin_pty,))
         # Skipping: 'fin_nid %s' (since we're sending x,y and addr)

         # Which planner to use.
         sockf.write('travel_mode %s\n' % (self.travel_mode,))

         # p3 planner options.
         if self.travel_mode in Travel_Mode.p3_modes:
            # Travel_Mode.wayward, Travel_Mode.bicycle
            # Skipping: p3_weight_attr
            if self.p3_weight_type:
               sockf.write('p3_wgt %s\n' % (self.p3_weight_type,))
            if self.p3_rating_pump:
               sockf.write('p3_rgi %d\n' % (self.p3_rating_pump,))
            if self.p3_burden_pump:
               sockf.write('p3_bdn %d\n' % (self.p3_burden_pump,))
            if self.p3_spalgorithm:
               sockf.write('p3_alg %s\n' % (self.p3_spalgorithm,))

         # p2 planner options.
         if self.travel_mode in Travel_Mode.p2_modes:
            sockf.write('p2_depart %s\n' % (self.p2_depart_at,))
            sockf.write('p2_txpref %s\n' % (str(self.p2_transit_pref),))
         # p1 planner options.
         elif self.travel_mode in (Travel_Mode.bicycle,
                                   Travel_Mode.classic,):
            sockf.write('priority dist %s\n' % (1.0 - self.p1_priority,))
            sockf.write('priority bike %s\n' % (self.p1_priority,))

         if ((self.travel_mode in (Travel_Mode.bicycle,
                                   Travel_Mode.classic,))
             or (self.p3_weight_type
                 in routed_p3_tgraph.Trans_Graph.weights_personal)):
            sockf.write('rating_min %g\n' % (self.rating_min,))
            sockf.write('use_defaults %g\n' % (self.tags_use_defaults,))
            for tp in self.tag_prefs:
               sockf.write('tagpref %s %s\n' % (tp[0], tp[1],))

         # Whether or not to compute landmarks.
         sockf.write('add_lmrks %d\n' % (int(self.compute_landmarks),))
         # The format of the results.
         sockf.write('asgpx %d\n' % (int(self.as_gpx),))
         # Whether to save the route as a new item in the database,
         # or to forget it.
         sockf.write('save_route %d\n' % (int(save_route),))

         # Execute the route operation last
         sockf.write('route\n')

         sockf.flush()

         # Read XML response.
         # NOTE: We'll block here waiting for the response.
         byte_count_str = sockf.readline().rstrip()
         if byte_count_str == '':
            # There was an internal error.
            # [lb] has doubts this hits: wouldn't the route finder already
            # have raised an error?
            log.error('No response from route daemon?: %s' % (self,))
            #raise GWIS_Error(Op_Handler.error_message 
            #                 % ('No response from', '',))
            raise GWIS_Error(Problem_Base.error_msg_basic)
         byte_count = int(byte_count_str)

         xml = sockf.read(byte_count)

         # MEH: If we're leeching off a remote route finder, save_route will
         # have applied only to the remote server, so we won't have saved
         # the route locally, to our own database. If we were using our local
         # database for pyserer, we might want to save the route locally, so
         # that, e.g., it shows up in the route library, etc. But coding that
         # seems tedious: We'd have to parse the response, make a new route
         # object, populate its steps and stops, and then call
         # route.prepare_and_commit_revisionless. It really seems easier to
         # just run all of pyserver remotely. And using the production server
         # to run pyserver and routed makes for much faster development.
         #  See: conf.remote_routed_role == 'client'

      except socket.error, e:
         log.error('Error connecting: %s' % (str(e),))
         #raise GWIS_Error(
         #   Op_Handler.error_message 
         #   #% ('Error connecting to', ('The error was: %s' % (str(e),)),))
         #   % ('Error connecting to', '',))
         raise GWIS_Error(Problem_Base.error_msg_basic)

      except IOError, e:
         log.error('I/O error connecting: %s' % (str(e),))
         #raise GWIS_Error(
         #   Op_Handler.error_message 
         #     #% ('I/O error connecting', ('The error was: %s' % (str(e),)),))
         #     % ('I/O error connecting', '',))
         raise GWIS_Error(Problem_Base.error_msg_basic)

      finally:
         # Close connection (must close both to avoid "Connection reset by
         # peer" on server).
         if sockf is not None:
            sockf.close()
         if sock is not None:
            sock.close()

      return xml

   # HACK: Not calling base class, which does
   #          return etree.tostring(self.doc, pretty_print=True)
   def response_xml(self):
      return self.xml

   # ***

# ***

