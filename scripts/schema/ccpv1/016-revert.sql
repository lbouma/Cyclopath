/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

drop function revision_geosummary_update(int);
drop function revision_geometry(int);
drop view geofeature;
drop view annotation_geo;
drop view annot_bs_geo;
select DropGeometryColumn('revision', 'geosummary');
select DropGeometryColumn('revision', 'bbox');
/*
drop index byway_segment_valid_before_rid;
drop index byway_segment_valid_starting_rid;
drop index basemap_polygon_valid_before_rid;
drop index basemap_polygon_valid_starting_rid;
drop index point_valid_before_rid;
drop index point_valid_starting_rid;
drop index annot_bs_valid_before_rid;
drop index annot_bs_valid_starting_rid;
drop index annotation_valid_before_rid;
drop index annotation_valid_starting_rid;
*/
drop function rid_inf();
