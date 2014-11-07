/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho Move non-changing route version=1 rows to new table.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Renaming p1 planner''s route_priorities to be p2 and p3 inclusive.
\qecho

ALTER TABLE @@@instance@@@.route_priority RENAME TO route_parameters;

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Adding p2 and p3 planner options from route table to parameters table.
\qecho

ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN travel_mode SMALLINT
   DEFAULT 0;

/* p1 Planner options. */
ALTER TABLE @@@instance@@@.route_parameters
   ADD COLUMN tags_use_defaults BOOLEAN DEFAULT FALSE;
/* Might as well rename things while we're at it... */
ALTER TABLE @@@instance@@@.route_parameters
   RENAME COLUMN priority TO p1_priority;
ALTER TABLE @@@instance@@@.route_parameters
   RENAME COLUMN value TO p1_value;

/* p2 Planner options. */
/* Please be kind, rename. */
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p2_transit_pref SMALLINT
   DEFAULT 0;
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p2_depart_at TEXT
   DEFAULT '';

/* p3 Planner options. */
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p3_weight_attr TEXT
   DEFAULT '';
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p3_weight_type TEXT
   DEFAULT '';
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p3_rating_pump INTEGER
   DEFAULT 0;
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p3_burden_pump INTEGER
   DEFAULT 0;
ALTER TABLE @@@instance@@@.route_parameters ADD COLUMN p3_spalgorithm TEXT
   DEFAULT '';

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Copying data to the new columns.
\qecho

UPDATE @@@instance@@@.route_parameters AS rp
   SET travel_mode = (SELECT travel_mode FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);

/* p1 Planner options. */
UPDATE @@@instance@@@.route_parameters AS rp
   SET tags_use_defaults = (SELECT COALESCE(use_defaults, FALSE) FROM route
                            WHERE route.stack_id = rp.route_stack_id
                              AND route.version = 1
                              -- Note that the branch_id isn't needed, since
                              -- routes cannot be saved across branches... yet?
                              -- Not needed: AND route.branch_id = rp.branch_id
                           );

/* p2 Planner options. */
UPDATE @@@instance@@@.route_parameters AS rp
   SET p2_transit_pref = (SELECT COALESCE(transit_pref, 0) FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);
UPDATE @@@instance@@@.route_parameters AS rp
   SET p2_depart_at = (SELECT COALESCE(depart_at, '') FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);

/* p3 Planner options. */
UPDATE @@@instance@@@.route_parameters AS rp
   SET p3_weight_attr = (SELECT COALESCE(p3_weight_attr, '') FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);
UPDATE @@@instance@@@.route_parameters AS rp
   SET p3_weight_type = (SELECT COALESCE(p3_weight_type, '') FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);
UPDATE @@@instance@@@.route_parameters AS rp
   SET p3_rating_pump = (SELECT COALESCE(p3_rating_pump, 0) FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);
UPDATE @@@instance@@@.route_parameters AS rp
   SET p3_burden_pump = (SELECT COALESCE(p3_burden_pump, 0) FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);
UPDATE @@@instance@@@.route_parameters AS rp
   SET p3_spalgorithm = (SELECT COALESCE(p3_spalgorithm, '') FROM route
      WHERE route.stack_id = rp.route_stack_id AND route.version = 1);

/* ==================================================================== */
/* Step (4)                                                             */
/* ==================================================================== */

\qecho
\qecho Setting up constraints.
\qecho

ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN travel_mode
   SET NOT NULL;

/* p1 Planner options. */
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN tags_use_defaults
   SET NOT NULL;

/* p2 Planner options. */
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p2_transit_pref
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p2_depart_at
   SET NOT NULL;

/* p3 Planner options. */
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p3_weight_attr
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p3_weight_type
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p3_rating_pump
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p3_burden_pump
   SET NOT NULL;
ALTER TABLE @@@instance@@@.route_parameters ALTER COLUMN p3_spalgorithm
   SET NOT NULL;

/* ==================================================================== */
/* Step (5)                                                             */
/* ==================================================================== */

\qecho
\qecho Dropping moved columns.
\qecho

-- Drop dependent table(s).
DROP VIEW IF EXISTS _rt;
/* DEVs: Rebuild the view with:
   psql -U cycling ccpv3_lite < /ccp/dev/cp/scripts/dev/convenience_views.sql
    */

/* MAYBE: Drop route.travel_mode? Or is it nice to not have to join? */
ALTER TABLE @@@instance@@@.route DROP COLUMN use_defaults;
ALTER TABLE @@@instance@@@.route DROP COLUMN transit_pref;
ALTER TABLE @@@instance@@@.route DROP COLUMN depart_at;
ALTER TABLE @@@instance@@@.route DROP COLUMN p3_weight_attr;
ALTER TABLE @@@instance@@@.route DROP COLUMN p3_weight_type;
ALTER TABLE @@@instance@@@.route DROP COLUMN p3_rating_pump;
ALTER TABLE @@@instance@@@.route DROP COLUMN p3_burden_pump;
ALTER TABLE @@@instance@@@.route DROP COLUMN p3_spalgorithm;

/* ==================================================================== */
/* Step (6)                                                             */
/* ==================================================================== */

\qecho
\qecho Removing obsolete columns.
\qecho

/* The cloned_from_id is superceeded by item_stack's column of the same
   name (although the latter uses the system_id, where route.cloned_from_id
   uses the stack ID).

   [lb] looked in the database to verify the data is okay.
    
   ccpv3_lite=> select stk_id,rt_clnid,is_clnid,nom
                from _rt where rt_clnid  > 0;
    stk_id  | rt_clnid | is_clnid |                   nom                    
   ---------+----------+----------+------------------------------------------
    1559193 |  1559192 |   361319 | New Route 06:54 03-24-12
    1559194 |  1559192 |   361318 | New Route 06:54 03-24-12

   ccpv3_lite=> select sys_id,stk_id,v,created,src,per,vis
      from _rt where stk_id in (1559192,1559193,1559194) order by sys_id;
    sys_id | stk_id  | v |            created         |   src    | per | vis 
   --------+---------+---+----------------------------+----------+-----+-----
    361318 | 1559192 | 1 | 2012-03-24 18:54:26.450503 | deeplink |   3 |   3
    361319 | 1559192 | 2 | 2012-03-24 18:55:19.662383 | deeplink |   3 |   3
    361320 | 1559192 | 3 | 2012-03-24 18:55:22.566689 | deeplink |   3 |   3
    361321 | 1559193 | 1 | 2012-03-24 18:55:19.662383 | deeplink |   2 |   3
    361322 | 1559194 | 1 | 2012-03-24 18:55:22.566689 | deeplink |   2 |   3

    [lb] can't exactly explain how this route's versions happened,
    or why the route was split. I think the splitting happened because
    of how the old code handled route sharing, but still, those five
    rows look weird. But -- thankfully! -- we can not worry about this
    and move on with life, because the new code doesn't have this problem,
    or, rather, it has completely different problems. =)
    */
ALTER TABLE @@@instance@@@.route DROP COLUMN cloned_from_id;
ALTER TABLE @@@instance@@@.route DROP COLUMN permission;
ALTER TABLE @@@instance@@@.route DROP COLUMN visibility;

/* This has long since been replaced by item_stack.stealth_secret. */
ALTER TABLE @@@instance@@@.route DROP COLUMN link_hash_id;

/* ==================================================================== */
/* Step (7)                                                             */
/* ==================================================================== */

\qecho
\qecho Reworking p1_priority
\qecho

/* In CcpV1, there are two rows for each route request, one row
   with priority='bike' and the other 'dist', where the two
   value values add up to 1.0. So we can just drop the rows
   with 'dist'. And there's sometimes 'use_bike_facils', which
   we can just translate to the p3 planner's p3_burden_pump.

   For example,

      ccpv3_test=> select route_stack_id, p1_priority, p1_value
                   from route_parameters where route_stack_id = 2538510;

          route_stack_id |   p1_priority   | p1_value 
         ----------------+-----------------+----------
                 2538510 | bike            |      0.5
                 2538510 | dist            |      0.5
                 2538510 | use_bike_facils |        0

   MAGIC_NUMBER: See pyserver.planner.routed_p3.tgraph::Trans_Graph.burden_vals
                  burden_vals = set([10, 20, 40, 65, 90, 95, 98,])
                 We'll choose something intermediate... 40?
*/

/* MAGIC NUMBER: travel_mode=5 is Travel_Mode.wayward. */
UPDATE @@@instance@@@.route_parameters
   SET p3_burden_pump = 40,
       p3_weight_type = 'fac',
       p3_spalgorithm = 'as*',
       travel_mode = 5,
       p1_value = 0
 WHERE p1_priority = 'dist'
   AND route_stack_id IN (SELECT route_stack_id FROM route_parameters
                          WHERE p1_priority = 'use_bike_facils');

DELETE FROM @@@instance@@@.route_parameters
   WHERE p1_priority = 'dist';
DELETE FROM @@@instance@@@.route_parameters
   WHERE p1_priority = 'use_bike_facils';

/* The two priority values equal 1.0. Delete one column and rename t'other. */
ALTER TABLE @@@instance@@@.route_parameters
   DROP COLUMN p1_priority;
ALTER TABLE @@@instance@@@.route_parameters
   RENAME COLUMN p1_value TO p1_priority;

SELECT cp_constraint_drop_safe('@@@instance@@@.route_parameters',
                               'route_priority_pkey');
ALTER TABLE @@@instance@@@.route_parameters
   ADD CONSTRAINT route_priority_pkey
      PRIMARY KEY (branch_id, route_stack_id);

/* ==================================================================== */
/* Step (8)                                                             */
/* ==================================================================== */

\qecho
\qecho Renaming other columns while we''re at it...
\qecho

ALTER TABLE @@@instance@@@.route_step RENAME COLUMN start_time TO beg_time;
ALTER TABLE @@@instance@@@.route_step RENAME COLUMN end_time TO fin_time;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

