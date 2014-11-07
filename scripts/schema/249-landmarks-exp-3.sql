/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the tables for the validation part of the landmarks
experiment. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script creates the landmark experiment tables.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* */

CREATE FUNCTION cp_alter_table_landmark_exp_route_1()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

      ALTER TABLE landmark_exp_route
         DROP CONSTRAINT landmark_exp_route_pkey;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table landmark_exp_route already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_landmark_exp_route_1();

DROP FUNCTION cp_alter_table_landmark_exp_route_1();

/* */

CREATE FUNCTION cp_alter_table_landmark_exp_route_2()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

      ALTER TABLE landmark_exp_route 
         ADD CONSTRAINT landmark_exp_route_pkey 
         PRIMARY KEY (username, route_system_id);

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table landmark_exp_route already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_landmark_exp_route_2();

DROP FUNCTION cp_alter_table_landmark_exp_route_2();

/* */

CREATE FUNCTION cp_alter_table_landmark_exp_route_3()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

      ALTER TABLE landmark_exp_route 
         DROP COLUMN route_stack_id;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table landmark_exp_route already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_landmark_exp_route_3();

DROP FUNCTION cp_alter_table_landmark_exp_route_3();

/* */
   
DROP TABLE IF EXISTS landmark_exp_route_p2_users;
CREATE TABLE landmark_exp_route_p2_users (
   username TEXT NOT NULL,
   route_system_id INTEGER NOT NULL,
   route_user TEXT NOT NULL,
   route_user_id INTEGER NOT NULL,
   done BOOLEAN DEFAULT FALSE
);

/* */

DROP TABLE IF EXISTS landmark_exp_validation;
CREATE TABLE landmark_exp_validation (
   username TEXT NOT NULL,
   rating INTEGER NOT NULL DEFAULT -1,
   route_system_id INTEGER NOT NULL,
   step_number INTEGER NOT NULL,
   landmark_id INTEGER NOT NULL,
   landmark_type_id INTEGER NOT NULL,
   landmark_name TEXT,
   created TIMESTAMP NOT NULL
);

/* */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

