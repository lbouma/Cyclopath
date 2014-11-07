/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Region table. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;


/*** Region tables ***/

CREATE TABLE region_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER region_type_u BEFORE UPDATE ON region_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER region_type_ilm BEFORE INSERT ON region_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
  

CREATE TABLE region (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  name TEXT,
  comments TEXT,
  type_code INT NOT NULL REFERENCES region_type (code) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  z INT NOT NULL,
  PRIMARY KEY (id, version)
);
SELECT AddGeometryColumn('region', 'geometry', 26915, 'POLYGON', 2);
ALTER TABLE region ALTER COLUMN geometry SET NOT NULL;
ALTER TABLE region ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));
CREATE INDEX region_gist ON region USING GIST ( geometry GIST_GEOMETRY_OPS );

ALTER TABLE watch_region ADD COLUMN comments TEXT;

/** Instances **/

INSERT INTO draw_class (code, text,     color)
                VALUES (9,    'region', X'880000'::INT);
INSERT INTO region_type (code, draw_class_code, text)
                 VALUES (2,    9,               'default');

COPY draw_param (draw_class_code, zoom, width, label) FROM STDIN;
9	9	2	t
9	10	3	t
9	11	3	t
9	12	3	t
9	13	4	t
9	14	4	t
9	15	6	t
9	16	6	t
9	17	8	t
9	18	8	t
9	19	8	t
\.

/* Make watch regions labelable */
update draw_param set label = true where draw_class_code = 6;

/* Make watch regions have fixed color */
alter table watch_region drop column color;

/* A view containing common columns of versioned geometric tables. */

drop view geofeature;

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
  from annotation_geo
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from region;

--\d region_type;
--SELECT * FROM point_type;
--\d region;
--\d geofeature;
--SELECT * FROM draw_class;
--SELECT * FROM draw_param_joined WHERE draw_class_code = 9;


/*** Region watching ***/

-- Who watches which region?
create table region_watcher (
   region_id integer not null,
   username  text not null references user_ (username) deferrable,
   primary key (region_id, username)
);

-- Combined view of private watch regions and public regions watched
create view watch_region_all as (
   select id, name, username, geometry 
   from watch_region
   where not deleted
     and notify_email
) union (
   select id, name, username, geometry 
   from region join region_watcher on (id = region_id)
   where not deleted
     and valid_before_rid = rid_inf()
);

-- FIXME: Cannot have a foreign key to a view.
alter table wr_email_pending drop constraint wr_email_pending_wrid_fkey;


/*** Region tagging ***/

CREATE TABLE tag_region (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  tag_id INT NOT NULL,   -- REFERENCES tag (id) DEFERRABLE,
  region_id INT NOT NULL, -- REFERENCES point (id) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
CREATE INDEX tag_region_tag_id on tag_region (tag_id);
CREATE INDEX tag_region_region_id on tag_region (region_id);
CREATE INDEX tag_region_valid_starting_rid on tag_region (valid_starting_rid);
CREATE INDEX tag_region_valid_before_rid on tag_region (valid_before_rid);

/* c.f. annot_bs_geo */
CREATE VIEW tag_region_geo AS
SELECT
  tr.id AS id,
  tr.version AS version,
  (r.deleted OR tr.deleted) AS deleted,
  tag_id,
  region_id,
  r.geometry AS geometry,
  GREATEST(tr.valid_starting_rid, r.valid_starting_rid) AS valid_starting_rid,
  LEAST(tr.valid_before_rid, r.valid_before_rid) AS valid_before_rid
FROM tag_region tr JOIN region r ON tr.region_id = r.id
WHERE
  tr.valid_starting_rid < r.valid_before_rid
  AND r.valid_starting_rid < tr.valid_before_rid;

/* Union of the byway, point, region views for use in tag_geo view */
CREATE OR REPLACE VIEW tag_obj_geo AS
  SELECT
    id,
    version,
    deleted,
    tag_id,
    byway_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM tag_bs_geo
UNION
  SELECT
    id,
    version,
    deleted,
    tag_id,
    point_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM tag_point_geo
UNION
  SELECT
    id,
    version,
    deleted,
    tag_id,
    region_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM tag_region_geo;

/* c.f. annotation_geo; returns tags with geometry */
CREATE OR REPLACE VIEW tag_geo as
SELECT
  t.id AS id,
  t.version AS version,
  (t.deleted or tb.deleted) as deleted,
  label,
  tb.geometry as geometry,
  GREATEST(t.valid_starting_rid, tb.valid_starting_rid) AS valid_starting_rid,
  LEAST(t.valid_before_rid, tb.valid_before_rid) AS valid_before_rid
FROM tag t JOIN tag_obj_geo tb ON t.id = tb.tag_id
WHERE
  t.valid_starting_rid < tb.valid_before_rid
  AND tb.valid_starting_rid < t.valid_before_rid;

/* A view containing common columns of versioned geometric tables. */

create or replace view geofeature as
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
  from annotation_geo
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from region
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from tag_geo;

--\d tag_region
--\d tag_region_geo
--\d tag_obj_geo
--\d tag_geo
--\d geofeature


/*** Update some revision-related things. ***/

/* We add functionality to not compute revision geometry in some cases,
   because the regions import is so large these computations crash the
   machine. */

-- If this column is true, then don't put geometry in that revision. Use for
-- revisions which are particularly massive (e.g., imports).
alter table revision add column skip_geometry boolean not null default false;

-- Update to honor skip_geometry. Previous version in
-- 034-revision-geometry.sql.
create or replace function revision_geosummary_update(rid int) returns void
as $$
declare
   skip boolean;
begin
   select skip_geometry from revision where id = rid into strict skip;
   if (skip) then
      raise notice 'skipping geometry computation';
   else
      -- Not sure why we need SetSRID() after Box2d().
      update revision
      set geometry = Multi(Buffer(revision_geometry(rid), 5, 1)),
          bbox = SetSRID(Box2d(Buffer(Box2d(revision_geometry(rid)),
                                      0.001, 1)), 26915),
          geosummary = Multi(Simplify(Buffer(revision_geometry(rid), 100, 2),
                                             25))
      where id = rid;
   end if;
end
$$ language plpgsql volatile;

-- A few existing big imports.
update revision set skip_geometry = true where id in (133, 142, 71, 70);


COMMIT;
