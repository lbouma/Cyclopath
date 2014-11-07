/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Add p3 planner column
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Update route table with new p3 planner column.
\qecho

/* The edge weight on which the planner decides. */
ALTER TABLE @@@instance@@@.route ADD COLUMN p3_weight_attr TEXT;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Update route_stop table with a few good attrs.
\qecho

ALTER TABLE @@@instance@@@.route_stop ADD COLUMN internal_system_id INTEGER
   DEFAULT -1;
ALTER TABLE @@@instance@@@.route_stop ADD COLUMN external_result BOOLEAN
   DEFAULT FALSE;

/*

[lb] doesn't remember having an issue with not having defaults or not null,
but if your column is not NOT NULL DEFAULT x, then psycopg2 complains, e.g.:

sql: programming: ERROR:  column "internal_system_id" is of type integer
but expression is of type boolean LINE 1: ...o Harbors, MN 55616', 3829627,
0, false, 2768336, false, 521...

when you try to insert data. Or maybe it's our item_base.py module. Who knows.
Anyway, add defaults so db_glue works...

*/

UPDATE route_stop SET internal_system_id = -1;
UPDATE route_stop SET external_result = FALSE;

ALTER TABLE @@@instance@@@.route_stop ALTER COLUMN internal_system_id
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_stop ALTER COLUMN external_result
   SET NOT NULL;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

