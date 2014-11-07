
/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Shared functions (in public schema) to support
   087-gis_views.sql (Views for use in db_export_shapefiles.sh) */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* 2012.07.31: FIXME: group_concat is slow!
   E.g.,
         SELECT
           DISTINCT(name)
           , GROUP_CONCAT(stack_id::TEXT) AS sids
         FROM 
           item_versioned
         GROUP BY
           name
         ORDER BY
           name;
   takes days with the group_concat... and mere seconds without.

   Fortunately, I don't think this fcn. is currently used, but I [lb] have 
   tinkered around with aggregates, so it's good to know they're slow. 

2012.07.31: After a dozen or two hours, query returned no results, so 
            something is definitely wrong... need to test using a smaller
            test sample than the entire item_versioned table!
*/ 

/* Emulate MySQL's GROUP_CONCAT()
   http://mssql-to-postgresql.blogspot.com/2007/12/cool-groupconcat.html */

CREATE FUNCTION _group_concat(text, text) RETURNS text AS $$
  SELECT CASE
    WHEN $2 IS NULL THEN $1
    WHEN $1 IS NULL THEN $2
    ELSE $1 || ',' || $2
  END
$$ IMMUTABLE LANGUAGE SQL;

CREATE AGGREGATE group_concat (
  BASETYPE = text,
  SFUNC = _group_concat,
  STYPE = text
);

COMMIT;

