/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script cleans up some data which should be NULL but isn't; see #514. */

begin transaction;
set constraints all deferred;

update byway_segment
   set speed_limit = null where speed_limit = 0;

update byway_segment
   set lane_count = null where lane_count = 0;

update byway_segment
   set outside_lane_width = null where outside_lane_width = 0;

update byway_segment out
set shoulder_width = null
where
  shoulder_width = 0
  and ((version > 1 and (select shoulder_width
                         from byway_segment inn
                         where inn.id = out.id and version = 1) is null)
       or (type_code in (14, 15)));

-- rollback;
commit;
