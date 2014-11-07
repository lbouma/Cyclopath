/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script can be used to scrub the database of private user data, so you
   (the developer) can copy the database to a laptop or a home development
   machine and not have to worry about (per University and Federal policy
   regarding protecting human subjects). */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\set anonymize_apache_table FALSE

/* FIXME: Make a special schema-upgrade.py for the anon scripts, so you don't
 *        have to change their name in the scripts folder to run them.
 *        Also: write a script to drop indices, constraints, and foreign keys,
 *        and see if that has an impact on the runtime of this script (I [lb]
 *        actually kind of doubt it, so maybe don't both with the script
 *        unless, though such a script would still be useful in the future for
 *        large database operations (and would complement the script we already
 *        have that re-creates the indices, constraints, and foreign keys. */

\qecho
\qecho This script strips the database of private user information for research
\qecho subjects (developer user information is retained, i.e., your login and
\qecho mine).
\qecho
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 45.28 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 10.43 mins. (incl. mn. and co.).]
\qecho
\qecho FIXME: The script time ballooned. See previous script: probably need
\qecho        to drop more indices in 020-anonymize-prepare2.sql. Or maybe
\qecho        drop fewer indices? Hrmm....
\qecho [EXEC. TIME: 2013.02.13/Huffy: ~ 537.03 mins. [runic; mn lite db]]
\qecho

/* FIXME: Can this script's execution time be drastically shortened? */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO. */
/* If you don't sqelch the verbosity, the output is super, super long. */
\set VERBOSITY terse
--SET client_min_messages TO NOTICE;
--SET client_min_messages TO INFO;
-- NOTE: DEBUG and LOG levels cause SQL to be printed
--SET client_min_messages TO DEBUG;

/* ==================================================================== */
/* Step (1.1) -- Create the anonymous user.                             */
/* ==================================================================== */

\qecho
\qecho Maybe creating anonymous user...
\qecho

CREATE FUNCTION add_anon_user()
   RETURNS VOID AS $$
   DECLARE
      uname TEXT;
   BEGIN
      BEGIN
         EXECUTE 'SELECT username
                     FROM user_
                     WHERE username = ''_user_anon_@@@instance@@@'';'
            INTO STRICT uname;
         RAISE DEBUG '.... nope!';
      EXCEPTION WHEN no_data_found THEN
         /* CCPV1 */
         RAISE DEBUG '....  yup!';
         INSERT INTO user_
            (username, email, login_permitted,
             enable_wr_email, enable_wr_digest,
             enable_email, enable_email_research, dont_study)
            VALUES ('_user_anon_@@@instance@@@', NULL, TRUE,
                    FALSE, FALSE,
                    FALSE, FALSE, FALSE);
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT add_anon_user();

DROP FUNCTION add_anon_user();

/* ==================================================================== */
/* Step (1.2) -- Create a bunch of helper fcns.                         */
/* ==================================================================== */

\qecho
\qecho Creating helper fcns.
\qecho

/* Third-level fcns.: these are called to scrub the individual tables. */

CREATE FUNCTION scrub_edited_user(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'UPDATE item_revisionless
               SET edited_user = ''_user_anon_@@@instance@@@''
               WHERE edited_user = ''' || uname || ''';';
      EXECUTE 'UPDATE group_item_access
               SET created_by = ''_user_anon_@@@instance@@@''
               WHERE created_by = ''' || uname || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_log_event(IN uname TEXT)
   RETURNS VOID AS $$
   DECLARE
      log_event_rec RECORD;
   BEGIN
      /* NOTE: In plpgsql, you can get away with a SELECT without wrapping it
               in an EXECUTE sometimes, but not always. E.g., if uname were
               guaranteed to be alpha-only, SELECT .... WHERE usarename = uname
               works (not that uname in unquoted). But if uname contain numbers
               and letters, postgres is not pleased. So always use EXECUTE,
               just to avoid silly issues. */
      FOR log_event_rec IN
         EXECUTE '
            SELECT id FROM log_event
            WHERE username = ''' || uname || ''' ORDER BY id ASC'
      LOOP
         RAISE DEBUG '.... log_event_kvp: event_id: %', log_event_rec.id;
         DELETE FROM log_event_kvp
            WHERE event_id = log_event_rec.id;
      END LOOP;
      RAISE DEBUG '.... log_event';
      EXECUTE 'DELETE FROM log_event
               WHERE username = ''' || uname || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_revision(IN uname TEXT, IN ualias TEXT)
   RETURNS VOID AS $$
   DECLARE
      rev_fb_rec RECORD;
   BEGIN
      FOR rev_fb_rec IN
         EXECUTE '
            SELECT id FROM revision_feedback
            WHERE username = ''' || uname || ''' ORDER BY id ASC'
      LOOP
         RAISE DEBUG '.... revision_feedback_link: rf_id: %', rev_fb_rec.id;
         DELETE FROM revision_feedback_link
            WHERE rf_id = rev_fb_rec.id;
      END LOOP;
      RAISE DEBUG '.... revision_feedback';
      EXECUTE 'DELETE FROM revision_feedback
               WHERE username = ''' || uname || ''';';
      /* NOTE I'm not sure if we should delete from revision, so let's
              just redact the username. */
      RAISE DEBUG '.... revision';
      /* First, anonymize the user's I.P. address. */
      EXECUTE 'UPDATE revision SET host = ''0.0.0.0''::INET
               WHERE username = ''' || uname || ''';';
      /* I wanted to replace username w/ alias but that doesn't jive with the
         foreign key constraint.
      UPDATE revision SET username = ualias WHERE username = uname;
      */
      EXECUTE 'UPDATE revision
               SET username = ''_user_anon_@@@instance@@@''
               WHERE username = ''' || uname || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_route_or_track(IN uname TEXT, IN tbl_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      access_level_owner INTEGER;
      gia_rec RECORD;
      sel TEXT;
      access_scope_private INTEGER;
   BEGIN
      /* We could go through and scrub routes that are private and not public
         (shared routes have 'client' access assigned to the public group),
         but this still leaves beg_addr, fin_addr, host, and session_id.
         I think we can safely leave beg_addr and fin_addr if we scrub host
         and session_id -- though I'm not sure about session_id, it might be
         used for deep-linking, but my understanding is that it's related
         moreso to the user. */
      /* NOTE This approache leaves a little gunk in the database, but it's not
              a big deal. There are group_item_access rows w/ 'owner' access to
              routes, but the group_ids reference groups that will have been
              deleted. However, this reveals no user information, and it won't
              crash pyserver, so there's no harm leaving it, other than disk
              space usage, which is insignificant and inconsequential, really.
              */
      RAISE DEBUG '.... finding %s', tbl_name;
      BEGIN
         /* CCPV2 */
         /* FIXME: I [lb] think we should scrub all routes/tracks, and not just
                   private ones. Delete this code if so.
         access_level_owner := cp_access_level_id('owner');
         access_scope_private := cp_access_scope_id('private');
                  JOIN group_ AS gr
                     ON (gr.stack_id = gm.group_id
                         AND gr.access_scope_id =
                             ' || access_scope_private || ')
                  WHERE
                     u.username = ''' || uname || '''
                     AND gia.access_level_id = ' || access_level_owner || ''
         */
         FOR gia_rec IN
            EXECUTE'
               SELECT gia.item_id, gia.stack_id
                  FROM user_ AS u
                  JOIN group_membership AS gm
                     ON (gm.user_id = u.id)
                  JOIN group_ AS gr
                     ON (gr.stack_id = gm.group_id)
                  JOIN group_item_access AS gia
                     ON (gia.group_id = gr.stack_id)
                  JOIN ' || tbl_name || ' AS gf
                     ON (gf.system_id = gia.item_id)
                  WHERE
                     u.username = ''' || uname || ''''
         LOOP
            RAISE DEBUG '.... %s: %:%',
                        tbl_name, gia_rec.stack_id, gia_rec.item_id;
            EXECUTE 'UPDATE ' || tbl_name || '
                     SET host = ''0.0.0.0''::INET
                     WHERE system_id = ' || gia_rec.item_id || ';';
            /* 2013.02.12: The created_by column was removed from the route and
                           track tables when the item_stack table was created.
                  EXECUTE 'UPDATE ' || tbl_name || '
                           SET created_by = ''_user_anon_@@@instance@@@''
                           WHERE system_id = ' || gia_rec.item_id || ';';
            */
            /* FIXME: The session_id column should be dropped. It was moved to
             *         group_item_access. */
            IF tbl_name = 'route' THEN
               EXECUTE 'UPDATE ' || tbl_name || '
                        SET session_id = ''''
                        WHERE system_id = ' || gia_rec.item_id || ';';
               /* FIXME: What about route_stop? I.e., the 'name' of the
                *        route stop might be revealing. */
            END IF;
         END LOOP;
         /* Scrubbing route_view is outside of the loop because anyone can
          * view public routes of anyone else. */
         IF EXISTS (SELECT * FROM pg_tables
                    WHERE schemaname='@@@instance@@@'
                          AND tablename = 'item_findability') THEN
            EXECUTE 'DELETE FROM item_findability
                     WHERE username = ''' || uname || ''';';
         END IF;
      EXCEPTION WHEN undefined_function THEN
         /* CCPV1 */
         EXECUTE 'UPDATE ' || tbl_name || '
                  SET host = ''0.0.0.0''::INET
                  WHERE owner_name = ''' || uname || ''';';
         IF tbl_name = 'route' THEN
            EXECUTE 'UPDATE ' || tbl_name || '
                     SET session_id = ''''
                     WHERE owner_name = ''' || uname || ''';';
         END IF;
         EXECUTE 'UPDATE ' || tbl_name || '
                  SET owner_name = ''_user_anon_@@@instance@@@''
                  WHERE owner_name = ''' || uname || ''';';
      END;
      /* Since we're leaving the route or track, no need to touch
         route_parameters, route_step, or track_point, but we'll still scrub
         route_feedback. And the newer (circa 2012) route_feedback_drag. */
      IF tbl_name = 'route' THEN
         RAISE DEBUG '.... route_feedback: %', uname;
         /* MAYBE: We could probably just change the username to
          *        _user_anon_@@@instance@@@, or are people's comments
          *        considered too private for laptop devs? */
         EXECUTE 'DELETE FROM route_feedback
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM route_feedback_stretch
                  WHERE feedback_drag_id IN (
                     SELECT id FROM route_feedback_drag
                     WHERE username = ''' || uname || ''');';
         EXECUTE 'DELETE FROM route_feedback_drag
                  WHERE username = ''' || uname || ''';';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_group(IN uname TEXT)
   RETURNS VOID AS $$
   DECLARE
      group_rec RECORD;
      access_scope_private INTEGER;
   BEGIN
      BEGIN
         RAISE DEBUG '.... finding groups: %', uname;
         access_scope_private := cp_access_scope_id('private');
         FOR group_rec IN
            EXECUTE '
               SELECT *
                  FROM group_
                  WHERE name = ''' || uname || '''
                        AND access_scope_id = ' || access_scope_private || ''
         LOOP
            RAISE DEBUG '.... group: %:%:%', group_rec.stack_id,
                                             group_rec.name,
                                             group_rec.access_scope_id;
            /* Find any items this group owns and delete them. The only
               owner-items in group_item_access so far (after the schema
               upgrade) are routes and private regions and their annotations
               and links. */
            RAISE DEBUG '.... link_value';
            PERFORM scrub_group_private(
                        group_rec.stack_id, 'link_value', 'link_value', '');
            RAISE DEBUG '.... annotation';
            PERFORM scrub_group_private(
                        group_rec.stack_id,
                           'annotation', 'annotation', 'attachment');
            RAISE DEBUG '.... region';
            PERFORM scrub_group_private(
                        group_rec.stack_id, 'region', '', 'geofeature');
            /* Don't scrub routes; see above.
            PERFORM scrub_group_private(
                        group_rec.stack_id, 'route', 'route', 'geofeature');
            */
            -- FIXME Not sure I should be deleting group_revision...
            --       Maybe just re-assign to dummy or public group?
            -- FIXME Do normal revisions get a group_revision? That is, check
            --       that all revisions have a group_revision item... old
            --       revisions should all get two group_revisions: one
            --       connecting the public group and another connecting the
            --       private group.
            RAISE DEBUG '.... group_revision';
            DELETE FROM group_revision AS gr
               WHERE gr.group_id = group_rec.stack_id;
            RAISE DEBUG '.... group_item_access';
            DELETE FROM group_item_access AS gia
               WHERE gia.group_id = group_rec.stack_id;
            RAISE DEBUG '.... group_membership (private)';
            DELETE FROM group_membership WHERE group_id = group_rec.stack_id;
            -- Bug 1976 -- DELETE FROM group_policy ...
            RAISE DEBUG '.... group_';
            DELETE FROM group_ WHERE stack_id = group_rec.stack_id;
         END LOOP;
         RAISE DEBUG '.... route_feedback';
         EXECUTE 'DELETE FROM route_feedback
                  WHERE username = ''' || uname || ''';';
         /* Public group_membership */
         RAISE DEBUG '.... group_membership (public)';
         EXECUTE 'DELETE FROM group_membership
                  WHERE username = ''' || uname || ''';';
      EXCEPTION WHEN undefined_function THEN
         /* No-op for CCPV1. */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_group_private(IN group_id_ INTEGER,
                                    IN item_type TEXT,
                                    IN table_child TEXT,
                                    IN table_parent TEXT)
   RETURNS VOID AS $$
   DECLARE
      -- access_level_owner INTEGER;
      gia_rec RECORD;
      item_type_id_ INTEGER;
   BEGIN
      /* 2013.04.09: We should scrub all private user GIA records, right?
      access_level_owner := cp_access_level_id('owner');
         */
      item_type_id_ := cp_item_type_id(item_type);
      FOR gia_rec IN
         SELECT * FROM group_item_access AS gia
            WHERE gia.group_id = group_id_
                  AND gia.item_type_id = item_type_id_
                  -- AND gia.access_level_id = access_level_owner
      LOOP
         RAISE DEBUG '.... private %:%:%', item_type, table_child,
            table_parent;
         IF table_child != '' THEN
            EXECUTE 'DELETE FROM ' || table_child || '
                        WHERE system_id = ' || gia_rec.item_id || '';
         END IF;
         IF table_parent != '' THEN
            EXECUTE 'DELETE FROM ' || table_parent || '
                        WHERE system_id = ' || gia_rec.item_id || '';
         END IF;
         RAISE DEBUG '.... item_versioned';
         DELETE FROM item_versioned WHERE system_id = gia_rec.item_id;
         RAISE DEBUG '.... group_item_access';
         DELETE FROM group_item_access WHERE item_id = gia_rec.item_id;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_tag_preference(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'DELETE FROM tag_preference
               WHERE username = ''' || uname || ''';';
      EXECUTE 'DELETE FROM tag_preference_event
               WHERE username = ''' || uname || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_byway_rating(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'DELETE FROM byway_rating
               WHERE username = ''' || uname || ''';';
      EXECUTE 'DELETE FROM byway_rating_event
               WHERE username = ''' || uname || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_item_watcher(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         /* CCPV2 */
/* BUG nnnn: Need script to go through existing old item_watcher table and make
 * new items for everyone. Probably easier to do using Python than to do in
 * SQL. */
         /*
         EXECUTE 'DELETE FROM item_watcher
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM item_read_event
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM watcher_events
                  WHERE username = ''' || uname || ''';';
         */
         /* FIXME: Item Watchers are now Attributes.
                   So now we want to scrub private link_values
                   owned by non-devs.
         See also: item_event_read
                   item_event_alert
         */
         EXECUTE 'DELETE FROM item_event_read
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM item_event_alert
                  WHERE username = ''' || uname || ''';';
      EXCEPTION WHEN undefined_table THEN
         /* CCPV1 */
         EXECUTE 'DELETE FROM region_watcher
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM thread_read_event
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM thread_watcher
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM tw_email_pending
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM watch_region
                  WHERE username = ''' || uname || ''';';
         EXECUTE 'DELETE FROM wr_email_pending
                  WHERE username = ''' || uname || ''';';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_apache_tables(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      RAISE NOTICE '....scrubbing apache_event_*';
      /* Delete from the apache_event table, which may or may not exist
         (developers generally don't copy this Very Large table). */
      BEGIN
         EXECUTE 'DELETE FROM apache_event
                  WHERE username = ''' || uname || ''';';
      EXCEPTION WHEN undefined_table THEN
         /* No-op */
      END;
      /* Delete from the user support tables. */
      EXECUTE 'DELETE FROM apache_event_session
               WHERE user_ = ''' || uname || ''';';
      RAISE NOTICE '....done with apache_event_*';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_routing_analytics(IN uname TEXT)
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         /* FIXME: To implement, do a delete from with a select.
          *        But route analytics is for planners, so not
          *        as sensitive if we leave some of this in....
         EXECUTE 'DELETE FROM analysis_status
                  WHERE username = ''' || uname || ''';';
                   For now, just delete all.
         */
         DELETE FROM analysis_status;
         EXECUTE 'DELETE FROM analysis_request
                  WHERE username = ''' || uname || ''';';
      EXCEPTION WHEN undefined_table THEN
         /* No-op */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* The second-level fcn., which calls the third-level fcns. */

CREATE FUNCTION scrub_users_rows(IN uname TEXT,
                                 IN uid INTEGER,
                                 IN ualias TEXT,
                                 IN include_apache_table BOOLEAN)
   RETURNS VOID AS $$
   BEGIN
      RAISE NOTICE '.. %', ualias;
      PERFORM scrub_edited_user(uname);
      PERFORM scrub_log_event(uname);
      PERFORM scrub_revision(uname, ualias);
      PERFORM scrub_route_or_track(uname, 'route');
      PERFORM scrub_route_or_track(uname, 'track');
      PERFORM scrub_group(uname);
      RAISE DEBUG '.... tag_pref, byway_rat, item_w, user';
      PERFORM scrub_tag_preference(uname);
      PERFORM scrub_byway_rating(uname);
      PERFORM scrub_item_watcher(uname);
      IF (include_apache_table) THEN
         PERFORM scrub_apache_tables(uname);
      END IF;
      PERFORM scrub_routing_analytics(uname);
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* The top-level fcn., which gets the user record. */

/* FIXME Make sure user's can register _underscore-prefixed usernames */

CREATE FUNCTION scrub_users(IN include_apache_table BOOLEAN)
   RETURNS VOID AS $$
   DECLARE
      user_rec RECORD;
   BEGIN
      /* NOTE: Postgres complains if you use a delimited backslash, e.g.,
       *          WARNING:  nonstandard use of \\ in a string literal
       *       So we use the escape string instead. */
      FOR user_rec IN
         SELECT username, id, alias FROM user_
            WHERE username NOT LIKE E'\\_%'
               AND dont_study = FALSE
            ORDER BY username ASC
      LOOP
         PERFORM scrub_users_rows(user_rec.username,
                                  user_rec.id,
                                  user_rec.alias,
                                  include_apache_table);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (2) -- Do It To It                                              */
/* ==================================================================== */

\qecho
\qecho Scrubbing users
\qecho

/* 2012.04.19: If your dump includes the apache table, this is really slow,
  like, 30 seconds per user! Well, more like 9 users scrubbed in 4 minutes,
  or 32.87407407407407 hours. If you exclude apache tables, this'll be quicker,
  on the order of 26 users per minute.
   >>> (4438.0/26.0)*60.0/60.0/60.0 = 2.84 hours is more like it.
*/

SELECT scrub_users(:anonymize_apache_table);
-- TESTING:
--SELECT scrub_users_rows('003cml', 1913, 'xiomara_mcglothin');
--SELECT scrub_users_rows('10kirs', 290, 'rufus_greenstreet');

/* NOTE: We're ignoring group_item_access.session_id: this value
         doesn't seem revealing, since it's a random UUID. */

\qecho
\qecho Cleaning up
\qecho

DROP FUNCTION scrub_users(IN include_apache_table BOOLEAN);
DROP FUNCTION scrub_users_rows(IN uname TEXT,
                               IN uid INTEGER,
                               IN ualias TEXT,
                               IN include_apache_table BOOLEAN);
DROP FUNCTION scrub_routing_analytics(IN uname TEXT);
DROP FUNCTION scrub_apache_tables(IN uname TEXT);
DROP FUNCTION scrub_item_watcher(IN uname TEXT);
DROP FUNCTION scrub_byway_rating(IN uname TEXT);
DROP FUNCTION scrub_tag_preference(IN uname TEXT);
DROP FUNCTION scrub_group_private(IN group_id_ INTEGER,
                                  IN item_type TEXT,
                                  IN table_child TEXT,
                                  IN table_parent TEXT);
DROP FUNCTION scrub_group(IN uname TEXT);
DROP FUNCTION scrub_route_or_track(IN uname TEXT, IN tbl_name TEXT);
DROP FUNCTION scrub_revision(IN uname TEXT, IN ualias TEXT);
DROP FUNCTION scrub_log_event(IN uname TEXT);
DROP FUNCTION scrub_edited_user(IN uname TEXT);

/* ==================================================================== */
/* Step (3) -- Scrub the Dec 2010 Experiment (Better CP)                */
/* ==================================================================== */

/* # ** begin-compliance */

\qecho
\qecho Scrubbing compliance experiment.
\qecho

CREATE FUNCTION scrub_experiment()
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         DROP VIEW c_user_revisions;
         DROP TABLE c_trial_big CASCADE;
         DROP TABLE c_trial_small CASCADE;
         DROP TABLE c_user_group CASCADE;
         DROP TABLE c_viewport CASCADE;
      EXCEPTION WHEN undefined_table THEN
         /* No-op: Does not apply to Colorado */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT scrub_experiment();

DROP FUNCTION scrub_experiment();

/* # ** end-compliance */

/* ==================================================================== */
/* Step (4) -- Scrub later-CcpV1 stuff.                                 */
/* ==================================================================== */

/* 2014.01.25: This table no longer exists... see: item_findability.

Failed after:
Anonymize ccpv3_anon database: 2152.00 mins.
Ug! Almost 36 hours!

\qecho
\qecho Scrubbing reaction_reminder.
\qecho

DELETE FROM reaction_reminder;

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

