/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the conflation job. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script creates the conflation job.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* */

DROP TABLE IF EXISTS conflation_job;
CREATE TABLE conflation_job (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* */
   track_id INTEGER NOT NULL,
   revision_id INTEGER, -- -1 means current revision.
                       -- EXPLAIN: [lb] asks, why not cp_rid_inf(), 2000000000?
   cutoff_distance REAL NOT NULL,
   distance_error REAL NOT NULL -- called DISTANCE_STD in conflation script
);

ALTER TABLE conflation_job 
   ADD CONSTRAINT conflation_job_pkey 
   PRIMARY KEY (system_id);

/* */

DROP TABLE IF EXISTS conflation_job_ride_steps;
CREATE TABLE conflation_job_ride_steps (
   -- ** Item Versioned columns
   job_id INTEGER NOT NULL,
   /* */
   byway_stack_id INTEGER NOT NULL,
   byway_geofeature_layer_id INTEGER NOT NULL,
   step_number INTEGER NOT NULL,
   step_name TEXT,
   split_from_stack_id INTEGER,
   geometry GEOMETRY NOT NULL,
   beg_node_id INTEGER NOT NULL,
   fin_node_id INTEGER NOT NULL,
   forward BOOLEAN NOT NULL,
   beg_time TIMESTAMP NOT NULL,
   fin_time TIMESTAMP NOT NULL,
   is_modified BOOLEAN NOT NULL,
   is_new BOOLEAN NOT NULL
);

ALTER TABLE conflation_job_ride_steps 
   ADD CONSTRAINT conflation_job_ride_steps_pkey 
   PRIMARY KEY (job_id, step_number);

/* */

/* Fix a problem with the track data. This isn't necessarily
   conflation-specific (it's much broader than that) but [lb]
   argues that [ft] found the problem while implement track
   conflation, and that this script is just a one-off schema-
   upgrade script, so why not just dump this code here....
   and the scripts/schema/ folder already has tons of files,
   so this also reduces file congestion. */

/* From [ft] to [lb], May 2013:

   I finally figured out why the length and time were wrong for tracks! The
   problem is that the geometry column for tracks in the geofeature table
   contained empty geometry collections. When doing group by gf.geometry when
   getting tracks, postgis does not group rows with empty geometry collections
   together. Therefore, the aggregate functions (max, min, length) were not
   working correctly. I ran the following sql code (which I am sure can be
   greatly improved) to fix the tracks that have valid geometries. I then tried
   getting tracks on my phone and they now display the correct length and time
   duration. I will also fix the track saving code so that these geometries get
   saved when saving a new track.
*/

UPDATE geofeature
   SET geometry = (
      SELECT ST_SetSRID(ST_MakeLine(ST_MakePoint(tp.x, tp.y)),cp_srid())
      FROM geofeature AS gf
      JOIN track AS tk
         ON (gf.system_id = tk.system_id)
      JOIN track_point AS tp
         ON (tk.system_id = tp.track_id)
       WHERE gf.system_id = geofeature.system_id)
   WHERE
      geofeature_layer_id = 106
      AND (
         SELECT ST_IsValid(ST_SetSRID(ST_MakeLine(ST_MakePoint(tp.x, tp.y)),
                                      cp_srid()))
         FROM geofeature AS gf
         JOIN track AS tk
            ON (gf.system_id = tk.system_id)
         JOIN track_point AS tp
            ON (tk.system_id = tp.track_id)
         WHERE gf.system_id = geofeature.system_id)
      AND (
         SELECT COUNT(*)
         FROM geofeature AS gf
         JOIN track AS tk
            ON (gf.system_id = tk.system_id)
         JOIN track_point AS tp
            ON (tk.system_id = tp.track_id)
          WHERE gf.system_id = geofeature.system_id) > 1
   ;

/* */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

