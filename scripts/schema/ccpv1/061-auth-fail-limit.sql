/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script tightens up the user security a bit, to rate-limit
   authentication failures. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

create table auth_fail_event (
  id serial not null primary key,
  username text not null,
  client_host text not null,
  ignore boolean not null default false,
  is_password boolean not null,
  created timestamp not null
);
create trigger auth_fail_event_i before insert on auth_fail_event
  for each row execute procedure set_created();
-- make table insert-only
create trigger auth_fail_event_u before update on auth_fail_event
  for each statement execute procedure fail();

\d auth_fail_event

alter table ban add column ban_all_wfs boolean;
alter table ban add column reason text;
alter table ban drop constraint ban_check1;
create index ban_expires on ban (expires);
create index ban_username on ban (username);
create index ban_ip_address on ban (ip_address);

\d ban

COMMIT;
