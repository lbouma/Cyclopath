/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the User_ and Byway Rating tables */


/** More timestamp stuff **/

CREATE OR REPLACE FUNCTION set_created() RETURNS TRIGGER AS '
  BEGIN 
    NEW.created = now();
    RETURN NEW;
  END
' LANGUAGE 'plpgsql';


/** Tables **/

CREATE TABLE user_ (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT,
  login_permitted BOOLEAN NOT NULL,
  last_modified TIMESTAMP NOT NULL,
  created TIMESTAMP NOT NULL
);
CREATE TRIGGER user_u BEFORE UPDATE ON user_
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER user_ilm BEFORE INSERT ON user_
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER user_ic BEFORE INSERT ON user_
  FOR EACH ROW EXECUTE PROCEDURE set_created();

CREATE TABLE byway_rating (
  user_id INT NOT NULL,
  byway_id INT NOT NULL,
  value REAL NOT NULL,
  last_modified TIMESTAMP NOT NULL,
  PRIMARY KEY (user_id, byway_id)  
);
CREATE TRIGGER byway_rating_u BEFORE UPDATE ON byway_rating
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER byway_rating_ilm BEFORE INSERT ON byway_rating
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


/** Instances **/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

COMMIT;
