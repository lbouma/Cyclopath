/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho This script creates indices on log_event.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Indicing log_event.
\qecho

/* These indices were also added to db_load_add_constraints.sql. We need these
   so we can go through log_event and send flashclient errors to the branch
   manager. */

DROP INDEX IF EXISTS log_event_created;
CREATE INDEX log_event_created ON log_event (created);

DROP INDEX IF EXISTS log_event_facility;
CREATE INDEX log_event_facility ON log_event (facility);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

