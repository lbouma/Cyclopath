/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the revision feedback table. */

begin transaction;
set constraints all deferred;

create table revision_feedback (
   id serial primary key,
   username text not null references user_ (username) deferrable,
   comments text not null,
   created timestamp not null
);
create index revision_feedback_username on revision_feedback (username);
create trigger revision_feedback_i before insert on revision_feedback
  for each row execute procedure set_created();
-- make table insert-only
create trigger revision_feedback_u before update on revision_feedback
  for each statement execute procedure fail();

create table revision_feedback_link (
  rf_id int not null references revision_feedback (id) deferrable,
  rid_target int unique not null references revision (id) deferrable,
  primary key (rf_id, rid_target)
);
create index revision_feedback_link_rid_target
  on revision_feedback_link (rid_target);
-- make table insert-only
create trigger revision_feedback_link_u before update on revision_feedback_link
  for each statement execute procedure fail();


--\d revision_feedback;

commit;
