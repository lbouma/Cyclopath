/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

   @once-per-instance

*/

\qecho 
\qecho Circa Fall 2012: This script adds route reaction and route sharing.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* This script uses a lookup of values created in an earlier, CcpV1->V2 script.
   See: SYNC_ME: Search: thread_type_id.

      SELECT cp_enum_definition_new('thread_type', 0, 'default');
      SELECT cp_enum_definition_new('thread_type', 1, 'general');
      SELECT cp_enum_definition_new('thread_type', 2, 'reaction');
*/

/* NOTE: Inline SELECT is slow, but the thread and post tables are small. */

/* The enum value matches the old ttype name, so it's simple to update the
   table. */

UPDATE thread SET thread_type_id = (
      SELECT cp_enum_definition_get_key('thread_type',
                                        thread.ttype));



/* BUG nnnn: Delete all route.session_id and implement server-managed session
             IDs (and delete GIA records when they expire? or mark deleted?)
*/


/* All done! */

COMMIT;

