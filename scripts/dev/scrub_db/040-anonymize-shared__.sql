/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script can be used to scrub the database of private user data, so you
   (the developer) can copy the database to a laptop or a home development
   machine and not have to worry about (per University and Federal policy
   regarding protecting human subjects). */

\qecho 
\qecho This script strips the database of private user information for research
\qecho subjects (developer user information is retained, i.e., your login and
\qecho mine).
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 11.13 mins (V2 / incl. mn. and co.).]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~  0.26 mins (V2 / incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.02.13/runic: ~  6.80 mins (V2 / 'lite' mn only.).]
\qecho 

/* FIXME: Can this script's execution time be shortened? */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

/* ==================================================================== */
/* Step (1) -- Create a bunch of helper fcns.                           */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

CREATE FUNCTION scrub_user(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      RAISE NOTICE '.. %', uname;
      DELETE FROM auth_fail_event WHERE username = uname;
      DELETE FROM ban WHERE username = uname;
      DELETE FROM user_preference_event WHERE username = uname;
      /* Delete the user's actual user_ entry */
      DELETE FROM user_ WHERE username = uname;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_users()
   RETURNS VOID AS $$
   DECLARE
      user_rec RECORD;
   BEGIN
      /* Scrub public users, i.e., dont_study is TRUE for developers, and
       * username starts with an underscore for 'bots'. */
      FOR user_rec IN 
         SELECT username, id, alias FROM user_ 
            WHERE dont_study = FALSE 
               AND username NOT LIKE E'\\_%'
            ORDER BY username ASC 
      LOOP
         PERFORM scrub_user(user_rec.username);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Scrubbing users from public schema
\qecho 

SELECT scrub_users();
-- TESTING:
--SELECT scrub_users_rows('000cml', 1913, 'xiomara_mcglothin');

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION scrub_users();
DROP FUNCTION scrub_user(IN uname TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 
\qecho (but please be patient on the commit...)
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;

