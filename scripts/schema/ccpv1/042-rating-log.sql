/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Adds a table to keep a log of rating changes. The byway_rating table
   continues to hold only current ratings. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

create table byway_rating_event (
   id        serial     primary key,
   username  text       not null references user_ (username) deferrable,
   byway_id  int        not null,
   value     real       not null,
   created   timestamp  not null
);
-- NOTE: set_created() trigger is below.
-- make table insert-only
create trigger byway_rating_event_u before update on byway_rating_event
  for each statement execute procedure fail();


/* Create log entries (with fake timestamps) for ratings that already exist. */
insert into byway_rating_event (username, byway_id, value, created)
select username, byway_id, value, '-infinity'::timestamp
from byway_rating
where username !~ '^_';


/* Trigger to automatically set created -- must be after above query to make
   the fake timestamps work. */
create trigger byway_rating_event_i before insert on byway_rating_event
  for each row execute procedure set_created();


commit;
