/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho Replace cp_maintenace key w/ cp_maint_beg and cp_maint_fin.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

/*
FIXME/BUG nnnn: Is there a way to make a rolling script instead, rather
than always making new scripts? Like define new, numbered fcns. and store
the last fcn. # called.
*/

\qecho 
\qecho Replace cp_maintenace key w/ cp_maint_beg and cp_maint_fin.
\qecho 

DELETE FROM key_value_pair WHERE key = 'cp_maintenance';

INSERT INTO @@@instance@@@.key_value_pair
   (key, value) VALUES ('cp_maint_beg', '');
INSERT INTO @@@instance@@@.key_value_pair
   (key, value) VALUES ('cp_maint_fin', '');

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

