#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./bike_facilities_populate.py --help
#
# Also:
#
#  $ ./bike_facilities_populate.py |& tee 2013.05.11.bike_facil_pop.txt
#

# BUG nnnn: Populate new /byway/cycle_route from byways' tags and attrs.
#           (I.e., this script answers yet-to-be-filed Bug nnnn.)

#  *** stats: created 18904 new links total
#  *** stats: created 16880 new links for attr: Bicycle Facility
#  *** stats: created 2024 new links for attr: Controlled Access
#  *** cnt:  14764 / facil: Bike Trail
#  *** cnt:   2116 / facil: Bike Lane
#FIXME: shoulder count
#
# May-12 21:17:00  INFO       script_base  #  Script completed in 4.98 mins.

script_name = ('Create and Populate New "Bike Facility" Attribute')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-05-11'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue
import time

import conf
import g

import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('facils_popl')

# ***

import copy
import psycopg2
import time
import traceback

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
from gwis.query_overlord import Query_Overlord
from item import item_base
from item import item_user_access
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.grac import group
from item.link import link_attribute
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
##debug_prog_log.debug_break_loop_cnt = 10

debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# ***

# 2013.05.11: [lb] doesn't quite remember when he sussed these tags out, so
# there might be some new ones we miss here... but probably not that many of
# them, it's not like people spend a lot of time tagging.

class Tag_Presumption(object):

   # 2013.05.12: On Mpls-St. Paul, applied to 2024 / 156378 line segments.
   tag_prohibited = (
      'prohibited',
      'closed',
      'biking prohibited',
      'closed - permanently',
      )

   # 2013.05.12: tag_bike_path + tag_bike_lane + tag_bike_shoulder:
#              On Mpls-St. Paul, applied to ??? / 156378 line segments.

   # 2013.05.12: trail: applied to 14764 / 156378 line segments.
   tag_bike_path = (
      'bikepath',
      'bike path',
      'combined path',
      #? 'path',
      #? 'paved path',
      #? 'wide sidewalk, bike path',
      )

   # 2013.05.12: blane: applied to 2116 / 156378 line segments.
   tag_bike_lane = (
      'bike lane',
      'bikelane',
      'bike lane one side',
      'bike lane on left',
      'bike lanes',
      )

# FIXME:
# 2013.05.13: shldr: applied to ??? / 156378 line segments.
   # FIXME: Sync with shoulder_dis
   tag_bike_shoulder = (
      'bike shoulder',
      'busy, good shoulder',
      'good shoulder',
      'great! recently repaved, wide shoulders',
      'nice shoulder',
      'shoulder',
      'shoulder lane',
      'striped shoulder',
      'striped shoulder on bridge',
      'wide shoulder',
      'wide shoulder path',
      'wide shoulder, safe',
      )

# FIXME: Wire this? ...
#        Make a boolean for unpaved??
#        And another boolean attribute for caution?
#        What about a temporal attribute for "xx (level?) of service"?
   tag_unpaved = (
      'dirt path',
      'Dirt path',
      'unpaved',
      )

   tag_bike_boulevard = (
      'bike boulevard',
      'bike boulevard marked with signage',
      # FIXME: Is bike route same as bike boulevard?:
      'bike route',
      ),

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      return ok

# *** Bike_Facilities_Populate

class Bike_Facilities_Populate(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.attr_cycle_facil = None
      # Piggy-back! So we don't need another script, attaching,
      # for controlled-access roadways (well, highways and freeways):
      self.attr_no_access = None
      # 2013.06.14: [lb] made the cautionary facils their own attribute. But we
      # don't need those for this script, since CcpV1 has no cautionaries.
      #  Nope: self.attr_cautionary = None
      #
      self.stats = dict()
      self.stats['cnt_attrs_all'] = 0
      self.stats['cnt_attrs_cyle_facil'] = 0
      self.stats['cnt_attrs_no_access'] = 0
      self.stats['cnt_facils_kvals'] = {}

   # ***

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         log.debug('go_main: getting exclusive revision lock...')
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='bike_facility_populate__go_main')
         log.debug('go_main: database is locked.')

         # MAYBE: There seems to be an awful lot of boilerplate code here.
         self.qb.grac_mgr = Grac_Manager()
         self.qb.grac_mgr.prepare_mgr('user', self.qb)
         # A developer is running this script.
         g.assurt(self.qb.username
                  and (self.qb.username != conf.anonymous_username))
         self.qb.user_group_id = User.private_group_id(self.qb.db,
                                                       self.qb.username)

         # Get a new revision ID.
         self.qb.item_mgr.start_new_revision(self.qb.db)
         log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

         # Get the Bike Facility attribute.
         internal_name = '/byway/cycle_facil'
         self.attr_cycle_facil = attribute.Many.get_system_attr(
                                          self.qb, internal_name)
         g.assurt(self.attr_cycle_facil is not None)

         # Get the Controlled Access attribute.
         internal_name = '/byway/no_access'
         self.attr_no_access = attribute.Many.get_system_attr(
                                          self.qb, internal_name)
         g.assurt(self.attr_no_access is not None)

         # BUG nnnn: New Script: Populate '/byway/cycle_route' by...
         #                       stack IDs? byway names? maybe easier
         #                       just to do in flashclient....

         self.byways_suss_out_facilities()

         # Save the new revision and finalize the sequence numbers.
         log.debug('go_main: saving rev # %d' % (self.qb.item_mgr.rid_new,))

         # NOTE: We're cheating here: We know only the public group needs
         #       group_revision records, since all new items were only public.
         # Either of these should be acceptable:
         # group_names_or_ids = ['Public',]
         group_names_or_ids = [group.Many.public_group_id(self.qb),]
         # MAYBE: Give credit to user who runs this script, or _script?
         #        I.e., where is the accountability if user like/dislike
         #        application (calculation) of this new attribute?
         #
         #complain_to_this_user = 'landonb'
         #complain_to_this_user = self.qb.username
         complain_to_this_user = '_script'
         #
         changenote = ('Populated new bike facility attr. using existing '
                       + 'tags and attrs. (i.e., guessing!).')
         #
         self.finish_script_save_revision(group_names_or_ids,
                                          username=complain_to_this_user,
                                          changenote=changenote)

         self.print_stats()

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def byways_suss_out_facilities(self):

      log.info('byways_suss_out_facilities: ready, set, suss!')

      time_0 = time.time()

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      # 2013.05.12: Weird. At first, you'll see 1250 byways being processed
      # each second, but later in the processing, after 100,000 byways, you'll
      # see 250 byways being processed every one or two seconds.
      #prog_log.log_freq = 250
      #prog_log.log_freq = 2500
      prog_log.log_freq = 1000
      prog_log.loop_max = None

      feat_class = byway
      feat_search_fcn = 'search_for_items' # E.g. byway.Many().search_for_items
      processing_fcn = self.feat_suss_out_facil
      self.qb.item_mgr.load_feats_and_attcs(
            self.qb, feat_class, feat_search_fcn,
            processing_fcn, prog_log, heavyweight=False)

      log.info('... processed %d features in %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   # ***

   #
   def feat_suss_out_facil(self, qb, gf, prog_log):

      bike_facil = self.byway_deduce_bike_facility(gf)
      if bike_facil is not None:
         self.create_link_attr_feat(qb,
                                    self.attr_cycle_facil,
                                    gf,
                                    value_text=bike_facil)
         self.stats['cnt_attrs_cyle_facil'] += 1
         misc.dict_count_inc(self.stats['cnt_facils_kvals'], bike_facil)

      travel_restricted = self.byway_deduce_restricted(gf)
      if travel_restricted:
         self.create_link_attr_feat(qb,
                                    self.attr_no_access,
                                    gf,
                                    value_boolean=True)
         self.stats['cnt_attrs_no_access'] += 1

   # ***

   #
   def create_link_attr_feat(self, qb,
                                   attr,
                                   feat,
                                   value_boolean=None,
                                   value_integer=None,
                                   value_real=None,
                                   value_text=None,
                                   value_binary=None,
                                   value_date=None):

      g.assurt(id(qb) == id(self.qb))
      g.assurt(feat.item_type_id == Item_Type.BYWAY)

      client_id = self.qb.item_mgr.get_next_client_id()

      new_link = link_value.One(
         qb=self.qb,
         row={
            # *** from item_versioned:
            'system_id'             : None, # assigned later
            'branch_id'             : self.qb.branch_hier[0][0],
            'stack_id'              : client_id,
            'version'               : 0,
            'deleted'               : False,
            'reverted'              : False,
            'name'                  : '', # FIXME: Is this right?
            #'valid_start_rid'      : # assigned by
            #'valid_until_rid'      : #   version_finalize_and_increment
            # NOTE: We don't set valid_start_rid any earlier, so historic
            #       views obviously won't show bike facility ornamentation.
            'lhs_stack_id'          : attr.stack_id,
            'rhs_stack_id'          : feat.stack_id,
            # The item type IDs are saved to the group_item_access table.
            'link_lhs_type_id'      : attr.item_type_id,
            'link_rhs_type_id'      : feat.item_type_id,
            'value_boolean'         : value_boolean,
            'value_integer'         : value_integer,
            'value_real'            : value_real,
            'value_text'            : value_text,
            'value_binary'          : value_binary,
            'value_date'            : value_date,
            }
         )

      log.verbose2('create_link_facil: new_link: %s' % (new_link,))

      g.assurt(new_link.groups_access is None)
      new_link.stack_id_correct(self.qb)
      g.assurt(new_link.fresh)
      log.verbose('create_link_facil: not clearing item_cache')
      # NO: self.qb.item_mgr.item_cache_reset()
      self.qb.item_mgr.item_cache_add(new_link, client_id)
      self.qb.item_mgr.item_cache_add(attr)
      self.qb.item_mgr.item_cache_add(feat)

      prepared = self.qb.grac_mgr.prepare_item(self.qb,
         new_link, Access_Level.editor, ref_item=None)
      g.assurt(prepared)
      log.verbose2(' >> prepare_item: %s' % (new_link,))

      log.verbose2(' >> groups_access/1: %s' % (new_link.groups_access,))

      new_link.version_finalize_and_increment(
                  self.qb, self.qb.item_mgr.rid_new)
      log.verbose2(' >> version_finalize_and_increment: %s' % (new_link,))

      new_link.save(self.qb, self.qb.item_mgr.rid_new)
      log.verbose2(' >> saved: %s' % (new_link,))

      log.verbose2(' >> groups_access/2: %s' % (new_link.groups_access,))
      g.assurt(len(new_link.groups_access) == 1)
      try:
         group_id = group.Many.public_group_id(self.qb)
         new_link.groups_access[group_id]
      except KeyError:
         g.assurt(False) # Unexpected.

      self.stats['cnt_attrs_all'] += 1

   # ***

   #
   def byway_deduce_bike_facility(self, bway):

      bike_facil = None

      # MAYBE: Make stats for each bike facility value.
      # BUG nnnn: Or just calculate nightly, along with miles of road, etc.,
      #           I.e., a report for the agency clients. See also gnuplot.
      if bway.geofeature_layer_id in (byway.Geofeature_Layer.Bike_Trail,
                                      byway.Geofeature_Layer.Major_Trail,):
         bike_facil = 'paved_trail'
      # MAYBE: Also check Tag_Presumption.tag_bike_path?
      # 2013.05.11: Checking tag_bike_path is new:
      elif bway.tagged.intersection(Tag_Presumption.tag_bike_path):
         bike_facil = 'paved_trail'
      elif bway.tagged.intersection(Tag_Presumption.tag_bike_lane):
         bike_facil = 'bike_lane'
      elif bway.tagged.intersection(Tag_Presumption.tag_bike_shoulder):
         bike_facil = 'shld_lovol'
      # Skipping: 'Narrow Shoulder'
      # Skipping: Tag_Presumption.tag_unpaved
      # BUG nnnn: MAYBE: Use Tag_Presumption.tag_bike_boulevard... or just
      #                  use new attr instead and skip tags... maybe just
      #                  search for this tag and update their cycle_route
      #                  attr.

      return bike_facil

   #
   def byway_deduce_restricted(self, bway):

      # BUG nnnn: Do we need to support other reasons for restricted access?:
      #           Closed/Restricted: 'Controlled Access',
      #                              'Construction',
      #                              'Not Plowed/Nature',

      if bway.tagged.intersection(Tag_Presumption.tag_prohibited):
         travel_restricted = True
      else:
         travel_restricted = False

      return travel_restricted

   # ***

   #
   def print_stats(self):

      log.debug('*** stats: created %d new links total'
                % (self.stats['cnt_attrs_all'],))

      log.debug('*** stats: created %d new links for attr: %s'
                % (self.stats['cnt_attrs_cyle_facil'],
                   self.attr_cycle_facil.name,))

      log.debug('*** stats: created %d new links for attr: %s'
                % (self.stats['cnt_attrs_no_access'],
                   self.attr_no_access.name,))

      for attr_val, attr_cnt in self.stats['cnt_facils_kvals'].iteritems():
         log.debug('*** cnt: %6d / facil: %s'
                   % (attr_cnt, attr_val,))

   # ***

# ***

if (__name__ == '__main__'):
   bike_facils_pop = Bike_Facilities_Populate()
   bike_facils_pop.go()

