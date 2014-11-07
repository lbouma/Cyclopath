/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho Fix problem: Cannot call fcn./subquery from table constraint.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

/*

Our geofeature Check constraint is invalid.

ccpv3_lite=> SELECT * FROM geometry_columns WHERE f_table_name = 'geofeature';
ERROR:  invalid input syntax for integer: "cp_srid"
CONTEXT:  SQL function "postgis_constraint_srid" statement 1

From the mouth:

 http://www.postgresql.org/docs/9.1/interactive/sql-createtable.html

 "Currently, CHECK expressions cannot contain subqueries nor refer to
  variables other than columns of the current row."

So... oops. Or, one could ask why we haven't had/seen a problem
until now. Maybe most uses of the contraint just ignore the bad
subquery?

This is wrong:

  ALTER TABLE geofeature
     ADD CONSTRAINT enforce_srid_geometry
     CHECK (srid(geometry) = cp_srid());

We need to hard-code the SRID if we want to use this constraint.

*/

ALTER TABLE geofeature DROP CONSTRAINT enforce_srid_geometry;

CREATE OR REPLACE FUNCTION re_enforce_srid_geometry()
   RETURNS VOID AS $$
   DECLARE
      instance_srid INTEGER;
   BEGIN
      instance_srid := cp_srid();
      EXECUTE '
        ALTER TABLE geofeature
           ADD CONSTRAINT enforce_srid_geometry
           CHECK (srid(geometry) = ' || instance_srid || '
         );
      ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT re_enforce_srid_geometry();

DROP FUNCTION re_enforce_srid_geometry();

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

