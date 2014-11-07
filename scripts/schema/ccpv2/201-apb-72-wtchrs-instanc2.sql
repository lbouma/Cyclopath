/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script drops a few columns we no longer need. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script drops columns obsoleted by permissions and branching.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop obsoleted columns                                   */
/* ==================================================================== */

\qecho 
\qecho Dropping username and notify_email columns from geofeature
\qecho 

/* The geofeature's username column was used for private watch regions. */
ALTER TABLE geofeature DROP COLUMN username;
/* The notify_email column was used for watching private regions. */
ALTER TABLE geofeature DROP COLUMN notify_email;

/* ==================================================================== */
/* Step (2) -- Add triggers                                             */
/* ==================================================================== */

CREATE TRIGGER item_read_event_ic
   BEFORE INSERT ON item_read_event
   FOR EACH ROW EXECUTE PROCEDURE public.set_created();

CREATE TRIGGER item_read_event_ir
   BEFORE INSERT ON item_read_event
   FOR EACH ROW EXECUTE PROCEDURE public.cp_set_created_rid();

ALTER TABLE item_read_event DISABLE TRIGGER item_read_event_ic;
ALTER TABLE item_read_event DISABLE TRIGGER item_read_event_ir;

/* ==================================================================== */
/* Step (3) -- Reenable triggers                                        */
/* ==================================================================== */

ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_i;
ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_u;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

