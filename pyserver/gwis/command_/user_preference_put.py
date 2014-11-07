# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error

log = g.log.getLogger('cmd.user_pre_put')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'email_bouncing',
      'enable_watchers_email',
      'enable_watchers_digest',
      'route_viz',
      'rf_planner',
      'rf_p1_priority',
      'rf_p2_transit_pref',
      'rf_p3_weight_type',
      'rf_p3_rating_pump',
      'rf_p3_burden_pump',
      'rf_p3_spalgorithm',
      'tags',
      'tags_enabled',
      # 2014.04.25: Generic/Agnostic client options.
      #            "Now why didn't I think of that?!"
      'flashclient_settings',
      'routefinder_settings',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.login_required = True
      self.email_bouncing = None
      self.enable_watchers_email = None
      self.enable_watchers_digest = None
      self.route_viz = None
      self.rf_planner = None
      self.rf_p1_priority = None
      self.rf_p2_transit_pref = None
      self.rf_p3_weight_type = None
      self.rf_p3_rating_pump = None
      self.rf_p3_burden_pump = None
      self.rf_p3_spalgorithm = None
      self.tags = None
      self.tags_enabled = None
      self.flashclient_settings = None
      self.routefinder_settings = None

   # ***

   #
   def __str__(self):
      selfie = (
         'user_pref_put: fc_sttgs: %s / rtef_sttgs: %s'
         % (#self.email_bouncing,
            #self.enable_watchers_email,
            #self.enable_watchers_digest,
            #self.route_viz,
            #self.rf_planner,
            #self.rf_p1_priority,
            #self.rf_p2_transit_pref,
            #self.rf_p3_weight_type,
            #self.rf_p3_rating_pump,
            #self.rf_p3_burden_pump,
            #self.rf_p3_spalgorithm,
            #self.tags,
            #self.tags_enabled,
            self.flashclient_settings,
            self.routefinder_settings,
            ))
      return selfie

   # ***

   #
   def decode_request(self):

      command.Op_Handler.decode_request(self)

      e = self.req.doc_in.find('preferences')

      try:

         email_bouncing = e.get('ebouncg')
         if (email_bouncing is not None):
            self.email_bouncing = bool(int(email_bouncing))
         else:
            self.email_bouncing = None

         # Watch Region email checkboxes
         enable_watchers_email = e.get('enable_watchers_email')
         if enable_watchers_email is not None:
            self.enable_watchers_email = bool(int(enable_watchers_email))
         else:
            self.enable_watchers_email = None

         enable_watchers_digest = e.get('enable_watchers_digest')
         if enable_watchers_digest is not None:
            self.enable_watchers_digest = bool(int(enable_watchers_digest))
         else:
            self.enable_watchers_digest = None

         # Route viz preferences
         route_viz = e.get('viz_id')
         if (route_viz is not None):
            self.route_viz = int(route_viz)
         else:
            self.route_viz = None

         # Which planner to use by default.
         rf_planner = e.get('rf_planner')
         if rf_planner is not None:
            self.rf_planner = int(rf_planner)
         else:
            self.rf_planner = None

         # Routefinder priority slider.
         rf_p1_priority = e.get('rf_p1_priority')
         if rf_p1_priority is not None:
            self.rf_p1_priority = float(rf_p1_priority)
         else:
            self.rf_p1_priority = None

         # RouteFinder multimodal busing slider.
         rf_p2_transit_pref = e.get('p2_transit_pref')
         if rf_p2_transit_pref is not None:
            self.rf_p2_transit_pref = float(rf_p2_transit_pref)
         else:
            self.rf_p2_transit_pref = None

         # Planner p3 options.
         rf_p3_weight_type = e.get('p3_wgt')
         if rf_p3_weight_type is not None:
            self.rf_p3_weight_type = rf_p3_weight_type
         else:
            self.rf_p3_weight_type = None

         rf_p3_rating_pump = e.get('p3_rgi')
         if rf_p3_rating_pump is not None:
            self.rf_p3_rating_pump = int(rf_p3_rating_pump)
         else:
            self.rf_p3_rating_pump = None

         rf_p3_burden_pump = e.get('p3_bdn')
         if rf_p3_burden_pump is not None:
            self.rf_p3_burden_pump = int(rf_p3_burden_pump)
         else:
            self.rf_p3_burden_pump = None

         rf_p3_spalgorithm = e.get('p3_alg')
         if rf_p3_spalgorithm is not None:
            self.rf_p3_spalgorithm = rf_p3_spalgorithm
         else:
            self.rf_p3_spalgorithm = None

         # Tag preferences (avoid, penalty, bonus)
         self.tags = dict()
         # One of: 0:ignore, 1:bonus, 2:penalty, 3:avoid
         res = self.req.db.sql("SELECT * FROM tag_preference_type")
         for row in res:
            vals = e.get(row['text'])
            if vals is not None:
               for v in vals.split(','):
                  self.tags[v] = int(row['id'])

         # Tag preference checkbox settings (enabled/disabled)
         self.tags_enabled = dict()
         vals = e.get('enabled')
         if vals is not None:
            for v in vals.split(','):
               self.tags_enabled[v] = True

         vals = e.get('disabled')
         if vals is not None:
            for v in vals.split(','):
               self.tags_enabled[v] = False

         flashclient_settings = e.get('fc_opts')
         if flashclient_settings is not None:
            self.flashclient_settings = flashclient_settings
         else:
            self.flashclient_settings = None

         routefinder_settings = e.get('rf_opts')
         if routefinder_settings is not None:
            self.routefinder_settings = routefinder_settings
         else:
            self.routefinder_settings = None

         # 2014.05.05: We used to raise GWIS_Error if any preference
         #             was missing from the GWIS request, but that's
         #             silly: we only update columns in the database
         #             that have changed.
         if False:
            if (    (email_bouncing is None)
                and (enable_watchers_email is None)
                and (enable_watchers_digest is None)
                and (route_viz is None)
                and (rf_planner is None)
                and (rf_p1_priority is None)
                and (rf_p2_transit_pref is None)
                and (rf_p3_weight_type is None)
                and (rf_p3_rating_pump is None)
                and (rf_p3_burden_pump is None)
                and (rf_p3_spalgorithm is None)
                and ((len(self.tags) == 0))
                and (flashclient_settings is None)
                and (routefinder_settings is None)
                ):
               raise GWIS_Error('No preferences were specified')

         for t in self.tags:
            # t is one of: ignore, bonus, penalty, avoid
            if not t in self.tags_enabled:
               raise GWIS_Error('Missing checkbox setting for tag')

      except ValueError:

         raise GWIS_Error('Inappropriate preferences value(s)')

   #
   def fetch_n_save(self):

      command.Op_Handler.fetch_n_save(self)

      success = self.req.db.transaction_retryable(self.attempt_save, self.req)

      if not success:
         log.warning('save: failed!')

   #
   def attempt_save(self, db, *args, **kwargs):

      g.assurt(id(db) == id(self.req.db))

      # Begin transaction
      #
      # Note that we don't lock any tables, as row conflicts would have to be
      # the same user setting the same preference and in that case the
      # arbitrary ordering obtained with locking is just as arbitrary as if we
      # didn't.
      self.req.db.transaction_begin_rw()

      # Save other preferences
      vars = list()
      if self.email_bouncing is not None:
         vars.append("email_bouncing = %s" % self.email_bouncing)
      if self.enable_watchers_email is not None:
         vars.append("enable_watchers_email = %s" % self.enable_watchers_email)
      if self.enable_watchers_digest is not None:
         vars.append("enable_watchers_digest = %s" 
                     % self.enable_watchers_digest)
      if self.route_viz is not None:
         vars.append("route_viz = %s" % self.route_viz)
      if self.rf_planner is not None:
         vars.append("rf_planner = %s" % self.rf_planner)
      if self.rf_p1_priority is not None:
         vars.append("rf_p1_priority = %s" % self.rf_p1_priority)
      if self.rf_p2_transit_pref is not None:
         vars.append("rf_p2_transit_pref = %s" % self.rf_p2_transit_pref)
      if self.rf_p3_weight_type is not None:
         vars.append("rf_p3_weight_type = '%s'" % self.rf_p3_weight_type)
      if self.rf_p3_rating_pump is not None:
         vars.append("rf_p3_rating_pump = %s" % self.rf_p3_rating_pump)
      if self.rf_p3_burden_pump is not None:
         vars.append("rf_p3_burden_pump = %s" % self.rf_p3_burden_pump)
      if self.rf_p3_spalgorithm is not None:
         vars.append("rf_p3_spalgorithm = %s"
                     % (self.req.db.quoted(self.rf_p3_spalgorithm),))
      if self.flashclient_settings is not None:
         vars.append("flashclient_settings = %s"
                     % (self.req.db.quoted(self.flashclient_settings),))
      if self.routefinder_settings is not None:
         vars.append("routefinder_settings = %s"
                     % (self.req.db.quoted(self.routefinder_settings),))
      # self.tags is a dict, but may be empty.

      # MAYBE: I [lb] think this is correct, unless we call it for the anon
      # user from a script. But I don't think we do.
      g.assurt(self.req.client.username != conf.anonymous_username)

      if len(vars) > 0:
         sql = (
            """
            UPDATE 
               user_
            SET 
               %s
            WHERE 
               username = %s
            """ % (", ".join(vars),
                   self.req.db.quoted(self.req.client.username),))
         self.req.db.sql(sql)

         # user preference log
         self.req.db.insert(
            'user_preference_event',
            { 'username': self.req.client.username, },
            { 'instance' : conf.instance_name,
              'enable_watchers_email': self.enable_watchers_email,
              'route_viz' : self.route_viz,
              'rf_planner': self.rf_planner,
              'rf_p1_priority' : self.rf_p1_priority,
              'rf_p2_transit_pref' : self.rf_p2_transit_pref,
              'rf_p3_weight_type' : self.rf_p3_weight_type,
              'rf_p3_rating_pump' : self.rf_p3_rating_pump,
              'rf_p3_burden_pump' : self.rf_p3_burden_pump,
              'rf_p3_spalgorithm' : self.rf_p3_spalgorithm,
              'flashclient_settings' : self.flashclient_settings,
              'routefinder_settings' : self.routefinder_settings,
               })

      # Save tag preferences
      if self.tags_enabled:
         for t in self.tags:
            # tag preference log
            self.req.db.insert(
               'tag_preference_event',
               { 'tag_stack_id': t,
                 'branch_id': self.req.branch.branch_id,
                 'username': self.req.client.username, },
               { 'tpt_id': self.tags[t],
                 'enabled': self.tags_enabled[t], })
            # real tag preference table
            self.req.db.insert_clobber(
               'tag_preference',
               { 'tag_stack_id': t,
                 'branch_id': self.req.branch.branch_id,
                 'username': self.req.client.username, },
               { 'tpt_id': self.tags[t],
                 'enabled': self.tags_enabled[t], })

      self.req.db.transaction_commit()

    # ***

# ***

