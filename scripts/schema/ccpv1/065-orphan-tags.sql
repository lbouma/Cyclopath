/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*
Fix the revision history to clean up orphan tag_bs's and tag_point's

1. Find each orphan tag_bs.id, version.

2. Set valid_before_rid on existing rows (version 1) to the valid_starting_rid
   of the "corresponding" byway. (update)

3. For each orphan, create a new row with version + 1, valid_starting_rid
   matches byway, valid_before is rid_inf(), deleted = true (insert select)

4. Manually fix up the outliers.

Repeat steps above for tag_point.
To determine the outliers necessary for step 4, replace 
  g.valid_before_rid = rid_inf() with g.valid_before_rid != rid_inf() 
  in the temp table where clause.

*/

begin transaction;

select AsText(bbox) from revision where id=9418;

/* tag_bs */

/* Step 1 */
create temp table tag_bs_orphan as
select ag.id as id,
       ag.version as version,
       ag.deleted as deleted,
       rid_inf() as valid_before_rid, -- ignore r9418 
       ag.valid_starting_rid as valid_starting_rid,
       ag.tag_id as tag_id,
       ag.byway_id as byway_id
from tag_bs ag
join byway_segment g
on (ag.byway_id = g.id
    and ag.valid_starting_rid < g.valid_before_rid
    and ag.valid_before_rid > g.valid_starting_rid)
where not ag.deleted
      and g.deleted
      and g.valid_before_rid = rid_inf();

/* Step 1b - clean up artifacts from r9418 */
update tag_bs set valid_before_rid=rid_inf() 
where id in (select id from tag_bs_orphan) and version=1;

delete from tag_bs where id in (select id from tag_bs_orphan) and version=2;

select revision_geosummary_update(9418);

/* Step 2 */
update tag_bs ag
set valid_before_rid = (select valid_starting_rid
                        from byway_segment g
                        where
                           ag.byway_id = g.id
                           and g.valid_before_rid = rid_inf()
                           and ag.valid_starting_rid < g.valid_before_rid
                           and ag.valid_before_rid > g.valid_starting_rid
                           and g.deleted)
where
   ag.id in (select id from tag_bs_orphan);

/* Step 3 */
insert into tag_bs (id, tag_id, byway_id, version, 
                    valid_before_rid, valid_starting_rid, deleted)
select ag.id as id,
       ag.tag_id as tag_id,
       ag.byway_id as byway_id,
       (ag.version + 1) as version,
       rid_inf() as valid_before_rid,
       g.valid_starting_rid as valid_starting_rid,
       true as deleted
from tag_bs_orphan ag
join byway_segment g
on (ag.byway_id = g.id
    and ag.valid_starting_rid < g.valid_before_rid
    and ag.valid_before_rid > g.valid_starting_rid)
where ag.id in (select id from tag_bs_orphan)
    and g.valid_before_rid = rid_inf();

/* Step 4 */
/** NOTE: This script cannot be re-run because of step 4, it must be commented
 * out and modified since these special cases have already been taken care of.
 */
update tag_bs ag set valid_before_rid=4731 where ag.id=1408975;
insert into tag_bs (id, tag_id, byway_id, version, 
                    valid_before_rid, valid_starting_rid, deleted) 
values (1408975, 1408951, 1028469, 2, 4773, 4731, true);
insert into tag_bs (id, tag_id, byway_id, version, 
                    valid_before_rid, valid_starting_rid, deleted) 
values (1408975, 1408951, 1028469, 3, rid_inf(), 4773, false);

update tag_bs ag set valid_before_rid=6235 where ag.id=1407725;
insert into tag_bs (id, tag_id, byway_id, version, 
                    valid_before_rid, valid_starting_rid, deleted) 
values (1407725, 1406085, 1092891, 2, 6245, 6235, true);
insert into tag_bs (id, tag_id, byway_id, version, 
                    valid_before_rid, valid_starting_rid, deleted) 
values (1407725, 1406085, 1092891, 3, rid_inf(), 6245, false);

update tag_bs ag set valid_before_rid=9255 where ag.id=1408956 and version=1;
update tag_bs ag set version=4 where ag.id=1408956 and version=2;
insert into tag_bs (id, tag_id, byway_id, version,
                    valid_before_rid, valid_starting_rid, deleted)
values (1408956, 1408951, 990226, 2, 9260, 9255, true);
insert into tag_bs (id, tag_id, byway_id, version,
                    valid_before_rid, valid_starting_rid, deleted)
values (1408956, 1408951, 990226, 3, 9273, 9260, false);

update tag_bs ag set valid_before_rid=9255 where ag.id=1408961 and version=1;
update tag_bs ag set version=4 where ag.id=1408961 and version=2;
insert into tag_bs (id, tag_id, byway_id, version,
                    valid_before_rid, valid_starting_rid, deleted)
values (1408961, 1408951, 993387, 2, 9260, 9255, true);
insert into tag_bs (id, tag_id, byway_id, version,
                    valid_before_rid, valid_starting_rid, deleted)
values (1408961, 1408951, 993387, 3, 9273, 9260, false);

/* tag_point */

/* Step 1 */
create temp table tag_point_orphan as
select ag.id as id,
       ag.version as version,
       ag.deleted as deleted,
       rid_inf() as valid_before_rid, -- as above
       ag.valid_starting_rid as valid_starting_rid,
       ag.tag_id as tag_id,
       ag.point_id as point_id
from tag_point ag
join point g
on (ag.point_id = g.id
    and ag.valid_starting_rid < g.valid_before_rid
    and ag.valid_before_rid > g.valid_starting_rid)
where not ag.deleted
      and g.deleted
      and g.valid_before_rid = rid_inf();

/* Step 1b - Remove traces of r9418 */
update tag_point set valid_before_rid=rid_inf() 
where id in (select id from tag_point_orphan) and version=1;

delete from tag_point 
where id in (select id from tag_point_orphan) and version=2;

select revision_geosummary_update(9418);

/* Step 2 */
update tag_point ag
set valid_before_rid = (select valid_starting_rid
                        from point g
                        where
                           ag.point_id = g.id
                           and g.valid_before_rid = rid_inf()
                           and ag.valid_starting_rid < g.valid_before_rid
                           and ag.valid_before_rid > g.valid_starting_rid
                           and g.deleted)
where
   ag.id in (select id from tag_point_orphan);

/* Step 3 */
insert into tag_point (id, tag_id, point_id, version, 
                    valid_before_rid, valid_starting_rid, deleted)
select ag.id as id,
       ag.tag_id as tag_id,
       ag.point_id as point_id,
       (ag.version + 1) as version,
       rid_inf() as valid_before_rid,
       g.valid_starting_rid as valid_starting_rid,
       true as deleted
from tag_point_orphan ag
join point g
on (ag.point_id = g.id
    and ag.valid_starting_rid < g.valid_before_rid
    and ag.valid_before_rid > g.valid_starting_rid)
where ag.id in (select id from tag_point_orphan)
    and g.valid_before_rid = rid_inf();

/* Step 4 */

/* No special cases for tag_point */

-- this annot_bs and annotation were correctly cleaned up 2 revisions
-- after they should have been, so we're just fixing it up
update annot_bs set valid_before_rid=6157 where id=1369623 and version=1;
update annot_bs set valid_starting_rid=6157 where id=1369623 and version=2;
update annotation set valid_before_rid=6157 where id=1369624 and version=1;
update annotation set valid_before_rid=6157 where id=1369625 and version=2;

-- this annot_bs also had a similar problem, only its annotation is still in 
-- use and doesn't require cleaning up
update annot_bs set valid_before_rid=6157 where id=1388087 and version=1;
update annot_bs set valid_starting_rid=6157 where id=1388087 and version=2;

select AsText(bbox) from revision where id=9418;

commit;
--rollback;
