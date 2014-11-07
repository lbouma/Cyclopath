/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the 'private road' geofeature layer type. */

\qecho 
\qecho This script adds new landmark item types.
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
\qecho Add new item types
\qecho 

INSERT INTO item_type (id, type_name) VALUES (56, 'landmark');
INSERT INTO item_type (id, type_name) VALUES (57, 'landmark_t');
INSERT INTO item_type (id, type_name) VALUES (58, 'landmark_other');

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

