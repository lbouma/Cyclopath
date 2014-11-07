/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho Add new geofeature layer IDs.
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
\qecho Add new geofeature layer IDs.
\qecho

/* NOTE: Skipping, e.g., INSERT INTO draw_class, because the skin files
         handle all the draw parameters, like widths and colors. */

INSERT INTO geofeature_layer (
   id, feat_type, layer_name, geometry_type, restrict_usage,
   draw_class_owner, draw_class_arbiter, draw_class_editor, draw_class_viewer
   -- last_modified
   ) VALUES (
      -- Hrmm... "Railroad"? "Railway"? "Rail transport"?
      43, 'byway', 'Railway', 'LINESTRING', FALSE,
      11, 11, 11, 11);

/* This is lakes, ponds, reservoirs, etc. */
/* BUG nnnn: Consolidate  */
INSERT INTO geofeature_layer (
   id, feat_type, layer_name, geometry_type, restrict_usage,
   draw_class_owner, draw_class_arbiter, draw_class_editor, draw_class_viewer
   -- last_modified
   ) VALUES (
      113, 'terrain', 'Waterbody', 'POLYGON', FALSE,
      11, 11, 11, 11);

/* This is rivers, streams, ditches. */
INSERT INTO geofeature_layer (
   id, feat_type, layer_name, geometry_type, restrict_usage,
   draw_class_owner, draw_class_arbiter, draw_class_editor, draw_class_viewer
   -- last_modified
   ) VALUES (
      114, 'terrain', 'Flowline', 'LINESTRING', FALSE,
      11, 11, 11, 11);

/*

FIXME: Because of z-level, there should not be endpoints with same x,y, right?!

Metro area:

No. Cyclopath nodes being used by two or more intersections: 1184

_ins_new_nde: 2+ ids on nd xy: best: node_stack_id: 1277335
_ins_new_nde: row: {'stack_id': 1277335, 'branch_id': 2538452, 'version': 1,
                    'system_id': 1160267, 'reference_n': 4}
_ins_new_nde: row: {'stack_id': 1361115, 'branch_id': 2538452, 'version': 1,
                    'system_id': 1216846, 'reference_n': 0}

E.g.,
  SELECT * FROM _nde WHERE stk_id IN (1277335, 1361115);
Or,
  SELECT * FROM node_endpt_xy
   WHERE endpoint_xy = ST_GeomFromText('POINT(475959.3 5009706)', cp_srid());

*/

/* MAGIC_NUMBERS: See: http://nhd.usgs.gov/
   And: http://nhd.usgs.gov/NHDv2.0_poster_6_2_2010.pdf
   */
/*
NHDWaterbody / FType
493 Estuary    [MnDOT: None]
378 Ice Mass   [MnDOT: None]
361 Praya      [MnDOT: None]
436 Reservoir  [MnDOT:  1944]
466 SwampMarsh [MnDOT: 11624]
390 LakePond   [MnDOT: 198675] [Default]
   Most: Perennial (FCode 39004 cnt: 148896
                          39009 cnt: 438
                          39011 cnt: 778
                          39010 cnt: 7
                          39012 cnt: 1)
   Others: Intermittent (FCode 39001 cnt: 10432
                               39006 cnt: 21
                               39005 cnt: 4)  
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

