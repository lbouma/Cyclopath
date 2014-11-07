/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Adds a table to contain the Apache log and a table containing all dates
   since we went live. */

begin transaction;
set constraints all deferred;


create view date_since_live as
select '2008-05-08'::date + s.a as day_
from generate_series(0, (current_date - '2008-05-08')) as s(a);


create table apache_event (
   id serial primary key,
   client_host text not null,
   username text,  -- no FK so deleted users can appear in logs
   timestamp_tz timestamp with time zone not null,
   request text not null,
   wfs_request text,
   status int not null,
   size int,
   time_consumed real
);
select AddGeometryColumn('apache_event', 'geometry', 26915, 'POLYGON', 2);
-- make table insert-only
create trigger apache_event_u before update on apache_event
  for each statement execute procedure fail();
-- indexes
create index apache_event_username on apache_event (username);
create index apache_event_timestamp_tz on apache_event (timestamp_tz);
create index apache_event_wfs_request on apache_event (wfs_request);
create index apache_event_geometry on apache_event using gist (geometry);


commit;
