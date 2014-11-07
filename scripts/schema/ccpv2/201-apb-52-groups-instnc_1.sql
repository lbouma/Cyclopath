/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds the new access control tables to the schema. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds the new access control tables to the schema.
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.73 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   1.21 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Silence                                                  */
/* ==================================================================== */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

/* ==================================================================== */
/* Step (2) -- Make a bunch o' tables                                   */
/* ==================================================================== */

\qecho 
\qecho Creating access control tables
\qecho 

/* 
 * group_ */

/* NOTE I considered making group_ and group_membership public tables. 
        However, group_membership is revisioned, and revision is an 
        instance table, so group_membership cannot be public. As for
        the group_ table, I could either way (I don't really think it 
        matters too much if it's a public or an instance table); however, 
        I don't imagine users will want to use groups cross-instance, so 
        rather than letting groups from one instance bleed to another 
        instance, we make the group_ table an instance table, too. */

/* NOTE Like 'user', we cannot use the name 'group', which is a Psql reserved 
        word. So we use 'group_' instead. */
/* FIXME Should name be unique()? */
/* FIXME? rename name to groupname and make unique */
/* FIXME New: deleted_date -- if you want to reclaim group name, cannot make
 *       groupname unique (but can always grab lock, query SQL, ...) */
CREATE TABLE group_ (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   -- FIXME See note in new_item_policy, not sure I should duplicate these
   --       columns, which are already in item_versioned
   deleted BOOLEAN NOT NULL DEFAULT FALSE,
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   name TEXT,
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   -- ** Group Access Control columns
   --group_id SERIAL,
   --group_id INTEGER NOT NULL,
   --group_name TEXT,
   description TEXT,
   access_scope_id INTEGER DEFAULT 0
   --deleted_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
);

--PRIMARY KEY (group_id)
ALTER TABLE group_ 
   ADD CONSTRAINT group__pkey 
   PRIMARY KEY (system_id);

/* 
 * group_membership */

CREATE TABLE group_membership (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   -- FIXME See note in new_item_policy, not sure I should duplicate these
   --       columns, which are already in item_versioned
   deleted BOOLEAN NOT NULL DEFAULT FALSE,
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   name TEXT, -- Not used
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   -- ** Group Access Control columns
   group_id INTEGER NOT NULL,
   -- ** Group Membership columns
   -- FIXME username or user_id??
   user_id INTEGER NOT NULL,
   username TEXT NOT NULL,
   access_level_id INTEGER NOT NULL,
   opt_out BOOLEAN DEFAULT FALSE
);

-- PRIMARY KEY (username, group_id, valid_start_rid, valid_until_rid),
ALTER TABLE group_membership 
   ADD CONSTRAINT group_membership_pkey 
   PRIMARY KEY (system_id);

/* 
 * new_item_policy */

DROP TABLE IF EXISTS new_item_policy;

CREATE TABLE new_item_policy (

   -- ** Item Versioned columns
   system_id INTEGER NOT NULL
   , branch_id INTEGER NOT NULL
   , stack_id INTEGER NOT NULL
   , version INTEGER NOT NULL

   /* NOTE: Unlike Map Item classes, which join w/ Item_Versioned to get
    *       the following columns, we include 'em here. Not sure why, but
    *       the GrAC classes are just a little different. */
   /* BUG nnnn: Would it make sense to do this for node_endpoint? I.e., 
                Does it matter (for speed) the size of item_versioned? */
   , deleted BOOLEAN NOT NULL DEFAULT FALSE
   , reverted BOOLEAN NOT NULL DEFAULT FALSE
   , name TEXT NOT NULL -- A description of the policy
   , valid_start_rid INTEGER NOT NULL
   , valid_until_rid INTEGER NOT NULL

   -- ** Group Access Control columns
   /* This is the group to which this policy applies. */
   , group_id INTEGER NOT NULL

   -- ** New Item Policy columns

   , target_item_type_id INTEGER NOT NULL
   /* MAYBE: target_item_layer isn't used. */
   , target_item_layer TEXT DEFAULT NULL

   , link_left_type_id INTEGER DEFAULT NULL
   , link_left_stack_id INTEGER DEFAULT NULL
   /* min_acl always null for lhs and rhs, 
    * or it's 3 and 4 for lhs and 5 for rhs
      (user must be attachment viewer or editor 
       but merely geofeature client). */
   , link_left_min_access_id INTEGER DEFAULT NULL

   , link_right_type_id INTEGER DEFAULT NULL
   , link_right_stack_id INTEGER DEFAULT NULL
   , link_right_min_access_id INTEGER DEFAULT NULL

   /* FIXME: 2012.10.09: Maybe remove these: processing_order and stop_on_match
    *                    are not used. */
   , processing_order INTEGER NOT NULL DEFAULT 0
   , stop_on_match BOOLEAN NOT NULL DEFAULT FALSE

   /* The NIP Style dictates how new items are setup.
    *
    * Many item types have just one GIA record. This NIP style is called 
    * "singular", meaning the item can be a private item (the user's private
    * group has editor access to the item) or the item can be a public item
    * (the public user group has editor access to the item). E.g., waypoints,
    * regions, and annotations are "singular"-style.
    *
    * Some item types have one or more GIA records, and one or more users can
    * create and update the item's GIA records. This style is called 
    * "multiple", meaning the user who creates the item is assigned owner
    * access to it and they can add or change other user groups' access to the
    * item. E.g., routes and branches are "multiple"-style.
    *
    * Some item types may not have their permissions edited, and are either
    * always publically-editable ("publics"-style) or always privately-editable
    * ("authors"-style). E.g., byways are always publically-editable and
    * ratings (link_values between byways are the rating attribute) are always
    * privately-editable. Most link_values are publically-editable (but are
    * still further restricted depending on access to the lhs and rhs items).
    *
    * For item types that cannot be created, there's a fifth style, "disabled".
    * Normally, if an item doesn't have an entry in the NIP table, it defaults
    * to not being createable, so you'd think we don't really need this style,
    * but we can use the style to restrict access to existing items. E.g., if
    * you want the public to be able to view items in your branch but not edit
    * them, setup the NIP for the public so that access_style is "disabled" for
    * each item type, and then setup the NIP for your shared group with the 
    * appropriate access_style for each item. (We could instead use GIA records
    * to control access, i.e., give the shared group an editor record and the
    * public record a viewer record for every item, but this seems incredibly
    * tedious, and then it's difficult to merge to the public branch because
    * you'll have to correct all of the GIAs.)
    *
    * The access_style is one of 

FIXME: What about routes? If being made public, delete orig and cloned anew?
Or is this usr_choice? Starts private, then has one-way street to public.

    *
    *  "permissive" -- user is assigned ownership and can manage groups access
    *  "pub_choice" -- user says if item is private (user is editor) or public
    *  "usr_choice" -- same as ^^, but defaults to usr_editor, not pub_editor
    *  "usr_editor" -- user is always editor (item is private)
    *  "pub_editor" -- public is always editor (item is public)
    *  "all_denied" -- nobody can do nothing (items cannot be created/edited)
    *
    */
   , access_style_id INTEGER DEFAULT NULL

   /* This is a hacky override for work items, to give the branch manager
    * group editor access to other users' jobs. If null, the access level is 
    * computed from group_item_access records. If this is set, the computed 
    * access level will be upgraded to super_acl if it's not already better.
    *
    * BUG nnnn: FIXME: Implement this. On checkout of work_items, check this 
    * value and send all work items if set to editor. On commit, check this
    * again to see if user has implicit rights.
    */
   , super_acl INTEGER DEFAULT NULL

);

ALTER TABLE new_item_policy 
   ADD CONSTRAINT new_item_policy_pkey 
   PRIMARY KEY (system_id);

/* Make a view for new_item_policy so all the columns fits nicely in one
 * line-width. */

DROP VIEW IF EXISTS nip;
CREATE OR REPLACE VIEW nip AS
   SELECT
      -- system_id
      stack_id
      , branch_id
      --, version AS v
      -- MAYBE: Join to get group name.
      , group_id
      , name
      , access_style_id AS a_sty
      , super_acl AS sup_a
      , target_item_type_id AS typ_id
      -- NOT USED: , target_item_layer AS typ_lr
      , link_left_type_id AS l_typ
      -- NOT USED: , link_left_stack_id AS l_sid
      , link_left_min_access_id AS l_acl
      , link_right_type_id AS r_typ
      -- NOT USED: , link_right_stack_id AS r_sid
      , link_right_min_access_id AS r_acl
      , processing_order AS rank
      , stop_on_match AS stop
   FROM
      new_item_policy
   WHERE
      valid_until_rid = cp_rid_inf()
      AND NOT deleted
      AND NOT reverted
   ;

/* 
 * group_item_access */

/* NOTE: [lb] was conflicted if the name 'item_id' is correct, or if 
         'system_id' is better. But I like item_id because it matches how other
         support tables reference item_versioned. That is, 'system_id' is only
         used by the class hierarchy, not by support tables: if a support table
         references, e.g., a route's system_id, the column is named 'route_id'
         (although, if a column references a stack_id, it's called, e.g.,
         'route_stack_id').  So it seems appropriate to say 'item_id' to mean
         an item's system_id (especially since we item type could be anything).
*/
CREATE TABLE group_item_access (
   /* Each group_item_access relates a specific item at a specific version to a
    * user and an access level. */
   /* The user's private group ID and the user's session ID. We encode the
    * session ID so that anonymous users can have ownership of items during
    * throughout their client session. Note that this currently just applies to
    * routes, i.e., anonymous users can request a route -- which gets saved --
    * and if the user eventually logs in, they can then decide to add that
    * route to their library (and we'll be able to find the route using the
    * user's session ID, which is preserved during logon (and invalidated on
    * logout, since a logout causes a new session ID to be grabbed)). */
/* FIXME: For anonymous users, is there a timeout period? It'd be silly if
          someone sat down at someone else's Cyclopath session, logged in, 
          and stole their routes... so maybe user's have to hit a Clear Cache 
          button, if they don't want to close the Cyclopath window but they 
          want to clear their route history (and autocomplete history, etc.). 
          BUG nnnn: Clear session history (e.g., many new session ID, reset 
          autocomplete lists, clear browsing history, etc.). */
   /* == User Identifier == */
   /* Usually, a GIA record is found by username, but for anonymous users, we
    * can also use the session ID (i.e., to find routes for a client's active
    * session so the user can logon and add those routes to their library). */
   group_id INTEGER NOT NULL,
   /* session_id only applies when group_id is the anonymous user; it gets set
      to the Session ID of the user who causes the save. */
   session_id UUID DEFAULT NULL,
/* BUG nnnn: Use user__session table to store ip addy.
             Check against IP when checking session ID. */
--   session_ip INET NOT NULL,
   /* == Access Level Assigned == */
   access_level_id INTEGER NOT NULL,
   /* == Item Description == */
   name TEXT,
   /* FIXME: Not sure deleted and reverted and name need to be in
    *        group_item_access: they're the same as what's in item_versioned.
    *        It might make sense if it speeds up queries, but I doubt it. */
   deleted BOOLEAN NOT NULL DEFAULT FALSE,
   /* Bug 2695: Branchy Items Need to be 'Revertable'. */
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   branch_id INTEGER NOT NULL,
   item_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* For access-only changes (i.e., versionless and revisionless), the
      acl_grouping is used like version, starting at 1 for each item 
      version and incrementing whenever there's an access-only change to the 
      item (so that access-only changes do not change an item's version). */
/* BUG nnnn: Implement acl_grouping. */
   acl_grouping INTEGER NOT NULL,
   /* Applicable revision IDs. */
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   /* The item's type. */
   item_type_id INTEGER NOT NULL,
   /* 2013.08.06: item_layer_id is deprecated; nothing uses it. */
   -- item_layer_id INTEGER NOT NULL,
   /* Link details, if item is a link_value. */
   link_lhs_type_id INTEGER,
   link_rhs_type_id INTEGER,
   /* == Audit trail == */
   created_by TEXT,
   /* Users can change permissions without saving a new revision (like
    * adding/updating ratings or watchers can be done without saving a
    * revision), so keep a record of changes. */
   /* NOTE: The created_by and date_created fields are only not null for
      records that can't be joined against item_versioned and revision to
      get the same value. */
   date_created TIMESTAMP WITH TIME ZONE
   /* We don't need last_modified since GIA records are only updated once, to
    * set the valid_until_rid when a new GIA records supercedes it. */
   /* NO: last_modified TIMESTAMP WITH TIME ZONE NOT NULL */

-- FIXME: When you set valid_until_rid, make sure GIA sets all records (i.e.,
-- w/ different acl_grouping

-- FIXME: finish implementing created_by, date_created, and last_modified.


);

ALTER TABLE group_item_access 
   ADD CONSTRAINT group_item_access_pkey 
   PRIMARY KEY (group_id, item_id, valid_until_rid, acl_grouping);

/* 
 * group_revision */

/* FIXME: branch_id in both revision and group_revision: I'm leaning toward 
          having it just in revision... */
/* FIXME: Is is_revertable useful? it's always true if visible_items > 0,
 *       anyway, since grac changes are not visible? */
/* FIXME: visible_items is not named right: in apb-55, it includes the new
 *       group that is created. so it's more like changed_items, or new_items,
 *       or new_item_versions. and is_revertable means something was a script,
 *       so we don't want a user to try to revert it (i.e., a Very Big
 *       Operation). */
CREATE TABLE group_revision (
   group_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   revision_id INTEGER NOT NULL,
   visible_items INTEGER NOT NULL, -- FIXME Does not apply to GrAC?
   is_revertable BOOLEAN NOT NULL, -- items: TRUE, permissions: FALSE
   -- BUG nnnn: Show in recent changes when user rates, changes permissions,
   -- edits watchers, etc.
   date_created TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE group_revision 
   ADD CONSTRAINT group_revision_pkey 
   PRIMARY KEY (group_id, branch_id, revision_id);

CREATE TRIGGER group_revision_date_created_i
   BEFORE INSERT ON group_revision
   FOR EACH ROW EXECUTE PROCEDURE public.set_date_created();

/* 2012.09.18: Do we want to disable the trigger before populating??
 * The NOT NULL will complain if I'm wrong... */
-- NO: We need it because group_revision is new and we populate it 
-- with now()
--   ALTER TABLE group_revision DISABLE TRIGGER group_revision_date_created_i;
/* FIXME: Is this okay? That group_revision.date_created is the time when this
          script runs? The revision table has the real date... but maybe we
          should copy its date? Or not have a date at all? I.e., won't
          group_revision.created always be equal to the revision timestamp? */

\set dimension 2
SELECT AddGeometryColumn('group_revision', 'bbox', (SELECT cp_srid()), 
                         'POLYGON', :dimension);
SELECT AddGeometryColumn('group_revision', 'geometry', (SELECT cp_srid()),
                         'MULTIPOLYGON', :dimension);
SELECT AddGeometryColumn('group_revision', 'geosummary', (SELECT cp_srid()), 
                         'MULTIPOLYGON', :dimension);

/* ==================================================================== */
/* Step (3) -- Un-Silence                                               */
/* ==================================================================== */

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* ==================================================================== */
/* Step (4) -- Modify revision table                                    */
/* ==================================================================== */

\qecho 
\qecho Adding is_revertable to revision table
\qecho 

ALTER TABLE revision ADD COLUMN is_revertable BOOLEAN;

\qecho 
\qecho Adding reverted_count to revision table
\qecho 

ALTER TABLE revision ADD COLUMN reverted_count INTEGER;

/* skip_geometry is not useful: you can deduce it if any of the geometry
 * columns are NULL. And it's not maintained very well: In Ccpv1, it's 
 * sometimes FALSE when geometry columns are NULL; so it seems broken, too. */
\qecho 
\qecho Dropping skip_geometry from revision table
\qecho 

ALTER TABLE revision DROP COLUMN skip_geometry;

/* 

The minnesota instance currently has 441 revert_events:

   cycling2=> SELECT COUNT(*) FROM revert_event;
    count 
   -------
      441
   (1 row)

This makes sense, since users are allowed to revert more than one revision at 
a time:

   cycling2=> SELECT COUNT(DISTINCT rid_reverting) FROM revert_event;
    count 
   -------
      400
   (1 row)

However, this doesn't make sense, since once reverted, how can a revision be 
reverted again?:

   cycling2=> SELECT COUNT(DISTINCT rid_victim) FROM revert_event;
    count 
   -------
      435
   (1 row)

Here are the rows in question:

   cycling2=> SELECT re.id,  re.rid_reverting,  re.rid_victim,
                     re2.id, re2.rid_reverting, re2.rid_victim 
              FROM revert_event re 
              JOIN revert_event re2 
                 ON re.rid_victim = re2.rid_victim 
                    AND re.id < re2.id;
    id  | rid_reverting | rid_victim | id  | rid_reverting | rid_victim 
   -----+---------------+------------+-----+---------------+------------
     45 |          6296 |       6067 |  46 |          6297 |       6067
    120 |          8676 |       8674 | 121 |          8677 |       8674
    141 |          8996 |       8991 | 142 |          8997 |       8991
    191 |         10304 |      10303 | 192 |         10309 |      10303
    333 |         12635 |      12633 | 334 |         12640 |      12633
    374 |         12891 |      12882 | 378 |         12946 |      12882
   (6 rows)

If we examine the last two reverts:

   cycling2=> SELECT id,version 
              FROM geofeature 
                 WHERE valid_starting_rid in (12882,12891,12946);
      id    | version 
   ---------+---------
    1503387 |       1
    1503387 |       4
    1503387 |       5
   (3 rows)

   cycling2=> SELECT id, version, valid_starting_rid, valid_before_rid 
              FROM geofeature 
                 WHERE id = 1503387;
      id    | version | valid_starting_rid | valid_before_rid 
   ---------+---------+--------------------+------------------
    1503387 |       1 |              12882 |            12883
    1503387 |       2 |              12883 |            12884
    1503387 |       3 |              12884 |            12891
    1503387 |       4 |              12891 |            12946
    1503387 |       5 |              12946 |       2000000000
   (5 rows)

FIXME Explain how the same revision got reverted twice...

*/

\qecho 
\qecho Populating reverted_count
\qecho 

CREATE FUNCTION revision_update_reverted_count()
   RETURNS VOID AS $$
   DECLARE
      rev_evt RECORD;
   BEGIN
      /* Iterate through revert_event and make some counts */
      FOR rev_evt IN SELECT DISTINCT rid_reverting FROM revert_event LOOP
         --RAISE INFO '...rid_reverting: %', rev_evt.rid_reverting;
         UPDATE revision 
            SET reverted_count 
               = (SELECT COUNT(*) FROM item_versioned 
                     WHERE valid_start_rid = rev_evt.rid_reverting)
            WHERE id = rev_evt.rid_reverting;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE 2010.11.03 Not sure what I did, but this used to take a while on the 
                   minnesota schema, and now it runs really quick. */
\qecho ...updating rows
\qecho    ...this takes a few seconds...
SELECT revision_update_reverted_count();

DROP FUNCTION revision_update_reverted_count();

/* ==================================================================== */
/* Step (5) -- Miscellaneous                                            */
/* ==================================================================== */

\qecho 
\qecho Setting all rows of revision
\qecho 

/* Non-revertable revisions are access level changes, so everything in the old 
   database is revertable, since access level changes were not revisioned. */
\qecho ... revision.is_revertable = TRUE
UPDATE revision SET is_revertable = TRUE;

/* I'm [lb] choosing to default this to 0, rather than leaving it NULL. */
\qecho ... revision.reverted_count = 0
UPDATE revision SET reverted_count = 0;

\qecho 
\qecho Renaming draw_class_id columns to draw_class_viewer
\qecho 

ALTER TABLE tiles_cache_byway_names RENAME COLUMN draw_class_id 
                                               TO draw_class_viewer;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

