/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;

/* This script guesses speed limits.

   Method based on advice from Nathan Drews <Nathan.Drews@dot.state.mn.us>.

   The procedure below, combined with explicitly known limits, covers about
   98% of roads in the metro. Of the remaining 2%, almost all are on/off ramps
   (and presumably unrideable); less than 0.2% of the roads in the metro will
   be missed entirely.

   This script takes a while to run: on the order of 10 minutes on magnify. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE FUNCTION
  guess_speed_limit(type_code VARCHAR(2), geometry GEOMETRY) RETURNS INT
  LANGUAGE plpgsql STABLE AS $$
DECLARE
  incity BOOLEAN;
BEGIN
  /* Municipal streets: always guess 30 MPH. */
  IF (type_code IN ('05', '10')) THEN
    RETURN 30;
  /* County and township roads: depends on whether "inside city boundaries".
     As municipal boundaries have only a loose relationship with the actual
     built-up area, we use the following heuristic: we consider a geometry to
     be inside city boundaries if it intersects a mndot_basemap_muni row with
     a population density greater than 100 people/km^2 OR it intersects a row
     from urban_area (Census urbanized areas). */
  ELSEIF (type_code IN ('04', '07', '08', '09')) THEN
    -- try mndot_basemap_muni first
    PERFORM gid FROM mndot_basemap_muni muni
      WHERE (muni.geometry && geometry AND Intersects(muni.geometry, geometry)
             AND population / (area / 1e6) >= 100)
      LIMIT 1;
    incity := FOUND;
    -- fall back to urban_area
    IF (NOT incity) THEN
      PERFORM gid FROM urban_area ua
        WHERE ua.geometry && geometry AND Intersects(ua.geometry, geometry)
        LIMIT 1;
      incity := FOUND;
    END IF;
    -- guess 40 MPH if in city, 55MPH otherwise
    IF (incity) THEN
      RETURN 40;
    ELSE
      RETURN 55;
    END IF;
  /* Everything else: unknown. (About 7%.) */
  ELSE
    RETURN NULL;
  END IF;
END;
$$;

UPDATE mndot_basemap
  SET speed_limit_guessed = guess_speed_limit(code, geometry);

DROP FUNCTION guess_speed_limit(type_code VARCHAR(2), geometry GEOMETRY);

--COMMIT;
\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;

