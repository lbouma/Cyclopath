/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates group-items for public items for the public group. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates group-items for public items for the public group.
\qecho 
\qecho [EXEC. TIME: 2011.04.25/Huffy: ~ 0.82 mins (w/out gia constraints).]
\qecho [EXEC. TIME: 2011.04.28/Huffy: ~ 1.28 mins (with gia constraints).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.58 min. [mn]]
\qecho 

/* PERFORMACE NOTE: Before 2011.04.22, this script took over _three_hours_.
 *                  Deferring index and constraint creation until later 
 *                  reduced this script's execution time down to _one_ 
 *                  _minute_ for both instances, colorado and minnesota. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Make group-item for public group access to basemap       */
/* ==================================================================== */

\qecho 
\qecho Giving editor access to public group on public base map
\qecho 

CREATE FUNCTION public_group_public_branch_grant_editor_access()
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
      branch_baseline_id INTEGER;
   BEGIN
      /* Cache static values, spare a cycle. */
      group_public_id := cp_group_public_id();
      item_type_id_ := cp_item_type_id('branch');
      access_level_id_ := cp_access_level_id('editor');
      branch_baseline_id := cp_branch_baseline_id();
      EXECUTE '
         INSERT INTO group_item_access 
            (group_id,
             item_id,
             stack_id,
             version,
             branch_id,
             item_type_id,
             valid_start_rid,
             valid_until_rid,
             deleted,
             name,
             acl_grouping,
             access_level_id)
         (SELECT
            ' || group_public_id || ',
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
         FROM branch AS br
            JOIN item_versioned AS iv USING (system_id)
         WHERE 
            br.stack_id = ' || branch_baseline_id || '
         );';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT public_group_public_branch_grant_editor_access();

DROP FUNCTION public_group_public_branch_grant_editor_access();

\qecho 
\qecho Giving owner access to owner group on public base map
\qecho 

CREATE FUNCTION owner_group_public_branch_grant_owner_access()
   RETURNS VOID AS $$
   DECLARE
      group_owners_id INTEGER;
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
      branch_baseline_id INTEGER;
      rid_inf INTEGER;
   BEGIN
      /* Cache static values, spare a cycle. */
      group_owners_id := cp_group_basemap_owners_id('');
      item_type_id_ := cp_item_type_id('branch');
      access_level_id_ := cp_access_level_id('owner');
      branch_baseline_id := cp_branch_baseline_id();
      rid_inf := cp_rid_inf();
      EXECUTE '
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
             item_type_id)
         (SELECT
            ' || group_owners_id || ',
            iv.stack_id,         -- same as: iv.branch_id
            iv.system_id,
            iv.stack_id,
            iv.version,
            iv.deleted,
            iv.name,
            1,                   -- iv.valid_start_rid,
            ' || rid_inf || ',   -- iv.valid_until_rid,
            1,                   -- the first acl_grouping
            ' || access_level_id_ || ',
            ' || item_type_id_ || '
         FROM branch AS br
            JOIN item_versioned AS iv USING (system_id)
         WHERE 
            iv.stack_id = ' || branch_baseline_id || '
            AND NOT iv.deleted
            AND iv.valid_until_rid = ' || rid_inf || '
         );';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT owner_group_public_branch_grant_owner_access();

DROP FUNCTION owner_group_public_branch_grant_owner_access();

/* ==================================================================== */
/* Step (3) -- Make group-items for public items                        */
/* ==================================================================== */

/* ==================================================================== */
/* Step (3)(a) -- Make group-items for Attachments                      */
/* ==================================================================== */

/* ====================================== */
/* Public group-items: Helper fcn.        */
/* ====================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

/* XREF See also group_item_create_private in 102-apb-58-groups-pvt_ins1.sql */
CREATE FUNCTION attachment_make_public(IN table_name TEXT, 
                                       IN access_level TEXT)
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      group_public_id := cp_group_public_id();
      item_type_id_ := cp_item_type_id(table_name);
      access_level_id_ := cp_access_level_id(access_level);
      /* NOTE Skipping cols: item_layer_id, attc_type, feat_type */
      EXECUTE '
         INSERT INTO group_item_access 
               (group_id,
                item_id,
                stack_id,
                version,
                branch_id,
                item_type_id,
                valid_start_rid,
                valid_until_rid,
                deleted,
                name,
                acl_grouping,
                access_level_id)
            (SELECT
               ' || group_public_id || ',
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
            FROM ' || table_name || ' AS attc
               JOIN item_versioned AS iv USING (system_id));';
            --   ''' || table_name || ''',
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ====================================== */
/* Public group-items: Apply all          */
/* ====================================== */

\qecho 
\qecho Granting public group access to public attachments
\qecho 

\qecho ...attachment: tag
SELECT attachment_make_public('tag', 'editor');
\qecho ...attachment: annotation
SELECT attachment_make_public('annotation', 'editor');
\qecho ...attachment: thread
SELECT attachment_make_public('thread', 'editor');
\qecho ...attachment: post
SELECT attachment_make_public('post', 'editor');
/* NOTE The five attributes created so far are system attributes, that is, 
        they are not to be edited by users. */
/* FIXME Do we want to make 'em 'client' access instead? */
\qecho ...attachment: attribute
SELECT attachment_make_public('attribute', 'viewer');

/* ====================================== */
/* Public group-items: Cleanup            */
/* ====================================== */

DROP FUNCTION attachment_make_public(IN table_name TEXT, IN access_level TEXT);

/* ==================================================================== */
/* Step (3)(b) -- Make group-items for Geofeatures                      */
/* ==================================================================== */

/* ====================================== */
/* Public group-items: Helper fcn.        */
/* ====================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION geofeature_make_public(IN feat_type TEXT)
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      item_type_id_ INTEGER;
      access_level_id_ INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      group_public_id := cp_group_public_id();
      item_type_id_ := cp_item_type_id(feat_type);
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
               ' || group_public_id || ',
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
               WHERE gfl.feat_type = ''' || feat_type || ''');';
            --   ''' || feat_type || ''',
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ====================================== */
/* Public group-items: Apply all          */
/* ====================================== */

\qecho 
\qecho Granting public group access to public geofeatures
\qecho 

/* FINDME / TESTING: Comment-out for speedy testing. */

\qecho ...geofeature: byway
SELECT geofeature_make_public('byway');
\qecho ...geofeature: region
SELECT geofeature_make_public('region');
\qecho ...geofeature: terrain
SELECT geofeature_make_public('terrain');
\qecho ...geofeature: waypoint
SELECT geofeature_make_public('waypoint');

/* NOTE Handling route and track later; their group-items are private, shared, 
        or denied */
/* NOTE Handling region_watched later; its group-items (regions and
        annotations) are private */
/* NOTE Skipping region_work_hint (which is empty, anyway, since we still
        haven't proccessed archive_@@@instance@@@_1.work_hint */
/* NOTE Skipping attc & feat support tables, which are not under access 
        control (well, they are, but by virutal of the attcs and feats they 
        reference). */

/* ====================================== */
/* Public group-items: Cleanup            */
/* ====================================== */

DROP FUNCTION geofeature_make_public(IN feat_type TEXT);

/* ==================================================================== */
/* Step (3)(c) -- Make group-items for Link_Values                      */
/* ==================================================================== */

/* ====================================== */
/* Public group-items: Helper fcn.        */
/* ====================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

/* NOTE We need this fcn. in a later script, when moving private items into 
        group_item_access. So it's quasi-temporary; we'll delete it in a later 
        script. */
CREATE FUNCTION gia_link_value_make(IN attc_type TEXT, 
                                    IN feat_type TEXT,
                                    IN value_type TEXT,
                                    IN item_system_id INTEGER,
                                    IN username TEXT)
   RETURNS VOID AS $$
   DECLARE
      item_name_query TEXT;
      value_where_clause TEXT;
      select_group_id TEXT;
      select_access_level_id TEXT;
      src_item_type_id INTEGER;
      link_lhs_type_id_ INTEGER;
      link_rhs_type_id_ INTEGER;
   BEGIN
      /* For attribute link, we want to grab the column whose value_* is set.
         We achieve this by calling this fcn. once for each value type. */
      item_name_query := '''''';  /* The empty string, '' */
      value_where_clause := '';
      IF (value_type != '') THEN
         IF item_system_id IS NOT NULL THEN
            RAISE EXCEPTION '% %', 
               'Programmer error:',
               'Please use either value_type or item_system_id but not both';
         END IF;
         IF (value_type = 'NULL') THEN
            /* If the value_type is not specified by the caller, we're looking
               for null-valued links that we missed, so that we don't leave
               version gaps in group_item_access. See Bug 2620. */
            value_where_clause := 
               'WHERE    
                      attc_geo.value_boolean IS NULL
                  AND attc_geo.value_integer IS NULL
                  AND attc_geo.value_real    IS NULL
                  AND attc_geo.value_text    IS NULL
                  AND attc_geo.value_binary  IS NULL
                  AND attc_geo.value_date    IS NULL
               ';
         ELSE
            IF value_type = 'value_binary' THEN
               /* Hint: postgres hexidecimal output ::HEX, also: to_hex(). */
               item_name_query := 
                  'encode(attc_geo.' || value_type || '::BYTEA, ''hex64'')';
            ELSE
               item_name_query := 'attc_geo.' || value_type || '::TEXT';
            END IF;
            /* BUG nnnn: Does the name based on the value really matter? */
            value_where_clause := 
               'WHERE attc_geo.' || value_type || ' IS NOT NULL';
         END IF;
      ELSIF item_system_id IS NOT NULL THEN
         value_where_clause := 
            'WHERE iv.system_id = ' || item_system_id;
      /* ELSE: No need to use where clause; this is a link_value without a
               value, e.g., tagged-byway. */
      END IF;
      /* Get the group ID if the username is specified. */
      /* NOTE I [lb] know this script *mostly* deals with public items -- this 
              is the only place you'll see anything dealing with private 
              groups, but it's only because I want to reuse this fcn. in a 
              later script! */
      IF username = '' THEN
         select_group_id := cp_group_public_id();
         select_access_level_id := cp_access_level_id('editor');
      ELSE
         /* NOTE: This fcn. fails unless the user has group_membership, which
          *       doesn't happen until the next script. But in this script, 
          *       username is always ''. */
         select_group_id := cp_group_private_id(username);
         /* 2013.04.09: Given the new access_style_id, user's private group
                        should be 'editor', too, since they can't change the
                        permissions of the region.
         select_access_level_id := cp_access_level_id('owner');
         */
         select_access_level_id := cp_access_level_id('editor');
      END IF;
      /* Using inline cp_* fcns. is slow, so cache the values ahead of time. */
      src_item_type_id  := cp_item_type_id('link_value');
      link_lhs_type_id_ := cp_item_type_id(attc_type);
      link_rhs_type_id_ := cp_item_type_id(feat_type);
      /* Run the query. */
      EXECUTE '
         INSERT INTO group_item_access 
               (group_id,
                item_id,
                stack_id,
                version,
                branch_id,
                item_type_id,
                link_lhs_type_id,
                link_rhs_type_id,
                valid_start_rid,
                valid_until_rid,
                deleted,
                name,
                acl_grouping,
                access_level_id)
            (SELECT
               ' || select_group_id || ',
               iv.system_id,
               iv.stack_id,
               iv.version,
               iv.branch_id,
               ' || src_item_type_id  || ',
               ' || link_lhs_type_id_ || ',
               ' || link_rhs_type_id_ || ',
               attc_geo.valid_start_rid,
               attc_geo.valid_until_rid,
               iv.deleted,
               ' || item_name_query || ',
               1, -- the first acl_grouping
               ' || select_access_level_id || '
            FROM ' || attc_type || '_' || feat_type || '_geo AS attc_geo
            JOIN item_versioned AS iv
               ON attc_geo.id = iv.stack_id
                  AND attc_geo.version = iv.version
            ' || value_where_clause || ');';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ====================================== */
/* Public group-items: Apply all          */
/* ====================================== */

\qecho 
\qecho Granting public group access to public link_values
\qecho 

CREATE FUNCTION gia_link_value_make_public_all()
   RETURNS VOID AS $$
   DECLARE
      attc_type_rec RECORD;
      feat_type_rec RECORD;
      do_value_loop BOOLEAN;
      value_type_rec RECORD;
   BEGIN
      /* Create a view for each attachment-geofeature type combination, and 
         also a view for all types. */
      FOR attc_type_rec IN 
            SELECT 'tag' AS name
            UNION (SELECT 'annotation')
            UNION (SELECT 'thread')
            UNION (SELECT 'post')
            UNION (SELECT 'attribute')
               LOOP
         do_value_loop := FALSE;
         IF attc_type_rec.name = 'attribute' THEN
            do_value_loop := TRUE;
         END IF;
         FOR feat_type_rec IN 
               SELECT 'byway' AS name
               UNION (SELECT 'region')
               UNION (SELECT 'terrain')
               UNION (SELECT 'waypoint')
               UNION (SELECT 'route')
                  LOOP
            RAISE INFO '... ''%'' / ''%''', 
               attc_type_rec.name, feat_type_rec.name;
            IF NOT do_value_loop THEN
               RAISE INFO '... skipping value types';
               PERFORM gia_link_value_make(
                        attc_type_rec.name, feat_type_rec.name, '', NULL, '');
            ELSE
               /* We want to populate group-item name by the value_*, so we
                  need to loop through each value column, since only one is 
                  set per row. */
               /* NOTE Only byways have attrs; this is a no-op for the rest */
               RAISE INFO '... populating value types';
               --RAISE INFO '...... NOTE: value_integer takes forevs, dude:';
               --RAISE INFO '......   2010.12.xx: colo- 65+ mins, minn- 172+';
               --RAISE INFO '......   2011.01.26: colo + minn took 8 hours!';
               --RAISE INFO '......   2011.04.24: colo + minn took 1 minute!';
               --RAISE INFO '......   2011.04.25: colo taking longer...';
               --RAISE INFO '......   2011.04.28: back to being quick...';
               FOR value_type_rec IN 
                     SELECT 'NULL' AS name -- Do once for NULLs (so name is '')
                     UNION (SELECT 'value_boolean')
                     UNION (SELECT 'value_integer')
                     UNION (SELECT 'value_real')
                     UNION (SELECT 'value_text')
                     UNION (SELECT 'value_binary')
                     UNION (SELECT 'value_date') LOOP
                  RAISE INFO '... value type: ''%''', value_type_rec.name;
                  IF ((attc_type_rec.name = 'attribute')
                      AND (feat_type_rec.name = 'byway')
                      AND (value_type_rec.name = 'NULL')) THEN
                     -- FIXME: This could be because I used --novacu
                     /* PERFORMANCE: Search: Slow V1->V2 ops. */
                     RAISE INFO 
                        '2012.09.23: Time: 0m 0s [co: 10h 0m 3s] (--novacu)';
                  END IF;
                  PERFORM gia_link_value_make(attc_type_rec.name, 
                                              feat_type_rec.name, 
                                              value_type_rec.name,
                                              NULL, 
                                              '');
               END LOOP;
            END IF;
         END LOOP;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* FINDME / TESTING Comment-out if you want to test without waiting. */
SELECT gia_link_value_make_public_all();

DROP FUNCTION gia_link_value_make_public_all();

/* NOTE As mentioned above, we'll consume the following later:
           region_watched
           region_work_hint
           route 
           track
           */

/* ============================================== */
/* Convert post_revision links (they're special!) */
/* ============================================== */

\qecho 
\qecho Granting public group access to public post_revision link_values
\qecho 

-- C.f. gia_link_value_make
CREATE FUNCTION gia_link_value_make_for_attr(IN attr_internal_name TEXT,
                                             IN lhs_type TEXT)
   RETURNS VOID AS $$
   DECLARE
      src_item_type_id INTEGER;
      link_lhs_type_id_ INTEGER;
      link_rhs_type_id_ INTEGER;
      attr_stack_id INTEGER;
      select_group_id TEXT;
      select_access_level_id TEXT;
   BEGIN
      src_item_type_id := cp_item_type_id('link_value');
      link_lhs_type_id_ := cp_item_type_id(lhs_type);
      link_rhs_type_id_ := cp_item_type_id('attribute');
      EXECUTE 'SELECT DISTINCT stack_id FROM attribute 
               WHERE value_internal_name = ''' || attr_internal_name || ''';'
         INTO STRICT attr_stack_id;
      select_group_id := cp_group_public_id();
      select_access_level_id := cp_access_level_id('editor');
      EXECUTE '
         INSERT INTO group_item_access 
               (group_id,
                item_id,
                stack_id,
                version,
                branch_id,
                item_type_id,
                link_lhs_type_id,
                link_rhs_type_id,
                valid_start_rid,
                valid_until_rid,
                deleted,
                name,
                acl_grouping,
                access_level_id)
            (SELECT
               ' || select_group_id || ',
               iv.system_id,
               iv.stack_id,
               iv.version,
               iv.branch_id,
               ' || src_item_type_id || ',
               ' || link_lhs_type_id_ || ',
               ' || link_rhs_type_id_ || ',
               iv.valid_start_rid,
               iv.valid_until_rid,
               iv.deleted,
               lv.value_integer::TEXT,
               1, -- the first acl_grouping
               ' || select_access_level_id || '
            FROM
               link_value AS lv
            JOIN
               item_versioned AS iv
               ON lv.stack_id = iv.stack_id
                  AND lv.version = iv.version
            WHERE 
               lv.rhs_stack_id = ' || attr_stack_id || ');';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT gia_link_value_make_for_attr('/post/revision', 'post');

DROP FUNCTION gia_link_value_make_for_attr(IN attr_internal_name TEXT,
                                           IN lhs_type TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

