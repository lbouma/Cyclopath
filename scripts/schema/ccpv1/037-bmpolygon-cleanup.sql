/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script cleans up rows in basemap_polygon which have invalid geometry,
   fixing bug #589. */

begin transaction;
set constraints all deferred;

/* This polygon breaks into a multipolygon when zero-buffered; it's a minor
   pond and expendable. */
delete from basemap_polygon where id = 368699;

update basemap_polygon
set geometry = buffer(geometry, 0)
where not isvalid(geometry);

alter table basemap_polygon add constraint enforce_valid_geometry
  check (IsValid(geometry));

--\d revision_feedback;

commit;
