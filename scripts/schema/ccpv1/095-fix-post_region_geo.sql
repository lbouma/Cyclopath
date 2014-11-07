/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script fixes the post_region_geo VIEW. See bug 1881. */

/* Run this script once for each instance
   @once-per-instance */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;
SET search_path TO @@@instance@@@, public;

/* See 080.sql */
CREATE OR REPLACE VIEW post_region_geo AS
SELECT
   pg.id AS id,
   pg.version AS version,
   (g.deleted OR pg.deleted) AS deleted,
   post_id,
   region_id,
   g.geometry AS geometry,
   GREATEST(pg.valid_starting_rid, g.valid_starting_rid) AS valid_starting_rid,
   LEAST(pg.valid_before_rid, g.valid_before_rid) AS valid_before_rid
FROM post_region pg JOIN region g ON pg.region_id = g.id
WHERE
   -- In 080.sql, it says > g.valid_starting_rid, not < g.valid_before_rid
   pg.valid_starting_rid < g.valid_before_rid
   AND g.valid_starting_rid < pg.valid_before_rid;

COMMIT;

