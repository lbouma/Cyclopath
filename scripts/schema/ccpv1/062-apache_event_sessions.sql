/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This file populates a table apache_event_sessions containing apparent user
   sessions on the application. */

begin;
set constraints all deferred;

create table apache_event_session (
  id serial primary key,
  user_ text not null,
  hit_count int not null,
  time_start timestamp with time zone not null,
  time_end timestamp with time zone not null
);
create index apache_event_session_user
  on apache_event_session (user_);
create index apache_event_session_time_start
  on apache_event_session (time_start);
create index apache_event_session_time_end
  on apache_event_session (time_end);

commit;
