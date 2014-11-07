/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script annotates _roads_ in the byway_segment table with data from the
   MNDOT bikeways dataset.

   Prerequisite: SQLized version of the bikeways dataset with buffered
   geometry in column geometry_buf. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;

/* The basic method of this join: a row A in byway_segment matches a row B in
   mndot_bikeways if A's geometry is within the buffered geometry of B. */
CREATE OR REPLACE TEMP VIEW bs_bikeways_joined AS
  SELECT
    id,
    version,
    deleted,
    name,
    type_code,
    valid_start_rid,
    valid_until_rid,
    bs.geometry AS bs_geometry,
    beg_node_id,
    end_node_id,
    paved,
    bike_lanes,
    one_way,
    speed_limit,
    outside_lane_width,
    shoulder_width,
    lane_count,
    gid,
    type,
    type LIKE '%Bike Lane' as is_bikelane,
    type LIKE '%Shoulder >= 5''' as is_shoulder5,
    proposed,
    conn_gap,
    mb.geometry AS mb_geometry,
    mb.geometry_buf AS mb_geometry_buf
  FROM
    byway_segment bs JOIN mndot_bikeways mb
    ON (bs.geometry && mb.geometry_buf
        AND (Within(bs.geometry, mb.geometry_buf)))
  WHERE
        type_code != 14  -- exclude bike trails
    AND proposed = 'N'
    AND conn_gap = 'N'
    AND (type LIKE '%Bike Lane' OR type LIKE '%Shoulder >= 5''');

/* Presence of bike lane implies shoulder width at least 4 feet. */
UPDATE byway_segment
  SET shoulder_width = 4
  WHERE
        (shoulder_width IS NULL OR shoulder_width < 4)
    AND id IN (SELECT id FROM bs_bikeways_joined WHERE is_bikelane);

/* Set other shoulder widths. Note that is_bikelane and is_shoulder5 are
   mutually exclusive. */
UPDATE byway_segment
  SET shoulder_width = 5
  WHERE id IN (SELECT id FROM bs_bikeways_joined WHERE is_shoulder5);

/* Tag roads with bike lanes. */
UPDATE byway_segment
  SET bike_lanes = 't'
  WHERE id IN (SELECT id FROM bs_bikeways_joined WHERE is_bikelane);

--COMMIT;
\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;

