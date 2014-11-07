/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

   @once-per-instance

*/

\qecho 
\qecho This script removes duplicates from and constrains coverage_area.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

CREATE TABLE coverage_area_tmp AS SELECT DISTINCT * FROM coverage_area;
DROP TABLE coverage_area;
ALTER TABLE coverage_area_tmp RENAME TO coverage_area;

/* Make sure this doesn't happen again. */
ALTER TABLE coverage_area 
   ADD CONSTRAINT coverage_area_pkey 
   PRIMARY KEY (name);

/* Actually, screw it, get rid of the table. We can do better -- this is now a
 * branch attribute. See Bug nnnn. */

DROP TABLE coverage_area;

/* All done! */

COMMIT;

