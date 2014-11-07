/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script alters the revision table:

   1. Updates bbox to include 1mm buffer to avoid the bbox degenerating into a
      point, yecch. (#542).

   2. Reduces the geosummary buffer width to make it look nicer at deeper zoom.

   3. Adds a column geometry which caches "exact" revision geometry. Currently
      this is NOT actually exact revision geometry, which would make it of
      type geometrycollection, because geometrycollections are pretty much
      useless for operating on. Instead, it's a tight buffer around the actual
      geometry, i.e. multipolygon. */

begin transaction;
set constraints all deferred;


select AddGeometryColumn('revision', 'geometry', 26915, 'MULTIPOLYGON', 2);
\d revision

create or replace function revision_geosummary_update(rid int) returns void
as $$
begin
   -- Not sure why we need SetSRID() after Box2d().
   update revision
   set geometry = Multi(Buffer(revision_geometry(rid), 5, 1)),
       bbox = SetSRID(Box2d(Buffer(Box2d(revision_geometry(rid)),
                                   0.001, 1)), 26915),
       geosummary = Multi(Simplify(Buffer(revision_geometry(rid), 100, 2), 50))
   where id = rid;
end
$$ language plpgsql volatile;


\qecho Updating geosummaries; this will take a few minutes.
select id, revision_geosummary_update(id)
  from revision
  where id>=145 and id != rid_inf();


create index revision_geometry on revision using gist (geometry);


-- rollback;
commit;

vacuum analyze revision;
