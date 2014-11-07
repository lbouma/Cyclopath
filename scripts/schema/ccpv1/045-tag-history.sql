/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script builds the tag history by creating an entry in the tag_bs table
   for every time a flag was checked or unchecked in a byway_segment. 
 
   To revert, delete all records from the tag and tag_bs tables.
 
   To remove flags from the database, run 046-tag-remove-flags.sql. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

/* These views on byway_segment have a single entry for every time the
   respective flag state changed, plus an entry for the final state of the
   flag on that byway.  The valid_before_rid for the eventual tag_bs entry
   is provided in the view but the valid_starting_rid must be determined
   programatically in the build_tag_history() main loop. */

CREATE OR REPLACE VIEW byway_segment_bikelane AS
   SELECT
      b1.id,
      COALESCE(b2.valid_starting_rid, RID_INF()) AS valid_before_rid,
      b1.bike_lanes AS value
   FROM
      byway_segment b1
      LEFT OUTER JOIN byway_segment b2 
      ON (b1.id = b2.id AND b1.version = b2.version - 1)
   WHERE b2 IS NULL OR b1.bike_lanes != b2.bike_lanes
   ORDER BY b1.id, b1.version;

CREATE OR REPLACE VIEW byway_segment_unpaved AS
   SELECT
      b1.id,
      COALESCE(b2.valid_starting_rid, RID_INF()) AS valid_before_rid,
      NOT b1.paved AS value
   FROM
      byway_segment b1
      LEFT OUTER JOIN byway_segment b2 
      ON (b1.id = b2.id AND b1.version = b2.version - 1)
   WHERE b2 IS NULL OR b1.paved != b2.paved
   ORDER BY b1.id, b1.version;

/* Since the closed flag was defined to allow NULLs, we must coalesce it with
   FALSE so that there are only two possible values to work with. */
CREATE OR REPLACE VIEW byway_segment_closed AS
   SELECT
      b1.id,
      COALESCE(b2.valid_starting_rid, RID_INF()) AS valid_before_rid,
      COALESCE(b1.closed, FALSE) AS value
   FROM
      byway_segment b1
      LEFT OUTER JOIN byway_segment b2 
      ON (b1.id = b2.id AND b1.version = b2.version - 1)
   WHERE b2 IS NULL OR COALESCE(b1.closed, FALSE) != COALESCE(b2.closed, FALSE)
   ORDER BY b1.id, b1.version;

CREATE OR REPLACE FUNCTION build_tag_history(tag_name TEXT, flag_name TEXT) RETURNS VOID AS $$

DECLARE

   bs RECORD;
   tid INT;
   flag_sql TEXT;
   bs_id INT;
   tbs_id INT;
   vstarting_rid INT;
   vbefore_rid INT;
   vers INT;
   check_b INT;
   check_t INT;
   check_f INT;

BEGIN

   -- Create tag in database
   tid := NEXTVAL('feature_id_seq');
   flag_sql := 'COALESCE(' || flag_name || ', FALSE)';
   RAISE INFO 'Created tag id % for %', tid, tag_name;

   EXECUTE
     'SELECT MIN(valid_starting_rid) FROM byway_segment WHERE ' || flag_sql
     INTO vstarting_rid;
   INSERT INTO tag
      (id, version, deleted, label, valid_starting_rid, valid_before_rid)
      VALUES (tid, 1, 'f', tag_name, vstarting_rid, RID_INF()); 

   -- Loop through relevant view.  (To save time, filter out those
   -- byway_segments that never had the flag applied)
   FOR bs IN 
      EXECUTE 
         'SELECT * FROM byway_segment_' || tag_name
         || ' WHERE id IN (SELECT id FROM '
         || ' byway_segment_' || tag_name
         || ' WHERE value )'
      LOOP

      IF bs_id IS NULL OR bs_id != bs.id THEN
         -- Starting on a new byway_segment
         bs_id := bs.id;
         vers := 0;
         tbs_id := NULL;

         -- use valid_starting_rid from byway_segment
         EXECUTE
            'SELECT MIN(valid_starting_rid) FROM byway_segment'
            || ' WHERE id = ' || bs_id || ' AND ' || flag_sql
            INTO vstarting_rid;
      ELSE
         -- valid_starting_rid is the valid_before_rid from last version
         vstarting_rid := vbefore_rid;
      END IF;

      vbefore_rid := bs.valid_before_rid;

      -- bs.value is true when the flag is applied in the current version
      -- tbs_id is assigned the first time there is a flag applied
      IF tbs_id IS NOT NULL OR bs.value THEN

         IF tbs_id IS NULL THEN
            tbs_id := NEXTVAL('feature_id_seq');
         END IF;

         vers := vers + 1;

         INSERT INTO tag_bs
            (id, version, deleted, tag_id, byway_id, valid_starting_rid, valid_before_rid)
            VALUES (tbs_id, vers, NOT bs.value, tid, bs.id, vstarting_rid, vbefore_rid);

      END IF;

   END LOOP;

   /* Sanity Check:
      
      B is the number of byways in each case.
      T is the number of entries in tag_bs for those byways
      F is the number of corresponding entries in byway_segment_XXXX
      
      Case 1: T = F
         For byways that have had this flag applied since their creation, there
         should be a tag_bs entry for every row in the byway_segment_$FLAG view.

      Case 2: T = F + B
         For byways that had this tag applied in a later revision, there will be
         an initial entry in byway_segment_$FLAG without a corresponding tag_bs
         entry. */

   -- Check case 1
   EXECUTE
     'SELECT count(*) FROM byway_segment WHERE ' || flag_sql
     || ' AND version=1' INTO check_b;
   EXECUTE
     'SELECT count(*) FROM byway_segment_' || tag_name
     || ' WHERE id IN (SELECT id FROM byway_segment WHERE ' || flag_sql
     || ' AND version=1);' INTO check_f;
   EXECUTE
     'SELECT count(*) FROM tag_bs WHERE tag_id = ' || tid
     || ' AND byway_id IN (SELECT id FROM byway_segment WHERE ' || flag_sql
     || ' AND version=1);' INTO check_t;
  
   RAISE INFO 'Byways tagged with % since creation: %', tag_name, check_b;
   RAISE INFO '    byway_segment_% entries: %', tag_name, check_f;
   RAISE INFO '    tag_bs entries: %', check_t;

   IF check_f != check_t THEN
      RAISE EXCEPTION 'Unexpected count mismatch';
   END IF;
   
   -- Check case 2 
   EXECUTE
     'SELECT count(*) FROM byway_segment WHERE NOT ' || flag_sql
     || ' AND version=1 AND id IN (SELECT id FROM byway_segment WHERE '
     || flag_sql || ');' INTO check_b;
   EXECUTE
     'SELECT count(*) FROM byway_segment_' || tag_name
     || ' WHERE id IN (SELECT id FROM byway_segment WHERE ' || flag_sql || ')'
     || ' AND id NOT IN (SELECT id FROM byway_segment WHERE ' || flag_sql
     || ' AND version=1);' INTO check_f;
   EXECUTE
     'SELECT count(*) FROM tag_bs WHERE tag_id = ' || tid
     || ' AND byway_id IN (SELECT id FROM byway_segment WHERE ' || flag_sql || ')'
     || ' AND byway_id NOT IN (SELECT id FROM byway_segment WHERE ' || flag_sql
     || ' AND version=1);' INTO check_t;
  
   RAISE INFO 'Byways tagged with % after creation: %', tag_name, check_b;
   RAISE INFO '    byway_segment_% entries: %', tag_name, check_f;
   RAISE INFO '    tag_bs entries: %', check_t;
   RAISE INFO '    % + % = %', check_t, check_b, (check_t+check_b);

   IF check_f != check_t + check_b THEN
      RAISE EXCEPTION 'Unexpected count mismatch';
   END IF;
   
END;

$$ LANGUAGE PLPGSQL;

SELECT build_tag_history('bikelane', 'bike_lanes');
SELECT build_tag_history('unpaved', 'NOT paved');
SELECT build_tag_history('closed', 'closed');

/* More sanity checks

\qecho *Tags*
SELECT * FROM tag;

\qecho *Unpaved* 
\qecho byway_segment
SELECT id, version, name, paved, valid_starting_rid, valid_before_rid
  FROM byway_segment WHERE id = 1134964;
\qecho byway_segment_unpaved
SELECT * FROM byway_segment_unpaved WHERE id = 1134964;
\qecho tag_bs
SELECT * FROM tag_bs WHERE byway_id = 1134964;

\qecho *Bike Lane*
\qecho byway_segment
SELECT id, version, name, bike_lanes, valid_starting_rid, valid_before_rid
  FROM byway_segment WHERE id = 1003407;
\qecho byway_segment_bikelane
SELECT * FROM byway_segment_bikelane WHERE id = 1003407;
\qecho tag_bs
SELECT * FROM tag_bs WHERE byway_id = 1003407;

\qecho *Closed*
SELECT id, version, name, closed, valid_starting_rid, valid_before_rid
  FROM byway_segment WHERE id = 1137951;
\qecho byway_segment_closed
SELECT * FROM byway_segment_closed WHERE id = 1137951;
\qecho tag_bs
SELECT * FROM tag_bs WHERE byway_id = 1137951;

*/

--ROLLBACK;
COMMIT;
