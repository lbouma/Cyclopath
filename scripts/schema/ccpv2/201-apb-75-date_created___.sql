/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script populates date_created and created_by column values. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script populates date_created and created_by column values.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho 
\qecho 
\qecho 

/* BUG nnnn: Populate item_versioned created_by and date_created for historic
             tracks and routes. We don't populate those fields except for
             revisionless saves. Populate group_item_access.date_created, too.
             (We don't populate just to save space -- I'm guessing keeping
              millions of timestamps out of the item tables is probably
              a good idea. And if not, we can always populate these columns
              later.)

   item_versioned.date_created
   item_versioned.created_by
   group_item_access.date_created
   group_item_access.created_by

*/

/* Cleanup. */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

\qecho Committing...

COMMIT;

