# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

log = g.log.getLogger('ccp_mrg_dbug')

from util_ import db_glue
from util_.log_progger import Debug_Progress_Logger

__all__ = (
   'Ccp_Merge_Conf_Base_Debug',
   )

# ***

class Ccp_Merge_Conf_Base_Debug(object):

   #__slots__ = (
   #   )

   # *** Constructor

   def __init__(self):

      # Use these switches to help debug.
      #
      # You can skip some fcns. or short-circuit processing some lists by
      # turning on some switches. Note that skipping fcns. reduces code 
      # coverage and short-circuiting lists reduces data coverage.

      # Isolate which features are imported, to focus on particular types.
      # Some items types are easier to import than others.
      # === item type =================== # processing speed
# FIXME: standins and exacts are somehow related, but not.
# standins are part of splits, otherwise they'd just be exacts.
      self.debug_skip_standins = False    # pretty quick (make lvals)
      self.debug_skip_standups = False    # snail (network conflation)
      self.debug_skip_exacts = False      # pretty quick (make lvals)
      self.debug_skip_splits = False      # tedious (inspect geometry)
      self.debug_skip_missing = False     # super fast
      # DEVS: Uncomment these as desired to speed up testing.
      #self.debug_skip_standins = True
      #self.debug_skip_standups = True
      #self.debug_skip_exacts = True
      #self.debug_skip_splits = True
      #self.debug_skip_missing = True

      self.debug_skip_import_all = (False
                                    or self.debug_skip_standins
                                    or self.debug_skip_standups
                                    or self.debug_skip_exacts 
                                    or self.debug_skip_splits
                                    or self.debug_skip_missing
                                    )

      # Scrutinize seemingly non-edited byways.
      # FIXME: This is an old switch. In the future, this could be tied to
      # EDIT_DATE, i.e., only scrutinize features with an EDIT_DATE greater
      # than a certain date.
      self.debug_scrutinize_untouched = False

      # Skip saving the target shapefiles, which can take a while.
      self.debug_skip_saves = False

      # Skip saving the new Cyclopath attributes.
      self.debug_skip_attrs = False
      #self.debug_skip_attrs = True

      # You can also short-circuit some of the lengthier processing loops,
      # giving better code coverage at the expense of better data coverage.
      self.debug_prog_log = Debug_Progress_Logger()
      #
      self.debug_prog_log.debug_break_loops = False
      #self.debug_prog_log.debug_break_loops = True
      #
      #self.debug_prog_log.debug_break_loop_cnt = 3
      #self.debug_prog_log.debug_break_loop_cnt = 10
      #self.debug_prog_log.debug_break_loop_cnt = 20
      #self.debug_prog_log.debug_break_loop_cnt = 30
      #self.debug_prog_log.debug_break_loop_cnt = 150
      #self.debug_prog_log.debug_break_loop_cnt = 300
      # 2012.02.ish: 
      #      2 loops / no commit: log.debug:         secs. / verbo:         s.
      #      3 loops / no commit: log.debug:   69.98 secs. / verbo:         s.
      #     10 loops / no commit: log.debug:  142.07 secs. / verbo:         s.
      #    100 loops / no commit: log.debug:         secs. / verbo:         s.
      #    100 loops / on commit: log.debug:         secs. / verbo:         s.
      # 2012.02.15: Script completed! 3035.32 secs. -> 50.5 mins. 
      #                               (no tags, though, and I killed logs et al
      # 
      #self.debug_prog_log.debug_break_loop_cnt = 10
      #self.debug_prog_log.debug_break_loop_cnt = 100
      #self.debug_prog_log.debug_break_loop_cnt = 1000

      # 2012.02.14: I [lb] had a failure 1220 items in but this didn't do the 
      #             trick... I was hoping to reproduce the failure quickly.
      #             BECAUSE: this affected how many groups of split features
      #             were imported, before the splits were combined and saved.
      #             You could make the log_freq the same. Or you could make 
      #             something akin to debug_just_ids, but debug_just_FIDs.
      #self.debug_prog_log.debug_break_loop_off = 1200

      self.debug_skip_commit = False
      #self.debug_skip_commit = True

      # Sometimes certain features have peculiar problems and you'd rather not
      # have to wait for half the script to run to debug 'em.
      self.debug_just_ids = ()
      # 2012.07.30: After implementing node_endpoint and node_endpoint and
      #             fixing byway splitting, the Bikeways import works on a
      #             subset of the Shapefile (i.e., debug_break_loop_cnt = 1000)
      #             but running against the complete Shapefile there are still
      #             some problem byways. Here's the list, as they were found...
      # MAYBE: When first reading the import shapefile, we just make two lists:
      # one for line segments with Ccp IDs, and one for line segments without.
      # We could further segment the Ccp-matching line segments so we get
      # better code coverage, because right now debug_break_loop_cnt doesn't
      # guarantee we'll hit all cases. Some groups: split-from vs. not. For
      # split-from, those with missing features at front, in the middle, or at
      # the end. For all matched Ccp features, those with _NEW_GEOM or _DELETE
      # or _REVERT set. Though: We could just as easily make a sample Shapefile
      # or just use Stack IDs here...
      #self.debug_just_ids = (1138689,)
      #self.debug_just_ids = (1398684,)
      #self.debug_just_ids = (985071,)
      #self.debug_just_ids = (1046589,)
      #self.debug_just_ids = (1124431,) # This line seg. has _NEW_GEOM = True
      #self.debug_just_ids = (1127428,) # Ug, forget to set _NEW_GEOM = True
      #self.debug_just_ids = (1124431, 1127428,) # The previous two together.
      #self.debug_just_ids = (1130805,) # dst_feat.GetGeometryRef().IsSimple()
      #self.debug_just_ids = (1484469,) # Marked _DELETE
      # 2013.11.22:
      # byway_setup: fixing truncated name: new: Bruce Vento Trail (17)
      #  / old: "Bruce Vento Trail " [byway:1125382.v6/233453-b2500677-acl:edt]
      # byway_setup: unexpected length: new: Bruce Vento Trail (17) 
      #  / old: "Bruce Vento Trail " [byway:1125382.v6/233453-b2500677-acl:edt]
      #self.debug_just_ids = (1125382,1125384,)
      #  1127417 which has an unexpected node_byway count...
      #self.debug_just_ids = (1127417,)
      #  1398684 has a truncated name that was also stripped of a space...
      #self.debug_just_ids = (1398684,)
      # 2013.11.23: This line uses a node endpoint that's used for two
      # intersections (at the same x,y), and the node_endpoint finder is
      # complaining because it's not considering the extra node roommate.
      # ccpv3_demo=> select * from _nde where stk_id in (1396788,1396790)
      #                                   and brn_id = 2538452;
      #  stk_id  | v | ref_n |start_rid|until_rid |           nd_xy           
      # ---------+---+-------+---------+----------+---------------------------
      #  1396790 | 1 |     4 |        1|2000000000| POINT(491994.4 4976656.9)
      #  1396788 | 1 |     2 |        1|2000000000| POINT(491994.4 4976656.9)
      #self.debug_just_ids = (1131454,)
      #
      # Actually, a better way to debug: byways are fetched and ordered by 
      # stack ID, so we just need to run the script until a problem happens, 
      # and then re-run the script starting with the stack ID that failed.
      self.debug_sids_from = None
      #self.debug_sids_from = 1519735 # The last Ccp ID in Bikeways Shapefile.
      #self.debug_sids_from = 1519337 # 9 IDs (split-sets) back from the last.
      #self.debug_sids_from = 1069739 # 2012.07.31: 1/3 through Bikeways
      #self.debug_sids_from = 1484469 # New geom marked _NEW_GEOM but with CCP
                                     # ID, and m_vals are both 1.0 because this
                                     # line segment just wants the byway's
                                     # attrs and not its geometry.
      #self.debug_sids_from = 1484463 # Related to previous; I combined two Ccp
                                     # byways into 1 and added a connecting 
                                     # segment, so there are three segs: one 
                                     # is a split-into, but it actually
                                     # resegmentizes the two Ccp byways; the
                                     # second is marked _DELETE and takes out 
                                     # the other byway being resegmentized;
                                     # the third is the new connector segment
                                     # (to link the other byway to the rest of 
                                     # the network).
      # 2013.04.26: [lb] hasn't imported in a while. 1.) CcpV3
      # (Statewide) changed a lot of code (including access_style_id and
      # style_change). 2.) My Arc license recently expired so the latest
      # shapefile was saved using OpenJump. 3.) I'm may have fixed some little
      # bugs in the import scripts along the way. Which is three things that
      # have changed since I last ran the import. But none of these convince me
      # why importing the Bikeways shapefile is now causing me problems. It's
      # a split segment, split into two automatically by RoadMatcher. One
      # segment is marked FIXME, and one is marked IMPORT, and one of them
      # (that latter, I think) fails being made as a Split_Defn() (from
      # splitset_assemble_segments in import_items_ccp): self.m_fin_fix <=
      # self.m_beg_fix, which means the final m-value is less than or equal to
      # the first m-value. 2013.04.26 UPDATE: Andrew O. had edited the a
      # feature's geometry but hadn't marked the feature _NEW_GEOM, and I
      # had an assert where I should really have had move-feature-to-fixme
      # and log-warning actions instead.
      # ANYWAY: Remember, use debug_sids_from, and don't use debug_just_ids.
      # No: self.debug_just_ids = (1133691,) # Argh. This doesn't hit...
      #self.debug_sids_from = 1133691 # Oh, wait, debug_just_ids is retired
      #                               # and using debug_sids_from works great!
      #self.debug_sids_from = 1140760 # 2013.04.27 (But really still the 26th.)
      # The last two features had geometry edited that was not marked
      # _NEW_GEOM, so they had unexpected m-values (geom_is_golden was
      # FALSE so we were checking geometry against the existing byway).
      # I changed the asserts to warnings.
      # FIXME: Features with edited geometry without _NEW_GEOM should be moved
      #        to FIXME layer. Right now, they are imported, their geometry is
      #        ignored, and a warning is logged.
# BUG nnnn: Log to a text file in /ccp/var/dbdumps/{UUID} and include in the
#           download package.

# FIXME_2013_06_11: Revisit this.
      # FIXME: Implement this for new and unconflated features, which we
      #        examine one-by-one.
      self.debug_fids_from = None

      # Set the database connection database. This is just so developers can 
      # use a database other than the one named in CONFIG (so you can update a
      # new database while apache still runs the old one). 
      #
      # NOTE: This is just like script_args '--database, but we're running a
      # job, so we can't use that switch. See also self.spf_conf.db_override.
      #
      debug_db_name_ = None
      #debug_db_name_ = 'ccpv3'
      if debug_db_name_:
         db_glue.DB.set_db_name(self.debug.debug_db_name)
      # else, we'll just use the default, conf.db_name.

      # This is shorthand for if one of the above is set.
      self.debugging_enabled = (   self.debug_skip_splits 
                                or self.debug_skip_saves
                                or self.debug_skip_attrs 
                                or self.debug_prog_log.debug_break_loops
                                or self.debug_skip_commit
                                or self.debug_just_ids
                                )

      if self.debugging_enabled:
         log.warning('****************************************')
         log.warning('*                                      *')
         log.warning('*      WARNING: debugging_enabled      *')
         log.warning('*                                      *')
         log.warning('****************************************')

      # *** Behavior switches

      # [lb] On 2011.08.29, I had a memory usage problem. 2 Gb of physical 
      # and 6 Gbs of swap memory were being used. I initially thought maybe
      # Postgres was having a problem with such a large transaction. I added 
      # the self.use_multiple_commits switch to commit the database after each
      # group of item types was processed (standins, standups, matched, etc.).
      # But circa Spring, 2012, I discovered the beauty of using psycopg2's 
      # fetchone instead of fetchall. So rather than loading all byways into
      # memory on boot, we just do 'em one-by-one as we go through the
      # Shapefile.
      #
      # Furthermore, using multiple commits is just a developer hack: if we
      # allowed the client to use multiple commits, it'd really screw up the
      # ability to cancel (or suspend) an import job, since we'd then have to
      # run a revert on anything we'd previously committed. So I've since
      # removed the self.use_multiple_commits switch.

      # The conflated Shapefile indicates features that must be split, or
      # segmentized. Sometimes the segmented geometry is included in the
      # Shapefile, and sometimes we have to reconstruct it. If you always want
      # to reconstruct segmented geometry, enable this switch. (When Cyclopath
      # segments geometry, it uses the (x,y) endpoints from the Shapefile and
      # feeds them to PostGIS along with the unsplit feature; the result is the
      # new geometry, as calculated by PostGIS, between those two endpoints.)
      # FIXME: This setting might only pertain to RoadMatcher.
      # FIXME: Is one method preferable over the other?
      self.split_with_all_new_features = False

      # Internally, Cyclopath deals with (x,y) coordinate pairs only to a
      # certain precision. Generally, you want your endpoint values to be 
      # set according to this precision. I.e., rather than using the raw 
      # endpoint (x,y) values from the Shapefile as floats, we convert the 
      # floats to Decimal types. Set this switch if you don't want to use 
      # Decimals but would rather just use floats (though this is not 
      # recommended and should only be used for testing and exploring).
      self.split_dont_replace_xy_endpoints = False

# ***

if (__name__ == '__main__'):
   pass

