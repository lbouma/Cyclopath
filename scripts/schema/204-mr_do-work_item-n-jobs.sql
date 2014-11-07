/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the jobs queuer table. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates the jobs queuer.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho 
\qecho Creating jobs queuer table.
\qecho 

/* */

DELETE FROM group_item_access WHERE item_type_id = 29; -- merge_job
-- NOTE: This leaves gunk in item_versioned.
DROP TABLE IF EXISTS route_analysis_job;
DROP TABLE IF EXISTS route_analysis_job_nids;
DROP TABLE IF EXISTS merge_job;
DROP TABLE IF EXISTS work_item_step;
DROP TABLE IF EXISTS work_item;

/* */

DROP TABLE IF EXISTS work_item;
CREATE TABLE work_item (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* FIXME Should we include the four missing columns from item_versioned to
    *       avoid the join? Should we do this to the attachment and geofeature
    *       tables? HALF-ANSWER: If we did, we could nix the item_versioned 
    *       table. It has name, that the children don't copy. And tsvect_name. 
    *       Maybe created_by. And valid_start_rid and valid_until_rid. But then
    *       group_item_access has a problem, doesn't it? I guess we need IV to 
    *       provide the link to GIA, so, really, the GRAC tables __should_not__
    *       have these? Or maybe the hybrid model is okay? Ok, ok: if you go
    *       through GIA and link to IV, then it makes sense not to have these
    *       columns, but if you bypass GIA, and then bypass IV, maybe, yeah, it
    *       makes sense to have these columns. But remember they're outside the
    *       tsvect search index. And outside other things.
    */
   /*
   deleted BOOLEAN NOT NULL DEFAULT FALSE,
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   name TEXT, -- A description of the policy
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   */
   job_class TEXT,
   created_by TEXT,
   job_priority INTEGER,
   job_finished BOOLEAN NOT NULL DEFAULT FALSE,
   num_stages INTEGER,
   /* */
   job_fcn TEXT,
   job_dat TEXT,
   job_raw BYTEA
);

ALTER TABLE work_item 
   ADD CONSTRAINT work_item_pkey 
   PRIMARY KEY (system_id);

/*

insert into work_item (system_id,branch_id,stack_id,version) VALUES (1,1,1,1);

insert into work_item_step (work_item_id, step_number) VALUES (1,1);
insert into work_item_step (work_item_id) VALUES (1);

*/

DROP TABLE IF EXISTS work_item_step;
CREATE TABLE work_item_step (
   /* This is the work_item's stack_id. It could just as well be the system_id 
    * since the item isn't versioned, but using the stack_id is the standard.
    */
   work_item_id INTEGER NOT NULL,
   step_number INTEGER NOT NULL,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
   stage_name TEXT,
   stage_num INTEGER,      -- >= 1
   stage_progress INTEGER, -- 0-100
   status_code INTEGER,
   status_text TEXT,
   cancellable BOOLEAN NOT NULL DEFAULT FALSE,
   /* These are structures for data pertaining to the stage currently being
    * processed. They could also be used to implement suspend/resume
    * operations (which we don't: suspend/resume is complicated and not
    * currently a customer requirement, but that's not to say we haven't 
    * thought about it). */
   -- suspendable BOOLEAN NOT NULL DEFAULT FALSE,
   -- callback_fcn TEXT,
   callback_dat TEXT,
   callback_raw BYTEA
);

ALTER TABLE work_item_step 
   ADD CONSTRAINT work_item_step_pkey 
   PRIMARY KEY (work_item_id, step_number);

CREATE TRIGGER work_item_step_last_modified_i
   BEFORE INSERT ON work_item_step 
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

/* */

DROP TABLE IF EXISTS merge_job;
CREATE TABLE merge_job (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* */
   for_group_id INTEGER NOT NULL,
   for_revision INTEGER NOT NULL
);

ALTER TABLE merge_job 
   ADD CONSTRAINT merge_job_pkey 
   PRIMARY KEY (system_id);

/* */

DROP TABLE IF EXISTS route_analysis_job;
CREATE TABLE route_analysis_job (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* */
   n INTEGER NOT NULL,
   revision_id INTEGER,    -- -1 means current revision.
   rt_source INTEGER,      --  1 means "user"
                           --  2 means "synthetic"
                           --  3 means "job"
                           --  4 means "radial"
                           --  etc.
   cmp_job_name TEXT,      -- Name of job to compare with.
   regions_ep_name_1 TEXT, -- List of region names for one end point.
   regions_ep_tag_1 TEXT,  -- Region tag for one end point.
   regions_ep_name_2 TEXT, -- List of region names for other end point.
   regions_ep_tag_2 TEXT,  -- Region tag for other end point.
   rider_profile TEXT
);

DROP TABLE IF EXISTS route_analysis_job_nids;
CREATE TABLE route_analysis_job_nids (
   job_id INTEGER NOT NULL,
   beg_node_id INTEGER NOT NULL,
   fin_node_id INTEGER NOT NULL
);

/* Route Sharing, circa Spring 2012, removes from_addr and to_addr from the
   route table. Now when fetching a route, the code calculates these values
   by joining against route_stop. But we already want to cache a few other
   values in the route (like n_steps, beg_nid, fin_nid, rsn_min, and rsn_max)
   so we don't have to recalculate these values all the time. So we might as
   well cache the from_addr and to_addr (or, as we now call 'em, beg_addr and
   fin_addr: We're renaming the two values by prefixing beg_ and fin_ to
   conform to Cyclopath convention. Which also helps clarify things -- route
   sharing allows trip- chaining (multiple waypoints), so there could be
   multiple from-to pairs, but there's always only one beginning-finishing
   pair).  (And I [lb] know it's spelled 'addy' and not 'ady' (the latter being
   slang for an ADHD medication), but by using 'ady' all the cache values are
   the same character length... (I know, talk about OCD!).) */
ALTER TABLE route ADD COLUMN beg_addr TEXT;
ALTER TABLE route ADD COLUMN fin_addr TEXT;

/* FIXME: I don't think we need the columns, rsn_min, rsn_max, or n_steps. */
ALTER TABLE route ADD COLUMN rsn_min INTEGER;
ALTER TABLE route ADD COLUMN rsn_max INTEGER;
ALTER TABLE route ADD COLUMN n_steps INTEGER;
/* 2012.09.21: Route Sharing adds ST_Length(geometry) to the route SQL query,
               but the length is calculated from the route steps -- so we're
               calculating route geometry length whenever a saved route is 
               requested; we can save cycles by caching the value instead. */
               /* NOTE: 'rsn' = 'route_steps'. */
ALTER TABLE route ADD COLUMN rsn_len REAL;
/* */
ALTER TABLE route ADD COLUMN beg_nid INTEGER;
ALTER TABLE route ADD COLUMN fin_nid INTEGER;

/* Don't need?: CREATE INDEX route_rsn_min ON route(rsn_min); */
/* Don't need?: CREATE INDEX route_rsn_max ON route(rsn_max); */
/* Don't need?: CREATE INDEX route_n_steps ON route(n_steps); */
CREATE INDEX route_beg_nid ON route(beg_nid);
CREATE INDEX route_fin_nid ON route(fin_nid);

/* This is used by route_analysis. */

CREATE OR REPLACE FUNCTION cp_node_ids_unnest(
      IN beg_node_id INTEGER,
      IN fin_node_id INTEGER,
      IN beg_node_intersects BOOLEAN,
      IN fin_node_intersects BOOLEAN)
   RETURNS SETOF INTEGER AS $$
   BEGIN 
      IF beg_node_intersects THEN
         RETURN NEXT beg_node_id;
      END IF;
      IF fin_node_intersects THEN
         RETURN NEXT fin_node_id;
      END IF;
      RETURN;
   END
$$ LANGUAGE 'plpgsql';

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;

