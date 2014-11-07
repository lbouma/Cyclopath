/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds:

   1. A table for tilecache_update.py to lock on.
   2. A generic table to hold key-value pairs.
   3. Another index on byway_segment to allow quick access by name.
   4. Rebuild byway_joined_current view. */

begin transaction;
set constraints all deferred;

create table tilecache_lock ();
\d tilecache_lock

create table key_value_pair (
   key text primary key,
   value text
);
\d key_value_pair

insert into key_value_pair (key, value) values ('tilecache_last_rid', '0');

create index byway_segment_name on byway_segment (name);

drop view byway_joined_current;
create view byway_joined_current as
SELECT
   byway_segment.id,
   byway_segment.version,
   byway_segment.name,
   byway_type.draw_class_code,
   byway_segment.geometry,
   byway_rating.value AS generic_rating
FROM byway_segment
   JOIN byway_type ON byway_segment.type_code = byway_type.code
   JOIN byway_rating ON byway_rating.byway_id = byway_segment.id
WHERE
   byway_segment.deleted = false
   AND byway_segment.valid_before_rid = rid_inf()
   AND byway_rating.username = '_cbf7_rater';

drop view bmpolygon_joined_current;
create view bmpolygon_joined_current as
SELECT
   basemap_polygon.id,
   basemap_polygon.version,
   basemap_polygon.name,
   basemap_polygon_type.draw_class_code,
   basemap_polygon.geometry
FROM basemap_polygon
   JOIN basemap_polygon_type
        ON basemap_polygon.type_code = basemap_polygon_type.code
WHERE
   basemap_polygon.deleted = false
   AND basemap_polygon.valid_before_rid = rid_inf();


--rollback;
commit;
