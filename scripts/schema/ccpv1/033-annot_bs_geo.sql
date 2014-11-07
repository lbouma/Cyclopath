/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Update the annot_bs_geo view to include the byway id col */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP VIEW geofeature;
DROP VIEW annotation_geo;
DROP VIEW annot_bs_geo;

create view annot_bs_geo as
select
  ab.id as id,
  ab.version as version,
  (bs.deleted or ab.deleted) as deleted,
  annot_id,
  bs.id as byway_id,
  --bs.name as bs_name,
  bs.geometry as geometry,
  greatest(ab.valid_starting_rid, bs.valid_starting_rid) as valid_starting_rid,
  least(ab.valid_before_rid, bs.valid_before_rid) as valid_before_rid
from annot_bs ab join byway_segment bs on ab.byway_id = bs.id
where
  ab.valid_starting_rid < bs.valid_before_rid
  and bs.valid_starting_rid < ab.valid_before_rid;

/** Below recreates the dropped views as is.  We had to drop them to satisfy
    psql **/
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

COMMIT;
