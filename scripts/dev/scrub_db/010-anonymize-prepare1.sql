/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This scripts drop constraints and indexes columns so that the next few
   scripts run efficiently. */

/* Tell schema-update to run this script as -U Postgres, since only sudo can
   new make schemas:

      @run-as-superuser 
   
   */

\qecho 
\qecho This script drops constraints and indexes columns so that the next
\qecho few scripts run efficiently.
\qecho 
--\qecho [EXEC. TIME: 2011.04.25/Huffy: ~ x mins (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.02.12: 0.01 mins. [runic]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

--SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop constraints and index columns                       */
/* ==================================================================== */

DROP INDEX IF EXISTS user__dont_study;
CREATE INDEX user__dont_study ON user_ (dont_study);

DROP INDEX IF EXISTS user__username;
CREATE INDEX user__username ON user_ (username);

DROP INDEX IF EXISTS auth_fail_event_username;
CREATE INDEX auth_fail_event_username ON auth_fail_event (username);

DROP INDEX IF EXISTS ban_username;
CREATE INDEX ban_username ON ban (username);

DROP INDEX IF EXISTS user_preference_event_username;
CREATE INDEX user_preference_event_username 
   ON user_preference_event (username);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

