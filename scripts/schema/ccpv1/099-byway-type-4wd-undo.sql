/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Undo the (re-)creation of the "4WD Road" byway type; see bug 1921. */

\set other 2
\set 4wd 12
\set tagid '(SELECT id FROM tag WHERE label=''unpaved'')'
\set rid_cur '(SELECT max(id) FROM revision WHERE id != RID_INF())'

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO colorado, public;

-- 4WD roads are (probably) unpaved; apply the tag before we lose that info.
INSERT INTO revision (timestamp, host, username, skip_geometry, comment)
       VALUES (now(), 'localhost', '_script', FALSE,
      'Added ''unpaved'' tag to 4WD roads imported from TIGER.');

INSERT INTO tag_bs (
   version,
   deleted,
   tag_id,
   byway_id,
   valid_starting_rid,
   valid_before_rid
) SELECT 1,
         false,
         :tagid,
         b.id,
         :rid_cur,
         rid_inf()
  FROM byway_current b
  WHERE type_code = :4wd
    AND NOT EXISTS (SELECT tbs.id 
                    FROM tag_bs tbs
                    WHERE tbs.byway_id = b.id
                    AND tbs.tag_id = :tagid);

SELECT revision_geosummary_update(:rid_cur);

-- Reassign existing foreign keys from "4WD Road" to "Other"
UPDATE byway_segment SET type_code = :other WHERE type_code = :4wd;
UPDATE tiger_codes SET byway_code = :other WHERE byway_code = :4wd;

-- Remove the "4WD Road" byway type.
-- NOTE: this script assumes no one has ever used the "4WD Road" type in the
-- minnesota instance.  If that is not the case, the following will fail.
DELETE FROM byway_type WHERE code = :4wd;

COMMIT;
