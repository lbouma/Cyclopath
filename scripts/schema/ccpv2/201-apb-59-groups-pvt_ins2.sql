/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script indexes columns so that the next few scripts run efficiently. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script indexes columns so that the next few scripts run efficiently
\qecho 
\qecho [EXEC. TIME: 2011.04.25/Huffy: ~ 0.16 mins (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.12 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ========================================================================= */
/* Step (1) -- Index columns                                                 */
/* ========================================================================= */

\qecho 
\qecho Indexing columns
\qecho 

CREATE INDEX group_revision_revision_id ON group_revision (revision_id);

CREATE INDEX group_revision_is_revertable ON group_revision (is_revertable);

CREATE INDEX route_permission ON route (permission);
CREATE INDEX route_owner_name ON route (owner_name);

CREATE INDEX track_permission ON track (permission);
CREATE INDEX track_owner_name ON track (owner_name);

/* Already exists:
CREATE INDEX user__login_permitted ON user_ (login_permitted);
*/

CREATE INDEX group__stack_id
   ON group_ (stack_id);
CREATE INDEX group__deleted
   ON group_ (deleted);
CREATE INDEX group__valid_start_rid 
   ON group_ (valid_start_rid);
CREATE INDEX group__valid_until_rid 
   ON group_ (valid_until_rid);
CREATE INDEX group_item_access_deleted 
   ON group_item_access (deleted);
CREATE INDEX group_item_access_valid_start_rid 
   ON group_item_access (valid_start_rid);
CREATE INDEX group_item_access_valid_until_rid 
   ON group_item_access (valid_until_rid);
CREATE INDEX group_item_access_group_id 
   ON group_item_access (group_id);
CREATE INDEX group_item_access_acl_grouping 
   ON group_item_access (acl_grouping);
CREATE INDEX group_item_access_access_level_id 
   ON group_item_access (access_level_id);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

