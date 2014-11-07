/* Update the permissions check on the revision table to allow revisions for
   anonymous users if they have visibility = no-one (e.g. sharing a route deep
   link). Also adda cloned_from_id column to a route so that permission changes
   can be tracked across the different ids used by the same 'route'. 

   @once-per-instance
*/

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;

ALTER TABLE revision DROP CONSTRAINT enforce_permissions;
ALTER TABLE revision ADD CONSTRAINT revision_enforce_permissions
        CHECK (visibility = 3 OR username IS NOT NULL OR permission = 1);

ALTER TABLE route ADD COLUMN cloned_from_id INT;

COMMIT;
