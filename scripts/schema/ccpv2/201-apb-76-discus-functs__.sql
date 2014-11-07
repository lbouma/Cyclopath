/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script fixes all of the functions that work on posts and threads. */



/* FIXME: DELETE THIS FILE.
 *
 *       Delete this file after you have cleaned up all usages of these fcns.
 *       from pyserver. */





\qecho 
\qecho This script removes the functions that work on posts and threads
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

\qecho 
\qecho FIXME: Implement this script!
\qecho  

/* Run this script just once, 
   for all instances of Cyclopath */

-- remove this comment:
/* NOTE We need to set search_path to an instance (e.g., 'minnesota') so SQL 
        doesn't complain about missing geofeature table */
--SET search_path TO public, minnesota;

/* FIXME: Delete this script once you've turned all the pl/pgsql into pyserver
 *       sql. */

SET search_path TO public;

/* ============== */
/* Timestamp fcn. */
/* ============== */

/* c.f. 084-timezone.sql */

\set TSWTZ 'TIMESTAMP WITH TIME ZONE'

/* ============================ */
/* Discussions function cleanup */
/* ============================ */

/* FIXME This is a mess...

CREATE OR REPLACE FUNCTION public.unread_posts(tid INT, u TEXT)
RETURNS INT AS $$
DECLARE
   ans INT;
   last_viewed timestamp with time zone;
BEGIN
   SELECT COALESCE(MAX(created), '-infinity') INTO last_viewed
          FROM thread_read_event tre
          WHERE tre.username = u 
                AND tre.thread_id = tid;
   IF u = '' THEN
      SELECT COUNT(*) INTO ans
             FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
             WHERE p.thread_id = tid
                   AND r.timestamp > last_viewed;
   ELSE
      SELECT COUNT(*) INTO ans
             FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
             WHERE p.thread_id = tid
                   AND r.timestamp > last_viewed
                   AND COALESCE(r.username, r.host) != u;
   END IF;
   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- DROP FUNCTION lp_ts(INT);
CREATE OR REPLACE FUNCTION public.lp_ts(tid INT) RETURNS :TSWTZ AS $$
DECLARE ans timestamp with time zone;
BEGIN
   SELECT MAX(timestamp) INTO ans
   FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

*/

/* c.f. 080-discussions.sql */

/* FIXME This is a mess...

CREATE OR REPLACE VIEW post_geo as
SELECT
  p.id,
  p.version AS version,
  (p.deleted or pg.deleted) as deleted,
  pg.obj_id as gf_id,
  pg.geometry as geometry,
  GREATEST(p.valid_start_rid, pg.valid_start_rid) AS valid_start_rid,
  LEAST(p.valid_until_rid, pg.valid_until_rid) AS valid_until_rid
FROM post_iv p JOIN post_obj_geo pg ON p.id = pg.post_id
WHERE
  p.valid_start_rid <= pg.valid_until_rid
  AND pg.valid_start_rid < p.valid_until_rid;

*/

/* Some utility functions */

/* FIXME This is a mess...

CREATE OR REPLACE FUNCTION contains_text(tid INT, txt TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post_iv
   WHERE thread_id = tid AND body ~ txt;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION contains_user(tid INT, u TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
   WHERE p.thread_id = tid AND COALESCE(r.username, r.host) ~ u;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION intersects_geom(tid INT, geom GEOMETRY) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post_iv p JOIN post_geo pg ON (p.id = pg.post_id)
   WHERE p.thread_id = tid AND ST_Intersects(pg.geometry, geom);

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION unread_posts(tid INT, u TEXT)
RETURNS INT AS $$
DECLARE ans INT;
DECLARE last_viewed TIMESTAMP;
BEGIN
   SELECT COALESCE(MAX(created), '-infinity') INTO last_viewed
   FROM thread_read_event tre
   WHERE tre.username = u 
         AND tre.thread_id = tid;

   IF u = '' THEN
      SELECT COUNT(*) INTO ans
      FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed;
   ELSE
      SELECT COUNT(*) INTO ans
      FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND COALESCE(r.username, r.host) != u;
   END IF;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION total_posts(tid INT)
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post_iv p 
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION lp_user(tid INT) 
RETURNS TEXT AS $$
DECLARE ans TEXT;
BEGIN
   SELECT COALESCE(username, host) INTO ans
   FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
   WHERE p.thread_id = tid
   ORDER BY timestamp DESC
   LIMIT 1;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION lp_ts(tid INT) 
RETURNS TIMESTAMP AS $$
DECLARE ans TIMESTAMP;
BEGIN
   SELECT MAX(timestamp) INTO ans
   FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION format_ts(ts TIMESTAMP) 
RETURNS TEXT AS $$
DECLARE f_ans TEXT;
BEGIN
   IF ts > now() - interval '1 day' THEN
      f_ans := TO_CHAR(ts, 'HH:MIam');
   ELSIF ts > DATE_TRUNC('YEAR', now()) THEN
      f_ans := TO_CHAR(ts, 'Mon DD');
   ELSE
      f_ans := TO_CHAR(ts, 'MM/DD/YYYY');
   END IF;

   RETURN f_ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION references_gf(tid INT, gfid INT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post_iv p JOIN post_geo pg ON (p.id = pg.id)
   WHERE p.thread_id = tid AND pg.gf_id = gfid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Return no. of threads attached to a geofeature.
CREATE OR REPLACE FUNCTION n_attached_threads(gfid INT) 
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(DISTINCT p.thread_id) INTO ans
   FROM post_geo pg JOIN post_iv p ON (pg.id = p.id)
   WHERE pg.gf_id = gfid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- What-th post after the last read event on a thread by a user?
CREATE OR REPLACE FUNCTION n_after_last_read(pid INT, u TEXT) 
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post_iv p JOIN revision r ON (p.valid_start_rid = r.id)
   WHERE p.id = pid
         AND r.timestamp > (SELECT MAX(created)
                            FROM thread_read_event tre
                            WHERE tre.thread_id = p.thread_id
                                  AND tre.username = u);

   RETURN ans;
END;
$$ LANGUAGE plpgsql VOLATILE;

*/

/* === */
/* EOF */
/* === */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;

