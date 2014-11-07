/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script populates the item tables created in the last script.

   */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script populates the item tables created in the last script.
\qecho
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 10.5 mins. (incl. mn. and co.)]
\qecho [EXEC. TIME: 2011.05.20/Huffy: ~ 29.1 mins. (22.5 co. + 6.7 mn.)]
\qecho [EXEC. TIME: 2013.04.23/runic:    6.97 mins. [mn]]
\qecho

/* PERFORMACE NOTE: Before 2011.04.22, this script ran with indexes and
 *                  constraints on table columns. Deferring that code until
 *                  later cuts the script execution time in half, from around
 *                  20 minutes to around 10. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (2) -- ITEM VERSIONED TABLE                                     */
/* ==================================================================== */

\qecho
\qecho Creating helper functions
\qecho

/* Coalesce the versioning info. from all the pertinent tables. Note that not
   all of the tables have a name column, so we treat that column specially. */

CREATE FUNCTION iv_get_name_col(IN name_col TEXT)
   RETURNS TEXT AS $$
   BEGIN
      IF $1 = '' THEN
         RETURN ''''''; -- Return empty string string ''
      ELSE
         RETURN $1;
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION populate_item_versioned(
      IN from_table TEXT, IN name_col TEXT)
   RETURNS VOID AS $$
   BEGIN
      RAISE INFO ' ... ''%''', from_table;
      -- Absorb the contents of from_table
      /* BUG 2729: Colorado data has duplicate rows, i.e., same id and version.
       *           So we have to use DISTINCT here... */
      IF '@@@instance@@@' != 'colorado' THEN
         EXECUTE
            'INSERT INTO item_versioned
                (id, version, deleted, reverted, name,
                 valid_start_rid, valid_until_rid)
             SELECT
                id, version, deleted, FALSE,
                ' || iv_get_name_col(name_col) || ',
                valid_starting_rid, valid_before_rid
             FROM ' || from_table || ';';
      ELSE
         EXECUTE
            'INSERT INTO item_versioned
                (id, version, deleted, reverted, name,
                 valid_start_rid, valid_until_rid)
             SELECT
                DISTINCT ON (id, version) id, version, deleted, FALSE,
                ' || iv_get_name_col(name_col) || ',
                valid_starting_rid, valid_before_rid
             FROM ' || from_table || '
             ORDER BY id, version;';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho
\qecho Dropping item_versioned''s primary key
\qecho

--DROP INDEX item_versioned_pkey;
ALTER TABLE item_versioned DROP CONSTRAINT item_versioned_pkey;

\qecho
\qecho Marshalling data into table '''item_versioned'''
\qecho

/* Start with the tables that have a name column. To make this script-writer's
   job easier, I'm indicating what columns we didn't read so that I remember to
   grab that data later in this script. */

SELECT populate_item_versioned('archive_@@@instance@@@_1.basemap_polygon',
                               'name');
   --% DONE: id, version, deleted, name, valid_start_rid, valid_until_rid
   --% LEFT: type_code, geometry, z
SELECT populate_item_versioned('archive_@@@instance@@@_1.byway_segment',
                               'name');
   --% LEFT: type_code, geometry, z
   --%       one_way, speed_limit, outside_lane_width,
   --%         shoulder_width, lane_count
   --%       beg_node_id, fin_node_id, split_from_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.point', 'name');
   --% LEFT: geometry, z, type_code, comments
SELECT populate_item_versioned('archive_@@@instance@@@_1.region', 'name');
   --% LEFT: geometry, z, type_code, comments
/* NOTE 'name' is NULL for every route, and deleted is always False. */
SELECT populate_item_versioned('archive_@@@instance@@@_1.route', 'name');
   --% LEFT: owner_name, from_addr, to_addr, host, source, use_defaults,
   --%       type_code, z, created, permission, details, session_id,
   --%       link_hash_id, visibility
SELECT populate_item_versioned('archive_@@@instance@@@_1.track', 'name');
   --% LEFT: owner_name, host, source, comments, type_code, z, created,
   --%       permission, details, visibility
/* NOTE watch_region rows are all verion=0, valid_start_rid=0, and
        valid_until_rid=rid_inf() -- We'll fix the version after we
        implement access control. */
SELECT populate_item_versioned('archive_@@@instance@@@_1.watch_region',
                               'name');
   --% LEFT: geometry, z, type_code, comments, username, notify_email

/* NOTE Skipping work_hint; saving for another day/Bug
SELECT populate_item_versioned('archive_@@@instance@@@_1.work_hint',
   'name'); */
   --% LEFT: geometry, z, type_code, comments, status_code

/* There are two tables with columns like 'name' but not named 'name'. The
   team decided to move the data from these columns into 'name'. */
SELECT populate_item_versioned('archive_@@@instance@@@_1.thread', 'title');
   --% DONE: id, version, deleted, title, valid_start_rid, valid_until_rid
   --% LEFT: populatie attachment and thread tables
SELECT populate_item_versioned('archive_@@@instance@@@_1.tag', 'label');
   --% DONE: id, version, deleted, label, valid_start_rid, valid_until_rid
   --% LEFT: populate attachment and tag tables

/* These tables all lack a name column. */
SELECT populate_item_versioned('archive_@@@instance@@@_1.annot_bs', '');
   --% LEFT: annot_id, byway_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.annotation', '');
   --% LEFT: comments
SELECT populate_item_versioned('archive_@@@instance@@@_1.post', '');
   --% LEFT: body, thread_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.post_bs', '');
   --% LEFT: post_id, byway_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.post_point', '');
   --% LEFT: post_id, point_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.post_region', '');
   --% LEFT: post_id, region_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.post_revision', '');
   --% LEFT: post_id, revision_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.post_route', '');
   --% LEFT: post_id, revision_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.tag_bs', '');
   --% LEFT: tag_id, byway_id
SELECT populate_item_versioned('archive_@@@instance@@@_1.tag_point', '');
   --% LEFT: tag_id, point_id
/* 2012.02.08: This is taking a while on huffy. 'top' suggests 4GB RAM is not
           enough, so the slowness is probably just paged memory swapping. */
SELECT populate_item_versioned('archive_@@@instance@@@_1.tag_region', '');
   --% LEFT: tag_id, region_id

/* Cleanup the fcns. we no longer need. */
DROP FUNCTION populate_item_versioned(IN from_table TEXT, IN name_col TEXT);
DROP FUNCTION iv_get_name_col(IN name_col TEXT);

/* ==================================================================== */
/* Step (3) -- GEOMETRY TABLES                                          */
/* ==================================================================== */

\qecho
\qecho Creating helper functions to populate geofeature
\qecho

/* FIXME/BUG nnnn: A bunch of these:

PL/pgSQL function "populate_geofeature" line 46 at EXECUTE statement
NOTICE:  Self-intersection at or near point 492084 4.99014e+06
CONTEXT:  SQL statement "INSERT INTO geofeature
(id, version, geometry, z, geofeature_layer_id, username, notify_email)
SELECT layer_tbl.id, layer_tbl.version, layer_tbl.geometry,
layer_tbl.z, gfl.id, username, notify_email
FROM public.geofeature_layer AS gfl
JOIN archive_1.watch_region_type AS layer_type
ON gfl.feat_type = 'region_watched'
AND gfl.layer_name = layer_type.text
JOIN archive_minnesota_1.watch_region
AS layer_tbl
ON layer_type.code = layer_tbl.type_code
WHERE ST_IsValid(layer_tbl.geometry);"

*/

/* Create a temporary utility function to assist with table population. */
CREATE FUNCTION populate_geofeature(IN archive_geo_tbl TEXT,
                                    IN new_feat_type TEXT,
                                    IN archive_type_tbl TEXT)
   RETURNS VOID AS $$
   DECLARE
      exec_str TEXT;
   BEGIN
      /* When we populated the geofeature_layer table in the shared script, we
         changed the IDs of most of the existing types, except for
         byway_segment. So we need to do some joins to figure out the correct
         IDs to use. */
      /* NOTE We made a row in item_versioned earlier, so the (id, version)
              foreign key already exists. */
      /* Build the start of the SQL query... */
      exec_str := 'INSERT INTO geofeature
         (id, version, geometry, z, geofeature_layer_id';
      /* NOTE This is kinda kludgy, but who cares; we'll fix this later, rather
              than complicating things now. For some tables, we maintain a
              few columns to ease implementation of arbitrary attributes.
              Check the geofeature type to see what columns to keep. */
      IF archive_geo_tbl = 'byway_segment' THEN
         exec_str := exec_str
                     || ', one_way, beg_node_id, fin_node_id, split_from_id';
      ELSIF archive_geo_tbl = 'watch_region' THEN
         exec_str := exec_str || ', username, notify_email';
      END IF;
      exec_str := exec_str || ')
          SELECT layer_tbl.id, layer_tbl.version, layer_tbl.geometry,
             layer_tbl.z, gfl.id';
      /* NOTE: start_node_id is renamed beg_node_id in V2. */
      /* NOTE: end_node_id   is renamed fin_node_id in V2. */
      IF archive_geo_tbl = 'byway_segment' THEN
         exec_str := exec_str
                     || ', layer_tbl.one_way
                         , layer_tbl.start_node_id
                         , layer_tbl.end_node_id
                         , layer_tbl.split_from_id';
      ELSIF archive_geo_tbl = 'watch_region' THEN
         exec_str := exec_str || ', username, notify_email';
      END IF;
       exec_str := exec_str || '
          FROM public.geofeature_layer AS gfl
             JOIN archive_1.' || archive_type_tbl || ' AS layer_type
                  ON gfl.feat_type = ''' || new_feat_type || '''
                     AND gfl.layer_name = layer_type.text
             JOIN archive_@@@instance@@@_1.' || archive_geo_tbl || '
                     AS layer_tbl
                  ON layer_type.code = layer_tbl.type_code
          WHERE ST_IsValid(layer_tbl.geometry);';
/* FIXME: How many rows are not ST_IsValid? Are they important? */
      EXECUTE exec_str;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* */

\qecho
\qecho Indexing archival tables'' type_code columns
\qecho

/* EXPLAIN: Why is the bmp type code index defined but not the others? */

--CREATE INDEX basemap_polygon_type_code
--   ON archive_minnesota_1.basemap_polygon (type_code);

/*
CREATE INDEX byway_segment_type_code
   ON archive_minnesota_1.byway_segment (type_code);

CREATE INDEX point_type_code
   ON archive_minnesota_1.point (type_code);

CREATE INDEX region_type_code
   ON archive_minnesota_1.region (type_code);

CREATE INDEX route_type_code
   ON archive_minnesota_1.route (type_code);

CREATE INDEX track_type_code
   ON archive_minnesota_1.track (type_code);

CREATE INDEX watch_region_type_code
   ON archive_minnesota_1.watch_region (type_code);
*/
/* Populate the geofeature table. */

\qecho
\qecho Dropping geofeature''s primary key
\qecho

--DROP INDEX geofeature_pkey;
ALTER TABLE geofeature DROP CONSTRAINT geofeature_pkey;
ALTER TABLE geofeature DROP CONSTRAINT enforce_dims_geometry;
ALTER TABLE geofeature DROP CONSTRAINT enforce_srid_geometry;

/* FIXME: These are the PostGIS defaults. Note: missing third enforce_

    "enforce_dims_geometry" CHECK (ndims(geometry) = 2)
    "enforce_srid_geometry" CHECK (srid(geometry) = 26915)
*/

\qecho
\qecho Populating table '''geofeature'''
\qecho

/* FINDME / TESTING: Comment-out for speedy testing; add ROLLBACK at EOF. */

\qecho ... adding terrain
SELECT populate_geofeature('basemap_polygon', 'terrain',
                           'basemap_polygon_type');
   --% All data consumed; done w/ basemap_polygon

\qecho ... adding byway
SELECT populate_geofeature('byway_segment', 'byway',
                           'byway_type');
   --% LEFT: one_way, speed_limit, outside_lane_width, shoulder_width,
   --%       lane_count
   --% SEE AUDITOR.SQL: CONSTRAINT enforce_one_way CHECK ((one_way = -1) ... )

\qecho ... adding waypoint
SELECT populate_geofeature('point', 'waypoint',
                           'point_type');
   --% LEFT: comments

\qecho ... adding region
SELECT populate_geofeature('region', 'region',
                           'region_type');
   --% LEFT: comments

\qecho ... adding route
/* type_code is 2 for all rows (default); z is 160 for all of 'em... */
/* NOTE route doesn't have any geometry, but we fake an empty linestring
        just so we can call it a geofeature. */
ALTER TABLE archive_@@@instance@@@_1.route
   ADD COLUMN geometry GEOMETRY
   DEFAULT ST_GeomFromText('LINESTRING EMPTY', cp_srid());
SELECT populate_geofeature('route', 'route',
                           'route_type');
   --% LEFT: owner_name, from_addr, to_addr, host, source, use_defaults,
   --%       created, permission, details, session_id,
   --%       link_hash_id, visibility

\qecho ... adding track
/* NOTE track doesn't have any geometry, but we fake an empty polygon
        just so we can call it a geofeature. */
ALTER TABLE archive_@@@instance@@@_1.track
   ADD COLUMN geometry GEOMETRY
   DEFAULT ST_GeomFromText('LINESTRING EMPTY', cp_srid());
SELECT populate_geofeature('track', 'track',
                           'track_type');
   --% LEFT: owner_name, host, source, comments, type_code, z, created,
   --%       permission, details, visibility

/* NOTE  A bunch of watch_regions have invalid geometries. This includes 79
         deleted watch_regions and 1 un-deleted watch_region. The deleted
         watch_regions we can just whack. For the un-deleted region, I'd rather
         not just drop it, but it seems a waste of time to deal with it.

         (IsValid(geometry) returns false, and trying to populate the
         geofeature table with these rows causes the following error:

             NOTICE: Self-intersection at or near point 466311 4.97372e+06
             ERROR:  new row for relation "geofeature"
                     violates check constraint enforce_valid_geometry

         To protect user's identify, I won't display the username here; you
         can find it with:

            SELECT * FROM watch_region
               WHERE NOT ST_IsValid(geometry) AND NOT deleted;

         Once you have the name, run this query:

            SELECT ST_AsText(geometry) FROM watch_region
               WHERE username='[REDACTED]';

         And you'll get:

            POLYGON((465799.8 4969046.4,
                     474766.2 4974790.4,
                     474766.2 4971257.6,
                     469063.8 4971257.6,
                     465799.8 4969046.4))

         You can also use ST_AsSVG instead of ST_AsText to get a string for an
         SVG file. Then, to see the offending geometry, make a byway1.svg file
         and write to it:

         <?xml version="1.0" standalone="no"?>
         <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN"
           "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
         <svg width="12cm" height="12cm"
              viewBox="465799.0 -4974791.0 10000 10000"
              xmlns="http://www.w3.org/2000/svg" version="1.1">
           <title>Bad path geometry</title>
           <desc>A path that draws a triangle</desc>
           <rect x="465799" y="-4974791" width="9990" height="9990"
                 fill="none" stroke="blue" stroke-width="100" />
           <path d="M 465799.799999999988358 -4969046.400000000372529
                      474766.200000000011642 -4974790.400000000372529
                      474766.200000000011642 -4971257.599999999627471
                      469063.799999999988358 -4971257.599999999627471 Z"
                 fill="red" stroke="blue" stroke-width="100" />
         </svg>

         Note that the last point overlaps the line from the first to the
         second point. If you delete the first point, you're left with a
         simple triangle; this is probably the region the user intended. To
         see it, replace path above with:

          <path d="M 474766.200000000011642 -4974790.400000000372529
                     474766.200000000011642 -4971257.599999999627471
                     469063.799999999988358 -4971257.599999999627471 Z"

         I tried running a PostGIS command to replace the incorrect geometry
         with the correct one, but I'm getting errors; in the interest of
         moving forward (and not being held up by one person's watch region,
         especially by a user who hasn't logged in since we added logins to the
         log table), we'll go the path of not copying over invalid geometries
         from the old watch_region table, that is, in populate_geofeature:

            WHERE ST_IsValid(geometry)

         which was added to populate_geofeature() for this problem.
   */

/* FIXME Does ST_IsValid actually work? I still get errors
         -- do a count(*) on archive.watch_region and compare to new schema
*/

/*
   2012.09.20: [lb] is seeing lots of self-intersection warnings.
               I don't remember these.

FIXME: Verify the watch_region table is copied correctly.

   #  NOTICE:  Self-intersection at or near point 466311.07413709193 49
   #  73723.5322885616
   #  CONTEXT:  SQL statement "INSERT INTO geofeature
   #  (id, version, geometry, z, geofeature_layer_id, username, notify_
   #  email)
   #  SELECT layer_tbl.id, layer_tbl.version, layer_tbl.geometry,
   #  layer_tbl.z, gfl.id, username, notify_email
   #  FROM public.geofeature_layer AS gfl
   #  JOIN archive_1.watch_region_type AS layer_type
   #  ON gfl.feat_type = 'region_watched'
   #  AND gfl.layer_name = layer_type.text
   #  JOIN archive_minnesota_1.watch_region
   #  AS layer_tbl
   #  ON layer_type.code = layer_tbl.type_code
   #  WHERE ST_IsValid(layer_tbl.geometry);"
   #  PL/pgSQL function "populate_geofeature" line 47 at EXECUTE statement

*/

\qecho ... adding region_watched
SELECT populate_geofeature('watch_region', 'region_watched',
                           'watch_region_type');
   --% LEFT: comments

/* NOTE Skipping work_hint; see [private bug] Bug 734
\qecho ... adding region_work_hint
SELECT populate_geofeature('work_hint', 'region_work_hint',
                           'work_hint_type');
   --% LEFT: status_code, comments */

/* NOTE These tables also have geometries, but they're not part of geofeature
           Table apache_event            // log table, not neceassry to capture
           Table tiles_cache_byway_names // used by tilecache_update.py
           Table revision                // uses computed aggregate value of
                                            multiple geometries */

/* NOTE Skipping these tables with geometry because they're old n' obsolete:
           Table county
           Table urban_area */

/* Cleanup */
DROP FUNCTION populate_geofeature(IN archive_geo_tbl TEXT,
                                  IN new_feat_type TEXT,
                                  IN archive_type_tbl TEXT);

\qecho
\qecho Fixing NOT NULL on geometry column
\qecho

\qecho
\qecho FIXME: Make sure this still works! Last time I ran it, said: UPDATE 0
\qecho        but maybe this is just the colorado instance? urs: @@@instance@@@
\qecho

/* There are currently 71 rows with null geometry -- Bug 588 -- which we
   correct here so we can apply a NOT NULL constraint on the new geofeature
   table. (Not a big deal: These rows are all marked deleted. And 23 are at
   version 1.) I wonder if this is/was a bug saving... like, create a byway in
   your working copy, delete it, and then save.... */
UPDATE geofeature
   SET geometry = ST_GeomFromText('LINESTRING EMPTY', cp_srid())
   WHERE geometry IS NULL;
ALTER TABLE geofeature ALTER COLUMN geometry SET NOT NULL;

\qecho
\qecho Recreating geofeature''s primary key
\qecho

ALTER TABLE geofeature
   ADD CONSTRAINT geofeature_pkey
   PRIMARY KEY (id, version);

/* Added in PostGIS 1.4.0:
 *    SELECT Populate_Geometry_Columns('minnesota.geofeature'::regclass);
 *
 * But we still want to be 1.3.6 compatible, at least for now, so we
 * explicitly recreate the checks.
 */

\set dimension 2

ALTER TABLE geofeature
   ADD CONSTRAINT enforce_dims_geometry
   CHECK (ndims(geometry) = :dimension);

ALTER TABLE geofeature
   ADD CONSTRAINT enforce_srid_geometry
   CHECK (srid(geometry) = cp_srid());

/* ==================================================================== */
/* Step (4) -- POPULATE ATTACHMENT TABLES                               */
/* ==================================================================== */

\qecho
\qecho Creating helper functions
\qecho

CREATE FUNCTION attr_attachment_create(IN iv_name TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      iv_id INTEGER;
   BEGIN
      /* NOTE Using start revision ID 1 since these attributes are inherent
              to the system, i.e., they've existed since the big bang. */
      INSERT INTO item_versioned
         (version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (1, iv_name, FALSE, FALSE, 1, cp_rid_inf());
      iv_id := CURRVAL('item_versioned_id_seq');
      INSERT INTO attachment (id, version) VALUES (iv_id, 1);
      RETURN iv_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ======================== */
/* ATTRIBUTES               */
/* ======================== */

CREATE FUNCTION attribute_create(
      IN attr_name TEXT,
      IN attr_value_internal_name TEXT,
      IN attr_spf_field_name TEXT,
      IN attr_value_type TEXT,
      IN attr_value_hints TEXT,
      IN attr_value_units TEXT,
      IN attr_value_minimum INTEGER,
      IN attr_value_maximum INTEGER,
      IN attr_value_stepsize INTEGER,
      IN attr_gui_sortrank INTEGER,
      IN attr_applies_to_type_id INTEGER,
      IN attr_uses_custom_control BOOLEAN,
      IN attr_is_directional BOOLEAN)
   RETURNS INTEGER AS $$
   DECLARE
      iv_id INTEGER;
   BEGIN
      /* Create the attachment row, which creates the item_versioned row. */
      iv_id := attr_attachment_create(attr_name);
      /* Create the attribute row. */
      INSERT INTO attribute (
            id,
            version,
            value_internal_name,
            spf_field_name,
            value_type,
            value_hints,
            value_units,
            value_minimum,
            value_maximum,
            value_stepsize,
            gui_sortrank,
            applies_to_type_id,
            uses_custom_control,
            value_restraints,
            multiple_allowed,
            is_directional)
         VALUES (
               iv_id,
               1,
               attr_value_internal_name,
               attr_spf_field_name,
               attr_value_type,
               attr_value_hints,
               attr_value_units,
               attr_value_minimum,
               attr_value_maximum,
               attr_value_stepsize,
               attr_gui_sortrank,
               attr_applies_to_type_id,
               attr_uses_custom_control,
               NULL,
               FALSE,
               attr_is_directional);
      RETURN iv_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ========================== */
/* BYWAY_SEGMENT LINK_VALUES  */
/* ========================== */

CREATE FUNCTION link_value_create_from_bs(
      IN lv_id INTEGER,
      IN lv_vers INTEGER,
      IN bs archive_@@@instance@@@_1.byway_segment,
      IN lv_value_int INTEGER,
      IN lv_lhs_id INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      new_lv_id INTEGER;
      use_vers INTEGER;
   BEGIN
      use_vers := lv_vers;
      /* Create a new item_versioned row. The item_versioned and
         link_value are considered deleted if the byway_segment is. */
      IF lv_id = 0 THEN
         /* Sanity check. */
         IF bs.version != 1 THEN
            RAISE EXCEPTION
               'Creating new link_value but byway_segment version not 1';
         END IF;
         use_vers := 1;
         INSERT INTO item_versioned
            (version, deleted, reverted,
             valid_start_rid, valid_until_rid)
         VALUES
            (use_vers, bs.deleted, FALSE,
             bs.valid_starting_rid, bs.valid_before_rid);
         new_lv_id := CURRVAL('item_versioned_id_seq');
      ELSE
         new_lv_id := lv_id;
         INSERT INTO item_versioned
            (id, version, deleted, reverted,
             valid_start_rid, valid_until_rid)
         VALUES
            (new_lv_id, use_vers, bs.deleted, FALSE,
             bs.valid_starting_rid, bs.valid_before_rid);
      END IF;
      /* Create the link_value row. */
      INSERT INTO link_value (id, version, value_integer, lhs_id, rhs_id)
         VALUES (new_lv_id, use_vers, lv_value_int, lv_lhs_id, bs.id);
      RETURN new_lv_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION link_value_update(
      IN lv_id INTEGER,
      IN lv_vers INTEGER,
      IN bs archive_@@@instance@@@_1.byway_segment)
   RETURNS VOID AS $$
   BEGIN
      UPDATE item_versioned SET valid_until_rid = bs.valid_before_rid
         WHERE id = lv_id AND version = lv_vers;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE In the old database, where attributes are columns in byway_segment,
        some cells, like lots of outside_lane_width cells, are NULL. E.g.,

         select count(*) from archive_minnesota_1.byway_segment
            where outside_lane_width is null;
         --------
         217859

         select count(*) from archive_minnesota_1.byway_segment
            where outside_lane_width is not null;
         -------
         775

      Regarding NULL, the following are counts from the old byway_segment
      table and the number of link_value rows we created running this script:

         218,634 have one_way; 0 do not [However, 195,860 have it set to 0]
                 [so 22774 max; 1821 set to -1 and 20953 set to 1]
                 [17,980 created]
         159,531 have speed_limit; 59,103 do not
                 [136,851 created]
         138,651 have shoulder_width; 79,983 do not
                 [116,814 created]
         148,234 have lane_count; 70,400 do not
                 [125,499 created]
             775 have outside_lane_width; 217,859 do not
                 [1014 created -- null got copied as some version 1s]
         (That's from 218,661 byway_segment rows in mpls; 377,124 in denver.)

      Regarding Zero values:

         124,882 shoulder_widths are 0; this value is meaningful, since 0 means
            the shoulder doesn't exist, and NULL means the information has not
            been entered
         There are 0 lane_counts of 0.
         There are 0 outside_lane_widths of 0.
         There are 0 speed_limits of 0.
         There are 195,860 one_way values of 0; this value is meaningless if
            it's always been 0 for the life of a byway_segment, since it
            defaults to 0 (just like shoulder_width defaults to NULL). However,
            if the value got set to 1 or -1, saved, and then set back to 0,
            that means something, and we need to keep that information for the
            history.

      So, we can ignore all NULL cells, and we can ignore 0-valued one_way
      cells, but only if the value is the same throughout all byway versions
      for each particular id.

      Number of unique byways:

         select count(*) from
            (select count(*) from byway_segment group by id) as a;
         --------
          165945

*/

CREATE FUNCTION byway_attribute_delete_meaningless(IN link_value_id INTEGER)
   RETURNS VOID AS $$
   DECLARE
      num_rows INTEGER;
   BEGIN
      num_rows := COUNT(*) FROM link_value WHERE id = link_value_id;
      --RAISE INFO 'Deleting (%) Link_Value rows with id = %',
      --            num_rows, link_value_id;
      DELETE FROM link_value WHERE id = link_value_id;
      DELETE FROM item_versioned WHERE id = link_value_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION byway_attribute_create_and_populate(
      IN old_byway_col_name TEXT,
      IN new_attr_name TEXT,
      IN can_ignore_zeros BOOLEAN,
      IN attr_value_internal_name TEXT,
      IN attr_spf_field_name TEXT,
      IN attr_value_hints TEXT,
      IN attr_value_units TEXT,
      IN attr_value_minimum INTEGER,
      IN attr_value_maximum INTEGER,
      IN attr_value_stepsize INTEGER,
      IN attr_gui_sortrank INTEGER,
      IN attr_applies_to_type_id INTEGER,
      IN attr_uses_custom_control BOOLEAN,
      IN attr_is_directional BOOLEAN)
   RETURNS VOID AS $$
   DECLARE
      -- list of byway_segment records
      bs archive_@@@instance@@@_1.byway_segment%ROWTYPE;
      -- last record examined
      prev_bs archive_@@@instance@@@_1.byway_segment%ROWTYPE;
      is_first_record BOOLEAN;      -- TRUE if first time through loop
      attribute_id INTEGER;         -- The new attribute ID
      lv_int_rec RECORD;            -- link_value of attr. in bs
      prev_lv_int_rec RECORD;       -- link_value of attr. in prev_bs
      link_value_id INTEGER;        -- Revision ID when attr. last updated
      link_value_vers INTEGER;      -- Revision vers. when attr. last updated
      is_value_always_zero BOOLEAN; -- if the value is zero for all versions
      total_new_ver1 INTEGER;
      total_new_ver2 INTEGER;
      total_deleted INTEGER;
      total_vers_ignored INTEGER;
      total_vers_updated INTEGER;
   BEGIN
      /* Make an attribute for the column we want to nix from byway_segment */
      attribute_id := attribute_create(
         new_attr_name,
         attr_value_internal_name,
         attr_spf_field_name,
         'integer',
         attr_value_hints,
         attr_value_units,
         attr_value_minimum,
         attr_value_maximum,
         attr_value_stepsize,
         attr_gui_sortrank,
         attr_applies_to_type_id,
         attr_uses_custom_control,
         attr_is_directional);
      /* Initialize loop vars */
      is_first_record := TRUE;
      is_value_always_zero := FALSE;
      total_new_ver1 := 0;
      total_new_ver2 := 0;
      total_deleted := 0;
      total_vers_ignored := 0;
      total_vers_updated := 0;
      /* Iterate through byway_segment and marshall the data around */
      FOR bs IN SELECT * FROM archive_@@@instance@@@_1.byway_segment
            ORDER BY id, version LOOP
         /* NOTE one_way is smallint and the rest aren't, so we ::cast */
         EXECUTE 'SELECT *, bs.' || old_byway_col_name || '::INTEGER AS lv_int
            FROM archive_@@@instance@@@_1.byway_segment AS bs WHERE id = '
               || bs.id || ' AND version = ' || bs.version || ';'
               INTO STRICT lv_int_rec;
         IF is_first_record THEN
            prev_bs = bs; -- This is a hack for the first record
            prev_lv_int_rec = lv_int_rec;
         END IF;
         IF is_first_record OR prev_bs.id != bs.id THEN
            /* Before we create the new record, see if we can't delete the last
               one if it's value was always NULL or 0. */
            IF (NOT is_first_record) AND (is_value_always_zero) THEN
               PERFORM byway_attribute_delete_meaningless(link_value_id);
               total_deleted := total_deleted + 1;
            END IF;
            /* First time viewing this particular ID, so make new link_value */
            link_value_id := 0; -- Tells our helper fcn. to get a new ID
            link_value_vers := 1;
            /* If the value can be ignored, ignore it; otherwise, store it. */
            --RAISE INFO 'ignore?: % / lv_int: %', can_ignore_zeros,
            --            lv_int_rec.lv_int;
            /* In the Minnesota instance, one_way is never NULL; in the
               Colorado instance, it's NULL if it's not set. So for
               Minnesota, see if it's zero; for Colorado, check if NULL. */
            is_value_always_zero := FALSE;
            IF (can_ignore_zeros) THEN
               IF ('@@@instance@@@' = 'minnesota') THEN
                  IF (lv_int_rec.lv_int = 0) THEN
                     --RAISE INFO '{is zero}: Byway.%.%',
                     --           bs.id, old_byway_col_name;
                     is_value_always_zero := TRUE;
                  END IF;
               ELSIF ('@@@instance@@@' = 'colorado') THEN
                  IF (lv_int_rec.lv_int IS NULL) THEN
                     --RAISE INFO '{is null}: Byway.%.%', bs
                     --           .id, old_byway_col_name;
                     is_value_always_zero := TRUE;
                  END IF;
               ELSE
                  RAISE NOTICE 'Instance not recognized! %', '@@@instance@@@';
               END IF;
            ELSIF (NOT can_ignore_zeros) AND (lv_int_rec.lv_int IS NULL) THEN
               --RAISE INFO 'Found {is null}: Byway.%.%',
               --           bs.id, old_byway_col_name;
               is_value_always_zero := TRUE;
            END IF;
            link_value_id := link_value_create_from_bs(link_value_id,
               link_value_vers, bs, lv_int_rec.lv_int, attribute_id);
            total_new_ver1 := total_new_ver1 + 1;
         END IF;
         IF (NOT is_first_record) AND (prev_bs.id = bs.id) THEN
            /* This is version 2 or greater of the byway_segment we examined
               last time through the loop, so update link_value. If the
               attribute didn't change, we just bump valid_until_rid;
               otherwise, we need a new link_value record with a new version
               number. */
            IF is_value_always_zero THEN
               IF (can_ignore_zeros) THEN
                  IF ('@@@instance@@@' = 'minnesota') THEN
                     IF (lv_int_rec.lv_int != 0) THEN
                        --RAISE INFO 'No longer {is zero}!';
                        is_value_always_zero := FALSE;
                     END IF;
                  ELSIF ('@@@instance@@@' = 'colorado') THEN
                     IF (lv_int_rec.lv_int IS NOT NULL) THEN
                        --RAISE INFO 'No longer {is null}!';
                        is_value_always_zero := FALSE;
                     END IF;
                  ELSE
                     RAISE NOTICE 'Instance not recognized! %',
                                  '@@@instance@@@';
                  END IF;
               ELSIF (NOT can_ignore_zeros)
                      AND (lv_int_rec.lv_int IS NOT NULL) THEN
                  --RAISE INFO 'No longer {is null}!';
                  is_value_always_zero := FALSE;
               END IF;
            END IF;
            /* NOTE Can't compare NULL and INTEGER, so check NULLs, too. */
            IF     (lv_int_rec.lv_int IS NOT NULL
                    AND prev_lv_int_rec.lv_int IS NULL)
                OR (lv_int_rec.lv_int IS NULL
                    AND prev_lv_int_rec.lv_int IS NOT NULL)
                OR (lv_int_rec.lv_int != prev_lv_int_rec.lv_int) THEN
               IF is_value_always_zero THEN
                  RAISE EXCEPTION 'Programming error';
               END IF;
               /* Value changed; created new link_value */
               link_value_vers := link_value_vers + 1;
               link_value_id := link_value_create_from_bs(link_value_id,
                  link_value_vers, bs, lv_int_rec.lv_int, attribute_id);
               total_new_ver2 := total_new_ver2 + 1;
               total_vers_updated := total_vers_updated + 1;
            ELSE
               /* Value didn't change; just update valid_until_id */
               PERFORM link_value_update(link_value_id, link_value_vers, bs);
               total_vers_ignored := total_vers_ignored + 1;
            END IF;
         END IF;
         prev_bs := bs; /* Remember this record */
         prev_lv_int_rec := lv_int_rec;
         is_first_record := FALSE;
      END LOOP;
      /* See if the last record can be deleted, since we didn't make it back
         to the top of the loop for the last record. */
      IF is_value_always_zero THEN
         PERFORM byway_attribute_delete_meaningless(link_value_id);
         total_deleted := total_deleted + 1;
      END IF;
      /* Display some stats on what just happened. */
      /* NOTE This information can be misleading if misread, so don't pay
              too much attention to it. */
      RAISE INFO 'added links: ver1: % | ver2+: % / deleted links: ver 1: %',
                  total_new_ver1, total_new_ver2, total_deleted;
      RAISE INFO 'total new links: % / of byway versions: diff: % / same: %',
                  total_new_ver1 + total_new_ver2 - total_deleted,
                  total_vers_updated, total_vers_ignored;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho
\qecho Indexing item_versioned''s id and version
\qecho

CREATE INDEX item_versioned_id ON item_versioned (id);
CREATE INDEX item_versioned_version ON item_versioned (version);
CREATE INDEX item_versioned_id_version ON item_versioned (id, version);

CREATE INDEX link_value_id ON link_value (id);

\qecho
\qecho Dropping link_value''s primary key
\qecho

--DROP INDEX link_value_pkey;
ALTER TABLE link_value DROP CONSTRAINT link_value_pkey;

\qecho
\qecho Creating and populating byway_segment attrs: one_way, etc.
\qecho

/* FINDME / TESTING: Comment-out for speedy testing; add ROLLBACK at EOF. */

\qecho ... '''one_way'''
\qecho 2012.09.20: Time: 0m 47s
\qecho 2012.09.23: Time: 0m 48s [co: 1m 17s]
SELECT byway_attribute_create_and_populate(
   'one_way', 'Direction', TRUE,
   '/byway/one_way', 'one_way',
   'Direction of traffic (one-way or two-way).', '',
   '-1', '1', '1',   -- Min, Max, StepSize
   '1',              -- GUI Order
   (SELECT id FROM item_type WHERE type_name = 'byway'), -- applies to byways
   TRUE, FALSE);     -- Custom GUI control, Is-directional
-- FIXME Impl. one_way_constraint in pyserver; one_way in (-1, 0, 1)

/* NOTE GUI Order (gui_sortrank) for position 2 is reserved for Z-level */

\qecho ... '''speed_limit'''
\qecho 2012.09.20: Time: 0m 39s
\qecho 2012.09.23: Time: 0m 40s [co: 1m 16s]
SELECT byway_attribute_create_and_populate(
   'speed_limit', 'Speed limit', FALSE,
   '/byway/speed_limit', 'speedlimit',
   'Posted speed limit for all traffic.', 'mph',
   '0', '75', '5',   -- Min, Max, StepSize
   '3',              -- GUI Order
   (SELECT id FROM item_type WHERE type_name = 'byway'), -- applies to byways
   FALSE, FALSE);    -- Custom GUI control, Is-directional

\qecho ... '''lane_count'''
\qecho 2012.09.20: Time: 0m 40s
\qecho 2012.09.23: Time: 0m 40s [co: 1m 09s]
SELECT byway_attribute_create_and_populate(
   'lane_count', 'Total number of lanes', FALSE,
   '/byway/lane_count', 'lane_count',
   'Number of lanes of traffic in either or both directions.', '',
   '0', '12', '1',   -- Min, Max, StepSize
   '4',              -- GUI Order
   (SELECT id FROM item_type WHERE type_name = 'byway'), -- applies to byways
   FALSE, TRUE);     -- Custom GUI control, Is-directional

\qecho ... '''outside_lane_width'''
\qecho 2012.09.20: Time: 0m 47s
\qecho 2012.09.23: Time: 0m 52s [co: 1m 09s]
SELECT byway_attribute_create_and_populate(
   'outside_lane_width', 'Width of outside lane', FALSE,
   '/byway/outside_lane_width', 'out_ln_wid',
   'Exclude shoulder and bike lane.', 'feet',
   '0', '24', '1',   -- Min, Max, StepSize
   '5',              -- GUI Order
   (SELECT id FROM item_type WHERE type_name = 'byway'), -- applies to byways
   FALSE, TRUE);     -- Custom GUI control, Is-directional

\qecho ... '''shoulder_width'''
\qecho 2012.09.20: Time: 0m 40s
\qecho 2012.09.23: Time: 0m 39s [co: 1m 14s]
SELECT byway_attribute_create_and_populate(
   'shoulder_width', 'Usable shoulder space', FALSE,
   '/byway/shoulder_width', 'shld_width',
   'Include width of bike lane, if any.', 'feet',
   '0', '24', '1',  -- Min, Max, StepSize
   '6',              -- GUI Order
   (SELECT id FROM item_type WHERE type_name = 'byway'), -- applies to byways
   FALSE, TRUE);     -- Custom GUI control, Is-directional

--% All data consumed; done w/ byway_segment

/* Cleanup */
DROP FUNCTION byway_attribute_create_and_populate(
   IN old_byway_col_name TEXT,
   IN new_attr_name TEXT,
   IN can_ignore_zeros BOOLEAN,
   IN attr_value_internal_name TEXT,
   IN attr_value_spf_field_name TEXT,
   IN attr_value_hints TEXT,
   IN attr_value_units TEXT,
   IN attr_value_minimum INTEGER,
   IN attr_value_maximum INTEGER,
   IN attr_value_stepsize INTEGER,
   IN attr_gui_sortrank INTEGER,
   IN attr_applies_to_type_id INTEGER,
   IN attr_uses_custom_control BOOLEAN,
   IN attr_is_directional BOOLEAN);
DROP FUNCTION byway_attribute_delete_meaningless(
   IN link_value_id INTEGER);
DROP FUNCTION link_value_update(
   IN lv_id INTEGER,
   IN lv_vers INTEGER,
   IN bs archive_@@@instance@@@_1.byway_segment);
DROP FUNCTION link_value_create_from_bs(
   IN lv_id INTEGER,
   IN lv_vers INTEGER,
   IN bs archive_@@@instance@@@_1.byway_segment,
   IN lv_value_int INTEGER,
   IN lv_lhs_id INTEGER);

\qecho
\qecho Dropping temporary indexes
\qecho

DROP INDEX item_versioned_id;
DROP INDEX item_versioned_version;
DROP INDEX item_versioned_id_version;

DROP INDEX link_value_id;

/* ====== */
/* ROUTES */
/* ====== */

\qecho
\qecho Dropping route''s primary key
\qecho

ALTER TABLE route DROP CONSTRAINT route_pkey;

\qecho
\qecho Populating table '''route'''
\qecho

/* NOTE: Not populating calculated columns; skipping: beg_addr, fin_addr,
         n_steps, beg_nid, fin_nid, rsn_min, rsn_max. */
INSERT INTO route (
      id, version, depart_at, travel_mode, transit_pref,
      use_defaults, details, source,
      owner_name, host, session_id, created,
      link_hash_id, cloned_from_id,
      permission, visibility)
   SELECT
      id, version, depart_at, travel_mode, transit_pref,
      use_defaults, details, source,
      owner_name, host, session_id, created,
      link_hash_id, cloned_from_id,
      permission, visibility
   FROM archive_@@@instance@@@_1.route;

/* ====== */
/* TRACKS */
/* ====== */

\qecho
\qecho Dropping track''s primary key
\qecho

ALTER TABLE track DROP CONSTRAINT track_pkey;

\qecho
\qecho Populating table '''track'''
\qecho

INSERT INTO track (id, version, owner_name, host, source, comments,
                   created, permission, visibility)
   SELECT id, version, owner_name, host, source, comments,
          created, permission, visibility
   FROM archive_@@@instance@@@_1.track;

\qecho
\qecho Populating track_point.step_number
\qecho

/* FIXME: BUG 2407: In V1, track.id is *the* unique id, but it should be a step
 *        number, lest we run out of unique IDs! (assuming we want to support
 *        >2^32 track_points). */

/* 2012.09.20: We have just over 100,000 track_points, and this fcn. runs in
 * about 10 secs. (assuming the id column is indexed (see below)). */

CREATE FUNCTION track_point_step_number_populate()
   RETURNS VOID AS $$
   DECLARE
      tp track_point%ROWTYPE;
      cur_track_id INTEGER;
      cur_step_num INTEGER;
   BEGIN
      cur_track_id := 0;
      FOR tp IN SELECT * FROM track_point
            ORDER BY track_id ASC, track_version ASC, id ASC LOOP
         IF (cur_track_id != tp.track_id) THEN
            cur_step_num := 1;
            cur_track_id = tp.track_id;
         END IF;
         UPDATE track_point
            SET step_number = cur_step_num
            WHERE id = tp.id;
         cur_step_num := cur_step_num + 1;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* 2012.09.20: The fcn. is taking minutes and minutes (actually, I [lb] don't
 * know how long; I gave up waiting and wrote a new fcn. before realizing the
 * table was missing an index! Regardless, this fcn. works and runs in 11 secs.
 */
/* This is just the same fcn, a little bit diff'rently writ than the previous:
CREATE FUNCTION track_point_step_number_populate()
   RETURNS VOID AS $$
   DECLARE
      sid_rec RECORD;
      tp_rec RECORD;
      cur_track_id INTEGER;
      cur_step_num INTEGER;
   BEGIN
      CREATE TEMPORARY TABLE tp_lookup (
         tp_id INTEGER,
         stack_id INTEGER,
         version INTEGER);
      INSERT INTO tp_lookup (tp_id, stack_id, version)
         SELECT id, track_id, track_version FROM track_point;
      FOR sid_rec IN SELECT DISTINCT(stack_id) FROM tp_lookup
      LOOP
         cur_step_num := 1;
         FOR tp_rec IN SELECT tp_id FROM tp_lookup
            WHERE stack_id = sid_rec.stack_id
            ORDER BY stack_id ASC, version ASC, tp_id ASC
         LOOP
            UPDATE track_point
               SET step_number = cur_step_num
               WHERE id = tp_rec.tp_id;
            cur_step_num := cur_step_num + 1;
         END LOOP;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;
*/

/* 2012.09.20: The track_point table in CcpV1 has no pkey and doesn't index id.
               But we need to index id for our update fcn. to run quickly.
               (and we'll make the primary key later). */
-- FIXME: audit all tables and check for pkeys and indices, esp. tables from
--        route sharing and route reactions... and tracks.
DROP INDEX IF EXISTS track_point_id;
CREATE INDEX track_point_id ON track_point (id);

-- FIXME: Why does this fcn. take so long??
\qecho 2012.09.20: Time: 10049.148 ms
SELECT track_point_step_number_populate();

DROP FUNCTION track_point_step_number_populate();

/* ===================================== */
/* Tags                    & Link Values */
/* ===================================== */

/** link_value instances / Not Attributes **/

\qecho
\qecho Creating helper functions
\qecho

CREATE FUNCTION attachment_populate(IN tbl_name TEXT)
   RETURNS VOID AS $$
   /* BUG 2729: Colorado data has duplicate rows in annotation and annot_bs. */
   BEGIN
      IF '@@@instance@@@' != 'colorado' THEN
         EXECUTE 'INSERT INTO attachment (id, version)
                  SELECT id, version FROM ' || tbl_name || ';';
      ELSE
         EXECUTE 'INSERT INTO attachment (id, version)
                  SELECT DISTINCT ON (id, version) id, version
                  FROM ' || tbl_name || '
                  ORDER BY id, version;';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION link_value_populate(IN src_table TEXT, IN lhs_id_col TEXT,
      IN rhs_id_col TEXT)
   RETURNS VOID AS $$
   BEGIN
      /* BUG 2729: Colorado data has duplicate rows. */
      /* What should be the proper way, if there weren't duplicate rows in
       * colorado's annotation and annot_bs... and hopefully this won't affect
       * runtimes... */
      IF '@@@instance@@@' != 'colorado' THEN
         EXECUTE 'INSERT INTO link_value (id, version, lhs_id, rhs_id)
                  SELECT id, version,
                  ' || lhs_id_col || ', ' || rhs_id_col || '
                  FROM ' || src_table || ';';
      ELSE
         EXECUTE 'INSERT INTO link_value (id, version, lhs_id, rhs_id)
                  SELECT DISTINCT ON (id, version) id, version,
                  ' || lhs_id_col || ', ' || rhs_id_col || '
                  FROM ' || src_table || '
                  ORDER BY id, version;';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/** link_value instances / Tags **/

\qecho
\qecho Dropping attachment''s primary key
\qecho

--DROP INDEX attachment_pkey;
ALTER TABLE attachment DROP CONSTRAINT attachment_pkey;

\qecho
\qecho Populating attachment and link_value tables for tag
\qecho

\qecho ...populating 'attachment' from archived 'tag'
SELECT attachment_populate('archive_@@@instance@@@_1.tag');

\qecho ...populating 'tag' from archived 'tag'
INSERT INTO tag (id, version) SELECT id, version
   FROM archive_@@@instance@@@_1.tag;
--% All data consumed; done w/ tag

\qecho ...populating 'link_value' from archived 'tag_bs'
SELECT link_value_populate('archive_@@@instance@@@_1.tag_bs',
                           'tag_id', 'byway_id');
--% All data consumed; done w/ tag_bs

\qecho ...populating 'link_value' from archived 'tag_point'
SELECT link_value_populate('archive_@@@instance@@@_1.tag_point',
                           'tag_id', 'point_id');
--% All data consumed; done w/ tag_point

\qecho ...populating 'link_value' from archived 'tag_region'
SELECT link_value_populate('archive_@@@instance@@@_1.tag_region',
                           'tag_id', 'region_id');
--% All data consumed; done w/ tag_region

/* ===================================== */
/* Byway Annotations       & Link Values */
/* ===================================== */

/** link_value instances / Annotations (Byway Notes) **/

\qecho
\qecho Populating attachment tables with byway_segment annotations
\qecho

/* NOTE Here's how the old db handles annotations being cleared and deleted.
          1. I added a note ('9999') to a byway and saved;
          2. I changed the note to the empty string and saved;
          3. I deleted the note and saved.
        This is the view of the database after 1-3:

cycling=> select * from annotation where id=1500096;
   id    | vers | del | comments | valid_starting_rid | valid_before_rid
---------+------+-----+----------+--------------------+------------------
 1500096 |    1 | f   | 9999     |              12797 |            12798
 1500096 |    2 | f   |          |              12798 |            12799
 1500096 |    3 | t   |          |              12799 |       2000000000
(3 rows)

cycling=> select * from annot_bs where annot_id=1500096;
   id    | vers | del | annot_id | byway_id | v_start_rid | v_until_rid
---------+------+-----+----------+----------+----------------+--------------
 1500097 |    1 | f   |  1500096 |  1115523 |          12797 |        12799
 1500097 |    2 | t   |  1500096 |  1115523 |          12799 |   2000000000
(2 rows)

cycling=> select id,version,deleted,name,valid_starting_rid,valid_until_rid
          from byway_segment where id=1115523;
   id    | vers | del |      name      | valid_starting_rid | valid_before_rid
---------+------+-----+----------------+--------------------+------------------
 1115523 |    1 | f   | E Hennepin Ave |                133 |              267
 1115523 |    2 | f   | E Hennepin Ave |                267 |              328
 1115523 |    3 | f   | E Hennepin Ave |                328 |             1033
 1115523 |    4 | f   | E Hennepin Ave |               1033 |            10973
 1115523 |    5 | f   | E Hennepin Ave |              10973 |       2000000000
(5 rows)

So byway_segment is never touched,
   link_value is only touched when the note is deleted, and
   annotation is always touched. */

\qecho ...populating 'attachment' from archived 'annotation'
SELECT attachment_populate('archive_@@@instance@@@_1.annotation');
--% LEFT: comments

/*

  BUG 2729: The colorado data has duplicate rows, i.e., same id and version.
  There's also no primary key and other constraints missing from
  the colorado table... what the hey?!

  SELECT * FROM annotation order by id,version

  has comments from valid_starting_rid 67 to 86, or 2010-07-22 to 2011-05-07
  (the last co revision is 87, on 2011-07-23).
*/
\qecho ...populating 'annotation' from archived 'annotation'
/* This code works on Mn, but on Co the data is broken!
INSERT INTO annotation (id, version, comments)
   SELECT id, version, comments FROM archive_@@@instance@@@_1.annotation;
*/
/* This isn't a fcn, so skipping: IF '@@@instance@@@' != 'colorado' THEN */
INSERT INTO annotation (id, version, comments)
   SELECT DISTINCT ON (id, version) id, version, comments
   FROM archive_@@@instance@@@_1.annotation ORDER by id, version;
--% All data consumed; done w/ annotation

/* BUG 2729: Colorado data has duplicate rows, i.e., same id and version.
             So we have to use DISTINCT here...
             The problem seems to affect the annotation and annot_bs tables.
             Both are missing the same three constraints:
    "annotation_pkey" PRIMARY KEY, btree (id, version)
    "annotation_unique_before_rid" UNIQUE, btree (id, valid_before_rid)
    "annotation_unique_starting_rid" UNIQUE, btree (id, valid_starting_rid)
    "annot_bs_pkey" PRIMARY KEY, btree (id, version)
    "annot_bs_unique_before_rid" UNIQUE, btree (id, valid_before_rid)
    "annot_bs_unique_starting_rid" UNIQUE, btree (id, valid_starting_rid)
*/
\qecho ...populating 'link_value' from archived 'annot_bs'
SELECT link_value_populate('archive_@@@instance@@@_1.annot_bs',
                           'annot_id', 'byway_id');
--% All data consumed; done w/ annot_bs

/* ===================================== */
/* Threads and Posts       & Link Values */
/* ===================================== */

/** link_value instances / Discussions **/

\qecho
\qecho Populating attachment tables for discussions
\qecho

\qecho ...populating 'attachment' from archived 'thread'
SELECT attachment_populate('archive_@@@instance@@@_1.thread');

\qecho ...populating 'thread' from archived 'thread'
INSERT INTO thread (id, version, ttype)
   SELECT id, version, ttype
   FROM archive_@@@instance@@@_1.thread;
--% All data consumed; done w/ thread.
-- 2012.10.31: There's a new column, thread_type_id, which
--             we'll populate later.

/* Make attachment rows for each post. */
\qecho ...populating 'attachment' from archived 'post'
SELECT attachment_populate('archive_@@@instance@@@_1.post');

/* Make post rows for each post. */
\qecho ...populating 'post' from archived 'post'
INSERT INTO post (id, version, thread_id, body, polarity)
   SELECT id, version, thread_id, body, polarity
   FROM archive_@@@instance@@@_1.post;
--% All data consumed; done w/ post

/* Make link_value rows for each post. */

\qecho ...populating 'link_value' from archived 'post_bs'
SELECT link_value_populate('archive_@@@instance@@@_1.post_bs',
                           'post_id', 'byway_id');
--% All data consumed; done w/ post_bs

\qecho ...populating 'link_value' from archived 'post_point'
SELECT link_value_populate('archive_@@@instance@@@_1.post_point',
                           'post_id', 'point_id');
--% All data consumed; done w/ post_point

\qecho ...populating 'link_value' from archived 'post_region'
SELECT link_value_populate('archive_@@@instance@@@_1.post_region',
                           'post_id', 'region_id');
--% All data consumed; done w/ post_region

/* FIXME: Is this okay? Or do we need to use, e.g., /post/route attribute? */
\qecho ...populating 'link_value' from archived 'post_route'
SELECT link_value_populate('archive_@@@instance@@@_1.post_route',
                           'post_id', 'route_id');
--% All data consumed; done w/ post_route

/* Cleanup */
DROP FUNCTION link_value_populate(IN src_table TEXT, IN lhs_id_col TEXT,
                                  IN rhs_id_col TEXT);
DROP FUNCTION attachment_populate(IN tbl_name TEXT);

/* Posts can link to revisions. In V1, this is via post_revision. In V2,
 * this is via a link_value linking the post and the '/post/revision'
 * attribute. */

\qecho
\qecho Consuming post_revision table
\qecho

CREATE FUNCTION link_value_consume_post_revision()
   RETURNS VOID AS $$
   DECLARE
      attribute_id INTEGER; -- The new attribute ID
   BEGIN
      RAISE INFO '...creating "/post/revision" attribute';
      attribute_id := attribute_create(
         'Revision ID',
         '/post/revision',
         'post_rev',
         'integer',
         '',     --     attr_value_hints
         '',     --     attr_value_units
         NULL,   --  0, attr_value_minimum
         NULL,   -- -1, attr_value_maximum
         NULL,   --     attr_value_stepsize
         NULL,   --  0, attr_gui_sortrank
         (SELECT id FROM item_type WHERE type_name = 'post'),
         TRUE,   --     attr_uses_custom_control
         FALSE); --     attr_is_directional
      EXECUTE 'INSERT INTO link_value (id, version, lhs_id, rhs_id,
                                       value_integer)
               SELECT id, version, post_id, ' || attribute_id || ', rev_id
               FROM archive_@@@instance@@@_1.post_revision;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT link_value_consume_post_revision();
--% All data consumed; done w/ post_revision

/* Cleanup */
DROP FUNCTION link_value_consume_post_revision();

/* ===================================== */
/* Other Annotations       & Link Values */
/* ===================================== */

/** link_value instances / Point, Region and Region_Watched Annotations
    (formerly: "Notes" (colloquial) or "comments" (SQL column)) **/

\qecho
\qecho Creating helper functions
\qecho

CREATE FUNCTION link_value_create(IN gf_id INTEGER, IN at_id INTEGER,
      IN start_rid INTEGER)
   RETURNS VOID AS $$
   DECLARE
      lv_id INTEGER;
   BEGIN
      INSERT INTO item_versioned
         (version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (1, '', FALSE, FALSE, start_rid, cp_rid_inf());
      lv_id := CURRVAL('item_versioned_id_seq');
      INSERT INTO link_value (id, version, lhs_id, rhs_id)
         VALUES (lv_id, 1, at_id, gf_id);
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION annotation_create(IN p_comments TEXT, IN start_rid INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      annot_id INTEGER;
   BEGIN
      INSERT INTO item_versioned
         (version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (1, '', FALSE, FALSE, start_rid, cp_rid_inf());
      annot_id := CURRVAL('item_versioned_id_seq');
      INSERT INTO attachment (id, version)
         VALUES (annot_id, 1);
      INSERT INTO annotation (id, version, comments)
         VALUES (annot_id, 1, p_comments);
      RETURN annot_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION annotation_change_comments(IN annot_id INTEGER,
      IN old_vers INTEGER, IN new_comments TEXT,
      IN start_rid INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      new_vers INTEGER;
   BEGIN
      IF old_vers < 1 THEN
         RAISE EXCEPTION 'Please specify old_vers >= 1 (You specified %)',
                         old_vers;
      END IF;
      new_vers := old_vers + 1;
      /* Correct the old_vers' until_rid before creating the new version */
      UPDATE item_versioned
         SET valid_until_rid = start_rid
         WHERE id = annot_id and version = old_vers;
      /* Create a the new version */
      INSERT INTO item_versioned
         (id, version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (annot_id, new_vers, '', FALSE, FALSE,
          start_rid, cp_rid_inf());
      /* Make the attachment record. */
      INSERT INTO attachment
         (id, version)
      VALUES
         (annot_id, new_vers);
      /* Make the annotation record. */
      INSERT INTO annotation
         (id, version, comments)
      VALUES
         (annot_id, new_vers, new_comments);
      /* Return the new item version. */
      RETURN new_vers;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* In the old database, annot_bs is kind of like link_value. When a user
   creates a new note, a new feat_vers gets created for annot_bs and persists
   until the note is deleted. However, points and regions store comments in
   their tables, so points or regions have historically only ever had one
   comment each. This changes with the new database, and we need to decide how
   to populate link_value knowing this.

   For instance, suppose a new point is created without a comment. In the old
   database, comments is NULL. Next, let's suppose the user adds a comment and
   saves, deletes the comment and saves again, and then adds a new comment and
   saves a fourth time. In the database, you'll get a new point at version 2
   with the comments set, a new point at version 3 with comments back to NULL,
   and a new point at version 4 with comments set again to another string.

   So the question is -- are the comments in version 2 and version 4 considered
   different annotations or not?

   They are not different annotations, is the answer. The way to think about
   this is that points and regions have always had one note associated with
   them, implicitly created as soon as the first comments for that point or
   region is created. So setting a comment to '' in flashclient, which causes
   the database to NULLify comments, isn't really indicating that the
   annotation is marked deleted, but rather that its comments where changed to
   '' and that it still lives on as the same note. */
CREATE FUNCTION annotations_create(IN tbl_name TEXT,
                                   IN tbl_id INTEGER)
   RETURNS VOID AS $$
   DECLARE
      r RECORD;
      annot_id INTEGER;
      annot_vers INTEGER;
      comments TEXT;
      comments_prev TEXT;
   BEGIN
      annot_id := -1;
      annot_vers := 1;
      comments_prev := NULL;
      /* We were passed one point or region ID; loop through each of its
         versions */
      FOR r IN EXECUTE 'SELECT * FROM ' || tbl_name || '
                        WHERE id = ' || tbl_id || '
                        ORDER BY version ASC' LOOP
         /* Per discussion above, store empty string, not NULL. We also can't
            compare NULL and TEXT (i.e., NULL != 'string' returns NULL). */
         comments = r.comments;
         IF comments IS NULL THEN
            comments = '';
         END IF;
         /* In the special case that comments are NULL throughout each version
            of the point or region, don't bother making an annotation or
            link_value. In other words, wait 'til the first non-NULL comment
            before making the annotation and link_value. */
         IF r.comments IS NOT NULL AND annot_id = -1 THEN
            annot_id := annotation_create(comments, r.valid_starting_rid);
            PERFORM link_value_create(r.id, annot_id, r.valid_starting_rid);
         ELSIF comments_prev != comments THEN
            /* Create a new row in annotation; nothing to do to link_value. */
            annot_vers := annotation_change_comments(annot_id, annot_vers,
               comments, r.valid_starting_rid);
         END IF;
         comments_prev = comments;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION annotations_consume_all(IN tbl_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      r RECORD;
   BEGIN
      FOR r IN EXECUTE 'SELECT id FROM ' || tbl_name || ' GROUP BY id' LOOP
         PERFORM annotations_create(tbl_name, r.id);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE The following operation must come after loading annot_bs because the
        prior operation used archive_@@@instance@@@_1.annot_bs's IDs, versions,
        and rids. Since points and regions had their notes stored in a column
        in their tables, we need to make new item_versioned IDs for point
        and region annotations. */

/** link_value instances / Annotations (Point and Region Notes) **/

\qecho
\qecho Consuming point and region comments
\qecho

\qecho ...point
\qecho 2012.09.20: Time: 28365.238 ms
SELECT annotations_consume_all('archive_@@@instance@@@_1.point');
--% All data consumed; done w/ point

\qecho ...region
SELECT annotations_consume_all('archive_@@@instance@@@_1.region');
--% All data consumed; done w/ region

/* NOTE We'll consume watch region annotations when we implement access
        control. */

\qecho
\qecho Cleaning up helper functions
\qecho

/* Cleanup */
DROP FUNCTION annotations_consume_all(IN tbl_name TEXT);
DROP FUNCTION annotations_create(IN tbl_name TEXT, IN tbl_id INTEGER);
DROP FUNCTION annotation_change_comments(IN annot_id INTEGER,
      IN old_vers INTEGER, IN new_comments TEXT,
      IN start_rid INTEGER);
DROP FUNCTION annotation_create(IN p_comments TEXT, IN start_rid INTEGER);
DROP FUNCTION link_value_create(IN gf_id INTEGER, IN at_id INTEGER,
      IN start_rid INTEGER);

/* =========== */
/* CLEANUP     */
/* =========== */

/* PERF. (2011.04.26) I [lb] split the -22- script into two files -- one to
 * NOTE:              create tables, and one to populate tables -- but my
 *                    attempts to decrease script execution time were in vain.
 *                    The section above, "populating byway_segment attrs",
 *                    takes a long time, and I don't think we have much we can
 *                    do about it. We have to go through the byway column
 *                    row-by-row, for each column that we're making a new
 *                    attribute, so I think it's just a slow op. */

\qecho
\qecho Recreating item_versioned''s primary key
\qecho

ALTER TABLE item_versioned
   ADD CONSTRAINT item_versioned_pkey
   PRIMARY KEY (id, version);

\qecho
\qecho Recreating link_value''s primary key
\qecho

ALTER TABLE link_value
   ADD CONSTRAINT link_value_pkey
   PRIMARY KEY (id, version);

\qecho
\qecho Recreating attachment''s primary key
\qecho

ALTER TABLE attachment
   ADD CONSTRAINT attachment_pkey
   PRIMARY KEY (id, version);

\qecho
\qecho Recreating route''s primary key
\qecho

ALTER TABLE route
   ADD CONSTRAINT route_pkey
   PRIMARY KEY (id, version);

\qecho
\qecho Recreating track''s primary key
\qecho

ALTER TABLE track
   ADD CONSTRAINT track_pkey
   PRIMARY KEY (id, version);

/* ===================================================== */
/* CLEANUP                                               */
/* ===================================================== */

DROP FUNCTION attribute_create(
   IN attr_name TEXT,
   IN attr_value_internal_name TEXT,
   IN attr_value_spf_field_name TEXT,
   IN attr_value_type TEXT,
   IN attr_value_hints TEXT,
   IN attr_value_units TEXT,
   IN attr_value_minimum INTEGER,
   IN attr_value_maximum INTEGER,
   IN attr_value_stepsize INTEGER,
   IN attr_gui_sortrank INTEGER,
   IN attr_applies_to_type_id INTEGER,
   IN attr_uses_custom_control BOOLEAN,
   IN attr_is_directional BOOLEAN);
DROP FUNCTION attr_attachment_create(
   IN iv_name TEXT);

/* ========================================================================= */
/* Step (n) -- All done!                                                     */
/* ========================================================================= */

\qecho
\qecho Done!
\qecho

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;

