/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

   @once-per-instance

*/

\qecho 
\qecho This script adds the 'cp_maintenance' key_value_pair.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Bug nnnn - System Messages... and maintenance mode.
 *
 * The valid maintainence mode values are: off, on, or a date:
 * - Off means database is open and may be read and written.
 * - On means the database is in read-only mode.
 * - A date means the site will be going read-only (or offline) 
 *    at the date specified. */
-- FIXME: Should this be a key_value_pair or do we need a system messages
-- infrastructure?

INSERT INTO @@@instance@@@.key_value_pair
   (key, value) VALUES ('cp_maintenance', 'off');

COMMIT;

