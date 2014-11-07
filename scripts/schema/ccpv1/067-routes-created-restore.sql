/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the 'created' colum to the Routes table and restores the
information from a backup dump.
(NOTE: It works as long as routes are not modifiable, since it assumes that the
'last_modified' column in the current table corresponds to the creation date
for routes created after the new route database model.) */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* First stage, create the import script for the old route table. */

\! pg_restore -f temp-route-restore.sql -t route /scratch/itamae/reid/production.20090903
\! sed '1,/FROM stdin/ s/route/route1/' temp-route-restore.sql > temp-route-restore2.sql
\! rm temp-route-restore.sql

/* Second stage, execute and clean-up temporary sql file. */

\i temp-route-restore2.sql
\! rm temp-route-restore2.sql
create index route1_id on route1(id);  -- makes update later much faster

/* Third stage, add 'created' column and restore information. */

ALTER TABLE route DISABLE TRIGGER route_u;

/* Add created column and trigger. */
ALTER TABLE route ADD COLUMN created TIMESTAMP;
UPDATE route SET created=last_modified WHERE created IS NULL;
ALTER TABLE route ALTER COLUMN created SET NOT NULL;

CREATE TRIGGER route_ic BEFORE INSERT ON route
  FOR EACH ROW EXECUTE PROCEDURE set_created();

/* Copy creation data from backup. */
UPDATE route
SET created=(SELECT route1.last_modified FROM route1 WHERE route1.id = route.id)
WHERE EXISTS
   (SELECT route1.last_modified FROM route1 WHERE route1.id = route.id);

/* Routes are not yet modifiable, so we can correct last_modified this way.
Note that this has no effect on routes created after new route database
model. */
UPDATE route SET last_modified=created;

ALTER TABLE route ENABLE TRIGGER route_u;

DROP TABLE route1;

COMMIT;
