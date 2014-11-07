/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script:

   - redefines how current versions are identifies
   - adds geometric columns to the Revision table and defines functions to
     update them
   - creates a view giving the geometry of annotations
*/

begin transaction;
set constraints all deferred;

/* Instead of current version having valid_before_rid is null, let's have
   current version be valid_before_rid = rid_inf(), which is a real int. */

create function rid_inf() returns int as $$
begin
   return 2000000000;  /* it'll be a while before we get 2G revisions... */
end
$$ language plpgsql immutable;

insert into revision (id, timestamp, host) values (rid_inf(), now(), '_DUMMY');

update basemap_polygon
   set valid_before_rid = rid_inf() where valid_before_rid is null;
alter table basemap_polygon alter column valid_before_rid set not null;

update point
   set valid_before_rid = rid_inf() where valid_before_rid is null;
alter table point alter column valid_before_rid set not null;

update byway_segment
   set valid_before_rid = rid_inf() where valid_before_rid is null;
alter table byway_segment alter column valid_before_rid set not null;

update annotation
   set valid_before_rid = rid_inf() where valid_before_rid is null;
alter table annotation alter column valid_before_rid set not null;

update annot_bs
   set valid_before_rid = rid_inf() where valid_before_rid is null;
alter table annot_bs alter column valid_before_rid set not null;


/* Create indexes for access by RID. */

create index annotation_valid_starting_rid on annotation (valid_starting_rid);
create index annotation_valid_before_rid on annotation (valid_before_rid);
create index annot_bs_valid_starting_rid on annot_bs (valid_starting_rid);
create index annot_bs_valid_before_rid on annot_bs (valid_before_rid);
create index point_valid_starting_rid on point (valid_starting_rid);
create index point_valid_before_rid on point (valid_before_rid);
create index basemap_polygon_valid_starting_rid
   on basemap_polygon (valid_starting_rid);
create index basemap_polygon_valid_before_rid
   on basemap_polygon (valid_before_rid);
create index byway_segment_valid_starting_rid
   on byway_segment (valid_starting_rid);
create index byway_segment_valid_before_rid
   on byway_segment (valid_before_rid);


/* Geometry columns in revision. */

select AddGeometryColumn('revision', 'bbox', 26915, 'POLYGON', 2);
select AddGeometryColumn('revision', 'geosummary', 26915, 'MULTIPOLYGON', 2);


/* Some views to see the geometry of annotations. */

create view annot_bs_geo as
select
  ab.id as id,
  ab.version as version,
  (bs.deleted or ab.deleted) as deleted,
  annot_id,
  --bs.id as bs_id,
  --bs.name as bs_name,
  bs.geometry as geometry,
  greatest(ab.valid_starting_rid, bs.valid_starting_rid) as valid_starting_rid,
  least(ab.valid_before_rid, bs.valid_before_rid) as valid_before_rid
from annot_bs ab join byway_segment bs on ab.byway_id = bs.id
where
  ab.valid_starting_rid < bs.valid_before_rid
  and bs.valid_starting_rid < ab.valid_before_rid;

create view annotation_geo as
select
  an.id as id,
  an.version as version,
  (an.deleted or ab.deleted) as deleted,
  comments,
  --bs_id,
  --bs_name,
  ab.geometry as geometry,
  greatest(an.valid_starting_rid, ab.valid_starting_rid) as valid_starting_rid,
  least(an.valid_before_rid, ab.valid_before_rid) as valid_before_rid
from annotation an join annot_bs_geo ab on an.id = ab.annot_id
where
  an.valid_starting_rid < ab.valid_before_rid
  and ab.valid_starting_rid < an.valid_before_rid;


/* A view containing common columns of versioned geometric tables. */

create view geofeature as
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from basemap_polygon
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from point
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from byway_segment
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from annotation_geo;


/* Some functions to manage geometry of revisions. */

create function revision_geometry(int) returns geometry as $$
   select Collect(geometry) from geofeature
   where not deleted and (valid_starting_rid = $1 or valid_before_rid = $1);
$$ language sql stable;

create function revision_geosummary_update(rid int) returns void as $$
begin
   -- Not sure why we need SetSRID() after Box2d().
   -- Docs for Buffer() say we can't pass a geometrycollection, but it works??
   update revision
   set bbox = SetSRID(Box2d(revision_geometry(rid)), 26915),
       geosummary = Multi(Simplify(Buffer(revision_geometry(rid), 200, 2), 50))
   where id = rid;
end
$$ language plpgsql volatile;


/* Update geosummaries. */
\qecho Updating geosummaries; this will take a few minutes.
select revision_geosummary_update(id)
  from revision
  where id>=145 and id != rid_inf();


-- rollback;
commit;
