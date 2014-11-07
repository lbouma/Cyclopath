/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds a table to log reverts. */

begin transaction;
set constraints all deferred;

create or replace function fail() returns trigger as $$
BEGIN
   RAISE EXCEPTION 'fail() called';    
END
$$ language 'plpgsql'; 

CREATE TABLE revert_event (
   id SERIAL primary key,
   rid_reverting int not null references revision (id) deferrable,
   rid_victim int not null references revision (id) deferrable,
   created timestamp not null,
   check (rid_reverting > rid_victim)
);
CREATE INDEX revert_event_rid_victim ON revert_event (rid_victim);
CREATE TRIGGER revert_event_i
   BEFORE INSERT ON revert_event
   FOR EACH ROW EXECUTE PROCEDURE set_created();
-- make table insert-only
CREATE TRIGGER revert_event_u
   BEFORE UPDATE ON revert_event
   FOR EACH STATEMENT EXECUTE PROCEDURE fail();

\d revert_event

-- ROLLBACK;
COMMIT;

