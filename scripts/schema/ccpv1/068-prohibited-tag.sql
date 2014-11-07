/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Create an 'prohibited' tag and apply it to all Expressways */

\set rid_cur '(SELECT max(id) FROM revision WHERE id != RID_INF())'
\set tagid '(SELECT id FROM tag WHERE label=''prohibited'')'
--\set codes '(41,42)' -- Expressway, Expressway Ramp
\set codes '(41)' -- Expressway
\set avoid 3

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO revision (timestamp, host, username, skip_geometry, comment)
       VALUES (now(), 'localhost', '_autotagger', TRUE,
      'Added ''prohibited'' tag to all Expressways');

-- Create prohibited tag if it doesn't exist
INSERT INTO tag (
   version,
   deleted,
   label,
   valid_starting_rid,
   valid_before_rid
) SELECT
    1,
    FALSE,
    'prohibited',
    :rid_cur,
    rid_inf()
  WHERE NOT EXISTS :tagid;

-- Apply to all Expressways 
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
  WHERE type_code IN :codes
    AND NOT EXISTS (SELECT tbs.id 
                    FROM tag_bs tbs
                    WHERE tbs.byway_id = b.id
                    AND tbs.tag_id = :tagid);

-- Set default to avoid in route finder
INSERT INTO tag_preference (username, tag_id, type_code, enabled)
  VALUES ('_r_generic', :tagid, :avoid, TRUE);

--ROLLBACK;
COMMIT;
