/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Tables to log, and facilitate persistence of, routefinder preferences. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

-- Routefinder Priority (distance vs. bikeability);
ALTER TABLE user_ ADD rf_priority REAL;

-- Log of changes to user preferences
CREATE TABLE user_preference_event (
   id SERIAL PRIMARY KEY,
   username TEXT NOT NULL REFERENCES user_ (username) DEFERRABLE,
   enable_wr_email BOOLEAN,
   rf_priority REAL,
   created TIMESTAMP NOT NULL
);
CREATE TRIGGER user_preference_event_i BEFORE INSERT ON user_preference_event
  FOR EACH ROW EXECUTE PROCEDURE set_created();
CREATE TRIGGER user_preference_event_u BEFORE UPDATE ON user_preference_event
  FOR EACH STATEMENT EXECUTE PROCEDURE fail();

-- Tag Preference Types
CREATE TABLE tag_preference_type (
  code INT PRIMARY KEY,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER tag_preference_type_u BEFORE UPDATE ON tag_preference_type 
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER tag_preference_type_i BEFORE INSERT ON tag_preference_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

INSERT INTO tag_preference_type VALUES (0, 'ignore');
INSERT INTO tag_preference_type VALUES (1, 'bonus');
INSERT INTO tag_preference_type VALUES (2, 'penalty');
INSERT INTO tag_preference_type VALUES (3, 'avoid');

-- Tag Preferences
CREATE TABLE tag_preference (
  username TEXT NOT NULL REFERENCES user_ (username) DEFERRABLE,
  tag_id INT NOT NULL, -- REFERENCES tag (id) DEFERRABLE,
  type_code INT NOT NULL REFERENCES tag_preference_type (code) DEFERRABLE,
  enabled BOOLEAN NOT NULL,
  last_modified TIMESTAMP NOT NULL,
  PRIMARY KEY (username, tag_id)  
);
CREATE INDEX tag_preference_tag_id ON tag_preference (tag_id);
CREATE TRIGGER tag_preference_u BEFORE UPDATE ON tag_preference
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER tag_preference_ilm BEFORE INSERT ON tag_preference
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

-- Default (generic) preferences
INSERT INTO tag_preference (username, tag_id, type_code, enabled) VALUES
  ('_r_generic', (SELECT id FROM tag WHERE label='closed'), 3, TRUE);

-- Log of changes to tag preferences
CREATE TABLE tag_preference_event (
   id SERIAL PRIMARY KEY,
   username TEXT NOT NULL REFERENCES user_ (username) DEFERRABLE,
   tag_id INT NOT NULL, -- REFERENCES tag (id) DEFERRABLE,
   type_code INT NOT NULL REFERENCES tag_preference_type (code) DEFERRABLE,
   enabled BOOLEAN NOT NULL,
   created TIMESTAMP NOT NULL
);
CREATE TRIGGER tag_preference_event_i BEFORE INSERT ON tag_preference_event
  FOR EACH ROW EXECUTE PROCEDURE set_created();
CREATE TRIGGER tag_preference_event_u BEFORE UPDATE ON tag_preference_event
  FOR EACH STATEMENT EXECUTE PROCEDURE fail();

-- Log routefinder preferences with each route
-- FIXME: these tables use last_modified for consistency with route and
-- route_step.  However, the route is only saved once, so created would be
-- more appropriate for all four tables (and route_digest).
CREATE TABLE route_tag_preference (
   route_id INT NOT NULL REFERENCES route (id) DEFERRABLE,
   tag_id INT NOT NULL, -- REFERENCES tag (id) DEFERRABLE,
   type_code INT NOT NULL REFERENCES tag_preference_type (code) DEFERRABLE,
   last_modified TIMESTAMP NOT NULL,
   PRIMARY KEY (route_id, tag_id)
);
CREATE TRIGGER route_tag_preference_u BEFORE UPDATE ON route_tag_preference
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_tag_preference_ilm BEFORE INSERT ON route_tag_preference
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

CREATE TABLE route_priority (
   route_id INT NOT NULL REFERENCES route (id) DEFERRABLE,
   priority TEXT NOT NULL,
   value REAL,
   last_modified TIMESTAMP NOT NULL,
   PRIMARY KEY (route_id, priority)
);
CREATE TRIGGER route_priority_u BEFORE UPDATE ON route_priority
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_priority_ilm BEFORE INSERT ON route_priority
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

-- Other route logging improvements
ALTER TABLE route ADD from_addr TEXT;
ALTER TABLE route ADD to_addr TEXT;
-- FIXME: Cannot reference route (id) since older route digests do not have
-- route ids
ALTER TABLE route_digest ADD route_id INT; --REFERENCES route (id) DEFERRABLE;

COMMIT;
