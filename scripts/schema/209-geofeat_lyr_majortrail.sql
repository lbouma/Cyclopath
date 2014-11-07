/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the 'major trail' geofeature layer type. */

\qecho 
\qecho This script adds new geofeature layer types:
\qecho 'Major Trail' and 'Alleyway'
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho 
\qecho Add Major Trail to geofeature_layer
\qecho 

/*
id |     text     |         last_modified         |  color   
----+--------------+-------------------------------+----------
 41 | super        | 2007-11-19 15:59:31.8362-06   | 15908644
 11 | small        | 2007-03-05 16:08:58.72922-06  | 16777215
 21 | medium       | 2007-03-05 16:08:58.72922-06  | 16775795
 31 | large        | 2007-03-05 16:08:58.72922-06  | 16775795
  1 | shadow       | 2010-03-29 17:02:51.852329-05 | 16777215
  6 | watch_region | 2008-08-23 15:40:55.893769-05 | 16711680
  4 | background   | 2010-03-29 17:02:51.852329-05 | 14075316
  3 | water        | 2010-03-29 17:02:51.852329-05 |  8828110
  5 | point        | 2010-03-29 17:02:51.852329-05 |  8537053
  8 | route        | 2010-03-29 17:02:51.852329-05 |  8835271
  9 | region       | 2010-03-29 17:02:51.852329-05 |  6710886
 10 | track        | 2011-07-13 21:01:38.746757-05 |    39168
 12 | bike_trail   | 2012-04-18 13:58:46.169863-05 | 14663679
*/

/* SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   MAGIC_NUMBER: 22 is 'Major Trail' (Bike_Trail), or 21 (Major_Road) + 1.
 */
/* MAGIC_NUMBER/DOESN'T MATTER: The color value (14663679)
                                is overridden by the skin. */
/*
INSERT INTO draw_class (
   id,
   text,
   --last_modified,
   color
   )
   VALUES (
      '22',
      'major_trail',
      14663679);
*/

INSERT INTO geofeature_layer (
   id,
   feat_type, 
   layer_name, 
   geometry_type, 
   restrict_usage,
   -- last_modified
   draw_class_owner,
   draw_class_arbiter,
   draw_class_editor,
   draw_class_viewer
   )
   VALUES (
      22,
      'byway', 
      'Major Trail', 
      'LINESTRING', 
      FALSE,
      21,
      21,
      21,
      21);

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho 
\qecho Add Alleyway to geofeature_layer
\qecho 

/*
ccpv3_demo=> select id, feat_type, layer_name from geofeature_layer
               where feat_type = 'byway' order by id;
 id  | feat_type |   layer_name    
-----+-----------+-----------------
   1 | byway     | Unknown       # Uses draw_class id=11
   2 | byway     | Other         # Uses draw_class id=11
  11 | byway     | Local Road    # Uses draw_class id=11
  14 | byway     | Bicycle Path  # Uses draw_class id=12
  15 | byway     | Sidewalk      # Uses draw_class id=12
  16 | byway     | Doubletrack   # Uses draw_class id=12
  17 | byway     | Singletrack   # Uses draw_class id=12
  21 | byway     | Major Road    # Uses draw_class id=21
  22 | byway     | Major Trail   # Uses draw_class id=22
  31 | byway     | Highway       # Uses draw_class id=31
  41 | byway     | Expressway    # Uses draw_class id=41
  42 | byway     | Expressway Ramp # Uses draw_class id=11
(12 rows)

# BUG nnnn: 'Singletrack' should be a dashed link, or
            maybe just draw_class id=11.
# Bug nnnn: Should 'Sidewalk' use draw_class id=11?

ccpv3_demo=> select * from draw_class order by id;
 id |     text     |         last_modified         |  color   
----+--------------+-------------------------------+----------
  1 | shadow       | 2010-03-29 17:02:51.852329-05 | 16777215
  2 | open_space   | 2013-05-23 01:29:04.710143-05 |  7969073
  3 | water        | 2010-03-29 17:02:51.852329-05 |  8828110
  4 | background   | 2010-03-29 17:02:51.852329-05 | 14075316
  5 | point        | 2010-03-29 17:02:51.852329-05 |  8537053
  6 | watch_region | 2008-08-23 15:40:55.893769-05 | 16711680
  7 | work_hint    | 2013-05-23 01:29:04.710143-05 |  8912896
  8 | route        | 2010-03-29 17:02:51.852329-05 |  8835271
  9 | region       | 2010-03-29 17:02:51.852329-05 |  6710886
 10 | track        | 2011-07-13 21:01:38.746757-05 |    39168
 11 | small        | 2007-03-05 16:08:58.72922-06  | 16777215
 12 | bike_trail   | 2013-05-23 01:29:04.710143-05 | 14663679
 21 | medium       | 2007-03-05 16:08:58.72922-06  | 16775795
 22 | major_trail  | 2013-05-23 04:09:19.469748-05 | 14663679
 31 | large        | 2007-03-05 16:08:58.72922-06  | 16775795
 41 | super        | 2007-11-19 15:59:31.8362-06   | 15908644

*/

/* SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   MAGIC_NUMBER: 22 is 'Alleyway'. Since 11 is small...
 */
/* MAGIC_NUMBER/DOESN'T MATTER: The color value (14663679)
                                is overridden by the skin. */
/*
INSERT INTO draw_class (
   id,
   text,
   --last_modified,
   color
   )
   VALUES (
      '51',
      'teeny',
      14663679);
*/

INSERT INTO geofeature_layer (
   id,
   feat_type, 
   layer_name, 
   geometry_type, 
   restrict_usage,
   -- last_modified
   draw_class_owner,
   draw_class_arbiter,
   draw_class_editor,
   draw_class_viewer
   )
   VALUES (
      18,
      -- WRONG: 'byway_alley',
      -- See: scripts/schema/219-fix_deleted_tag_et_al.sql
      'byway',
      'Alley',
      'LINESTRING',
      FALSE,
      11,
      11,
      11,
      11);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

