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
/* Step (1) -- Fix the last_modified triggers                           */
/* ==================================================================== */

CREATE TRIGGER enum_definition_i
   BEFORE INSERT ON enum_definition
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER enum_definition_u
   BEFORE UPDATE ON enum_definition
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

