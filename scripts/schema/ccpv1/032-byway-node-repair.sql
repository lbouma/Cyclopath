/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds a constraint which prevents byways which are not geometric
   loops from having the same start and end nodes. */

begin transaction;
set constraints all deferred;

alter table byway_segment
  add constraint enforce_valid_loop
  check (not (    start_node_id != 0
              and   end_node_id != 0
              and start_node_id  = end_node_id
              and Distance(StartPoint(geometry), EndPoint(geometry)) > 0.001));

-- rollback;
commit;
