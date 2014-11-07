/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Regression: Update cp_user_new callouts...
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Fixing new user fcns. used by Mediawiki CycloAuth.php plugin...
\qecho  FIXME: that we really need to do a better job of testing
\qecho         or at least proactively catching errors...
\qecho

/* */

ALTER TABLE item_revisionless ALTER COLUMN stack_id
   SET DEFAULT nextval('item_stack_stack_id_seq');
ALTER TABLE item_revisionless ALTER COLUMN system_id
   SET DEFAULT nextval('item_versioned_system_id_seq');

/* */

\qecho ...creating permanent helper fcn.
CREATE OR REPLACE FUNCTION cp_group_make_private_group(
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

      INSERT INTO item_stack 
         (access_style_id, access_infer_id)
         -- Skipping: stealth_secret, cloned_from_id
      VALUES 
         (cp_access_style_id('all_denied'),
          cp_access_infer_id('usr_viewer'));
      /* Get the freshly-created stack ID. */
      gp_stack_id := CURRVAL('item_stack_stack_id_seq');

      INSERT INTO item_versioned 
         (branch_id, stack_id, version, name, deleted, reverted, 
          valid_start_rid, valid_until_rid)
      VALUES 
         (branch_baseline_id, gp_stack_id, 1, username, FALSE, FALSE,
          rid_beg, rid_inf);
      /* The item name is same as username; same for group_ name. */
      /* NOTE: Using CURRVAL('revision_id_seq') or cp_rev_max() instead of 
       *       RID 1. Since this is a private group... it shouldn't matter if 
       *       it's 1 or not (unlike public group, which needs to start at 1.) 
       */
      /* Get the system ID that was just created. */
      gp_system_id := CURRVAL('item_versioned_system_id_seq');

      INSERT INTO item_revisionless
         (branch_id, system_id, stack_id, version, acl_grouping,
          edited_date,
          edited_user,
          edited_note,
          edited_addr,
          edited_host,
          edited_what)
      VALUES 
         (branch_baseline_id, gp_system_id, gp_stack_id, 1, 1,
          NOW(),
          '_script', -- edited_user
          NULL, -- edited_note
          NULL, -- edited_addr
          NULL, -- edited_host
          NULL); -- edited_what

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

/* */

CREATE OR REPLACE FUNCTION cp_group_membership_new(
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

      INSERT INTO item_stack 
         (access_style_id, access_infer_id)
         -- Skipping: stealth_secret, cloned_from_id
      VALUES 
         (cp_access_style_id('all_denied'),
          cp_access_infer_id('usr_viewer'));
      /* Get the freshly-created stack ID. */
      gm_stack_id := CURRVAL('item_stack_stack_id_seq');

      /* */
      INSERT INTO item_versioned 
         (branch_id, stack_id, version, name, deleted, reverted, 
          valid_start_rid, valid_until_rid)
      VALUES 
         (branch_baseline_id, gm_stack_id, 1, NULL, FALSE, FALSE, 
          rid_beg, rid_inf);
      /* Get the newly minted system ID. */
      gm_system_id := CURRVAL('item_versioned_system_id_seq');

      INSERT INTO item_revisionless
         (branch_id, system_id, stack_id, version, acl_grouping,
          edited_date,
          edited_user,
          edited_note,
          edited_addr,
          edited_host,
          edited_what)
      VALUES 
         (branch_baseline_id, gm_system_id, gm_stack_id, 1, 1,
          NOW(),
          '_script', -- edited_user
          NULL, -- edited_note
          NULL, -- edited_addr
          NULL, -- edited_host
          NULL); -- edited_what

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

/* */

CREATE OR REPLACE FUNCTION cp_attribute_create(
      IN attr_name TEXT,
      IN attr_value_internal_name TEXT,
      IN attr_spf_field_name TEXT,
      IN attr_value_type TEXT,
      IN attr_value_hints TEXT,
      IN attr_value_units TEXT,
      IN attr_value_minimum INTEGER,
      IN attr_value_maximum INTEGER,
      IN attr_value_stepsize INTEGER,
      IN attr_gui_sortrank INTEGER,
      IN attr_applies_to_type_id INTEGER,
      IN attr_uses_custom_control BOOLEAN,
      IN attr_is_directional BOOLEAN)
   RETURNS VOID AS $$
   DECLARE
      branch_baseline_id INTEGER;
      attr_system_id INTEGER;
      attr_stack_id INTEGER;
      attr_version INTEGER;
   BEGIN
      branch_baseline_id := cp_branch_baseline_id();
      attr_version := 1;
      /* Populate item_stack. */
      INSERT INTO item_stack
         (access_style_id,
          access_infer_id)
         -- Skipping: stealth_secret, cloned_from_id
      VALUES
         (cp_access_style_id('all_denied'),
          cp_access_infer_id('pub_viewer'));
      attr_stack_id := CURRVAL('item_stack_stack_id_seq');
      /* Populate item_versioned. */
      /* NOTE Using start revision ID 1 since these attributes are inherent
              to the system, i.e., they've existed since the big bang. */
      INSERT INTO item_versioned
         (branch_id, stack_id, version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (branch_baseline_id, attr_stack_id, attr_version, attr_name,
          FALSE, FALSE, 1, cp_rid_inf());
      attr_system_id := CURRVAL('item_versioned_system_id_seq');
      /* Populate item_revisionless. */
      INSERT INTO item_revisionless
         (branch_id, system_id, stack_id, version, acl_grouping,
          edited_date,
          edited_user,
          edited_note,
          edited_addr,
          edited_host,
          edited_what)
      VALUES 
         (branch_baseline_id, attr_system_id, attr_stack_id, 1, 1,
          NOW(),
          '_script', -- edited_user
          NULL, -- edited_note
          NULL, -- edited_addr
          NULL, -- edited_host
          NULL); -- edited_what
      /* Populate attachment. */
      INSERT INTO attachment
            (system_id, branch_id, stack_id, version)
         VALUES
            (attr_system_id, branch_baseline_id, attr_stack_id, attr_version);
      /* Populate attribute. */
      INSERT INTO attribute (
            system_id,
            branch_id,
            stack_id,
            version,
            value_internal_name,
            spf_field_name,
            value_type,
            value_hints,
            value_units,
            value_minimum,
            value_maximum,
            value_stepsize,
            gui_sortrank,
            applies_to_type_id,
            uses_custom_control,
            value_restraints,
            multiple_allowed,
            is_directional)
         VALUES (
               attr_system_id,
               branch_baseline_id,
               attr_stack_id,
               attr_version,
               attr_value_internal_name,
               attr_spf_field_name,
               attr_value_type,
               attr_value_hints,
               attr_value_units,
               attr_value_minimum,
               attr_value_maximum,
               attr_value_stepsize,
               attr_gui_sortrank,
               attr_applies_to_type_id,
               attr_uses_custom_control,
               '',
               FALSE,
               FALSE);
      /* Grant access to attribute to public user group. */
      /* Ignoring columns: item_layer_id, link_lhs_type_id, link_rhs_type_id */
      INSERT INTO group_item_access
         (group_id,
          branch_id,
          item_id,
          stack_id,
          version,
          deleted,
          name,
          valid_start_rid,
          valid_until_rid,
          acl_grouping,
          access_level_id,
          item_type_id
         )
      VALUES
         (cp_group_public_id(),
          branch_baseline_id,
          attr_system_id,
          attr_stack_id,
          attr_version,
          FALSE,
          attr_name,
          1, -- the first revision
          cp_rid_inf(), -- the infinite revision
          1, -- the first acl_grouping
          cp_access_level_id('client'),
          cp_item_type_id('attribute')
         );
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

