/* (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script was supposed to be based off of a previous orphan-deleter,

     096-delete-orphaned-features.sql

   but the problem seems unique.

   BUG nnnn: This orphan...

   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO minnesota, public;

/*
 * FIXME: This is the one we want. The one cron keeps complaining about.
 orphan tag_point | 1543284 |       1 | 1543281 |       2
 */

/*

select 'orphan tag_point', ag.id, ag.version, g.id, g.version
from
   tag_point ag
   join point g
   on (ag.point_id = g.id
       and ag.valid_starting_rid < g.valid_before_rid
       and ag.valid_before_rid > g.valid_starting_rid ) 
where
   not ag.deleted
   -- and ag.valid_until_rid = cp_rid_inf()
   and g.deleted
order by g.id, ag.id, ag.version;

     ?column?     |   id    | version |   id    | version 
------------------+---------+---------+---------+---------
 orphan tag_point | 1543284 |       1 | 1543281 |       2

===

production=> select * from tag_point where id=1543284;

   id    | version | deleted | tag_id  | point_id | valid_starting_rid | valid_before_rid 
---------+---------+---------+---------+----------+--------------------+------------------
 1543284 |       1 | f       | 1409258 |  1543281 |              15060 |            15071
 1543284 |       2 | t       | 1409258 |  1543281 |              15071 |       2000000000

===

production=> select * from point where id=1543281;

   id    | version | deleted |               name               | type_code | valid_starting_rid | valid_before_rid |                      geometry                      | comments |  z  
---------+---------+---------+----------------------------------+-----------+--------------------+------------------+----------------------------------------------------+----------+-----
 1543281 |       1 | f       | Crosswinds Arts & Science School |         2 |              15059 |            15070 | 0101000020236900000000000074A71E41000000C06BFB5241 |          | 140
 1543281 |       2 | t       | Crosswinds Arts & Science School |         2 |              15070 |       2000000000 | 0101000020236900000000000074A71E41000000C06BFB5241 |          | 140

===

production=> select * from tag where id=1409258;
   id    | version | deleted | label  | valid_starting_rid | valid_before_rid 
---------+---------+---------+--------+--------------------+------------------
 1409258 |       1 | f       | school |               7586 |       2000000000

===

BUG nnnn:

So, what, the rids are off by one?!

*/

UPDATE tag_point SET valid_before_rid=15070 WHERE id=1543284 AND version=1;
UPDATE tag_point SET valid_starting_rid=15070 WHERE id=1543284 AND version=2;

/* ==== */
/* DONE */
/* ==== */

\qecho 
\qecho All done!
\qecho 

COMMIT;

