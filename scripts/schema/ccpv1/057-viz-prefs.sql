/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;

/** Create an INSERT ONLY node_attributes table.  This table MUST be truncated
    and recreated when new attributes are added. Upon creation the elevation
    update script should be run to insert elevations into the database for
    the first time. **/

CREATE TABLE node_attribute (
  node_id INT UNIQUE NOT NULL PRIMARY KEY, 
  elevation_meters REAL NOT NULL
);

CREATE TRIGGER node_insert_only BEFORE UPDATE ON node_attribute
   FOR EACH ROW EXECUTE PROCEDURE fail();

/** Create a visualization table. This is really a hack to substitute for the 
    postgresql 8.3 enum type. **/

SET CONSTRAINTS ALL DEFERRED;

CREATE TABLE visualization (
  id SERIAL PRIMARY KEY, 
  name TEXT NOT NULL
);

/** Populate initial visualizations. **/

/* SYNC_ME: Search: viz table. */                                 -- ID
INSERT INTO visualization (name) VALUES ('Plain'),                -- 1
                                        ('Rating'),               -- 2
                                        ('Slope'),                -- 3
                                        ('Byway Type'),           -- 4
                                        ('Bonus/Penalty Tagged'); -- 5

/** Add route_visualization preference to user_ table. **/

ALTER TABLE user_ 
ADD route_visualization INT
                        NOT NULL 
                        DEFAULT ceil(5*random())
                        REFERENCES visualization(id) DEFERRABLE;

ALTER TABLE user_preference_event ADD route_visualization INT;

/** Assign visualizations based on the most recent route requests. The user
    with the most recent request is assigned viz 1, the user with the second
    most recent request is assigned viz 2, the user with the nth most recent
    request is assigned viz ceil(n % viz_count). Users with no route requests
    are just assigned a random visualization.

    FIXME: The above left in to document what the "right" way to do it is, but
    this runs afoul of the following problem: we currently have no way to
    "push" updated preferences to the client, so we can't share the updated
    with anything remotely approaching reliability. :( **/

COMMIT;

\d node_attribute
\d visualization
\d user_
