/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This (very destructive!) script removes work hints tables no longer needed
   after the experiment is over. */

begin;

/* work hints detritus */
drop function wh_during_trial(text, timestamp);
drop table wh_viewport_familiarity;
drop table wh_viewport;
drop view wh_familiarity;
drop table wh_point_familiarity;
drop table wh_byway_familiarity;
drop table wh_view_event;
drop table wh_point_viewdetails_event;
drop table wh_byway_viewdetails_event;
drop table wh_work_hint_defer;
drop table wh_trial_rating_needed;
drop table wh_trial;
drop table wh_user;

/* general cleanup */
drop table bikeways_qgis;
drop view exp_point;
drop view exp_point_comment;
drop table exp_byway_comments;
drop table exp_point_comments;
drop view exp_rating_byway;
drop table exp_rating;
drop view tis_basemap_joined;
drop table tisdata;
drop view mndot_basemap;
drop view mndot_bikeways;
drop table mndot_basemap_muni;
drop table mndot_basemap_tweaked;
drop table mndot_bikeways_tweaked;
drop table overlap_bike_paths_200903;

commit;
