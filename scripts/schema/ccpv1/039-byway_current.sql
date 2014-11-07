/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Create a byway_current convenience view. */


\qecho --- OK if this is not found
drop view byway_current;


begin transaction;
set constraints all deferred;

create view byway_current as
select * from byway_segment bs
where bs.deleted = false and bs.valid_before_rid = rid_inf();

-- rollback;
commit;
