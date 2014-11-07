/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Revert everything done in 044-tag.sql */

BEGIN TRANSACTION;

DROP VIEW geofeature;
DROP VIEW tag_geo;
DROP VIEW tag_obj_geo;
DROP VIEW tag_bs_geo;
DROP VIEW tag_point_geo;
DROP TABLE tag;
DROP TABLE tag_bs;
DROP TABLE tag_point;

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
