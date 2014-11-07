/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script recreates constraints, indexes, and foreign keys that were
   previously dropped to improve SQL performance during the V2 upgrade. */

/*

   Usage:

    psql -U cycling ccpv3_test \
      < /ccp/dev/cp/scripts/setupcp/db_load_add_constraints.sql

   Maybe also:

   cd /ccp/dev/cp/scripts
   ./vacuum.sh

   */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

/* PERFORMACE  In the early days of V2 development, the 102-apb-* scripts took
 *       NOTE  hours to run -- 3 at first, then 8, and finally 24. That's when
 *             I [lb] got fed up and took time away from pyserver and
 *             flashclient to fix the database. The solution: when marshalling
 *             tons of data around, it's best to drop all constraints, foreign
 *             keys, and indexes. Keep just primary keys. Then re-create the
 *             constraints, foreign keys, and indexes after you've marshalled
 *             all your data. On 2011.04.25, the result was that the update
 *             scripts ran in just 80 minutes!
 */

/* FIXME: I still need to audit this file...
          I.e., run psql and \d every table and compare against this file... */

/* NOTE: This script is meant to be generic and reusable against the V2
 *      database.
 */

/* 2012.09.18: There are still TRIGGERs and CONSTRAINTs missing... and
 * some tables, too... */

/*
 * BUG 2406: Create complimentary "drop constraint" SQL script.
 *           Make convenience shell script to run either.
 *           Also to run db anonymizer.
 */

/* FIXME: Add this file -- or schema-upgrade -- to proj plan. */

/* NOTE: Not doing primary keys herein. */

\qecho
\qecho This script recreates constraints, indexes, and foreign keys that were
\qecho previously dropped to improve SQL performance during the V2 upgrade.
\qecho
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ x mins. (on complete database).]
\qecho
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 3.03 mins. (on anonymized database).]
\qecho
\qecho [EXEC. TIME: 2012.02.10/Pluto: Still just a few minutes....]
\qecho

-- FIXME: Run the 999 scripts before this script?? Or wrap the 999 scripts?

/* FIXME: Compare V1 vs. V2, table-for-table, and double-check indices,
 *        constraints, foreign keys. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* FIXME: This script started in the schema/ folder but has since matured.
            The easiest way (besides not caring) to set the INSTANCE is to
            wrap this script with a Ccp cli script.
          Also, by make a python wrapper, you can better debug this script.
            Indexing takes a while, so it sucks to hit errors late in the game.
            (For now, you can copy the SQL and just delete the code toward the
             top that works all the way down to where the error is, to easily
             test.)
          You know what would be ideal? Have the item classes make their
            own constraints.
          */
--SET search_path TO @@@instance@@@, public;
--SET search_path TO minnesota, public;
-- FIXME: Can you ensure that this script runs from psql_wrap? Or will it just
-- fail if INSTANCE isn't set?

/* ==================================================================== */
/* ==================================================================== */
/* Step (1) -- Disable NOTICEs                                          */
/* ==================================================================== */

/* We add a bunch of primary keys, each of which triggers the Psql notice:

      NOTICE: ALTER TABLE / ADD PRIMARY KEY will create implicit index
              "blah_pkey" for table "blah"

      */

\qecho
\qecho Disabling NOTICEs to avoid noise
\qecho

SET client_min_messages = 'warning';

/* ======================================================================== */
/* ======================================================================== */
/* Step (2) -- Public schema support tables                                 */
/* ======================================================================== */

/* FIXME: Add missing public tables to this script. */

/* ======================================================================== */
/* enum_definition                                                          */
/* ======================================================================== */

DROP INDEX IF EXISTS enum_definition_enum_name;
CREATE INDEX enum_definition_enum_name
   ON public.enum_definition (enum_name);

DROP INDEX IF EXISTS enum_definition_enum_name_enum_key;
CREATE INDEX enum_definition_enum_name_enum_key
   ON public.enum_definition (enum_name, enum_key);
   /* For the reverse, i.e., looking up by name to get the id: */
DROP INDEX IF EXISTS enum_definition_enum_name_enum_value;
CREATE INDEX enum_definition_enum_name_enum_value
   ON public.enum_definition (enum_name, enum_value);

ALTER TABLE enum_definition ENABLE TRIGGER enum_definition_i;
ALTER TABLE enum_definition ENABLE TRIGGER enum_definition_u;

/* ======================================================================== */
/* ======================================================================== */
/* Step (3) -- User tables                                                  */
/* ======================================================================== */

/* FIXME: 2013.09.30: Just add user_ table but others still missing... */

/* MAYBE: Like, user_preference_event table, and others? */

/* ======================================================================== */
/* user_                                                                    */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to user_.
\qecho

SELECT cp_constraint_drop_safe('user_', 'user__alias_key');
ALTER TABLE public.user_ ADD CONSTRAINT user__alias_key UNIQUE (alias);

SELECT cp_constraint_drop_safe('user_', 'user__id_key');
ALTER TABLE public.user_ ADD CONSTRAINT user__id_key UNIQUE (id);

DROP INDEX IF EXISTS user__username_unique_caseinsensitive;
CREATE INDEX user__username_unique_caseinsensitive
   ON public.user_ (LOWER(username));

DROP INDEX IF EXISTS user__unsubscribe_proof_i;
CREATE INDEX user__unsubscribe_proof_i ON public.user_ (unsubscribe_proof);

SELECT cp_constraint_drop_safe('user_', 'user__unsubscribe_proof_u');
ALTER TABLE public.user_ ADD CONSTRAINT user__unsubscribe_proof_u
   UNIQUE (unsubscribe_proof);

/* ======================================================================== */
/* user__token                                                              */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to user__token.
\qecho

SELECT cp_constraint_drop_safe('public.user__token',
                               'user__token_username_fkey');
ALTER TABLE public.user__token
   ADD CONSTRAINT user__token_username_fkey
      FOREIGN KEY (username) REFERENCES public.user_ (username) DEFERRABLE;

SELECT cp_constraint_drop_safe('public.user__token',
                               'user__token_user_id_fkey');
ALTER TABLE public.user__token
   ADD CONSTRAINT user__token_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.user_ (id) DEFERRABLE;

DROP INDEX IF EXISTS user__token_username;
CREATE INDEX user__token_username ON public.user__token (username);

DROP INDEX IF EXISTS user__token_user_id;
CREATE INDEX user__token_user_id ON public.user__token (user_id);

DROP INDEX IF EXISTS user__token_date_expired;
CREATE INDEX user__token_date_expired ON public.user__token (date_expired);

/* ======================================================================== */
/* alias_source                                                             */
/* ======================================================================== */

/* FIXME: This is a public schema table -- but this script is instance
          specific! So we're just wasting time doing this twice... */

SELECT cp_constraint_drop_safe('alias_source',
   'alias_source_unique_text');
ALTER TABLE public.alias_source
   ADD CONSTRAINT alias_source_unique_text
      UNIQUE (text);

/* ======================================================================== */
/* ======================================================================== */
/* Step (4) -- Item versioned tables: shared constraints                    */
/* ======================================================================== */

\qecho
\qecho Creating helper fcns.
\qecho

/* */

DROP FUNCTION IF EXISTS item_table_system_id_add_constraints(
                              IN table_name TEXT,
                              IN parent_name TEXT);
DROP FUNCTION IF EXISTS index_drop_n_add(
                              IN table_name TEXT,
                              IN columns TEXT,
                              IN constraint_name TEXT);
DROP FUNCTION IF EXISTS constraint_drop_n_add(
                              IN table_name TEXT,
                              IN constraint_name TEXT,
                              IN the_constraint TEXT);
CREATE FUNCTION constraint_drop_n_add(IN table_name TEXT,
                                      IN constraint_name TEXT,
                                      IN the_constraint TEXT)
   RETURNS VOID AS $$
   BEGIN
      PERFORM cp_constraint_drop_safe(table_name, constraint_name);
      EXECUTE 'ALTER TABLE ' || table_name || '
                  ADD CONSTRAINT ' || constraint_name ||
                  ' ' || the_constraint || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION index_drop_n_add(IN table_name TEXT,
                                 IN columns TEXT,
                                 IN constraint_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      constraint_name TEXT;
   BEGIN
      constraint_name := table_name || '_' || columns;
      EXECUTE 'DROP INDEX IF EXISTS ' || constraint_name || ';';
      EXECUTE 'CREATE INDEX ' || constraint_name ||
               ' ON ' || table_name || ' (' || columns || ');';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* */

CREATE FUNCTION item_table_system_id_add_constraints(
      IN table_name TEXT, IN parent_name TEXT)
   RETURNS VOID AS $$
   BEGIN

      /* FIXME: These two UNIQUEs seem equal to one another.... */
      PERFORM constraint_drop_n_add(
         table_name,
         table_name || '_unique_branch_id_system_id',
         'UNIQUE (branch_id, system_id)');
      /* */
      PERFORM constraint_drop_n_add(
         table_name,
         table_name || '_unique_branch_id_stack_id_version',
         'UNIQUE (branch_id, stack_id, version)');
      /* FIXME: Seems weird: */
      PERFORM constraint_drop_n_add(
         table_name,
         table_name || '_unique_system_id_branch_id_stack_id_version',
         'UNIQUE (system_id, branch_id, stack_id, version)');

      /* INDEX what's not in PRIMARY KEY. */
      PERFORM index_drop_n_add(table_name, 'branch_id',
                               table_name || '_branch_id');
      PERFORM index_drop_n_add(table_name, 'stack_id',
                               table_name || '_stack_id');
      PERFORM index_drop_n_add(table_name, 'version',
                               table_name || '_version');

      /* If the table represents a derived class (all of the item tables
       * except for item_versioned), foreign-key the parent table. */
      IF parent_name != '' THEN
         PERFORM constraint_drop_n_add(
            table_name, table_name || '_system_id_fkey',
            'FOREIGN KEY (system_id) REFERENCES '
               || parent_name || ' (system_id) DEFERRABLE');
         /* FIXME: Do I need 0, 1, 2, or 3 of the following? */
         PERFORM constraint_drop_n_add(
            table_name, table_name || '_branch_id_system_id_fkey',
            'FOREIGN KEY (branch_id, system_id) REFERENCES '
               || parent_name || ' (branch_id, system_id) DEFERRABLE');
         PERFORM constraint_drop_n_add(
            table_name, table_name || '_branch_id_stack_id_version_fkey',
            'FOREIGN KEY (branch_id, stack_id, version) REFERENCES '
               || parent_name || ' (branch_id, stack_id, version) '
               || 'DEFERRABLE');
         PERFORM constraint_drop_n_add(
            table_name, table_name ||
               '_system_id_branch_id_stack_id_version_fkey',
            'FOREIGN KEY (system_id, branch_id, stack_id, version) REFERENCES '
               || parent_name || ' (system_id, branch_id, stack_id, version) '
               || 'DEFERRABLE');
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho
\qecho Adding constraints on Item_Versioned and derived tables
\qecho

/* Base table */
\qecho ...item_versioned
SELECT item_table_system_id_add_constraints('item_versioned', '');

/* Intermediate tables */
\qecho ...attachment
SELECT item_table_system_id_add_constraints('attachment', 'item_versioned');
\qecho ...geofeature
SELECT item_table_system_id_add_constraints('geofeature', 'item_versioned');
\qecho ...link_value
SELECT item_table_system_id_add_constraints('link_value', 'item_versioned');

/* Attachment tables */
\qecho ...tag
SELECT item_table_system_id_add_constraints('tag',        'attachment');
\qecho ...annotation
SELECT item_table_system_id_add_constraints('annotation', 'attachment');
\qecho ...thread
SELECT item_table_system_id_add_constraints('thread',     'attachment');
\qecho ...post
SELECT item_table_system_id_add_constraints('post',       'attachment');
\qecho ...attribute
SELECT item_table_system_id_add_constraints('attribute',  'attachment');
/* Geofeature tables */
\qecho ...route
SELECT item_table_system_id_add_constraints('route',      'geofeature');
\qecho ...track
SELECT item_table_system_id_add_constraints('track',      'geofeature');

/* Nonwiki Item tables */
\qecho ...work_item
SELECT item_table_system_id_add_constraints('work_item', 'item_versioned');
\qecho ...merge_job
SELECT item_table_system_id_add_constraints('merge_job', 'item_versioned');
-- \qecho ...__deprecated__item_watcher
-- SELECT item_table_system_id_add_constraints('__deprecated__item_watcher',
--                                             'item_versioned');

/* Permissionless tables */
\qecho ...node_endpoint
SELECT item_table_system_id_add_constraints('node_endpoint', 'item_versioned');
\qecho ...node_traverse
SELECT item_table_system_id_add_constraints('node_traverse', 'item_versioned');

/* ======================================================================== */
/* ======================================================================== */
/* Step (5) -- Item versioned tables: table-specific constraints            */
/* ======================================================================== */

/* ================================== */
/* *** Items: Base tables             */
/* ================================== */

/* ======================================================================== */
/* item_stack                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to item_stack.
\qecho

SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_creator_name_fkey');
/* creator_name is now a calculated value.
ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_creator_name_fkey
   FOREIGN KEY (creator_name) REFERENCES user_ (username) DEFERRABLE;
*/

SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_stealth_secret_unique');
ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_stealth_secret_unique
   UNIQUE (stealth_secret);

SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_cloned_from_id_fkey');
ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_cloned_from_id_fkey
   FOREIGN KEY (cloned_from_id) REFERENCES item_versioned (system_id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_access_style_fkey');
SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_access_style_id_fkey');
ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_access_style_id_fkey
   FOREIGN KEY (access_style_id)
      REFERENCES public.access_style (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_access_infer_fkey');
SELECT cp_constraint_drop_safe('item_stack',
                               'item_stack_access_infer_id_fkey');
/* access_infer_id is a bitmask, so it doesn't make sense to use an fkey.
ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_access_infer_id_fkey
   FOREIGN KEY (access_infer_id)
      REFERENCES public.access_infer (id) DEFERRABLE;
*/

/* */
DROP INDEX IF EXISTS item_stack_creator_name;
/* creator_name is now a calculated value.
CREATE INDEX item_stack_creator_name ON item_stack (creator_name);
*/

/* */
DROP INDEX IF EXISTS item_stack_stealth_secret;
CREATE INDEX item_stack_stealth_secret ON item_stack (stealth_secret);

/* ======================================================================== */
/* item_versioned                                                           */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to item_versioned.
\qecho

\qecho ...item_versioned_stack_id_fkey
SELECT cp_constraint_drop_safe('item_versioned',
                               'item_versioned_stack_id_fkey');
/* 2013.06.14: The node_endpoint items share the same stack_id for the 
               same x,y vertex but are unique to each branch, so we don't
               use item_stack. So we can't have this constraint, so a
               node_endpoint stack_id can be found in item_versioned
               but not item_stack....
ALTER TABLE item_versioned
   ADD CONSTRAINT item_versioned_stack_id_fkey
      FOREIGN KEY (stack_id) REFERENCES item_stack (stack_id) DEFERRABLE;
*/

\qecho ...item_versioned_valid_start_rid_fkey
SELECT cp_constraint_drop_safe('item_versioned',
                               'item_versioned_valid_start_rid_fkey');
ALTER TABLE item_versioned
   ADD CONSTRAINT item_versioned_valid_start_rid_fkey
      FOREIGN KEY (valid_start_rid) REFERENCES revision (id) DEFERRABLE;

\qecho ...item_versioned_valid_until_rid_fkey
SELECT cp_constraint_drop_safe('item_versioned',
                               'item_versioned_valid_until_rid_fkey');
ALTER TABLE item_versioned
   ADD CONSTRAINT item_versioned_valid_until_rid_fkey
      FOREIGN KEY (valid_until_rid) REFERENCES revision (id) DEFERRABLE;

/* NOTE In the existing Db, enforce_version checks >= 1, but we relax that
        by one to accommodate watch_region; we defer to auditor.sql to make
        sure only watch_regions use version = 0.
2011.04.24: This is still the case.
FIXME: Clean up versioned-0 items.
*/
--ALTER TABLE item_versioned
--   ADD CONSTRAINT enforce_version CHECK (version > 0);
\qecho ...enforce_version
SELECT cp_constraint_drop_safe('item_versioned', 'enforce_version');
ALTER TABLE item_versioned
   ADD CONSTRAINT enforce_version CHECK (version >= 0);

/* 2013.06.02: We're using private attribute link_values now for item_watchers
   and these don't cause a new revision to be created, but they do create new
   versions of items. This is safe because of how we use distinct and order by
   version desc when we fetch items. */
/* */
\qecho ...enforce_unique_start_rid
/* 2013.06.02: Not anymore:
ALTER TABLE item_versioned
   ADD CONSTRAINT enforce_unique_start_rid
      UNIQUE (branch_id, stack_id, valid_start_rid); */
SELECT cp_constraint_drop_safe('item_versioned', 'enforce_unique_start_rid');
/* */
\qecho ...enforce_unique_until_rid
SELECT cp_constraint_drop_safe('item_versioned', 'enforce_unique_until_rid');
/* 2013.06.02: Not anymore:
      ALTER TABLE item_versioned
   ADD CONSTRAINT enforce_unique_until_rid
      UNIQUE (branch_id, stack_id, valid_until_rid); */

\qecho ...enforce_start_less_than_until_rid
SELECT cp_constraint_drop_safe('item_versioned',
            'enforce_start_less_than_until_rid');
ALTER TABLE item_versioned
   ADD CONSTRAINT enforce_start_less_than_until_rid
      CHECK (valid_start_rid <= valid_until_rid);

\qecho ...enforce_version_positive_non_negative
SELECT cp_constraint_drop_safe('item_versioned',
            'enforce_version_positive_non_negative');
ALTER TABLE item_versioned
   ADD CONSTRAINT enforce_version_positive_non_negative
      CHECK (version > 0);

/* FIXME: Should we use a predicate to just index where deleted IS FALSE? */
\qecho ...item_versioned_deleted
DROP INDEX IF EXISTS item_versioned_deleted;
CREATE INDEX item_versioned_deleted ON item_versioned (deleted);

/* Index name so user's can search items quickly by name. (NOTE: I'm [lb] not
 * convinced this is so: according to the Postgres docs, at
 *   http://www.postgresql.org/docs/8.3/static/indexes-types.html
 * indexing text only works if the query is LIKE 'foo%' and _not_ LIKE '%foo'.
 */
\qecho ...item_versioned_name
DROP INDEX IF EXISTS item_versioned_name;
CREATE INDEX item_versioned_name ON item_versioned (name);

/* FIXME: How do I figure out if I should use two, singular indices, or just
 *        one, mulitple index? */
\qecho ...item_versioned_valid_start_rid
DROP INDEX IF EXISTS item_versioned_valid_start_rid;
CREATE INDEX item_versioned_valid_start_rid
   ON item_versioned (valid_start_rid);
/* */
\qecho ...item_versioned_valid_until_rid
DROP INDEX IF EXISTS item_versioned_valid_until_rid;
CREATE INDEX item_versioned_valid_until_rid
   ON item_versioned (valid_until_rid);
/* Make a multi-column index to speed up revision ID searches. */
\qecho ...item_versioned_rids
DROP INDEX IF EXISTS item_versioned_rids;
CREATE INDEX item_versioned_rids
   ON item_versioned (valid_start_rid, valid_until_rid);

/* ======================================================================== */
/* item_revisionless                                                        */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to item_revisionless.
\qecho

/* */

/*
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_pkey
   PRIMARY KEY (system_id, acl_grouping);
*/

/* */

\qecho ...item_revisionless_system_id_fkey
SELECT cp_constraint_drop_safe('item_revisionless',
                               'item_revisionless_system_id_fkey');
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_system_id_fkey
      FOREIGN KEY (system_id) REFERENCES item_versioned (system_id) DEFERRABLE;

/* */

\qecho ...item_revisionless_other_ids_fkey
SELECT cp_constraint_drop_safe('item_revisionless',
                               'item_revisionless_other_ids_fkey');
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_other_ids_fkey
      FOREIGN KEY (branch_id, stack_id, version)
      REFERENCES item_versioned (branch_id, stack_id, version) DEFERRABLE;

/* */

\qecho ...item_revisionless_creator_fkey
SELECT cp_constraint_drop_safe('item_revisionless',
                               'item_revisionless_creator_fkey');
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_creator_fkey
   FOREIGN KEY (edited_user) REFERENCES user_ (username) DEFERRABLE;

/* */

\qecho ...item_revisionless_unique_branch_stack_version_acl
SELECT cp_constraint_drop_safe('item_revisionless',
         'item_revisionless_unique_branch_stack_version_acl');
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_unique_branch_stack_version_acl
      UNIQUE (branch_id, stack_id, version, acl_grouping);

/* */

\qecho ...enforce_acl_grouping
SELECT cp_constraint_drop_safe('item_revisionless', 'enforce_acl_grouping');
ALTER TABLE item_revisionless
   ADD CONSTRAINT enforce_acl_grouping CHECK (acl_grouping > 0);

\qecho ...enforce_version_positive_non_negative
SELECT cp_constraint_drop_safe('item_revisionless',
            'enforce_version_positive_non_negative');
ALTER TABLE item_revisionless
   ADD CONSTRAINT enforce_version_positive_non_negative
      CHECK (version > 0);

/* ======================================================================== */
/* branch                                                                   */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to branch.
\qecho

/* FIXME: Should this reference geofeature? Ummm... no...?
 *        Also, not fkeying on stack_id and/or version... */
SELECT cp_constraint_drop_safe('branch', 'branch_system_id_fkey');
ALTER TABLE branch
   ADD CONSTRAINT branch_system_id_fkey
      FOREIGN KEY (system_id) REFERENCES item_versioned (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('branch', 'branch_last_merge_rid_fkey');
ALTER TABLE branch
   ADD CONSTRAINT branch_last_merge_rid_fkey
      FOREIGN KEY (last_merge_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('branch', 'branch_unique_stack_version');
ALTER TABLE branch
   ADD CONSTRAINT branch_unique_stack_version
      UNIQUE (stack_id, version);

/* */
DROP INDEX IF EXISTS branch_stack_id;
CREATE INDEX branch_stack_id ON branch (stack_id);
/* */
DROP INDEX IF EXISTS branch_version;
CREATE INDEX branch_version ON branch (version);
/* */
DROP INDEX IF EXISTS branch_parent_id;
CREATE INDEX branch_parent_id ON branch (parent_id);
/* Skipping: last_merge_rid, conflicts_resolved, import_callback */

/* ================================== */
/* *** Items: Intermediate tables     */
/* ================================== */

/* ======================================================================== */
/* attachment                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to attachment.
\qecho

\qecho ...enforce_version_positive_non_negative
SELECT cp_constraint_drop_safe('attachment',
            'enforce_version_positive_non_negative');
ALTER TABLE attachment
   ADD CONSTRAINT enforce_version_positive_non_negative
      CHECK (version > 0);

/* ======================================================================== */
/* geofeature                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to geofeature.
\qecho

SELECT cp_constraint_drop_safe('geofeature',
      'geofeature_geofeature_layer_id_fkey');
ALTER TABLE geofeature
   ADD CONSTRAINT geofeature_geofeature_layer_id_fkey
      FOREIGN KEY (geofeature_layer_id) REFERENCES public.geofeature_layer (id)
      DEFERRABLE;

/* NOTE See auditor.sql for more "constraints". */

/* Not indexing: z. */
DROP INDEX IF EXISTS geofeature_geofeature_layer_id;
CREATE INDEX geofeature_geofeature_layer_id
   ON geofeature (geofeature_layer_id);
/* FIXME: Do I need these indices? */
DROP INDEX IF EXISTS geofeature_beg_node_id;
CREATE INDEX geofeature_beg_node_id ON geofeature (beg_node_id);
/* */
DROP INDEX IF EXISTS geofeature_fin_node_id;
CREATE INDEX geofeature_fin_node_id ON geofeature (fin_node_id);
/* */
DROP INDEX IF EXISTS geofeature_split_from_stack_id;
CREATE INDEX geofeature_split_from_stack_id
   ON geofeature (split_from_stack_id);

DROP INDEX IF EXISTS geofeature_is_disconnected;
CREATE INDEX geofeature_is_disconnected
   ON geofeature (is_disconnected);

/* Check that the geometry, if a byway, isn't really a point. */
SELECT cp_constraint_drop_safe('geofeature', 'enforce_valid_loop');
ALTER TABLE geofeature ADD CONSTRAINT enforce_valid_loop
   CHECK (NOT (    (beg_node_id <> 0)
               AND (fin_node_id <> 0)
               AND (beg_node_id = fin_node_id)
               AND (distance(startpoint(geometry), endpoint(geometry))
                    > (0.001::double precision))));

/* Check byway-specific columns. */

SELECT cp_constraint_drop_safe('geofeature', 'enforce_one_way');
ALTER TABLE geofeature ADD CONSTRAINT enforce_one_way
   CHECK ((one_way = -1) OR (one_way = 0) OR (one_way = 1));

\qecho
\qecho Creating index on geofeature.geometry
\qecho

/* For fast lookup, build spatial index using Gist (GeneralIzed Search Tree) */

/* Make sure the geometry is valid */
SELECT cp_constraint_drop_safe('geofeature', 'enforce_valid_geometry');
ALTER TABLE geofeature ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(geometry));

\qecho ...enforce_version_positive_non_negative
SELECT cp_constraint_drop_safe('geofeature',
            'enforce_version_positive_non_negative');
ALTER TABLE geofeature
   ADD CONSTRAINT enforce_version_positive_non_negative
      CHECK (version > 0);

DROP INDEX IF EXISTS geofeature_geometry;
-- This is the PostGIS 1.x way:
-- CREATE INDEX geofeature_geometry ON geofeature
--    USING GIST (geometry GIST_GEOMETRY_OPS);
CREATE INDEX geofeature_geometry ON geofeature
   USING GIST (geometry);

/* ======================================================================== */
/* link_value                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to link_value.
\qecho

/* */
DROP INDEX IF EXISTS link_value_lhs_stack_id;
CREATE INDEX link_value_lhs_stack_id ON link_value (lhs_stack_id);
/* */
DROP INDEX IF EXISTS link_value_rhs_stack_id;
CREATE INDEX link_value_rhs_stack_id ON link_value (rhs_stack_id);
/* FIXME: Index the value_*s? */
DROP INDEX IF EXISTS link_value_value_boolean;
CREATE INDEX link_value_value_boolean ON link_value (value_boolean);
/* */
DROP INDEX IF EXISTS link_value_value_integer;
CREATE INDEX link_value_value_integer ON link_value (value_integer);
/* FIXME: Index value_real/text/binary/date ? */

SELECT cp_constraint_drop_safe('link_value', 'enforce_lhs_and_rhs_stack_ids');
ALTER TABLE link_value ADD CONSTRAINT enforce_lhs_and_rhs_stack_ids
   CHECK ((lhs_stack_id > 0) AND (rhs_stack_id > 0));

/* See 202-full_text_search-index.sql for full text search SQL. */

/* ================================== */
/* *** Items: Attachment tables       */
/* ================================== */

/* ======================================================================== */
/* tag                                                                      */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to tag.
\qecho

/* No-op. */

/* ======================================================================== */
/* annotation                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to annotation.
\qecho

/* No-op. */

/* FIXME: Index 'comments' for Search? */

/* ======================================================================== */
/* thread                                                                   */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to thread.
\qecho

DROP INDEX IF EXISTS thread_ttype;
CREATE INDEX thread_ttype ON thread (ttype);

DROP INDEX IF EXISTS thread_thread_type_id;
CREATE INDEX thread_thread_type_id ON thread (thread_type_id);

/* No-op. */

/* ======================================================================== */
/* post                                                                     */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to post.
\qecho

/* */
DROP INDEX IF EXISTS post_thread_stack_id;
CREATE INDEX post_thread_stack_id ON post (thread_stack_id);

/* MAYBE: Do we need to index polarity? Only if we're grouping on it to
 *        count 'em.... */
DROP INDEX IF EXISTS post_polarity;
CREATE INDEX post_polarity ON post (polarity);

/* FIXME: Index 'body' for Search? */

/* ======================================================================== */
/* attribute                                                                */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to attribute.
\qecho

SELECT cp_constraint_drop_safe('attribute',
         'attribute_applies_to_type_id_fkey');
ALTER TABLE attribute
   ADD CONSTRAINT attribute_applies_to_type_id_fkey
   FOREIGN KEY (applies_to_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

/* Postgres 8.3 does not support ENUMs, but we can still accomplish the same
 * with a simple CHECK ... IN. */
SELECT cp_constraint_drop_safe('attribute', 'enforce_value_type');
ALTER TABLE attribute ADD CONSTRAINT enforce_value_type
   CHECK (
      value_type IN ('boolean', 'integer', 'real', 'text', 'binary', 'date'));

/* */
DROP INDEX IF EXISTS attribute_value_internal_name;
CREATE INDEX attribute_value_internal_name ON attribute (value_internal_name);
/* */
DROP INDEX IF EXISTS attribute_applies_to_type_id;
CREATE INDEX attribute_applies_to_type_id ON attribute (applies_to_type_id);

/* ================================== */
/* *** Items: Geofeature tables       */
/* ================================== */

/* ======================================================================== */
/* route                                                                    */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route.
\qecho

\qecho ... re-enabling trigger(s)

/* Moved to item_revisionless:
    ALTER TABLE route ENABLE TRIGGER route_ic;
*/
ALTER TABLE route ENABLE TRIGGER route_tsvect_details_trig;

\qecho ... route analysis node endpoint helpers

/* We shouldn't need to index the step counts, since we don't on them.

DROP INDEX IF EXISTS route_rsn_max;
CREATE INDEX route_rsn_max ON route(rsn_max);

DROP INDEX IF EXISTS route_rsn_max;
CREATE INDEX route_rsn_max ON route(rsn_max);

DROP INDEX IF EXISTS route_n_steps;
CREATE INDEX route_n_steps ON route(n_steps);

*/

DROP INDEX IF EXISTS route_beg_nid;
CREATE INDEX route_beg_nid ON route(beg_nid);

DROP INDEX IF EXISTS route_fin_nid;
CREATE INDEX route_fin_nid ON route(fin_nid);

SELECT cp_constraint_drop_safe('route', 'route_travel_mode_fkey');
ALTER TABLE route
   ADD CONSTRAINT route_travel_mode_fkey
      FOREIGN KEY (travel_mode) REFERENCES travel_mode(id) DEFERRABLE;

/*
DROP INDEX IF EXISTS route_tsvect_details;
CREATE INDEX route_tsvect_details 
   ON route USING gin(tsvect_details);
ALTER TABLE route ENABLE TRIGGER route_tsvect_details_trig;
*/

/*
    "route_unique_branch_id_stack_id_version" UNIQUE, btree (branch_id, stack_id, version)
    "route_unique_branch_id_system_id" UNIQUE, btree (branch_id, system_id)
    "route_unique_system_id_branch_id_stack_id_version" UNIQUE, btree (system_id, branch_id, stack_id, version)
    "route_beg_nid" btree (beg_nid)
    "route_branch_id" btree (branch_id)
    "route_fin_nid" btree (fin_nid)
    "route_stack_id" btree (stack_id)
    "route_tsvect_details" gin (tsvect_details)
    "route_version" btree (version)
*/

/* ======================================================================== */
/* track                                                                    */
/* ======================================================================== */

-- Nada.

/* ================================== */
/* *** Items: Nonwiki item tables     */
/* ================================== */

/* See below for: work_item, merge_job, and item_watcher. */

/* ================================== */
/* *** Items: Permissionless tables   */
/* ================================== */

/* See below for: node_endpoint, and node_traverse. */

/* ======================================================================== */
/* Step (6) --  Group tables                                                */
/* ======================================================================== */

/* ======================================================================== */
/* group_                                                                   */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to group_.
\qecho

SELECT cp_constraint_drop_safe('group_',
   'group__branch_id_stack_id_version_key');
ALTER TABLE group_
   ADD CONSTRAINT group__branch_id_stack_id_version_key
   UNIQUE (branch_id, stack_id, version);

SELECT cp_constraint_drop_safe('group_', 'group__system_id_fkey');
ALTER TABLE group_
   ADD CONSTRAINT group__system_id_fkey
   FOREIGN KEY (system_id) REFERENCES item_versioned (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_',
   'group__branch_id_stack_id_version_fkey');
ALTER TABLE group_
   ADD CONSTRAINT group__branch_id_stack_id_version_fkey
   FOREIGN KEY (branch_id, stack_id, version)
      REFERENCES item_versioned (branch_id, stack_id, version) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_', 'group__access_scope_id_fkey');
ALTER TABLE group_
   ADD CONSTRAINT group__access_scope_id_fkey
   FOREIGN KEY (access_scope_id) REFERENCES public.access_scope (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('group_', 'group__valid_start_rid_fkey');
ALTER TABLE group_
   ADD CONSTRAINT group__valid_start_rid_fkey
   FOREIGN KEY (valid_start_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_', 'group__valid_until_rid_fkey');
ALTER TABLE group_
   ADD CONSTRAINT group__valid_until_rid_fkey
   FOREIGN KEY (valid_until_rid) REFERENCES revision (id) DEFERRABLE;

/* */
DROP INDEX IF EXISTS group__branch_id;
CREATE INDEX group__branch_id ON group_ (branch_id);
/* */
DROP INDEX IF EXISTS group__stack_id;
CREATE INDEX group__stack_id ON group_ (stack_id);
/* */
DROP INDEX IF EXISTS group__version;
CREATE INDEX group__version ON group_ (version);
/* */
DROP INDEX IF EXISTS group__deleted;
CREATE INDEX group__deleted ON group_ (deleted);
/* */
DROP INDEX IF EXISTS group__valid_start_rid;
CREATE INDEX group__valid_start_rid ON group_ (valid_start_rid);
/* */
DROP INDEX IF EXISTS group__valid_until_rid;
CREATE INDEX group__valid_until_rid ON group_ (valid_until_rid);
/* */
DROP INDEX IF EXISTS group__access_scope_id;
CREATE INDEX group__access_scope_id ON group_ (access_scope_id);

/* Make a multi-column index to speed up revision ID searches. */
DROP INDEX IF EXISTS group__rids;
CREATE INDEX group__rids ON group_ (valid_start_rid, valid_until_rid);

/* ======================================================================== */
/* group_membership                                                         */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to group_membership.
\qecho

SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_branch_id_stack_id_version_key');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_branch_id_stack_id_version_key
   UNIQUE (branch_id, stack_id, version);

SELECT cp_constraint_drop_safe('group_membership',
                  'group_membership_system_id_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_system_id_fkey
   FOREIGN KEY (system_id) REFERENCES item_versioned (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_branch_id_stack_id_version_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_branch_id_stack_id_version_fkey
   FOREIGN KEY (branch_id, stack_id, version)
      REFERENCES item_versioned (branch_id, stack_id, version) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_valid_start_rid_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_valid_start_rid_fkey
   FOREIGN KEY (valid_start_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_valid_until_rid_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_valid_until_rid_fkey
   FOREIGN KEY (valid_until_rid) REFERENCES revision (id) DEFERRABLE;
   -- ** Group Access Control columns
   -- FIXME Like w/ previous Item_Versioned tables, we cannot reference that
   --       which is not unique. So: Does this make for slower JOINs, since SQL
   --       cannot use an INDEX? If we want, we could make group_membership
   --       reference group_.system_id, and just have one group_membership for
   --       each user for each group_ version.
   --FOREIGN KEY (group_id) REFERENCES group_(stack_id) DEFERRABLE;
   -- ** New Item Policy columns

SELECT cp_constraint_drop_safe('group_membership',
                  'group_membership_user_id_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_user_id_fkey
   FOREIGN KEY (user_id) REFERENCES public.user_ (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_membership',
                  'group_membership_username_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_access_level_id_fkey');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_access_level_id_fkey
   FOREIGN KEY (access_level_id) REFERENCES public.access_level (id)
      DEFERRABLE;

/* 2013.04.26: Prevent duplicate records for user-group relations.
   I.e., same group_id and user but different stack IDs.
         This is a lazy check, but it should work, since unique
         stack IDs will all start at version=1 (so the unique
         ignores stack IDs and just looks at version). */
SELECT cp_constraint_drop_safe('group_membership',
                       'group_membership_group_id_user_id_version');
ALTER TABLE group_membership
   ADD CONSTRAINT group_membership_group_id_user_id_version
   UNIQUE (group_id, user_id, version);

-- FIXME auditor: Check there's only 1 stack_id for every group_id/user_id pair

/* */
DROP INDEX IF EXISTS group_membership_branch_id;
CREATE INDEX group_membership_branch_id ON group_membership (branch_id);
/* */
DROP INDEX IF EXISTS group_membership_stack_id;
CREATE INDEX group_membership_stack_id ON group_membership (stack_id);
/* */
DROP INDEX IF EXISTS group_membership_version;
CREATE INDEX group_membership_version ON group_membership (version);
/* */
DROP INDEX IF EXISTS group_membership_deleted;
CREATE INDEX group_membership_deleted ON group_membership (deleted);
/* */
DROP INDEX IF EXISTS group_membership_valid_start_rid;
CREATE INDEX group_membership_valid_start_rid
   ON group_membership (valid_start_rid);
/* */
DROP INDEX IF EXISTS group_membership_valid_until_rid;
CREATE INDEX group_membership_valid_until_rid
   ON group_membership (valid_until_rid);
/* */
DROP INDEX IF EXISTS group_membership_group_id;
CREATE INDEX group_membership_group_id ON group_membership (group_id);
/* */
DROP INDEX IF EXISTS group_membership_user_id;
CREATE INDEX group_membership_user_id ON group_membership (user_id);
/* */
DROP INDEX IF EXISTS group_membership_username;
CREATE INDEX group_membership_username ON group_membership (username);
/* */
DROP INDEX IF EXISTS group_membership_access_level_id;
CREATE INDEX group_membership_access_level_id
   ON group_membership (access_level_id);
/* */
DROP INDEX IF EXISTS group_membership_opt_out;
CREATE INDEX group_membership_opt_out ON group_membership (opt_out);

/* Make a multi-column index to speed up revision ID searches. */
DROP INDEX IF EXISTS group_membership_rids;
CREATE INDEX group_membership_rids
   ON group_membership (valid_start_rid, valid_until_rid);

/* ======================================================================== */
/* new_item_policy                                                          */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to new_item_policy.
\qecho

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_branch_id_stack_id_version_key');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_branch_id_stack_id_version_key
   UNIQUE (branch_id, stack_id, version);

SELECT cp_constraint_drop_safe('new_item_policy',
               'new_item_policy_system_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_system_id_fkey
   FOREIGN KEY (system_id) REFERENCES item_versioned (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_branch_id_stack_id_version_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_branch_id_stack_id_version_fkey
   FOREIGN KEY (branch_id, stack_id, version)
      REFERENCES item_versioned (branch_id, stack_id, version)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_valid_start_rid_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_valid_start_rid_fkey
   FOREIGN KEY (valid_start_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_valid_until_rid_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_valid_until_rid_fkey
   FOREIGN KEY (valid_until_rid) REFERENCES revision (id) DEFERRABLE;
   -- ** New Item Policy columns

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_target_item_type_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_target_item_type_id_fkey
   FOREIGN KEY (target_item_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_link_left_type_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_link_left_type_id_fkey
   FOREIGN KEY (link_left_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_link_left_min_access_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_link_left_min_access_id_fkey
   FOREIGN KEY (link_left_min_access_id)
      REFERENCES public.access_level (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_link_right_type_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_link_right_type_id_fkey
   FOREIGN KEY (link_right_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_link_right_min_access_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_link_right_min_access_id_fkey
   FOREIGN KEY (link_right_min_access_id)
      REFERENCES public.access_level (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_access_style_fkey');
SELECT cp_constraint_drop_safe('new_item_policy',
                       'new_item_policy_access_style_id_fkey');
ALTER TABLE new_item_policy
   ADD CONSTRAINT new_item_policy_access_style_id_fkey
   FOREIGN KEY (access_style_id)
      REFERENCES public.access_style (id) DEFERRABLE;

/* */
DROP INDEX IF EXISTS new_item_policy_branch_id;
CREATE INDEX new_item_policy_branch_id ON new_item_policy (branch_id);
/* */
DROP INDEX IF EXISTS new_item_policy_stack_id;
CREATE INDEX new_item_policy_stack_id ON new_item_policy (stack_id);
/* */
DROP INDEX IF EXISTS new_item_policy_version;
CREATE INDEX new_item_policy_version ON new_item_policy (version);
/* */
DROP INDEX IF EXISTS new_item_policy_deleted;
CREATE INDEX new_item_policy_deleted ON new_item_policy (deleted);
/* */
DROP INDEX IF EXISTS new_item_policy_valid_start_rid;
CREATE INDEX new_item_policy_valid_start_rid
   ON new_item_policy (valid_start_rid);
/* */
DROP INDEX IF EXISTS new_item_policy_valid_until_rid;
CREATE INDEX new_item_policy_valid_until_rid
   ON new_item_policy (valid_until_rid);
/* */
DROP INDEX IF EXISTS new_item_policy_group_id;
CREATE INDEX new_item_policy_group_id ON new_item_policy (group_id);
/* NOTE: I don't think we need to index target_item_* or link_*. */

/* This isn't necessary since we have the FOREIGN KEY
DROP INDEX IF EXISTS new_item_policy_branch_id;
CREATE INDEX new_item_policy_branch_id
   ON new_item_policy (branch_id); */
/* NOTE I don't think we need to index the item_type of link_* columns.
 *      (Because of the FOREIGN KEYs, right?) */
/* FIXME: 2011.04.22: I don't think FOREIGN KEYs are indexed, except maybe in
 *       the table being referenced! */
/* FIXME: Does this index help speed up ORDER BY? */
DROP INDEX IF EXISTS new_item_policy_processing_order;
CREATE INDEX new_item_policy_processing_order
   ON new_item_policy (processing_order);

/* Make a multi-column index to speed up revision ID searches. */
DROP INDEX IF EXISTS new_item_policy_rids;
CREATE INDEX new_item_policy_rids
   ON new_item_policy (valid_start_rid, valid_until_rid);

/* ======================================================================== */
/* ======================================================================== */
/* Step (7) -- Revision tables                                              */
/* ======================================================================== */

/* ======================================================================== */
/* revision                                                                 */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to revision.
\qecho

SELECT cp_constraint_drop_safe('revision', 'revision_username_fkey');
ALTER TABLE revision
   ADD CONSTRAINT revision_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username)
      DEFERRABLE;

/* */
DROP INDEX IF EXISTS revision_branch_id;
CREATE INDEX revision_branch_id ON revision (branch_id);

-- See schema/scripts/ccpv1/115-reactions.sql
DROP INDEX IF EXISTS rev_username;
/* NOTE: Seems like we should index username so filtering by user can be a
 *       faster operation. [ml] indicates that this also speeds up
 *       "near my edits" queries. */
DROP INDEX IF EXISTS revision_username;
CREATE INDEX revision_username ON revision (username);

/* FIXME: Index 'comment' for Search? */

\qecho
\qecho Creating index on revision.geometry
\qecho

/* FIXME:
 *       check constraint "revision_geometry" is violated by some row
SELECT cp_constraint_drop_safe('revision', 'revision_geometry');
ALTER TABLE revision ADD CONSTRAINT revision_geometry
   CHECK (IsValid(geometry));
 */

/* */
DROP INDEX IF EXISTS revision_geometry_i;
-- This is the PostGIS 1.x way:
-- CREATE INDEX revision_geometry_i ON revision
--   USING GIST (geometry GIST_GEOMETRY_OPS);
CREATE INDEX revision_geometry_i ON revision
  USING GIST (geometry);

/* FIXME: Do I need this indices as well?

\qecho
\qecho Creating index on revision.bbox
\qecho

SELECT cp_constraint_drop_safe('revision', 'revision_bbox');
ALTER TABLE revision ADD CONSTRAINT revision_bbox
   CHECK (IsValid(bbox));

DROP INDEX IF EXISTS revision_bbox;
-- This is the PostGIS 1.x way:
CREATE INDEX revision_bbox ON revision
  USING GIST (bbox GIST_GEOMETRY_OPS);

\qecho
\qecho Creating index on revision.geosummary
\qecho

SELECT cp_constraint_drop_safe('revision', 'revision_geosummary');
ALTER TABLE revision ADD CONSTRAINT revision_geosummary
   CHECK (IsValid(geosummary));

DROP INDEX IF EXISTS revision_geosummary;
-- This is the PostGIS 1.x way:
CREATE INDEX revision_geosummary ON revision
  USING GIST (geosummary GIST_GEOMETRY_OPS);

*/

/* ======================================================================== */
/* group_revision                                                           */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to group_revision.
\qecho

SELECT cp_constraint_drop_safe('group_revision',
               'group_revision_revision_id_fkey');
ALTER TABLE group_revision
   ADD CONSTRAINT group_revision_revision_id_fkey
   FOREIGN KEY (revision_id) REFERENCES revision (id) DEFERRABLE;

\qecho
\qecho Creating index on group_revision.bbox
\qecho

SELECT cp_constraint_drop_safe('group_revision', 'enforce_valid_geometry');
ALTER TABLE group_revision ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(bbox));

/* No need to index bbox: we never search on it. */
DROP INDEX IF EXISTS group_revision_bbox;
-- This is the PostGIS 1.x way:
--CREATE INDEX group_revision_bbox ON group_revision
--  USING GIST (bbox GIST_GEOMETRY_OPS);

\qecho
\qecho Creating index on group_revision.geosummary
\qecho

SELECT cp_constraint_drop_safe('group_revision', 'enforce_valid_geometry');
/* Skip strict enforcement of the geosummary geometry: it's not guaranteed
   to be simple (see ST_Simplify and ST_IsSimple). */
/*
ALTER TABLE group_revision ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(geosummary));
*/

/* No need to index geosummary: we never search on it. */
DROP INDEX IF EXISTS group_revision_geosummary;
-- This is the PostGIS 1.x way:
--CREATE INDEX group_revision_geosummary ON group_revision
--  USING GIST (geosummary GIST_GEOMETRY_OPS);

\qecho
\qecho Creating index on group_revision.geometry
\qecho

SELECT cp_constraint_drop_safe('group_revision', 'enforce_valid_geometry');
ALTER TABLE group_revision ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(geometry));

DROP INDEX IF EXISTS group_revision_geometry;
-- This is the PostGIS 1.x way:
-- CREATE INDEX group_revision_geometry ON group_revision
--   USING GIST (geometry GIST_GEOMETRY_OPS);
CREATE INDEX group_revision_geometry ON group_revision
  USING GIST (geometry);

/* The Primary Key indexes the three columns as one, so index them
 * individually. */
DROP INDEX IF EXISTS group_revision_group_id;
CREATE INDEX group_revision_group_id ON group_revision (group_id);
/* */
DROP INDEX IF EXISTS group_revision_branch_id;
CREATE INDEX group_revision_branch_id ON group_revision (branch_id);
/* */
DROP INDEX IF EXISTS group_revision_revision_id;
CREATE INDEX group_revision_revision_id ON group_revision (revision_id);

/* FIXME: Check that group_revision has same three constraints as revision.

I think these are created by postgis when you add the geometry column.
    "enforce_dims_bbox" CHECK (ndims(bbox) = 2)
    "enforce_geotype_bbox" CHECK (geometrytype(bbox) = 'POLYGON'::text
                                  OR bbox IS NULL)
    "enforce_srid_bbox" CHECK (srid(bbox) = 26915)
*/

\qecho ... re-enabling triggers: group_revision

ALTER TABLE group_revision
   ENABLE TRIGGER group_revision_date_created_i;

/* ======================================================================== */
/* ======================================================================== */
/* Step (7b) -- Revision support tables                                     */
/* ======================================================================== */

/* ======================================================================== */
/* revision_feedback                                                        */
/* ======================================================================== */

/*

SELECT cp_constraint_drop_safe('revision_feedback',
                  'revision_feedback_username_fkey');
ALTER TABLE revision_feedback
   ADD CONSTRAINT revision_feedback_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

DROP INDEX IF EXISTS revision_feedback_username;
CREATE INDEX revision_feedback_username ON revision_feedback (username);

\qecho ... re-enabling triggers: revision_feedback

ALTER TABLE revision_feedback ENABLE TRIGGER revision_feedback_i;
ALTER TABLE revision_feedback ENABLE TRIGGER revision_feedback_u;

*/

/* ======================================================================== */
/* revision_feedback_link                                                   */
/* ======================================================================== */

/*

DROP INDEX IF EXISTS revision_feedback_link_rid_target;
CREATE INDEX revision_feedback_link_rid_target
   ON revision_feedback_link (rid_target);

SELECT cp_constraint_drop_safe('revision_feedback_link',
                       'revision_feedback_link_rid_target_key');
ALTER TABLE revision_feedback_link
   ADD CONSTRAINT revision_feedback_link_rid_target_key
      UNIQUE (rid_target);

SELECT cp_constraint_drop_safe('revision_feedback_link',
                       'revision_feedback_link_rf_id_fkey');
ALTER TABLE revision_feedback_link
   ADD CONSTRAINT revision_feedback_link_rf_id_fkey
   FOREIGN KEY (rf_id) REFERENCES revision_feedback (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('revision_feedback_link',
                       'revision_feedback_link_rid_target_fkey');
ALTER TABLE revision_feedback_link
   ADD CONSTRAINT revision_feedback_link_rid_target_fkey
   FOREIGN KEY (rid_target) REFERENCES revision (id) DEFERRABLE;

\qecho ... re-enabling triggers: revision_feedback_link

ALTER TABLE revision_feedback_link ENABLE TRIGGER revision_feedback_link_u;

*/

/* ======================================================================== */
/* revert_event                                                             */
/* ======================================================================== */

\qecho
\qecho Adding/Enabling constraints/indexes/triggers on revert_event.
\qecho

/*

SELECT cp_constraint_drop_safe('revert_event',
            'revert_event_rid_reverting_fkey');
ALTER TABLE revert_event
   ADD CONSTRAINT revert_event_rid_reverting_fkey
   FOREIGN KEY (rid_reverting) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('revert_event', 'revert_event_rid_victim_fkey');
ALTER TABLE revert_event
   ADD CONSTRAINT revert_event_rid_victim_fkey
   FOREIGN KEY (rid_victim) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('revert_event', 'revert_event_check');
ALTER TABLE revert_event
   ADD CONSTRAINT revert_event_check CHECK (rid_reverting > rid_victim);

*/

/* FIXME: Should we index this column?

DROP INDEX IF EXISTS revert_event_rid_reverting;
CREATE INDEX revert_event_rid_reverting ON revert_event (rid_reverting);
*/

/*

DROP INDEX IF EXISTS revert_event_rid_victim;
CREATE INDEX revert_event_rid_victim ON revert_event (rid_victim);

*/

\qecho ... re-enabling triggers: revert_event

ALTER TABLE revert_event ENABLE TRIGGER revert_event_i;
ALTER TABLE revert_event ENABLE TRIGGER revert_event_u;

/* ======================================================================== */
/* Step (8) -- GIA table                                                    */
/* ======================================================================== */

/* ======================================================================== */
/* group_item_access                                                        */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to group_item_access.
\qecho

SELECT cp_constraint_drop_safe('group_item_access',
                        'group_item_access_item_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_item_id_fkey
   FOREIGN KEY (item_id) REFERENCES item_versioned (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_branch_id_stack_id_version_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_branch_id_stack_id_version_fkey
   FOREIGN KEY (branch_id, stack_id, version)
      REFERENCES item_versioned (branch_id, stack_id, version)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_stack_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_stack_id_fkey
   FOREIGN KEY (stack_id)
   REFERENCES item_stack (stack_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_valid_start_rid_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_valid_start_rid_fkey
   FOREIGN KEY (valid_start_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_valid_until_rid_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_valid_until_rid_fkey
   FOREIGN KEY (valid_until_rid) REFERENCES revision (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_access_level_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_access_level_id_fkey
   FOREIGN KEY (access_level_id) REFERENCES public.access_level (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_item_type_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_item_type_id_fkey
   FOREIGN KEY (item_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

/* 2013.08.06: item_layer_id is deprecated; nothing uses it. */
/*
SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_item_layer_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_item_layer_id_fkey
   FOREIGN KEY (item_layer_id) REFERENCES public.geofeature_layer (id)
      DEFERRABLE;
*/

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_link_lhs_type_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_link_lhs_type_id_fkey
   FOREIGN KEY (link_lhs_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('group_item_access',
                       'group_item_access_link_rhs_type_id_fkey');
ALTER TABLE group_item_access
   ADD CONSTRAINT group_item_access_link_rhs_type_id_fkey
   FOREIGN KEY (link_rhs_type_id) REFERENCES public.item_type (id)
      DEFERRABLE;

\qecho ...enforce_version_positive_non_negative
SELECT cp_constraint_drop_safe('group_item_access',
            'enforce_version_positive_non_negative');
ALTER TABLE group_item_access
   ADD CONSTRAINT enforce_version_positive_non_negative
      CHECK (version > 0);

/* 2011.04.24: How did I miss this for so long?!! I really hope this speeds up
 *             load times...!! */

\qecho
\qecho Creating indexes on group_item_access.
\qecho

/* 2011.03.18 Try indexing 'em all!
   FIXME: Things were really slow. I thought foreign keys were automatically
          indexed, but it appears they're not.  Indexing all the columns seems
          to work, but I wonder if that's ineffecient (I've read that it's
          wasteful). Then again, for a database under 1 GB, I bet it doesn't
          matter. */

/* NOTE: Adding indices before populating group_item_access might make
 *       populating the table slower than adding indices after populating
 *       the table. */

/* */
DROP INDEX IF EXISTS group_item_access_group_id;
CREATE INDEX group_item_access_group_id
   ON group_item_access (group_id);
/* */
DROP INDEX IF EXISTS group_item_access_session_id;
CREATE INDEX group_item_access_session_id
   ON group_item_access (session_id);
/* */
DROP INDEX IF EXISTS group_item_access_access_level_id;
CREATE INDEX group_item_access_access_level_id
   ON group_item_access (access_level_id);
/* */
DROP INDEX IF EXISTS group_item_access_name;
CREATE INDEX group_item_access_name
   ON group_item_access (name);
/* */
DROP INDEX IF EXISTS group_item_access_deleted;
CREATE INDEX group_item_access_deleted
   ON group_item_access (deleted);
/* */
DROP INDEX IF EXISTS group_item_access_reverted;
CREATE INDEX group_item_access_reverted
   ON group_item_access (reverted);
/* */
DROP INDEX IF EXISTS group_item_access_branch_id;
CREATE INDEX group_item_access_branch_id
   ON group_item_access (branch_id);
/* */
DROP INDEX IF EXISTS group_item_access_item_id;
CREATE INDEX group_item_access_item_id
   ON group_item_access (item_id);
/* */
DROP INDEX IF EXISTS group_item_access_stack_id;
CREATE INDEX group_item_access_stack_id
   ON group_item_access (stack_id);
/* */
DROP INDEX IF EXISTS group_item_access_version;
CREATE INDEX group_item_access_version
   ON group_item_access (version);
/* */
DROP INDEX IF EXISTS group_item_access_acl_grouping;
CREATE INDEX group_item_access_acl_grouping
   ON group_item_access (acl_grouping);
/* */
DROP INDEX IF EXISTS group_item_access_valid_start_rid;
CREATE INDEX group_item_access_valid_start_rid
   ON group_item_access (valid_start_rid);
/* */
/* MAYBE: Is this already indexed because it's in the primary key? */
DROP INDEX IF EXISTS group_item_access_valid_until_rid;
CREATE INDEX group_item_access_valid_until_rid
   ON group_item_access (valid_until_rid);
/* */
DROP INDEX IF EXISTS group_item_access_item_type_id;
CREATE INDEX group_item_access_item_type_id
   ON group_item_access (item_type_id);
/* */
/* 2013.08.06: item_layer_id is deprecated; nothing uses it. */
/*
DROP INDEX IF EXISTS group_item_access_item_layer_id;
CREATE INDEX group_item_access_item_layer_id
   ON group_item_access (item_layer_id);
*/
/* */
DROP INDEX IF EXISTS group_item_access_link_lhs_type_id;
CREATE INDEX group_item_access_link_lhs_type_id
   ON group_item_access (link_lhs_type_id);
/* */
DROP INDEX IF EXISTS group_item_access_link_rhs_type_id;
CREATE INDEX group_item_access_link_rhs_type_id
   ON group_item_access (link_rhs_type_id);

/* Make a multi-column index to speed up revision ID searches. */
/* 2012.10.05: The above comment needs proof, I think, like quantification.
               And this is ASC, ASC, which might not fit our usage... and
               really you should use EXPLAIN to see the planner ever even
               considers this index. */
DROP INDEX IF EXISTS group_item_access_rids;
CREATE INDEX group_item_access_rids
   ON group_item_access (valid_start_rid, valid_until_rid);

/* 2013.04.02: Create indexes for specific ORDER BY clauses. */

/* FIXME: Look at SQL output and look for other ORDER BY clauses to include */

/* SYNC_ME: add_constraints/sql_clauses_cols_all.inner.order_by */
DROP INDEX IF EXISTS group_item_access_major_order_by_a;
CREATE INDEX group_item_access_major_order_by_a
   ON group_item_access (stack_id ASC
                        , branch_id DESC
                        , version DESC
                        , acl_grouping DESC
                        , access_level_id ASC);

DROP INDEX IF EXISTS group_item_access_major_order_by_b;
CREATE INDEX group_item_access_major_order_by_b
   ON group_item_access (stack_id ASC
                        , branch_id DESC
                        , acl_grouping DESC
                        , access_level_id ASC);

/* ======================================================================== */
/* ======================================================================== */
/* Step (9) -- Node tables                                                  */
/* ======================================================================== */

/* ======================================================================== */
/* node_byway                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to node_byway.
\qecho

SELECT cp_constraint_drop_safe('node_byway', 'enforce_valid_geometry');
ALTER TABLE node_byway ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(node_vertex_xy));

/* I'm not sure that points support GIST_GEOMETRY_OPS... */
DROP INDEX IF EXISTS node_byway_node_vertex_xy;
-- This is the PostGIS 1.x way:
-- CREATE INDEX node_byway_node_vertex_xy ON node_byway
--    USING GIST (node_vertex_xy GIST_GEOMETRY_OPS);
CREATE INDEX node_byway_node_vertex_xy ON node_byway
   USING GIST (node_vertex_xy);

/* ======================================================================== */
/* node_endpoint                                                            */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to node_endpoint.
\qecho

/* ======================================================================== */
/* node_endpt_xy                                                            */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to node_endpt_xy.
\qecho

SELECT cp_constraint_drop_safe('node_endpt_xy', 'enforce_valid_geometry');
ALTER TABLE node_endpt_xy ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(endpoint_xy));

/* I'm not sure that points support GIST_GEOMETRY_OPS... */
DROP INDEX IF EXISTS node_endpt_xy_endpoint_xy;
-- This is the PostGIS 1.x way:
-- CREATE INDEX node_endpt_xy_endpoint_xy ON node_endpt_xy
--    USING GIST (endpoint_xy GIST_GEOMETRY_OPS);
CREATE INDEX node_endpt_xy_endpoint_xy ON node_endpt_xy
   USING GIST (endpoint_xy);

/* ======================================================================== */
/* node_traverse                                                            */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to node_traverse.
\qecho

/* In lieu of foreign keys (since the stack ID is not unique), we at least
 * index the foreign "keys". */

DROP INDEX IF EXISTS node_traverse_node_stack_id;
CREATE INDEX node_traverse_node_stack_id ON node_traverse (node_stack_id);

DROP INDEX IF EXISTS node_traverse_exit_stack_id;
CREATE INDEX node_traverse_exit_stack_id ON node_traverse (exit_stack_id);

DROP INDEX IF EXISTS node_traverse_into_stack_id;
CREATE INDEX node_traverse_into_stack_id ON node_traverse (into_stack_id);

/* ======================================================================== */
/* ======================================================================== */
/* Step (10) -- Branch support tables                                       */
/* ======================================================================== */

/* ======================================================================== */
/* branch_conflict                                                          */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to branch_conflict.
\qecho

SELECT cp_constraint_drop_safe('branch_conflict',
                               'branch_conflict_branch_system_id_fkey');
ALTER TABLE branch_conflict
   ADD CONSTRAINT branch_conflict_branch_system_id_fkey
      FOREIGN KEY (branch_system_id) REFERENCES branch (system_id) DEFERRABLE;

/* */
DROP INDEX IF EXISTS branch_conflict_branch_system_id;
CREATE INDEX branch_conflict_branch_system_id
   ON branch_conflict (branch_system_id);
/* */
DROP INDEX IF EXISTS branch_conflict_item_id_left;
CREATE INDEX branch_conflict_item_id_left ON branch_conflict (item_id_left);
/* */
DROP INDEX IF EXISTS branch_conflict_item_id_right;
CREATE INDEX branch_conflict_item_id_right ON branch_conflict (item_id_right);
/* */
DROP INDEX IF EXISTS branch_conflict_conflict_resolved;
CREATE INDEX branch_conflict_conflict_resolved
   ON branch_conflict (conflict_resolved);

/* ======================================================================== */
/* ======================================================================== */
/* Step (11) -- Item support tables                                         */
/* ======================================================================== */

/* ======================================================================== */
/* aadt                                                                     */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to aadt.
\qecho

/* FIXME: Is this appropriate?: */
/* */
--DROP INDEX IF EXISTS aadt_branch_id;
--CREATE INDEX aadt_branch_id ON aadt (branch_id);
/* */
--DROP INDEX IF EXISTS aadt_byway_stack_id;
--CREATE INDEX aadt_byway_stack_id ON aadt (byway_stack_id);

\qecho ... re-enabling triggers: aadt

ALTER TABLE aadt ENABLE TRIGGER aadt_ilm;
ALTER TABLE aadt ENABLE TRIGGER aadt_u;

/* ======================================================================== */
/* byway_rating                                                             */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to byway_rating.
\qecho

SELECT cp_constraint_drop_safe('byway_rating', 'byway_rating_username_fkey');
ALTER TABLE byway_rating
   ADD CONSTRAINT byway_rating_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username)
      DEFERRABLE;

/* From V1: */
DROP INDEX IF EXISTS byway_rating_byway_stack_id;
CREATE INDEX byway_rating_byway_stack_id ON byway_rating (byway_stack_id);
/* */
DROP INDEX IF EXISTS byway_rating_last_modified;
CREATE INDEX byway_rating_last_modified ON byway_rating (last_modified);

/* New in V2: */
DROP INDEX IF EXISTS byway_rating_username;
CREATE INDEX byway_rating_username ON byway_rating (username);
/* */
DROP INDEX IF EXISTS byway_rating_branch_id;
CREATE INDEX byway_rating_branch_id ON byway_rating (branch_id);

\qecho ... re-enabling triggers: byway_rating

ALTER TABLE byway_rating ENABLE TRIGGER byway_rating_ilm;
ALTER TABLE byway_rating ENABLE TRIGGER byway_rating_u;

/* ======================================================================== */
/* byway_rating_event                                                       */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to byway_rating_event.
\qecho

SELECT cp_constraint_drop_safe('byway_rating_event',
                  'byway_rating_event_username_fkey');
ALTER TABLE byway_rating_event
   ADD CONSTRAINT byway_rating_event_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username)
      DEFERRABLE;

/* FIXME: Are any of these useful? */
/*
DROP INDEX IF EXISTS byway_rating_event_branch_id;
CREATE INDEX byway_rating_event_branch_id
   ON byway_rating_event (branch_id);
DROP INDEX IF EXISTS byway_rating_event_byway_stack_id;
CREATE INDEX byway_rating_event_byway_stack_id
   ON byway_rating_event (byway_stack_id);
DROP INDEX IF EXISTS byway_rating_event_username;
CREATE INDEX byway_rating_event_username
   ON byway_rating_event (username);
*/

\qecho ... re-enabling triggers: byway_rating_event

ALTER TABLE byway_rating_event ENABLE TRIGGER byway_rating_event_i;
ALTER TABLE byway_rating_event ENABLE TRIGGER byway_rating_event_u;

/* ======================================================================== */
/* geofeature_layer                                                         */
/* ======================================================================== */

\qecho
\qecho Adding/Enabling constraints/indexes/triggers on byway_rating_event.
\qecho

\qecho ... re-enabling triggers: geofeature_layer

ALTER TABLE geofeature_layer ENABLE TRIGGER geofeature_layer_i;
ALTER TABLE geofeature_layer ENABLE TRIGGER geofeature_layer_u;

/* ======================================================================== */
/* ======================================================================== */
/* Step (12) -- Route support tables                                        */
/* ======================================================================== */

/* ======================================================================== */
/* route_feedback                                                           */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_feedback.
\qecho

SELECT cp_constraint_drop_safe('route_feedback',
                  'route_feedback_route_id_fkey');
ALTER TABLE route_feedback
   ADD CONSTRAINT route_feedback_route_id_fkey
   FOREIGN KEY (route_id) REFERENCES route (system_id) DEFERRABLE;

SELECT cp_constraint_drop_safe('route_feedback',
                  'route_feedback_username_fkey');
ALTER TABLE route_feedback
   ADD CONSTRAINT route_feedback_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

/* */
DROP INDEX IF EXISTS route_feedback_route_id;
CREATE INDEX route_feedback_route_id ON route_feedback (route_id);
/* */
DROP INDEX IF EXISTS route_feedback_username;
CREATE INDEX route_feedback_username ON route_feedback (username);

\qecho ... re-enabling triggers: route_feedback

ALTER TABLE route_feedback ENABLE TRIGGER route_feedback_i;
ALTER TABLE route_feedback ENABLE TRIGGER route_feedback_u;

/* ======================================================================== */
/* route_feedback_drag                                                      */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_feedback_drag.
\qecho

/* FIXME: Update to CcpV2. In CcpV1, this is the stack_id... */

DROP INDEX IF EXISTS route_feedback_drag_username;
CREATE INDEX route_feedback_drag_username
   ON route_feedback_drag (username);

DROP INDEX IF EXISTS route_feedback_drag_new_route_id;
CREATE INDEX route_feedback_drag_new_route_id
   ON route_feedback_drag (new_route_id);

DROP INDEX IF EXISTS route_feedback_drag_old_route_id;
CREATE INDEX route_feedback_drag_old_route_id
   ON route_feedback_drag (old_route_id);

\qecho ... re-creating foreign key constraints

SELECT cp_constraint_drop_safe('route_feedback_drag',
                  'route_feedback_drag_username_fkey');
ALTER TABLE route_feedback_drag
   ADD CONSTRAINT route_feedback_drag_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

/* FIXME: Either just use
            new_route_id
            old_route_id
          and delete
            old_route_stack_id
            old_route_version
            new_route_stack_id
            new_route_version
          or keep the latter and add
            new_route_branch_id
            old_route_branch_id

SELECT cp_constraint_drop_safe('route_feedback_drag',
                  'route_feedback_drag_new_route_fkey');
ALTER TABLE route_feedback_drag
   ADD CONSTRAINT route_feedback_drag_new_route_fkey
   FOREIGN KEY (new_route_id, new_route_version)
   REFERENCES route (stack_id, version) DEFERRABLE;

SELECT cp_constraint_drop_safe('route_feedback_drag',
                  'route_feedback_drag_old_route_fkey');
ALTER TABLE route_feedback_drag
   ADD CONSTRAINT route_feedback_drag_old_route_fkey
   FOREIGN KEY (old_route_id, old_route_version)
   REFERENCES route (stack_id, version) DEFERRABLE;

*/

\qecho ... re-enabling triggers: route_feedback_drag

ALTER TABLE route_feedback_drag ENABLE TRIGGER route_feedback_drag_i;
ALTER TABLE route_feedback_drag ENABLE TRIGGER route_feedback_drag_u;

/* ======================================================================== */
/* route_feedback_stretch                                                   */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_feedback_stretch.
\qecho

SELECT cp_constraint_drop_safe('route_feedback_stretch',
                  'route_feedback_stretch_feedback_drag_id_fkey');
ALTER TABLE route_feedback_stretch
   ADD CONSTRAINT route_feedback_stretch_feedback_drag_id_fkey
   FOREIGN KEY (feedback_drag_id)
   REFERENCES route_feedback_drag (id) DEFERRABLE;

SELECT cp_constraint_drop_safe('route_feedback_stretch',
                  'route_feedback_stretch_byway_stack_id_fkey');
ALTER TABLE route_feedback_stretch
   ADD CONSTRAINT route_feedback_stretch_byway_stack_id_fkey
   FOREIGN KEY (byway_stack_id)
   REFERENCES item_stack (stack_id) DEFERRABLE;

/* ======================================================================== */
/* route_parameters                                                         */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_parameters.
\qecho

/* FIXME: [lb] notes that routes are not saved across branches,
          so the branch_id column in route_parameters is useless.. */
DROP INDEX IF EXISTS route_parameters_branch_id;
CREATE INDEX route_parameters_branch_id ON route_parameters (branch_id);

/* */
SELECT cp_constraint_drop_safe('route_parameters', 'route_priority_pkey');
ALTER TABLE route_parameters
   ADD CONSTRAINT route_priority_pkey
      PRIMARY KEY (branch_id, route_stack_id);

/* ======================================================================== */
/* route_step                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_step.
\qecho

SELECT cp_constraint_drop_safe('route_step', 'route_step_route_id_fkey');
ALTER TABLE route_step
   ADD CONSTRAINT route_step_route_id_fkey
   FOREIGN KEY (route_id) REFERENCES route (system_id)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('route_step', 'route_step_byway_id_fkey');
ALTER TABLE route_step
   ADD CONSTRAINT route_step_byway_id_fkey
   FOREIGN KEY (byway_id) REFERENCES geofeature (system_id)
      DEFERRABLE;

/* FIXME: The primary key is (route_id, step_number). Does that mean we should
 *        explicitly index the columns individually? */
/* */
DROP INDEX IF EXISTS route_step_route_id;
CREATE INDEX route_step_route_id ON route_step (route_id);
/* */
--DROP INDEX IF EXISTS route_step_step_number;
--CREATE INDEX route_step_step_number ON route_step (step_number);
/* */
--DROP INDEX IF EXISTS route_step_byway_id;
--CREATE INDEX route_step_byway_id ON route_step (byway_id);
/* */
--DROP INDEX IF EXISTS route_step_route_id_byway_id;
--CREATE INDEX route_step_route_id_byway_id ON route_step (route_id, byway_id);

DROP INDEX IF EXISTS route_step_gist;
-- This is the PostGIS 1.x way:
-- CREATE INDEX route_step_gist ON route_step
--    USING GIST (transit_geometry GIST_GEOMETRY_OPS);
CREATE INDEX route_step_gist ON route_step
   USING GIST (transit_geometry);

SELECT cp_constraint_drop_safe('route_step', 'enforce_valid_byway');
ALTER TABLE route_step
   ADD CONSTRAINT enforce_valid_byway
   CHECK ((    (travel_mode != 2)
           AND (byway_id IS NOT NULL)
           AND (byway_stack_id IS NOT NULL)
           AND (byway_version IS NOT NULL))
          OR (    (travel_mode = 2)
              AND (transit_geometry IS NOT NULL)));

/* ======================================================================== */
/* route_stop                                                               */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_stop.
\qecho

/* FIXME: This table is new to CcpV2... make sure this is setup right. */

/* The route_stop table, new in 2012, references the old route table.
 * Currently, I don't think this table needs to be changed... but maybe later
 * we'll find out it does. For now, just fix the foreign key constraint. */

SELECT cp_constraint_drop_safe('route_stop', 'route_stop_route_id_fkey');
ALTER TABLE route_stop
   ADD CONSTRAINT route_stop_route_id_fkey
   FOREIGN KEY (route_id) REFERENCES route (system_id)
      DEFERRABLE;

/* NOTE: Not making foreign key constraint on node_id to node_endpoint since
         it's the stack_id and its versioned. But we can now make a foreign
         key relationship with the new item_stack table (2012.09.26). */
/* FIXME: Audit all other tables, none of which have fkeys on stack_id, and
          make new fkeys. */
/* MAYBE: Should node_id be renamed to node_stack_id?
          In geofeature, we have beg_node_id and fin_node_id... which are
          also just stack_ids... this breaks convention, doesn't it?? */
/* 2012.12.23: Silly, why is this fkey here? We haven't populate item_stack
   with the node stack IDs....
SELECT cp_constraint_drop_safe('route_stop', 'route_stop_node_id_fkey');
ALTER TABLE route_stop
   ADD CONSTRAINT route_stop_node_id_fkey
   FOREIGN KEY (node_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;
*/

DROP INDEX IF EXISTS route_stop_route_id;
CREATE INDEX route_stop_route_id ON route_stop (route_id);

/* FIXME: See 201-apb-81-sys_id-populate.sql:
 *        Missing indexices:
 *          route_stop_route_stack_id,
 *          route_stop_route_version
 *          route_stop_route_stack_id_version
 */

/* ======================================================================== */
/* route_view                                                               */
/* ======================================================================== */

/* Fix the CcpV1 route_view, which pkey on stack_id and then username...
   but we should index by username and then stack_id. */

/* FIXME: Delete route_view. Replaced by item_findability.

ALTER TABLE route_view DROP CONSTRAINT route_view_pkey;
ALTER TABLE route_view
   ADD CONSTRAINT route_view_pkey
   PRIMARY KEY (username, route_stack_id);

SELECT cp_constraint_drop_safe('route_view', 'route_view_username_fkey');
ALTER TABLE route_view
   ADD CONSTRAINT route_view_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('route_view', 'route_view_route_stack_id_fkey');
ALTER TABLE route_view
   ADD CONSTRAINT route_view_route_stack_id_fkey
   FOREIGN KEY (route_stack_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;

DROP INDEX IF EXISTS route_view_route_stack_id;
CREATE INDEX route_view_route_stack_id
   ON route_view (route_stack_id);

DROP INDEX IF EXISTS route_view_active;
CREATE INDEX route_view_active
   ON route_view (active);

-- Skipping: last_viewed.

DROP INDEX IF EXISTS route_view_branch_id;
CREATE INDEX route_view_branch_id
   ON route_view (branch_id);

\qecho ... re-enabling triggers: route_view
ALTER TABLE route_view ENABLE TRIGGER route_view_last_viewed_i;

*/

/* ======================================================================== */
/* routed_ports                                                             */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to routed_ports.
\qecho

/* MAYBE: The item_stack table is much newer than this constraints file.
          Previously, we could not FKEY any stack_ids, like branch_id and
          stack_id. But now we can. Should we do this across the board? */
SELECT cp_constraint_drop_safe('routed_ports', 'routed_ports_branch_id_fkey');
ALTER TABLE routed_ports
   ADD CONSTRAINT routed_ports_branch_id_fkey
   FOREIGN KEY (branch_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;

/* It's not like the routed_ports table will ever be that populated...
   but indices never hurt. Do they? Or maybe indexing just a few rows
   actually makes it slower... or is that just junk science? */
/* See routed_ports.py, which WHEREses all these columns that we index. */
/*
DROP INDEX IF EXISTS routed_ports_instance;
CREATE INDEX routed_ports_instance ON routed_ports (instance);
DROP INDEX IF EXISTS routed_ports_branch_id;
CREATE INDEX routed_ports_branch_id ON routed_ports (branch_id);
DROP INDEX IF EXISTS routed_ports_routed_pers;
CREATE INDEX routed_ports_routed_pers ON routed_ports (routed_pers);
DROP INDEX IF EXISTS routed_ports_purpose;
CREATE INDEX routed_ports_purpose ON routed_ports (purpose);
*/
/* */
DROP INDEX IF EXISTS routed_ports_unique_index;
CREATE INDEX routed_ports_unique_index ON routed_ports
   (instance, branch_id, routed_pers, purpose);
DROP INDEX IF EXISTS routed_ports_routed_hup;
CREATE INDEX routed_ports_routed_hup ON routed_ports
   (instance, purpose);

\qecho ... re-enabling triggers: routed_ports
ALTER TABLE routed_ports ENABLE TRIGGER routed_ports_i;
ALTER TABLE routed_ports ENABLE TRIGGER routed_ports_u;

/* ======================================================================== */
/* route_tag_preference                                                     */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to route_tag_preference.
\qecho

SELECT cp_constraint_drop_safe('route_tag_preference',
                     'route_tag_preference_tpt_id_fkey');
ALTER TABLE route_tag_preference
   ADD CONSTRAINT route_tag_preference_tpt_id_fkey
   FOREIGN KEY (tpt_id) REFERENCES public.tag_preference_type (id)
      DEFERRABLE;

/* */
DROP INDEX IF EXISTS route_tag_preference_route_stack_id;
CREATE INDEX route_tag_preference_route_stack_id
   ON route_tag_preference (route_stack_id);
/* */
DROP INDEX IF EXISTS route_tag_preference_tag_stack_id;
CREATE INDEX route_tag_preference_tag_stack_id
   ON route_tag_preference (tag_stack_id);
/* */
DROP INDEX IF EXISTS route_tag_preference_branch_id;
CREATE INDEX route_tag_preference_branch_id
   ON route_tag_preference (branch_id);

/* ======================================================================== */
/* tag_preference                                                           */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to tag_preference.
\qecho

SELECT cp_constraint_drop_safe('tag_preference',
                  'tag_preference_username_fkey');
ALTER TABLE tag_preference
   ADD CONSTRAINT tag_preference_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('tag_preference', 'tag_preference_tpt_id_fkey');
ALTER TABLE tag_preference
   ADD CONSTRAINT tag_preference_tpt_id_fkey
   FOREIGN KEY (tpt_id) REFERENCES public.tag_preference_type (id)
      DEFERRABLE;

/* */
DROP INDEX IF EXISTS tag_preference_username;
CREATE INDEX tag_preference_username
   ON tag_preference (username);
/* */
DROP INDEX IF EXISTS tag_preference_branch_id;
CREATE INDEX tag_preference_branch_id
   ON tag_preference (branch_id);
/* */
DROP INDEX IF EXISTS tag_preference_tag_stack_id;
CREATE INDEX tag_preference_tag_stack_id
   ON tag_preference (tag_stack_id);

\qecho ... re-enabling triggers: tag_preference

ALTER TABLE tag_preference ENABLE TRIGGER tag_preference_ilm;
ALTER TABLE tag_preference ENABLE TRIGGER tag_preference_u;

/* ======================================================================== */
/* tag_preference_event                                                     */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to tag_preference_event.
\qecho

SELECT cp_constraint_drop_safe('tag_preference_event',
                  'tag_preference_event_username_fkey');
ALTER TABLE tag_preference_event
   ADD CONSTRAINT tag_preference_event_username_fkey
   FOREIGN KEY (username) REFERENCES public.user_ (username)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('tag_preference_event',
                  'tag_preference_event_tpt_id_fkey');
ALTER TABLE tag_preference_event
   ADD CONSTRAINT tag_preference_event_tpt_id_fkey
   FOREIGN KEY (tpt_id) REFERENCES public.tag_preference_type (id)
      DEFERRABLE;

/* */
DROP INDEX IF EXISTS tag_preference_event_username;
CREATE INDEX tag_preference_event_username
   ON tag_preference_event (username);
/* */
DROP INDEX IF EXISTS tag_preference_event_branch_id;
CREATE INDEX tag_preference_event_branch_id
   ON tag_preference_event (branch_id);
/* */
DROP INDEX IF EXISTS tag_preference_event_tag_stack_id;
CREATE INDEX tag_preference_event_tag_stack_id
   ON tag_preference_event (tag_stack_id);

\qecho ... re-enabling triggers: tag_preference_event

ALTER TABLE tag_preference_event ENABLE TRIGGER tag_preference_event_i;
ALTER TABLE tag_preference_event ENABLE TRIGGER tag_preference_event_u;

/* ======================================================================== */
/* item_findability                                                         */
/* ======================================================================== */

/* C.f. route_view */

--ALTER TABLE item_findability DROP CONSTRAINT item_findability_pkey;
SELECT cp_constraint_drop_safe('item_findability',
                               'item_findability_pkey');
ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_pkey
   PRIMARY KEY (username, item_stack_id);

SELECT cp_constraint_drop_safe('item_findability',
                               'item_findability_username_fkey');
ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username)
      DEFERRABLE;

SELECT cp_constraint_drop_safe('item_findability',
                               'item_findability_item_stack_id_fkey');
ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_item_stack_id_fkey
   FOREIGN KEY (item_stack_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;

DROP INDEX IF EXISTS item_findability_item_stack_id;
CREATE INDEX item_findability_item_stack_id
   ON item_findability (item_stack_id);

DROP INDEX IF EXISTS item_findability_branch_id;
CREATE INDEX item_findability_branch_id
   ON item_findability (branch_id);

\qecho ... re-enabling triggers: item_findability
ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_i;
ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_u;

/* ======================================================================== */
/* ======================================================================== */
/* Step (13) -- Track support tables                                        */
/* ======================================================================== */

/* ======================================================================== */
/* track_point                                                              */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to track_point.
\qecho

SELECT cp_constraint_drop_safe('track_point', 'track_point_track_id_fkey');
ALTER TABLE track_point
   ADD CONSTRAINT track_point_track_id_fkey
   FOREIGN KEY (track_id) REFERENCES track (system_id)
      DEFERRABLE;

/* */

/* FIXME: Are these necessary? */

DROP INDEX IF EXISTS track_point_track_stack_id;
CREATE INDEX track_point_track_stack_id ON track_point (track_stack_id);

DROP INDEX IF EXISTS track_point_track_version;
CREATE INDEX track_point_track_version ON track_point (track_version);

DROP INDEX IF EXISTS track_point_track_stack_id_version;
CREATE INDEX track_point_track_stack_id_version
   ON track_point (track_stack_id, track_version);

/* This is the pkey, so an index would be redundant:
DROP INDEX IF EXISTS track_point_track_stack_id_step_number;
CREATE INDEX track_point_track_stack_id_step_number
   ON track_point (track_stack_id, step_number);
*/

/* Is this necessary?: */
DROP INDEX IF EXISTS track_point_track_stack_id_version_step_number;
CREATE INDEX track_point_track_stack_id_version_step_number
   ON track_point (track_stack_id, track_version, step_number);

/* In CcpV1, the timestamp is also indexed... */
DROP INDEX IF EXISTS track_point_timestamp;
CREATE INDEX track_point_timestamp
   ON track_point (timestamp);

/* ======================================================================== */
/* ======================================================================== */
/* Step (14) -- Item event (watchers, read, and alert) tables               */
/* ======================================================================== */

/* ======================================================================== */
/* item_event_read                                                          */
/* ======================================================================== */

\qecho
\qecho Adding/Enabling constraints/indexes/triggers on item_event_read.
\qecho

-- Not indexing: created.

DROP INDEX IF EXISTS item_event_read_username;
CREATE INDEX item_event_read_username
          ON item_event_read (username);

DROP INDEX IF EXISTS item_event_read_item_id;
CREATE INDEX item_event_read_item_id
          ON item_event_read (item_id);

DROP INDEX IF EXISTS item_event_read_revision_id;
CREATE INDEX item_event_read_revision_id
          ON item_event_read (revision_id);

\qecho ... re-enabling triggers: item_event_read
ALTER TABLE item_event_read ENABLE TRIGGER item_event_read_ic;
ALTER TABLE item_event_read ENABLE TRIGGER item_event_read_ir;

/* ======================================================================== */
/* item_watcher                                                             */
/* ======================================================================== */

/*

2013.03.27: Deprecated. Replaced by private link_value attributes.

\qecho
\qecho Adding constraints and indexes to item_watcher.
\qecho

/ * FIXME: I'm not sure if INDEXes on FOREIGN KEYs is redundant... I believe
           not. * /

SELECT cp_constraint_drop_safe('item_watcher',
            'item_watcher_for_username_fkey');
ALTER TABLE item_watcher
   ADD CONSTRAINT item_watcher_for_username_fkey
      FOREIGN KEY (for_username) REFERENCES public.user_ (username) DEFERRABLE;
DROP INDEX IF EXISTS item_watcher_for_username;
CREATE INDEX item_watcher_for_username ON item_watcher (for_username);

SELECT cp_constraint_drop_safe('item_watcher',
            'item_watcher_item_type_id_fkey');
ALTER TABLE item_watcher
   ADD CONSTRAINT item_watcher_item_type_id_fkey
      FOREIGN KEY (item_type_id) REFERENCES public.item_type (id) DEFERRABLE;
DROP INDEX IF EXISTS item_watcher_item_type_id;
CREATE INDEX item_watcher_item_type_id ON item_watcher (item_type_id);

DROP INDEX IF EXISTS item_watcher_item_stack_id;
CREATE INDEX item_watcher_item_stack_id ON item_watcher (item_stack_id);

*/

/* ======================================================================== */
/* item_watcher_change                                                      */
/* ======================================================================== */

/*

2013.03.27: Deprecated. Replaced by private link_value attributes.

\qecho
\qecho Adding constraints and indexes to item_watcher_change.
\qecho

DROP INDEX IF EXISTS item_watcher_change_item_watcher_id;
CREATE INDEX item_watcher_change_item_watcher_id
   ON item_watcher_change (item_watcher_id);

*/

/* ======================================================================== */
/* item_event_alert                                                         */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to item_event_alert.
\qecho

--ALTER TABLE item_event_alert DROP CONSTRAINT messaging_pkey;
SELECT cp_constraint_drop_safe('item_event_alert',
                               'messaging_pkey');
--DROP INDEX IF EXISTS messaging_pkey;
--ALTER TABLE item_event_alert DROP CONSTRAINT item_event_alert_pkey;
SELECT cp_constraint_drop_safe('item_event_alert',
                               'item_event_alert_pkey');
ALTER TABLE item_event_alert
   ADD CONSTRAINT item_event_alert_pkey
   PRIMARY KEY (messaging_id);

SELECT cp_constraint_drop_safe('item_event_alert',
                               'messaging_username_fkey');
SELECT cp_constraint_drop_safe('item_event_alert',
                               'item_event_alert_username_fkey');
ALTER TABLE item_event_alert
   ADD CONSTRAINT item_event_alert_username_fkey
      FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

DROP INDEX IF EXISTS messaging_username;
DROP INDEX IF EXISTS item_event_alert_username;
CREATE INDEX item_event_alert_username
             ON item_event_alert (username);

SELECT cp_constraint_drop_safe('item_event_alert',
                               'messaging_latest_rev_fkey');
SELECT cp_constraint_drop_safe('item_event_alert',
                               'item_event_alert_latest_rid_fkey');
ALTER TABLE item_event_alert
   ADD CONSTRAINT item_event_alert_latest_rid_fkey
   FOREIGN KEY (latest_rid) REFERENCES revision (id) DEFERRABLE;

DROP INDEX IF EXISTS messaging_latest_rev;
DROP INDEX IF EXISTS item_event_alert_latest_rid;
CREATE INDEX item_event_alert_latest_rid
             ON item_event_alert (latest_rid);

SELECT cp_constraint_drop_safe('item_event_alert',
                               'messaging_item_id_fkey');
SELECT cp_constraint_drop_safe('item_event_alert',
                               'item_event_alert_item_id_fkey');
ALTER TABLE item_event_alert
   ADD CONSTRAINT item_event_alert_item_id_fkey
   FOREIGN KEY (item_id) REFERENCES item_versioned (system_id) DEFERRABLE;

DROP INDEX IF EXISTS messaging_item_id;
DROP INDEX IF EXISTS item_event_alert_item_id;
CREATE INDEX item_event_alert_item_id
             ON item_event_alert (item_id);

DROP INDEX IF EXISTS messaging_item_stack_id;
DROP INDEX IF EXISTS item_event_alert_item_stack_id;
CREATE INDEX item_event_alert_item_stack_id
             ON item_event_alert (item_stack_id);

DROP INDEX IF EXISTS messaging_date_alerted;
DROP INDEX IF EXISTS item_event_alert_date_alerted;
CREATE INDEX item_event_alert_date_alerted
             ON item_event_alert (date_alerted);

/* ======================================================================== */
/* ======================================================================== */
/* Step (15) -- Miscellaneous tables                                        */
/* ======================================================================== */

/* FIXME: Would an index on the apache_event table be usefule? */
/*
SELECT cp_constraint_drop_safe('apache_event', 'enforce_valid_geometry');
ALTER TABLE apache_event ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(geometry));

DROP INDEX IF EXISTS apache_event_geometry;
-- This is the PostGIS 1.x way:
CREATE INDEX apache_event_geometry ON apache_event
  USING GIST (geometry GIST_GEOMETRY_OPS);
*/

/* ======================================================================== */
/* state_cities                                                             */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to state_cities.
\qecho

DROP INDEX IF EXISTS state_cities_state_name;
CREATE INDEX state_cities_state_name ON state_cities (state_name);

DROP INDEX IF EXISTS state_cities_municipal_name;
CREATE INDEX state_cities_municipal_name ON state_cities (municipal_name);

/* ======================================================================== */
/* state_city_abbrev                                                        */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to state_city_abbrev.
\qecho

SELECT cp_constraint_drop_safe('state_city_abbrev',
                               'state_city_abbrev_pkey');
ALTER TABLE state_city_abbrev
   ADD CONSTRAINT state_city_abbrev_pkey
   PRIMARY KEY (state_name, municipal_name, municipal_abbrev);

/* ======================================================================== */
/* state_counties                                                           */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to state_counties.
\qecho

DROP INDEX IF EXISTS state_counties_state_name;
CREATE INDEX state_counties_state_name ON state_counties (state_name);

DROP INDEX IF EXISTS state_counties_county_name;
CREATE INDEX state_counties_county_name ON state_counties (county_name);

/* ======================================================================== */
/* state_name_abbrev                                                        */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to state_name_abbrev.
\qecho

SELECT cp_constraint_drop_safe('state_name_abbrev',
                               'state_name_abbrev_pkey');
ALTER TABLE state_name_abbrev
   ADD CONSTRAINT state_name_abbrev_pkey
   PRIMARY KEY (state_name, state_abbrev);

/* ======================================================================== */
/* zipcodes_city                                                            */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to zipcodes.
\qecho

DROP INDEX IF EXISTS zipcodes_city;
CREATE INDEX zipcodes_city ON zipcodes (city);

DROP INDEX IF EXISTS zipcodes_state;
CREATE INDEX zipcodes_state ON zipcodes (state);

/* ======================================================================== */
/* ======================================================================== */
/* Step (16) -- Other tables                                                */
/* ======================================================================== */

/* NOTE: These other tables were not altered during the V2 upgrade. I'm [lb]
 *       including the code to recreate indices and constraints here in case
 *       someone needs this code someday, and also to have a record of what's
 *       indexed and constrained.
 */

/* ======================================================================== */
/* apache_event_session                                                     */
/* ======================================================================== */

/*

DROP INDEX IF EXISTS apache_event_session_time_end;
CREATE INDEX apache_event_session_time_end
   ON apache_event_session (time_end);
DROP INDEX IF EXISTS apache_event_session_time_start;
CREATE INDEX apache_event_session_time_start
   ON apache_event_session (time_start);
DROP INDEX IF EXISTS apache_event_session_user;
CREATE INDEX apache_event_session_user
   ON apache_event_session (user);

FIXME: This currently isn't set:

SELECT cp_constraint_drop_safe('apache_event_session',
                       'apache_event_session_user_fkey');
ALTER TABLE apache_event_session
   ADD CONSTRAINT apache_event_session_user_fkey
   FOREIGN KEY (user) REFERENCES user_ (username) DEFERRABLE;

*/

/* ======================================================================== */
/* async_locks                                                              */
/* ======================================================================== */

\qecho
\qecho Adding/Enabling constraints/indexes/triggers on async_locks.
\qecho

\qecho ... re-enabling triggers: async_locks

ALTER TABLE public.async_locks ENABLE TRIGGER async_locks_date_created_ic;

/* ======================================================================== */
/* key_value_pair                                                           */
/* ======================================================================== */

\qecho ... re-creating key_value_pair index

-- FIXME: Do this for V2 upgrade, but comment out in disable/enable scripts?

/* */
DROP INDEX IF EXISTS key_value_pair_key;
CREATE INDEX key_value_pair_key ON key_value_pair (key);

/* ======================================================================== */
/* log_event                                                                */
/* ======================================================================== */

/*

SELECT cp_constraint_drop_safe('log_event', 'log_event_username_fkey');
ALTER TABLE log_event
   ADD CONSTRAINT log_event_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;

\qecho ... re-enabling triggers: log_event

ALTER TABLE log_event ENABLE TRIGGER log_event_ic;
ALTER TABLE log_event ENABLE TRIGGER log_event_u;

*/

\qecho ... re-creating index: log_event_created

DROP INDEX IF EXISTS log_event_created;
/* 2014.05.08: Time: 31066.207 ms */
CREATE INDEX log_event_created ON log_event (created);

\qecho ... re-creating index: log_event_facility

DROP INDEX IF EXISTS log_event_facility;
/* 2014.05.08: Time: 351206.564 ms */
CREATE INDEX log_event_facility ON log_event (facility);

/* ======================================================================== */
/* log_event_kvp                                                            */
/* ======================================================================== */

/*

SELECT cp_constraint_drop_safe('log_event_kvp', 'log_event_kvp_event_id_fkey');
ALTER TABLE log_event_kvp
   ADD CONSTRAINT log_event_kvp_event_id_fkey
   FOREIGN KEY (event_id) REFERENCES log_event (id) DEFERRABLE;

\qecho ... re-enabling triggers: log_event_kvp

ALTER TABLE log_event_kvp ENABLE TRIGGER log_event_kvp_u;

*/

/* ======================================================================== */
/* ======================================================================== */
/* Step (17) -- Tile and Transit cache tables                               */
/* ======================================================================== */

/* ======================================================================== */
/* gtfsdb_cache_register                                                    */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to gtfsdb_cache_register.
\qecho

SELECT cp_constraint_drop_safe('gtfsdb_cache_register',
                               'gtfsdb_cache_register_username_fkey');
ALTER TABLE gtfsdb_cache_register
   ADD CONSTRAINT gtfsdb_cache_register_username_fkey
      FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;
DROP INDEX IF EXISTS gtfsdb_cache_register_username;
CREATE INDEX gtfsdb_cache_register_username
   ON gtfsdb_cache_register (username);

DROP INDEX IF EXISTS gtfsdb_cache_register_branch_id;
CREATE INDEX gtfsdb_cache_register_branch_id
   ON gtfsdb_cache_register (branch_id);

SELECT cp_constraint_drop_safe('gtfsdb_cache_register',
                               'gtfsdb_cache_register_revision_id_fkey');
ALTER TABLE gtfsdb_cache_register
   ADD CONSTRAINT gtfsdb_cache_register_revision_id_fkey
      FOREIGN KEY (revision_id) REFERENCES revision (id) DEFERRABLE;
DROP INDEX IF EXISTS gtfsdb_cache_register_revision_id;
CREATE INDEX gtfsdb_cache_register_revision_id
   ON gtfsdb_cache_register (revision_id);

/* FIXME: Need to index anything?? */

/* ======================================================================== */
/* gtfsdb_cache_links                                                       */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to gtfsdb_cache_links.
\qecho

SELECT cp_constraint_drop_safe('gtfsdb_cache_links',
                               'gtfsdb_cache_links_username_fkey');
ALTER TABLE gtfsdb_cache_links
   ADD CONSTRAINT gtfsdb_cache_links_username_fkey
      FOREIGN KEY (username) REFERENCES user_ (username) DEFERRABLE;
DROP INDEX IF EXISTS gtfsdb_cache_links_username;
CREATE INDEX gtfsdb_cache_links_username
   ON gtfsdb_cache_links (username);

DROP INDEX IF EXISTS gtfsdb_cache_links_branch_id;
CREATE INDEX gtfsdb_cache_links_branch_id
   ON gtfsdb_cache_links (branch_id);

DROP INDEX IF EXISTS gtfsdb_cache_links_revision_id;
CREATE INDEX gtfsdb_cache_links_revision_id
   ON gtfsdb_cache_links (revision_id);

/* FIXME: node_endpoint_id is currently TEXT ?
DROP INDEX IF EXISTS gtfsdb_cache_links_node_endpoint_id;
CREATE INDEX gtfsdb_cache_links_node_endpoint_id
   ON gtfsdb_cache_links (node_endpoint_id);
*/

/* FIXME: Need to index anything else?
 gtfs_caldate    | text    | not null
 node_endpoint_id   | text    | not null
 transit_stop_id | text    | not null
*/

/* ======================================================================== */
/* tiles_cache_byway_cluster                                                */
/* ======================================================================== */

\qecho
\qecho Adding constraints and indexes to tiles_cache_byway_cluster.
\qecho

/* MAYBE: This is exactly what tilecache_update.py does. Do we need to do it
          here, as well? A lot of other tables are being "fixed", i.e., this
          script could be a one-off script to fix existing tables in the
          minnesota database. Or we could maintain this script, effectively
          duplicating some stuff that's elsewhere. If we do keep this script
          current, at least it'll serve as documentation of how we've setup
          the database -- [lb] notes that setting indices properly does
          wonders for performance. */

DROP INDEX IF EXISTS tiles_cache_byway_cluster_cluster_name;
CREATE INDEX tiles_cache_byway_cluster_cluster_name
   ON tiles_cache_byway_cluster (cluster_name, branch_id);

DROP INDEX IF EXISTS tiles_cache_byway_cluster_label_priority;
CREATE INDEX tiles_cache_byway_cluster_label_priority
   ON tiles_cache_byway_cluster (label_priority);

SELECT cp_constraint_drop_safe(
         'tiles_cache_byway_cluster',
         'tiles_cache_byway_cluster_winningest_gfl_id_fkey');
ALTER TABLE tiles_cache_byway_cluster
   ADD CONSTRAINT tiles_cache_byway_cluster_winningest_gfl_id_fkey
   FOREIGN KEY (winningest_gfl_id)
   REFERENCES geofeature_layer(id) DEFERRABLE;

DROP INDEX IF EXISTS tiles_cache_byway_cluster_is_cycle_route;
CREATE INDEX tiles_cache_byway_cluster_is_cycle_route
   ON tiles_cache_byway_cluster (is_cycle_route);

SELECT cp_constraint_drop_safe('tiles_cache_byway_cluster',
                               'enforce_valid_geometry');
ALTER TABLE tiles_cache_byway_cluster ADD CONSTRAINT enforce_valid_geometry
   CHECK (IsValid(geometry));

/* */
DROP INDEX IF EXISTS tiles_cache_byway_cluster_geometry;
-- This is the PostGIS 1.x way:
-- CREATE INDEX tiles_cache_byway_cluster_geometry ON tiles_cache_byway_cluster
--    USING GIST (geometry GIST_GEOMETRY_OPS);
CREATE INDEX tiles_cache_byway_cluster_geometry ON tiles_cache_byway_cluster
   USING GIST (geometry);

/* ======================================================================== */
/* tiles_cache_clustered_byways                                             */
/* ======================================================================== */

/* Nothing to do. */

/* ======================================================================== */
/* tiles_mapserver_zoom                                                     */
/* ======================================================================== */

/* FIXME: Add this and tiles_mapserver_zooooom, tiles_mapserver_zooooom_2 ? */

/* ======================================================================== */
/* ======================================================================== */
/* Step (18) -- Work item tables                                            */
/* ======================================================================== */

/* ======================================================================== */
/* job_action                                                               */
/* ======================================================================== */

/* ======================================================================== */
/* job_status                                                               */
/* ======================================================================== */

/* ======================================================================== */
/* work_item                                                                */
/* ======================================================================== */

/* See item_table_system_id_add_constraints('work_item'), above */

/* ======================================================================== */
/* work_item_step                                                           */
/* ======================================================================== */

\qecho ... re-creating index: work_item_step_work_item_id

DROP INDEX IF EXISTS work_item_step_work_item_id;
CREATE INDEX work_item_step_work_item_id ON work_item_step (work_item_id);

/* ======================================================================== */
/* merge_job                                                                */
/* ======================================================================== */

\qecho ... re-creating index and constraint: merge_job

DROP INDEX IF EXISTS merge_job_for_group_id;
CREATE INDEX merge_job_for_group_id ON merge_job (for_group_id);

SELECT cp_constraint_drop_safe('merge_job',
                               'merge_job_for_revision_fkey');
ALTER TABLE merge_job
   ADD CONSTRAINT merge_job_for_revision_fkey
      FOREIGN KEY (for_revision) REFERENCES revision (id) DEFERRABLE;

/* ======================================================================== */
/* route_analysis_job                                                       */
/* ======================================================================== */

/* ======================================================================== */
/* conflation_job                                                           */
/* ======================================================================== */

/* FIXME: None of the job tables create any indices. Shouldn't we at least
          index the stack IDs of things? */

/* ======================================================================== */
/* ======================================================================== */
/* Step (n-3) -- Cleanup                                                    */
/* ======================================================================== */

DROP FUNCTION IF EXISTS item_table_system_id_add_constraints(
                              IN table_name TEXT,
                              IN parent_name TEXT);
DROP FUNCTION IF EXISTS index_drop_n_add(
                              IN table_name TEXT,
                              IN columns TEXT,
                              IN constraint_name TEXT);
DROP FUNCTION IF EXISTS constraint_drop_n_add(
                              IN table_name TEXT,
                              IN constraint_name TEXT,
                              IN the_constraint TEXT);

/* ======================================================================== */
/* ======================================================================== */
/* Step (n-2) -- Analyze                                                    */
/* ======================================================================== */

/* FIXME: Is this necessary?
ANALYZE;
*/

/* FIXME: Or this?
VACUUM ANALYZE;
*/

/* ======================================================================== */
/* ======================================================================== */
/* Step (n-1) -- Enable NOTICEs                                             */
/* ======================================================================== */

\qecho
\qecho Enabling noisy NOTICEs
\qecho

SET client_min_messages = 'notice';

/* ======================================================================== */
/* ======================================================================== */
/* Step (n) -- All done!                                                    */
/* ======================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

