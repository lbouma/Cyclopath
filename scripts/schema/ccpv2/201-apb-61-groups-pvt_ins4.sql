/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates a private group for each user and populates group-item
   with users' private items. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates a private group for each user and populates 
\qecho group-item with users'' private items
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop permission column from revision table               */
/* ==================================================================== */

\qecho 
\qecho Dropping permission column on revision table
\qecho 

/* Permission is always 1 in the old table. In the new schema, we handle
   permissions with the group_revision table. So drop the column. */

/* FIXME Instead of dropping columns, should I be archiving the table and 
         making it anew instead?

FIXME: 2013.04.24: Hold onto these until you know that
                   CcpV2 stuff is configured properly.
                   See also item_stack.access_style_id
                   and route's and track's permissions
                   and visibility columns (which we're
                   also preserving for the time being).

ALTER TABLE revision DROP COLUMN permission;

ALTER TABLE revision DROP COLUMN visibility;

*/

/* FIXME: route manip. Eventually drop other route columns, too: 
                         owner_name -- see gia records
                         host -- just an IP addy... used for stats?
                                 or along with session_id? 
                                 FIXME: Why is host sometimes NULL?
                         session_id -- won't matter after apache restart...
                         link_hash_id -- item_stack.stealth_secret
                         cloned_from_id -- FIXME: see ???
                         created -- see group_item_access
                         type_code... it's now geofeature.gfl_id

                         but not these:
                         source -- maybe not: this is an internal value, 
                              prod_mirror=> select distinct(source) from route;
                                 source    
                              -------------
                               android_top
                               
                               search
                               put_feature
                               deep
                               deeplink
                               top
                               routes
                               history
                              (9 rows)

SELECT id,version,owner_name,host,source,session_id,cloned_from_id 
from route where version > 1 
order by id DESC,version;

*/

/* ==================================================================== */
/* Step (2) -- Watch Regions -- Convert to simple regions || PART 1/2   */
/* ==================================================================== */

/* NOTE See the next script for PART 2/2. */

\qecho 
\qecho Updating geofeature: making old watch regions just regions
\qecho 

UPDATE geofeature 
   SET geofeature_layer_id 
      = (SELECT id FROM geofeature_layer 
         WHERE feat_type = 'region'
               AND layer_name = 'default')
   WHERE geofeature_layer_id 
      = (SELECT id FROM geofeature_layer 
         WHERE feat_type = 'region_watched');

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

