/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script configures the system_id column in the route_feedback, 
   route_step, and track_point tables. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds system_id & branch_id and renames id to stack_id
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 10    mins. mn. / 0 mins. co.]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 8    hours. mn. / 0 mins. co.]
\qecho [EXEC. TIME: 2013.04.23/runic:  1.36 min. [mn]]
\qecho 

/* PERFORMANCE NOTE: Before deferring index and constraint creation, this
 *                   script took ~ 15 mins. to run. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (10) -- Add Branch ID to *versioned* support tables             */
/* ==================================================================== */

/* ================================== */
/* Support tables: Helper fcn.        */
/* ================================== */

\qecho 
\qecho Creating helper fcn. for versioned support tables
\qecho 

CREATE FUNCTION item_table_update_versioned(
      IN table_name TEXT, IN idvers_prefix TEXT)
   RETURNS VOID AS $$
   BEGIN
      /* NOTE: This operation is super slow. */
      EXECUTE 'UPDATE ' || table_name || ' AS child 
                  SET ' || idvers_prefix || '_id = 
                     (SELECT system_id 
                        FROM geofeature AS parent 
                        WHERE parent.stack_id 
                                 = child.' || idvers_prefix || '_stack_id 
                              AND parent.version 
                                 = child.' || idvers_prefix || '_version);';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ================================== */
/* Support tables: Apply all          */
/* ================================== */

\qecho 
\qecho Creating indices for versioned support tables
\qecho 

/* PERF. NOTE: These indices... don't really speed things up. */

--CREATE INDEX geofeature_system_id ON geofeature (system_id);
DROP INDEX IF EXISTS geofeature_stack_id;
CREATE INDEX geofeature_stack_id ON geofeature (stack_id);
/* */
DROP INDEX IF EXISTS geofeature_version;
CREATE INDEX geofeature_version ON geofeature (version);
/* */
DROP INDEX IF EXISTS geofeature_stack_id_version;
CREATE INDEX geofeature_stack_id_version 
   ON geofeature (stack_id, version);

-- Already done:
--   CREATE INDEX route_feedback_route_stack_id 
--     ON route_feedback (route_stack_id);
-- Not needed?:
/* */
DROP INDEX IF EXISTS route_feedback_route_version;
CREATE INDEX route_feedback_route_version ON route_feedback (route_version);
/* */
DROP INDEX IF EXISTS route_feedback_route_stack_id_version;
CREATE INDEX route_feedback_route_stack_id_version 
   ON route_feedback (route_stack_id, route_version);

/* */
DROP INDEX IF EXISTS route_step_byway_stack_id;
CREATE INDEX route_step_byway_stack_id ON route_step (byway_stack_id);
/* */
DROP INDEX IF EXISTS route_step_byway_version;
CREATE INDEX route_step_byway_version ON route_step (byway_version);
/* */
DROP INDEX IF EXISTS route_step_byway_stack_id_version;
CREATE INDEX route_step_byway_stack_id_version 
   ON route_step (byway_stack_id, byway_version);

/* */
DROP INDEX IF EXISTS route_step_route_stack_id;
CREATE INDEX route_step_route_stack_id ON route_step (route_stack_id);
/* */
DROP INDEX IF EXISTS route_step_route_version;
CREATE INDEX route_step_route_version ON route_step (route_version);
/* */
DROP INDEX IF EXISTS route_step_route_stack_id_version;
CREATE INDEX route_step_route_stack_id_version 
   ON route_step (route_stack_id, route_version);

/* */
DROP INDEX IF EXISTS route_stop_route_stack_id;
CREATE INDEX route_stop_route_stack_id ON route_stop (route_stack_id);
/* */
DROP INDEX IF EXISTS route_stop_route_version;
CREATE INDEX route_stop_route_version ON route_stop (route_version);
/* */
DROP INDEX IF EXISTS route_stop_route_stack_id_version;
CREATE INDEX route_stop_route_stack_id_version 
   ON route_stop (route_stack_id, route_version);

/* */
DROP INDEX IF EXISTS track_point_track_stack_id;
CREATE INDEX track_point_track_stack_id ON track_point (track_stack_id);
/* */
DROP INDEX IF EXISTS track_point_track_version;
CREATE INDEX track_point_track_version ON track_point (track_version);
/* */
DROP INDEX IF EXISTS track_point_track_stack_id_version;
CREATE INDEX track_point_track_stack_id_version 
   ON track_point (track_stack_id, track_version);

/* 2012.10.04: Route Feedback Drag. */
/* FIXME: Should we index old_route_stack_id or old_route_version or both? */

/*
EXPLAIN 
UPDATE route_step AS child 
   SET byway_id = parent.system_id
   FROM geofeature AS parent
      WHERE parent.stack_id 
               = child.byway_stack_id 
            AND parent.version 
               = child.byway_version;

*/

\qecho 
\qecho Populating ID columns in versioned support tables
\qecho 

\qecho ...route_feedback
SELECT item_table_update_versioned('route_feedback', 'route');
/* NOTE: Updating the route_step table takes a long, long time, so we perform
         these tasks in a later script (since each of these tasks takes hours
         to perform, we can minimize developer discomfort by segregating these,
         i.e., it'd suck if you waited three hours for the route_step table to
         be updated but then another error is this file caused a failure before
         the commit. */
/* DEFERRED: SELECT item_table_update_versioned('route_step', 'byway'); */
/* DEFERRED: SELECT item_table_update_versioned('route_step', 'route'); */
\qecho ...route_stop (route)
SELECT item_table_update_versioned('route_stop', 'route');
\qecho ...track_point (track)
/* Skipping: route_view. It's just the stack ID; versionless. */
SELECT item_table_update_versioned('track_point', 'track');

/* 2012.10.04: Route Feedback Drag. */
\qecho ...route_feedback_drag (old_route)
SELECT item_table_update_versioned('route_feedback_drag', 'old_route');
\qecho ...route_feedback_drag (new_route)
SELECT item_table_update_versioned('route_feedback_drag', 'new_route');

/* ================================== */
/* Support tables: Cleanup            */
/* ================================== */

/* 2012.09.24: [lb] split this script into three, so we can segregate the two
   operations that each take three hours to run.
   So we'll drop this fcn. later:
DROP FUNCTION item_table_update_versioned(
   IN table_name TEXT, IN idvers_prefix TEXT);
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

\qecho Committing... [2012.09.22: huffy: mn: 2m]

COMMIT;

/*

cycling5=> \d geofeature 
                Table "minnesota.geofeature"
       Column        |   Type   |         Modifiers         
---------------------+----------+---------------------------
 stack_id            | integer  | not null
 version             | integer  | not null
 z                   | integer  | not null
 geofeature_layer_id | integer  | not null
 beg_node_id         | integer  | 
 fin_node_id         | integer  | 
 split_from_stack_id | integer  | 
 username            | text     | not null default ''::text
 notify_email        | boolean  | not null default false
 geometry            | geometry | not null
 system_id           | integer  | not null
 branch_id           | integer  | 
Indexes:
    "geofeature_pkey" PRIMARY KEY, btree (stack_id, version)
Check constraints:
    "enforce_dims_geometry" CHECK (ndims(geometry) = 2)
    "enforce_srid_geometry" CHECK (srid(geometry) = cp_srid())

cycling5=> \d route_step
     Table "minnesota.route_step"
     Column     |  Type   | Modifiers 
----------------+---------+-----------
 route_stack_id | integer | not null
 step_number    | integer | not null
 byway_stack_id | integer | not null
 byway_version  | integer | not null
 forward        | boolean | not null
 route_version  | integer | not null
 byway_id       | integer | 
 route_id       | integer | 
Indexes:
    "route_step_pkey" PRIMARY KEY, btree (route_stack_id, route_version, step_number)

cycling5=> EXPLAIN 
cycling5-> UPDATE route_step AS child 
cycling5->    SET byway_id = parent.system_id
cycling5->    FROM geofeature AS parent
cycling5->       WHERE parent.stack_id 
cycling5->                = child.byway_stack_id 
cycling5->             AND parent.version 
cycling5->                = child.byway_version;
                                             QUERY PLAN                                              
-----------------------------------------------------------------------------------------------------
 Merge Join  (cost=990452.81..1039893.35 rows=45874 width=35)
   Merge Cond: ((child.byway_stack_id = parent.stack_id) AND (child.byway_version = parent.version))
   ->  Sort  (cost=902544.78..917314.77 rows=5907996 width=31)
         Sort Key: child.byway_stack_id, child.byway_version
         ->  Seq Scan on route_step child  (cost=0.00..96710.96 rows=5907996 width=31)
   ->  Materialize  (cost=87908.03..95694.40 rows=622910 width=12)
         ->  Sort  (cost=87908.03..89465.30 rows=622910 width=12)
               Sort Key: parent.stack_id, parent.version
               ->  Seq Scan on geofeature parent  (cost=0.00..17310.10 rows=622910 width=12)
(9 rows)

cycling5=> CREATE INDEX geofeature_stack_id ON geofeature (stack_id);
CREATE INDEX
cycling5=> CREATE INDEX geofeature_version ON geofeature (version);
CREATE INDEX
cycling5=> CREATE INDEX route_step_route_stack_id ON route_step (route_stack_id);
CREATE INDEX
cycling5=> CREATE INDEX route_step_route_version ON route_step (route_version);
CREATE INDEX
cycling5=> CREATE INDEX route_step_route_stack_id_version 
cycling5->    ON route_step (route_stack_id, route_version);
CREATE INDEX

cycling5=> EXPLAIN 
UPDATE route_step AS child 
   SET byway_id = parent.system_id
   FROM geofeature AS parent
      WHERE parent.stack_id 
               = child.byway_stack_id 
            AND parent.version 
               = child.byway_version;
                                             QUERY PLAN                                              
-----------------------------------------------------------------------------------------------------
 Merge Join  (cost=950199.66..997287.42 rows=45874 width=35)
   Merge Cond: ((child.byway_stack_id = parent.stack_id) AND (child.byway_version = parent.version))
   ->  Sort  (cost=902544.78..917314.77 rows=5907996 width=31)
         Sort Key: child.byway_stack_id, child.byway_version
         ->  Seq Scan on route_step child  (cost=0.00..96710.96 rows=5907996 width=31)
   ->  Materialize  (cost=47654.88..51519.95 rows=309206 width=12)
         ->  Sort  (cost=47654.88..48427.89 rows=309206 width=12)
               Sort Key: parent.stack_id, parent.version
               ->  Seq Scan on geofeature parent  (cost=0.00..14173.06 rows=309206 width=12)
(9 rows)

cycling5=> ANALYZE geofeature;
ANALYZE
cycling5=> ANALYZE route_step;
ANALYZE

NOTE: parent and child flipped in the query plan now:

cycling5=> EXPLAIN 
UPDATE route_step AS child 
   SET byway_id = parent.system_id
   FROM geofeature AS parent
      WHERE parent.stack_id 
               = child.byway_stack_id 
            AND parent.version 
               = child.byway_version;
                                             QUERY PLAN                                              
-----------------------------------------------------------------------------------------------------
 Merge Join  (cost=949832.93..1044611.76 rows=4846318 width=35)
   Merge Cond: ((parent.stack_id = child.byway_stack_id) AND (parent.version = child.byway_version))
   ->  Sort  (cost=47056.36..47817.43 rows=304425 width=12)
         Sort Key: parent.stack_id, parent.version
         ->  Seq Scan on geofeature parent  (cost=0.00..14125.25 rows=304425 width=12)
   ->  Materialize  (cost=902557.49..976408.33 rows=5908067 width=31)
         ->  Sort  (cost=902557.49..917327.66 rows=5908067 width=31)
               Sort Key: child.byway_stack_id, child.byway_version
               ->  Seq Scan on route_step child  (cost=0.00..96711.67 rows=5908067 width=31)
(9 rows)

oops, forgot to index route_step.byway_stack_id and byway_version...

-----------------------------------------------------------------------------------------------------
 Merge Join  (cost=944896.38..1037390.82 rows=4635368 width=35)
   Merge Cond: ((parent.version = child.byway_version) AND (parent.stack_id = child.byway_stack_id))
   ->  Sort  (cost=42333.37..43110.01 rows=310654 width=12)
         Sort Key: parent.version, parent.stack_id
         ->  Seq Scan on geofeature parent  (cost=0.00..8684.54 rows=310654 width=12)
   ->  Materialize  (cost=902557.49..976408.33 rows=5908067 width=31)
         ->  Sort  (cost=902557.49..917327.66 rows=5908067 width=31)
               Sort Key: child.byway_version, child.byway_stack_id
               ->  Seq Scan on route_step child  (cost=0.00..96711.67 rows=5908067 width=31)
(9 rows)


*/

