/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho Fix scope of Session ID Group from shared to public.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Changing scope of Session ID Group.
\qecho

UPDATE group_ SET access_scope_id = cp_access_scope_id('public')
   WHERE name = 'Session ID Group';

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

/*
   BUG nnnn: Improve route search:
             Search route length,
                    route region (e.g., part of the state)
                    route last edited
                    and many, many more.
*/

\qecho
\qecho Creating column, indices and triggers for route full text search.
\qecho

ALTER TABLE route ADD COLUMN tsvect_details tsvector;
UPDATE route SET tsvect_details =
     to_tsvector('english', coalesce(details, ''));
CREATE INDEX route_tsvect_details 
   ON route USING gin(tsvect_details);
CREATE TRIGGER route_tsvect_details_trig 
   BEFORE INSERT OR UPDATE ON route 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_details, 'pg_catalog.english', details);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

