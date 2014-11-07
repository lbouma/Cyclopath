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
\qecho [EXEC. TIME: 2013.04.23/runic:  26.92 min. [mn]]
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

\qecho ...route_step (route)
\qecho ... [this one is slower]
\qecho ... [2012.03.10: huffy: hours... or maybe i need to not novacu]
\qecho ... [2012.03.10: huffy: script total: 350.76 mins. (no prior vacuum)]
\qecho ... [2012.09.22: huffy: mn: 3h51]
\qecho ... [2012.09.24: huffy: mn: 4h11 (--novacu)]
\qecho ... [2013.05.12: runic: mn: 0h28]
/* PERFORMANCE: Search: Slow V1->V2 ops. */
SELECT item_table_update_versioned('route_step', 'route');

/* ================================== */
/* Support tables: Cleanup            */
/* ================================== */

DROP FUNCTION item_table_update_versioned(
   IN table_name TEXT, IN idvers_prefix TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

\qecho Committing... [2012.09.22: huffy: mn: 2m]

COMMIT;

