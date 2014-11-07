/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script fixes search issues in the discussions feature. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE FUNCTION contains_text(tid INT, txt TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post
   WHERE thread_id = tid AND lower(body) ~ lower(txt);

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION contains_user(tid INT, u TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.thread_id = tid AND lower(COALESCE(r.username, r.host)) ~ lower(u);

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

COMMIT;
