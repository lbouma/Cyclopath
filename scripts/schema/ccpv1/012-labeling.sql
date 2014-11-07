/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script builds a cache of byway geometry in order to feed to mapnik. */

begin transaction;
set constraints all deferred;

-- QGIS requires OIDs to look at the table, and OIDs are deprecated Postgres
-- thingies, so we have to explicitly include them.
create table byway_name_cache (
  name text,
  draw_class_code int not null
) WITH OIDS;
select AddGeometryColumn('byway_name_cache', 'geometry', 26915, 'LINESTRING', 2);
alter table byway_name_cache alter column geometry set not null;
alter table byway_name_cache
  add constraint enforce_valid_geometry
    check (IsValid(geometry));
create index byway_name_cache_name on byway_name_cache (name);
create index byway_name_cache_gist on byway_name_cache
  using gist ( geometry gist_geometry_ops );

\d byway_name_cache;

commit;
--rollback;
