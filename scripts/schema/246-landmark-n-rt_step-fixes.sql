/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Fixes to A Handful of Recently-Discovered Errors...
\qecho
\qecho 2014.05.22: Expected Runtime: ~1 hr. 11 mins.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Get Ready
\qecho

-- We cannot drop some table constraints after editing rows, e.g.,
--    ERROR:  cannot ALTER TABLE "group_item_access"
--            because it has pending trigger events
-- So do it now.

SELECT cp_constraint_drop_safe('geofeature',
            'geofeature_branch_id_stack_id_version_fkey');
SELECT cp_constraint_drop_safe('geofeature',
            'geofeature_system_id_branch_id_stack_id_version_fkey');
SELECT cp_constraint_drop_safe('group_item_access',
            'group_item_access_branch_id_stack_id_version_fkey');

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Landmarks
\qecho

/* The original Landmarks code had a bug: it always fetched the latest
   version of a route. Unfortunately, one route was edited, and a few
   users interacted with a different version of the route than other users.

   Here, we add the route_system_id so that we can lock on to a specific
   route. We also have to guess about the one route that was edited. We
   can sort of use a timestamp in the database to guess what version of
   the route the user saw.

   Check Landmarks tables for route IDs. These two use route IDs:
      landmark_exp_route
      landmark_exp_landmarks
   but none of these do, so we can ignore them:
      landmark_exp_feedback
      landmark_experiment
      landmark_prompt
      landmark_trial
*/

CREATE FUNCTION cp_alter_table_landmark_exp_route()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE landmark_exp_route
            RENAME COLUMN route_id TO route_stack_id;
         ALTER TABLE landmark_exp_route
            ADD COLUMN route_system_id INTEGER;
         ALTER TABLE landmark_exp_route
            ADD COLUMN route_version INTEGER;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table landmark_exp_route already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_landmark_exp_route();

DROP FUNCTION cp_alter_table_landmark_exp_route();

/* MAGIC_NUMBERS: See comments in conf.py for landmarks_exp_rt_system_ids. */

UPDATE landmark_exp_route SET route_system_id = 362374, route_version = 1
                        WHERE route_stack_id = 1560257;

UPDATE landmark_exp_route SET route_system_id = 246133, route_version = 2
                        WHERE route_stack_id = 1566106;

UPDATE landmark_exp_route SET route_system_id = 377655, route_version = 6
                        WHERE route_stack_id = 1573123;

UPDATE landmark_exp_route SET route_system_id = 252536, route_version = 1
                        WHERE route_stack_id = 1575227;

UPDATE landmark_exp_route SET route_system_id = 371644, route_version = 1
                        WHERE route_stack_id = 1585730;

UPDATE landmark_exp_route SET route_system_id = 376582, route_version = 1
                        WHERE route_stack_id = 1590915;

UPDATE landmark_exp_route SET route_system_id = 379485, route_version = 1
                        WHERE route_stack_id = 1594845;

UPDATE landmark_exp_route SET route_system_id = 380966, route_version = 1
                        WHERE route_stack_id = 1596538;

UPDATE landmark_exp_route SET route_system_id = 383542, route_version = 1
                        WHERE route_stack_id = 1599410;

/* Is this okay? Probably not... but it's good enough? Try to guess which
   version of the route the test subject actually saw...

    Anyway, [lb] only sees two such rows that were v=2 of this route. */
UPDATE landmark_exp_route SET route_system_id = 375513, route_version = 1
                        WHERE route_stack_id = 1589507
                          AND last_modified < '2014-05-03 13:18:07.292408-05';
UPDATE landmark_exp_route SET route_system_id = 3830992, route_version = 2
                        WHERE route_stack_id = 1589507
                          AND last_modified >= '2014-05-03 13:18:07.292408-05';

/* Do the same thing again for the other table with route_id. */

CREATE FUNCTION cp_alter_table_landmark_exp_landmarks()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE landmark_exp_landmarks
            RENAME COLUMN route_id TO route_stack_id;
         ALTER TABLE landmark_exp_landmarks
            ADD COLUMN route_system_id INTEGER;
         ALTER TABLE landmark_exp_landmarks
            ADD COLUMN route_version INTEGER;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table landmark_exp_landmarks already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_landmark_exp_landmarks();

DROP FUNCTION cp_alter_table_landmark_exp_landmarks();

/* MAGIC_NUMBERS: See comments in conf.py for landmarks_exp_rt_system_ids. */

UPDATE landmark_exp_landmarks SET route_system_id = 362374, route_version = 1
                           WHERE route_stack_id = 1560257;

UPDATE landmark_exp_landmarks SET route_system_id = 246133, route_version = 2
                           WHERE route_stack_id = 1566106;

UPDATE landmark_exp_landmarks SET route_system_id = 377655, route_version = 6
                           WHERE route_stack_id = 1573123;

UPDATE landmark_exp_landmarks SET route_system_id = 252536, route_version = 1
                           WHERE route_stack_id = 1575227;

UPDATE landmark_exp_landmarks SET route_system_id = 371644, route_version = 1
                           WHERE route_stack_id = 1585730;

UPDATE landmark_exp_landmarks SET route_system_id = 376582, route_version = 1
                           WHERE route_stack_id = 1590915;

UPDATE landmark_exp_landmarks SET route_system_id = 379485, route_version = 1
                           WHERE route_stack_id = 1594845;

UPDATE landmark_exp_landmarks SET route_system_id = 380966, route_version = 1
                           WHERE route_stack_id = 1596538;

UPDATE landmark_exp_landmarks SET route_system_id = 383542, route_version = 1
                           WHERE route_stack_id = 1599410;

/* This isn't perfect -- someone could've got the v=1 route and started
   the experiment while someone else was editing and saving the route,
   such that the "created" is later than the v=2 creation time -- but it's
   good enough. */
UPDATE landmark_exp_landmarks SET route_system_id = 375513, route_version = 1
                           WHERE route_stack_id = 1589507
                             AND created < '2014-05-03 13:18:07.292408-05';
UPDATE landmark_exp_landmarks SET route_system_id = 3830992, route_version = 2
                           WHERE route_stack_id = 1589507
                             AND created >= '2014-05-03 13:18:07.292408-05';

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route Steps: Fix missing names and system IDs.
\qecho

/*

The byway_id (byway's system_id) is new since the CcpV1->V2 upgrade,
and thankfully we kept the stack_id and version around.

Here's the problem:

   SELECT COUNT(*) FROM route_step WHERE byway_id IS NULL;

    count
   -------
     1901

Which isn't such a big deal, since our sql uses the stack ID
and version instead (though it could easilyer use the system ID).

But for the step name it's a little more serious, since
we don't join on byway to get each route step's data, but
instead we cache data in route_step. So for the routes to
which this problem applies, we've been showing cue sheets
without road names. I think. Though no users have complained.
(Aside: I wish more people would complain when we're broken.)

   SELECT COUNT(*) FROM route_step WHERE step_name IS NULL;

     count
   ---------
    8168731

 */

/*

But first _Things_ FIRST!

The following SQL revealed, urm, another CcpV2 upgrade overlooksee:

   UPDATE route_step AS rs
      SET step_name = (SELECT name FROM item_versioned AS iv
                        WHERE iv.stack_id = rs.byway_stack_id
                          AND iv.version = rs.byway_version)
      WHERE step_name IS NULL;

complains

   ERROR: more than one row returned by a subquery used as an expression

And you'd assume it's regarding the subquery select, and it is! Indeed,

   SELECT iv.stack_id, iv2.n_duplicates
   FROM item_versioned iv
   INNER JOIN (
      SELECT iv2.stack_id, COUNT(*) AS n_duplicates
      FROM item_versioned iv2
      GROUP BY iv2.stack_id, iv2.version
      HAVING COUNT(*) > 1) iv2
   ON (iv.stack_id = iv2.stack_id);

returns a lot of duplicate rows.

   (And thanks to:
     stackoverflow.com/questions/2112618/finding-duplicate-rows-in-sql-server
    for the easy-to-replicate duplicate column finder sql code.)

But then you realize you're dumb [lb is] and forgot to check branch_id ([lb]!).

And then you realize that the CcpV2-ized route_step table is missing
the branch_id column ([lb]!!).

(Though, if I recall -- and I know I'm correct =) -- the intention was to
always just use the system_id and not to bother with the branch_id, stack_id,
and version (it's tedious to write all three IDs, and it's quicker to just
join the system ID and not the other three IDs), and routes are branch-locked,
so there's really no need for branch_id... except when you're trying to
recreate the system_id...!)

The route_step table was changed by or before 201-apb-82-sys_id-cnstrnts.sql,
and thankfully we held off deleting the stack_id and version columns,
commenting that we should wait until we are confident that we have everything
covered with just system_id. And now we know we're not covered with just the
system_id, so it's good that the stack_id and version columns weren't dropped.

As for the duplicate (stack id, version,) rows, we've fortunately never saved
routes for anything other than the mainline branch, so it's easy to populate.

So make the branch_id column and populate it, and then move on to NeXT problem.

*/

CREATE FUNCTION cp_alter_table_route_step()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE route_step ADD COLUMN branch_id INTEGER;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table route_step already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_route_step();

DROP FUNCTION cp_alter_table_route_step();

/* */

CREATE FUNCTION route_step_populate_branch_id()
   RETURNS VOID AS $$
   DECLARE
      baseline_branch_id INTEGER;
   BEGIN
      baseline_branch_id := cp_branch_baseline_id();
      EXECUTE '
         UPDATE route_step SET branch_id = ' || baseline_branch_id || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho route_step_populate_branch_id: ~5 to 9 minutes...
SELECT route_step_populate_branch_id();
/*
May-21 18:06:42  DEBG         schema-up  #  Time: 1245461.972 ms
*/

DROP FUNCTION route_step_populate_branch_id();

/*

Now It's Time: Update route_step.name and route_step.byway_id.

EXPLAINing: There are a few differents ways to update the table.

One is to use the "naive" approach, using subqueries. E.g.,

   UPDATE route_step AS rs
      SET byway_id = (SELECT system_id FROM item_versioned AS iv
                       WHERE iv.stack_id = rs.byway_stack_id
                         AND iv.version = rs.byway_version
                         AND iv.branch_id = rs.branch_id)
      WHERE byway_id IS NULL;

   UPDATE 1901
   Time: 5936.799 ms

But using subqueries is slow, because you're running SELECT
for every row. Also, other developers are gonna laugh at
you if you don't use an UPDATE's more powerful JOIN, ala:
 https://stackoverflow.com/questions/21048955/
  postgres-error-more-than-one-row-returned-by-a-subquery-used-as-an-expression

So here it is, the proper implementation, with fancy columntastic formatting...
not that it still doesn't take a half hour, which a similar query with
subqueries would probably also take, because it's eleven million rows we're
updating, but at least this has pretty formatting, and it does the job.
 */

\qecho Updating route_step... (~26 to 48 minutes)...
-------------------------------------------
UPDATE route_step rs
SET    step_name = iv.name,
       byway_id = iv.system_id
FROM   item_versioned iv
WHERE  rs.byway_stack_id = iv.stack_id
AND    rs.byway_version = iv.version
/* AND we could also restrict further,
AND  ((rs.name IS NULL) OR (rs.byway_id IS NULL))
   BUT it can't hurt to be thorough, either. */
;
/* UPDATE 11187518
   Time: 1552162.013 ms (What is that, 1552.1620130000001 seconds?) */
                                                   -- 26 minutes, bud.
/* Time: 2884996.504 ms */

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Group_Item_Access: Fix bad item system IDs.
\qecho

/*

  This problem seems to affect items that were marked deleted when
  the CcpV1->V2 upgrade happened. It looks like the rows with the
  bad system IDs are marked deleted... so... this maybe never
  caused any problems for anyone?

      SELECT sys_id, brn_id, stk_id, v, d, start_rid, until_rid
         FROM _gia WHERE stk_id = 1493434;

      sys_id     | brn_id  | stk_id  | v | d | start_rid | until_rid
  ---vvvvvvvv----+---------+---------+---+---+-----------+------------
  --> 216647 <-- | 2500677 | 1493434 | 1 | f |     12418 |      22341
  --> 216647 <-- | 2500677 | 1493434 | 2 | t |     22341 | 2000000000
     ^^^^^^^^
   Note that the sys_id is the same for both versions!

   SELECT system_id, version FROM item_versioned WHERE stack_id = 1493434;

    system_id | version
   -----------+---------
       216647 |       1
      3820652 |       2

   */

\qecho UPDATE group_item_access... 1-1/2 minutes...

UPDATE group_item_access AS gia
   SET item_id = (SELECT iv.system_id FROM item_versioned AS iv
                   WHERE iv.branch_id = gia.branch_id
                     AND iv.stack_id = gia.stack_id
                     AND iv.version = gia.version)
 WHERE NOT EXISTS(SELECT 1 FROM item_versioned AS iv2
                          WHERE iv2.system_id = gia.item_id
                            AND iv2.branch_id = gia.branch_id
                            AND iv2.stack_id = gia.stack_id
                            AND iv2.version = gia.version);

/*
   UPDATE 222723
   Time: 92787.685 ms
   */

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Link_Value: Remove three invalid link_values
\qecho

/*

PROBLEM INTRO

Later on in this script, we'll make the item_revisionless table.
To populate that table, we join against GIA. This caused me to
find that not all items have at least one GIA record. In particular,
while investigating the link_value table, I found 218,601 missing
GIA records for items marked deleted (which might not seem like a
problem, but it means revision revert won't work, or at least not
for these items missing GIA records).

I also found 13 link_values not marked deleted and lacking a GIA
record.

And one of these link_values has a zero for a reference stack ID!

   select count(*) from _lv where lhs = 0;
    count
   -------
        3

Fortunately it's just three records and only affects lhs_stack_id.

   select count(*) from _lv where rhs = 0;
    count
   -------
        0

Here are the stack IDs:

   SELECT stk_id FROM _lv WHERE lhs = 0;

    stk_id
   ---------
    1518270
    1523313
    1530748

*/

/*

PROBLEM LINK_VALUE #1

Here's a walk-through on one of the problems:

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
   WHERE stk_id = 1530748;

    stk_id  | v | d | start | until | a | nfr | lhs |  rhs   | vi
   ---------+---+---+-------+-------+---+-----+-----+--------+----
    1530748 | 1 | f | 14566 | inf   | 9 | 0x0 |   0 | 990144 |

Starting with the byway:

   SELECT stk_id, v, d, nom, start, until, a, nfr, gfl, ow
   FROM _by WHERE stk_id = 990144;

   stk_id | v | d |       nom        | start | until | a | nfr  | gfl | ow
  --------+---+---+------------------+-------+-------+---+------+-----+----
   990144 | 3 | f | Golden Valley Rd | 14568 | inf   | 8 | 0x20 |  11 |  1
   990144 | 2 | f | Golden Valley Rd | 14566 | 14568 | 8 | 0x20 |  11 |  0
   990144 | 1 | f | Golden Valley Rd |   133 | 14566 | 8 | 0x20 |  42 |  0

You'll notice that the latest version looks to have been created because
one-way was set.

  SELECT stk_id, v, d, start, until, a, nfr, lhs, vi
  FROM _lv WHERE rhs = 990144;

   stk_id  | v | d | start | until |   lhs   | vi
  ---------+---+---+-------+-------+---------+----
   1530747 | 1 | f | 14565 | inf   | 1530746 |     <-- post
   1530748 | 1 | f | 14566 | inf   |       0 |     <-- WHO KNOWS?!
   1660484 | 2 | f | 14568 | inf   | 1654321 |  1  <-- /byway/one_way
   1660484 | 1 | f |   133 | 14568 | 1654321 |  0  <-- /byway/one_way
   1998274 | 1 | f |   133 | inf   | 1992111 |  1  <-- /byway/lane_count
   2336064 | 1 | f |   133 | inf   | 2329901 |  0  <-- /byway/shoulder_width

The link without an lhs_stack_id is an old revision, and you'll see
two nearby edits.

  SELECT id, tstamp, comment FROM _rev WHERE id IN (14565,14566,14567,14568);

    id   |      tstamp      |            comment
  -------+------------------+--------------------------------
   14568 | 2011-05-24 18:16 | one-way
   14567 | 2011-05-24 15:19 |                                <-- Unrelated
   14566 | 2011-05-24 14:53 | This is not an expressway...   <-- Bad: lhs=0
   14565 | 2011-05-24 14:52 | New thread: Not impassible

Above, we saw that gfl_id changed from 42 (Expressway_Ramp) to 11 (Local_Road).
Here's all that happened at the suspect revision:

  SELECT * FROM _iv WHERE start = 14566 OR until = '14566';

   stk_id  | v | d | r |       nom        | start | until | a | nfr
  ---------+---+---+---+------------------+-------+-------+---+------
    990144 | 2 | f | f | Golden Valley Rd | 14566 | 14568 | 8 | 0x20
    990144 | 1 | f | f | Golden Valley Rd |   133 | 14566 | 8 | 0x20
   1530748 | 1 | f | f |                  | 14566 | inf   | 9 | 0x0

This just shows the byway, whose GFL ID was edited, and the bad link_value.

And note that the link_value's access_style_id is all_denied. So weird.

So let's just whack the bad link_value; there's nothing else associated
with it, it seems.

-----------------------------------------------------------
I wrote the previous comments while the server was offline.
Here's what I found in the CcpV1 database:

ccpv1_live=> SELECT * FROM post_bs WHERE id = 1530748;
   id    | version | deleted | post_id | byway_id | valid_starting_rid | valid_
---------+---------+---------+---------+----------+--------------------+-------
 1530748 |       1 | f       |       0 |   990144 |              14566 |  (inf)

Oy! So, hopefully this problem has long since been fixed...

*/

-- Note that there's not a GIA record for this link_value.
-- Not needed: DELETE FROM group_item_access WHERE stack_id = 1530748;
DELETE FROM link_value WHERE stack_id = 1530748;
DELETE FROM item_versioned WHERE stack_id = 1530748;
DELETE FROM item_stack WHERE stack_id = 1530748;

/*

PROBLEM LINK_VALUE #2

Looking at another bad link_value, 1523313:

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
   WHERE stk_id = 1523313;

    stk_id  | v | d | start | until | a | nfr | lhs |   rhs   |  vi
   ---------+---+---+-------+-------+---+-----+-----+---------+-------
    1523313 | 1 | f | 14265 | inf   | 9 | 0x0 |   0 | 2498796 | 14260

Starting with the other latest bad link_value, 1523313:

   SELECT stk_id, v, d, nom, a, g, start, until, ityp FROM _gia
   WHERE stk_id = 2498796;

    stk_id  | v | d |     nom     | a | g | start | until |   ityp
   ---------+---+---+-------------+---+---+-------+-------+-----------
    2498796 | 1 | f | Revision ID | 4 | 1 |     1 | inf   | attribute

The Revision ID attribute is not very much used.

   SELECT COUNT(*) FROM _lv WHERE rhs = 2498796;

    count
   -------
       15

It links a revision to a post.

   SELECT id, tstamp, unom, comment FROM _rev WHERE id = 14265;

     id   |      tstamp      | unom  |   comment
   -------+------------------+-------+-------------
    14265 | 2011-03-07 15:57 | hokan | update note

Except the changenote makes it sounds like an annotation was updated,
and not that a post was edited and assigned a post-revision link_value.

Checking for other items at that revision,

  SELECT * FROM _iv WHERE start = 14265 OR until = '14265';

    sys_id | brn_id  | stk_id  | v | d | r | nom | start | until | a | nfr
   --------+---------+---------+---+---+---+-----+-------+-------+---+------
    402364 | 2500677 | 1353999 | 7 | f | f |     | 14265 | 21194 | 8 | 0x20
    401627 | 2500677 | 1353999 | 6 | f | f |     |  8547 | 14265 | 8 | 0x20
    402871 | 2500677 | 1523313 | 1 | f | f |     | 14265 | inf   | 9 | 0x0

and

   SELECT stk_id, v, d, nom, a, g, start, until, ityp FROM _gia
   WHERE stk_id IN (1353999, 1523313);

    stk_id  | v | d | nom | a | g | start | until |    ityp
   ---------+---+---+-----+---+---+-------+-------+------------
    1523313 | 1 | f |     | 3 | 1 | 14265 | inf   | link_value     *** 14265
    1353999 | 8 | t |     | 3 | 1 | 21194 | inf   | annotation
    1353999 | 7 | f |     | 3 | 1 | 14265 | 21194 | annotation     *** 14265
    1353999 | 6 | f |     | 3 | 1 |  8547 | 14265 | annotation     *** 14265
    1353999 | 5 | f |     | 3 | 1 |  6760 | 8547  | annotation
    1353999 | 4 | t |     | 3 | 1 |  6759 | 6760  | annotation
    1353999 | 3 | f |     | 3 | 1 |  1164 | 6759  | annotation
    1353999 | 2 | f |     | 3 | 1 |   462 | 1164  | annotation
    1353999 | 1 | f |     | 3 | 1 |   453 | 462   | annotation

You can see that an annotation was edited and the bad link_value was created
during the same revision; we don't have to worry about the annotation
link_value because it doesn't need to be edited:

   SELECT stk_id, v, d, start, until, a, nfr, rhs FROM _lv WHERE lhs = 1353999;

    stk_id  | v | d | start | until | a | nfr |   rhs
   ---------+---+---+-------+-------+---+-----+---------
    1354000 | 4 | t | 21194 | inf   | 9 | 0x0 | 1114507
    1354000 | 3 | f |  6760 | 21194 | 9 | 0x0 | 1114507
    1354000 | 2 | t |  6759 | 6760  | 9 | 0x0 | 1114507
    1354000 | 1 | f |   453 | 6759  | 9 | 0x0 | 1114507
    1400012 | 2 | t | 20544 | inf   | 9 | 0x0 | 1400013
    1400012 | 1 | f |  6919 | 20544 | 9 | 0x0 | 1400013
    1542327 | 2 | t | 20563 | inf   | 9 | 0x0 | 1542325
    1542327 | 1 | f | 15027 | 20563 | 9 | 0x0 | 1542325

Fortunately, the link_value has a GIA record, which stores the link types.

   SELECT stk_id, v, d, grp_name, a, g, start, until, ityp, lt, rt
   FROM _gia WHERE stk_id = 1523313;

    stk_id  | v | d | grp_name  | a | g | start | until |    ityp    | lt | rt
   ---------+---+---+-----------+---+---+-------+-------+------------+----+----
    1523313 | 1 | f | All Users | 3 | 1 | 14265 | inf   | link_value |  8 |  5

Note that the lhs_type_id is 8, or post.

Look for nearby (timewise) other posts.

   SELECT stk_id, v, d, start, until, a, nfr, thd, bod, pol
   FROM _po ORDER BY start;

   ...
    1523311 | 1 | f | 14264 | inf   | 8 | 0x20 | 1523310 |
         Hi,\r\rI reverted the edit that close Plym   |   0
    1523314 | 1 | f | 14266 | inf   | 8 | 0x20 | 1523310 |
         Thanks and sorry for the carelessness. I     |   0
   ...

How much you wanna bet the missing link_revision goes with that thread?

   SELECT stk_id, v, d, start, until, a, nfr, thd, bod, pol
   FROM _po WHERE thd = 1523310;

shows the same two posts.

And checking out their link_values,

   SELECT stk_id, v, d, r, start, until, a, nfr, rhs, vb, vi
   FROM _lv WHERE lhs IN (1523311, 1523314);

    stk_id  | v | d | r | start | until | a | nfr |   rhs   | vb |  vi
   ---------+---+---+---+-------+-------+---+-----+---------+----+-------
    1523312 | 1 | f | f | 14264 | inf   | 9 | 0x0 | 2498796 |    | 14260

Reveals another link_value for a similar link_value post-revision!

Reprinted again, here's the bad link_value:

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
   WHERE stk_id = 1523313;

    stk_id  | v | d | start | until | a | nfr | lhs |   rhs   |  vi
   ---------+---+---+-------+-------+---+-----+-----+---------+-------
    1523313 | 1 | f | 14265 | inf   | 9 | 0x0 |   0 | 2498796 | 14260

So the bad link_value was created one revision after the okay link_value, and
both value_integers are the same ("14260" is the revision being referenced).

Yikes, so, a valid link_value post-revision was created, but also an
invalid, dangling link_value was also created, presumably for the same
two items, so the second link_value should be obliterated.

-----------------------------------------------------------
I wrote the previous comments while the server was offline.
Here's what I found in the CcpV1 database:

ccpv1_live=> SELECT * FROM post_revision WHERE id = 1523313;
   id    | version | deleted | post_id | rev_id | valid_starting_rid |
         |         |         |         |        | valid_before_rid   |
---------+---------+---------+---------+--------+--------------------+
 1523313 |       1 | f       |       0 |  14260 |              14265 |
         |         |         |         |        |         2000000000 |

Oy! So, hopefully this problem has long since been fixed...

*/

DELETE FROM group_item_access WHERE stack_id = 1523313;
DELETE FROM link_value WHERE stack_id = 1523313;
DELETE FROM item_versioned WHERE stack_id = 1523313;
DELETE FROM item_stack WHERE stack_id = 1523313;

/*

PROBLEM LINK_VALUE #3

Finally, the final third bad link_value.

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
   WHERE stk_id = 1518270;

    stk_id  | v | d | start | until | a | nfr | lhs |   rhs   | vi
   ---------+---+---+-------+-------+---+-----+-----+---------+----
    1518270 | 1 | f | 13751 | inf   | 9 | 0x0 |   0 | 1365270 |

Using _gia to see about the rhs item,

   SELECT stk_id, v, d, nom, a, g, start, until, ityp FROM _gia
   WHERE stk_id = 1365270;

    stk_id  | v | d |     nom     | a | g | start | until |   ityp
   ---------+---+---+-------------+---+---+-------+-------+-----------
    1365270 | 3 | f | The Nook    | 3 | 1 |  3648 | inf   | waypoint
    1365270 | 2 | f | The Nook    | 3 | 1 |  3600 | 3648  | waypoint
    1365270 | 1 | f | The_Nook    | 3 | 1 |  3540 | 3600  | waypoint

We find a waypoint with a dangling link_value.

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
   WHERE rhs = 1365270;

    stk_id  | v | d | start | until | a | nfr |   lhs   |   rhs   | vi
   ---------+---+---+-------+-------+---+-----+---------+---------+----
    1518223 | 1 | f | 13749 | inf   | 9 | 0x0 | 1518211 | 1365270 |
    1518226 | 1 | f | 13750 | inf   | 9 | 0x0 | 1518225 | 1365270 |
    1518270 | 1 | f | 13751 | inf   | 9 | 0x0 |       0 | 1365270 |
    2499520 | 1 | f |  3600 | inf   | 9 | 0x0 | 2499519 | 1365270 |

Taking a look at the other attachments to the item:

   SELECT stk_id, v, d, nom, a, g, start, until, ityp FROM _gia
   WHERE stk_id IN (1518211, 1518225, 2499519);

    stk_id  | v | d |    nom    | a | g | start | until |    ityp
   ---------+---+---+-----------+---+---+-------+-------+------------
    2499519 | 1 | f |           | 3 | 1 |  3600 | inf   | annotation
    1518225 | 1 | f |           | 3 | 1 | 13750 | inf   | post
    1518211 | 1 | f | destroyed | 3 | 1 | 13749 | inf   | tag

Taking a look at the revisions involved, and nearby,

   SELECT id, tstamp, unom, comment FROM _rev WHERE id IN
   (3540, 3600, 3648, 13747, 13748, 13749, 13750, 13751, 13752, 13753, 13754);

     id   |      tstamp      |     unom      |            comment
   -------+------------------+---------------+--------------------------------
    13754 | 2010-12-15 21:21 | oldbag        |
    13753 | 2010-12-15 21:16 | oldbag        | added tags to coon rapids dam
    13752 | 2010-12-15 21:08 | systxm        | added tags
*** 13751 | 2010-12-15 21:07 | tobymarkowitz | better cp by spring assignment
    13750 | 2010-12-15 21:01 | tobymarkowitz | New thread: Fire
    13749 | 2010-12-15 21:01 | tobymarkowitz | assigned block, Nook Fire
    13748 | 2010-12-15 20:58 | davies767     |
    13747 | 2010-12-15 20:24 | andy10k       |
     3648 | 2008-09-03 08:14 | wafer         | POI changes
     3600 | 2008-09-02 18:58 | wafer         | POI
     3540 | 2008-09-02 08:20 |               | added points of interest and c

There were a lot of edits in this revision, spurred by the Better Cp By Spring
campaign.

   SELECT COUNT(*), ityp FROM _gia WHERE start = 13751 OR until = '13751'
   GROUP BY ityp;

    count |    ityp
   -------+------------
        2 | tag
       44 | link_value

The offensive link_value has no GIA record, so we don't even get a hint what
item type the lhs is supposedly.

   SELECT * FROM _gia WHERE stk_id = 1518270;

    sys_id | brn_id | stk_id ...
   --------+--------+------- ...
   (0 rows)

So we should just whack the link_value and move on with life...

tl;dr, I found three link_values with an unset lhs_stack_id; two of
them were unrecoverable and I don't know what caused the problem,
and the third is probably a bug with the special post-revision link_value.
And now we have a table constraint that will alert us to whatever code
might be trying to make dangling link_values, should this(these) bug(s)
still be crawling around the system somewhere.

-----------------------------------------------------------
I wrote the previous comments while the server was offline.
Here's what I found in the CcpV1 database:

ccpv1_live=> SELECT * FROM post_point WHERE id = 1518270;
   id    | version | deleted | post_id | point_id | valid_starting_rid |
         |         |         |         |          | valid_before_rid   |
---------+---------+---------+---------+----------+--------------------+
 1518270 |       1 | f       |       0 |  1365270 |              13751 |
         |         |         |         |          |         2000000000 |

Oy! So, hopefully this problem has long since been fixed...

*/

-- Note that there's not a GIA record for this link_value.
-- Not needed: DELETE FROM group_item_access WHERE stack_id = 1518270;
DELETE FROM link_value WHERE stack_id = 1518270;
DELETE FROM item_versioned WHERE stack_id = 1518270;
DELETE FROM item_stack WHERE stack_id = 1518270;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Link_Value: Add stack IDs constraint
\qecho

SELECT cp_constraint_drop_safe('link_value', 'enforce_lhs_and_rhs_stack_ids');
ALTER TABLE link_value ADD CONSTRAINT enforce_lhs_and_rhs_stack_ids
   CHECK ((lhs_stack_id > 0) AND (rhs_stack_id > 0));

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route: Discussion on "Missing" GIA Rows
\qecho

/*

   How many wabbits down this hole owie? Whad started with the
   simpuhest task of fixing a minor landmarks bug has bwossomed
   into a bootiful bouquet of bugs!

   On to the next bug!!

   And we'll explain this one by way of example:

      SELECT COUNT(*) FROM group_item_access WHERE item_type_id = 10;

       count
      -------
       26319

   Whereas,

      SELECT COUNT(*) FROM route;

       count
      --------
       141799

That is, we (I, [lb]) didn't make gia records (last Fall,
during the CcpV1->V2 upgrade) for anonymously-requested
routes.

This is not really a big deal, since the routes are not
user-accessible, but this makes it harder to assume that
the group_item_access and the item_revisionless tables are
fully representative of all items from the item_versioned
table -- since they're not.

So let's make entries for missing entries.

Poking around, I found some routes that were permission=3
and visibility=3 in CcpV1 (what were called, er, "private"
and "noone"), that don't have arbiter records in CcpV2. But
read on: tl;dr;dc: these were anon-requested routes and
then the user logged on and assumed them (or something
like that), and CcpV1 made new routes (i.e., new stack
IDs, as in: CcpV1 makes a new route and uses a new stack
ID and revision when you change a route's permissions
(so you're not really changing *that* route's permissions:
you're cloning it, you're deleting the old one, and you're
making a new route with different permissions. I know, right?),
which is not how it works in CcpV2, which uses the same
stack ID when permissions change and just makes a new gia
record), so we really don't need records for these old
routes, since they were cloned. I guess this comment wasn't
really tl;dr;db, but I Didn't Bother Editing The Comment.
Just Prolonging it, I guess. Anyway:
* In current code, for new routes requested by users,
  anonymous or not, we at least make a gia record for the
  session ID. These old routes are missing gia records,
  and that feels weird.

By making gia for records for all routes missing them:
1) Hopefully this rabbit hole never happens again.
2) We'll make item_revisionless records for these routes, next,
   when we make the item_revisionless table and populate it.
3) We'll know that earlier, when we claimed, "Hundreds of
   thousands of routes requested", it was probably more like,
   "Tens of thousands of routes requested"... sorry to break
   our tens of hearts.

==============================================================

Investigative Report: Here's What Smells Funny, and Here's Why.

  And here's also why we can make missing group_item_access
  records, to make it smell less funny.

Here's what I first noticed. A user edited a route or added it
to their library, so there's a revision when this happened, but
there's no group_item_access record. E.g., SQLing

   SELECT * FROM _iv WHERE stk_id = 1575797;

shows the edit in question.

Note that the latest version is not marked deleted, which
CcpV1 otherwise tends to do when a user assumes ownership
of a route:

    sys_id | stk_id  | v | d | r | start_rid | until_rid  | acs | infer
   --------+---------+---+---+---+-----------+------------+-----+-------
    253081 | 1575797 | 1 | f | f |         0 |      18468 |   3 | 0x1
    253082 | 1575797 | 2 | f | f |     18468 | 2000000000 |   3 | 0x1

The revision,

   SELECT id, timestamp, comment FROM _rev WHERE id = 18468;

shows a comment that the user made.

     id   |    timestamp     |            comment             | user
   -------+------------------+--------------------------------+------
    18468 | 2012-08-19 18:51 | Chatsworth ped bridge is close | XXXX

The revision also shows the username, but it's not connected
via route.owner_name.

But then you have to remember that CcpV1 makes a new route clone all
the time, so never trust one route's stack ID to tell that route's
complete story.

You'll also see something a little fishy in item_stack:

   SELECT stack_id, creator_name, access_style_id, access_infer_id
     FROM item_stack WHERE stack_id = 1575797;

Because it says the route was created by _script,

    stack_id | creator_name | access_style_id | access_infer_id
   ----------+--------------+-----------------+-----------------
     1575797 | _script      |               3 |               1

which smells funny because the route eventually has a non-anon real
user-creator.

This is because, when we made item_stack, we populated creator_name using
revision.username, but revision.id=0's username is '_script'. And the clone
route is the one associated with the user.

In CcpV2, when an item's permissions or access is changed, the code made
a new item, i.e., grabbed a new stack ID, marked deleted the old stack ID,
and claimed a new revision ID.

*** CAVEAT *************

This odd behavior grossly inflated the statistics for the
number of routes requested: while there was supposedly
a big spike in the number of routes requested one early
summer, it was inflated somewhat by a ton of automatic
routes automatically updated, because whenever a route with
spoiled byways beneath was viewed, a new, repaired route
was suggested to the viewer. So we made a lot of clones of
routes!

************************

Note also that access_style_id=3 is restricted-style and
access_infer_id=1 is private-user-arbiter... so at least
the upgrade script got those two parameters right... unless
you consider that they are no group_item_access records for
this route, so, really access_infer_id should be 0.... I know,
right?

How many routes have this particular or similar issue?

   SELECT COUNT(*) FROM route WHERE version = 1; -- 138505
   SELECT COUNT(*) FROM route WHERE version > 1; -- 3329
   SELECT COUNT(*) FROM (SELECT *                -- 135
      FROM item_versioned AS iv
      JOIN revision AS rev ON (rev.id = iv.valid_start_rid)
      JOIN route AS rt ON (rt.system_id = iv.system_id)
      WHERE rt.system_id NOT IN (SELECT item_id FROM group_item_access
                                               WHERE item_type_id = 10)
      AND rev.id > 0 AND rev.username IS NOT NULL
      ORDER BY rev.id DESC) AS foo;

The 135 matches are all version > 1 (since at version = 1, they're rev.id = 0).
So 135 routes where edited but don't have group_item_access records.
Along with almost 100000 other routes without group_item_access records.

Back to our original example route, just to recap, but this time
using the original, CcpV1 database:

   SELECT route.owner_name,
          route.id,
          route.version AS v,
          route.deleted AS d,
          route.valid_starting_rid AS beg_r,
          route.valid_before_rid AS fin_r,
          SUBSTRING(route.name FOR 13),
          TO_CHAR(route.created, 'YY.MM.DD|HH24:MI') AS created,
          route.permission AS p,
          route.visibility AS v,
          revision.username,
          revision.comment,
          revision.permission AS rp,
          revision.visibility AS rv,
          TO_CHAR(revision.timestamp, 'YYYY.MM.DD|HH24:MI') AS timestamp
      FROM route
      LEFT OUTER JOIN revision ON (route.valid_starting_rid = revision.id)
      WHERE route.id IN (1575797)
      ORDER BY route.id ASC, version ASC;

    ownr|v|d|beg_r|fin_r|  created  |p|v|user|  comment    | timestamp
   -----+-+-+-----+-----+-----------+-+-+----+-------------+-----------
        |1|f|    0|18468|12.08|18:30|3|3|    |             |
        |2|f|18468|  inf|12.08|18:51|3|3|XXXX|bridge closed|12.08|18:51

Note that the last route has no route.owner_name for either version.
It's p=3, v=3, and the revision is private to the user, but the user made
a comment?! Was this route reactions? Was the user mistakingly thinking
they were saving the route to their library? (And remember that
permission=3="private" and visibility=3="noone".)

Checking route_views,

   SELECT * FROM route_views WHERE route_id = 1575797;
    route_id | username | active | last_viewed
   ----------+----------+--------+-------------
   (0 rows)

So we know this route is not accessible to the user.

However, if we look for routes for the user,

   SELECT * FROM route WHERE route.owner_name = 'XXXX'
      ORDER BY route.id ASC, version ASC;

You'll find two routes:

   SELECT route.owner_name,
          route.id,
          route.version AS v,
          route.deleted AS d,
          route.valid_starting_rid AS beg_r,
          route.valid_before_rid AS fin_r,
          SUBSTRING(route.name FOR 13),
          TO_CHAR(route.created, 'YY.MM.DD|HH24:MI') AS created,
          route.permission AS p,
          route.visibility AS v,
          revision.username,
          revision.comment,
          revision.permission AS rp,
          revision.visibility AS rv,
          TO_CHAR(revision.timestamp, 'YYYY.MM.DD|HH24:MI') AS timestamp
      FROM route
      LEFT OUTER JOIN revision ON (route.valid_starting_rid = revision.id)
      WHERE route.id IN (1575814, 1575815)
      ORDER BY route.id ASC, version ASC;

      id    | v | d | beg_r |   fin_r    |    created     | p | v | username
   ---------+---+---+-------+------------+----------------+---+---+----------
    1575814 | 1 | f |     0 | 2000000000 | 12.08.19|18:51 | 3 | 3 |
    1575815 | 1 | f |     0 | 2000000000 | 12.08.19|18:52 | 3 | 3 |

Back in CcpV2's database,

   SELECT sys_id, stk_id, v, d, r, a, g, start, until, ityp
      FROM _gia WHERE stk_id IN (1575814, 1575815);

    sys_id | stk_id  | v | d | r | a | g | start | until | ityp
   --------+---------+---+---+---+---+---+-------+-------+-------
    253084 | 1575815 | 1 | f | f | 2 | 1 |     0 | inf   | route
    253083 | 1575814 | 1 | f | f | 2 | 1 |     0 | inf   | route

Which means: the "forgotten" route doesn't matter: CcpV1 cloned it,
and in CcpV2, we've correctly got group_item_access records for it.

==============================================================

Another example.

This is similar to the last run-through of the problem-non-problem.

CAVEAT: There many times as many "unique" route requests based on stack ID
        as there are actual unique route requests when you consider the
        cloning issue, as detailed (endlessly), above.

The is another example of the CcpV1 route-editing-and-changing-permissions-of
behavior.

   SELECT stk_id, v, d, r, nom, start_rid, until_rid, acs, infer
      FROM _iv WHERE start_rid = 19867;

This shows the second version of the auto-generated route with an
auto-generated name, "Route via 2nd St", being deleted, and then the
deliberately user-saved route, with a deliberately user-named name,
"Ruthan's" (very cool name), being wrongfullly assigned a new stack ID.

This is wrong because it's logically the same route, i.e., only the
permissions are changing, so why are we deleting the old route and
cloning a new route? That inflates our routes-requested statistics
(by 10x) and also infuriates our codesters (blimey!). Anyway, here is
the query, finally, two stack IDs, one revision, one meeting it's
anonymous death and the other greeting life with a really cool name,
which I'd also like to meet:

 stk_id  | v | d | r |       nom        | start_rid | until_rid  | acs | infer
 --------+---+---+---+------------------+-----------+------------+-----+-------
 1588503 | 2 | t | f | Route via 2nd St |     19867 | 2000000000 |   3 | 0x1
 1588504 | 1 | f | f | Ruthan's         |     19867 |      19868 |   3 | 0x1

(sounds like "Runyon's", doesn't it?).

Anyway, moving on, considering the route, 1588503, and those that followed:

 SELECT stk_id, v, g, d, r, nom, beg_r, acs, aif, last_edited
    FROM _rt1 WHERE stk_id IN (1588503, 1588504, 1588505);

  stk_id  | v | g | d | r |   nom    | beg_r | acs |  aif  |  last_edited
 ---------+---+---+---+---+----------+-------+-----+-------+----------------
  1588505 | 1 | 1 | f | f | Ruthan's | 19868 |   3 | 0x401 | 13.05.24|15:57
  1588504 | 2 | 1 | t | f | Ruthan's | 19868 |   3 | 0x1   | 13.05.24|15:57
  1588504 | 1 | 1 | f | f | Ruthan's | 19867 |   3 | 0x1   | 13.05.24|15:57
  -- MISSING: 1588503, because no GIA record.

You'll see that CcpV1 makes "new" routes whenever an existing route is edited
(it makes a new version of the existing route that it marks deleted, and then
it makes a clone route at v=1).

Digging deeper into the problem,

   SELECT route.owner_name,
          route.id,
          route.version AS v,
          route.deleted AS d,
          route.valid_starting_rid AS beg_r,
          route.valid_before_rid AS fin_r,
          SUBSTRING(route.name FOR 13),
          TO_CHAR(route.created, 'YY.MM.DD|HH24:MI') AS created,
          route.permission AS p,
          route.visibility AS v,
          revision.username,
          revision.comment,
          revision.permission AS rp,
          revision.visibility AS rv,
          TO_CHAR(revision.timestamp, 'YY.MM.DD|HH24:MI') AS timestamp
      FROM route
      LEFT OUTER JOIN revision ON (route.valid_starting_rid = revision.id)
      WHERE route.id IN (1588503, 1588504, 1588505)
      ORDER BY route.id ASC, version ASC;

 owner|  id   |v|d|beg_r|fin_r| substring | created   |p|v|user|   comment
 -----+-------+-+-+-----+-----+-----------+-----------+-+-+----+--------------
      |1588503|1|f|    0|19867|Rte via W B|05.24|15:51|3|3|    |
      |1588503|2|t|19867|  inf|Rte via 2nd|05.24|15:57|3|3|XXXX|Add rte to lib
 XXXXX|1588504|1|f|19867|19868|Ruthan's   |05.24|15:57|3|2|XXXX|Add rte to lib
 XXXXX|1588504|2|t|19868|  inf|Ruthan's   |05.24|15:57|3|2|XXXX|Creating deepl
 XXXXX|1588505|1|f|19868|  inf|Ruthan's   |05.24|15:57|2|2|XXXX|Creating deepl

shows three versions of the same route.

It's left as an exercise to the user (have you made
it this far?!) to identify why the old code had to
delete the pristine route and to clone the route just to
make a so-called "deeplink", otherwise known as just
giving someone a URL to the route. Really? Kill my route
and make a clone just so I can copy and paste a link in an
email???????????????????????????!

"Every time I interact with an object, I should not be creating
 a new object."

Also -- Argh -- I think I kind of sort or maybe vaguely remember being worried
about this problem before (the one tediously described above), and then
forgetting about it. And now this? At least by patching these holes we'll never
have to worry about me over-analyzing this stupid problem again. And yea, I've
said "stupid" once, twice (thrice) now, already, in this script- and I've been
counting. This is all so ridiculous... perfection, smerfection! I like a wiki
with a lot of cruft. But not any, really. Like I've said no times before, I've
been coding too much, and also listening to too much Doctorama, or Future Who,
take yer pick, let's go already, on to the NExT plpgsql!
*/

\qecho
\qecho Route: Add "Missing" GIA Rows
\qecho

CREATE FUNCTION group_item_access_add_items_denied(item_type TEXT)
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      acl_denied INTEGER;
      item_type_id INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      group_public_id := cp_group_public_id();
      acl_denied := cp_access_level_id('denied');
      item_type_id := cp_item_type_id(item_type);
      EXECUTE '
         INSERT INTO group_item_access
            (group_id,
             access_level_id,
             -- Leave NULL: session_id
             item_id,
             branch_id,
             stack_id,
             version,
             acl_grouping,
             valid_start_rid,
             valid_until_rid,
             deleted,
             reverted,
             name,
             item_type_id,
             -- Leave NULL: link_lhs_type_id
             -- Leave NULL: link_rhs_type_id
             created_by
             -- date_created
             -- tsvect_name
            )
            SELECT
               ' || group_public_id || ' AS group_id,
               ' || acl_denied || ' AS access_level_id,
               item.system_id,
               item.branch_id,
               item.stack_id,
               item.version,
               1 AS acl_grouping,
               iv.valid_start_rid,
               iv.valid_until_rid,
               iv.deleted,
               iv.reverted,
               iv.name,
               ' || item_type_id || ' AS item_type_id,
               ''_user_anon_@@@instance@@@'' AS created_by
            FROM ' || item_type || ' AS item
            JOIN item_versioned AS iv
               USING (system_id)
            JOIN revision AS rev
               ON (iv.valid_start_rid = rev.id)
            WHERE item.system_id NOT IN (SELECT item_id
                                         FROM group_item_access
                                         WHERE item_type_id = 10)
      ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT group_item_access_add_items_denied('route');
/*
Time: 24680.508 ms
*/

/* There are 71 track records without GIA rows.

   These were anonymously-created and left unclaimed.
*/
SELECT group_item_access_add_items_denied('track');

DROP FUNCTION group_item_access_add_items_denied(item_type TEXT);

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Link_Value: Missing GIA records for CcpV1 watch_region comments
\qecho

/*

There are a number of link_values without GIA records.

   SELECT COUNT(*) FROM link_value AS lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = lv.system_id);
    count
   -------
      134

Here we'll consider a smaller subset, those not marked deleted.

   SELECT COUNT(*) FROM link_value AS lv
      JOIN item_versioned USING (system_id)
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = lv.system_id)
                           AND deleted IS TRUE;
    count
   -------
      123

So, 11 link_values without GIA records are marked not deleted.

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS FALSE;
    stk_id  | v | d | start | until | a | nfr |   lhs   |   rhs   | vi
   ---------+---+---+-------+-------+---+-----+---------+---------+----
    2518431 | 1 | f | 22011 | inf   | 9 | 0x0 | 2518430 | 1506228 |
    2518433 | 1 | f | 22017 | inf   | 9 | 0x0 | 2518432 | 1491111 |
    2518435 | 1 | f | 22080 | inf   | 9 | 0x0 | 2518434 | 1489274 |
    2518437 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518436 | 1487001 |
    2518439 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518438 | 1487003 |
    2518441 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518440 | 1488086 |
    2518443 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518442 | 1489549 |
    2518445 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518444 | 1491457 |
    2518447 | 1 | f | 22105 | inf   | 9 | 0x0 | 2518446 | 1491733 |
    2518449 | 1 | f | 22155 | inf   | 9 | 0x0 | 2518448 | 1584003 |
    2518451 | 1 | f | 22155 | inf   | 9 | 0x0 | 2518450 | 1584694 |

Shows us the link_values.

Looking at the left hand side, you'll find all annotations.

   SELECT stk_id, v, d, nom, a, g, start, until, ityp FROM _gia
   WHERE stk_id IN (SELECT lhs FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS FALSE);

    stk_id  | v | d | nom | a | g | start | until |    ityp
   ---------+---+---+-----+---+---+-------+-------+------------
    2518450 | 1 | f |     | 3 | 1 | 22155 | inf   | annotation
    2518448 | 1 | f |     | 3 | 1 | 22155 | inf   | annotation
    2518446 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518444 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518442 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518440 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518438 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518436 | 1 | f |     | 3 | 1 | 22105 | inf   | annotation
    2518434 | 1 | f |     | 3 | 1 | 22080 | inf   | annotation
    2518432 | 1 | f |     | 3 | 1 | 22017 | inf   | annotation
    2518430 | 1 | f |     | 3 | 1 | 22011 | inf   | annotation

And looking at the right hand side you'll find all regions.

   SELECT stk_id, v, d, nom, a, g, start, ityp FROM _gia
   WHERE stk_id IN (SELECT rhs FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS FALSE);

    stk_id  | v | d |               nom               | a | g | start |  ityp
   ---------+---+---+---------------------------------+---+---+-------+--------
    1584694 | 1 | f | como                            | 3 | 1 | 22155 | region
    1584003 | 1 | f | uofm                            | 3 | 1 | 22155 | region
    1506228 | 1 | f | I-494 South St. Paul Bridge     | 3 | 1 | 22011 | region
    1491733 | 1 | f | Fix this intersection           | 3 | 1 | 22105 | region
    1491457 | 1 | f | RxR shortchut                   | 3 | 1 | 22105 | region
    1491111 | 1 | f | Fridley to North Oaks - watched | 3 | 1 | 22017 | region
    1489549 | 1 | f | Fix this area                   | 3 | 1 | 22105 | region
    1489274 | 1 | f | McRae Park                      | 3 | 1 | 22080 | region
    1488086 | 1 | f | fix this area at high res       | 3 | 1 | 22105 | region
    1487003 | 1 | t | Small park                      | 3 | 1 | 22105 | region
    1487001 | 1 | f | Silver Park area                | 3 | 1 | 22105 | region

And looking at one of the regions, which I recognize as private to me,

   SELECT
   id, version AS v, deleted AS d, name AS nom,
   notify_email AS noty, type_code AS tc,
   valid_starting_rid AS start,
   CASE WHEN valid_before_rid = 2000000000
     THEN 'inf' ELSE valid_before_rid::TEXT END AS until,
   comments
   FROM watch_region WHERE username = 'landonb';

      id    | v | d |    nom     | noty | tc | start | until |    comments
   ---------+---+---+------------+------+----+-------+-------+-----------------
    1489315 | 0 | f | Home       | t    |  2 |     0 | inf   |
    1489274 | 0 | f | McRae Park | t    |  2 |     0 | inf   | This is a test.

And the link_value,

    stk_id  | v | d | start | until | a | nfr |   lhs   |   rhs   | vi
   ---------+---+---+-------+-------+---+-----+---------+---------+----
    2518435 | 1 | f | 22080 | inf   | 9 | 0x0 | 2518434 | 1489274 |

Makes me think the CcpV1->V2 upgrade scripts forget or failed to make links for
private watch region comment annotations.

Indeed, taking the region stack IDs and comparing against the CcpV1 database,

   SELECT
   id, version AS v, deleted AS d, name AS nom,
   notify_email AS noty, type_code AS tc,
   valid_starting_rid AS start,
   CASE WHEN valid_before_rid = 2000000000
     THEN 'inf' ELSE valid_before_rid::TEXT END AS until,
   comments
   FROM watch_region WHERE id IN (
    1584694,
    1584003,
    1506228,
    1491733,
    1491457,
    1491111,
    1489549,
    1489274,
    1488086,
    1487003,
    1487001);

   SELECT COUNT(*) FROM watch_region WHERE comments <> '';
    count
   -------
       11

You'll see that all the problem link_values are private watch region notes.

*/

/* First, the item_stack rows. */

UPDATE item_stack st
SET    access_style_id = cp_access_style_id('usr_editor'),
       access_infer_id = cp_access_infer_id('usr_editor')
FROM   link_value lv
JOIN   item_versioned iv USING (system_id)
WHERE  NOT EXISTS(SELECT 1
                  FROM   group_item_access gia
                  WHERE  gia.item_id = lv.system_id)
       AND iv.deleted IS FALSE
       AND st.stack_id = lv.stack_id;
/*
UPDATE 11
Time: 2281.093 ms
*/

/* Next, the group_item_access rows. */

CREATE FUNCTION group_item_access_add_link_values_watch_regions()
   RETURNS VOID AS $$
   DECLARE
      lv_row RECORD;
      acl_editor INTEGER;
      lval_type_id INTEGER;
      annot_type_id INTEGER;
      region_type_id INTEGER;
      group_private_id INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      acl_editor := cp_access_level_id('editor');
      lval_type_id := cp_item_type_id('link_value');
      annot_type_id := cp_item_type_id('annotation');
      region_type_id := cp_item_type_id('region');

      FOR lv_row IN SELECT lv.system_id,
                           lv.branch_id,
                           lv.stack_id,
                           lv.version,
                           lv.lhs_stack_id,
                           lv.rhs_stack_id,
                           --lv.direction_id,
                           --lv.value_boolean,
                           --lv.value_integer,
                           --lv.value_real,
                           --lv.value_text,
                           --lv.value_binary,
                           --lv.value_date,
                           --lv.split_from_stack_id,
                           ----lv.line_evt_mval_a,
                           ----lv.line_evt_mval_b,
                           ----lv.line_evt_dir_id,
                           ----lv.tsvect_value_text,
                           iv.deleted,
                           iv.reverted,
                           iv.name,
                           iv.valid_start_rid,
                           iv.valid_until_rid,
                           st.creator_name,
                           st.stealth_secret,
                           st.cloned_from_id,
                           st.access_style_id,
                           st.access_infer_id
                    FROM   link_value lv
                    JOIN   item_versioned iv USING (system_id)
                    JOIN   item_stack st ON (st.stack_id = lv.stack_id)
                    WHERE  NOT EXISTS(SELECT 1
                                      FROM   group_item_access gia
                                      WHERE  gia.item_id = lv.system_id)
                           AND iv.deleted IS FALSE
      LOOP
         group_private_id := cp_group_private_id(lv_row.creator_name);
         INSERT INTO group_item_access
            (group_id,
             access_level_id,
             -- Leave NULL: session_id
             item_id,
             branch_id,
             stack_id,
             version,
             acl_grouping,
             valid_start_rid,
             valid_until_rid,
             deleted,
             reverted,
             name,
             item_type_id,
             link_lhs_type_id,
             link_rhs_type_id,
             created_by
             -- date_created
             -- tsvect_name
            )
            VALUES
              (group_private_id, -- group_id
               acl_editor, -- access_level_id
               lv_row.system_id,
               lv_row.branch_id,
               lv_row.stack_id,
               lv_row.version,
               1, -- acl_grouping
               lv_row.valid_start_rid,
               lv_row.valid_until_rid,
               lv_row.deleted,
               lv_row.reverted,
               lv_row.name,
               lval_type_id, -- item_type_id
               annot_type_id, -- link_lhs_type_id
               region_type_id, -- link_rhs_type_id
               lv_row.creator_name -- created_by
               );
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT group_item_access_add_link_values_watch_regions();

DROP FUNCTION group_item_access_add_link_values_watch_regions();

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Link_Value: Repair Two Lost Watch_Regions
\qecho

/*
   After running this script the first time, I found a bunch of
   missing item_revisionless rows. That's what a lot of code in
   this script does: fix the many different problems that caused
   the symptom of missing item_revisionless rows.

   E.g., I ran

      SELECT COUNT(*) FROM _rg AS iv -- 0
         WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                                  WHERE ir.system_id = iv.sys_id);

   and found two missing rows.

   SELECT stk_id, v, d, nom, start, until, a, nfr, area
      FROM _rg AS iv
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.sys_id);
    stk_id  | v | d |     nom      | start | until | a | nfr |    area     
   ---------+---+---+--------------+-------+-------+---+-----+-------------
    1366184 | 0 | f | XXXXXXXXXXXX |     0 | inf   | 9 | 0x0 | 1010344919.
    1366185 | 0 | f | XXXXXXXXXXXX |     0 | inf   | 9 | 0x0 | 252586229.8

   SELECT id, version, deleted, name, username, notify_email AS email,
          comments AS note
   FROM watch_region WHERE id IN (1366184, 1366185);

      id    | version | deleted |     name     | username | email | note 
   ---------+---------+---------+--------------+----------+-------+------
    1366185 |       0 | f       | XXXXXXXXXXXX | roseradz | t     | 
    1366184 |       0 | f       | XXXXXXXXXXXX | roseradz | t     | 

   I think this was an earlier error. From 201-apb-60-groups-pvt_ins3.sql:
     "INFO:  No such group or user is not member: roseradz"
   except that the user does exist:
      SELECT COUNT(*) FROM user_ WHERE username = 'roseradz'; --> is: 1.

   So we can just make GIA records, and fix the item_stack records.
*/

/* First, fix the geofeature version. */

/* NOTE: We'll recreated this constraint using db_load_add_constraints.sql */

UPDATE geofeature gf
SET    version = 1
WHERE  version = 0;
/*
UPDATE 2
Time: 35.877 ms
*/

/* Second, fix the group_item_access version. */

UPDATE group_item_access gia
SET    version = 1
WHERE  version = 0;
/*
UPDATE 0
Time: 1.951 ms
*/

/* Third, fix the item_versioned version. */

UPDATE item_versioned iv
SET    version = 1
WHERE  version = 0;
/*
UPDATE 2
Time: 42.930 ms
*/

/* Fourth, the item_stack rows. */

UPDATE item_stack st
SET    creator_name = 'roseradz',
       access_style_id = cp_access_style_id('usr_editor'),
       access_infer_id = cp_access_infer_id('usr_editor')
WHERE  st.stack_id IN (1366184, 1366185);
/*
UPDATE 2
Time: 23.146 ms
*/

/* Next, the group_item_access rows. */

CREATE FUNCTION group_item_access_add_watch_regions()
   RETURNS VOID AS $$
   DECLARE
      rg_row RECORD;
      acl_editor INTEGER;
      region_type_id INTEGER;
      group_private_id INTEGER;
   BEGIN
      /* Cache plpgsql values. */
      acl_editor := cp_access_level_id('editor');
      region_type_id := cp_item_type_id('region');

      FOR rg_row IN SELECT rg.system_id,
                           rg.branch_id,
                           rg.stack_id,
                           rg.version,
                           iv.deleted,
                           iv.reverted,
                           iv.name,
                           iv.valid_start_rid,
                           iv.valid_until_rid,
                           st.creator_name,
                           st.stealth_secret,
                           st.cloned_from_id,
                           st.access_style_id,
                           st.access_infer_id
                    FROM   geofeature rg
                    JOIN   item_versioned iv USING (system_id)
                    JOIN   item_stack st ON (st.stack_id = rg.stack_id)
                    WHERE  rg.stack_id IN (1366184, 1366185)
      LOOP
         group_private_id := cp_group_private_id(rg_row.creator_name);
         INSERT INTO group_item_access
            (group_id,
             access_level_id,
             -- Leave NULL: session_id
             item_id,
             branch_id,
             stack_id,
             version,
             acl_grouping,
             valid_start_rid,
             valid_until_rid,
             deleted,
             reverted,
             name,
             item_type_id,
             --link_lhs_type_id,
             --link_rhs_type_id,
             created_by
             -- date_created
             -- tsvect_name
            )
            VALUES
              (group_private_id, -- group_id
               acl_editor, -- access_level_id
               rg_row.system_id,
               rg_row.branch_id,
               rg_row.stack_id,
               rg_row.version,
               1, -- acl_grouping
               rg_row.valid_start_rid,
               rg_row.valid_until_rid,
               rg_row.deleted,
               rg_row.reverted,
               rg_row.name,
               region_type_id, -- item_type_id
               -- link_lhs_type_id
               -- link_rhs_type_id
               rg_row.creator_name -- created_by
               );
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT group_item_access_add_watch_regions();

DROP FUNCTION group_item_access_add_watch_regions();

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Link_Value: Remove Deleted Link_Values with "Missing" GIA Records
\qecho

/*

There's a similar problem with link_values that are marked deleted.

   SELECT stk_id, v, d, start, until, a, nfr, lhs, rhs, vi FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS NOT FALSE
      ORDER BY start, stk_id, v DESC;

shows all 123 link_values. Here are some examples:

 stk_id  | v | d | start | until | a | nfr  |   lhs   |   rhs   |
---------+---+---+-------+-------+---+------+---------+---------+-
 1354932 | 2 | t |  4668 | inf   | 9 | 0x0  | 1354916 | 1015696 |
 1977021 | 1 | t |  5464 | inf   | 9 | 0x0  | 1823216 | 1376653 |
 2145916 | 1 | t |  5464 | inf   | 9 | 0x0  | 1992111 | 1376653 |
 2483706 | 1 | t |  5464 | inf   | 9 | 0x0  | 2329901 | 1376653 |
 1355154 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1355122 | 1092891 |
 1362522 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1354009 | 1092891 |
 1407725 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1406085 | 1092891 |
 1483518 | 2 | t | 11754 | 11755 | 9 | 0x0  | 1406085 | 1483519 |
 1564437 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1014239 |
 1594761 | 1 | t | 20788 | inf   | 9 | 0x0  | 1406085 | 1594744 |
 1596646 | 1 | t | 21201 | inf   | 9 | 0x0  | 1422707 | 1596647 |

Here are all the records. I've noted a problem I found (described
further below) wherein we're missing items indicated by the
lhs and rhs stack IDs (or, those items never existed; maybe the
referenced byways, e.g., were fresh in the client and abandoned,
but a map save included their links... which I seem to remember
being a caveat about CcpV1 put_feature, because we had that silly
orhpan cleaner task).

 stk_id  | v | d | start | until | a | nfr  |   lhs   |   rhs   |
---------+---+---+-------+-------+---+------+---------+---------+-
 1354932 | 2 | t |  4668 | inf   | 9 | 0x0  | 1354916 | 1015696 |
 1977021 | 1 | t |  5464 | inf   | 9 | 0x0  | 1823216 |+1376653+| NO RHS BYWAY
 2145916 | 1 | t |  5464 | inf   | 9 | 0x0  | 1992111 | 1376653 | NO RHS BYWAY
 2483706 | 1 | t |  5464 | inf   | 9 | 0x0  | 2329901 | 1376653 | NO RHS BYWAY
 1977213 | 1 | t |  5486 | inf   | 9 | 0x0  | 1823216 |+1377071+| NO RHS BYWAY
 2146108 | 1 | t |  5486 | inf   | 9 | 0x0  | 1992111 | 1377071 | NO RHS BYWAY
 2483898 | 1 | t |  5486 | inf   | 9 | 0x0  | 2329901 | 1377071 | NO RHS BYWAY
 1977254 | 1 | t |  5514 | inf   | 9 | 0x0  | 1823216 |+1377229+| NO RHS BYWAY
 2146149 | 1 | t |  5514 | inf   | 9 | 0x0  | 1992111 | 1377229 | NO RHS BYWAY
 2483939 | 1 | t |  5514 | inf   | 9 | 0x0  | 2329901 | 1377229 | NO RHS BYWAY
 1355472 | 2 | t |  5676 | inf   | 9 | 0x0  | 1355471 | 1050685 |
 1377188 | 2 | t |  5676 | inf   | 9 | 0x0  | 1377189 | 1050685 |
 1408984 | 2 | t |  5676 | inf   | 9 | 0x0  | 1408951 | 1050685 |
 1380319 | 1 | t |  5944 | inf   | 9 | 0x0  | 1369746 |+1380317+| NO RHS BYWAY
 1355154 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1355122 | 1092891 |
 1362522 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1354009 | 1092891 |
 1407725 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1406085 | 1092891 |
 1395180 | 2 | t |  6280 | inf   | 9 | 0x0  | 1364864 | 1395160 |
 1979653 | 1 | t |  6463 | inf   | 9 | 0x0  | 1823216 |+1396713+| NO RHS BYWAY
 2148548 | 1 | t |  6463 | inf   | 9 | 0x0  | 1992111 | 1396713 | NO RHS BYWAY
 2486338 | 1 | t |  6463 | inf   | 9 | 0x0  | 2329901 | 1396713 | NO RHS BYWAY
 1356753 | 2 | t |  6676 | inf   | 9 | 0x0  | 1356758 | 1138624 |
 1980468 | 1 | t |  6803 | inf   | 9 | 0x0  | 1823216 |+1399078+| NO RHS BYWAY
 2149363 | 1 | t |  6803 | inf   | 9 | 0x0  | 1992111 | 1399078 | NO RHS BYWAY
 2487153 | 1 | t |  6803 | inf   | 9 | 0x0  | 2329901 | 1399078 | NO RHS BYWAY
 1398965 | 2 | t |  7152 | inf   | 9 | 0x0  | 1397538 | 1398970 |
 1981950 | 1 | t |  7618 | inf   | 9 | 0x0  | 1823216 |+1409413+| NO RHS BYWAY
 2150845 | 1 | t |  7618 | inf   | 9 | 0x0  | 1992111 | 1409413 | NO RHS BYWAY
 2488635 | 1 | t |  7618 | inf   | 9 | 0x0  | 2329901 | 1409413 | NO RHS BYWAY
 1373629 | 4 | t | 10519 | inf   | 9 | 0x0  | 1373576 | 1373622 |
 1468369 | 2 | t | 10850 | inf   | 9 | 0x0  | 1409158 | 1371957 |
 1817061 | 1 | t | 10859 | inf   | 9 | 0x0  | 1654321 |+1473788+| NO RHS BYWAY
 1985956 | 1 | t | 10859 | inf   | 9 | 0x0  | 1823216 | 1473788 | NO RHS BYWAY
 2154851 | 1 | t | 10859 | inf   | 9 | 0x0  | 1992111 | 1473788 | NO RHS BYWAY
 2492641 | 1 | t | 10859 | inf   | 9 | 0x0  | 2329901 | 1473788 | NO RHS BYWAY
 1469326 | 2 | t | 11309 | inf   | 9 | 0x0  | 1409158 | 1104220 |
 1483518 | 2 | t | 11754 | 11755 | 9 | 0x0  | 1406085 | 1483519 |
 1505896 | 1 | t | 13056 | inf   | 9 | 0x0  |+1505897+|  993141 | NO LHS ITEM
 1989040 | 1 | t | 13231 | inf   | 9 | 0x0  | 1823216 |+1510190+| NO RHS BYWAY
 1510236 | 1 | t | 13232 | inf   | 9 | 0x0  | 1510173 |+1510237+| NO RHS ITEM
 1989129 | 1 | t | 13309 | inf   | 9 | 0x0  | 1823216 |+1511742+| NO RHS BYWAY
 2158024 | 1 | t | 13309 | inf   | 9 | 0x0  | 1992111 | 1511742 | NO RHS BYWAY
 2495814 | 1 | t | 13309 | inf   | 9 | 0x0  | 2329901 | 1511742 | NO RHS BYWAY
 1517199 | 1 | t | 13618 | inf   | 9 | 0x0  | 1485315 |+1517188+| NO RHS BYWAY
 1517206 | 1 | t | 13618 | inf   | 9 | 0x0  | 1422707 | 1517188 | NO RHS BYWAY
 1517209 | 1 | t | 13618 | inf   | 9 | 0x0  | 1421828 | 1517188 | NO RHS BYWAY
 1517218 | 1 | t | 13618 | inf   | 9 | 0x0  | 1408486 |+1517219+| NO RHS ITEM
 1522233 | 1 | t | 14183 | inf   | 9 | 0x0  | 1427010 |+1522234+| NO RHS ITEM
 1522238 | 1 | t | 14183 | inf   | 9 | 0x0  | 1522204 | 1522234 | NO RHS ITEM
 1522239 | 1 | t | 14183 | inf   | 9 | 0x0  | 1519547 | 1522234 | NO RHS ITEM
 1522240 | 1 | t | 14183 | inf   | 9 | 0x0  | 1497371 | 1522234 | NO RHS ITEM
 1526698 | 1 | t | 14394 | inf   | 9 | 0x0  | 1446019 |+1526699+| NO RHS ITEM
 1526712 | 1 | t | 14394 | inf   | 9 | 0x0  | 1446019 |+1526713+| NO RHS ITEM
 1526717 | 1 | t | 14394 | inf   | 9 | 0x0  | 1446019 |+1526718+| NO RHS ITEM
 1989423 | 1 | t | 14674 | inf   | 9 | 0x0  | 1823216 |+1533827+| NO RHS BYWAY
 2158318 | 1 | t | 14674 | inf   | 9 | 0x0  | 1992111 | 1533827 | NO RHS BYWAY
 2496108 | 1 | t | 14674 | inf   | 9 | 0x0  | 2329901 | 1533827 | NO RHS BYWAY
 1551401 | 1 | t | 15374 | inf   | 9 | 0x0  | 1369688 |+1551402+| NO RHS ITEM
 1553065 | 1 | t | 15436 | inf   | 9 | 0x0  | 1409158 |+1553051+| NO RHS BYWAY
 1820867 | 1 | t | 15436 | inf   | 9 | 0x0  | 1654321 | 1553051 | NO RHS BYWAY
 1989762 | 1 | t | 15436 | inf   | 9 | 0x0  | 1823216 | 1553051 | NO RHS BYWAY
 2158657 | 1 | t | 15436 | inf   | 9 | 0x0  | 1992111 | 1553051 | NO RHS BYWAY
 2496447 | 1 | t | 15436 | inf   | 9 | 0x0  | 2329901 | 1553051 | NO RHS BYWAY
 1564377 | 1 | t | 16797 | inf   | 9 | 0x0  |+1564378+| 1028655 | NO LHS ITEM
 1564379 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1019210 | NO LHS ITEM
 1564382 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028474 | NO LHS ITEM
 1564385 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1034805 | NO LHS ITEM
 1564386 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 |  989876 | NO LHS ITEM
 1564390 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033715 | NO LHS ITEM
 1564392 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033691 | NO LHS ITEM
 1564396 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033572 | NO LHS ITEM
 1564399 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033580 | NO LHS ITEM
 1564400 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1001470 | NO LHS ITEM
 1564406 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 |  991269 | NO LHS ITEM
 1564408 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028765 | NO LHS ITEM
 1564409 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033705 | NO LHS ITEM
 1564410 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1017029 | NO LHS ITEM
 1564411 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028866 | NO LHS ITEM
 1564412 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028702 | NO LHS ITEM
 1564414 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033643 | NO LHS ITEM
 1564416 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1029440 | NO LHS ITEM
 1564417 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1034801 | NO LHS ITEM
 1564418 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028318 | NO LHS ITEM
 1564422 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028675 | NO LHS ITEM
 1564423 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028913 | NO LHS ITEM
 1564425 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1028603 | NO LHS ITEM
 1564426 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033689 | NO LHS ITEM
 1564428 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1016244 | NO LHS ITEM
 1564430 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033593 | NO LHS ITEM
 1564431 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1019218 | NO LHS ITEM
 1564433 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1033683 | NO LHS ITEM
 1564434 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1029119 | NO LHS ITEM
 1564437 | 1 | t | 16797 | inf   | 9 | 0x0  | 1564378 | 1014239 | NO LHS ITEM
 1571330 | 1 | t | 17830 | inf   | 9 | 0x0  | 1571329 |+1571331+| NO RHS BYWAY
 1580111 | 1 | t | 18843 | inf   | 9 | 0x0  | 1418865 |+1580112+| NO RHS ITEM
 1580156 | 1 | t | 18844 | inf   | 9 | 0x0  | 1418865 |+1580157+| NO RHS ITEM
 1822055 | 1 | t | 18961 | inf   | 9 | 0x0  | 1654321 |+1580869+| NO RHS BYWAY
 1822061 | 1 | t | 18961 | inf   | 9 | 0x0  | 1654321 |+1580880+| NO RHS BYWAY
 1990956 | 1 | t | 18961 | inf   | 9 | 0x0  | 1823216 | 1580880 | NO RHS BYWAY
 2159851 | 1 | t | 18961 | inf   | 9 | 0x0  | 1992111 | 1580880 | NO RHS BYWAY
 2497641 | 1 | t | 18961 | inf   | 9 | 0x0  | 2329901 | 1580880 | NO RHS BYWAY
 1581841 | 1 | t | 19122 | inf   | 9 | 0x0  | 1418865 |+1581842+| NO RHS ITEM
 1581920 | 1 | t | 19131 | inf   | 9 | 0x0  | 1451838 |+1581921+| NO RHS ITEM
 1581934 | 1 | t | 19133 | inf   | 9 | 0x0  | 1451838 |+1581935+| NO RHS ITEM
 1581947 | 1 | t | 19133 | inf   | 9 | 0x0  | 1451838 |+1581948+| NO RHS ITEM
 1581963 | 1 | t | 19133 | inf   | 9 | 0x0  | 1451838 |+1581964+| NO RHS ITEM
 1581998 | 1 | t | 19141 | inf   | 9 | 0x0  | 1451838 |+1581999+| NO RHS ITEM
 1582008 | 1 | t | 19141 | inf   | 9 | 0x0  | 1451838 |+1582009+| NO RHS ITEM
 1582012 | 1 | t | 19145 | inf   | 9 | 0x0  | 1451838 |+1582013+| NO RHS ITEM
 1582046 | 1 | t | 19145 | inf   | 9 | 0x0  | 1451838 |+1582047+| NO RHS ITEM
 1582215 | 1 | t | 19171 | inf   | 9 | 0x0  | 1373900 |+1582216+| NO RHS ITEM
 1582218 | 1 | t | 19171 | inf   | 9 | 0x0  | 1505549 |+1582216+| NO RHS ITEM
 1590436 | 1 | t | 20117 | inf   | 9 | 0x0  | 1397891 |+1590437+| NO RHS ITEM
 1592226 | 1 | t | 20378 | inf   | 9 | 0x0  | 1451838 |+1592227+| NO RHS ITEM
 1592235 | 1 | t | 20378 | inf   | 9 | 0x0  | 1451838 |+1592236+| NO RHS ITEM
 1594207 | 1 | t | 20678 | inf   | 9 | 0x0  | 1484199 |+1594208+| NO RHS ITEM
 1594212 | 1 | t | 20678 | inf   | 9 | 0x0  | 1354373 |+1594208+| NO RHS ITEM
 1594743 | 1 | t | 20788 | inf   | 9 | 0x0  | 1360069 |+1594744+| NO RHS ITEM
 1594746 | 1 | t | 20788 | inf   | 9 | 0x0  | 1360069 |+1594747+| NO RHS ITEM
 1594757 | 1 | t | 20788 | inf   | 9 | 0x0  | 1406085 |+1594758+| NO RHS ITEM
 1594760 | 1 | t | 20788 | inf   | 9 | 0x0  | 1406085 |+1594747+| NO RHS ITEM
 1594761 | 1 | t | 20788 | inf   | 9 | 0x0  | 1406085 |+1594744+| NO RHS ITEM
 1596646 | 1 | t | 21201 | inf   | 9 | 0x0  | 1422707 |+1596647+| NO RHS ITEM
(123 rows)

The latest revision indicated by a link_value, 21201, is 2013-07-31 12:49.

Looking at the left hand side, you'll find all a mix of attachment
types, but limited to the basic CcpV1 types.

   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, until, ityp
   FROM _gia WHERE stk_id IN (SELECT lhs FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS NOT FALSE)
      ORDER BY start, stk_id, v DESC;

    stk_id  | v | d |      nom      | a | g | start | until |    ityp
   ---------+---+---+---------------+---+---+-------+-------+------------
    1654321 | 1 | f | Direction     | 4 | 1 |     1 | inf   | attribute
    1823216 | 1 | f | Speed limit   | 4 | 1 |     1 | inf   | attribute
    1992111 | 1 | f | Total number  | 4 | 1 |     1 | inf   | attribute
    2329901 | 1 | f | Usable should | 4 | 1 |     1 | inf   | attribute
    1406085 | 1 | f | bikelane      | 3 | 1 |   133 | inf   | tag
    1408486 | 1 | f | unpaved       | 3 | 1 |   142 | inf   | tag
    1354009 | 1 | f |               | 3 | 1 |   453 | inf   | annotation
    1354373 | 1 | f |               | 3 | 1 |   481 | inf   | annotation
    1354916 | 1 | f |               | 3 | 1 |   681 | 7703  | annotation
    1355122 | 1 | f |               | 3 | 1 |   912 | 5188  | annotation
    1355471 | 1 | f |               | 3 | 1 |  1252 | 5676  | annotation
    1356758 | 1 | f |               | 3 | 1 |  1729 | inf   | annotation
    1408951 | 1 | f | closed        | 3 | 1 |  1818 | inf   | tag
    1360069 | 1 | f |               | 3 | 1 |  2389 | inf   | annotation
    1364864 | 1 | f |               | 3 | 1 |  3442 | 4428  | annotation
    1364864 | 2 | f |               | 3 | 1 |  4428 | inf   | annotation
    1369688 | 1 | f |               | 3 | 1 |  4443 | inf   | annotation
    1369746 | 1 | f |               | 3 | 1 |  4459 | inf   | annotation
    1373576 | 1 | f |               | 3 | 1 |  4931 | 6759  | annotation
    1373900 | 1 | f |               | 3 | 1 |  4995 | 7951  | annotation
    1355122 | 2 | f |               | 3 | 1 |  5188 | inf   | annotation
    1377189 | 1 | f |               | 3 | 1 |  5512 | 5676  | annotation
    1355471 | 2 | t |               | 3 | 1 |  5676 | inf   | annotation
    1377189 | 2 | t |               | 3 | 1 |  5676 | inf   | annotation
    1397538 | 1 | f |               | 3 | 1 |  6577 | inf   | annotation
    1397891 | 1 | f |               | 3 | 1 |  6645 | inf   | annotation
    1373576 | 2 | t |               | 3 | 1 |  6759 | 6760  | annotation
    1373576 | 3 | f |               | 3 | 1 |  6760 | inf   | annotation
    1409158 | 1 | f | hill          | 3 | 1 |  7568 | inf   | tag
    1354916 | 2 | f |               | 3 | 1 |  7703 | inf   | annotation
    1373900 | 2 | f |               | 3 | 1 |  7951 | inf   | annotation
    1418865 | 1 | f | gravel        | 3 | 1 |  8219 | inf   | tag
    1421828 | 1 | f | paved path    | 3 | 1 |  8380 | inf   | tag
    1422707 | 1 | f | park          | 3 | 1 |  8418 | inf   | tag
    1427010 | 1 | f | dirt path     | 3 | 1 |  8696 | inf   | tag
    1446019 | 1 | f | residential   | 3 | 1 | 10007 | inf   | tag
    1451838 | 1 | f | prohibited    | 3 | 1 | 10378 | inf   | tag
    1484199 | 1 | f |               | 3 | 1 | 11634 | 11635 | annotation
    1484199 | 2 | f |               | 3 | 1 | 11635 | inf   | annotation
    1485315 | 1 | f | quiet         | 3 | 1 | 11758 | inf   | tag
    1497371 | 1 | f | wooded        | 3 | 1 | 12651 | inf   | tag
    1505549 | 1 | f | crossings not | 3 | 1 | 13036 | inf   | tag
    1510173 | 1 | f | sidepath      | 3 | 1 | 13231 | inf   | tag
    1519547 | 1 | f | single lane   | 3 | 1 | 13928 | inf   | tag
    1522204 | 1 | f |               | 3 | 1 | 14179 | inf   | annotation
    1571329 | 1 | f | rice creek no | 3 | 1 | 17830 | inf   | tag
   (46 rows)

The latest revision noted, 17830, is 2012-07-01 18:20.

Looking at the right hand side, you'll find all byways.

   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, ityp
   FROM _gia WHERE stk_id IN (SELECT rhs FROM _lv
      WHERE NOT EXISTS(SELECT 1 FROM group_item_access AS gia
                               WHERE gia.item_id = _lv.sys_id)
                           AND d IS NOT FALSE)
      ORDER BY start, stk_id, v DESC;

    stk_id  | v | d |      nom      | a | g | start | ityp
   ---------+---+---+---------------+---+---+-------+-------
     989876 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
     991269 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
     993141 | 1 | f | 29th Ave NE   | 3 | 1 |   133 | byway
    1001470 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1014239 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1015696 | 1 | f | Broadway St N | 3 | 1 |   133 | byway
    1016244 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1017029 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1019210 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1019218 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1028318 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1028474 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1028603 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1028655 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1028675 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1028702 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1028765 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1028866 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1028913 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1029119 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1029440 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033572 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033580 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033593 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1033643 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033683 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033689 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033691 | 1 | f | E 76th St     | 3 | 1 |   133 | byway
    1033705 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1033715 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1034801 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1034805 | 1 | f | W 76th St     | 3 | 1 |   133 | byway
    1050685 | 1 | f | N Griggs St   | 3 | 1 |   133 | byway
    1092891 | 1 | f | W Summit Ave  | 3 | 1 |   133 | byway
    1104220 | 1 | f | Gramsie Rd    | 3 | 1 |   133 | byway
    1138624 | 1 | f | Hardwood Cree | 3 | 1 |   142 | byway
    1050685 | 2 | f | N Griggs St   | 3 | 1 |  1252 | byway
    1092891 | 2 | f | W Summit Ave  | 3 | 1 |  1585 | byway
    1104220 | 2 | f | Gramsie Rd    | 3 | 1 |  2207 | byway
    1092891 | 3 | f | W Summit Ave  | 3 | 1 |  2610 | byway
    1050685 | 3 | f | N Griggs St   | 3 | 1 |  2900 | byway
    1371957 | 1 | f | Glenwood Ave  | 3 | 1 |  4757 | byway
    1373622 | 1 | f |               | 3 | 1 |  4941 | byway
    1092891 | 4 | f | W Summit Ave  | 3 | 1 |  5287 | byway
    1050685 | 4 | f | N Griggs St   | 3 | 1 |  5512 | byway
    1092891 | 6 | f | W Summit Ave  | 3 | 1 |  6245 | byway
    1395160 | 1 | f |               | 3 | 1 |  6275 | byway
    1395160 | 2 | f |               | 3 | 1 |  6279 | byway
    1398970 | 1 | f | W Como Ave    | 3 | 1 |  6794 | byway
    1104220 | 3 | f | Gramsie Rd    | 3 | 1 | 10749 | byway
    1483519 | 1 | f | Portland Ave  | 3 | 1 | 11563 | byway
    1483519 | 3 | f | Portland Ave  | 3 | 1 | 11755 | byway
    1092891 | 7 | t | W Summit Ave  | 3 | 1 | 22303 | byway
   (53 rows)

The latest revision noted, 17830, is 2013-11-26 16:10, Metc Bikeways Import.
The one before it, 11755, is 2010-03-29 15:37.

Since both lhs and rhs revisions are before the CcpV1->V2 upgrade,
and because privatey things were not apart of the various link tables,
we should be safe in assuming everything is public. Nonetheless, let's
dig a little deeper, before we decide what to do.

You'll notice above where I marked link_values referencing items
no where to be found. Here's an example of one the link_values ID,
from the old CcpV1 database:

   SELECT * FROM tag_bs WHERE id = 1581934;
      id    | version | deleted | tag_id  | byway_id | valid_starting_rid |
   ---------+---------+---------+---------+----------+--------------------+
    1581934 |       1 | t       | 1451838 |  1581935 |              19133 |

   SELECT COUNT(*) FROM byway_segment WHERE id = 1581935;
    count
   -------
        0

Behold, the problem doesn't appear to be a CcpV1->V2 upgrade problem,
at least not for some of these link_values.

I also checked point, region, and watch_region, but that byway_id, 1581935,
is no where to be found.

But for some link_values whose rhs item is missing from CcpV2, it is a
CcpV1->V2 upgrade problem.

   SELECT id, version AS v, deleted AS d, name AS nom,
          valid_starting_rid, valid_before_rid
   FROM byway_segment WHERE id = 1571331;

      id    | v | d | nom | valid_starting_rid | valid_before_rid
   ---------+---+---+-----+--------------------+------------------
    1571331 | 1 | t |     |              17830 |       2000000000

But in CcpV2,

   SELECT COUNT(*) FROM _by WHERE stk_id = 1571331;
    count
   -------
        0

so we didn't make GIA records for some deleted byways, which will make
reverting these byways impossible. But how much do we care about this
roads? Not that much!

Ug... checking item_versioned:

   SELECT * FROM _iv WHERE stk_id = 1571331;
    sys_id | brn_id  | stk_id  | v | d | r | nom | start | until | a | nfr
   --------+---------+---------+---+---+---+-----+-------+-------+---+-----
    227203 | 2500677 | 1571331 | 1 | t | f |     | 17830 | inf   | 9 | 0x0

And looking at the links with missing attachments, 1564378 and 1505897:

   SELECT * FROM annot_bs WHERE id = 1505896;
      id    | version | deleted | annot_id | byway_id | valid_starting_rid |
   ---------+---------+---------+----------+----------+--------------------+
    1505896 |       1 | t       |  1505897 |   993141 |              13056 |
   SELECT COUNT(*) FROM annotation WHERE id = 1505897;
    count
   -------
        0

   SELECT * FROM annot_bs WHERE id = 1564377;
      id    | version | deleted | annot_id | byway_id | valid_starting_rid |
   ---------+---------+---------+----------+----------+--------------------+
    1564377 |       1 | t       |  1564378 |  1028655 |              16797 |
   SELECT COUNT(*) FROM annotation WHERE id = 1564378;
    count
   -------
        0

SOLUTION: Delete all these link_values missing GIA records, and
          delete the handful of byways that were deleted in CcpV1
          but were improperly imported (technically, we should
          export the geometry from CcpV1 and insert new rows into
          geofeature and group_item_access, but it's really not
          worth the effort for these rows).

*/

/* These are link_values with no lhs or rhs item, anywhere, and
   [lb] verified as much against the CcpV1 database, too.
   These are marked NO LHS ITEM and NO RHS ITEM, above. */

CREATE FUNCTION link_value_delete_orphans(lval_stk_id INTEGER)
   RETURNS VOID AS $$
   BEGIN
      DELETE FROM group_item_access WHERE stack_id = lval_stk_id;
      DELETE FROM link_value WHERE stack_id = lval_stk_id;
      DELETE FROM item_versioned WHERE stack_id = lval_stk_id;
      DELETE FROM item_stack WHERE stack_id = lval_stk_id;
   END
$$ LANGUAGE plpgsql VOLATILE;

SELECT link_value_delete_orphans(1505896);
SELECT link_value_delete_orphans(1510236);
SELECT link_value_delete_orphans(1517218);
SELECT link_value_delete_orphans(1522233);
SELECT link_value_delete_orphans(1522238);
SELECT link_value_delete_orphans(1522239);
SELECT link_value_delete_orphans(1522240);
SELECT link_value_delete_orphans(1526698);
SELECT link_value_delete_orphans(1526712);
SELECT link_value_delete_orphans(1526717);
SELECT link_value_delete_orphans(1551401);
SELECT link_value_delete_orphans(1564377);
SELECT link_value_delete_orphans(1564379);
SELECT link_value_delete_orphans(1564382);
SELECT link_value_delete_orphans(1564385);
SELECT link_value_delete_orphans(1564386);
SELECT link_value_delete_orphans(1564390);
SELECT link_value_delete_orphans(1564392);
SELECT link_value_delete_orphans(1564396);
SELECT link_value_delete_orphans(1564399);
SELECT link_value_delete_orphans(1564400);
SELECT link_value_delete_orphans(1564406);
SELECT link_value_delete_orphans(1564408);
SELECT link_value_delete_orphans(1564409);
SELECT link_value_delete_orphans(1564410);
SELECT link_value_delete_orphans(1564411);
SELECT link_value_delete_orphans(1564412);
SELECT link_value_delete_orphans(1564414);
SELECT link_value_delete_orphans(1564416);
SELECT link_value_delete_orphans(1564417);
SELECT link_value_delete_orphans(1564418);
SELECT link_value_delete_orphans(1564422);
SELECT link_value_delete_orphans(1564423);
SELECT link_value_delete_orphans(1564425);
SELECT link_value_delete_orphans(1564426);
SELECT link_value_delete_orphans(1564428);
SELECT link_value_delete_orphans(1564430);
SELECT link_value_delete_orphans(1564431);
SELECT link_value_delete_orphans(1564433);
SELECT link_value_delete_orphans(1564434);
SELECT link_value_delete_orphans(1564437);
SELECT link_value_delete_orphans(1580111);
SELECT link_value_delete_orphans(1580156);
SELECT link_value_delete_orphans(1581841);
SELECT link_value_delete_orphans(1581920);
SELECT link_value_delete_orphans(1581934);
SELECT link_value_delete_orphans(1581947);
SELECT link_value_delete_orphans(1581963);
SELECT link_value_delete_orphans(1581998);
SELECT link_value_delete_orphans(1582008);
SELECT link_value_delete_orphans(1582012);
SELECT link_value_delete_orphans(1582046);
SELECT link_value_delete_orphans(1582215);
SELECT link_value_delete_orphans(1582218);
SELECT link_value_delete_orphans(1590436);
SELECT link_value_delete_orphans(1592226);
SELECT link_value_delete_orphans(1592235);
SELECT link_value_delete_orphans(1594207);
SELECT link_value_delete_orphans(1594212);
SELECT link_value_delete_orphans(1594743);
SELECT link_value_delete_orphans(1594746);
SELECT link_value_delete_orphans(1594757);
SELECT link_value_delete_orphans(1594760);
SELECT link_value_delete_orphans(1594761);
SELECT link_value_delete_orphans(1596646);

/* These are link_values with a deleted rhs item that was a
   publically editable byway. These are marked NO RHS BYWAY,
   above, because in CcpV2 during the upgrade we failed to
   make the geofeature and group_item_access rows.

   And rather than import the few missing byways, we might
   as well delete them.

   And note that I'm not sure why these byways were special:
   I'm sure there were other deleted byways from CcpV1 that
   *were* successfully copied over... right?

For example,

   SELECT * FROM _iv WHERE stk_id = 1376653;
    sys_id | stk_id  | v | d | r |    nom    | start | until | a | nfr 
   --------+---------+---+---+---+-----------+-------+-------+---+-----
    182288 | 1376653 | 1 | t | f | 73rd St E |  5464 | inf   | 9 | 0x0

   SELECT COUNT(*) FROM geofeature WHERE stack_id = 1376653;
    count 
   -------
        0

But, in CcpV1,

   SELECT COUNT(*) FROM byway_segment WHERE id = 1376653;
    count 
   -------
        1
Copied from above,

 2145916 | 1 | t |  5464 | inf   | 9 | 0x0  | 1992111 |+1376653+| NO RHS BYWAY
 1977213 | 1 | t |  5486 | inf   | 9 | 0x0  | 1823216 |+1377071+| NO RHS BYWAY
 1977254 | 1 | t |  5514 | inf   | 9 | 0x0  | 1823216 |+1377229+| NO RHS BYWAY
 1380319 | 1 | t |  5944 | inf   | 9 | 0x0  | 1369746 |+1380317+| NO RHS BYWAY
 1979653 | 1 | t |  6463 | inf   | 9 | 0x0  | 1823216 |+1396713+| NO RHS BYWAY
 1980468 | 1 | t |  6803 | inf   | 9 | 0x0  | 1823216 |+1399078+| NO RHS BYWAY
 1981950 | 1 | t |  7618 | inf   | 9 | 0x0  | 1823216 |+1409413+| NO RHS BYWAY
 1817061 | 1 | t | 10859 | inf   | 9 | 0x0  | 1654321 |+1473788+| NO RHS BYWAY
 1989040 | 1 | t | 13231 | inf   | 9 | 0x0  | 1823216 |+1510190+| NO RHS BYWAY
 1989129 | 1 | t | 13309 | inf   | 9 | 0x0  | 1823216 |+1511742+| NO RHS BYWAY
 1517199 | 1 | t | 13618 | inf   | 9 | 0x0  | 1485315 |+1517188+| NO RHS BYWAY
 1989423 | 1 | t | 14674 | inf   | 9 | 0x0  | 1823216 |+1533827+| NO RHS BYWAY
 1553065 | 1 | t | 15436 | inf   | 9 | 0x0  | 1409158 |+1553051+| NO RHS BYWAY
 1571330 | 1 | t | 17830 | inf   | 9 | 0x0  | 1571329 |+1571331+| NO RHS BYWAY
 1822055 | 1 | t | 18961 | inf   | 9 | 0x0  | 1654321 |+1580869+| NO RHS BYWAY
 1822061 | 1 | t | 18961 | inf   | 9 | 0x0  | 1654321 |+1580880+| NO RHS BYWAY

   SELECT COUNT(*) FROM _by WHERE stk_id IN (
      1376653,
      1377071,
      1377229,
      1380317,
      1396713,
      1399078,
      1409413,
      1473788,
      1510190,
      1511742,
      1517188,
      1533827,
      1553051,
      1571331,
      1580869,
      1580880);
    count 
   -------
        0

   SELECT COUNT(*) FROM byway_segment WHERE id IN (
      1376653,
      1377071,
      1377229,
      1380317,
      1396713,
      1399078,
      1409413,
      1473788,
      1510190,
      1511742,
      1517188,
      1533827,
      1553051,
      1571331,
      1580869,
      1580880);
    count 
   -------
       18

Just delete the byways and their link_values.

 */

CREATE FUNCTION byway_drop_deleted_missing(byway_stk_id INTEGER)
   RETURNS VOID AS $$
   BEGIN
      DELETE FROM item_versioned WHERE stack_id = byway_stk_id;
      DELETE FROM item_stack WHERE stack_id = byway_stk_id;
   END
$$ LANGUAGE plpgsql VOLATILE;

SELECT byway_drop_deleted_missing(1376653);
SELECT byway_drop_deleted_missing(1377071);
SELECT byway_drop_deleted_missing(1377229);
SELECT byway_drop_deleted_missing(1380317);
SELECT byway_drop_deleted_missing(1396713);
SELECT byway_drop_deleted_missing(1399078);
SELECT byway_drop_deleted_missing(1409413);
SELECT byway_drop_deleted_missing(1473788);
SELECT byway_drop_deleted_missing(1510190);
SELECT byway_drop_deleted_missing(1511742);
SELECT byway_drop_deleted_missing(1517188);
SELECT byway_drop_deleted_missing(1533827);
SELECT byway_drop_deleted_missing(1553051);
SELECT byway_drop_deleted_missing(1571331);
SELECT byway_drop_deleted_missing(1580869);
SELECT byway_drop_deleted_missing(1580880);

DROP FUNCTION byway_drop_deleted_missing(byway_stk_id INTEGER);

/* Drop also the link_values for these. See NO RHS BYWAY above. */

SELECT link_value_delete_orphans(1977021);
SELECT link_value_delete_orphans(2145916);
SELECT link_value_delete_orphans(2483706);
SELECT link_value_delete_orphans(1977213);
SELECT link_value_delete_orphans(2146108);
SELECT link_value_delete_orphans(2483898);
SELECT link_value_delete_orphans(1977254);
SELECT link_value_delete_orphans(2146149);
SELECT link_value_delete_orphans(2483939);
SELECT link_value_delete_orphans(1380319);
SELECT link_value_delete_orphans(1979653);
SELECT link_value_delete_orphans(2148548);
SELECT link_value_delete_orphans(2486338);
SELECT link_value_delete_orphans(1980468);
SELECT link_value_delete_orphans(2149363);
SELECT link_value_delete_orphans(2487153);
SELECT link_value_delete_orphans(1981950);
SELECT link_value_delete_orphans(2150845);
SELECT link_value_delete_orphans(2488635);
SELECT link_value_delete_orphans(1817061);
SELECT link_value_delete_orphans(1985956);
SELECT link_value_delete_orphans(2154851);
SELECT link_value_delete_orphans(2492641);
SELECT link_value_delete_orphans(1989040);
SELECT link_value_delete_orphans(1989129);
SELECT link_value_delete_orphans(2158024);
SELECT link_value_delete_orphans(2495814);
SELECT link_value_delete_orphans(1517199);
SELECT link_value_delete_orphans(1517206);
SELECT link_value_delete_orphans(1517209);
SELECT link_value_delete_orphans(1989423);
SELECT link_value_delete_orphans(2158318);
SELECT link_value_delete_orphans(2496108);
SELECT link_value_delete_orphans(1553065);
SELECT link_value_delete_orphans(1820867);
SELECT link_value_delete_orphans(1989762);
SELECT link_value_delete_orphans(2158657);
SELECT link_value_delete_orphans(2496447);
SELECT link_value_delete_orphans(1571330);
SELECT link_value_delete_orphans(1822055);
SELECT link_value_delete_orphans(1822061);
SELECT link_value_delete_orphans(1990956);
SELECT link_value_delete_orphans(2159851);
SELECT link_value_delete_orphans(2497641);

/*

Finally, there are a dozen or so rows whose lhs and rhs items exist
and have GIA records, but for which the link_value does not.

 1354932 | 2 | t |  4668 | inf   | 9 | 0x0  | 1354916 | 1015696 |
 1355472 | 2 | t |  5676 | inf   | 9 | 0x0  | 1355471 | 1050685 |
 1377188 | 2 | t |  5676 | inf   | 9 | 0x0  | 1377189 | 1050685 |
 1408984 | 2 | t |  5676 | inf   | 9 | 0x0  | 1408951 | 1050685 |
 1355154 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1355122 | 1092891 |
 1362522 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1354009 | 1092891 |
 1407725 | 2 | t |  6235 | 6245  | 9 | 0x20 | 1406085 | 1092891 |
 1395180 | 2 | t |  6280 | inf   | 9 | 0x0  | 1364864 | 1395160 |
 1356753 | 2 | t |  6676 | inf   | 9 | 0x0  | 1356758 | 1138624 |
 1398965 | 2 | t |  7152 | inf   | 9 | 0x0  | 1397538 | 1398970 |
 1373629 | 4 | t | 10519 | inf   | 9 | 0x0  | 1373576 | 1373622 |
 1468369 | 2 | t | 10850 | inf   | 9 | 0x0  | 1409158 | 1371957 |
 1469326 | 2 | t | 11309 | inf   | 9 | 0x0  | 1409158 | 1104220 |
 1483518 | 2 | t | 11754 | 11755 | 9 | 0x0  | 1406085 | 1483519 |

E.g.,

   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, ityp
   FROM _gia WHERE stk_id IN (1354916, 1015696);

    stk_id  | v | d |      nom      | a | g | start |    ityp    
   ---------+---+---+---------------+---+---+-------+------------
    1354916 | 2 | f |               | 3 | 1 |  7703 | annotation
    1354916 | 1 | f |               | 3 | 1 |   681 | annotation
    1015696 | 1 | f | Broadway St N | 3 | 1 |   133 | byway

From CcpV1,

   SELECT id, version AS v, deleted AS d, byway_id,
              valid_starting_rid AS start, valid_before_rid AS until
   FROM annot_bs WHERE annot_id = 1354916 ORDER BY id, version DESC;

      id    | v | d | byway_id | start |   until    
   ---------+---+---+----------+-------+------------
    1354904 | 1 | f |  1034862 |   681 | 2000000000
    1354905 | 1 | f |  1059918 |   681 | 2000000000
    1354906 | 1 | f |  1032879 |   681 | 2000000000
    1354907 | 1 | f |  1032014 |   681 | 2000000000
    1354909 | 1 | f |  1046714 |   681 | 2000000000
    1354911 | 2 | t |  1090425 |  7703 | 2000000000
    1354911 | 1 | f |  1090425 |   681 |       7703
    1354912 | 1 | f |  1001466 |   681 | 2000000000
    1354913 | 1 | f |   986187 |   681 | 2000000000
    1354914 | 1 | f |  1076523 |   681 | 2000000000
    1354917 | 1 | f |  1032015 |   681 | 2000000000
    1354918 | 1 | f |  1018389 |   681 | 2000000000
    1354919 | 1 | f |   989110 |   681 | 2000000000
    1354920 | 1 | f |  1099023 |   681 | 2000000000
    1354921 | 1 | f |  1078391 |   681 | 2000000000
    1354923 | 1 | f |   986189 |   681 | 2000000000
    1354924 | 1 | f |  1032878 |   681 | 2000000000
    1354925 | 2 | t |  1008577 |  5279 | 2000000000
    1354925 | 1 | f |  1008577 |   681 |       5279
    1354927 | 2 | t |  1060956 | 14934 | 2000000000
    1354927 | 1 | f |  1060956 |   681 |      14934
    1354928 | 1 | f |   995917 |   681 | 2000000000
    1354929 | 1 | f |  1002626 |   681 | 2000000000
    1354930 | 1 | f |  1100148 |   681 | 2000000000
    1354932 | 2 | t |  1015696 |  4668 | 2000000000  <-- The one missing GIA
    1354932 | 1 | f |  1015696 |   681 |       4668  <-- The one missing GIA
    1357971 | 1 | f |  1357962 |  1968 | 2000000000
    1370880 | 1 | f |  1370876 |  4668 | 2000000000

It's funny, because there are other deleted links pointing at
deleted byway_segments that were imported properly into CcpV2.

   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, until, ityp
   FROM _gia WHERE stk_id IN (
      SELECT lhs FROM _lv
      WHERE stk_id IN (
         1354932,
         1355472,
         1377188,
         1408984,
         1355154,
         1362522,
         1407725,
         1395180,
         1356753,
         1398965,
         1373629,
         1468369,
         1469326,
         1483518))
      ORDER BY start, stk_id, v DESC;

    stk_id  | v | d |   nom    | a | g | start | until |    ityp    
   ---------+---+---+----------+---+---+-------+-------+------------
    1406085 | 1 | f | bikelane | 3 | 1 |   133 | inf   | tag
    1354009 | 1 | f |          | 3 | 1 |   453 | inf   | annotation
    1354916 | 1 | f |          | 3 | 1 |   681 | 7703  | annotation
    1355122 | 1 | f |          | 3 | 1 |   912 | 5188  | annotation
    1355471 | 1 | f |          | 3 | 1 |  1252 | 5676  | annotation
    1356758 | 1 | f |          | 3 | 1 |  1729 | inf   | annotation
    1408951 | 1 | f | closed   | 3 | 1 |  1818 | inf   | tag
    1364864 | 1 | f |          | 3 | 1 |  3442 | 4428  | annotation
    1364864 | 2 | f |          | 3 | 1 |  4428 | inf   | annotation
    1373576 | 1 | f |          | 3 | 1 |  4931 | 6759  | annotation
    1355122 | 2 | f |          | 3 | 1 |  5188 | inf   | annotation
    1377189 | 1 | f |          | 3 | 1 |  5512 | 5676  | annotation
    1355471 | 2 | t |          | 3 | 1 |  5676 | inf   | annotation
    1377189 | 2 | t |          | 3 | 1 |  5676 | inf   | annotation
    1397538 | 1 | f |          | 3 | 1 |  6577 | inf   | annotation
    1373576 | 2 | t |          | 3 | 1 |  6759 | 6760  | annotation
    1373576 | 3 | f |          | 3 | 1 |  6760 | inf   | annotation
    1409158 | 1 | f | hill     | 3 | 1 |  7568 | inf   | tag
    1354916 | 2 | f |          | 3 | 1 |  7703 | inf   | annotation

   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, until, ityp
   FROM _gia WHERE stk_id IN (
      SELECT rhs FROM _lv
      WHERE stk_id IN (
         1354932,
         1355472,
         1377188,
         1408984,
         1355154,
         1362522,
         1407725,
         1395180,
         1356753,
         1398965,
         1373629,
         1468369,
         1469326,
         1483518))
      ORDER BY start, stk_id, v DESC;

    stk_id  | v | d |      nom      | a | g | start | until | ityp  
   ---------+---+---+---------------+---+---+-------+-------+-------
    1015696 | 1 | f | Broadway St N | 3 | 1 |   133 | 4668  | byway
    1050685 | 1 | f | N Griggs St   | 3 | 1 |   133 | 1252  | byway
    1092891 | 1 | f | W Summit Ave  | 3 | 1 |   133 | 1585  | byway
    1104220 | 1 | f | Gramsie Rd    | 3 | 1 |   133 | 2207  | byway
    1138624 | 1 | f | Hardwood Cree | 3 | 1 |   142 | 6676  | byway
    1050685 | 2 | f | N Griggs St   | 3 | 1 |  1252 | 2900  | byway
    1092891 | 2 | f | W Summit Ave  | 3 | 1 |  1585 | 2610  | byway
    1104220 | 2 | f | Gramsie Rd    | 3 | 1 |  2207 | 10749 | byway
    1092891 | 3 | f | W Summit Ave  | 3 | 1 |  2610 | 5287  | byway
    1050685 | 3 | f | N Griggs St   | 3 | 1 |  2900 | 5512  | byway
    1371957 | 1 | f | Glenwood Ave  | 3 | 1 |  4757 | 10850 | byway
    1373622 | 1 | f |               | 3 | 1 |  4941 | 10519 | byway
    1092891 | 4 | f | W Summit Ave  | 3 | 1 |  5287 | 6235  | byway
    1050685 | 4 | f | N Griggs St   | 3 | 1 |  5512 | 5676  | byway
    1092891 | 6 | f | W Summit Ave  | 3 | 1 |  6245 | inf   | byway
    1395160 | 1 | f |               | 3 | 1 |  6275 | 6279  | byway
    1395160 | 2 | f |               | 3 | 1 |  6279 | 6280  | byway
    1398970 | 1 | f | W Como Ave    | 3 | 1 |  6794 | 7152  | byway
    1104220 | 3 | f | Gramsie Rd    | 3 | 1 | 10749 | 11309 | byway
    1483519 | 1 | f | Portland Ave  | 3 | 1 | 11563 | 11754 | byway
    1483519 | 3 | f | Portland Ave  | 3 | 1 | 11755 | inf   | byway
    1092891 | 7 | t | W Summit Ave  | 3 | 1 | 22303 | inf   | byway

Again, same solution: purge 'em all!

*/

SELECT link_value_delete_orphans(1354932);
SELECT link_value_delete_orphans(1355472);
SELECT link_value_delete_orphans(1377188);
SELECT link_value_delete_orphans(1408984);
SELECT link_value_delete_orphans(1355154);
SELECT link_value_delete_orphans(1362522);
SELECT link_value_delete_orphans(1407725);
SELECT link_value_delete_orphans(1395180);
SELECT link_value_delete_orphans(1356753);
SELECT link_value_delete_orphans(1398965);
SELECT link_value_delete_orphans(1373629);
SELECT link_value_delete_orphans(1468369);
SELECT link_value_delete_orphans(1469326);
SELECT link_value_delete_orphans(1483518);

DROP FUNCTION link_value_delete_orphans(lval_stk_id INTEGER);

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Item_Revisionless: Create it
\qecho

/* I [lb] created group_item_access's date_created and created
   a while ago, to mimic what was in the route table, but the
   implementation isn't quite right: besides missing the host
   column (since, e.g., when created_by is _user_anon_minnesota,
   that's not very helpful, and having an I.P. might be more so),
   we're also duplicating data for how many ever records share
   the same system_id and acl_grouping, which we can consolidate
   in a single row and in a new table.

   See also convenience_views.sql, since we've devving
   before checking'ing'ing, so you might see some views
   being dropped that you've never heard of before. */

DROP VIEW IF EXISTS _ir;
DROP VIEW IF EXISTS _ir2;
DROP VIEW IF EXISTS _rt;
DROP VIEW IF EXISTS _rt1;
DROP VIEW IF EXISTS _rt2;
DROP VIEW IF EXISTS _tr;
DROP TABLE IF EXISTS item_revisionless;
CREATE TABLE item_revisionless (
   /* Primary keys. */
   system_id INTEGER NOT NULL,
   acl_grouping INTEGER NOT NULL,
   /* Repetita juvant. */
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* Item_Revisionlessy attributes. */
   edited_date TIMESTAMP WITH TIME ZONE, -- NOT NULL,
   edited_user TEXT, -- NOT NULL,
   edited_note TEXT,
   edited_addr INET,
   edited_host TEXT,
   edited_what TEXT -- like ye olde route.source
   /* This column in a compromise, to make it easy to
      determine at when time, revision, and by whom an
      item was created. Without this, we'd have to join
      item_versioned on stack_id at version=1 and then
      join revision; an alternative would be to store
      the creator_name and created_date in every
      item_revisionless row, but that seems redundant
      and wasteful. So this is a compromise: store the
      revision ID of the first item version. */
   -- On second thought... we can get away without it...
   --, first_start_rid INTEGER NOT NULL
);

ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_pkey
   PRIMARY KEY (system_id, acl_grouping);

/* We'll wait to create the table constraints
   until after populating the table. */

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Item_Revisionless: Populate it
\qecho

/* NOTE: Some items are valid_start_rid = 1
          like Stk Id 4082240 (a merge_export_job: see nonwiki_item),
         so revision's creator name and created time and pretty
         meaningless for these items. We get this data from elsewhere
         instead, when available. */

/* NOTE: Instead of the multiple CASE WHEN ... IS NOT NULL, we could
         have used COALESCE. The CASEs just seem easier to read. */

/*

This is just CxPx DEV code if you've run this script beforev
and want to remake and repopulate the item_revisionless table.

-- Reset changes from below:
ALTER TABLE item_stack RENAME COLUMN creator_name_TBD TO creator_name;
ALTER TABLE group_item_access RENAME COLUMN created_by_TBD TO created_by;
ALTER TABLE group_item_access RENAME date_created_TBD TO date_created;
ALTER TABLE route RENAME COLUMN host_TBD TO host;
ALTER TABLE route RENAME COLUMN created_TBD TO created;
ALTER TABLE route RENAME COLUMN source_TBD TO source;
ALTER TABLE revision RENAME COLUMN permission_TBD TO permission;
ALTER TABLE revision RENAME COLUMN visibility_TBD TO visibility;
ALTER TABLE track RENAME COLUMN permission_TBD TO permission;
ALTER TABLE track RENAME COLUMN visibility_TBD TO visibility;
ALTER TABLE track RENAME COLUMN source_TBD TO source;
DROP TRIGGER track_ic ON track;
ALTER TABLE track RENAME COLUMN created_TBD TO created;
ALTER TABLE track RENAME COLUMN host_TBD TO host;

-- Re-apply changes from below:
ALTER TABLE item_stack RENAME COLUMN creator_name TO creator_name_TBD;
ALTER TABLE group_item_access RENAME COLUMN created_by TO created_by_TBD;
ALTER TABLE group_item_access RENAME date_created TO date_created_TBD;
ALTER TABLE route RENAME COLUMN host TO host_TBD;
ALTER TABLE route RENAME COLUMN created TO created_TBD;
ALTER TABLE route RENAME COLUMN source TO source_TBD;
ALTER TABLE revision RENAME COLUMN permission TO permission_TBD;
ALTER TABLE revision RENAME COLUMN visibility TO visibility_TBD;
ALTER TABLE track RENAME COLUMN permission TO permission_TBD;
ALTER TABLE track RENAME COLUMN visibility TO visibility_TBD;
ALTER TABLE track RENAME COLUMN source TO source_TBD;
DROP TRIGGER track_ic ON track;
ALTER TABLE track RENAME COLUMN created TO created_TBD;
ALTER TABLE track RENAME COLUMN host TO host_TBD;
*/

\qecho Creating helper fcns.

/* The route.host and track.host are NULL or a real IP, whereas
   revision.host is a hostname or an IP or a script identifier. */

CREATE FUNCTION cp_revision_get_hostname(rid INTEGER)
   RETURNS TEXT AS $$
   DECLARE
      hostname TEXT;
   BEGIN
      BEGIN
         hostname := rev.host::INET FROM revision AS rev WHERE id = rid;
         /* This means the hostname is a valid IP, so Null it. */
         hostname := NULL;
      EXCEPTION WHEN OTHERS THEN
         /* The string is not a valid IP, so it's either a hostname
            or a special internal name that some script used. */
         hostname := rev.host FROM revision AS rev WHERE id = rid;
      END;
      RETURN hostname;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION cp_revision_get_ipaddress(rid INTEGER)
   RETURNS INET AS $$
   DECLARE
      hostname TEXT;
   BEGIN
      BEGIN
         hostname := rev.host::INET FROM revision AS rev WHERE id = rid;
         /* This means the hostname is a valid IP. */
      EXCEPTION WHEN OTHERS THEN
         /* Not a valid ID, so return NULL. */
         hostname := NULL;
      END;
      RETURN hostname;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* Test:
SELECT cp_revision_get_hostname(22363);
SELECT cp_revision_get_hostname(22338);
SELECT cp_revision_get_ipaddress(22363);
SELECT cp_revision_get_ipaddress(22338);
*/

--DROP FUNCTION cp_revision_get_hostname(rid INTEGER);
--DROP FUNCTION cp_revision_get_ipaddress(rid INTEGER);

\qecho INSERT INTO item_revisionless... ~45 seconds...

INSERT INTO item_revisionless
   (system_id, acl_grouping, branch_id, stack_id, version,
    edited_date, edited_user, edited_note,
    edited_addr, edited_host, edited_what
    --, first_start_rid
    )
   SELECT
      gia.item_id,
      gia.acl_grouping,
      gia.branch_id,
      gia.stack_id,
      gia.version,
      CASE WHEN gia.item_type_id = 42 -- 'merge_export_job'
                THEN (SELECT wst.last_modified FROM work_item_step AS wst
                       WHERE (wst.work_item_id = gia.item_id)
                         AND (wst.step_number = 1))
           WHEN gia.date_created IS NOT NULL THEN gia.date_created
           WHEN rt.created       IS NOT NULL THEN rt.created
           WHEN tr.created       IS NOT NULL THEN tr.created
           --WHEN rev.timestamp    IS NOT NULL THEN rev.timestamp
           WHEN gia.item_type_id =  8 THEN rev.timestamp -- 'post'
           WHEN gia.item_type_id = 13 THEN rev.timestamp -- 'thread'
           ELSE NULL -- Doesn't hit (or triggers constraint)
         END AS edited_date,
      CASE WHEN gia.item_type_id = 42 -- 'merge_export_job'
                THEN (SELECT wrk.created_by FROM work_item AS wrk
                       WHERE wrk.system_id = gia.item_id)
           WHEN (gia.created_by  IS NOT NULL
             -- HA! Here's a bug not found: 'NULL' the string, not the value.
             AND gia.created_by  != 'NULL')  THEN gia.created_by
           --WHEN rev.username   IS NOT NULL THEN rev.username
           WHEN gia.item_type_id =  8 THEN rev.username -- 'post'
           WHEN gia.item_type_id = 13 THEN rev.username -- 'thread'
           ELSE '_user_anon_@@@instance@@@'
         END AS edited_user,
      CASE WHEN ((gia.item_type_id = 10) -- 'route'
                 AND (rev.id <= 21988)) -- last minnesota revision before CcpV2
                -- Use the revision's comment, which is valid for old routes
                -- (until we started revisionlessing them; and note that the
                -- old route comments include generated strings, i.e., not all
                -- comments were written by the actual user).
                THEN rev.comment
           WHEN tr.comments IS NOT NULL THEN tr.comments
           ELSE NULL -- This is a revisioned item, which can join revision and
                     -- use its comment -- we don't need to duplicate the same
                     -- comment for 100000s of items. (This might also be a
                     -- work_item-type item (like merge_export_job), for which
                     -- there is no valid changenote.)
         END AS edited_note,
      CASE WHEN rt.host IS NOT NULL THEN rt.host::INET
           WHEN tr.host IS NOT NULL THEN tr.host::INET
           WHEN gia.item_type_id IN (8, 13) -- 'post', 'thread':
                 THEN cp_revision_get_ipaddress(rev.id)
           ELSE NULL
         END AS edited_addr,
      -- NOTE: We weren't capturing host for acl_grouping > 1:
           -- WHEN gia.acl_grouping = 1
           --   THEN COALESCE(rt.host::TEXT,
           --                 tr.host::TEXT,
           --                 rev.host)
      CASE WHEN rt.host IS NOT NULL THEN NULL -- Not a hostname: rt.host
           WHEN tr.host IS NOT NULL THEN NULL -- Not a hostname: tr.host
           WHEN gia.item_type_id IN (8, 13) -- 'post', 'thread':
                 THEN cp_revision_get_hostname(rev.id)
           ELSE NULL
         END AS edited_host,
      -- Note that track.source is unused:
      rt.source AS edited_what
      --, first_iv.valid_start_rid AS first_start_rid
   FROM (
      SELECT
         DISTINCT ON (gia.item_id, gia.acl_grouping)
         gia.item_id,
         gia.acl_grouping,
         gia.branch_id,
         gia.stack_id,
         gia.version,
         gia.valid_start_rid,
         gia.item_type_id,
         gia.date_created,
         gia.created_by
      FROM group_item_access AS gia
      GROUP BY
         gia.item_id,
         gia.acl_grouping,
         gia.branch_id,
         gia.stack_id,
         gia.version,
         gia.valid_start_rid,
         gia.item_type_id,
         gia.date_created,
         gia.created_by
   ) AS gia
   LEFT OUTER JOIN revision AS rev
      ON (rev.id = gia.valid_start_rid)
   LEFT OUTER JOIN route AS rt
      ON (rt.system_id = gia.item_id)
   LEFT OUTER JOIN track AS tr
      ON (tr.system_id = gia.item_id)
   --LEFT OUTER JOIN item_versioned AS first_iv
   --   ON (first_iv.stack_id = gia.stack_id
   --       AND first_iv.version = 1)
   ;
/*
INSERT 0 2425388
Time: 40650.528 ms
*/

/*

-------------------------------------------------------------------------------
BUG nnnn/WHO_CARES: Orphaned Item_Versioned Rows.
-------------------------------------------------------------------------------

Since we just populated item_revisionless, you'd think
that inner joining item_versioned and item_revisionless
would always work, but there are a number of item_versioned
rows without group_item_access rows, and some item_versioned
rows without even rows in another item table.

Currently, there are two types of item_versioned rows without
item_revisionless records: node_endpoint rows (for which not
having an item_revisionless row is completely fine, since
they don't waste time/space even with group_item_access rows),
and also other rows that are orphaned (i.e., I can't find
any reference to the item from any other table).

E.g., consider item_versioned orphans that we know for sure
are not node_endpoints:

   SELECT COUNT(*) FROM item_versioned AS iv
      LEFT OUTER JOIN node_endpoint USING (system_id)
      WHERE node_endpoint.system_id IS NULL
        AND NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
     count
   ---------
     258749 without nodes

For reference,

   SELECT COUNT(*) FROM item_versioned AS iv
      LEFT OUTER JOIN node_endpoint USING (system_id)
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
     count
   ---------
     752365    with nodes (493616 + 258749)

If we exclude other tables witch stack IDs without GIA records,
we can decreast the count further, and we also exclude the
MetC branch here because it's got two item_versioned rows
for each node_endpoint (one for each branch), but only the
basemap branch has a row in node_endpoint (and hopefully
the node_cache_maker script will fix this problem).

   -- SELECT * FROM item_versioned AS iv
   SELECT COUNT(*) FROM item_versioned AS iv
      LEFT OUTER JOIN geofeature
         ON (iv.system_id = geofeature.system_id)
      LEFT OUTER JOIN group_
         ON (iv.system_id = group_.system_id)
      LEFT OUTER JOIN group_membership
         ON (iv.system_id = group_membership.system_id)
      LEFT OUTER JOIN new_item_policy
         ON (iv.system_id = new_item_policy.system_id)
      LEFT OUTER JOIN track
         ON (iv.system_id = track.system_id)
      LEFT OUTER JOIN node_endpoint
         ON (iv.system_id = node_endpoint.system_id)
      LEFT OUTER JOIN node_traverse
         ON (iv.system_id = node_traverse.system_id)
      WHERE iv.deleted IS FALSE
        AND geofeature.system_id IS NULL
        AND group_.system_id IS NULL
        AND group_membership.system_id IS NULL
        AND new_item_policy.system_id IS NULL
        AND track.system_id IS NULL
        AND ((node_endpoint.system_id IS NULL)
             -- Comment this out for the 'all branches' count:
             AND (iv.branch_id != 2538452)
             )
        AND node_traverse.system_id IS NULL
        AND NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);

    count  
   --------
    238463 all branches
      2975 ignoring missing node_endpoints in metc branch

So, the bulk of the problem records should/will hopefully
be fixed the next time we run the node_cache_maker.py script,
but there are still not quite three thousand or so truly
orphaned item_versioned rows.

I think some of the item_versioned rows without rows anywhere else -- not in
item_stack, nor in group_item_access, nor in any of the item tables -- are
abandoned node_endpoint items. Curiously, the items start at rid 1 (so there is
not even a revision breadcrumb), and there are two items, one for each branch,
in item_versioned. Hopefully, this was a bug in node_endpoint, emphasis: was.

-------------------------------------------------------------------------------
BUG nnnn: Orphaned Item_Versioned Rows: No node_endpoint rows for leafy branch.
-------------------------------------------------------------------------------

   SELECT stack_id, version AS v, deleted AS d, name,
          valid_start_rid AS start, valid_until_rid AS until
   FROM item_versioned WHERE stack_id = 2878787;

    stack_id | v | d | name | start |   until    
   ----------+---+---+------+-------+------------
     2878787 | 1 | f |      |     1 | 2000000000
     2878787 | 1 | f |      |     1 | 2000000000

-------------------------------------------------------------------------------
BUG nnnn: Orphaned Item_Versioned Rows: Missing deleted items item rows.
-------------------------------------------------------------------------------

Here's an example of a byway marked deleted whose deleted version does not
have a row in the descendant item table.

   SELECT COUNT(*) FROM item_versioned AS iv
      LEFT OUTER JOIN geofeature gf ON (iv.system_id = gf.system_id)
      WHERE gf.system_id IS NULL
        AND iv.deleted IS TRUE
        AND NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
    count 
   -------
      171

   SELECT * FROM _iv WHERE stk_id = 1138624;
   stk_id  | v | d | r |         nom          | start | until | a | nfr  
   --------+---+---+---+----------------------+-------+-------+---+------
   1138624 | 2 | t | f | Hardwood Creek Trail |  6676 | inf   | 8 | 0x20
   1138624 | 1 | f | f | Hardwood Creek Trail |   142 | 6676  | 8 | 0x20
   (2 rows)

   SELECT stk_id, v, d, r, nom, start, until FROM _by WHERE stk_id = 1138624;
    stk_id  | v | d | r |         nom          | start | until 
   ---------+---+---+---+----------------------+-------+-------
    1138624 | 1 | f | f | Hardwood Creek Trail |   142 | 6676
   (1 row)

I don't think it's worth our time to worry about this old data... it would
only matter for viewing historic revisions and for reverting....

-------------------------------------------------------------------------------
BUG nnnn: Orphaned Item_Versioned Rows: Missing watch_region geometry.
                                        Because original geometry is invalid!
-------------------------------------------------------------------------------

Here's an orphan item_version record that's a private user region,
from a CcpV1 watch_region.

   SELECT * FROM _iv WHERE stk_id = 1418167;
   stk_id  | v | d | r |       nom        | start | until | a | nfr 
   --------+---+---+---+------------------+-------+-------+---+-----
   1418167 | 1 | f | f | New Watch Region | 22043 | inf   | 9 | 0x0
   (1 row)

   SELECT stk_id, v, d, r, nom, start, until FROM _rg WHERE stk_id = 1418167;
    stk_id | v | d | r | nom | start | until 
   --------+---+---+---+-----+-------+-------
   (0 rows)

See them all in CcpV1 database:

   SELECT id, version AS v, deleted AS d, name, username AS unom,
          notify_email AS notif, type_code AS tcod,
          valid_starting_rid AS start, valid_before_rid AS until,
          SUBSTRING(comments FOR 13) AS comments FROM watch_region;

See just mine in CcpV1 database:

   SELECT id, version AS v, deleted AS d, name, username AS unom,
          notify_email AS notif, type_code AS tcod,
          valid_starting_rid AS start, valid_before_rid AS until,
          SUBSTRING(comments FOR 13) AS comments FROM watch_region
          WHERE username = 'landonb';

   id    | v |    name    | notif | tcod | start |   until    |   comments    
---------+---+------------+-------+------+-------+------------+---------------
 1489315 | 0 | Home       | t     |    2 |     0 | 2000000000 | 
 1489274 | 0 | McRae Park | t     |    2 |     0 | 2000000000 | This is a tes

See just mine in CcpV2 database:

   SELECT stk_id, v, d, r, nom, start, until, a, nfr
   FROM _rg WHERE stk_id IN (1489274, 1489315);

    stk_id  | v | d | r |    nom     | start | until | a | nfr 
   ---------+---+---+---+------------+-------+-------+---+-----
    1489274 | 1 | f | f | McRae Park | 22080 | inf   | 7 | 0x2
    1489315 | 1 | f | f | Home       | 22080 | inf   | 7 | 0x2

So my watch regions were upgrade okay, but not all users' were.

   SELECT id, version AS v, deleted AS d, name, username AS unom,
          notify_email AS notif, type_code AS tcod,
          valid_starting_rid AS start, valid_before_rid AS until,
          SUBSTRING(comments FOR 13) AS comments FROM watch_region
          WHERE id = 1418167;

   id    | v | d |       name       | notif | tcod | start | until | comments 
---------+---+---+------------------+-------+------+-------+-------+----------
 1418167 | 0 | f | New Watch Region | t     |    2 |     0 |   inf | 

And then you realize that the geometry is borked.

   SELECT ST_IsValid(geometry) FROM watch_region WHERE id = 1418167;

   NOTICE:  Self-intersection at or near point
            469251.48935933033 4971257.5999999996
    st_isvalid 
   ------------
    f

SOLUTIONs: Just leave the cruft and ignore it, delete the cruft, or repair
           the bad geometry. The latterest option seems silly. The second
           option would require writing SQL to find rows in item_versioned
           that don't have a referenece from anywhere else, and also being
           confident we've identified an orphan, and then deleting it.
           So the safest and simplest option seems like the first option,
           to just ignore the cruft... and hopefully we'll remember in the
           future when we find this cruft that we should pay it no mind.

-------------------------------------------------------------------------------
BUG nnnn: Orphaned Item_Versioned Rows: Other, Unclassified Bug!
-------------------------------------------------------------------------------

Here is an item missing a GIA record because the item is... what now?
This might very well still be a bug! What you see is an orphaned
item_versioned row without any other references to the stack_id.
This might be cruft we can ignore, or it might have been a new
item that the user created that we failed to save properly.

   SELECT stack_id, version v, deleted d,
          valid_start_rid AS start, valid_until_rid AS until
   FROM item_versioned WHERE stack_id = 1599214;

    stack_id | v | d | start |   until    
   ----------+---+---+-------+------------
     1599214 | 1 | f |     1 |      22278
     1599214 | 2 | f | 22278 | 2000000000

   SELECT COUNT(*) FROM _gia WHERE stk_id = 1599214;
    count 
   -------
        0

   SELECT id, tstamp, unom, comment FROM _rev WHERE id = 22278;

     id   |      tstamp      |   unom    |            comment             
   -------+------------------+-----------+--------------------------------
    22278 | 2013-10-07 18:48 | neverlost | fixed road that did not really exist


   SELECT stk_id, v, d, SUBSTRING(nom FOR 13) AS nom, a, g, start, until, ityp
   FROM _gia WHERE start = 22278 OR until = '22278';

    stk_id  | v | d | nom | a | g | start | until | ityp  
   ---------+---+---+-----+---+---+-------+-------+-------
    1599212 | 3 | f |     | 3 | 1 | 22278 | inf   | byway
    1599212 | 2 | f |     | 3 | 1 | 21940 | 22278 | byway


   SELECT stk_id, v, d, r, nom, start, until, len FROM _by
   WHERE stk_id = 1599212;

    stk_id  | v | d | r | nom | start | until |  len  
   ---------+---+---+---+-----+-------+-------+-------
    1599212 | 3 | f | f |     | 22278 | inf   | 16.3
    1599212 | 2 | f | f |     | 21940 | 22278 | 154.9
    1599212 | 1 | f | f |     | 21939 | 21940 | 153.6

So a road was edited and that worked, but there is cruft in item_versioned.
Also, there is no item_stack record for 1599214, probably not surprisingly.

-------------------------------------------------------------------------------
Finally. Just Checking.
-------------------------------------------------------------------------------

Count items by type missing GIA records when we populated item_revisionless.

   SELECT COUNT(*) FROM attachment AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM link_value AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM work_item AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM merge_job AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM route AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM track AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM geofeature AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.system_id);
   SELECT COUNT(*) FROM _rg AS iv -- 0
      WHERE NOT EXISTS(SELECT 1 FROM item_revisionless AS ir
                               WHERE ir.system_id = iv.sys_id);
   -- Etc...

-------------------------------------------------------------------------------
Reference: These are CcpV1 tables that have an id column with a stack ID, for
           trying to find what type of item to which a stack ID belongs.
-------------------------------------------------------------------------------

SELECT COUNT(*) FROM annot_bs WHERE id = 1599214;
SELECT COUNT(*) FROM annotation WHERE id = 1599214;
SELECT COUNT(*) FROM basemap_polygon WHERE id = 1599214;
SELECT COUNT(*) FROM byway_name_cache WHERE id = 1599214;
SELECT COUNT(*) FROM byway_segment WHERE id = 1599214;
SELECT COUNT(*) FROM c_trial_small WHERE id = 1599214;
SELECT COUNT(*) FROM c_viewport WHERE id = 1599214;
SELECT COUNT(*) FROM point WHERE id = 1599214;
SELECT COUNT(*) FROM post WHERE id = 1599214;
SELECT COUNT(*) FROM post_bs WHERE id = 1599214;
SELECT COUNT(*) FROM post_point WHERE id = 1599214;
SELECT COUNT(*) FROM post_region WHERE id = 1599214;
SELECT COUNT(*) FROM post_revision WHERE id = 1599214;
SELECT COUNT(*) FROM post_route WHERE id = 1599214;
SELECT COUNT(*) FROM reaction_reminder WHERE id = 1599214;
SELECT COUNT(*) FROM region WHERE id = 1599214;
SELECT COUNT(*) FROM revert_event WHERE id = 1599214;
SELECT COUNT(*) FROM revision WHERE id = 1599214;
SELECT COUNT(*) FROM revision_feedback WHERE id = 1599214;
SELECT COUNT(*) FROM route WHERE id = 1599214;
SELECT COUNT(*) FROM route_feedback WHERE id = 1599214;
SELECT COUNT(*) FROM route_feedback_drag WHERE id = 1599214;
SELECT COUNT(*) FROM route_feedback_stretch WHERE id = 1599214;
SELECT COUNT(*) FROM rp_region_sequence WHERE id = 1599214;
SELECT COUNT(*) FROM tag WHERE id = 1599214;
SELECT COUNT(*) FROM tag_bs WHERE id = 1599214;
SELECT COUNT(*) FROM tag_point WHERE id = 1599214;
SELECT COUNT(*) FROM tag_region WHERE id = 1599214;
SELECT COUNT(*) FROM thread WHERE id = 1599214;
SELECT COUNT(*) FROM thread_read_event WHERE id = 1599214;
SELECT COUNT(*) FROM track WHERE id = 1599214;
SELECT COUNT(*) FROM track_point WHERE id = 1599214;
SELECT COUNT(*) FROM watch_region WHERE id = 1599214;
SELECT COUNT(*) FROM work_hint WHERE id = 1599214;

*/

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Item_Revisionless: Constrain it
\qecho

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

/* [lb] thought about storing the first item version's revision ID in
item_revisionless, to make it easy to join on revision to find the
creator's deets, but we can just as easily join join on item_versioned
where v=1 and then revision...

\qecho ...item_revisionless_first_start_rid_fkey
SELECT cp_constraint_drop_safe('item_revisionless',
                               'item_revisionless_first_start_rid_fkey');
ALTER TABLE item_revisionless
   ADD CONSTRAINT item_revisionless_first_start_rid_fkey
   FOREIGN KEY (first_start_rid) REFERENCES revision (id) DEFERRABLE;
*/

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

/* */

/*
\qecho ...enforce_first_start_rid
SELECT cp_constraint_drop_safe('item_versioned', 'enforce_first_start_rid');
ALTER TABLE item_revisionless
   ADD CONSTRAINT enforce_first_start_rid CHECK (first_start_rid >= 0);
*/

/* */

DROP TRIGGER IF EXISTS item_revisionless_edited_date_i ON item_revisionless;
/* We don't setup a trigger for the edited_date, since most item types
   can just key off revision.timestamp.
CREATE OR REPLACE FUNCTION public.cp_set_edited_date()
   RETURNS TRIGGER AS $cp_set_edited_date$
      BEGIN
         IF NEW.edited_date IS NULL THEN
            NEW.edited_date = now();
         END IF;
         RETURN NEW;
      END
   $cp_set_edited_date$ LANGUAGE 'plpgsql';
CREATE TRIGGER item_revisionless_edited_date_i BEFORE INSERT
   ON item_revisionless
   FOR EACH ROW EXECUTE PROCEDURE cp_set_edited_date();
*/

/* */

CREATE FUNCTION cp_alter_table_item_revisionless()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

      /* FIXME: TBD: To Be Deleted: Drop these columns. Eventually. */
      DROP VIEW IF EXISTS _gia;
      ALTER TABLE group_item_access RENAME COLUMN created_by TO created_by_TBD;
      ALTER TABLE group_item_access RENAME date_created TO date_created_TBD;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table item_revisionless already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_item_revisionless();

DROP FUNCTION cp_alter_table_item_revisionless();

/* */

CREATE FUNCTION cp_alter_table_item_stack()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

      ALTER TABLE item_stack RENAME COLUMN creator_name TO creator_name_TBD;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table item_stack already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_item_stack();

DROP FUNCTION cp_alter_table_item_stack();

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route
\qecho

CREATE FUNCTION cp_alter_table_route()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         /* The session_id was long, long ago moved to group_item_access. */
         DROP VIEW IF EXISTS _rt;
         ALTER TABLE route DROP COLUMN session_id;

         /* We subsumed these in item_revisionless. */
         /* FIXME: TBD: To Be Deleted: Drop these columns. Later. */
         ALTER TABLE route RENAME COLUMN host TO host_TBD;
         ALTER TABLE route RENAME COLUMN created TO created_TBD;
         ALTER TABLE route RENAME COLUMN source TO source_TBD;

         ALTER TABLE route ALTER COLUMN created_tbd DROP NOT NULL;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table route already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_route();

DROP FUNCTION cp_alter_table_route();

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route_Parameters: Missing rows
\qecho

/*
   -- 2014.05.15: Do we care? The route_parameters table derived from the old
   --             route_priority table, so that table must've not had at least
   --             one row for every route.
   --
   --     COUNT(*) FROM route_parameters        : 126,774
   --     COUNT(*) FROM route WHERE version = 1 : 138,470

   Here we add 11,696 records, + 126,774 = 138,470.

 */

INSERT INTO route_parameters
   (branch_id,
    route_stack_id,
    p1_priority
    -- Leave these empty and use the table defaults:
    --  travel_mode
    --  tags_use_defaults
    --  p2_transit_pref
    --  p2_depart_at
    --  p3_weight_attr
    --  p3_weight_type
    --  p3_rating_pump
    --  p3_burden_pump
    --  p3_spalgorithm
    )
   SELECT
      rt.branch_id,
      rt.stack_id,
      0.5
   FROM route AS rt
   WHERE rt.version = 1
     AND NOT EXISTS (SELECT 1 FROM route_parameters AS rtp
                      WHERE rtp.route_stack_id = rt.stack_id)
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route: Comments on Ignoring Edits During Upgrade Months
\qecho

/*

MAYBE/PROBABLY NOT: Import CcpV1 ROUTES from Sep 2013 to April/May
                    (the period during which the old server was still
                     active while the new server was also active, and
                     the old server had a note saying no changes made
                     would be retained).

   ccpv1_live=> SELECT COUNT(*) FROM route WHERE created >= '2013-09-04';
    count 
   -------
     3357

Find the last route we copied from CcpV1.

   SELECT id FROM route WHERE created > '2013-09-03'
                          AND created < '2013-09-05' order by id;

Reveals 1599477 is the last old route.

But it looks like some routes were probably edited?

   ccpv1_live=> SELECT COUNT(*) FROM route WHERE id > 1599477;
    count 
   -------
     2961

   ccpv1_live=> SELECT id FROM route WHERE created >= '2013-09-04'
                ORDER BY id;

1569893 was edited a ton, and 1575666 once, and 1580403, 1584336,
1590347, and then 1593749 a ton, then 1599468, 1599469,
1599470, 1599471, 1599472, 1599473, 1599474, 1599475, 1599476, 1599477.
A lot of the edits look like auto-saves... so forget 'em all! Is my
recommendation.

*/

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Route_Parameters: An Unrelated Matter
\qecho

/* Just saving a little whitespace (width) for the _rt view.
   All the others are 9 or 10 chars long (e.g., wgt_fac_85). */
UPDATE route_parameters SET p3_weight_attr = 'wgt_pers_f'
                      WHERE p3_weight_attr = 'wgt_personalized_f';

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Revision: Rename deprecated columns
\qecho

CREATE FUNCTION cp_alter_table_revision()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         /* FIXME: TBD: To Be Deleted: Drop these columns. Some day. */
         ALTER TABLE revision RENAME COLUMN permission TO permission_TBD;
         ALTER TABLE revision RENAME COLUMN visibility TO visibility_TBD;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table revision already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_revision();

DROP FUNCTION cp_alter_table_revision();

/* */

CREATE FUNCTION cp_alter_table_track()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         /* FIXME: TBD: To Be Deleted: Drop these columns. Some day. */
         ALTER TABLE track RENAME COLUMN permission TO permission_TBD;
         ALTER TABLE track RENAME COLUMN visibility TO visibility_TBD;

         /* The source column is not used by track.
               ccpv3_lite=> select distinct(source) from track;
                source 
               --------
                
               (1 row)
         */
         ALTER TABLE track RENAME COLUMN source TO source_TBD;

         /* The created and host values can now be found in item_revisionless.
            Just be sure to join on acl_grouping = 1, unless you're coming
            from item_user_access, and then you can use whatever acl_grouping
            that item_user_access indicates.
             
             See also:

               SELECT * FROM _tr;
             
         */
         DROP TRIGGER track_ic ON track;
         ALTER TABLE track RENAME COLUMN created TO created_TBD;
         ALTER TABLE track RENAME COLUMN host TO host_TBD;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table track already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_track();

DROP FUNCTION cp_alter_table_track();

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho route table: drop deprecated column trigger
\qecho

DROP TRIGGER IF EXISTS route_ic ON route;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

\qecho Committing... ~11 minutes...

--ROLLBACK;
COMMIT;

