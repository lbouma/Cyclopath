/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Add geofeature column for connectedness, so route finder only
\qecho choose origins and destinations on the well-connected network.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Add geofeature column for connectedness, so route finder only
\qecho choose origins and destinations on the well-connected network.
\qecho

ALTER TABLE @@@instance@@@.geofeature
   ADD COLUMN is_disconnected BOOLEAN;

UPDATE @@@instance@@@.geofeature
   SET is_disconnected = FALSE;

ALTER TABLE @@@instance@@@.geofeature
   ALTER COLUMN is_disconnected SET NOT NULL;

CREATE INDEX geofeature_disconnected
   ON @@@instance@@@.geofeature (is_disconnected);

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Update route table with new p3 planner columns.
\qecho

/* p3_weight_type: 'len', 'rat', 'fac', 'rac', 'prat', 'pfac', 'prac' */
ALTER TABLE @@@instance@@@.route
   ADD COLUMN p3_weight_type TEXT;

/* p3_burden_pump: E.g., 10, 20, 40, 65, 90
                   See: Trans_Graph.burden_vals */
ALTER TABLE @@@instance@@@.route
   ADD COLUMN p3_burden_pump INTEGER;

/* p3_spalgorithm: 'as*', 'asp', 'dij', 'sho' */
ALTER TABLE @@@instance@@@.route
   ADD COLUMN p3_spalgorithm TEXT;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

