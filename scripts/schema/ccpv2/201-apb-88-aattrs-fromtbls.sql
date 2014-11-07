/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script makes attributes for tables that should be attributized.

   */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script attributizes attributetic tables, like the
\qecho watcher table, the rating table, and the aadt table.
\qecho
\qecho This script also creates new attributes for CcpV2.
\qecho
\qecho 2013.05.10: Is it too late to add attributes for Statewide? ;_)
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho
\qecho Creating helper functions
\qecho

CREATE FUNCTION cp_attribute_create(
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
         (creator_name,
          access_style_id,
          access_infer_id)
      VALUES
         ('_script',
          cp_access_style_id('all_denied'),
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
/* Step (2) --                                                          */
/* ==================================================================== */

/* ==================================================== */
/* Miscellaneous Tables That Are Really Just Attributes */
/* ==================================================== */

/* NOTE: The two fcns., cp_attribute_create and attr_attachment_create, were
 *       created in an earlier script but were not deleted so that we could use
 *       them. */

/* FIXME: delete this once this script works as expected. */
/*
select stack_id, value_internal_name from attribute;
delete from attribute
   where stack_id in (2369557, 2369558, 2369559, 2369560, 2369561);
delete from attachment
   where stack_id in (2369557, 2369558, 2369559, 2369560, 2369561);
delete from item_versioned
   where stack_id in (2369557, 2369558, 2369559, 2369560, 2369561);
*/

\qecho
\qecho Making system attributes
\qecho

/* 2013.03.26: Finally commenting this out. [lb] cannot remember what he saw in
               having stack_id as at attribute, anyway....
\qecho ... Cyclopath ID
SELECT cp_attribute_create(
   'Cyclopath ID',
   '/item/stack_id',
   'ccp_id',
   'integer',
   'The internal, uneditable Cyclopath Stack ID.',
   '',            -- attr_value_units
   0,             -- attr_value_minimum
   0,             -- attr_value_maximum
   0,             -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   NULL,          -- applies_to_type_id
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional
-- FIXME: This is a "magic" attribute, and is uneditable. How do you accomplish
-- that? 2012.10.31: The idea is that this attribute maps to
-- item_versioned.stack_id, but what's the utility in that?
*/

/* FIXME: MAYBE: Implement this. */
/* 2013.03.26: The idea here is to replace the byway_rating table.
               We'd have to make private link_values, like
               /item/alert_email. But what do we gain from
               doing this? [lb] guesses merely consistency,
               as in, convert more data from unique implementations
               to being attribute link_values. But bikeability is
               already implemented, and it's pretty special, and all
               we'd get from converting it to an attribute and link_values
               is a waste of developer time.
\qecho ... Bikeability Rating
SELECT cp_attribute_create(
   'Bikeability Rating',
   '/byway/rating',
   'bke_rating',
   'integer',
   'Your personal opinion about how much you like riding this block.',
   'bikeability', -- attr_value_units
   -1,            -- attr_value_minimum
    4,            -- attr_value_maximum
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   (SELECT id FROM item_type WHERE type_name = 'byway'),
   TRUE,          -- attr_uses_custom_control
   TRUE);         -- attr_is_directional
*/

/* FIXME: MAYBE: Implement this. */
/* 2013.03.26: The reason to implement this attribute is similar to why we'd
               implement bikeability as an attribute (see previous comment).
               Also, we remove what [lb] feels is a little bit of a hack:
               post.polarity. Polarity represents a user's like or dislike
               of a route, but the value is captured in a column in the post
               table. [lb] feels that polarity would better be suited as an
               attribute. A benefit would be that user could then thumbs-up
               and thumbs-down any item type, and not just posts that have
               route links.
               NOTE: Leaving uncommented so devs see this in the database and
                     get curious... and maybe find there way to this comment.
               */
\qecho ... Post Thumber
SELECT cp_attribute_create(
   'Post Thumber',
   '/post/rating',
   'postrating',
   'integer',
   'Was this post good or helpful, or not?',
   'thumbs',      -- attr_value_units
   -1,            -- attr_value_minimum
    1,            -- attr_value_maximum
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   (SELECT id FROM item_type WHERE type_name = 'post'),
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* FIXME: MAYBE: Implement this. */
/* 2013.03.26: See previous comments about why we'd want to implement this. */
\qecho ... Route Thumber
SELECT cp_attribute_create(
   'Route Thumber',
   '/route/polarity',
   'rtpolarity',
   'integer',
   'Do you like or dislike this route?',
   'thumbs',      -- attr_value_units
   -1,            -- attr_value_minimum
    1,            -- attr_value_maximum
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   (SELECT id FROM item_type WHERE type_name = 'post'),
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* FIXME: MAYBE: Implement this. */
\qecho ... AADT
SELECT cp_attribute_create(
   'AADT',
   '/byway/aadt',
   'road_aadt',
   'integer',
   'Average Annual Daily Traffic.',
   'motor vehicles', -- attr_value_units
    0,               -- attr_value_minimum
    NULL,            -- attr_value_maximum
    1,               -- attr_value_stepsize
   NULL,             -- attr_gui_sortrank
   (SELECT id FROM item_type WHERE type_name = 'byway'),
   TRUE,             -- attr_uses_custom_control
   TRUE);            -- attr_is_directional

/* FIXME: MAYBE: Implement this. */
/* 2013.03.26: The idea here is to replace the route_tag_preference
               table. [lb] thinks this is less useful than implementing
               item polarity (or item liking) because it's already
               implemented and reimplementing as an attribute and link_values
               doesn't gain us anything.
\qecho ... Tag Preference
SELECT cp_attribute_create(
   'Tag Preference',
   '/tag/preference',
   'tag_pref',
   'integer',
   'Affects how byways with this tag are chosen when route-finding.',
   'preference',  -- attr_value_units
    0,            -- attr_value_minimum
    3,            -- attr_value_maximum
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   (SELECT id FROM item_type WHERE type_name = 'tag'),
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional
*/

/* 2013.03.26: [lb] finally figured out how to implement item watching (a/k/a
               item alerts). We can use one attribute for each alert type
               (where an alert type is email, sms, twitter, etc.), and we
               can use new_item_policy.link_left_stack_id = the attr's stack id
               and access_style = usr_editor to force new alert link_values
               to be private to the user. */

/* MAGIC_NUMBERS: The min/max values are based on an enumeration,
                  Watcher_Frequency, in item/util/watcher_frequency.py. */
\qecho ... Item Watcher Digest Frequency
SELECT cp_attribute_create(
   'Email Item Alert',
   '/item/alert_email',
   'alrt_email',
   'integer',
   'Whether to notify you when this item changes, and when to notify you.',
   'frequency',   -- attr_value_units
    0,            -- attr_value_minimum
   99,            -- attr_value_max., but we use a custom ctrl, so meaningless.
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   NULL,          -- applies_to_type_id
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional
/* BUG nnnn: MAYBE: Other alert types?
                    SMS, Twitter, Flashclient (new panel)? */

\qecho ... Item Reminder, a/k/a Ask Me Later
SELECT cp_attribute_create(
   'Ask Me Later',
   '/item/reminder_email',
   'rmndr_emal',
   'text',
   'Whether to notify you in the future to revisit this item.',
   'frequency',   -- attr_value_units
    0,            -- attr_value_minimum
   99,            -- attr_value_max., but we use a custom ctrl, so meaningless.
    1,            -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   NULL,          -- applies_to_type_id
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* 2013.05.10: Throughout CcpV2, bike facility was added as a new attribute as
   part of importing the Bikeways Shapefile (see: metc_bikeways_defs.py, which
   defines '/metc_bikeways/bike_facil'). But this means the attribute is only
   available to the Bikeways branch. Bah! It's too awesome not to add it to the
   basemap, too. */
\qecho ... Bicycle Facility
SELECT cp_attribute_create(
   'Bicycle Facility',
   '/byway/cycle_facil',
   'cyclefacil',
   'text',
   'The type of bicycle facility, if any, on this road segment.',
   '',            -- attr_value_units
   0,             -- attr_value_minimum
   0,             -- attr_value_maximum
   0,             -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   cp_item_type_id('byway'), -- applies_to_type_id
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* 2013.06.14: [lb] got the idea for the "cautionary" facilities from the
               Portland City bike map. But they're not a Bike Facility,
               says Loren. And [lb] agrees, but I wanted to simplify things
               (i.e., a single dropdown menu). But we really do want to capture
               this information separately from the facility (there could be
               both) and it won't be used that often so three extra mouse
               clicks is not a big concern (click checkbox to enable cautions,
               click once to activate the dropdown, then mouse and click to
               your desired caution). */
\qecho ... Bicycle Caution
SELECT cp_attribute_create(
   'Bicycle Caution',
   '/byway/cautionary',
   'cautionary',
   'text',
'The extra level of discretion that should be excerised on this road segment.',
   '',            -- attr_value_units
   0,             -- attr_value_minimum
   0,             -- attr_value_maximum
   0,             -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   cp_item_type_id('byway'), -- applies_to_type_id
   TRUE,          -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

\qecho ... Bicycle Route
SELECT cp_attribute_create(
   'Bicycle Route',
   '/byway/cycle_route',
   'cycleroute',
   'text',
   'The name(s) of the Bicycle Routes on this road.',
   '',            -- attr_value_units
   0,             -- attr_value_minimum
   0,             -- attr_value_maximum
   0,             -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   cp_item_type_id('byway'), -- applies_to_type_id
   --FALSE,         -- attr_uses_custom_control
   --TRUE,          -- FIXME: Until implemented, don't show.
   -- 2013.08.08: Well, MetC really wants something exactly like this...
   FALSE,         -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* 2013.05.11: Statewide: MnDOT is adding "controlled access" bool to their
               TDS (TDI?) bike data. */
\qecho ... Bicycle Route
SELECT cp_attribute_create(
   'Controlled Access',
   '/byway/no_access',
   'no_access',
   'boolean',
   'Indicates controlled-access roadways.',
   '',            -- attr_value_units
   0,             -- attr_value_minimum
   0,             -- attr_value_maximum
   0,             -- attr_value_stepsize
   NULL,          -- attr_gui_sortrank
   cp_item_type_id('byway'), -- applies_to_type_id
   --FALSE,         -- attr_uses_custom_control
   --TRUE,          -- FIXME: Until implemented, don't show.
   -- 2013.08.08: Well, this seems like a good way to test Boolean
   FALSE,         -- attr_uses_custom_control
   FALSE);        -- attr_is_directional

/* =========== */
/* CLEANUP     */
/* =========== */

/* 2013.06.07: Should we keep this fcn? */
/*
DROP FUNCTION cp_attribute_create(
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
   IN attr_is_directional BOOLEAN);
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;

