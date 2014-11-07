/* This script corrects some inconsistencies in the versioning data of tag_bs
   and annotation.

   @once-per-instance */

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;
SET CONSTRAINTS ALL DEFERRED;

/* tag_bs - see bug 1295 */

DELETE FROM tag_bs WHERE id IN (1406438, 1406536, 1407315, 1408192,
                                1408891, 1409065, 1427067);

\qecho *** This query should give zero rows
SELECT *
FROM 
  tag_bs tb1 JOIN tag_bs tb2 USING (id, tag_id, byway_id, valid_starting_rid)
WHERE tb1.version != tb2.version 
ORDER BY id, tb1.version;

ALTER TABLE tag_bs
  ADD CONSTRAINT tag_bs_unique_starting_rid UNIQUE (id, valid_starting_rid);

/* annotation - see bug 1851 */

UPDATE annotation SET valid_starting_rid = 6157 
  WHERE id = 1369624 AND version = 2;

COMMIT;
