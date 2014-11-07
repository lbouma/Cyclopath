/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script constrains columns we populated in previous scripts. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script constrains columns we populated in previous scripts.
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.24 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.11 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ======================================================================== */
/* Step (1) -- Set branch_id cols: NOT NULL                                 */
/* ======================================================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION table_column_branch_id_set_not_null(IN table_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  ALTER COLUMN branch_id SET NOT NULL;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Adding not null to tables'' columns
\qecho 

/* Start w/ the base table */
\qecho ...item_versioned
SELECT table_column_branch_id_set_not_null('item_versioned');
/* Do the intermediate tables */
\qecho ...attachment
SELECT table_column_branch_id_set_not_null('attachment');
\qecho ...geofeature
SELECT table_column_branch_id_set_not_null('geofeature');
\qecho ...link_value
SELECT table_column_branch_id_set_not_null('link_value');
/* Do the attachment tables */
\qecho ...tag
SELECT table_column_branch_id_set_not_null('tag');
\qecho ...annotation
SELECT table_column_branch_id_set_not_null('annotation');
\qecho ...thread
SELECT table_column_branch_id_set_not_null('thread');
\qecho ...post
SELECT table_column_branch_id_set_not_null('post');
\qecho ...attribute
SELECT table_column_branch_id_set_not_null('attribute');
/* Do the geofeature tables */
\qecho ...route
SELECT table_column_branch_id_set_not_null('route');
\qecho ...track
SELECT table_column_branch_id_set_not_null('track');
/* Do the attachment and geofeature support tables */
\qecho ...aadt
SELECT table_column_branch_id_set_not_null('aadt');
\qecho ...byway_rating (~5 secs)
SELECT table_column_branch_id_set_not_null('byway_rating');
\qecho ...byway_rating_event
SELECT table_column_branch_id_set_not_null('byway_rating_event');
\qecho ...reaction_reminder
SELECT table_column_branch_id_set_not_null('reaction_reminder');
/* 2012.10.04: Route Feedback Drag. */
\qecho ...route_feedback_stretch
SELECT table_column_branch_id_set_not_null('route_feedback_stretch');
\qecho ...route_priority
SELECT table_column_branch_id_set_not_null('route_priority');
\qecho ...route_tag_preference
SELECT table_column_branch_id_set_not_null('route_tag_preference');
\qecho ...route_view
SELECT table_column_branch_id_set_not_null('route_view');
\qecho ...tag_preference
SELECT table_column_branch_id_set_not_null('tag_preference');
\qecho ...tag_preference_event
SELECT table_column_branch_id_set_not_null('tag_preference_event');

/* Also do the revision table */
\qecho ...revision
SELECT table_column_branch_id_set_not_null('revision');

\qecho 
\qecho Removing helper fcn.
\qecho 

DROP FUNCTION table_column_branch_id_set_not_null(
   IN table_name TEXT);

/* ======================================================================== */
/* Step (2) -- Recreate Primary Keys for misc. tables                       */
/* ======================================================================== */

\qecho 
\qecho Recreating primary keys on versionless support tables
\qecho 

/* FIXME: Should branch_id be part of the primary keys? */

ALTER TABLE aadt
   ADD CONSTRAINT aadt_pkey
   PRIMARY KEY (branch_id, byway_stack_id);

ALTER TABLE byway_rating
   ADD CONSTRAINT byway_rating_pkey
   PRIMARY KEY (username, branch_id, byway_stack_id);

ALTER TABLE route_priority
   ADD CONSTRAINT route_priority_pkey
   PRIMARY KEY (branch_id, route_stack_id, priority);

ALTER TABLE route_tag_preference
   ADD CONSTRAINT route_tag_preference_pkey
   PRIMARY KEY (branch_id, route_stack_id, tag_stack_id);

ALTER TABLE tag_preference
   ADD CONSTRAINT tag_preference_pkey
   PRIMARY KEY (username, branch_id, tag_stack_id);

/* ======================================================================== */
/* Step (n) -- All done!                                                    */
/* ======================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

