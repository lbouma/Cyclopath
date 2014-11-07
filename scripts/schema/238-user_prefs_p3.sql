/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho
\qecho Alter user and user prefs tables
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Maybe update user tables for clients                     */
/* ==================================================================== */

\qecho
\qecho Updating user tables for installs that did not run bad 234 script.
\qecho

/* NOTE: [lb] screwed up and had public-schema commands mixed in with
         schema-specific commands (in 234-byway-is_disconnected.sql),
         but the problem wasn't detected because we're only running one
         instance (Minnesota) since having taken Colorado offline...
         so we need an exceptionable upgrade function. */

DROP FUNCTION IF EXISTS update_user_tables();

CREATE FUNCTION update_user_tables()
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         ALTER TABLE user_ ADD COLUMN rf_use_bike_facils BOOLEAN DEFAULT FALSE;
         ALTER TABLE user_ ADD COLUMN rf_p3_weight_type TEXT DEFAULT 'len';
         -- MAGIC_NUMBERS: Defaults used in ccp.py, Conf.as, route_get.py,
         --                and 234-byway-is_disconnected.sql; see the value
         --                sets, pyserver/planner/routed_p3/tgraph.py's
         --                Trans_Graph.rating_pows and burden_vals.
         ALTER TABLE user_ ADD COLUMN rf_p3_burden_pump INTEGER DEFAULT 10;
         ALTER TABLE user_ ADD COLUMN rf_p3_spalgorithm TEXT DEFAULT 'as*';

         ALTER TABLE user_preference_event
            ADD COLUMN rf_use_bike_facils BOOLEAN;
         ALTER TABLE user_preference_event
            ADD COLUMN rf_p3_weight_type TEXT;
         ALTER TABLE user_preference_event
            ADD COLUMN rf_p3_burden_pump INTEGER;
         ALTER TABLE user_preference_event
            ADD COLUMN rf_p3_spalgorithm TEXT;
      EXCEPTION 
         WHEN OTHERS THEN
            /* E.g., "ERROR: constraint "..." does not exist" */
            /* No-op. */
            RAISE INFO 'Skipping 234 fix: user tables previously updated.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT update_user_tables();

DROP FUNCTION update_user_tables();

/* ==================================================================== */
/* Step (2) -- Update user tables                                       */
/* ==================================================================== */

\qecho
\qecho Updating user tables
\qecho

-- MAGIC_NUMBERS: Defaults used in ccp.py, Conf.as, route_get.py,
--                and 234-byway-is_disconnected.sql; see the value
--                sets, pyserver/planner/routed_p3/tgraph.py's
--                Trans_Graph.rating_pows and burden_vals.
ALTER TABLE user_ ADD COLUMN rf_p3_rating_pump INTEGER DEFAULT 4;
ALTER TABLE user_ ALTER COLUMN rf_p3_burden_pump SET DEFAULT 20;

ALTER TABLE user_preference_event ADD COLUMN rf_p3_rating_pump INTEGER;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

