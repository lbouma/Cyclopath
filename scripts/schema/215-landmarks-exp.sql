/* Copyright (c) 2006-2013 Regents of the University of Minnesota
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

DROP TABLE IF EXISTS landmark_trial;
CREATE TABLE landmark_trial (
   username TEXT NOT NULL,
   trial_num INTEGER NOT NULL,
   trial_time TIMESTAMP NOT NULL,
   condition TEXT NOT NULL,
   track_id INTEGER,
   email_sent BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE landmark_trial 
   ADD CONSTRAINT landmark_trial_pkey 
   PRIMARY KEY (username, trial_num);

DROP TABLE IF EXISTS landmark_prompt;
CREATE TABLE landmark_prompt (
   username TEXT NOT NULL,
   trial_num INTEGER NOT NULL,
   prompt_num INTEGER NOT NULL,
   prompt_time TIMESTAMP NOT NULL,
   node_id INTEGER
);

ALTER TABLE landmark_prompt 
   ADD CONSTRAINT landmark_prompt_pkey 
   PRIMARY KEY (username, trial_num, prompt_num);

/* */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

