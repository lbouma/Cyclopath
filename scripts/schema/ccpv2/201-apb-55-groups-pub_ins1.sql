/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates and populates the public basemap group. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates and populates the public basemap group.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1.1) -- Define function for retrieving private group ID        */
/* ==================================================================== */

\qecho 
\qecho Creating private group ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. 
 *           That is, use this command to get the ID just once, then 
 *           build your SQL select; don't run SQL commands with this 
 *           (or any other cp_*()) command in it. */

CREATE FUNCTION cp_group_private_id(IN username TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      group_id INTEGER;
      access_scope_id_ INTEGER;
      access_level_denied INTEGER;
      valid_until_rid INTEGER;
   BEGIN
      /* Hard-coding access_scope_id in fcn. means we need to re-define
       * function if we change access scope ids. */
      access_scope_id_ := cp_access_scope_id('private');
      access_level_denied := cp_access_level_id('denied');
      valid_until_rid := cp_rid_inf();
      /* FIXME: Do we need to check grp.valid_until_rid or grp.deleted? */
      BEGIN
         EXECUTE 'SELECT grp.stack_id AS group_id
                     FROM user_ AS usr
                     JOIN group_membership AS gmp
                        ON gmp.user_id = usr.id
                     JOIN group_ AS grp
                        ON grp.stack_id = gmp.group_id
                     WHERE
                        usr.username = ''' || username || ''' 
                        AND grp.access_scope_id = ' || access_scope_id_ || '
                        AND gmp.access_level_id < ''' 
                           || access_level_denied || '''
                        AND gmp.valid_until_rid = ' || valid_until_rid || '
                        AND gmp.deleted IS FALSE;'
            INTO STRICT group_id;
      EXCEPTION WHEN no_data_found THEN
         RAISE INFO 'No such group or user is not member: %', username;
         group_id := 0;
      END;
      RETURN group_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
CREATE FUNCTION cp_group_private_id_sloppy(IN username TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      group_id INTEGER;
      access_scope_id_ INTEGER;
      valid_until_rid INTEGER;
   BEGIN
      /* Hard-coding access_scope_id in fcn. means we need to re-define
       * function if we change access scope ids. */
      access_scope_id_ := cp_access_scope_id('private');
      valid_until_rid := cp_rid_inf();
      BEGIN
         /* This is the 'quick' way to do it, without complete disrespek for 
          * group_membership permissions. */
         EXECUTE 'SELECT stack_id FROM group_ 
                     WHERE name = ''' || username || ''' 
                           AND access_scope_id = ' || access_scope_id_ || '
                           AND valid_until_rid = ' || valid_until_rid || '
                           AND deleted IS FALSE;'
            INTO STRICT group_id;
      EXCEPTION WHEN no_data_found THEN
         RAISE WARNING 'No such group: %', username;
         group_id := 0;
      END;
      RETURN group_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
CREATE FUNCTION cp_group_shared_id(IN groupname TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      group_id INTEGER;
      access_scope_id_ INTEGER;
      valid_until_rid INTEGER;
   BEGIN
      /* Hard-coding access_scope_id in fcn. means we need to re-define
       * function if we change access scope ids. */
      access_scope_id_ := cp_access_scope_id('shared');
      valid_until_rid := cp_rid_inf();
      BEGIN
         /* This is the 'quick' way to do it, without complete disrespek for 
          * group_membership permissions. */
         EXECUTE 'SELECT stack_id FROM group_ 
                     WHERE name = ''' || groupname || ''' 
                           AND access_scope_id = ' || access_scope_id_ || '
                           AND valid_until_rid = ' || valid_until_rid || '
                           AND deleted IS FALSE;'
            INTO STRICT group_id;
      EXCEPTION WHEN no_data_found THEN
         RAISE INFO 'No such group: %', groupname;
         group_id := 0;
      END;
      RETURN group_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (1.2) -- Define function for retrieving basemap group ID        */
/* ==================================================================== */

\qecho 
\qecho Creating basemap owners group ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* NOTE The key_value_pair row will be created in a later script. */
CREATE FUNCTION cp_group_basemap_owners_id(IN instance TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      instance_key TEXT;
   BEGIN
      IF instance IS NOT NULL AND instance != '' THEN
         instance_key = 'cp_group_basemap_owners_id_' || instance;
      ELSE
         instance_key = 'cp_group_basemap_owners_id_@@@instance@@@';
      END IF;
      RETURN value::INTEGER FROM key_value_pair 
         WHERE key = instance_key;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (1.3) -- Create one revision for this whole script.             */
/* ==================================================================== */

\qecho 
\qecho Creating shared group for basemap branch owners
\qecho 

/* Create a new revision that only the branch owners can see. */

\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
   'Group Access Ctrl: Make Basemap groups. Add all users to Public group.');

/* ==================================================================== */
/* Step (1.4) -- Create shared group for basemap owners                 */
/* ==================================================================== */

\qecho 
\qecho Creating shared group for basemap branch owners
\qecho 

/* Create a new revision that only the branch owners can see. */

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
   'Group Access Control: Adding Shared Group for Basemap Owners');
*/

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here must match the one in group_, below
   (cp_branch_baseline_id(), 1, 'Basemap Owners', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
   -- SYNC_ME: 'Basemap Owners'.
   'Basemap Owners', -- This name must match the one in item_versioned, above
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
   'Basemap Owners', 
   cp_access_scope_id('shared'));
   
\qecho ...storing Basemap Owners Group ID
INSERT INTO key_value_pair (key, value) 
   VALUES ('cp_group_basemap_owners_id_@@@instance@@@', 
           CURRVAL('item_stack_stack_id_seq'));

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));
*/

\qecho 
\qecho Basemap-owners user group created with group ID:
SELECT cp_group_basemap_owners_id('');
\qecho 

/* ==================================================================== */
/* Step (2.1) -- Define function for retrieving public group ID         */
/* ==================================================================== */

\qecho 
\qecho Creating public group ID convenience function
\qecho 

/* NOTE: This is a Convenience fcn. for pyserver.
         This is not a temporary fcn.; we will not be deleting it. */
/* NOTE: The key_value_pair row will be created in a later script. */
/* Remember: Fcns that use select used within another select are costly. */
/* NOTE: MapServer needs the schema to be hard-coded, so we're defining this
 *      fcn. specifically for each instance. */
CREATE FUNCTION cp_group_public_id()
   RETURNS INTEGER AS $$
   BEGIN
      RETURN value::INTEGER FROM @@@instance@@@.key_value_pair 
         WHERE key = 'cp_group_public_id';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (2.2) -- Create public group                                    */
/* ==================================================================== */

\qecho 
\qecho Creating public group
\qecho 

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
    'Group Access Control: Adding Public Group for Basemap');
*/

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here should match the one in group_, below
--   (cp_branch_baseline_id(), 1, 'Public', FALSE, FALSE, 
--   (cp_branch_baseline_id(), 1, 'Basemap Editors', FALSE, FALSE, 
   (cp_branch_baseline_id(), 1, 'All Users', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
--   'Public', -- This name should match the one in item_versioned, above
--   'Basemap Editors', -- This name matches the one in item_versioned, above.
   'All Users', -- This name matches the one in item_versioned, above.
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
--   'Public Group',
   'All users, including anonymous (users who are not logged in).',
   cp_access_scope_id('public'));

\qecho ...storing public group ID
INSERT INTO key_value_pair (key, value) 
   VALUES ('cp_group_public_id', CURRVAL('item_stack_stack_id_seq'));

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));
*/

\qecho 
\qecho Public user group created with group ID:
SELECT cp_group_public_id();
\qecho 

/* ==================================================================== */
/* Step (3.1) -- Create anonymous user                                  */
/* ==================================================================== */

\qecho 
\qecho Creating anonymous user named: _user_anon_@@@instance@@@
\qecho 

/* login_permitted has to be TRUE because of how future scripts operate.
   When making group_membership and other GrAC items, future scripts 
   ignore users whose login_permitted is FALSE. */

/* FIXME Make sure that login_permitted = TRUE and no password doesn't let
 *       someone login as the anonymous user!! 
 *
 * BUG nnnn: Do not let people use preceeding underscores for usernames 
 *           or logging in.
 *       */

INSERT INTO user_ 
   (username, email, login_permitted, 
    enable_wr_email, enable_wr_digest, 
    enable_email, enable_email_research, dont_study)
   VALUES ('_user_anon_@@@instance@@@', NULL, TRUE, 
           FALSE, FALSE, 
           FALSE, FALSE, FALSE);

/* ==================================================================== */
/* Step (4.1) -- Add all users to the public group                      */
/* ==================================================================== */

\qecho 
\qecho Granting all users membership in the public group
\qecho 

/* FIXME: Is this necessary? Given the anonymous user? */



/* BUG nnnn: New user registration... works with CcpV2? probably not... 
 * well, maybe, see: cp_user_new
 *
 * FIXME: This probably isn't necessary except for anonymous user (see last sql
 *         statement) or you want to make sure to add this to new user
 *         registration.
 *
 *         ALSO: routes viewable by basemap owners... but you don't make this
 *         record in route.py for new routes, do you?? */



\qecho ...creating helper fcn.
CREATE FUNCTION group_add_public_all_users()
   RETURNS VOID AS $$
   DECLARE
      user_rec user_%ROWTYPE;
      gm_system_id INTEGER;
      gm_stack_id INTEGER;
      /* Cache vars. */
      revision_id INTEGER;
      branch_baseline_id INTEGER;
      rid_beg INTEGER;
      rid_inf INTEGER;
      group_public_id INTEGER;
      access_level_id_ INTEGER;
   BEGIN
      /* Cache plpgpsql values. */
      /* NOTE: For the public group, make sure the user's start rid is 1,
       *       otherwise they won't be able to see historic data. */
      -- NO: rid_beg := CURRVAL('revision_id_seq');
      rid_beg := 1; -- 1 is the first revision ID.
      branch_baseline_id := cp_branch_baseline_id();
      rid_inf := cp_rid_inf();
      group_public_id := cp_group_public_id();
      access_level_id_ := cp_access_level_id('viewer');
      /* NOTE 075-script-user.sql sets login_permitted to TRUE on the user 
       *      named '_script'. I'm not sure what the original intent was -- 
       *      is there a need to login as '_script'? -- but keeping 
       *      login_permitted gives us a user to test or run against pyserver 
       *      and the new group access control system. */
      /* Only grant membership for users that can login, which excludes users
       * we've banned as well as fake users we've created as developers. */
      FOR user_rec IN SELECT * FROM user_ WHERE login_permitted IS TRUE LOOP
         /* Create a new item */
         INSERT INTO item_versioned 
            (branch_id, version, name, deleted, reverted,
             valid_start_rid, valid_until_rid)
         VALUES 
            (branch_baseline_id, 1, NULL, FALSE, FALSE, 
             rid_beg, rid_inf);
         gm_system_id := CURRVAL('item_versioned_system_id_seq');
         gm_stack_id := CURRVAL('item_stack_stack_id_seq');
         /* Add user to group_membership */
         INSERT INTO group_membership 
               (system_id,
                branch_id,
                stack_id,
                version,
                deleted,
                name,
                valid_start_rid,
                valid_until_rid,
                user_id,
                username,
                group_id,
                access_level_id,
                opt_out)
            VALUES 
               (gm_system_id,
                branch_baseline_id,
                gm_stack_id,
                1,
                FALSE,
                NULL,
                /* NOTE: Using valid_start_rid = 1, so user can see public 
                 *       history. */
                rid_beg,
                rid_inf,
                user_rec.id,
                user_rec.username,
                group_public_id,
                access_level_id_,
                FALSE);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* Create a new revision that only the branch owners can see. */

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
    'Group Access Control: Adding Users to Public Group');
*/

\qecho ...adding all users to public group
SELECT group_add_public_all_users();

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));
*/

\qecho ...dropping helper fcn.
DROP FUNCTION group_add_public_all_users();

/* ==================================================================== */
/* Step (5.1) -- Create shared group from basemap arbiters              */
/* ==================================================================== */

/* 2012.10.09: The convention with branches is to make three groups, i.e.,
               %{branch-name} Editors, %{branch-name} Owners, and 
               %{branch-name} Arbiters. So we do that here, though those two
               groups currently aren't used (but we reserve their names here).
*/

\qecho
\qecho Creating shared group for basemap branch arbiters and editors.
\qecho

/* Basemap Arbiters. */

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here must match the one in group_, below
   (cp_branch_baseline_id(), 1, 'Basemap Arbiters', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
   'Basemap Arbiters', -- This name must match the one in item_versioned, above
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
   'Basemap Arbiters', 
   cp_access_scope_id('shared'));

/* Basemap Editors. */

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here must match the one in group_, below
   (cp_branch_baseline_id(), 1, 'Basemap Editors', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
   'Basemap Editors', -- This name must match the one in item_versioned, above
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
   'Basemap Editors', 
   cp_access_scope_id('shared'));

/* ==================================================================== */
/* Step (6.1) -- Define function for retrieving stealth group ID        */
/* ==================================================================== */

\qecho 
\qecho Creating public group ID convenience function
\qecho 

/* NOTE: This is a Convenience fcn. for pyserver.
         This is not a temporary fcn.; we will not be deleting it. */
/* NOTE: The key_value_pair row will be created in a later script. */
/* Remember: Fcns that use select used within another select are costly. */
/* NOTE: MapServer needs the schema to be hard-coded, which is why we define a
 *       unique public group ID for each instance. So we don't really need to
 *       define a unique stealth group ID for each instance, except that the
 *       key_value_pair table is per-instance, so what the hay. */
CREATE FUNCTION cp_group_stealth_id()
   RETURNS INTEGER AS $$
   BEGIN
      RETURN value::INTEGER FROM @@@instance@@@.key_value_pair 
         WHERE key = 'cp_group_stealth_id';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (6.2) -- Create stealth group                                   */
/* ==================================================================== */

\qecho 
\qecho Creating stealth group
\qecho 

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here should match the one in group_, below
   (cp_branch_baseline_id(), 1, 'Stealth-Secret Group', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
   'Stealth-Secret Group', -- This name matches same in item_versioned, above.
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
   'Users who use a shared secret to find items.',
   -- Use the 'public' scope; now we have two MAGIC_NUMBERs for 'public':
   --    'All Users' and 'Stealth-Secret Group'
   cp_access_scope_id('public'));

\qecho ...storing stealth group ID
INSERT INTO key_value_pair (key, value) 
   VALUES ('cp_group_stealth_id', CURRVAL('item_stack_stack_id_seq'));

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));
*/

\qecho 
\qecho Stealth user group created with group ID:
SELECT cp_group_stealth_id();
\qecho 

/* ==================================================================== */
/* Step (7.1) -- Define function for retrieving session group ID        */
/* ==================================================================== */

\qecho 
\qecho Creating public group ID convenience function
\qecho 

/* NOTE: This is a Convenience fcn. for pyserver.
         This is not a temporary fcn.; we will not be deleting it. */
/* NOTE: The key_value_pair row will be created in a later script. */
/* Remember: Fcns that use select used within another select are costly. */
/* NOTE: MapServer needs the schema to be hard-coded, which is why we define a
 *       unique public group ID for each instance. So we don't really need to
 *       define a unique session group ID for each instance, except that the
 *       key_value_pair table is per-instance, so what the hay. */
CREATE FUNCTION cp_group_session_id()
   RETURNS INTEGER AS $$
   BEGIN
      RETURN value::INTEGER FROM @@@instance@@@.key_value_pair 
         WHERE key = 'cp_group_session_id';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (7.2) -- Create session group                                   */
/* ==================================================================== */

\qecho 
\qecho Creating session group
\qecho 

\qecho ...creating new item_versioned
INSERT INTO item_versioned 
   (branch_id, version, name, deleted, reverted,
    valid_start_rid, valid_until_rid)
VALUES 
   -- The name here should match the one in group_, below
   (cp_branch_baseline_id(), 1, 'Session ID Group', FALSE, FALSE, 
    CURRVAL('revision_id_seq'), cp_rid_inf());

\qecho ...creating new group
INSERT INTO group_ 
   (
   system_id,
   branch_id,
   stack_id,
   version,
   deleted,
   name,
   valid_start_rid,
   valid_until_rid,
   description,
   access_scope_id
   ) 
VALUES 
   (
   CURRVAL('item_versioned_system_id_seq'),
   cp_branch_baseline_id(),
   CURRVAL('item_stack_stack_id_seq'),
   1,
   FALSE,
   'Session ID Group', -- This name matches same in item_versioned, above.
      -- NO: CURRVAL('revision_id_seq'), 
   1, -- YES: Start at RID 1.
   cp_rid_inf(),
   'Users who use a shared secret to find items.',
   -- MAYBE: [lb] is assuming 'shared' is the proper access scope.
   cp_access_scope_id('shared'));

\qecho ...storing session group ID
INSERT INTO key_value_pair (key, value) 
   VALUES ('cp_group_session_id', CURRVAL('item_stack_stack_id_seq'));

/* 2012.10.09: Using one revision instead of three or four.
\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));
*/

\qecho 
\qecho Session user group created with group ID:
SELECT cp_group_session_id();
\qecho 

/* ==================================================================== */
/* Step (n)(-1) -- Create one revision for this whole script.           */
/* ==================================================================== */

\qecho ...creating new group_revision
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

