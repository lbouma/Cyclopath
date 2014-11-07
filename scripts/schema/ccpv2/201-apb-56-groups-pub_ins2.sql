/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script drops constraints and indexes columns so that the next few
   scripts run efficiently. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script drops constraints and indexes columns so that the next
\qecho few scripts run efficiently.
\qecho 
\qecho [EXEC. TIME: 2011.04.25/Huffy: ~ 0.36 mins (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.14 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop constraints and index columns                       */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION item_table_create_indices(IN table_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'CREATE INDEX ' || table_name || '_stack_id
                  ON ' || table_name || '(stack_id);';
      EXECUTE 'CREATE INDEX ' || table_name || '_version
                  ON ' || table_name || '(version);';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating indices on the item tables
\qecho 

CREATE INDEX item_versioned_deleted 
   ON item_versioned (deleted);
CREATE INDEX item_versioned_valid_start_rid 
   ON item_versioned (valid_start_rid);
CREATE INDEX item_versioned_valid_until_rid 
   ON item_versioned (valid_until_rid);

/* Base table */
\qecho ...item_versioned
SELECT item_table_create_indices('item_versioned');

/* Intermediate tables */
\qecho ...attachment
SELECT item_table_create_indices('attachment');
\qecho ...geofeature
SELECT item_table_create_indices('geofeature');
\qecho ...link_value
SELECT item_table_create_indices('link_value');

/* Attachment tables */
\qecho ...tag
SELECT item_table_create_indices('tag');
\qecho ...annotation
SELECT item_table_create_indices('annotation');
\qecho ...thread
SELECT item_table_create_indices('thread');
\qecho ...post
SELECT item_table_create_indices('post');
\qecho ...attribute
SELECT item_table_create_indices('attribute');
/* Geofeature tables */
\qecho ...route
SELECT item_table_create_indices('route');
\qecho ...track
SELECT item_table_create_indices('track');

\qecho 
\qecho Removing helper fcn.
\qecho 

DROP FUNCTION item_table_create_indices(IN table_name TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

