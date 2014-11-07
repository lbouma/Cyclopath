/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the tables for the landmarks experiment. */

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

DROP TABLE IF EXISTS landmark_experiment;
CREATE TABLE landmark_experiment (
   username TEXT NOT NULL,
   trial_time TIMESTAMP NOT NULL,
   email_sent BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE landmark_experiment 
   ADD CONSTRAINT landmark_experiment_pkey 
   PRIMARY KEY (username);

DROP TABLE IF EXISTS landmark_exp_route;
CREATE TABLE landmark_exp_route (
   username TEXT NOT NULL,
   route_id INTEGER NOT NULL,
   familiarity INTEGER DEFAULT -1,
   done BOOLEAN NOT NULL DEFAULT FALSE,
   part INTEGER DEFAULT 1,
   last_modified TIMESTAMP NOT NULL
);

ALTER TABLE landmark_exp_route 
   ADD CONSTRAINT landmark_exp_route_pkey 
   PRIMARY KEY (username, route_id);

DROP TABLE IF EXISTS landmark_exp_landmarks;
CREATE TABLE landmark_exp_landmarks (
   username TEXT NOT NULL,
   route_id INTEGER NOT NULL,
   step_number INTEGER NOT NULL,
   landmark_id INTEGER NOT NULL,
   landmark_type_id INTEGER NOT NULL,
   landmark_name TEXT,
   landmark_geo GEOMETRY,
   current BOOLEAN DEFAULT TRUE,
   created TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS landmark_exp_feedback;
CREATE TABLE landmark_exp_feedback (
   username TEXT NOT NULL,
   feedback TEXT NOT NULL,
   time_submitted TIMESTAMP NOT NULL
);

/* */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

