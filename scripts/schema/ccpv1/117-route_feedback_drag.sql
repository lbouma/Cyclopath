/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ========================== */
/* route_feedback_drag        */
/* ========================== */

CREATE TABLE route_feedback_drag (
   id                SERIAL PRIMARY KEY,
   username          TEXT,
   created           TIMESTAMP WITH TIME ZONE NOT NULL,
   old_route_id      INTEGER NOT NULL,
   old_route_version INTEGER NOT NULL,
   new_route_id      INTEGER NOT NULL,
   new_route_version INTEGER NOT NULL,
   old_reason        TEXT,
   new_reason        TEXT,
   change            INTEGER
);

CREATE INDEX route_feedback_drag_username
   ON route_feedback_drag (username);
CREATE INDEX route_feedback_drag_old_route_id
   ON route_feedback_drag (old_route_id);
CREATE INDEX route_feedback_drag_new_route_id
   ON route_feedback_drag (new_route_id);

ALTER TABLE route_feedback_drag 
   ADD CONSTRAINT route_feedback_drag_username_fkey 
   FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

ALTER TABLE route_feedback_drag 
   ADD CONSTRAINT route_feedback_drag_old_route_fkey 
   FOREIGN KEY (old_route_id, old_route_version)
   REFERENCES route (id, version) DEFERRABLE;

ALTER TABLE route_feedback_drag 
   ADD CONSTRAINT route_feedback_drag_new_route_fkey 
   FOREIGN KEY (new_route_id, new_route_version)
   REFERENCES route (id, version) DEFERRABLE;

CREATE TRIGGER route_feedback_drag_i BEFORE INSERT ON route_feedback_drag
  FOR EACH row EXECUTE PROCEDURE set_created();

/* Make the table insert-only. */
CREATE TRIGGER route_feedback_drag_u BEFORE UPDATE ON route_feedback_drag
  FOR EACH statement EXECUTE PROCEDURE fail();

/* ========================== */
/* route_feedback_stretch     */
/* ========================== */

CREATE TABLE route_feedback_stretch (
   id                SERIAL PRIMARY KEY,
   feedback_drag_id  INTEGER NOT NULL,
   byway_id          INTEGER NOT NULL
);

ALTER TABLE route_feedback_stretch 
   ADD CONSTRAINT route_feedback_stretch_feedback_drag_id_fkey 
   FOREIGN KEY (feedback_drag_id)
   REFERENCES route_feedback_drag (id) DEFERRABLE;

/* All done. */

COMMIT;

