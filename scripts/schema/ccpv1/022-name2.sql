/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script removes the unused attribute name2 from byway_segment. */

begin transaction;
set constraints all deferred;

drop view byway_segment_aadt;
drop view byway_joined_current_aadt;
alter table byway_segment drop column name2;

commit;
