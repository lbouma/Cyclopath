/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script updates public functions to use the new system ID
   and branch ID, to respek permissions, and creates a few convience fcns. */

\qecho 
\qecho This script updates public functions to use the new system ID
\qecho and branch ID, to respek permissions, and creates a few convience fcns.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
/* NOTE We need to set search_path to an instance (e.g., 'minnesota') so SQL 
        doesn't complain about missing geofeature table */
SET search_path TO public, minnesota;

/* ==================================================================== */
/* Step (1) -- Find *our* functions; examine them                       */
/* ==================================================================== */

/* If you log in to the SQL database and type

      \df

   you can see all the functions that're defined for each of the schemas.
   (Run \df+ if you want very verbose output.)

   If you find Cyclopath functions and examine them, you'll find that 
   some of them reference renamed columns or archived tables -- this 
   latter problem is fine (Postgres'll still find the tables when the 
   function is run) and the former is not fine, since Postgres will 
   throw an exception, complaining the column doesn't exist.

   So, while Postgres enforces dependencies between Tables, Views, and 
   Columns, it does not do so to functions -- rather, it is our 
   responsibilty to find and maintain these functions. (If you use pg_dump, 
   you'll also see that functions are defined first, before the tables 
   even exist.)

   When you run \df, you'll see three schemas: minnesota, pg_catalog, and
   public. All fcns. in the minnesota schema are ours, none of the functions 
   in the pg_catalog schema are ours, and only some of the public schema 
   functions are ours (most of them are PostGIS's).
   
   For reference, I'm listing parts of the Cyclopath schema here. This list was
   gathered manually using pg_dump and grepping for 'create', and also by 
   grepping /scripts/schema/ for 'create function' and 'replace function',
   since digging through the public schema for our functions is tedious.

   In this script, we just tackle the public schema; we leave instance schema 
   functions for a later script.

   ==================================================
   Public schema / V1

FIXME: Document these better. Maybe also rename all to cp_*?
      FIXME: Search for 'CREATE FUNCTION' in V2 scripts and change all to cp_*?

      User_ fcns:

         FIXME: Prefix with cp_user_*?

         salt_new                   generates default value for user_.salt

         pw_hash                    used by login_ok and password_set

         password_set               hooked from mediawiki when creating user

         login_ok                   hooked from mediawiki when logging in user
         
         user_alias_set             insert trigger on user_
         
         cp_user_id                 returns user's user ID

      Group fcns:

         cp_group_basemap_owners_id

         cp_group_public_id

         cp_group_private_id

         cp_group_private_id_sloppy

         cp_group_session_id

         cp_group_stealth_id

      Branching fcns:

         cp_branch_baseline_id

      Enumeration helpers:

         cp_access_level_id

         cp_access_scope_id

         cp_access_style_id

         cp_item_type_id

      Revisions fcns:

         cp_rid_inf

      Instance-related fcns:

         cp_register_view_geometry  registers geometry columns with PostGIS 
                                    for the active instance

         cp_srid                    returns the SRID of the active instance
                                    (e.g., 26915 for minnesota, 26913 for co.)

      Geometry helpers:

         bbox_text                  (converts a GEOMETRY into a TEXT)

      Aggregate fcns:

         group_concat (Aggregate)   Emulate MySQL's GROUP_CONCAT (like MAX(*) 
                                    or COUNT(*), but makes comma-separated list
                                    of GROUP-BYed rows).

      SQL trigger fcns:

         FIXME: Prefix with cp_trigger_*?

         fail                       used by update triggers to raise exception
                                    on tables that should only be appended 
                                    (whose rows shouldn't change once added)

         set_created                used for insert triggers; sets the 
                                    'created' column

         set_last_modified          used for insert and update triggers;
                                    sets the 'last_modified' column

      Obsolete Discussions fcns:

         NOTE: Discussions fcns. are being implemented in pyserver, or dropped
               altogether.
               - Some of the fcns. are used as column values in a SELECT, but 
                 the fcn. might always return the same value for every row,
                 in which case the speed of the operation is unneccessarily
                 impacted. (That is, Postgres runs the fcn. for each column of
                 each row, so it cannot optimize.)
               - The fcns. themselves are harder to manage if they're 
                 hard-coded SQL fcns. By moving them to pyserver, they're much
                 easier to maintain.
               - Because of user permissions, most of these fcns. are broken. 
                 And because of user permissions, most of these fcns. cannot 
                 be reimplemented as SQL functions.

         contains_text
         
         contains_user
         
         intersects_geom
         
         unread_posts
         
         total_posts
         
         lp_user
         
         lp_ts
         
         format_ts
         
         references_gf
         
         n_attached_threads
         
         n_attached_posts
         
         n_after_last_read

      Unused/Unneeded/Stale fcns:
      
         fix               (used to make populate annotation and annot_bs)

         build_tag_history (used to convert old byway_segment_[tagname] tables 
                            to tag and tag_bs tables; should have been dropped 
                            when byway_segment_* tables were dropped)

         guess_speed_limit (created by and only used in 
                            scripts/sql/guess-speed-limits.sql)

         wh_extend         (from work_hints experiment)

         wh_still_a_wh     (from work_hints experiment)

      Unknown fcns:

         FIXME: This fcn. might have been created by a script that was checked 
                into cp-scholarly.

         rp_gf_current        (in Cyclopath V1 pg_dump only; cannot find 
                               original code that created this function)
         2012.08.16: There was unused code in flashclient alongside a function
         that uses gf_deleted: the following parameter was gf_current, but it 
         was never specifed by any callers. So it's been since deleted. And 
         [lb] is not sure what its purpose was to be. But it was related to 
         link_values for posts... a/k/a link_posts.

         rp_popularity_filter (cannot find declaration in source code;
                               used by rp_region_new)
         rp_region_new        (in V1 schema; cannot find definition)

*/

/* ==================================================================== */
/* Step (2) -- Define function for looking up access infer ID           */
/* ==================================================================== */

\qecho 
\qecho Creating access_infer ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. */
CREATE FUNCTION public.cp_access_infer_id(IN infer_name TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      access_infer_id_ INTEGER;
   BEGIN
      EXECUTE 'SELECT id FROM access_infer 
                  WHERE infer_name = ''' || infer_name || ''';'
         INTO STRICT access_infer_id_;
      RETURN access_infer_id_;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (2) -- Define function for retrieving access level by name      */
/* ==================================================================== */

\qecho 
\qecho Creating access_level ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. */
CREATE FUNCTION public.cp_access_level_id(IN desc_ TEXT)
   RETURNS INTEGER AS $$
   BEGIN
      -- FIXME This might not work where, given the table specified before 
      --       creation?
      RETURN (SELECT id FROM access_level WHERE description = desc_);
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (3) -- Define function for looking up access scope ID           */
/* ==================================================================== */

\qecho 
\qecho Creating access_scope ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. */
CREATE FUNCTION public.cp_access_scope_id(IN scope_name TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      access_scope_id_ INTEGER;
   BEGIN
      EXECUTE 'SELECT id FROM access_scope 
                  WHERE scope_name = ''' || scope_name || ''';'
         INTO STRICT access_scope_id_;
      RETURN access_scope_id_;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (3) -- Define function for looking up access style ID           */
/* ==================================================================== */

\qecho 
\qecho Creating access_style ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. */
CREATE FUNCTION public.cp_access_style_id(IN style_name TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      access_style_id_ INTEGER;
   BEGIN
      EXECUTE 'SELECT id FROM access_style 
                  WHERE style_name = ''' || style_name || ''';'
         INTO STRICT access_style_id_;
      RETURN access_style_id_;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (4) -- Re-define public functions                               */
/* ==================================================================== */

\qecho 
\qecho Fixing '''geofeature''' functions
\qecho 

/* NOTE: We'll fix has_tag() in a later script. */

\qecho 
\qecho Dropping function: revision_geometry
\qecho 

DROP FUNCTION revision_geometry(INTEGER);

/* NOTE: We are not re-creating this fcn., e.g., as cp_revision_geometry.
 *       This fcn. is being moved to pyserver. 
 *
 *       See pyserver/util_/revision.py,
 *       and scripts/setupcp/populate_revision_geo.py
 */

/* ==================================================================== */
/* Step (5) -- Define function for retrieving item type id by name      */
/* ==================================================================== */

\qecho 
\qecho Creating item_type ID convenience function
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* Remember: Fcns that use select used within another select are costly. */
CREATE FUNCTION cp_item_type_id(IN type_name_ TEXT)
   RETURNS INTEGER AS $$
   BEGIN
      RETURN (SELECT id FROM item_type WHERE type_name = type_name_);
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (6) -- Define function for retrieving user ID by username       */
/* ==================================================================== */

\qecho 
\qecho Creating username->id convenience function
\qecho 

DROP FUNCTION IF EXISTS user_id(TEXT);

CREATE FUNCTION cp_user_id(TEXT)
   RETURNS INT
   LANGUAGE SQL STABLE
   AS $$
      SELECT id FROM user_ WHERE username = $1 LIMIT 1;
   $$;

/* ==================================================================== */
/* Step (7) -- Drop unused, unnecessary, or unneeded fcns.              */
/* ==================================================================== */

\qecho 
\qecho Dropping unused fcns.
\qecho 

/* from 014-annotations.sql */
DROP FUNCTION fix(bid INT, thecomments TEXT);

/* from 045-tag-history.sql */
DROP FUNCTION build_tag_history(tag_name TEXT, flag_name TEXT);

DROP FUNCTION guess_speed_limit(IN type_code CHARACTER VARYING, 
                                IN geometry GEOMETRY);

DROP FUNCTION wh_extend(line IN GEOMETRY, IN len INTEGER, IN dir INTEGER);

DROP FUNCTION wh_still_a_wh(IN wh_id integer);

/* from... no where; only found in V1 schema; cannot locatate orig. source. */
DROP FUNCTION rp_gf_current(IN id_ INTEGER, IN version_ INTEGER);

DROP FUNCTION rp_popularity_filter(IN id_ INTEGER);

DROP FUNCTION rp_region_new();

\qecho 
\qecho Dropping Discussions fcns.
\qecho 

DROP FUNCTION contains_text(tid INT, txt TEXT);
DROP FUNCTION contains_user(tid INT, u TEXT);
DROP FUNCTION intersects_geom(tid INT, geom GEOMETRY);
DROP FUNCTION unread_posts(tid INT, u TEXT);
DROP FUNCTION total_posts(tid INT);
DROP FUNCTION lp_user(tid INT);
DROP FUNCTION lp_ts(tid INT);
DROP FUNCTION format_ts(ts TIMESTAMP WITH TIME ZONE);
DROP FUNCTION references_gf(tid INT, gfid INT);
DROP FUNCTION n_attached_threads(gfid INT);
DROP FUNCTION n_attached_posts(gfid INT, r INT);
DROP FUNCTION n_after_last_read(pid INT, u TEXT);

\qecho 
\qecho Dropping Reaction fcns.
\qecho 

/* BUG nnnn: FIXME: Drop all this and remake in Python... for numerous reasons:
                    1. hard to maintain, 2. slow, 3. obscure, etc... */

/* FIXME: reactions. Drop these once you've recreated them in pyserver.
DROP FUNCTION unread_posts(tid INT, u TEXT);
DROP FUNCTION total_polarity(tid INT);
*/
DROP FUNCTION is_social_rev(rid INT);
/*
DROP FUNCTION total_posts(tid INT);
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

