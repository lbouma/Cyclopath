/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Drop recently deprecated columns.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

ALTER TABLE route DROP COLUMN COLUMN host_TBD;
ALTER TABLE route DROP COLUMN COLUMN created_TBD;
ALTER TABLE route DROP COLUMN COLUMN source_TBD;

ALTER TABLE track DROP COLUMN permission_TBD;
ALTER TABLE track DROP COLUMN visibility_TBD;
ALTER TABLE track DROP COLUMN source_TBD;
ALTER TABLE track DROP COLUMN created_TBD;
ALTER TABLE track DROP COLUMN host_TBD;

ALTER TABLE group_item_access DROP COLUMN created_by_TBD;
ALTER TABLE group_item_access DROP COLUMN date_created_TBD;

ALTER TABLE item_stack DROP COLUMN creator_name_TBD;

ALTER TABLE revision DROP COLUMN permission_TBD;
ALTER TABLE revision DROP COLUMN visibility_TBD;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

