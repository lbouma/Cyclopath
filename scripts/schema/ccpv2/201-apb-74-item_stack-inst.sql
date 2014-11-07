/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script sets up the item_stack table. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho
\qecho This script sets up the item_stack table.
\qecho
\qecho [EXEC. TIME: 2013.04.23/runic:  31.87 min. [mn] {oops, missing where}]
\qecho [EXEC. TIME: 2013.04.??/runic:   0.93 min. [mn] {fixed!}]
\qecho


BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho 
\qecho 
\qecho 

/* 
 * item_stack */

/* 2012.09.20: Adding item_stack to CcpV2 to accommodate Route Sharing. */

\qecho Altering item_versioned table.

/* Now that we've populated item_stack, we can set stack_id NOT NULL. */
ALTER TABLE item_versioned ALTER COLUMN stack_id SET NOT NULL;

/* Rename item_versioned_id_seq. 
   See 201-apb-31..., we've already done this.
ALTER TABLE item_versioned_stack_id_seq RENAME TO item_stack_stack_id_seq;
*/

\qecho Creating item_stack table.

CREATE TABLE item_stack (
   stack_id INTEGER DEFAULT nextval('item_stack_stack_id_seq') NOT NULL,
   /* Note: creator_name is not necessarily redundant. For revisioned items,
            you can just get item_versioned.version = 1 and join for 
            revision.username. But for revisionless items, you'd have to join 
            against group_item_access and then reduce to just one row (since 
            there could be multiple GIA records. So it seems easier to just 
            store the creator's username here. */
   /* NOTE: revision.username is sometimes NULL. So don't use NOT NULL. */
   creator_name TEXT,
   stealth_secret UUID,
   /* 2012.09.20: Route Sharing introduces cloned_from_id, but I'm [lb] not
      sure why we store it: the value is only used by pyserver during the clone
      operation and is never used again. Nonetheless, maybe it'll be useful in 
      the future: if anything, it provides a more robust audit trail. */
   /* NOTE: cloned_from_id is the item's system_id, since we clone a specific
            version of an item; in CcpV1, it was just the stack_id, but it 
            implied the second-to-last version of the original item, since the
            final item version is the one marked deleted. */
   cloned_from_id INTEGER,
   /* 2012.09.30: Store the access_style, which we need to know later if the
                  user wants to change permissions on an item. */
   access_style_id INTEGER NOT NULL,
   /* 2013.04.18: Oh, boy, this is a reimplementation of what flashclient was
                  trying to infer as access_scope based on what few details it
                  had. But the route library -- which sends checkout and asks
                  for item_stack details, but doesn't get group_item_access
                  records -- doesn't have enough information to tell the user
                  if the routes in the list are private, public, shared,
                  editable, etc., like we do in CcpV1. So we really do need to
                  maintain a cache value that indicates what kind of access
                  users have to this item. Fortunately, the type of this value
                  also doubles as the value used to change GIA records for
                  access_style 'restricted'. */
   access_infer_id INTEGER NOT NULL
);

ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_pkey
   PRIMARY KEY (stack_id);

ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_creator_name_fkey
   FOREIGN KEY (creator_name) REFERENCES user_ (username) DEFERRABLE;

ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_stealth_secret_unique
   UNIQUE (stealth_secret);

ALTER TABLE item_stack
   ADD CONSTRAINT item_stack_cloned_from_id_fkey
   FOREIGN KEY (cloned_from_id) REFERENCES item_versioned (system_id)
      DEFERRABLE;

/* Create reserved UUIDs. */

/* 2012.09.20:
ccpv2=> select min(stack_id) from item_versioned;
  min   
--------
 367669
(1 row)

ccpv2=> insert into test (value) values (2147483647);
INSERT 0 1
ccpv2=> insert into test (value) values (2147483648);
ERROR:  integer out of range
>>> math.pow(2,31)
2147483648.0
*/

/* 2012.09.20: [lb] isn't sure we need to reserve these... but that's 
               the M.O. of firmware and hardware designers, so what the
               hey. */
-- BUG nnnn: Server-assigned session IDs. Claim these two GUIDs when you 
--           implement the new user__session table.

\qecho Creating special UUID stealth_secrets.

--INSERT INTO item_stack (stack_id, creator_name, stealth_secret)
--VALUES (0, '_script', 
--   '00000000-0000-0000-0000-000000000000'::UUID);
INSERT INTO item_stack
   (stack_id, stealth_secret, access_style_id, access_infer_id)
   VALUES (
      0,
      '00000000-0000-0000-0000-000000000000'::UUID,
      cp_access_style_id('all_denied'),
      cp_access_infer_id('not_determined')
      );

--INSERT INTO item_stack (stack_id, creator_name, stealth_secret)
--VALUES (2147483647, '_script', 
--   'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF'::UUID);
-- Note that item_stack_stack_id_seq goes to 9223372036854775807...
--           but the postgres INTEGER value only goes to 2^31.
-- BUG nnnn?: ALTER TABLE item_stack ALTER COLUMN stack_ID BIGINT;
--            though Postgres says performance isn't as good as INT.
INSERT INTO item_stack
   (stack_id, stealth_secret, access_style_id, access_infer_id)
   VALUES (
      2147483647,
      'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF'::UUID,
      cp_access_style_id('all_denied'),
      cp_access_infer_id('not_determined')
      );

/* Populate the new table. */

\qecho Creating item_stack_populate_stealth_secret fcn.

CREATE FUNCTION item_stack_populate_stealth_secret()
   RETURNS VOID AS $$
   DECLARE
      route RECORD;
   BEGIN
      /* This fcn. is deprecated (we do a simple update instead; see below),
         but it's still got some comments in it... */
      RAISE EXCEPTION 'Deprecated.';
      -- Create view for each geofeature type
      /* 2012.09.20: All route versions have the same link_hash_id, i.e., none
                     have null link_hash_id if at least have one set. 
            SELECT id, version, link_hash_id FROM route 
               WHERE link_hash_id IS NOT NULL
               ORDER BY id ASC, version DESC;
         */
      FOR route IN 
            SELECT DISTINCT ON (link_hash_id) link_hash_id, id, version
            FROM archive_@@@instance@@@_1.route
            WHERE link_hash_id IS NOT NULL
            ORDER BY link_hash_id, id DESC, version DESC
      LOOP

/* FIXME: The UUID is shared btw. routes with different stack IDs but 
          on the same cloned_from_id lineage...
          
we should either make 'em unique for the different routes (or delete the uuid 
for the early routes, since it's used independent of the stack ID, i.e., the 
   client just sends the uuid and we find the non-deleted one. so maybe 
   just delete the uuid for early versions before doing the update...
   see the code for the aadt table? or maybe order by uuid...

FIXME: Just using DISTINCT doesn't work? I thought it did!
You need to audit other places you don't distinct on!
Without the ON, it works only if select has just one column named...
FIXME: Add this to the SQL Wiki page.

does not work:
SELECT DISTINCT(link_hash_id), id, version 
            FROM archive_minnesota_1.route WHERE link_hash_id IS NOT NULL
            ORDER BY link_hash_id, id DESC, version DESC;

works:
SELECT DISTINCT ON (link_hash_id) link_hash_id, id, version 
            FROM archive_minnesota_1.route WHERE link_hash_id IS NOT NULL
            ORDER BY link_hash_id, id DESC, version DESC;

*/

         UPDATE item_stack SET stealth_secret = route.link_hash_id::UUID
            WHERE item_stack.stack_id = route.id;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho Creating item_stack_populate_cloned_from_id fcn.

CREATE FUNCTION item_stack_populate_cloned_from_id()
   RETURNS VOID AS $$
   DECLARE
      route RECORD;
   BEGIN
      -- Create view for each geofeature type
      /* 2012.09.20: Only version 1 has cloned_from_id set.
            SELECT id, version, cloned_from_id FROM route 
               WHERE cloned_from_id IS NOT NULL
               ORDER BY id ASC, version DESC;
         */

      -- NOTE: In the original table, cloned_from_id is the stack ID.
      FOR route IN 
            SELECT DISTINCT ON (id) id, version, cloned_from_id 
            FROM archive_@@@instance@@@_1.route
            WHERE cloned_from_id IS NOT NULL
            GROUP BY id, version, cloned_from_id
            ORDER BY id ASC, version ASC
      LOOP
         /* CHEAT: We should say that the cloned_from_id is item with the 
            version of the second-to-last item it that stack, since the last 
            version is the one that got marked deleted when the route was 
            cloned. But that's tedious to compute, and the cloned_from_id isn't
            used for anything; in the future, if we care, we can always 
            recompute this value correctly. (Just know the revision when CcpV2 
            is released so we only compute values for rows from before then.) 
         */
         UPDATE item_stack SET cloned_from_id = 
            (SELECT system_id FROM item_versioned
             WHERE ((stack_id = route.cloned_from_id)
                    AND (version = 1)))
            WHERE item_stack.stack_id = route.id;
      END LOOP;

-- FIXME: How does his method of doing it compare to previous LOOP?

      CREATE TEMPORARY TABLE cloned_from_lookup (
         new_stack_id INTEGER,
         cloned_from_id INTEGER
      );
      INSERT INTO cloned_from_lookup
         (new_stack_id, cloned_from_id)
         (SELECT 
            bar.new_stack_id, iv.system_id AS cloned_from_id
               FROM (
                  SELECT 
                     foo.stack_id AS old_stack_id,
                     CASE 
                        WHEN (foo.version = 1) THEN 1
                        ELSE (foo.version - 1)
                        END AS old_version,
                     new_stack_id
                  FROM (
                     SELECT
                        DISTINCT ON (iv.stack_id, iv.version) iv.stack_id,
                        iv.version,
                        rt.id AS new_stack_id
                     FROM archive_@@@instance@@@_1.route AS rt
                     JOIN item_versioned AS iv 
                        ON (iv.stack_id = rt.cloned_from_id)
                     ORDER BY iv.stack_id ASC, iv.version DESC
                  ) AS foo
               ) AS bar
               JOIN item_versioned AS iv
                  ON (bar.old_stack_id = iv.stack_id 
                      AND bar.old_version = iv.version)
            );
      UPDATE item_stack SET cloned_from_id = foo.cloned_from_id
      FROM (SELECT new_stack_id, cloned_from_id FROM cloned_from_lookup)
         AS foo(new_stack_id, cloned_from_id)
      WHERE item_stack.stack_id = foo.new_stack_id;

   END;
$$ LANGUAGE plpgsql VOLATILE;

/*
SELECT id, version AS ver, owner_name, host, source, 
   cloned_from_id AS cloned_id,
   permission AS prm, visibility AS vis
   FROM route WHERE id IN (1556817, 1556816)
   ORDER BY id ASC, version DESC;

SELECT id, version AS ver, deleted AS del, 
   owner_name, host, source, 
   cloned_from_id AS cloned_id,
   permission AS prm, visibility AS vis
   FROM route
   ORDER BY id DESC, version DESC;


   id    | ver | del |        owner_name        |      host       |   source    | cloned_id | prm | vis 
---------+-----+-----+--------------------------+-----------------+-------------+-----------+-----+-----

--

 1577765 |   1 | f   | rosa3267                 | 140.209.104.84  | put_feature |   1577764 |   3 |   2
 1577764 |   2 | t   | rosa3267                 | 140.209.104.84  | put_feature |           |   3 |   3
 1577764 |   1 | f   | rosa3267                 | 140.209.104.84  | history     |           |   3 |   3

 1575034 |   1 | f   | jakre                    | 75.72.149.175   | put_feature |   1575033 |   3 |   2
 1575033 |   2 | t   |                          | 75.72.149.175   | put_feature |           |   3 |   3
 1575033 |   1 | f   |                          | 75.72.149.175   | deeplink    |           |   3 |   3

 1577671 |   1 | f   | sfyetter                 | 192.28.0.17     | put_feature |   1577632 |   2 |   2
 1577632 |   3 | t   | sfyetter                 | 192.28.0.17     | put_feature |           |   3 |   2
 1577632 |   2 | f   | sfyetter                 | 192.28.0.17     | put_feature |           |   3 |   2
 1577632 |   1 | f   | sfyetter                 | 192.28.0.17     | put_feature |   1577629 |   3 |   2
 1577629 |   2 | t   | sfyetter                 | 192.28.0.17     | put_feature |           |   3 |   3
 1577629 |   1 | f   | sfyetter                 | 192.28.0.17     | top         |           |   3 |   3

 1574882 |   1 | f   | tsochoo                  | 70.57.156.81    | put_feature |   1574881 |   2 |   2
 1574881 |   2 | t   | tsochoo                  | 70.57.156.81    | put_feature |           |   3 |   2
 1574881 |   1 | f   | tsochoo                  | 70.57.156.81    | put_feature |   1574880 |   3 |   2
 1574880 |   2 | t   | tsochoo                  | 70.57.156.81    | put_feature |           |   3 |   3
 1574880 |   1 | f   | tsochoo                  | 70.57.156.81    | deeplink    |           |   3 |   3

--

why no owner_name?
maybe because user just made a link_hash_id but didn't add to library... TEST THIS

 1577571 |   1 | f   |                          | 64.131.43.74    | deeplink    |   1577569 |   2 |   3
 1577569 |   2 | t   |                          | 64.131.43.74    | deeplink    |           |   3 |   3
 1577569 |   1 | f   |                          | 64.131.43.74    | deeplink    |           |   3 |   3

so this is someone making a link_hash_id and then making the route public with same session_id?
 1576517 |   1 | f   |                          | 205.215.177.149 | put_feature |   1576516 |   1 |   1
 1576516 |   2 | t   |                          | 205.215.177.149 | put_feature |           |   2 |   3
 1576516 |   1 | f   |                          | 205.215.177.149 | deeplink    |   1576515 |   2 |   3
 1576515 |   2 | t   |                          | 205.215.177.149 | deeplink    |           |   3 |   3
 1576515 |   1 | f   |                          | 205.215.177.149 | deeplink    |           |   3 |   3

--

note: cloned_from_id only set for version 1...
 1577393 |   2 | f   |                          | 156.98.14.252   | put_feature |           |   1 |   1
 1577393 |   1 | f   |                          | 156.98.14.252   | put_feature |   1577388 |   1 |   1
 1577388 |   2 | t   |                          | 156.98.14.252   | put_feature |           |   3 |   3
 1577388 |   1 | f   |                          | 156.98.14.252   | deeplink    |           |   3 |   3

 1574825 |   1 | f   |                          | 198.102.39.250  | put_feature |   1574824 |   1 |   1
 1574824 |   2 | t   |                          | 198.102.39.250  | put_feature |           |   2 |   3
 1574824 |   1 | f   |                          | 198.102.39.250  | deeplink    |   1574823 |   2 |   3
 1574823 |   2 | t   |                          | 198.102.39.250  | deeplink    |           |   3 |   3
 1574823 |   1 | f   |                          | 198.102.39.250  | deeplink    |           |   3 |   3

--

 1574943 |   1 | f   | frankwalsh1914           | 97.116.171.253  | put_feature |   1574940 |   2 |   2
 1574940 |   2 | t   |                          | 97.116.171.253  | put_feature |           |   2 |   3
 1574940 |   1 | f   |                          | 97.116.171.253  | deeplink    |   1574939 |   2 |   3
 1574939 |   2 | t   |                          | 97.116.171.253  | deeplink    |           |   3 |   3
 1574939 |   1 | f   |                          | 97.116.171.253  | deeplink    |           |   3 |   3

*/

/*
BUG nnnn: Search for version = 0. Put in auditor, too.

Sep-20 21:31:46  DEBG         schema-up  #  WARNING:  item_stack_populate: unexpected version: 0 / sid: 1366184
Sep-20 21:31:46  ERRR         schema-up  #  
One or more fatal errors or warnings detected.
Sep-20 21:31:46  DEBG         schema-up  #  WARNING:  item_stack_populate: unexpected version: 0 / sid: 1366185

select * from item_versioned where stack_id = 1366184;
Eden Prairie is the name...
1366185 is Buffalo
Both are rev 0 to rid_inf, 1 version only, not deleted.
*/

\qecho Populating item_stack table: stack_id...

/* 2012.11.24: Don't forget to use LEFT OUTER since some item's have stack IDs
               set to 0 or 1. */
-- MAGIC_NUMBER: Access_Style.all_denied == 9.
/* Use DO to make a simple fcn. so you can define a local variable and avoid
   using a fcn. in a WHERE clause, which is super, super slow. Oh, wait, DO
   is not introduced until Postgres 8.5. We still have to use FUNCTIONs.... */
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   access_style_id_ := cp_access_style_id('all_denied');
   access_infer_id_ := cp_access_infer_id('not_determined');
   INSERT INTO item_stack
         (stack_id, creator_name, access_style_id, access_infer_id)
      SELECT
         DISTINCT ON (iv.stack_id) iv.stack_id,
         rev.username,
         access_style_id_,
         access_infer_id_
      FROM item_versioned AS iv
      LEFT OUTER JOIN revision AS rev
         ON (rev.id = iv.valid_start_rid)
      GROUP BY
         iv.stack_id,
         rev.username;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

\qecho Populating item_stack table: stealth_secret...

/* I don't think we need this fcn. A simple UPDATE should work.
     SELECT item_stack_populate_stealth_secret(); */
UPDATE item_stack
   SET stealth_secret = foo.link_hash_id::UUID
   FROM (
      SELECT DISTINCT ON (link_hash_id) link_hash_id, id AS stack_id, version
      FROM archive_@@@instance@@@_1.route
      WHERE
         link_hash_id IS NOT NULL
      GROUP BY
         link_hash_id,
         id,
         version
      ORDER BY
         link_hash_id,
         id DESC,
         version DESC
   ) AS foo
   WHERE
      item_stack.stack_id = foo.stack_id;

\qecho Populating item_stack table: cloned_from_id...

SELECT item_stack_populate_cloned_from_id();

/* */

\qecho Making GIA records for stealth secrets...

CREATE FUNCTION route_make_gia_for_stealth_secret()
   RETURNS VOID AS $$
   DECLARE
      item_rec RECORD;
   BEGIN
      FOR item_rec IN
            SELECT
               itmv.system_id,
               itmv.stack_id,
               itmv.version,
               itmv.name,
               itmv.deleted,
               itmv.reverted,
               itmv.branch_id,
               itmv.valid_start_rid,
               itmv.valid_until_rid,
               itms.stealth_secret
            FROM route AS rt
            JOIN item_versioned AS itmv
               ON (rt.system_id = itmv.system_id)
            JOIN item_stack AS itms
               ON (itmv.stack_id = itms.stack_id)
            WHERE itms.stealth_secret IS NOT NULL
      LOOP
         INSERT INTO group_item_access 
            (group_id,
             session_id,
             access_level_id,
             name,
             deleted,
             reverted,
             branch_id,
             item_id,
             stack_id,
             version,
             valid_start_rid,
             valid_until_rid,
             acl_grouping,
             item_type_id
            )
         VALUES
            (cp_group_stealth_id(),
             NULL,
             cp_access_level_id('viewer'),
             item_rec.name,
             item_rec.deleted,
             item_rec.reverted,
             item_rec.branch_id,
             item_rec.system_id,
             item_rec.stack_id,
             item_rec.version,
             item_rec.valid_start_rid,
             item_rec.valid_until_rid,
             1, -- the first acl_grouping
             cp_item_type_id('route')
            );
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NO: We've already made the stealth secret records.
       See passage_make_group_items in 201-apb-60-groups-pvt_ins3.sql.
SELECT route_make_gia_for_stealth_secret();
*/

DROP FUNCTION route_make_gia_for_stealth_secret();

/* */

\qecho Updating item_stack.creator_name from revision.

/*

NOTE: Mirror revision.username as item_stack.created_by. This
is solely to make searching by username quicker, so we don't
have to join the revision table against the massive item join.

We don't care about the timestamp, though: if a user searches
by timestamp, we'll look in the revision table in one query to
determine what revision to use in the item checkout; and if a
user wants the first version's timestamp, they're probably just
lazy-loading one item, i.e., like how access_style_id is lazy-
loaded by flashclient. And if we're only getting one item,
joining against revision outside the item query is perfect.

-- Sandbox --

Get counts of users' revisions:

SELECT username, count FROM
   (SELECT DISTINCT ON (username) username, count(*)
      -- , itm.branch_id AS itm_brid
      -- , rev.branch_id AS rev_brid
    FROM item_versioned AS itm
    JOIN revision AS rev
      ON (rev.id = itm.valid_start_rid)
    WHERE itm.version = 1
    GROUP BY username ORDER BY username
   ) AS foo
   ORDER BY count DESC ;
 */

UPDATE item_stack
   SET creator_name = username
   FROM (
      SELECT DISTINCT ON (itm.stack_id) itm.stack_id, username
      FROM item_versioned AS itm
      JOIN revision AS rev
         ON (rev.id = itm.valid_start_rid)
      LEFT OUTER JOIN route AS rte
         ON (rte.stack_id = itm.stack_id)
      LEFT OUTER JOIN track AS trk
         ON (trk.stack_id = itm.stack_id)
      WHERE
         itm.version = 1
         AND rev.username IS NOT NULL
         -- Ignores routes and tracks; we'll snag their created_bys next.
         AND rte.stack_id IS NULL
         AND trk.stack_id IS NULL
         -- Opposite:
         --    AND (   rte.stack_id IS NOT NULL
         --         OR trk.stack_id IS NOT NULL)
      GROUP BY
         itm.stack_id
         , rev.username
      ORDER BY
         itm.stack_id
   ) AS foo
   WHERE
      item_stack.stack_id = foo.stack_id;

/* The route and track tables have their own creator_name-ish columns.
   These item types aren't revisioned in CcpV1, and during our schema
   update, when we consumed routes and tracks, we set all their rids to
   the same revision whose username is '_script'. So fix these now.
   */

\qecho Updating item_stack.creator_name from route.

UPDATE item_stack
   SET creator_name = foo.created_by
   FROM (
      SELECT DISTINCT ON (stack_id) stack_id, version, created_by
      FROM route
      WHERE
         created_by IS NOT NULL
      GROUP BY
         stack_id,
         version,
         created_by
      ORDER BY
         stack_id DESC,
         version DESC
   ) AS foo
   WHERE
      item_stack.stack_id = foo.stack_id;

\qecho Updating item_stack.creator_name from track.

UPDATE item_stack
   SET creator_name = foo.created_by
   FROM (
      SELECT DISTINCT ON (stack_id) stack_id, version, created_by
      FROM track
      WHERE
         created_by IS NOT NULL
      GROUP BY
         stack_id,
         version,
         created_by
      ORDER BY
         stack_id DESC,
         version DESC
   ) AS foo
   WHERE
      item_stack.stack_id = foo.stack_id;

\qecho Dropping route.created_by and track.created_by.

ALTER TABLE route DROP COLUMN created_by;

ALTER TABLE track DROP COLUMN created_by;

\qecho

/* ============================================================ */

/* Populate access_style.
 */

/* MAYBE: Permissive lets you add GIA records for other groups.
 *        But once added, you can only mark groups denied... like, maybe you
 *        can't elimate them from your list (or maybe the client just hides the
 *        ones that are denied when you start a new session). */

/* 2012.10.02: MAYBE: Don't bother setting access_style unless it
   matters. I.e., if usr_editor, pub_editor, usr_choice, pub_choice, or
   all_denied doesn't matter: these types of items cannot have their
   permissions changed once created. So we only care about the other
   access_style types, e.g., 'restricted' and 'permissive'. */

/* NOTE: Starting with the branch. The UPDATEs are precarious: if you mess up a
         SELECT, you might UPDATE records you don't mean to update. By starting
         with the branch, if that case does happen, the make_new_branch.py
         script, which runs shortly after the V1->V2 sql schema scripts, will
         catch the problem (it asserts that the public basemap branch's
         access_style_id is 'permissive'). */

-- geofeature_layer_id.branch == 109
\qecho UPDATE item_stack: branch (1)
\qecho
UPDATE item_stack
   SET access_style_id = cp_access_style_id('permissive'),
       access_infer_id = cp_access_infer_id('not_determined')
   FROM branch AS br
   WHERE br.stack_id = item_stack.stack_id;

/* */

-- geofeature_layer_id.route == 105
\qecho UPDATE item_stack: all routes (126426)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   access_style_id_ := cp_access_style_id('restricted');
   access_infer_id_ := cp_access_infer_id('not_determined');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM route AS rt
      WHERE rt.stack_id = item_stack.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

/* See 201-apb-60-groups-pvt_ins3.sql */
/*
   ccpv3=> select x'07' | x'08';
    ?column? 
   ----------
    00001111
*/
-- 1,1 records are all publicly editable.
\qecho UPDATE item_stack: 1, 1 (160)
\qecho
UPDATE item_stack
   SET access_infer_id = cp_access_infer_id('pub_editor')
   FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                          AND visibility = 1 AND permission = 1;

-- 1,2 records are all publicly viewable but arbited by the creator.
\qecho UPDATE item_stack: 1, 2 (40)
\qecho
UPDATE item_stack
   SET access_infer_id = (cp_access_infer_id('usr_arbiter')
                          | cp_access_infer_id('pub_viewer'))
   FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                          AND visibility = 1 AND permission = 2;

-- 2,2 records are all stealthfully viewable and arbited by the creator.
\qecho UPDATE item_stack: 2, 2 (29)
\qecho
UPDATE item_stack
   SET access_infer_id = (cp_access_infer_id('usr_arbiter')
                          | cp_access_infer_id('stealth_viewer'))
   FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                          AND visibility = 2 AND permission = 2;

-- 2,3 records are private and arbited by the creator.
\qecho UPDATE item_stack: 2, 3 (291)
\qecho
UPDATE item_stack
   SET access_infer_id = cp_access_infer_id('usr_arbiter')
   FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                          AND visibility = 2 AND permission = 3;

-- Some 3,2 records are stealthfully viewable and arbited by the creator...
\qecho UPDATE item_stack: 3, 2 / normal (1167)
\qecho
UPDATE item_stack
   SET access_infer_id = (cp_access_infer_id('usr_arbiter')
                          | cp_access_infer_id('stealth_viewer'))
   FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                          AND visibility = 3 AND permission = 2;

-- ... and some 3,2 records are also publicly viewable (those in reactions).
\qecho UPDATE item_stack: 3, 2 / reactions (23)
\qecho
UPDATE item_stack
   SET access_infer_id = (cp_access_infer_id('usr_arbiter')
                          | cp_access_infer_id('stealth_viewer')
                          | cp_access_infer_id('pub_viewer'))
   FROM route AS rt
   JOIN archive_@@@instance@@@_1.post_route AS prt
      ON (prt.route_id = rt.stack_id)
   WHERE rt.stack_id = item_stack.stack_id
      AND visibility = 3 AND permission = 2;

-- 3,3 records are private and arbited by the creator (like 2,3).
\qecho UPDATE item_stack: 3, 3 (124739)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_infer_id_ INTEGER;
BEGIN
   access_infer_id_ := cp_access_infer_id('usr_arbiter');
   UPDATE item_stack
      SET access_infer_id = access_infer_id_
      FROM route AS rt WHERE rt.stack_id = item_stack.stack_id
                             AND visibility = 3 AND permission = 3;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

-- geofeature_layer_id.track == 106
\qecho UPDATE item_stack: track (108)
\qecho
UPDATE item_stack
   SET access_style_id = cp_access_style_id('restricted'),
       -- Tracks are currently all private to the user.
       access_infer_id = cp_access_infer_id('usr_arbiter')
   FROM track AS tk
   WHERE tk.stack_id = item_stack.stack_id;

/* Byways, terrain, and waypoints. */
\qecho UPDATE item_stack: geofeature (177613)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   access_style_id_ := cp_access_style_id('pub_editor');
   access_infer_id_ := cp_access_infer_id('pub_editor');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM (
         SELECT DISTINCT ON (stack_id) stack_id
         FROM geofeature AS gf
         WHERE gf.geofeature_layer_id IN
            -- Byways, terrain, and waypoints.
            -- Not set yet: Major Trail == 110
            (1,2,11,14,15,16,17,21,31,41,42,101,102,103)
      ) AS foo
      WHERE item_stack.stack_id = foo.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

/* Before, user's were owners of private regions. Now,
   users are editors who are not owners because they cannot
   change permissions of regions, but only delete them or make a
   public clone.

   Annontations and Regions all have one GIA editor record -- either to the
   public group or to a private user group. Use the group ID to retroactively
   determine the access_style.
   */

/* Private CcpV1 user watch regions and associated notes. */
\qecho UPDATE item_stack: private regions and notes (330)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   public_group_id_ INTEGER;
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   public_group_id_ := cp_group_public_id();
   access_style_id_ := cp_access_style_id('usr_editor');
   access_infer_id_ := cp_access_infer_id('usr_editor');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM (
         SELECT DISTINCT ON (stack_id) stack_id, access_level_id, group_id
         FROM group_item_access AS gia
         WHERE
            -- geofeature_layer_id.region == 104,108
            -- Item_Type.region == 9
            -- Item_Type.annotation == 4
            gia.item_type_id IN (4, 9)
            AND group_id != public_group_id_
         ) AS foo
      WHERE foo.stack_id = item_stack.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

/* The same as previous except using pub_editor not usr_editor and = not !=.
   These are public regions and their notes.
    */
\qecho UPDATE item_stack: public regions and notes (4526)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   public_group_id_ INTEGER;
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   public_group_id_ := cp_group_public_id();
   access_style_id_ := cp_access_style_id('pub_editor');
   access_infer_id_ := cp_access_infer_id('pub_editor');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM (
         SELECT DISTINCT ON (stack_id) stack_id, access_level_id, group_id
         FROM group_item_access AS gia
         WHERE
            -- geofeature_layer_id.region == 104,108
            -- Item_Type.region == 9
            -- Item_Type.annotation == 4
            gia.item_type_id IN (4, 9)
            AND group_id = public_group_id_
         ) AS foo
      WHERE foo.stack_id = item_stack.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

/* Skipping: link_values... they'll all default to all_denied, which is good.
   */

/* Attachments. */

/* MEH: Should post and threads just be marked pub_editor?
        It doesn't matter since you can't change permissions
        of existing threads or posts. */
\qecho UPDATE item_stack: post (405)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   access_style_id_ := cp_access_style_id('pub_editor');
   access_infer_id_ := cp_access_infer_id('pub_editor');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM post
      WHERE post.stack_id = item_stack.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

\qecho UPDATE item_stack: thread (290)
\qecho
CREATE FUNCTION _inline() RETURNS VOID AS $$
DECLARE
   access_style_id_ INTEGER;
   access_infer_id_ INTEGER;
BEGIN
   access_style_id_ := cp_access_style_id('pub_editor');
   access_infer_id_ := cp_access_infer_id('pub_editor');
   UPDATE item_stack
      SET access_style_id = access_style_id_,
          access_infer_id = access_infer_id_
      FROM thread
      WHERE thread.stack_id = item_stack.stack_id;
END; $$ LANGUAGE plpgsql VOLATILE;
SELECT _inline();
DROP FUNCTION _inline();

/* Existing attributes are not editable. But that's controlled by GIA records.
 * For what they originally were, we'll just say pub_editor, which has the same
 * effect as saying usr_editor or all_denied: these attributes cannot have
 * their permissions changed. */
\qecho UPDATE item_stack: attribute (11)
\qecho
UPDATE item_stack
   -- SET access_style_id = cp_access_style_id('usr_editor')
   SET access_style_id = cp_access_style_id('all_denied'),
       access_infer_id = cp_access_infer_id('pub_viewer')
   FROM attribute
   WHERE attribute.stack_id = item_stack.stack_id;

/* Tags are all public. */
\qecho UPDATE item_stack: tag (826)
\qecho
UPDATE item_stack
   SET access_style_id = cp_access_style_id('pub_editor'),
       access_infer_id = cp_access_infer_id('pub_editor')
   FROM tag
   WHERE tag.stack_id = item_stack.stack_id;

/* There are more item types that we could update with a more appropriate
   Access_Style, but it doesn't matter if we leave some set to access_denied.
*/

/* ============================================================ */

/* Add foreign key constrainst.
 */

/* FIXME: Are there other tables that need this? */

\qecho
\qecho To item_findability: Add foreign key constaint
\qecho

ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_item_stack_id_fkey
   FOREIGN KEY (item_stack_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;

/* ============================================================ */

/* Cleanup. */

\qecho
\qecho Cleaning up
\qecho

DROP FUNCTION item_stack_populate_cloned_from_id();

DROP FUNCTION item_stack_populate_stealth_secret();

/* Not dropping columns until we're confident
   we made the changes correctly. See a later
   script.

\qecho 
\qecho Dropping old access control stuff.
\qecho 

ALTER TABLE route DROP COLUMN permission;
ALTER TABLE route DROP COLUMN visibility;

ALTER TABLE track DROP COLUMN permission;
ALTER TABLE track DROP COLUMN visibility;

DROP TABLE route_view;

*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

\qecho Committing... takes about ten seconds.

COMMIT;

