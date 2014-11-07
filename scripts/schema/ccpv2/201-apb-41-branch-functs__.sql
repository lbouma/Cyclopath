/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates a public function to retrieve an instances' public 
   basemap ID. */

\qecho 
\qecho This script creates a public function to retrieve an instances'' public 
\qecho basemap ID
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Make Entry in Geofeature Layer table                     */
/* ==================================================================== */

\qecho 
\qecho Branch: Add to geofeature_layer
\qecho 

/* NOTE: The branch isn't really drawn, so just setting draw class arbitrarily 
 *       to be 'background'; the value shouldn't matter. */

INSERT INTO geofeature_layer (
   feat_type, 
   layer_name, 
   geometry_type, 
   draw_class_id,
   restrict_usage
   )
   VALUES (
      'branch', 
      'default', 
      'POLYGON', 
      (SELECT id FROM draw_class WHERE text='background'),
      TRUE);

\qecho 
\qecho Branch: Creating geofeature_layer view
\qecho 

CREATE VIEW gfl_branch AS 
   SELECT * 
      FROM geofeature_layer AS gfl
      WHERE gfl.feat_type = 'branch';

/* ==================================================================== */
/* Step (2) -- Create aggregate utility functions                       */
/* ==================================================================== */

\qecho 
\qecho Creating utility functions, First and Last.
\qecho 

/* These two aggregate functions are courtesy the Postgres Wiki.
 *
 *   http://wiki.postgresql.org/wiki/First_%28aggregate%29
 *   http://wiki.postgresql.org/wiki/Last_%28aggregate%29
 *
 * NOTE: These fcns. are used by more than just branches, but this SQL script 
 *       is as good as any for declaring these functions.
 *
 */

-- Create a function that always returns the first non-NULL item
CREATE OR REPLACE FUNCTION public.first_agg ( anyelement, anyelement )
RETURNS anyelement AS $$
        SELECT CASE WHEN $1 IS NULL THEN $2 ELSE $1 END;
$$ LANGUAGE SQL STABLE;

/* And then wrap an aggregate around it. */
CREATE AGGREGATE public.first (
        sfunc    = public.first_agg,
        basetype = anyelement,
        stype    = anyelement
);

-- Create a function that always returns the last non-NULL item
CREATE OR REPLACE FUNCTION public.last_agg ( anyelement, anyelement )
RETURNS anyelement AS $$
        SELECT $2;
$$ LANGUAGE SQL STABLE;

-- And then wrap an aggreagate around it
CREATE AGGREGATE public.last (
        sfunc    = public.last_agg,
        basetype = anyelement,
        stype    = anyelement
);

/* ==================================================================== */
/* Step (3) --                                                          */
/* ==================================================================== */

\qecho 
\qecho Creating utility function, cp_set_created_rid
\qecho 

-- FIXME: Rename revision_id to created_rid ?
CREATE OR REPLACE FUNCTION public.cp_set_created_rid()
   RETURNS TRIGGER AS $cp_set_created_rid$
      BEGIN 
         NEW.revision_id := MAX(id) FROM revision WHERE id < cp_rid_inf();
         RETURN NEW;
      END
   $cp_set_created_rid$ LANGUAGE 'plpgsql';

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

