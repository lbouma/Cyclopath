/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates a private group for each user. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates a private group for each user.
\qecho 
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 0.10 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.14 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Create helper functions                                  */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

/* NOTE This is a Convenience fcn. for Cyclopath.
        This is not a temporary fcn.; we will not be deleting it. */
\qecho ...creating permanent helper fcn.
CREATE FUNCTION cp_rev_max()
   RETURNS INTEGER AS $$
   DECLARE
      rid_max INTEGER;
   BEGIN
      EXECUTE 'SELECT MAX(id) FROM revision WHERE id < cp_rid_inf();'
         INTO STRICT rid_max;
      RETURN rid_max;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE This is a Convenience fcn. for Cyclopath.
        This is not a temporary fcn.; we will not be deleting it. */
\qecho ...creating permanent helper fcn.
CREATE FUNCTION cp_group_make_private_group(
      IN username TEXT,
      IN branch_baseline_id INTEGER,
      IN rid_beg INTEGER,
      IN rid_inf INTEGER,
      IN access_scope_id_ INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      gp_system_id INTEGER;
      gp_stack_id INTEGER;
   BEGIN
      /* Create a new item */
      BEGIN
         /* We haven't created item_stack yet but we keep this fcn., so be
            forward-thinking. */
         INSERT INTO item_stack 
            (creator_name, access_style_id, access_infer_id)
         VALUES 
            ('_script',
             cp_access_style_id('all_denied'),
             cp_access_infer_id('usr_viewer'));
         gp_stack_id := CURRVAL('item_stack_stack_id_seq');
         /* */
         INSERT INTO item_versioned 
            (branch_id, stack_id, version, name, deleted, reverted, 
             valid_start_rid, valid_until_rid)
         VALUES 
            (branch_baseline_id, gp_stack_id, 1, username, FALSE, FALSE,
             rid_beg, rid_inf);
      EXCEPTION WHEN undefined_table THEN
         /* This happens during schema-upgrade, before creating item_stack. */
         INSERT INTO item_versioned 
            (branch_id, version, name, deleted, reverted, 
             valid_start_rid, valid_until_rid)
         VALUES 
            (branch_baseline_id, 1, username, FALSE, FALSE,
             rid_beg, rid_inf);
         gp_stack_id := CURRVAL('item_stack_stack_id_seq');
      END;
      /* The item name is same as username; same for group_ name. */
      /* NOTE: Using CURRVAL('revision_id_seq') or cp_rev_max() instead of 
       *       RID 1. Since this is a private group... it shouldn't matter if 
       *       it's 1 or not (unlike public group, which needs to start at 1.) 
       */
      /* Get the system ID that was just created. */
      gp_system_id := CURRVAL('item_versioned_system_id_seq');
      /* Add record to group_. */
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
         gp_system_id,
         branch_baseline_id,
         gp_stack_id,
         1,
         FALSE,
         username, -- This name should match the one above
         /* CORRECT?: Start at latest RID and not at 1? */
         rid_beg,
         rid_inf,
         'Private Group', 
         access_scope_id_);
      RETURN gp_stack_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (2) -- Create private group for each user                       */
/* ==================================================================== */

\qecho 
\qecho Creating private group for each user
\qecho 

\qecho ...creating temporary helper fcn.
CREATE FUNCTION group_add_private_groups()
   RETURNS VOID AS $$
   DECLARE
      user_rec user_%ROWTYPE;
      branch_baseline_id INTEGER;
      rid_beg INTEGER;
      rid_inf INTEGER;
      access_scope_id_ INTEGER;
      gp_stack_id INTEGER;
   BEGIN
      /* Cache plpgsql static values. */
      branch_baseline_id := cp_branch_baseline_id();
      rid_beg := CURRVAL('revision_id_seq');
      rid_inf := cp_rid_inf();
      access_scope_id_ := cp_access_scope_id('private');
      /* CORRECT?: Include all users. */
      /* NO: 
      FOR user_rec IN SELECT * FROM user_ WHERE login_permitted IS TRUE LOOP
       */
      FOR user_rec IN SELECT * FROM user_ LOOP
      gp_stack_id := cp_group_make_private_group(user_rec.username, 
            branch_baseline_id, rid_beg, rid_inf, access_scope_id_);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* Create a new revision that only the branch owners can see. */

\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
    'Group Access Control: Adding Private User Groups');

\qecho ...creating private groups
SELECT group_add_private_groups();

\qecho ...creating new group_revision for basemap owners
INSERT INTO group_revision 
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES 
      (cp_group_basemap_owners_id(''), 
       cp_branch_baseline_id(), 
       CURRVAL('revision_id_seq'), 
       FALSE, 
       (SELECT COUNT(*) FROM item_versioned 
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));

\qecho ...dropping temporary helper fcn.
DROP FUNCTION group_add_private_groups();

/* ==================================================================== */
/* Step (3) -- Create helper functions                                  */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

/* NOTE This is a Convenience fcn. for Cyclopath.
        This is not a temporary fcn.; we will not be deleting it. */
\qecho ...creating permanent helper fcn.
CREATE FUNCTION cp_group_membership_new(
      IN user_id_ INTEGER,
      IN username_ TEXT,
      IN branch_baseline_id INTEGER,
      IN rid_beg INTEGER,
      IN rid_inf INTEGER,
      IN group_id_ INTEGER,
      IN access_level_id_ INTEGER)
   RETURNS VOID AS $$
   DECLARE
      gm_system_id INTEGER;
      gm_stack_id INTEGER;
   BEGIN
      /* Create a new item */
      BEGIN
         /* We haven't created item_stack yet but we keep this fcn. */
         INSERT INTO item_stack 
            (creator_name, access_style_id, access_infer_id)
         VALUES 
            ('_script',
             cp_access_style_id('all_denied'),
             cp_access_infer_id('usr_viewer'));
         gm_stack_id := CURRVAL('item_stack_stack_id_seq');
         /* */
         INSERT INTO item_versioned 
            (branch_id, stack_id, version, name, deleted, reverted, 
             valid_start_rid, valid_until_rid)
         VALUES 
            (branch_baseline_id, gm_stack_id, 1, NULL, FALSE, FALSE, 
             rid_beg, rid_inf);
      EXCEPTION WHEN undefined_table THEN
         /* This happens during schema-upgrade, before creating item_stack. */
         INSERT INTO item_versioned 
            (branch_id, version, name, deleted, reverted, 
             valid_start_rid, valid_until_rid)
         VALUES 
            (branch_baseline_id, 1, NULL, FALSE, FALSE, 
             rid_beg, rid_inf);
         gm_stack_id := CURRVAL('item_stack_stack_id_seq');
      END;
      gm_system_id := CURRVAL('item_versioned_system_id_seq');
      /* Add user to group_membership */
      /* NOTE: Using cp_group_private_id_sloppy since user doesn't 
       *       have group_membership yet, which is what we're doing
       *       here. */
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
             1,      -- the first version
             FALSE,  -- not deleted
             NULL,   -- no name
             /* CORRECT?: We don't have to use valid_start_rid = 1? I think
             *            that only matters for the public group (and for
             *            shared groups we might want to use an earlier 
             *            valid_start_rid for history to work?). */
             /* CORRECT?: Start at latest RID and not at 1? */
             rid_beg,
             rid_inf,
             user_id_,
             username_,
             group_id_,
             access_level_id_,
             FALSE);
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (4) -- Grant each user access to their private group            */
/* ==================================================================== */

\qecho 
\qecho Granting each user access to their private group
\qecho 

\qecho ...creating temporary helper fcn.
CREATE FUNCTION group_add_private_group_memberships()
   RETURNS VOID AS $$
   DECLARE
      user_rec user_%ROWTYPE;
      branch_baseline_id INTEGER;
      rid_beg INTEGER;
      rid_inf INTEGER;
      access_level_id_ INTEGER;
      group_id INTEGER;
   BEGIN
      /* Cache plpgsql static values. */
      branch_baseline_id := cp_branch_baseline_id();
      rid_beg := CURRVAL('revision_id_seq');
      rid_inf := cp_rid_inf();
      access_level_id_ := cp_access_level_id('viewer');
      /* */
      FOR user_rec IN SELECT * FROM user_ WHERE login_permitted IS TRUE LOOP
         group_id := cp_group_private_id_sloppy(user_rec.username);
         PERFORM cp_group_membership_new(
               user_rec.id, user_rec.username, branch_baseline_id,
               rid_beg, rid_inf, group_id, access_level_id_);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* Create a new revision that only the branch owners can see. */

\qecho ...creating new revision
INSERT INTO revision 
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES 
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE, 
    'Group Access Control: Adding Users to Private Groups');

\qecho ...granting access to private groups
SELECT group_add_private_group_memberships();

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

\qecho ...dropping temporary helper fcn.
DROP FUNCTION group_add_private_group_memberships();

/* ==================================================================== */
/* Step (5) -- Create fcns. to add private user groups and 'ships       */
/* ==================================================================== */

/* These fcns. are needed for CycloAuth.php, which creates new users and 
 * just has remote access to the database. If we didn't want to use SQL 
 * we'd have to send obscure GWIS commands to make the private group and 
 * memberships. */

/* NOTE This is a Convenience fcn. for Cyclopath.
        This is not a temporary fcn.; we will not be deleting it. */
\qecho ...creating permanent helper fcn.
CREATE FUNCTION cp_user_new(
      IN username_ TEXT, 
      IN user_email TEXT,
      IN user_pass TEXT)
   RETURNS VOID AS $$
   DECLARE
      user_id INTEGER;
      revision_id INTEGER;
      branch_baseline_id INTEGER;
      rid_beg INTEGER;
      rid_inf INTEGER;
      group_id INTEGER;
      access_scope_id_ INTEGER;
      access_level_id_ INTEGER;
      gp_stack_id INTEGER;
   BEGIN
      /* Cache plpgsql static values. */
      branch_baseline_id := cp_branch_baseline_id();
      rid_inf := cp_rid_inf();
      /* Start with the CcpV1 user_ table. */
      INSERT INTO user_
         (username, email, login_permitted)
      VALUES
         (username_, user_email, 't');
      /* Set the user's password. */
      PERFORM password_set(username_, user_pass);
      /* Get the user's ID. */
      user_id := cp_user_id(username_);
      /* Make the private group. */
      rid_beg := cp_rev_max();
      access_scope_id_ := cp_access_scope_id('private');
      gp_stack_id := cp_group_make_private_group(
            username_, branch_baseline_id, 
            rid_beg, rid_inf, access_scope_id_);
      /* Make the private group membership. */
      rid_beg := cp_rev_max();
      group_id := cp_group_private_id_sloppy(username_);
      access_level_id_ := cp_access_level_id('viewer');
      PERFORM cp_group_membership_new(
            user_id, username_, branch_baseline_id,
            rid_beg, rid_inf, group_id, access_level_id_);
      /* Make the public group membership. */
      rid_beg := 1; -- Use 1 so user can see public history.
      group_id := cp_group_public_id();
      access_level_id_ := cp_access_level_id('viewer');
      PERFORM cp_group_membership_new(
            user_id, username_, branch_baseline_id,
            rid_beg, rid_inf, group_id, access_level_id_);
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

