/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Clean up duplicate annot_bs, tag_bs and tag_point links */

BEGIN TRANSACTION;

/* annot_bs */

\qecho 'Counting orphan annotations - should be 0.'
select count(*)
from annotation ann
where
   valid_before_rid = rid_inf()
   and not deleted
   and not exists (select 1 from annot_bs
                   where
                      valid_before_rid = rid_inf()
                      and not deleted
                      and ann.id = annot_id);
\qecho 'Deleting duplicates from annot_bs';
DELETE FROM annot_bs c WHERE c.id IN (
  SELECT b.id
  FROM annot_bs a
  JOIN annot_bs b ON (a.id < b.id
                      AND a.annot_id = b.annot_id
                      AND a.byway_id = b.byway_id)
  WHERE
    a.valid_before_rid = rid_inf()
    AND NOT a.deleted
    AND b.valid_before_rid = rid_inf()
    AND NOT b.deleted
);
\qecho 'Counting orphan annotations - should still be 0.'
select count(*)
from annotation ann
where
   valid_before_rid = rid_inf()
   and not deleted
   and not exists (select 1 from annot_bs
                   where
                      valid_before_rid = rid_inf()
                      and not deleted
                      and ann.id = annot_id);

/* tag_bs */
\qecho 'Deleting duplicates from tag_bs';
DELETE FROM tag_bs c WHERE c.id IN (
  SELECT b.id
  FROM tag_bs a
  JOIN tag_bs b ON (a.id < b.id
                    AND a.tag_id = b.tag_id
                    AND a.byway_id = b.byway_id)
  WHERE
    a.valid_before_rid = rid_inf()
    AND NOT a.deleted
    AND b.valid_before_rid = rid_inf()
    AND NOT b.deleted
);

/* tag_point */
\qecho 'Deleting duplicates from tag_point';
DELETE FROM tag_point c WHERE c.id IN (
  SELECT b.id
  FROM tag_point a
  JOIN tag_point b ON (a.id < b.id
                       AND a.tag_id = b.tag_id
                       AND a.point_id = b.point_id)
  WHERE 
    a.valid_before_rid = rid_inf()
    AND NOT a.deleted
    AND b.valid_before_rid = rid_inf()
    AND NOT b.deleted
);

COMMIT;
