/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script configures the system_id column in the route_feedback, 
   route_step, and track_point tables. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds system_id & branch_id and renames id to stack_id
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 10    mins. mn. / 0 mins. co.]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 8    hours. mn. / 0 mins. co.]
\qecho [EXEC. TIME: 2013.04.23/runic:  24.66 min. [mn]]
\qecho 

/* PERFORMANCE NOTE: Before deferring index and constraint creation, this
 *                   script took ~ 15 mins. to run. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho 
\qecho Populating ID columns in versioned support tables
\qecho 

\qecho ...route_step (byway)
\qecho ... [this one is slow]
--\qecho ... [5,907,996 rows (2011.04.26)]
--\qecho ... [doesn''t seem like that many...]
\qecho ... [2012.09.24: huffy: mn: 2h52 (--novacu)]
\qecho ... [2012.09.25: huffy: mn: 2h40]
\qecho ... [2013.05.12: runic: mn: 0h27]
/* PERFORMANCE: Search: Slow V1->V2 ops. */
SELECT item_table_update_versioned('route_step', 'byway');

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

\qecho Committing... [2012.09.22: huffy: mn: 2m]

COMMIT;

