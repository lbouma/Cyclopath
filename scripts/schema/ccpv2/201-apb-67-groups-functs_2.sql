/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script [is a no-op/documentation]. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script [is a no-op/documentation].
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Discuss CcpV1 instance schema                            */
/* ==================================================================== */

/* See 102-apb-53-access-fcns____.sql for a discussions on Cyclopath's 
   SQL functions.

   In that script, we updated the public schema; in this script, we update 
   functions in the instance schemas.
   2013.08.06: Well, that was the intent of this script. I [lb] think all
               the FIXMEs herein can be ignored, since minnesota is working
               well and we don't care about colorado (well, we _care_ about
               Colorado, but we don't need to maintain any of the
               non-conformist psql entities that the colorado schema uses,
               like tiger_bs.)

   ==================================================
   Instance schemas (minnesota and colorado)

   FUNCTIONS

      Instance SRID:

         srid

      GIS export:

         has_tag

   Colorado has a few fcns not shared.

   FIXME Can we delete these?

      colorado.cdot_nearest (used by VIEW cdot_bs_best)

   FIXME Colorado-specific TABLES

      colorado.cdot_bs    FIXME Consume 'unpaved'? 
                                What's h_id, h_distance, h_length?
                                Did the other columns get consumed?
      colorado.tiger_bs   FIXME Make this an attr
      colorado.tiger_lines
      colorado.cdot_bs_route
      colorado.cdot_codes
      colorado.cdot_highways
      colorado.cdot_roads
      colorado.cdot_route_cache
      colorado.drcog_bike
      colorado.drcog_boundary
      colorado.drcog_parks
      colorado.tiger_codes
      colorado.tiger_nodes
      colorado.usgs_nhd

   FIXME Colorado-specific VIEWS

      colorado.tiger_bs_divided
      colorado.cdot_bs_best
      colorado.cdot_valid_route_names AS

   FIXME Colorado-only sequences

      colorado.cdot_highways_ogc_fid_seq
      colorado.cdot_roads_ogc_fid_seq
      colorado.drcog_bike_ogc_fid_seq
      colorado.drcog_ogc_fid_seq
      colorado.drcog_parks_ogc_fid_seq
      colorado.tiger_lines_ogc_fid_seq
      colorado.usgs_nhd_ogc_fid_seq

   SEQUENCES

      apache_event_id_seq
      apache_event_session_id_seq
      byway_rating_event_id_seq
      --group__group_id_seq
      item_read_event_id_seq
      item_stack_stack_id_seq
      log_event_id_seq
      --new_item_policy_id_seq
      revert_event_id_seq
      revision_feedback_id_seq
      revision_id_seq
      route_feedback_id_seq
      route_feedback_drag_id_seq
      route_feedback_stretch_id_seq
      route_reaction_id_seq
      route_view_id_seq
      tag_preference_event_id_seq

   VIEWS

      [attc]_geo
      [attc]_[feat]_geo
      gf_[feat]
      iv_*
      iv_cur_[attc]
      post_revision_geo
      annotation_region_watched_geo
      node_usage
      node_usage_count

*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

