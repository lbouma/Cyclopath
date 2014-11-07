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
\qecho Setting constraints on new draw class columns
\qecho 

ALTER TABLE geofeature_layer ALTER COLUMN draw_class_owner SET NOT NULL;
ALTER TABLE geofeature_layer ALTER COLUMN draw_class_editor SET NOT NULL;
ALTER TABLE geofeature_layer ALTER COLUMN draw_class_viewer SET NOT NULL;

ALTER TABLE geofeature_layer 
   ADD CONSTRAINT geofeature_layer_draw_class_owner_fkey
   FOREIGN KEY (draw_class_owner) 
   REFERENCES draw_class (id) DEFERRABLE;
ALTER TABLE geofeature_layer 
   ADD CONSTRAINT geofeature_layer_draw_class_editor_fkey
   FOREIGN KEY (draw_class_editor) 
   REFERENCES draw_class (id) DEFERRABLE;
ALTER TABLE geofeature_layer 
   ADD CONSTRAINT geofeature_layer_draw_class_viewer_fkey
   FOREIGN KEY (draw_class_viewer) 
   REFERENCES draw_class (id) DEFERRABLE;

/* ==================================================================== */
/* Step (3) -- Cleanup geofeature_layer table                           */
/* ==================================================================== */

\qecho 
\qecho Cleaning up geofeature_layer table
\qecho 

DELETE FROM geofeature_layer WHERE feat_type = 'region_watched';

/* ==================================================================== */
/* Step (4) -- Archive old stuff                                        */
/* ==================================================================== */

\qecho 
\qecho Archiving old access control stuff.
\qecho 

/* FIXME minnesota.revision depends on table permissions */
/*       revision.permission is always 1: public */
ALTER TABLE permissions SET SCHEMA archive_1;
ALTER TABLE visibility SET SCHEMA archive_1;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

