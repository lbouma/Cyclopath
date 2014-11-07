/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script fixes geofeature_layer so it supports items of different access 
   levels. That is, so it can tell the client to draw item types differently 
   based on the user's access to those items. */

\qecho 
\qecho This script fixes geofeature_layer to support items of different access
\qecho levels, so private items can be drawn differently than public items.
\qecho It also archives a few, old public tables dealing with access control.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Fix geofeature_layer                                      */
/* ==================================================================== */

\qecho 
\qecho Adding draw class ID columns to geofeature_layer for each access level
\qecho 

ALTER TABLE geofeature_layer ADD COLUMN draw_class_owner INTEGER;
ALTER TABLE geofeature_layer ADD COLUMN draw_class_arbiter INTEGER;
ALTER TABLE geofeature_layer ADD COLUMN draw_class_editor INTEGER;
ALTER TABLE geofeature_layer ADD COLUMN draw_class_viewer INTEGER;

/* FIXME: Do we need indices?
CREATE INDEX geofeature_layer_draw_class_owner 
   ON geofeature_layer (draw_class_owner);
CREATE INDEX geofeature_layer_draw_class_arbiter 
   ON geofeature_layer (draw_class_arbiter);
CREATE INDEX geofeature_layer_draw_class_editor 
   ON geofeature_layer (draw_class_editor);
CREATE INDEX geofeature_layer_draw_class_viewer 
   ON geofeature_layer (draw_class_viewer);
*/

\qecho 
\qecho Setting defaults values for the new columns
\qecho 

UPDATE geofeature_layer SET draw_class_owner = draw_class_id;
UPDATE geofeature_layer SET draw_class_arbiter = draw_class_id;
UPDATE geofeature_layer SET draw_class_editor = draw_class_id;
UPDATE geofeature_layer SET draw_class_viewer = draw_class_id;

/* ==================================================================== */
/* Step (2) -- Watch Regions -- Convert to simple regions || PART 2/2   */
/* ==================================================================== */

/* NOTE See the previous script for PART 1/2. */

\qecho 
\qecho Applying old watch region draw class to region owner column
\qecho 

UPDATE geofeature_layer 
   SET draw_class_owner = (SELECT draw_class_id FROM geofeature_layer 
                           WHERE feat_type = 'region_watched')
   WHERE feat_type = 'region';

\qecho 
\qecho Making region_work_hint a region with layer set to 'work_hint'
\qecho 

UPDATE geofeature_layer 
   SET (feat_type, layer_name) = ('region', 'work_hint')
   WHERE feat_type = 'region_work_hint';

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

