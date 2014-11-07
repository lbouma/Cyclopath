/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Fix-Add missing tag rows.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Fix-Add missing tag rows.
\qecho

/* 2014.04.21: Haha, we were missing the 'aliens' tag all this time!

INFO:  add_mssg_tags: 3870914: county
INFO:  add_mssg_tags: 3865555: township
INFO:  add_mssg_tags: 3513805: disconnected
INFO:  add_mssg_tags: 3021534: logging traffic
INFO:  add_mssg_tags: 1254434: Safety
INFO:  add_mssg_tags: 1254289: TNR
INFO:  add_mssg_tags: 1254230: local microbrewery
INFO:  add_mssg_tags: 1254223: quilting
INFO:  add_mssg_tags: 1254218: aliens
*/

DROP FUNCTION IF EXISTS add_missing_tag_rows_maybe();
CREATE FUNCTION add_missing_tag_rows_maybe()
   RETURNS VOID AS $$
   DECLARE
      gia_row RECORD;
      tag_type_id INTEGER;
   BEGIN
      -- Caching the tag type id saves a noticeable number of seconds over
      -- using the cp_item_type_id function inline.
      tag_type_id  := cp_item_type_id('tag');
      IF '@@@instance@@@' = 'minnesota' THEN
         FOR gia_row IN EXECUTE '
            SELECT item_id, branch_id, stack_id, version, name
             FROM group_item_access AS gia
             WHERE item_type_id = ' || tag_type_id || '
               AND NOT EXISTS(
                  SELECT system_id FROM tag WHERE system_id = gia.item_id)
             ' LOOP
            RAISE INFO 'add_mssg_tags: %: %', gia_row.item_id, gia_row.name;
            INSERT INTO tag (system_id, branch_id, stack_id, version)
               VALUES (gia_row.item_id,
                       gia_row.branch_id,
                       gia_row.stack_id,
                       gia_row.version);
         END LOOP; 
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT add_missing_tag_rows_maybe();

DROP FUNCTION IF EXISTS add_missing_tag_rows_maybe();

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Add landmarks experiment reset function.
\qecho

DROP FUNCTION IF EXISTS cp_experiment_landmarks_reset_user(IN uname TEXT);
CREATE FUNCTION cp_experiment_landmarks_reset_user(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      DELETE FROM landmark_exp_feedback WHERE username = uname;
      DELETE FROM landmark_exp_landmarks WHERE username = uname;
      DELETE FROM landmark_exp_route WHERE username = uname;
      DELETE FROM landmark_experiment WHERE username = uname;
      DELETE FROM landmark_prompt WHERE username = uname;
      DELETE FROM landmark_trial WHERE username = uname;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Add landmarks experiment null feedback okay.
\qecho

ALTER TABLE landmark_exp_feedback ALTER COLUMN feedback DROP NOT NULL;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

