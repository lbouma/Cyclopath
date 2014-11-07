/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho This script adds link_value lhs_stack_id and rhs_stack_id to gia...
\qecho 



FIXME/MAYBE: Do this???




BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;


/* ==================================================================== */
/* Step                                                                 */
/* ==================================================================== */

\qecho
\qecho

ALTER TABLE group_item_access ADD COLUMN lhs_stack_id INTEGER;
ALTER TABLE group_item_access ADD COLUMN rhs_stack_id INTEGER;

UPDATE group_item_access AS gia
 SET lhs_stack_id = (
   SELECT lv.lhs_stack_id FROM link_value AS lv
   WHERE lv.system_id = gia.item_id);
UPDATE group_item_access AS gia
 SET rhs_stack_id = (
   SELECT lv.rhs_stack_id FROM link_value AS lv
   WHERE lv.system_id = gia.item_id);

DROP INDEX IF EXISTS group_item_access_lhs_stack_id;
CREATE INDEX group_item_access_lhs_stack_id
   ON group_item_access (lhs_stack_id);
-- UPDATE 2404369
-- Time: 377498.560 ms

DROP INDEX IF EXISTS group_item_access_rhs_stack_id;
CREATE INDEX group_item_access_rhs_stack_id
   ON group_item_access (rhs_stack_id);
-- UPDATE 2404369
-- Time: 906405.590 ms

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

