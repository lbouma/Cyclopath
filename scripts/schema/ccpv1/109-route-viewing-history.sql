/*
 * Updates the database to include a route_views table that records route
 * views by users to present in the 'Routes I've Looked At' panel in the client
 *
 * @once-per-instance
 */

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;

/* C.f. set_last_modified() and set_created(). */
CREATE OR REPLACE FUNCTION public.set_last_viewed() 
   RETURNS TRIGGER AS $set_last_viewed$
     BEGIN 
         NEW.last_viewed = now();
         RETURN NEW;
     END
   $set_last_viewed$ LANGUAGE 'plpgsql';

CREATE TABLE route_views (
   route_id INT,
   username TEXT REFERENCES user_ (username),
   active BOOL NOT NULL DEFAULT TRUE, 
   last_viewed TIMESTAMP NOT NULL,

   PRIMARY KEY (route_id, username)
);

CREATE TRIGGER last_viewed_i BEFORE INSERT ON route_views
   FOR EACH ROW EXECUTE PROCEDURE set_last_viewed();

/* 
 * We don't create a trigger on select to set last_viewed because the client
 * will sometimes reload a route for purposes unrelated to the user viewing
 * a route.
 */

COMMIT;
