/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script fixes constraints to use system_id and branch_id. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script corrects table constraints affected by the new ids
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.39 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.27 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Cleanup Indexes                                          */
/* ==================================================================== */

/* We created this index earlier, and we'll recreate it later, but drop it for
 * now. */

DROP INDEX geofeature_stack_id;
DROP INDEX geofeature_version;
DROP INDEX geofeature_stack_id_version;

-- Already done:
--   CREATE INDEX route_feedback_route_stack_id 
--     ON route_feedback (route_stack_id);
-- Not needed?:
DROP INDEX route_feedback_route_version;
DROP INDEX route_feedback_route_stack_id_version;

DROP INDEX route_step_byway_stack_id;
DROP INDEX route_step_byway_version;
DROP INDEX route_step_byway_stack_id_version;

DROP INDEX route_step_route_stack_id;
DROP INDEX route_step_route_version;
DROP INDEX route_step_route_stack_id_version;

/* ==================================================================== */
/* Step (1) -- Drop old constraints                                     */
/* ==================================================================== */

/* ================================== */
/* * Versioned * Support tables       */
/* ================================== */

\qecho 
\qecho Fixing constraints on versioned support tables
\qecho 

/* These tables reference a specific item at a specific version, i.e., they
   use an item's system_id. */

\qecho ... route_feedback

/* Remember: Indices are re-created in a much later script. */
DROP INDEX route_feedback_route_id;

\qecho ... route_step

ALTER TABLE route_step DROP CONSTRAINT route_step_pkey;

/* NOTE: NULL columns in route_step are for transit legs.
 * => select count(*) from route_step;                         ==> 7942995
 * => select count(*) from route_step where byway_id is null;  ==>     321
So we can't/don't want to set this constraint:
  No: ALTER TABLE route_step ALTER COLUMN byway_id SET NOT NULL;
 */

ALTER TABLE route_step ALTER COLUMN route_id SET NOT NULL;

\qecho Setting route_step''s pkey...

ALTER TABLE route_step 
   ADD CONSTRAINT route_step_pkey
   PRIMARY KEY (route_id, step_number);

\qecho ... route_stop

ALTER TABLE route_stop ALTER COLUMN route_id SET NOT NULL;

ALTER TABLE route_stop ALTER COLUMN stop_number SET NOT NULL;

\qecho Setting route_stop''s pkey...
ALTER TABLE route_stop DROP CONSTRAINT route_stop_pkey;
ALTER TABLE route_stop 
   ADD CONSTRAINT route_stop_pkey
   PRIMARY KEY (route_id, stop_number);

\qecho ... track_point

/* track_point doesn't have a primary key.
ALTER TABLE track_point DROP CONSTRAINT track_point_pkey;
*/

ALTER TABLE track_point ALTER COLUMN track_id SET NOT NULL;

ALTER TABLE track_point ALTER COLUMN step_number SET NOT NULL;

\qecho Setting track_point''s pkey...

/* NOTE: This model doesn't support steps for anything but version = 1. */
ALTER TABLE track_point 
   ADD CONSTRAINT track_point_pkey
   PRIMARY KEY (track_id, step_number);

/* ==================================================================== */
/* Step (3) -- Fix *versioned* support tables                           */
/* ==================================================================== */

\qecho 
\qecho Dropping stack IDs and versions that were replaced by system ID.
\qecho   Also dropping the GIS Views... for now
\qecho 

/* route_feedback, route_step */

\qecho ...route_feedback
ALTER TABLE route_feedback DROP COLUMN route_stack_id;
ALTER TABLE route_feedback DROP COLUMN route_version;

/* We'll recreate these later. */
DROP INDEX route_feedback_username;
ALTER TABLE route_feedback DROP CONSTRAINT route_feedback_username_fkey;

/* We replaced (stack_id, version) with system_id, so drop the old columns. */

\qecho ...route_step
/* 2012.09.20: Don't be so quick to drop these. They might be necessary...
   2014.05.15: I was never more right than the last comment!! We need these
               to fix NULL route_(system_)id columns!
ALTER TABLE route_step DROP COLUMN route_stack_id;
ALTER TABLE route_step DROP COLUMN route_version;
ALTER TABLE route_step DROP COLUMN byway_stack_id;
ALTER TABLE route_step DROP COLUMN byway_version;
*/

\qecho ...track_point
/* 2012.09.20: Is this correct? If you change the name of a track, it changes
 * the version, but the track_points are still just the 1st version, right?
ALTER TABLE track_point DROP COLUMN track_stack_id;
ALTER TABLE track_point DROP COLUMN track_version;
*/
/* 2012.09.20: We really don't need the id column (it's replaced by 
               (track_stack_id, track_version, step_number). */
ALTER TABLE track_point DROP COLUMN id;

/* ==================================================================== */
/* Step (7) -- Fix support tables                                       */
/* ==================================================================== */
/* ================================== */
/* Support tables: Apply all          */
/* ================================== */

\qecho 
\qecho Setting system ID on versioned support tables
\qecho 

ALTER TABLE route_feedback ALTER COLUMN route_id SET NOT NULL;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

