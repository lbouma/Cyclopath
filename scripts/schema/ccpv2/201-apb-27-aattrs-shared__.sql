/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Fix the last_modified triggers. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

\qecho 
\qecho Fix the last_modified triggers
\qecho 

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Enable the last_modified triggers                        */
/* ==================================================================== */

ALTER TABLE geofeature_layer ENABLE TRIGGER geofeature_layer_i;
ALTER TABLE geofeature_layer ENABLE TRIGGER geofeature_layer_u;

/* ==================================================================== */
/* Step (2) -- Rename draw_class texts to match convention              */
/* ==================================================================== */


\qecho 
\qecho Updating draw_class text columns
\qecho 

/* SYNC_ME: Search draw_class table. */
UPDATE draw_class SET text = 'bike_trail' WHERE text = 'biketrail' AND id = 12;
UPDATE draw_class SET text = 'open_space' WHERE text = 'openspace' AND id = 2;
UPDATE draw_class SET text = 'work_hint' WHERE text = 'workhint' AND id = 7;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

