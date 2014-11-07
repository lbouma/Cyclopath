/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds a closed attribute to Byway_Segment. */

begin transaction;
set constraints all deferred;

alter table byway_segment add column closed boolean;

commit;
