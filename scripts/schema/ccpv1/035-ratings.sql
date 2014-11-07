/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script prepares a few updates related to slightly different ratings
   infrastructure (see #389). */

begin transaction;
set constraints all deferred;

delete from byway_rating where username in ('_cbf7_rater',
                                            '_naive_rater',
                                            'terveen');

insert into user_ (username, email, login_permitted, enable_wr_email)
  values ('_r_generic', null, 'f', 'f');

create index byway_rating_byway_id on byway_rating (byway_id);

drop view byway_joined_current;
create view byway_joined_current as
SELECT
   byway_segment.id,
   byway_segment.version,
   byway_segment.name,
   byway_type.draw_class_code,
   byway_segment.geometry,
   byway_rating.value AS generic_rating
FROM byway_segment
   JOIN byway_type ON byway_segment.type_code = byway_type.code
   JOIN byway_rating ON byway_rating.byway_id = byway_segment.id
WHERE
   byway_segment.deleted = false
   AND byway_segment.valid_before_rid = rid_inf()
   AND byway_rating.username = '_r_generic';

-- rollback;
commit;
