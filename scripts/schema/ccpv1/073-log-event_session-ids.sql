/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** Add columns to log_event and apache_event tables to store browser and
    session IDs */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE log_event ADD COLUMN browid TEXT;
ALTER TABLE log_event ADD COLUMN sessid TEXT;

ALTER TABLE apache_event ADD COLUMN browid TEXT;
ALTER TABLE apache_event ADD COLUMN sessid TEXT;

CREATE VIEW log_event_joined AS
SELECT *
FROM
  log_event 
  LEFT OUTER JOIN log_event_kvp ON (log_event.id = log_event_kvp.event_id);

COMMIT;

