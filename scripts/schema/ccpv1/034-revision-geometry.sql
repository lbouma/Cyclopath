/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script updates revision_geomsummary_update() slightly to restore the
   rounded appearance of geosummaries. */

begin transaction;
set constraints all deferred;


create or replace function revision_geosummary_update(rid int) returns void
as $$
begin
   -- Not sure why we need SetSRID() after Box2d().
   update revision
   set geometry = Multi(Buffer(revision_geometry(rid), 5, 1)),
       bbox = SetSRID(Box2d(Buffer(Box2d(revision_geometry(rid)),
                                   0.001, 1)), 26915),
       geosummary = Multi(Simplify(Buffer(revision_geometry(rid), 100, 2), 25))
   where id = rid;
end
$$ language plpgsql volatile;


\qecho Updating geosummaries; this will take a while.
select id, revision_geosummary_update(id)
  from revision
  where id>=145 and id != rid_inf();


-- rollback;
commit;

vacuum analyze revision;
