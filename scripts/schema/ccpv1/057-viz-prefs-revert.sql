/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;

ALTER TABLE user_ DROP route_visualization;
ALTER TABLE user_preference_event DROP route_visualization;
DROP TABLE visualization;
DROP TABLE node_attribute;

COMMIT;

\d user_preference_event
\d user_
