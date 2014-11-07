/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script moves comments stored in byway_segment.comments to annotations
   and removes the comments column. */

begin transaction;
set constraints all deferred;
set transaction isolation level serializable;  -- ensure max revid is stable.

create function fix(bid int, thecomments text) returns int as $$
declare
   aid int;
   rid int;
begin
   aid = nextval('feature_id_seq');
   select max(id) from revision into rid;
   insert into annotation
      (id, version, deleted, comments, valid_starting_rid, valid_before_rid)
      values (aid, 1, 'f', thecomments, rid, null);
   insert into annot_bs
      (version, deleted, annot_id, byway_id,
       valid_starting_rid, valid_before_rid)
      values (1, 'f', aid, bid, rid, null);
   return aid;
end
$$ language plpgsql;

--select id, version, substr(comments, 0, 16) from byway_segment where id in (1085009, 984868);

insert into revision
  (host, username, timestamp)
  values (user, '_014-annotations.sql', now());

select fix(id, comments) from byway_segment
where valid_before_rid is null and comments is not null;

drop view exp_all_comment;
drop view exp_byway_comment;
alter table byway_segment drop column comments;

/*
select byway_id, annot_id, substr(comments, 0, 16)
from
  byway_segment bs
  join annot_bs ab on bs.id = ab.byway_id
  join annotation an on ab.annot_id = an.id
where
  bs.id in (1085009, 984868)
  and bs.valid_before_rid is null;
*/

--rollback;
commit;

vacuum full verbose analyze byway_segment;
