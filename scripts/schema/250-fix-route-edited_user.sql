/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho
\qecho This script fixes the item_revisionless.created_user value for routes.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* */

UPDATE item_revisionless
   SET edited_user = _gia.grp_name
   FROM _gia
      WHERE ityp = 'route'
      AND grp_name NOT IN ('All Users',
                           'Session ID Group',
                           'Stealth-Secret Group')
      AND system_id = _gia.sys_id
   ;

/* */

DELETE FROM public.geofeature_layer WHERE id = 12;
INSERT INTO geofeature_layer (
   id,
   feat_type, 
   layer_name, 
   geometry_type, 
   restrict_usage,
   draw_class_owner,
   draw_class_arbiter,
   draw_class_editor,
   draw_class_viewer
   -- Skipping: last_modified
   )
   VALUES (
      12,
      'byway',
      '_4WD_Road',
      'LINESTRING',
      FALSE,
      11,
      11,
      11,
      11);

/* */

CREATE FUNCTION cp_alter_table_track()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE track ALTER COLUMN created_tbd DROP NOT NULL;

      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'Table track already altered.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_table_track();

DROP FUNCTION cp_alter_table_track();

/* */

/* Fix incorrect user_ids in item_findability. */

/*
   select * from item_findability as itf
   left outer join user_ on (user_.id = itf.user_id)
   where user_.id is null;
*/

UPDATE item_findability
SET user_id = (SELECT id FROM user_
               WHERE user_.username = item_findability.username);

/* */

/* Fix MetC bike facils with "ERROR" value... weird; must've been a long-ago
   import problem. */

/* The ccp_export_branches script is indicating a problem with a handful
   of bike facility values in the MetC branch.

From the log file:

  3388 Sep-07 03:13:43  ERRR      metc_bikewyz  #  diff_class: unknown bike_facil: "ERROR" / FID: n/a

From the db:

ccpv3_live=> select * from _lv where vt = 'ERROR';

 sys_id  | brn_id  | stk_id  | v | d | r | start | until | a | nfr  |   lhs   |   rhs   | vb | vi | vr |  vt   | vx | vd 
---------+---------+---------+---+---+---+-------+-------+---+------+---------+---------+----+----+----+-------+----+----
 1407322 | 2538452 | 2684478 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 2684477 |    |    |    | ERROR |    | 
 1410464 | 2538452 | 2687482 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 2687480 |    |    |    | ERROR |    | 
 1427929 | 2538452 | 2704213 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 1359860 |    |    |    | ERROR |    | 
 1449865 | 2538452 | 2725208 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 1400113 |    |    |    | ERROR |    | 
 1463539 | 2538452 | 2738263 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 1444184 |    |    |    | ERROR |    | 
 1469354 | 2538452 | 2743873 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 2743869 |    |    |    | ERROR |    | 
 1471211 | 2538452 | 2745663 | 1 | f | f | 22303 | inf   | 8 | 0x20 | 2539744 | 1484463 |    |    |    | ERROR |    | 

Where 2538452 is Metc Bikeways 2012 branch,
and lhs is /metc_bikeways/bike_facil.

ccpv3_live=> select distinct(vt) from _lv where lhs = 2539744;

      vt      
--------------
 shld_lovol
 rdway_shared
 bike_lane
 ERROR
 hway_lovol
 paved_trail

*/

UPDATE link_value
   SET value_text = ''
 WHERE value_text = 'ERROR'
   AND lhs_stack_id = 2539744;

/* Now it's:

ccpv3_live=> select distinct(vt) from _lv where lhs = 2539744;
      vt      
--------------
 shld_lovol
 rdway_shared
 
 bike_lane
 hway_lovol
 paved_trail

*/

/* */

/* For some reason the colorado geofeature table constraint is wrong.

=> SELECT postgis_constraint_srid('colorado', 'geofeature', 'geometry');
ERROR:  invalid input syntax for integer: "cp_srid"
CONTEXT:  SQL function "postgis_constraint_srid" statement 1

=> \d colorado.geofeature
    "enforce_srid_geometry" CHECK (st_srid(geometry) = colorado.cp_srid())

=> \d minnesota.geofeature
    "enforce_srid_geometry" CHECK (st_srid(geometry) = 26915)

The geometry_columns view is also borked:

=> SELECT * FROM geometry_columns WHERE f_table_name = 'geofeature';
ERROR:  invalid input syntax for integer: "cp_srid"
CONTEXT:  SQL function "postgis_constraint_srid" statement 1

*/

ALTER TABLE colorado.geofeature DROP CONSTRAINT enforce_srid_geometry;
/* This doesn't work:
ALTER TABLE colorado.geofeature
   ADD CONSTRAINT enforce_srid_geometry
   CHECK (srid(geometry) = SELECT cp_srid());
*/
-- Whatever, just MAGIC_NUMBER it in there.
ALTER TABLE colorado.geofeature
   ADD CONSTRAINT enforce_srid_geometry
   CHECK (srid(geometry) = 26913);

/* */

/* 2014.09.17: Apache log lines for big files, like VirtualBox VDI
               files, indicate size as a big int.
                
   E.g., 16072 1.2.3.4 - - [24/Jan/2014:16:29:22 -0600]
         "GET /exports/devs/cyclopath.vdi.zip HTTP/1.1" 200 6076270858
*/

ALTER TABLE apache_event ALTER COLUMN size TYPE BIGINT;

/* */

/* 2014.09.25: Whoa, wait, what, how didn't we [lb] notice missing
               rows from travel_mode for this long?

ccpv3_live=> SELECT * FROM travel_mode;
 id |   descr   
----+-----------
  0 | undefined
  1 | bicycle
  2 | transit
  3 | walking
  4 | autocar
  5 | generic
(6 rows)

*/

-- Change id=5 from 'generic' to 'wayward'.
UPDATE travel_mode SET descr = 'wayward' WHERE id = 5;
INSERT INTO travel_mode (id, descr) VALUES (6, 'classic');
INSERT INTO travel_mode (id, descr) VALUES (7, 'invalid');

/* */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

