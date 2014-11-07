/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN;

/* Load temp. VIEWs. */
\i ../../daily/usage/ccp_common.sql

\qecho "Total number of user ratings"

SELECT count(*) FROM user_rating;

\qecho "Number of byway ratings by byway type"

SELECT
   count(*),
   gfl.layer_name
FROM
   user_rating AS ur
   JOIN byway AS gf
      ON (ur.byway_stack_id = gf.stack_id)
   JOIN gfl_byway AS gfl ON (gf.geofeature_layer_id = gfl.id)
GROUP BY gfl.layer_name
ORDER BY gfl.layer_name;

\qecho "Top raters"

SELECT
   username,
   count(*)
FROM
   user_rating
GROUP BY
   username
ORDER BY
   count DESC
LIMIT 20;

ROLLBACK;

