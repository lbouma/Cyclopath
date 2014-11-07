/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* For bug 1698. Fixes orphan tag region caused by revert bug 1701. This bug
   causes tags in reverted regions to not appear as reverted until one
   revision later. Therefore, the fix is to change the relevant revision id's
   from 11369 to 11368. */

BEGIN TRANSACTION;

UPDATE tag_region
SET valid_before_rid=11368
WHERE id=1480781 AND version=1;

UPDATE tag_region
SET valid_starting_rid=11368
WHERE id=1480781 AND version=2;

COMMIT;
