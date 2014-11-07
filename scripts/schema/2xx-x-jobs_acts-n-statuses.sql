/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds the Job Status enumeration to the database. */

\qecho 
\qecho This script adds the Job Status enumeration to the database.
\qecho 

FIXME: These tables are not needed?

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Make the job status lookups.                             */
/* ==================================================================== */

\qecho 
\qecho Creating the tables, public.job_status and public.job_action.
\qecho 


/* FIXME: Do I need these tables?
 *        Should I use the enum table? Or no table at all? */

CREATE TABLE job_status (
   id INTEGER NOT NULL,
   description TEXT
);

ALTER TABLE job_status 
   ADD CONSTRAINT job_status_pkey 
   PRIMARY KEY (id);

CREATE INDEX job_status_description ON job_status (description);

/* */

CREATE TABLE job_action (
   id INTEGER NOT NULL,
   description TEXT
);

ALTER TABLE job_action 
   ADD CONSTRAINT job_action_pkey 
   PRIMARY KEY (id);

CREATE INDEX job_action_description ON job_action (description);

/* ==================================================================== */
/* Step (2) -- Define the access levels and scopes                      */
/* ==================================================================== */

\qecho 
\qecho Populating job_status and job_action.
\qecho 

/* SYNC_ME: Search: Job Statuses. */
/* Out of bounds. */
INSERT INTO job_status (id, description) VALUES (-1, 'invalid');
INSERT INTO job_status (id, description) VALUES ( 0, 'notset');
/* Universal statuses. */
INSERT INTO job_status (id, description) VALUES ( 1, 'queued');
INSERT INTO job_status (id, description) VALUES ( 2, 'starting');
INSERT INTO job_status (id, description) VALUES ( 3, 'working');
INSERT INTO job_status (id, description) VALUES ( 4, 'complete');
INSERT INTO job_status (id, description) VALUES ( 5, 'failed');
/* Universal statuses. */
--INSERT INTO job_status (id, description) VALUES ( 6, 'finished'); --?
--INSERT INTO job_status (id, description) VALUES ( 7, 'expired'); --?

/* */

/* SYNC_ME: Search: Job Actions. */
/* Out of bounds. */
INSERT INTO job_action (id, description) VALUES (-1, 'invalid');
INSERT INTO job_action (id, description) VALUES ( 0, 'notset');
/* Universal actions. */
INSERT INTO job_action (id, description) VALUES ( 1, 'cancel');
INSERT INTO job_action (id, description) VALUES ( 2, 'delist');
INSERT INTO job_action (id, description) VALUES ( 3, 'suspend');
INSERT INTO job_action (id, description) VALUES ( 4, 'restart');
INSERT INTO job_action (id, description) VALUES ( 5, 'resume');
/* Custom actions: file actions. */
INSERT INTO job_action (id, description) VALUES ( 6, 'download');
INSERT INTO job_action (id, description) VALUES ( 7, 'upload');
INSERT INTO job_action (id, description) VALUES ( 8, 'delete');
/* Custom actions: merge (import and export shapefiles). */
/* Custom actions: study (bulk route analysis). */

/* ==================================================================== */
/* Step (3) -- Populate the enum def lookup                             */
/* ==================================================================== */

/* FIXME: If the enum table is good, get rid of the job_status table. */

\qecho 
\qecho Populating enum_definition table with enum values from said tables.
\qecho 

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'job_status', '', id, description, now() FROM job_status);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'job_action', '', id, description, now() FROM job_action);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

