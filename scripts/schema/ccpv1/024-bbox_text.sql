/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds a function to return the four points of a bounding box,
   separated by spaces. */

begin transaction;
set constraints all deferred;

create or replace function bbox_text(geometry) returns text as $$
   select
     XMin($1) || ' ' ||
     YMin($1) || ' ' ||
     XMax($1) || ' ' ||
     YMax($1);
$$ language sql immutable;

commit;
