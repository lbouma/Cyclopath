/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script modifies byway_segment to allow null geometries, but only for
   deleted byways. This allows cleanup of degenerate byways; see #588. */

begin transaction;
set constraints all deferred;

alter table byway_segment alter column geometry drop not null;
alter table byway_segment add constraint enforce_geometry_notnull
  check (deleted or (geometry is not null));

--\d revision_feedback;

commit;
