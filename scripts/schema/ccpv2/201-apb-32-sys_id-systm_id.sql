/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script populates the system_id in the item tables. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script populates the system_id in the item tables.
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.60 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.35 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (5) -- Add System and Branch IDs: Create helper function        */
/* ==================================================================== */

\qecho 
\qecho Creating temporary helper fcn. to alter dependent tables
\qecho 

CREATE FUNCTION item_table_correct_system_id(IN table_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'UPDATE ' || table_name || ' AS child 
                  SET system_id = 
                     (SELECT system_id 
                        FROM item_versioned AS parent 
                        WHERE parent.stack_id = child.stack_id 
                              AND parent.version = child.version);';
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  ALTER COLUMN system_id SET NOT NULL;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (6) -- Add System and Branch IDs: Attachment tables             */
/* ==================================================================== */

\qecho 
\qecho Populating ID columns in Attachment tables
\qecho 

\qecho ...tag
SELECT item_table_correct_system_id('tag');
\qecho ...annotation
SELECT item_table_correct_system_id('annotation');
\qecho ...thread
SELECT item_table_correct_system_id('thread');
\qecho ...post
SELECT item_table_correct_system_id('post');
\qecho ...attribute
SELECT item_table_correct_system_id('attribute');
-- Save the base table for last, so we don't have to fudge and use CASCADE
\qecho ...attachment
SELECT item_table_correct_system_id('attachment');

/* DFER Function will be dropped after geofeature uses it. */

/* ==================================================================== */
/* Step (7) -- Add System and Branch IDs: Geofeature tables             */
/* ==================================================================== */

\qecho 
\qecho Adding System ID to Geofeature tables
\qecho 

-- Do the child tables first
\qecho ...route
SELECT item_table_correct_system_id('route');
\qecho ...track
SELECT item_table_correct_system_id('track');
-- Do the intermediate table second
\qecho ...geofeature
SELECT item_table_correct_system_id('geofeature');

/* ==================================================================== */
/* Step (8) -- Add System and Branch IDs: Link_Value table              */
/* ==================================================================== */

\qecho 
\qecho Adding System ID to Link_Value table
\qecho 

SELECT item_table_correct_system_id('link_value');

/* ==================================================================== */
/* Step (9) -- Add System and Branch IDs: Cleanup                       */
/* ==================================================================== */

DROP FUNCTION item_table_correct_system_id(IN table_name TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

