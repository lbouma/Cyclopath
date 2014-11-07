/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the 'private road' geofeature layer type. */

\qecho 
\qecho This script adds new geofeature layer type(s) and Travel Mode(s).
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
\qecho Add new geofeature_layer types
\qecho 

/*

SYNC_ME/MAGIC_NUMBER: The geofeature_layer_id is just a unique, made up number.

See:

  SELECT id, feat_type, layer_name, geometry_type FROM _gfl ORDER BY id;

 id  | feat_type |   layer_name    | geometry_type 
-----+-----------+-----------------+---------------
   1 | byway     | Unknown         | LINESTRING
   2 | byway     | Other           | LINESTRING
  11 | byway     | Local Road      | LINESTRING
  14 | byway     | Bicycle Path    | LINESTRING
  15 | byway     | Sidewalk        | LINESTRING
  16 | byway     | Doubletrack     | LINESTRING
  17 | byway     | Singletrack     | LINESTRING
  18 | byway     | Alley           | LINESTRING
  21 | byway     | Major Road      | LINESTRING
  22 | byway     | Major Trail     | LINESTRING
  31 | byway     | Highway         | LINESTRING
  41 | byway     | Expressway      | LINESTRING
  42 | byway     | Expressway Ramp | LINESTRING
  43 | byway     | Railway         | LINESTRING
  44 | byway     | Private Road    | LINESTRING      **** NEW ****
  51 | byway     | Other Ramp      | LINESTRING      **** NEW ****
  52 | byway     | Parking Lot     | LINESTRING      **** NEW ****
 101 | terrain   | openspace       | POLYGON
 102 | terrain   | water           | POLYGON
 103 | waypoint  | default         | POINT
 104 | region    | default         | POLYGON
 105 | route     | default         | POLYGON
 106 | track     | default         | POLYGON
 108 | region    | work_hint       | POLYGON
 109 | branch    | default         | POLYGON
 113 | terrain   | Waterbody       | POLYGON
 114 | terrain   | Flowline        | LINESTRING
(24 rows)

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
      44,
      'byway', 
      'Private Road', 
      'LINESTRING', 
      FALSE,
      21,
      21,
      21,
      21);

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
      51,
      'byway', 
      'Other Ramp', 
      'LINESTRING', 
      FALSE,
      21,
      21,
      21,
      21);

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
      52,
      'byway', 
      'Parking Lot', 
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
\qecho Add new travel_mode
\qecho 

INSERT INTO travel_mode (id, descr) VALUES (5, 'generic');

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

