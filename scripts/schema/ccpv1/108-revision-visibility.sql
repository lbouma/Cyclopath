/* Add a visibility column to the revision table. This visibility mirrors
   the functionality of visibility within the route table.
   See 089-route-visibility-enum.sql for details.

   @once-per-instance */

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;

-- Update revision table to have visibility, initially all rows are fully
-- visible, because they are all public revisions
ALTER TABLE revision ADD visibility INT DEFAULT 1 NOT NULL
   REFERENCES visibility(code);

-- Update revision and route tables to have valid viz/perm constraints
ALTER TABLE revision ADD CONSTRAINT revision_enforce_visibility
        CHECK ((permission = 1 AND visibility = 1) OR (permission = 2) 
               OR (permission = 3 AND visibility != 1));

ALTER TABLE route ADD CONSTRAINT route_enforce_visibility
        CHECK ((permission = 1 AND visibility = 1) OR (permission = 2)
               OR (permission = 3 AND visibility != 1));

COMMIT;

