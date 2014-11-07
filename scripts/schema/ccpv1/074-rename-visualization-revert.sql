/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;

/** Using 'visualization' is too verbose. Renaming tables to use the 
  * more concise name 'viz'
  */

SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE user_ RENAME COLUMN route_viz TO route_visualization;
ALTER TABLE user_preference_event RENAME COLUMN route_viz TO route_visualization;
ALTER TABLE viz RENAME TO visualization;

COMMIT;
