/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script populates group_item_access with users' private items. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script populates group_item_access with users'' private items.
\qecho
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 29.00 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~  0.31 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   1.54 min. [mn]]
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

\qecho
\qecho The public base map branch ID:
SELECT cp_branch_baseline_id();
\qecho

/* ==================================================================== */
/* Step (1) -- Consume private comments from watch regions and tracks   */
/* ==================================================================== */

/* NOTE In an earlier script, we made watch regions into geofeatures.
        However, the watch regions are not versioned, nor revisioned --
        that is, each watch region's valid_start_rid is 0, and each watch
        region's version is 0. We also haven't consumed watch region comments
        yet, since we want to associate those to the user who wrote them.

        Regarding revisioning old items that have never been revisioned, there
        are a few approaches.

         (1) We could insert the items in revision control such that they
             temporally relate to existing items. That is, if the system was
             at revision 100 and a user made a watch region, the system didn't
             make a new revision, it just gave the watch region a special
             revision of 0. Now, suppose the system is at revision 200 and
             we want to revision the watch region. If we know the watch region
             was created at revision 100, we could renumber revisions 101 to
             200 as revisions 102 to 201, and then we could apply revision 101
             to that watch region.
         (a) Are revision such blessed objects that we shouldn't renumber them?
             People get emails about revision changes, so all of the old emails
             would be invalid. I can't think of any other effect, though.
         (b) Unfortunately, watch regions don't have a creation timestamp, so
             we'd have to scour the apache logs to gather this info. This seems
             like not enough work without enough gain.

         (2) We could create new revisions at the end of the sequence and
             assign the watch region a new, fresh revision.
         (a) It will appear to the user that the watch region was only recently
             created, which it kind of was -- that is, the old watch region
             isn't the same as the new one, since one is under revision control
             and the other isn't.

        Obviously, (2) seems like the best choice: it's easy to implement and
        easy for users to understand. The first option, (1), also kind of feels
        like cheating -- we shouldn't insert items into the revision timeline
        after the fact, since that's like rewriting history, and this is a
        truthful Geowiki we're trying to build here.

        Note that the revision we create for the watch region can also be used
        on more than one item. For any given user, that user might have defined
        more than one watch region. Furthermore, each region might have some
        notes attached, for which we need to make private annotations.

        Thusly, the remaining tasks on watch regions are:

         (1) Make a revision for each user with one or more private regions
         (2) Update watch regions in the database, setting valid start rid
         (3) Make new annotations and link_values for any comments
         (4) Make private group-items for each region, annotation, and link
         (5) Make a group-revision entry for the changes
         (6) After all watch regions are processed, remove that designation
             from the geofeature_layer table, since watch regions are now
             just a set of private items -- geofeature regions, attachment
             annotations, and annotation-region link_values. */

/* ==================================================================== */
/* Step (1)(a) -- Setup helper functions                                */
/* ==================================================================== */

\qecho
\qecho Creating helper functions
\qecho

/* XREF See also attachment_make_public() in 102-apb-56-groups-pub_inst.sql */
CREATE FUNCTION group_item_create(IN item_system_id INTEGER,
                                  IN username TEXT,
                                  IN item_type_id_ INTEGER,
                                  IN access_level_id_ INTEGER)
   RETURNS VOID AS $$
   DECLARE
      group_private_id INTEGER;
   BEGIN
      --RAISE INFO '...group_item_create: % / % / % / %',
      --           item_system_id, username, item_type_id_, access_level_id_;
      /* Cache plpgsql values. */
      group_private_id := cp_group_private_id(username);
      --RAISE INFO '...group_private_id: %', group_private_id;
      EXECUTE '
         INSERT INTO group_item_access
               (group_id,
                item_id,
                stack_id,
                version,
                branch_id,
                --item_type,
                item_type_id,
                valid_start_rid,
                valid_until_rid,
                deleted,
                name,
                acl_grouping,
                access_level_id)
            (SELECT
               ' || group_private_id || ',
               iv.system_id,
               iv.stack_id,
               iv.version,
               iv.branch_id,
               ' || item_type_id_ || ',
               iv.valid_start_rid,
               iv.valid_until_rid,
               iv.deleted,
               iv.name,
               1, -- the first acl_grouping
               ' || access_level_id_ || '
            FROM item_versioned AS iv
               WHERE iv.system_id = ' || item_system_id || ');';
            --   ''' || item_type || ''',
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION link_value_create(IN lhs_stack_id_ INTEGER,
                                  IN rhs_stack_id_ INTEGER,
                                  IN start_rid INTEGER,
                                  IN branch_baseline_id INTEGER,
                                  IN rid_inf INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      link_system_id INTEGER;
      link_stack_id INTEGER;
   BEGIN
      /* Create a new item */
      INSERT INTO item_versioned
         (branch_id, version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (cp_branch_baseline_id(), 1, '', FALSE, FALSE,
          start_rid, rid_inf);
      link_system_id := CURRVAL('item_versioned_system_id_seq');
      link_stack_id := CURRVAL('item_stack_stack_id_seq');
      INSERT INTO link_value (system_id, branch_id, stack_id, version,
                              lhs_stack_id, rhs_stack_id)
         VALUES (link_system_id, cp_branch_baseline_id(), link_stack_id, 1,
                 lhs_stack_id_, rhs_stack_id_);
      RETURN link_system_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION annotation_create(IN comments_ TEXT,
                                  IN start_rid INTEGER,
                                  IN branch_baseline_id INTEGER,
                                  IN rid_inf INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
      annot_system_id INTEGER;
      annot_stack_id INTEGER;
   BEGIN
      /* Create a new item */
      INSERT INTO item_versioned
         (branch_id, version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES
         (branch_baseline_id, 1, '', FALSE, FALSE,
          start_rid, rid_inf);
      annot_system_id := CURRVAL('item_versioned_system_id_seq');
      annot_stack_id := CURRVAL('item_stack_stack_id_seq');
      INSERT INTO attachment (system_id, branch_id, stack_id, version)
         VALUES (annot_system_id, branch_baseline_id, annot_stack_id, 1);
      INSERT INTO annotation (system_id, branch_id, stack_id, version,
                              comments)
         VALUES (annot_system_id, branch_baseline_id, annot_stack_id, 1,
                 comments_);
      RETURN annot_system_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (1)(b) -- Make items for watch region annotations               */
/* ==================================================================== */

/* NOTE This code is somewhat c.f. 102-apb-22-aattrs-instance.sql
        It's a lot different, though, since it deals with system_id
        (which didn't exist in the old script) and it also creates
        a new revision for each user's watch regions. */

/* The old database didn't *version watch regions -- it just set their
   valid_start_rid to 0 and didn't track changes. In this manner, watch
   regions were kept out of the revision control system, effectively
   keeping other users from seeing each other's watch regions or reverting
   their changes. This also meant users couldn't see their own watch
   regions in the revision history.

   We solve the problem by creating a private revision for each
   watch region, and assign that private revision to the user's
   private group.

   As a consequence of this action, users will see their watch regions as
   having been recently created. I.e., after this change is implemented, when
   a user logs in, they'll see their watch regions at the top of the revision
   history. This isn't really that big of a deal, especially considering only
   388 watch regions exist in the minnesota instance, and just 1 in the
   colorado instance. */

/* For a given user, finds all watch regions and associated annotations and
   make a new revision for them. Also assigns the user's private group access
   to the new items. */
CREATE FUNCTION revision_consume_private_wr_user(
      IN tbl_name TEXT,
      IN username_ TEXT,
      IN item_type_id_ INTEGER,
      IN branch_baseline_id INTEGER,
      IN rid_inf INTEGER,
      IN private_access_level INTEGER)
   RETURNS VOID AS $$
   DECLARE
      wr RECORD;
      rid_currval INTEGER;
      item_system_id INTEGER;
      annot_system_id INTEGER;
      annot_stack_id INTEGER;
      link_system_id INTEGER;
   BEGIN
      /* Create a new revision for the private region and annotation. */
      INSERT INTO revision
            (branch_id, timestamp, host, username, is_revertable, comment)
         VALUES
            (branch_baseline_id, now(), '_DUMMY', username_, FALSE,
            'System update: Adding private watch regions to revision control');
      rid_currval := CURRVAL('revision_id_seq');

      /* Display progress */
      --RAISE INFO '...rev. %: %', rid_currval, username;

      /* Find all of this user's watch regions and update 'em. */
      /* NOTE This is an archived table, so there's still an 'id' column. */
      FOR wr IN EXECUTE 'SELECT * FROM ' || tbl_name || '
                         WHERE username = ''' || username_ || '''
                         ORDER BY id ASC, version DESC' LOOP

         /* We expect this table to contain un-versioned items only. That is,
            there's only one version of any item, and it's version 0. */
         IF wr.version != 0 THEN
            RAISE EXCEPTION 'Expecting all IDs to be un-versioned.';
         END IF;
         /* Also, the valid starting revision should be 0. */
         IF wr.valid_starting_rid != 0 THEN
            RAISE EXCEPTION 'Expecting all watch regions to be un-revisioned.';
         END IF;

         /* Get the item's system ID. */
         EXECUTE 'SELECT system_id FROM item_versioned
                  WHERE stack_id = ' || wr.id || ';'
            INTO STRICT item_system_id;

         /* Display progress */
         RAISE INFO '...rev. %: %: %', rid_currval, username_, item_system_id;

         /* Correct the watch region's item: when we consumed it earlier,
            we left its start revision ID set to 0. */
         UPDATE item_versioned SET valid_start_rid = rid_currval
            WHERE system_id = item_system_id;
         /* Also set the version to 1 */
         /* FIXME Is this correct? I added it 2010.11.22.
                  I must've forgot about it? */
         UPDATE item_versioned SET version = 1
            WHERE system_id = item_system_id;
         UPDATE geofeature SET version = 1
            WHERE system_id = item_system_id;

         /* See if the user has any comments about this private region. If so,
            create a new annotation and link_value, and give access to the
            user. */
         IF wr.comments IS NOT NULL THEN
            /* Make the new annotation and link_value */
            annot_system_id := annotation_create(wr.comments,
                                                 rid_currval,
                                                 branch_baseline_id,
                                                 rid_inf);
            /* */
            annot_stack_id := stack_id FROM item_versioned
                                       WHERE system_id = annot_system_id;
            /* */
            link_system_id := link_value_create(annot_stack_id,
                                                wr.id,
                                                rid_currval,
                                                branch_baseline_id,
                                                rid_inf);
            /* Give the user private rights to the new items */
            PERFORM group_item_create(annot_system_id,
                                      wr.username,
                                      item_type_id_,
                                      private_access_level);
            /* NOTE 2010.12.17 Don't forget the link IDs, sheesh!
                    I originally just called group_item_create
                    but that didn't populate the link_valueish columns. */
            /* FIXME Make sure this works now:
                     select count(*) from group_item_access
                     where item_type_id = 3 and link_rhs_type_id is null;
                      count
                     -------
                          9
                     (1 row)
                     */
            PERFORM gia_link_value_make(
               'annotation', 'region', '', link_system_id, wr.username);
         END IF;

         /* NOTE We make group-items for the watch regions below. */

      END LOOP; /* End: new watch_region.comments annotations. */

      /* Create a group-revision so the user can see the revision history. */
      /* NOTE visible_items indicates the number of items in the revision that
              the user can see, so this calculation is okay, even though we're
              bypassing the group_item_access table. */
      /* FIXME Keep branch_id in group_revision? */
      INSERT INTO group_revision
         (group_id,
          branch_id,
          revision_id,
          is_revertable,
          visible_items)
      VALUES
         (cp_group_private_id(username_),
          branch_baseline_id,
          rid_currval,
          FALSE,
          (SELECT COUNT(*) FROM item_versioned
           WHERE valid_start_rid = rid_currval));

      /* NOTE: We'll populate the revision bbox, geosummary, and geometry via
               a script, later.
               */
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* Finds each distinct user in the table and processes items for that user. */
CREATE FUNCTION revision_consume_private_wr(IN tbl_name TEXT,
                                            IN uname_col TEXT)
   RETURNS VOID AS $$
   DECLARE
      r RECORD;
      item_type_id_ INTEGER;
      branch_baseline_id INTEGER;
      rid_inf INTEGER;
      owner_access_level INTEGER;
   BEGIN
      branch_baseline_id := cp_branch_baseline_id();
      rid_inf = cp_rid_inf();
      /* 2013.03.27: This should be editor, since access_style_id is
                     usr_editor for private regions. Not arbiter or
                     owner. */
      owner_access_level := cp_access_level_id('editor');
      item_type_id_ := cp_item_type_id('annotation');
      FOR r IN EXECUTE
            'SELECT DISTINCT u.username
               FROM ' || tbl_name || ' AS tbl
               JOIN user_ AS u
                  ON tbl.' || uname_col || ' = u.username
               WHERE u.login_permitted IS TRUE
               ORDER BY u.username
               ;'
            LOOP
         /* NOTE There's actually only one id per watch region, since there's
                 only one version of each watch region. */
         PERFORM revision_consume_private_wr_user(tbl_name,
                                                  r.username,
                                                  item_type_id_,
                                                  branch_baseline_id,
                                                  rid_inf,
                                                  owner_access_level);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (1)(c) -- Make items for track comments                         */
/* ==================================================================== */

/* C.f. the two fcns above. 2013.05.11: [lb] is squeezing this in late. */
CREATE FUNCTION revision_consume_private_tk_user(
      IN tbl_name TEXT,
      IN username_ TEXT,
      IN item_type_id_ INTEGER,
      IN branch_baseline_id INTEGER,
      IN rid_inf INTEGER,
      IN private_access_level INTEGER)
   RETURNS VOID AS $$
   DECLARE
      tk RECORD;
      rid_currval INTEGER;
      item_system_id INTEGER;
      annot_system_id INTEGER;
      annot_stack_id INTEGER;
      link_system_id INTEGER;
   BEGIN

      INSERT INTO revision
            (branch_id, timestamp, host, username, is_revertable, comment)
         VALUES
            (branch_baseline_id, now(), '_DUMMY', username_, FALSE,
            'System update: Making private track comments into annotations.');
      rid_currval := CURRVAL('revision_id_seq');

      /* Find all of this user's track comments and make annotation for 'em. */
      /* NOTE: This is an archived table, so there's still an 'id' column. */
      /* NOTE: Order by version DESC since some tracks are edited. This just
               uses the latest comment, and we lose any earlier comment
               versions. Oh, well. */
      /* NOTE: valid_starting_rid is 0 in CcpV1 for all track versions. */

      FOR tk IN EXECUTE '
            SELECT DISTINCT ON (track.id) id
                  , track.version
                  , track.valid_starting_rid
                  , track.owner_name
                  , track.comments
            FROM ' || tbl_name || '
            WHERE owner_name = ''' || username_ || '''
            GROUP BY id
                  , version
                  , valid_starting_rid
                  , owner_name
                  , comments
            ORDER BY id ASC, version DESC' LOOP

         /* This is cute: the valid start revision id in CcpV2 is the same as
            the version.... This is something [lb] caused to happen during
            these here update scripts... in CcpV1 the valid_start(ing)_rids
            are all 0. */
         /* It looks like the upgrade scripts change this to match the
            version... */
         --IF tk.valid_starting_rid != 0 THEN
         IF tk.valid_starting_rid != tk.version THEN
            RAISE INFO 'Track not revisioned==versioned? %', tk;
            RAISE EXCEPTION 'Expecting all tracks to be un-revisioned.';
         END IF;

         /* Get the item's system ID. */
         EXECUTE 'SELECT system_id FROM item_versioned
                  WHERE stack_id = ' || tk.id || '
                     AND version = ' || tk.version || ';'
            INTO STRICT item_system_id;

         /* Display progress */
         RAISE INFO '...rev. %: %: %', rid_currval, username_, item_system_id;

         /* See if the user has any comments about this track. If so,
            create a new annotation and link_value, and give access to the
            user. */
         IF tk.comments IS NOT NULL THEN
            /* Make the new annotation and link_value */
            annot_system_id := annotation_create(tk.comments,
                                                 rid_currval,
                                                 branch_baseline_id,
                                                 rid_inf);
            /* */
            annot_stack_id := stack_id FROM item_versioned
                                       WHERE system_id = annot_system_id;
            /* */
            link_system_id := link_value_create(annot_stack_id,
                                                tk.id,
                                                rid_currval,
                                                branch_baseline_id,
                                                rid_inf);
            /* Give the user private rights to the new items */
            PERFORM group_item_create(annot_system_id,
                                      tk.owner_name,
                                      item_type_id_,
                                      private_access_level);
            /* Don't forget the link IDs. */
            PERFORM gia_link_value_make(
               'annotation', 'track', '', link_system_id, tk.owner_name);
         END IF;

         /* NOTE We make group-items for the watch regions below. */

      END LOOP; /* End: new track.comments annotations. */

      INSERT INTO group_revision
         (group_id,
          branch_id,
          revision_id,
          is_revertable,
          visible_items)
      VALUES
         (cp_group_private_id(username_),
          branch_baseline_id,
          rid_currval,
          FALSE,
          (SELECT COUNT(*) FROM item_versioned
           WHERE valid_start_rid = rid_currval));

   END;
$$ LANGUAGE plpgsql VOLATILE;

/* C.f. revision_consume_private_wr... */
CREATE FUNCTION revision_consume_private_tk(IN tbl_name TEXT,
                                            IN uname_col TEXT)
   RETURNS VOID AS $$
   DECLARE
      r RECORD;
      item_type_id_ INTEGER;
      branch_baseline_id INTEGER;
      rid_inf INTEGER;
      owner_access_level INTEGER;
   BEGIN
      branch_baseline_id := cp_branch_baseline_id();
      rid_inf = cp_rid_inf();
      /* 2013.03.27: This should be editor, since access_style_id is
                     usr_editor for private regions. Not arbiter or
                     owner. */
      owner_access_level := cp_access_level_id('editor');
      item_type_id_ := cp_item_type_id('annotation');
      FOR r IN EXECUTE
            'SELECT DISTINCT u.username
               FROM ' || tbl_name || ' AS tbl
               JOIN user_ AS u
                  ON tbl.' || uname_col || ' = u.username
               WHERE u.login_permitted IS TRUE
               ORDER BY u.username
               ;'
            LOOP
         /* NOTE There's actually only one id per watch region, since there's
                 only one version of each watch region. */
         PERFORM revision_consume_private_tk_user(tbl_name,
                                                  r.username,
                                                  item_type_id_,
                                                  branch_baseline_id,
                                                  rid_inf,
                                                  owner_access_level);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ================================================ */
/* Watch Regions And More: Make private group-items */
/* ================================================ */

\qecho
\qecho Adding private revisions for private watch regions
\qecho

\qecho ...region_watched
SELECT revision_consume_private_wr('archive_@@@instance@@@_1.watch_region',
                                   'username');

\qecho ...track
SELECT revision_consume_private_tk('archive_@@@instance@@@_1.track',
                                   'owner_name');

/* =============================================== */
/* Watch Regions And More: Cleanup                 */
/* =============================================== */

\qecho
\qecho Cleaning up helper functions
\qecho

DROP FUNCTION revision_consume_private_wr(IN tbl_name TEXT, IN uname_col TEXT);
DROP FUNCTION revision_consume_private_wr_user(
                                          IN tbl_name TEXT,
                                          IN username_ TEXT,
                                          IN item_type_id_ INTEGER,
                                          IN branch_baseline_id INTEGER,
                                          IN rid_inf INTEGER,
                                          IN private_access_level INTEGER);
DROP FUNCTION revision_consume_private_tk(IN tbl_name TEXT, IN uname_col TEXT);
DROP FUNCTION revision_consume_private_tk_user(
                                          IN tbl_name TEXT,
                                          IN username_ TEXT,
                                          IN item_type_id_ INTEGER,
                                          IN branch_baseline_id INTEGER,
                                          IN rid_inf INTEGER,
                                          IN private_access_level INTEGER);
DROP FUNCTION annotation_create(IN comments_ TEXT,
                                IN start_rid INTEGER,
                                IN branch_baseline_id INTEGER,
                                IN rid_inf INTEGER);
DROP FUNCTION link_value_create(IN lhs_stack_id_ INTEGER,
                                IN rhs_stack_id_ INTEGER,
                                IN start_rid INTEGER,
                                IN branch_baseline_id INTEGER,
                                IN rid_inf INTEGER);
DROP FUNCTION group_item_create(IN item_system_id INTEGER,
                                IN username TEXT,
                                IN item_type_id_ INTEGER,
                                IN access_level_id_ INTEGER);

/* NOTE This fcn. was created in an earlier script, when we added public links
        as public group items. We're done with this fcn., so let's whack it. */
DROP FUNCTION gia_link_value_make(IN attc_type TEXT,
                                  IN feat_type TEXT,
                                  IN value_type TEXT,
                                  IN item_system_id INTEGER,
                                  IN username TEXT);

/* ==================================================================== */
/* Step (1)(b) -- Make private group-items for watch region geofeatures */
/* ==================================================================== */

/* Since we consumed watch regions into geofeature in an earlier script,
   we can just find those watch regions and attach their users to 'em. */

\qecho
\qecho Adding watch regions as private group-items
--\qecho (Please be patient, this takes a few minutes on minnesota)
\qecho

CREATE FUNCTION private_group_watch_regions_grant_access()
   RETURNS VOID AS $$
   DECLARE
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      /* NOTE: Watch regions are just regions with access restrictions. */
      item_type_id_ := cp_item_type_id('region');
      /* 2013.04.09: With access_style, use 'editor' and private user group ID.
      access_level_id_ := cp_access_level_id('owner');
      */
      /* 2013.08.06: item_layer_id is deprecated; nothing uses it. */
      access_level_id_ := cp_access_level_id('editor');
      EXECUTE '
         INSERT INTO group_item_access
               (group_id,
                item_id,
                stack_id,
                version,
                branch_id,
                item_type_id,
                -- item_layer_id,
                valid_start_rid,
                valid_until_rid,
                deleted,
                name,
                acl_grouping,
                access_level_id)
            (SELECT
               cp_group_private_id(gf.username),
               iv.system_id,
               iv.stack_id,
               iv.version,
               iv.branch_id,
               ' || item_type_id_ || ',
               -- gfl.id,
               iv.valid_start_rid,
               iv.valid_until_rid,
               iv.deleted,
               iv.name,
               1, -- the first acl_grouping
               ' || access_level_id_ || '
            FROM geofeature AS gf
               JOIN item_versioned AS iv USING (system_id)
               JOIN geofeature_layer AS gfl
                  ON gf.geofeature_layer_id = gfl.id
               JOIN user_ AS u
                  ON gf.username = u.username
               WHERE gfl.feat_type = ''region_watched''
                  AND u.login_permitted IS TRUE);
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT private_group_watch_regions_grant_access();

DROP FUNCTION private_group_watch_regions_grant_access();

/* NOTE We're still not done with watch_regions -- we still have to record
        which users are watching which regions! See a later script for that. */

/* ===================================================================== */
/* Step (2) -- Make private and shared group-items for routes and tracks */
/* ===================================================================== */

\qecho
\qecho Adding route and track group items, with owner, client, or none access
\qecho

/* HEREIN: Routes and Tracks <==> Passages (like a class hierarchy,
 * item_versioned -> geofeature -> passage -> route or track */

/* In the original model, this is how routes and tracks are access-controlled:

      cycling=> select * from permissions;
       code |  text
      ------+---------
          1 | public
          2 | shared
          3 | private

      cycling=> select * from visibility;
       code | text
      ------+-------
          1 | all
          2 | owner
          3 | noone

      This is before route manip (circa Feb 2012):

      cycling2=> select distinct permission, visibility from route;
       permission | visibility
      ------------+------------
                2 |          3
                3 |          3

      prod_mirror=> select distinct permission, visibility from track;
       permission | visibility
      ------------+------------
                3 |          3

      This is after route manip (circa Feb 2012):

      prod_mirror=> select distinct (visibility, permission) from route;
      -------
       (1,1) all,public     pub edit, pub lib, some usr hist, all ss
       (1,2) all,shared     pub view, pub lib, some usr hist, all ss
       (2,2) owner,shared   deeplink: all usr hist, usr arb, all sstealth view
       (2,3) owner,private  usr hist, usr arb, no public and no deeplink/ss
       (3,2) noone,shared   all sstealth view, maybe usr hist, all usr arb
       (3,3) noone,private  sessID and owner_name maybes, no ss, some usr hist
              NOTE: All tracks are 3,3.
      2,2 and 3,2 are very similar..., 3,* means not in user library, and
      we have to make the 3,2 link_hash_id records public viewer, but not
      public library...
      MISSING/NEW: 1,3 (all,private)
                   2,1 (owner,public)
                   3,1 (noone,public)
      => select count(distinct(id)) from route where visibility=1 and permission=1; 141
      => select count(distinct(id)) from route where visibility=1 and permission=2; 30
      => select count(distinct(id)) from route where visibility=2 and permission=2; 27
      => select count(distinct(id)) from route where visibility=2 and permission=3; 256
      => select count(distinct(id)) from route where visibility=3 and permission=2; 1120
      => select count(distinct(id)) from route where visibility=3 and permission=3; 120587
      # no. views:
      select count(distinct(id)) from route left outer join route_views as rv
         on (rv.route_id = route.id) where rv.route_id is not null
      # no. posts:
      select count(distinct(route.id)) from route left outer join post_route
         as pr on (pr.route_id = route.id) where pr.route_id is not null
      # no. links:
      select count(distinct(id)) from route where link_hash_id is not null
      # posted and linked:
      select count(route.distinct(id)) from route left outer join post_route
         as pr on (pr.route_id = route.id) where pr.route_id is not null
         and link_hash_id is not null
      #
      and ...                            rtes   | vws  |post| lnks | pls | ownr
      ... visibility=1 and permission=1; 141    | 118  | 2  | 141  | 2   | 24
      ... visibility=1 and permission=2; 30     | 30   | 0  | 30   | 0   | 30
      ... visibility=2 and permission=2; 27     | 27   | 0  | 27   | 0   | 27
      ... visibility=2 and permission=3; 256    | 256  | 0  | 0    | 0   | 256
      ... visibility=3 and permission=2; 1120   | 61   | 23 | 1120 | 23  | 327
      ... visibility=3 and permission=3; 120587 | 1538 | 0  | 0    | 0   |19842
      NOTE: 3,2 does not show permissions widget in CcpV1 for deeplink
            2,2 does show permissions widget, private to user
            1,1 does show permissions widget, public for all

vis 1 okay: no item_findability records, so library_restrict defaults FALSE
vis 2 okay: no item_findability records, so library_restrict defaults FALSE
vis 3: recent list okay (views), but library_restrict should be TRUE for user

2012.11.23: [lb] is trying to figure out the proper permissions for CcpV1
            routes.

SELECT id, version AS v, deleted AS del, source, created, owner_name, name,
       valid_starting_rid AS start_rid, valid_before_rid AS final_rid,
       visibility AS visib, permission AS permi, link_hash_id,
       cloned_from_id AS clone_id, session_id
FROM route
WHERE TRUE
AND visibility=3 AND permission=3
-- AND id <= 1571611
--AND owner_name = ''
--AND owner_name IS NOT NULL
--AND deleted IS FALSE
AND version > 1
ORDER BY id desc, version asc
;

WHERE id = 1492406

915 (v1) / 941 (v*):
SELECT COUNT(*) FROM route
WHERE version=1 AND visibility=3 AND permission=2 AND cloned_from_id IS NULL;

205, all version 1:
SELECT COUNT(*) FROM route
WHERE visibility=3 AND permission=2 AND cloned_from_id IS NOT NULL;

==

SELECT COUNT(*) FROM route
WHERE visibility=3 AND permission=3
      AND link_hash_id IS NOT NULL; -- 0

SELECT COUNT(*) FROM route
WHERE visibility=3 AND permission=2
      AND link_hash_id IS NULL; -- 0

SELECT COUNT(*) FROM route
WHERE visibility=2 AND permission=3
      AND link_hash_id IS NOT NULL; -- 0

SELECT COUNT(*) FROM route
WHERE visibility=2 AND permission=2
      AND link_hash_id IS NULL; -- 0

SELECT COUNT(*) FROM route
WHERE visibility=1 AND permission=2
      AND link_hash_id IS NULL; -- 0

SELECT COUNT(*) FROM route
WHERE visibility=1 AND permission=1
      AND link_hash_id IS NULL; -- 0

==

2012.11.24: [lb] is still trying to figure out the proper permissions for
            CcpV1 routes. Here we see what role route_view.active plays.

New routes default to being in the user's route library...

SELECT id, version AS v, deleted AS del, source, owner_name, name,
       valid_starting_rid AS start_rid, valid_before_rid AS final_rid,
       visibility AS visib, permission AS permi, rv.active
FROM route AS rt
JOIN route_view AS rv
   ON (rt.id = rv.route_id)
WHERE TRUE
AND visibility=3 AND permission=3
ORDER BY id desc, version desc
;

SELECT COUNT(*) FROM route AS rt
JOIN route_view AS rv ON (rt.id = rv.route_id)
WHERE visibility=3 AND permission=3 AND rv.active IS TRUE;

All combos of accesses have active of true and false.

==

      prod_mirror=> select distinct(visibility,permission) from track;
       (3,3)
==

   In the new model, a visibility of 'noone' is 'client'-level access, i.e.,
   you can see it, but you can't really see it (system-level attributes like
   speed limit are client-level access, since the client needs to know their
   definition, but the user interface is advised not to display that info).
   In the case of routes, client-level routes can be found by searching, but
   the system won't explicitly find routes the user hasn't searched for.

   Also in the new model, a permissions of shared or private corresponds to
   the public user group and/or the user's private group. A private item has a
   group-item just for the user who owns it, but a shared item has a
   group-item for the owner, and a group-item for the public user group.

   Note that client-access routes aren't sent to the client, but the user is
   allowed to search routes and discover 'em. */

/* In the old database, routes are not revisioned; valid_starting_rid is always
   0. Routes created by anonymous users have a null owner_name. And when a user
   logs out of their client, they can no longer find the route, though we store
   the route in our database with the user's name attached.

   In the new database, we'll revision all the routes. We can't go back and
   figure out at which revision they were really created, so we'll just create
   a new revision and use that. Since old routes aren't findable, this actually
   makes sense: if the user vistory history from before we revisioned routes,
   they won't find any routes.

   As of 2011.01.25, against the old database:

      select count(*) from route: 72,886
      select count(*) from route
        where owner_name IS NULL: 57,917
      select count(*) from route
           where owner_name = '':      0
      select distinct(owner_name)
        from route where
          owner_name like E'\\_%': (0 rows)

      select distinct (valid_starting_rid) from route: 0
      select distinct (valid_before_rid) from route: 2000000000
*/

/* ====================================== */
/* Routes: Helper fcn.                    */
/* ====================================== */

\qecho
\qecho Creating helper fcn.
\qecho

CREATE FUNCTION passage_make_group_items_impl(
      IN passage_tbl TEXT,
      IN visibility_id INTEGER,
      IN permission_id INTEGER,
      IN use_private_group BOOLEAN,
      IN use_stealth_group BOOLEAN,
      IN use_basemap_owners_group BOOLEAN,
      IN access_level TEXT,
      IN extra_join_clause TEXT,
      IN extra_join_where TEXT)
   RETURNS VOID AS $$
   DECLARE
      select_group_id TEXT;
      join_clause TEXT;
      where_clause TEXT;
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
   BEGIN
      join_clause := '';
      where_clause := '';
      IF (use_private_group) THEN
         select_group_id := 'cp_group_private_id(pg.owner_name)';
         /* NOTE Only makes group-items for routes that are owned. That is,
                 skip routes that are created by anonymous, not-logged in
                 users. */
         join_clause := 'JOIN user_ AS u ON pg.owner_name = u.username';
         /* FIXME: 2012.03.10: Why was I checking login_permitted? */
         where_clause := 'AND pg.owner_name IS NOT NULL
                          -- AND u.login_permitted IS TRUE';
      ELSIF (use_stealth_group) THEN
         select_group_id := 'cp_group_stealth_id()';
         where_clause := 'AND pg.link_hash_id IS NOT NULL
                          -- AND u.login_permitted IS TRUE';
      ELSIF (use_basemap_owners_group) THEN
         select_group_id := 'cp_group_basemap_owners_id(NULL)';
         /* Make group-items for everything; leave where_clause empty. */
      ELSE
         select_group_id := 'cp_group_public_id()';
         /* CcpV2 replaces route.link_hash_id with item_stack.stealth_secret */
         --IF passage_tbl = 'route' THEN
         --   /* This only applies to "shared" routes, that is, routes the user
         --      has allowed others to see, by sharing the route with a
         --      deep_link. */
         --   where_clause := 'AND pg.link_hash_id IS NOT NULL';
         --ELSE
         --   /* FIXME: There is no equivalent in tracks, right? */
         --   --where_clause := 'AND FALSE';
         --END IF;
      END IF;
      /* Cache lookup values to save SQL processing cycles. */
      item_type_id_ := cp_item_type_id(passage_tbl);
      access_level_id_ := cp_access_level_id(access_level);
      /* 2013.08.06: item_layer_id is deprecated; nothing uses it. */
      /* */
      EXECUTE '
         INSERT INTO group_item_access
               (group_id,
                branch_id,
                item_id,
                stack_id,
                version,
                deleted,
                name,
                item_type_id,
                -- item_layer_id,
                valid_start_rid,
                valid_until_rid,
                acl_grouping,
                access_level_id)
            (SELECT
               ' || select_group_id || ',
               pg.branch_id,
               pg.system_id,
               pg.stack_id,
               pg.version,
               iv.deleted,
               iv.name,
               ' || item_type_id_ || ',
               -- gfl.id,
               iv.valid_start_rid,
               iv.valid_until_rid,
               1, -- the first acl_grouping
               ' || access_level_id_ || '
            FROM ' || passage_tbl || ' AS pg
               JOIN geofeature AS gf USING (system_id)
               JOIN item_versioned AS iv USING (system_id)
               JOIN geofeature_layer AS gfl
                  ON gf.geofeature_layer_id = gfl.id
               ' || join_clause || '
               ' || extra_join_clause || '
               WHERE gfl.feat_type = ''' || passage_tbl || '''
                     AND pg.visibility = ' || visibility_id || '
                     AND pg.permission = ' || permission_id || '
                     ' || where_clause || '
                     ' || extra_join_where || '
               );';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION passage_make_group_items(
      IN visibility_id INTEGER,
      IN permission_id INTEGER,
      IN use_private_group BOOLEAN,
      IN use_stealth_group BOOLEAN,
      IN use_basemap_owners_group BOOLEAN,
      IN access_level TEXT)
   RETURNS VOID AS $$
   BEGIN
      PERFORM passage_make_group_items_impl('route', visibility_id,
         permission_id, use_private_group, use_stealth_group,
         use_basemap_owners_group, access_level, '', '');
      /* The track table does not have link_hash_id. */
      IF (NOT use_stealth_group) THEN
         PERFORM passage_make_group_items_impl('track', visibility_id,
            permission_id, use_private_group, use_stealth_group,
            use_basemap_owners_group, access_level, '', '');
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* */

/* This is wrong. Don't mark these records deleted. The user who asked for this
   route will be assigned arbiter rights, but we'll use the route_view.active
   flag to determine if the route is searchable or findable.

CREATE FUNCTION passage_set_items_deleted_impl(IN passage_tbl TEXT,
                                               IN vbil_id INTEGER,
                                               IN perm_id INTEGER)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE '
         UPDATE ' || passage_tbl || ' AS pg
            SET deleted = TRUE
            FROM item_versioned AS itmv
               ON (pg.system_id = itmv.system_id)
            WHERE pg.visibility = 3
               AND pg.permission = 3;
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION passage_set_items_deleted(IN vbil_id INTEGER,
                                          IN perm_id INTEGER)
   RETURNS VOID AS $$
   BEGIN
      PERFORM passage_set_items_deleted_impl('route', vbil_id, perm_id);
      PERFORM passage_set_items_deleted_impl('track', vbil_id, perm_id);
   END;
$$ LANGUAGE plpgsql VOLATILE;

*/

/* ====================================== */
/* Routes: Apply all                      */
/* ====================================== */

\qecho ...creating new revision
INSERT INTO revision
   (branch_id, timestamp, host, username, is_revertable, comment)
VALUES
   (cp_branch_baseline_id(), now(), '_DUMMY', '_script', FALSE,
   'Group Access Control: Revisioning Routes and Tracks and Setting Access');

/* BUG nnnn: Write script to set route. and track.valid_start_rid using
             created. For now... using rid = 1, which nothing uses.
             Or maybe we can just leave the rids at 0? */

\qecho ...routes: changing start rid from 0 to 1
                     /* FIXME: Or should it be 1? */
/*
UPDATE item_versioned AS iv
   --SET valid_start_rid = CURRVAL('revision_id_seq')
   SET valid_start_rid = 1
   FROM route AS rt
   WHERE rt.system_id = iv.system_id
      AND iv.valid_start_rid = 0;
*/

\qecho ...tracks: changing start rid from 0 to 1
                     /* FIXME: Or should it be 1? */
/*
UPDATE item_versioned AS iv
   --SET valid_start_rid = CURRVAL('revision_id_seq')
   SET valid_start_rid = 1
   FROM track AS tk
   WHERE tk.system_id = iv.system_id
      AND iv.valid_start_rid = 0;
*/

\qecho ...making group-items for all,public [pub editor]
/* NOTE: We're not making a record for the user for this item.
         In CcpV1, this same route has a different entry (earlier stack ID)
         for this route with visibilty=3 and permission=3, if not another
         record with visibility=2. */
SELECT passage_make_group_items(1, 1, FALSE, FALSE, FALSE, 'editor');
/* Don't bother making GIA for the stealth group (since no one can arbit the
   record, and a stealth ID search will still yield the public record). */
/* Without a stealth record or with either of the following won't matter
   because public has editor access:
-- SELECT passage_make_group_items(1, 1, FALSE, TRUE, FALSE, 'editor');
-- SELECT passage_make_group_items(1, 1, FALSE, TRUE, FALSE, 'denied');
*/

\qecho ...making group-items for all,shared [usr arbiter, pub viewer]
SELECT passage_make_group_items(1, 2, TRUE, FALSE, FALSE, 'arbiter');
SELECT passage_make_group_items(1, 2, FALSE, FALSE, FALSE, 'viewer');
/* Unlike public-only and stealth, here we have a user-arbiter, so
   make GIA for the stealth group. */
-- Inherit public permissions: This is not needed:
--   SELECT passage_make_group_items(1, 2, FALSE, TRUE, FALSE, 'viewer');

\qecho ...making group-items for owner,shared [usr arbiter, stealth viewer]
SELECT passage_make_group_items(2, 2, TRUE, FALSE, FALSE, 'arbiter');
SELECT passage_make_group_items(2, 2, FALSE, TRUE, FALSE, 'viewer');

\qecho ...making group-items for owner,private [usr arbiter]
/* FIXME: See BUG nnnn below: Does this mean the user added a route to their
          route library, so route_view.active is true? If a user removes a
          route from the library, in CcpV1, a new route row is not created
          (i.e., new permissions and visibility are not assigned), unlike
          when a deeplink is created or when a route is made public...? */
SELECT passage_make_group_items(2, 3, TRUE, FALSE, FALSE, 'arbiter');

/* Users can arbit all routes they've ever requested that they haven't made
 * public. Though old routes (pre-route sharing) won't show up in the list in
 * the application because we've marked these routes deleted. */
/* BUG nnnn: Let user see all their routes, i.e., show deleted. Zombie option?
 */

/* FIXME: Is this really right? The most routes in route sharing are
          anonymously shared routes? */
\qecho ...making group-items for noone,shared [usr arb deleted, stealth viewer]
/* See comments below. We could make an arbiter record for the user, but the
   route currently doesn't show up in the user's route library and the route
   isn't searchable. So making an arbiter record would not work unless we made
   a new GIA attribute, like "hide_from_searches", or something silly. But if
   the access_style is restricted, and if creator_name matches a user's
   username, we could someday recover past routes, and change the SQL in
   item_user_access to make it possible to get denied-items for a user-owner
   and give them arbiter access, i.e., if they want to add the route to their
   library.
   BUG nnnn: Do the above (let users see all their routes from all of time)
             Also, route_view.active controls what's in the route library,
             I think. How does that relate to the GIA record?
No: SELECT passage_make_group_items(3, 2, TRUE, FALSE, FALSE, 'arbiter');
*/
-- NO: SELECT passage_make_group_items(3, 2, TRUE, FALSE, FALSE, 'denied');
SELECT passage_make_group_items(3, 2, TRUE, FALSE, FALSE, 'arbiter');
/* The stealth group gets viewer access. */
SELECT passage_make_group_items(3, 2, FALSE, TRUE, FALSE, 'viewer');
/* WRONG: 2013.03.25: This is the permissions for link-route records. I.e.,
          user requested a route and started a thread about it. So allow
          users to click the link-route to see the route. */
/* NOTE: Later, we'll set library_restrict to TRUE since this routes aren't
         meant to be in the route library. */
/* NOTE: We only do this for the two dozen noone,shared routes that are posted
         about and not for the thousand plus other routes. */
-- No: SELECT passage_make_group_items(3, 2, FALSE, FALSE, FALSE, 'viewer');
SELECT passage_make_group_items_impl(
   'route', 3, 2, FALSE, FALSE, FALSE, 'viewer',
   'JOIN archive_@@@instance@@@_1.post_route AS prt
      ON (prt.route_id = pg.stack_id)
    LEFT OUTER JOIN group_item_access AS gia
      ON (pg.system_id = gia.item_id)',
   'AND gia.item_id IS NULL');

\qecho ...making group-items for noone,private [usr arbiter deleted]
/* We can consider these records as 'deleted', since the user no longer has
   access to this route (well, maybe by session ID, but we're taking the site
   offline to update the database, so session IDs are all obsolete at this
   point). */
/* Maybe the proper solution is to give the user denied access to the route,
   and then use access_style and creator_name to determine if we can give
   the user arbiter access if they want to reclaim the route. So at least
   we're making a GIA record. Note that some vis=3/prm=3 routes are marked
   deleted if the user make a deeplink or otherwise shared the route.
No: SELECT passage_set_items_deleted(3, 3);
No: SELECT passage_make_group_items(3, 3, TRUE, FALSE, FALSE, 'arbiter');
 */
/* Because some routes are active, we cannot mark denied. The route will be
 * filtered from route library and route search when route_view.active is
 * false. */
/* No: SELECT passage_make_group_items(3, 3, TRUE, FALSE, FALSE, 'denied'); */
SELECT passage_make_group_items(3, 3, TRUE, FALSE, FALSE, 'arbiter');

/* FIXME: Do we care? This
     SELECT passage_make_group_items(3, 2, TRUE, FALSE, FALSE, 'owner');
   causes this:
INFO:  No such group or user is not member: pilot-ex1
INFO:  No such group or user is not member: pilot-ex2
INFO:  No such group or user is not member: pilot-ex3
INFO:  No such group or user is not member: pilot-in1
INFO:  No such group or user is not member: pilot-in2
INFO:  No such group or user is not member: pilot-in2
INFO:  No such group or user is not member: pilot-in2
INFO:  No such group or user is not member: pilot-in2
INFO:  No such group or user is not member: rej-test35
INFO:  No such group or user is not member: rej-test35
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: roseradz
INFO:  No such group or user is not member: test15
INFO:  No such group or user is not member: test16
INFO:  No such group or user is not member: test17
INFO:  No such group or user is not member: test18
INFO:  No such group or user is not member: test20
INFO:  No such group or user is not member: test21
INFO:  No such group or user is not member: test22
INFO:  No such group or user is not member: test23
INFO:  No such group or user is not member: test24
INFO:  No such group or user is not member: test24
INFO:  No such group or user is not member: test25
INFO:  No such group or user is not member: test25
INFO:  No such group or user is not member: test26
INFO:  No such group or user is not member: test27
INFO:  No such group or user is not member: test29
INFO:  No such group or user is not member: test30
INFO:  No such group or user is not member: test32
INFO:  No such group or user is not member: test33
INFO:  No such group or user is not member: test34
INFO:  No such group or user is not member: test36
INFO:  No such group or user is not member: test37
INFO:  No such group or user is not member: test38
INFO:  No such group or user is not member: test39
INFO:  No such group or user is not member: test40
INFO:  No such group or user is not member: test42
INFO:  No such group or user is not member: test43
INFO:  No such group or user is not member: test43
INFO:  No such group or user is not member: test44
INFO:  No such group or user is not member: test45
INFO:  No such group or user is not member: test47
INFO:  No such group or user is not member: test47
INFO:  No such group or user is not member: test47
INFO:  No such group or user is not member: test47
INFO:  No such group or user is not member: test47
INFO:  No such group or user is not member: test48
INFO:  No such group or user is not member: test49

2013.03.27: Aha. These accounts have login_permitted set to false.

   ccpv1_lite=>
      select distinct(username) from user_
      where login_permitted is false
      order by username;

   disabled_accounts = (
      '_cbf7_rater',
      'ktalbright',
      '_naive_rater',
      'pilot-ex1',
      'pilot-ex2',
      'pilot-ex3',
      'pilot-in1',
      'pilot-in2',
      'rej-test35',
      '_r_generic',
      'roseradz',
      'test15',
      'test16',
      'test17',
      'test18',
      'test20',
      'test21',
      'test22',
      'test23',
      'test24',
      'test25',
      'test26',
      'test27',
      'test29',
      'test30',
      'test32',
      'test33',
      'test34',
      'test36',
      'test37',
      'test38',
      'test39',
      'test40',
      'test42',
      'test43',
      'test44',
      'test45',
      'test47',
      'test48',
      'test49',
      '_vacuous_rater',
      )
   # From the CcpV1 database, these users did not get a group_membership record
   # created.
   # BUG nnnn: Figure out how login_permitted really works: in future, we'll
   #           just set this flag false and probably won't touch
   #           group_membership... which is probably fine. So V1->V2 probably
   #           could have made the group_membership records. Meh.

 */

/* FIXME route manip from trunk/wfs_GetRevision.py:
 *
 *  make sure the code in this file matches these goals:
 *
      # visibility = 1 is all, visibility = 2 is for owner, we never show
      # the case when visibility = 3 (no-one)
      where_user = ''' AND (visibility = 1
                            OR (visibility = 2
                                AND username IS NOT NULL
                                AND username = %s))
                   ''' % (self.req.db.quoted(self.req.client.username))
*/

/* NOTE: The following are just for developers. We give viewer access to all
 *       routes to the basemap owners. */
/* FIXME: We don't add basemap owner access from route.py when saving new
          routes... so why do it here? Either don't do it at all, or update
          route.py... */
/* 2013.04.26: [lb] is disabling this. It was interesting for testing, but
                    we're getting close to really finally releasing the new
                    database, and there are other ways to allow a developer
                    access to an item without necessarily giving them sneaky
                    GIA access in the live database.
\qecho ...making Shared group-items for Shared Passages for Basemap Owners
SELECT passage_make_group_items(1, 1, FALSE, FALSE, TRUE, 'viewer');
SELECT passage_make_group_items(1, 2, FALSE, FALSE, TRUE, 'viewer');
SELECT passage_make_group_items(2, 2, FALSE, FALSE, TRUE, 'viewer');
SELECT passage_make_group_items(2, 3, FALSE, FALSE, TRUE, 'viewer');
SELECT passage_make_group_items(3, 2, FALSE, FALSE, TRUE, 'viewer');
SELECT passage_make_group_items(3, 3, FALSE, FALSE, TRUE, 'viewer');
*/

\qecho ...creating new group_revision
INSERT INTO group_revision
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES
      (cp_group_basemap_owners_id(''),                         -- group_id
       cp_branch_baseline_id(),                                -- branch_id
       CURRVAL('revision_id_seq'),                             -- revision_id
       FALSE,                                                  -- is_revertable
       (SELECT COUNT(*) FROM item_versioned
        WHERE valid_start_rid = CURRVAL('revision_id_seq')));  -- visible_items

/* NOTE Some considerations:
         * The route revision numbers are all 0.
         ** Routes are still a very special thingy that exist outside
            of revisions. We'll fix this when we implement route manipulation,
            but we won't ever add old routes to revision control: it just
            doesn't make sense. If a user somehow gains better access to an old
            route, we can always revision it at that time.
         * Some groups were given client-level access to some routes.
         ** So some routes are discoverable through searching, but the
            user won't find them via the revision history or any sort of log.
         * There are no group-revisions.
         ** Users can only find old routes by explicitly searching, and users
            cannot see their route history in the revision history panel. */

/* =============================================== */
/* Routes: Cleanup, incl. remove obsolete columns  */
/* =============================================== */

\qecho
\qecho Cleaning up.
\qecho

DROP FUNCTION passage_make_group_items(
   IN visibility_id INTEGER,
   IN permission_id INTEGER,
   IN use_private_group BOOLEAN,
   IN use_stealth_group BOOLEAN,
   IN use_basemap_owners_group BOOLEAN,
   IN access_level TEXT);
DROP FUNCTION passage_make_group_items_impl(
   IN passage_tbl TEXT,
   IN visibility_id INTEGER,
   IN permission_id INTEGER,
   IN use_private_group BOOLEAN,
   IN use_stealth_group BOOLEAN,
   IN use_basemap_owners_group BOOLEAN,
   IN access_level TEXT,
   IN extra_join_clause TEXT,
   IN extra_join_where TEXT);

/* See notes above. We don't mark any routes deleted.
DROP FUNCTION passage_set_items_deleted(IN vbil_id INTEGER,
                                        IN perm_id INTEGER);
DROP FUNCTION passage_set_items_deleted_impl(IN passage_tbl TEXT,
                                             IN vbil_id INTEGER,
                                             IN perm_id INTEGER);
*/

/* 2013.04.17: Wait to do this.

\qecho
\qecho Dropping old access control stuff.
\qecho

ALTER TABLE route DROP COLUMN permission;
ALTER TABLE route DROP COLUMN visibility;

ALTER TABLE track DROP COLUMN permission;
ALTER TABLE track DROP COLUMN visibility;

*/

/* What was the 'owner_name' is really the name of the user who created the
 item, since the idea of ownerhip is handled by the group tables. With some
 items, you could deduce the creator by joining against the revision table
 using the item at version=1, but routes and tracks (and old watch_regions)
 all have a valid_start_rid=0 (and there's no record in revision at id=0). We
 could use the group_item_access table to determine who created a route or a
 track, though: there's a group_item_access record for the creator at revision
 0. For now, we'll keep the column, but we'll rename it so as not to confuse
 with idea of 'owner' as defined by access_level.
 */

/* 2012.11.23: We'll delete this when we use owner_name/created_by to populate
               item_stack.creator_name. */

\qecho Renaming route.owner_name to created_by
ALTER TABLE route RENAME COLUMN owner_name TO created_by;

\qecho Renaming track.owner_name to created_by
ALTER TABLE track RENAME COLUMN owner_name TO created_by;

/* NOTE We're also not addressing the two other user-centric columns here,
        host and session_id. */

/* ==================================================================== */
/* Step (3) -- Populate group_revision table                            */
/* ==================================================================== */

\qecho
\qecho Populating group_revision table
\qecho

/* route manip: this is wrong. */

/* Before access control was implemented, everything except routes was
   public and wholly revertable, so it's easy to populate group_revision.

- Existing routes are not revisioned, so they're not in the revision table.
wrong: routes are now revisioned. and versioned.
prod_mirror=> select count(*) from route where valid_starting_rid=0;   103336
prod_mirror=> select count(*) from route where valid_starting_rid!=0;  220

   - Private stuff we've added with the *-apb-* scripts is tagged with
     username = '_script' and has host = '_DUMMY', but there are some old
     revisions that also match this criteria.
   - We added a new column, is_revertable, which is set to TRUE for all old
     revisions, but the apb scripts have only ever set it to FALSE. So all the
     old revisions are marked TRUE, and those are the ones for which we want
     to make public group_revision rows. */

/*

prod_mirror=> select distinct (visibility, permission) from revision;
-------
 (1,1)  all,public
 (1,2)  all,shared
 (2,3)  owner,private
 (3,2)  noone,shared
 (3,3)  noone,private
MISSING: 1,3 (all,private)
         2,1 (owner,public)
         2,2 (owner,shared)
         3,1 (noone,public)
=> select count(*) from revision where visibility=1 and permission=1;  14822
=> select count(*) from revision where visibility=1 and permission=2;  29
=> select count(*) from revision where visibility=2 and permission=3;  60
=> select count(*) from revision where visibility=3 and permission=2;  7
=> select count(*) from revision where visibility=3 and permission=3;  65

EXPLAIN: What's the difference between noone,shared and noone,private?
         Esp. since no one can see it, anyway, right?

*/

CREATE FUNCTION group_revision_populate_for_bulk(
      IN group_public_id INTEGER,
      IN branch_baseline_id INTEGER,
      IN access_permission INTEGER,
      IN access_visibility INTEGER)
   RETURNS VOID AS $$
   BEGIN
      /* NOTE: Setting visible_items to 0. We'll populate it next. */
      EXECUTE '
         INSERT INTO group_revision (
            group_id,
            branch_id,
            revision_id,
            is_revertable,
            visible_items
            )
            (SELECT
               ' || group_public_id || ',
               ' || branch_baseline_id || ',
               rev.id,
               TRUE, -- is_revertable
               0     -- visible_items: set next
            FROM
               revision AS rev
            WHERE
               /* NOTE: is_revertable is set for revisions that apply to items.
               *        is_revertable is only FALSE for GrAC edits.
               *        FIXME: I am not really sure is_revertable is ever
               *               FALSE. Is not GrAC just saved with items? */
               is_revertable IS TRUE
               AND permission = ' || access_permission || '
               AND visibility = ' || access_visibility || '
            );
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION group_revision_populate_for_user(
      IN revision_id INTEGER,
      IN user_group_id INTEGER,
      IN branch_baseline_id INTEGER)
   RETURNS VOID AS $$
   BEGIN
      /* NOTE: Setting visible_items to 0. We'll populate it next. */
      EXECUTE '
         INSERT INTO group_revision (
            group_id,
            branch_id,
            revision_id,
            is_revertable,
            visible_items
            )
            VALUES (
               ' || user_group_id || ',
               ' || branch_baseline_id || ',
               ' || revision_id || ',
               TRUE, -- is_revertable
               0     -- visible_items: set next
            );
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION group_revision_populate()
   RETURNS VOID AS $$
   DECLARE
      branch_baseline_id INTEGER;
      group_public_id INTEGER;
      group_basemap_owners_id INTEGER;
      --revision_rec RECORD;
      revision_rec @@@instance@@@.revision%ROWTYPE;
      user_group_id INTEGER;
   BEGIN
      /* Cache static values, spare a cycle. */
      branch_baseline_id := cp_branch_baseline_id();
      group_public_id := cp_group_public_id();
      group_basemap_owners_id := cp_group_basemap_owners_id('');
      /*
       Revisions have the following visibilty,permission:
        (1,1)  all,public
        (1,2)  all,shared
        (2,3)  owner,private
        (3,2)  noone,shared
        (3,3)  noone,private

       So,
         all,*             means the public can see the revision.
         all,* + owner,*   means the user can see their revision.
         noone,*           means no one can see the rev (ex. basemap owners).
      */

      /* Make all the public group_revision records. */
      -- Old way: PERFORM group_revision_populate_for_bulk(
      --             group_public_id, branch_baseline_id, 1, 0);
      PERFORM group_revision_populate_for_bulk(
         group_public_id, branch_baseline_id, 1, 1);
      PERFORM group_revision_populate_for_bulk(
         group_public_id, branch_baseline_id, 1, 2);

      /* Make records for users for shared/private records. */
      -- FIXME: Maybe do not make user entries for noone entries?
      FOR revision_rec IN
            SELECT * FROM @@@instance@@@.revision
            WHERE ((visibility != 1) OR (permission != 1))
            ORDER BY id
               LOOP
         /* Get the user's group ID. If no group, create a record for the
          * basemap owners. */
         IF revision_rec.username IS NOT NULL THEN
            user_group_id := cp_group_private_id(revision_rec.username);
            IF user_group_id = 0 THEN
               RAISE EXCEPTION 'No private group for user: %',
                               revision_rec.username;
            END IF;
         ELSE
            --user_group_id := group_public_id;
            user_group_id := group_basemap_owners_id;
         END IF;
         /* Create records for the user for 1,1;1,2;2,3, i.e., viz: all/owner
          * Create records for basemap owners for 3,2;3,3, i.e., viz: noone. */
         IF (revision_rec.visibility = 3) THEN
            /* Always use basemap owners. */
            user_group_id := group_basemap_owners_id;
         END IF;
         PERFORM group_revision_populate_for_user(
            revision_rec.id, user_group_id, branch_baseline_id);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT group_revision_populate();

DROP FUNCTION group_revision_populate_for_user(
      IN revision_id INTEGER,
      IN user_group_id INTEGER,
      IN branch_baseline_id INTEGER);
DROP FUNCTION group_revision_populate_for_bulk(
      IN group_public_id INTEGER,
      IN branch_baseline_id INTEGER,
      IN access_permission INTEGER,
      IN access_visibility INTEGER);
DROP FUNCTION group_revision_populate();

\qecho
\qecho Updating group_revision table
--\qecho ... please be patient!! (like, 12+ mins for mn)
\qecho

CREATE INDEX group_revision_group_id ON group_revision (group_id);

/* NOTE It's okay to bypass group-items table: since permissions haven't
        changed, any group that can see a revision history can also see
        all of the items at that revision. */

/* Update the public group revisions we just created. */
CREATE FUNCTION group_revision_update()
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
   BEGIN
      /* Cache static values, spare a cycle. */
      group_public_id := cp_group_public_id();
      /* NOTE: Setting visible_items to 0. We'll populate it next. */
      EXECUTE '
         UPDATE group_revision AS gr
            SET visible_items = (
               SELECT COUNT(*) FROM item_versioned AS iv
                  WHERE iv.valid_start_rid = gr.revision_id)
            WHERE group_id = ' || group_public_id || '
               AND is_revertable IS TRUE;
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT group_revision_update();

DROP FUNCTION group_revision_update();

/* ==================================================================== */
/* Step (4) -- Let Basemap Owners see Special Revisions                 */
/* ==================================================================== */

\qecho
\qecho Revealing special revisions to basemap owners using group_revision
\qecho

INSERT INTO group_revision
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES
      (cp_group_basemap_owners_id(''), cp_branch_baseline_id(),
       0, FALSE, (SELECT COUNT(*) FROM item_versioned
                  WHERE valid_start_rid = CURRVAL('revision_id_seq')));

INSERT INTO group_revision
      (group_id, branch_id, revision_id, is_revertable, visible_items)
   VALUES
      (cp_group_basemap_owners_id(''), cp_branch_baseline_id(),
       1, FALSE, (SELECT COUNT(*) FROM item_versioned
                  WHERE valid_start_rid = CURRVAL('revision_id_seq')));

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;

