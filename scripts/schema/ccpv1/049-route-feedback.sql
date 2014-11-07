/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* A simple table to record feedback on routes */
 
begin transaction;
set constraints all deferred;

create table route_feedback (
   id serial primary key,
   route_id int not null references route (id) deferrable,
   username text references user_ (username) deferrable,
   purpose text,
   satisfaction int,
   comments text,
   created timestamp not null
);
create index route_feedback_route_id on route_feedback (route_id);
create index route_feedback_username on route_feedback (username);
create trigger route_feedback_i before insert on route_feedback
  for each row execute procedure set_created();
-- make table insert-only
create trigger route_feedback_u before update on route_feedback
  for each statement execute procedure fail();

commit;
