/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Add constraints to all versioned features to ensure valid versioning */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/***
   STEP 1: Add enforce_version to all versioned features
***/

ALTER TABLE annot_bs ADD CONSTRAINT enforce_version CHECK (version >= 1);
ALTER TABLE annotation ADD CONSTRAINT enforce_version CHECK (version >= 1);

-- NOTE: Original geofeatures already have this constraint
--ALTER TABLE basemap_polygon ADD CONSTRAINT enforce_version CHECK (version >= 1);
--ALTER TABLE byway_segment ADD CONSTRAINT enforce_version CHECK (version >= 1);
--ALTER TABLE point ADD CONSTRAINT enforce_version CHECK (version >= 1);

ALTER TABLE region ADD CONSTRAINT enforce_version CHECK (version >= 1);

-- NOTE: Tags are already always version=1
--ALTER TABLE tag ADD CONSTRAINT enforce_version CHECK (version >= 1);

ALTER TABLE tag_bs ADD CONSTRAINT enforce_version CHECK (version >= 1);
ALTER TABLE tag_point ADD CONSTRAINT enforce_version CHECK (version >= 1);
ALTER TABLE tag_region ADD CONSTRAINT enforce_version CHECK (version >= 1);
ALTER TABLE route ADD CONSTRAINT enforce_version CHECK (version >= 1);

-- NOTE: watch_regions all have version=0; but at the moment they aren't
-- really versioned features anyway.
--ALTER TABLE watch_region ADD CONSTRAINT enforce_version CHECK (version >= 1);

ALTER TABLE work_hint ADD CONSTRAINT enforce_version CHECK (version >= 1);

/***
   STEP 2: Make sure only one version of an object starts in any revision
***/

ALTER TABLE annot_bs ADD CONSTRAINT annot_bs_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE annotation ADD CONSTRAINT annotation_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE basemap_polygon ADD CONSTRAINT basemap_polygon_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE byway_segment ADD CONSTRAINT byway_segment_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE point ADD CONSTRAINT point_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE region ADD CONSTRAINT region_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE tag ADD CONSTRAINT tag_unique_starting_rid UNIQUE (id, valid_starting_rid);

-- FIXME: tag_bs will violate this constraint (see bug 1295)!
--ALTER TABLE tag_bs ADD CONSTRAINT tag_bs_unique_starting_rid UNIQUE (id, valid_starting_rid);

ALTER TABLE tag_point ADD CONSTRAINT tag_point_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE tag_region ADD CONSTRAINT tag_region_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE route ADD CONSTRAINT route_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE watch_region ADD CONSTRAINT watch_region_unique_starting_rid UNIQUE (id, valid_starting_rid);
ALTER TABLE work_hint ADD CONSTRAINT work_hint_unique_starting_rid UNIQUE (id, valid_starting_rid);

/***
   STEP 3: Make sure only one version of an object is removed in any revision
***/

ALTER TABLE annot_bs ADD CONSTRAINT annot_bs_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE annotation ADD CONSTRAINT annotation_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE basemap_polygon ADD CONSTRAINT basemap_polygon_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE byway_segment ADD CONSTRAINT byway_segment_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE point ADD CONSTRAINT point_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE region ADD CONSTRAINT region_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE tag ADD CONSTRAINT tag_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE tag_bs ADD CONSTRAINT tag_bs_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE tag_point ADD CONSTRAINT tag_point_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE tag_region ADD CONSTRAINT tag_region_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE route ADD CONSTRAINT route_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE watch_region ADD CONSTRAINT watch_region_unique_before_rid UNIQUE (id, valid_before_rid);
ALTER TABLE work_hint ADD CONSTRAINT work_hint_unique_before_rid UNIQUE (id, valid_before_rid);

--ROLLBACK;
COMMIT;
