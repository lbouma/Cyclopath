/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script is deprecated. See the export service network auditor.
\qecho 
/* */
ROLLBACK;

/* This script deletes bike trails which obscure other blocks. */

\set buf 2
\set length_min 50
\set rid_cur '(select max(id) from revision where id != cp_rid_inf())'

\qecho -- OK if this drop table fails
drop table overlap_bike_paths_200903;

begin;
set transaction isolation level serializable;
set constraints all deferred;

create table overlap_bike_paths_200903 (
   id int not null unique,
   version int not null,
   name text,
   start_node_id int,
   end_node_id int,
   primary key (id, version)
);
select AddGeometryColumn('overlap_bike_paths_200903', 'geometry',
                         26915, 'LINESTRING', 2);
create index overlap_bike_paths_200903_gist
   on overlap_bike_paths_200903 using gist (geometry);

-- Collect victim paths

insert into overlap_bike_paths_200903
select distinct
   path.id,
   path.version,
   path.name,
   path.start_node_id,
   path.end_node_id,
   path.geometry
from
   iv_gf_cur_byway path
   join iv_gf_cur_byway covd
      on (path.geometry && covd.geometry
          and path.type_code = 14
          and path.id != covd.id
          and ST_Length(path.geometry) > 2 * :buf
          and ((ST_Within(covd.geometry, ST_Buffer(path.geometry, :buf))
                and ST_Length(covd.geometry) >= :length_min)
               or ST_Within(path.geometry, ST_Buffer(covd.geometry, :buf))));

-- Delete victim paths

\qecho -- Number of victim paths (v)
select count(*) from overlap_bike_paths_200903;

\qecho -- Total number of active blocks (ba)
select count(*) from iv_gf_cur_byway;

\qecho -- Total number of byway_segment rows (bt)
select count(*) from byway_segment;

insert into revision (timestamp, host, username, comment)
values (now(), 'localhost', '_overlap-path-cleanup.sql',
        'Automated cleanup of bike paths which obscure other blocks');

-- create new (deleted) verisions
insert into byway_segment (
   id,
   version,
   deleted,
   name,
   type_code,
   valid_start_rid,
   valid_until_rid,
   geometry,
   start_node_id,
   end_node_id,
   paved,
   bike_lanes,
   one_way,
   speed_limit,
   outside_lane_width,
   shoulder_width,
   lane_count,
   z,
   closed,
   split_from_id
)
select
   bs.id,
   bs.version + 1,
   TRUE,
   bs.name,
   bs.type_code,
   :rid_cur,
   cp_rid_inf(),
   bs.geometry,
   bs.start_node_id,
   bs.end_node_id,
   bs.paved,
   bs.bike_lanes,
   bs.one_way,
   bs.speed_limit,
   bs.outside_lane_width,
   bs.shoulder_width,
   bs.lane_count,
   bs.z,
   bs.closed,
   NULL
from
   byway_segment bs
   join overlap_bike_paths_200903 ob on (bs.id = ob.id
                                         and bs.version = ob.version);

-- update old versions
update byway_segment
set valid_until_rid = :rid_cur
where
   (id, version) in (select id, version from overlap_bike_paths_200903);

select cp_revision_geosummary_update(:rid_cur);

\qecho -- Total number of active blocks
\qecho -- WARNING: This should equal ba - v.
select count(*) from iv_gf_cur_byway;

\qecho -- Total number of byway_segment rows
\qecho -- WARNING: This should equal bt + v
select count(*) from byway_segment;

--commit;
\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;

