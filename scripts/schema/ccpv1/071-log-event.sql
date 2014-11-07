/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** Create the tables necessary to store the new and improved logging events */

/* Start IDs at ten million to leave a hole starting at zero to import into.
   (Estimated with "zcat *.gz | grep request=Null | wc", which gives 400k.) */

CREATE SEQUENCE log_event_id_seq START 10000000;

CREATE TABLE log_event (
  id INT PRIMARY KEY DEFAULT nextval('log_event_id_seq'),
  client_host TEXT NOT NULL,
  username TEXT REFERENCES user_(username) DEFERRABLE,
  created TIMESTAMP NOT NULL,
  timestamp_client TIMESTAMP WITH TIME ZONE NOT NULL,
  facility TEXT NOT NULL
);

CREATE TRIGGER log_event_ic BEFORE INSERT ON log_event
  FOR EACH ROW EXECUTE PROCEDURE set_created();
-- make table insert-only
create trigger log_event_u before update on log_event
  for each statement execute procedure fail();

CREATE TABLE log_event_kvp (
  event_id INT NOT NULL REFERENCES log_event (id) DEFERRABLE,
  key_ TEXT NOT NULL,
  value TEXT,
  PRIMARY KEY (event_id, key_)
);
-- make table insert-only
create trigger log_event_kvp_u before update on log_event_kvp
  for each statement execute procedure fail();

