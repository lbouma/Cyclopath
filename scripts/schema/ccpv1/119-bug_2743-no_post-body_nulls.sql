/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Bug 2743 - Database: Some post.body being stored as 'null'. */

UPDATE post SET body = NULL WHERE body = 'null';

/* C.f. 115-reactions.sql. */

CREATE OR REPLACE FUNCTION unread_posts(tid INT, u TEXT)
RETURNS INT AS $$
DECLARE ans INT;
DECLARE last_viewed timestamp with time zone;
BEGIN
   SELECT COALESCE(MAX(created), '-infinity') INTO last_viewed
   FROM thread_read_event tre
   WHERE tre.username = u 
         AND tre.thread_id = tid;

   IF u = '' THEN
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND p.body != ''
            AND p.body != 'null'
            AND p.body IS NOT NULL
            AND p.valid_before_rid = rid_inf();
   ELSE
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND COALESCE(r.username, r.host) != u
            AND p.body != ''
            AND p.body != 'null'
            AND p.body IS NOT NULL
            AND p.valid_before_rid = rid_inf();
   END IF;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION total_posts(tid INT)
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post p 
   WHERE p.thread_id = tid
         AND p.body IS NOT NULL
         AND p.valid_before_rid = rid_inf();

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

/* All done! */

COMMIT;

