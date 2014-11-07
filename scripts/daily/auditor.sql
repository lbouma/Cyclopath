/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Run various audits against the database. Produce only whitespace in output
   if all is well, and non-whitespace rows if trouble is found. Therefore, if
   run with -qt and piped through grep -v '^[\t ]*$', there is no output
   unless trouble is found. */

BEGIN READ ONLY;

-- FIXME [aa] Rename geofeatures

/*** FIXME: add checks:
     - orphan attachments
     - attachment rows that don't have a corresponding
       attribute/note/tag/discussion row
     - item_versioned rows that don't have a corresponding
       geofeature/attachment row
     - "foreign key" violations where we don't have an FK due to versioning */

/*** Check for orphan wr_email_pending rows. */

\qecho FIXME There are a bunch of tables in here that have been replaced by item_versioned

select
  'orphan wr_email_pending',
  rid,
  wrid
from
  wr_email_pending
where
  wrid not in (select id from region_watched_all);

/*** Check for orphaned annot_bs, annotation, tag_bs, tag_point and tag_region
     rows. ***/

/* annot_bs */

FIXME [aa]

select 'orphan annot_bs', ag.id, ag.version, g.id, g.version
from
   annot_bs ag
   join byway_segment g
   on (ag.byway_id = g.id
       and ag.valid_start_rid < g.valid_until_rid
       and ag.valid_until_rid > g.valid_start_rid ) 
where
   not ag.deleted
   -- and ag.valid_until_rid = cp_rid_inf()
   and g.deleted
order by g.id, ag.id, ag.version;

/* annotation */

SELECT 'orphan annotation', a.id FROM annotation a
WHERE NOT a.deleted
      AND a.valid_until_rid = cp_rid_inf()
      AND NOT EXISTS (SELECT ag.id FROM annot_bs ag
                      WHERE a.id = ag.annot_id
                      -- AND ag.valid_until_rid = cp_rid_inf()
                      AND NOT ag.deleted);

/* tag_bs */

select 'orphan tag_bs', ag.id, ag.version, g.id, g.version
from
   tag_bs ag
   join byway_segment g
   on (ag.byway_id = g.id
       and ag.valid_start_rid < g.valid_until_rid
       and ag.valid_until_rid > g.valid_start_rid ) 
where
   not ag.deleted
   --   and ag.valid_until_rid = cp_rid_inf()
   and g.deleted
order by g.id, ag.id, ag.version;

/* tag_point */

select 'orphan tag_point', ag.id, ag.version, g.id, g.version
from
   tag_point ag
   join point g
   on (ag.point_id = g.id
       and ag.valid_start_rid < g.valid_until_rid
       and ag.valid_until_rid > g.valid_start_rid ) 
where
   not ag.deleted
   -- and ag.valid_until_rid = cp_rid_inf()
   and g.deleted
order by g.id, ag.id, ag.version;

/* tag_region */

select 'orphan tag_region', ag.id, ag.version, g.id, g.version
from
   tag_region ag
   join region g
   on (ag.region_id = g.id
       and ag.valid_start_rid < g.valid_until_rid
       and ag.valid_until_rid > g.valid_start_rid ) 
where
   not ag.deleted
   and g.deleted
order by g.id, ag.id, ag.version;

/*** Check if we're running out of aliases. ***/

/* Gripe if we're more than 50% of the way through alias_source. Replenish
   with aliases.py. */
SELECT
  CASE 
    WHEN count(username) > count(text) * 0.50
       THEN ('WARNING: low on aliases - '
             || count(username) || ' used, '
             || count(text)     || ' total')
    ELSE null
    END
FROM
  alias_source ac
  LEFT OUTER JOIN user_ u
  ON (u.id = ac.id)
;

/*** Check for duplicate annot_bs, tag_bs, tag_point and tag_region rows. ***/

/* annot_bs */

SELECT 'duplicate annot_bs',
       a.id as id1,
       b.id as id2,
       a.byway_id,
       a.annot_id,
       r.timestamp,
       r.id as rev
FROM annot_bs a
JOIN annot_bs b ON (a.id < b.id
                    AND a.annot_id = b.annot_id
                    AND a.byway_id = b.byway_id)
JOIN revision r ON (b.valid_start_rid = r.id)
WHERE
   a.valid_until_rid = cp_rid_inf()
   AND NOT a.deleted
   AND b.valid_until_rid = cp_rid_inf()
   AND NOT b.deleted
ORDER BY r.timestamp, a.id, b.id; 

/* tag_bs */

SELECT 'duplicate tag_bs',
       a.id as id1,
       b.id as id2,
       a.byway_id,
       a.tag_id,
       r.timestamp,
       r.id as rev
FROM tag_bs a
JOIN tag_bs b ON (a.id < b.id
                  AND a.tag_id = b.tag_id
                  AND a.byway_id = b.byway_id)
JOIN revision r ON (b.valid_start_rid = r.id)
WHERE
   a.valid_until_rid = cp_rid_inf()
   AND NOT a.deleted
   AND b.valid_until_rid = cp_rid_inf()
   AND NOT b.deleted
ORDER BY r.timestamp, a.id, b.id; 

/* tag_point */

SELECT 'duplicate tag_point',
       a.id as id1,
       b.id as id2,
       a.point_id,
       a.tag_id,
       r.timestamp,
       r.id as rev
FROM tag_point a
JOIN tag_point b ON (a.id < b.id
                     AND a.point_id = b.point_id
                     AND a.tag_id = b.tag_id)
JOIN revision r ON (b.valid_start_rid = r.id)
WHERE
   a.valid_until_rid = cp_rid_inf()
   AND NOT a.deleted
   AND b.valid_until_rid = cp_rid_inf()
   AND NOT b.deleted
ORDER BY r.timestamp, a.id, b.id; 

/* tag_region */

SELECT 'duplicate tag_region', 
       a.id as id1,
       b.id as id2,
       a.region_id,
       a.tag_id,
       r.timestamp,
       r.id as rev
FROM tag_region a
JOIN tag_region b ON (a.id < b.id
                      AND a.region_id = b.region_id
                      AND a.tag_id = b.tag_id)
JOIN revision r ON (b.valid_start_rid = r.id)
WHERE
   a.valid_until_rid = cp_rid_inf()
   AND NOT a.deleted
   AND b.valid_until_rid = cp_rid_inf()
   AND NOT b.deleted
ORDER BY r.timestamp, a.id, b.id; 

/* Check strict ordering of versions, i.e., 1, 2, 3, 4, ..., with no gaps.

   (NOTE region_watched rows are all version 0, so that's a special case.)

   We already have two CONSTRAINTs: UNIQUE (id, version) and 
   CHECK (version >= 0). Therefore, we can just make sure that no version
   number is greating than the number of records sharing that ID. Pretty
   simple! (This doesn't solve the case for Version = 0, but as a stop-gap we
   can just make sure that if Verion = 0, there's only one record with that
   ID.) */

SELECT 'version too high', * 
   FROM (SELECT id, COUNT(*) AS version_count 
         FROM item_versioned GROUP BY (id)) AS iv1
   JOIN item_versioned AS iv2 
      ON (iv2.id = iv1.id AND iv2.version > iv1.version_count);

SELECT 'version 0 is not alone', *
   FROM (SELECT id, COUNT(*) AS version_count 
         FROM item_versioned GROUP BY (id)) AS iv1
   JOIN item_versioned AS iv2 ON (iv2.id = iv1.id AND iv2.version = 0 
                                     AND iv1.version_count > 1);

SELECT 'version 0 is not region_watched', *
   FROM item_versioned AS iv
   JOIN geofeature gf ON (id, version)
   JOIN geofeature_layer gfl ON (gf.geofeature_layer_id = gfl.id)
   WHERE version = 0 AND gfl.feat_type != 'region_watched';

/* Check strict ordering of start/until revision IDs.

   I.e., Version 1 valid_start_rid 
         < Version 1 valid_until_rid 
         = Version 2 valid_start_rid 
         < Version 2 valid_until_rid 
         ...
         = Version N valid_start_rid
         < Version N valid_until_rid 
         = 2000000000

   The SQL CONSTRAINTs on rids are UNIQUE (id, valid_start_rid), 
   UNIQUE (id, valid_until_rid), and CHECK (valid_start_rid 
   < valid_until_rid), so we just need to check two things -- that each
   version's until_rid matches the next version's start_rid, and that each
   version's start_rid matches the previous version's until_rid. Since we
   already know that start_rid < until_rid for each individual record,
   it'll follow that lesser versions' rids will be less than greater versions'.

   Also, we can check that the final version's until_rid is cp_rid_inf(). */

SELECT 'until_rid not same as next version''s start_rid', * 
   FROM item_versioned AS iv1 JOIN item_versioned iv2 ON iv1.id = iv2.id 
   WHERE iv1.version = iv2.version - 1 
   AND iv1.valid_until_rid != iv2.valid_start_rid;

SELECT 'start_rid not same as last version''s until_rid', * 
   FROM item_versioned AS iv1 JOIN item_versioned iv2 ON iv1.id = iv2.id 
   WHERE iv1.version = iv2.version + 1 
   AND iv1.valid_start_rid != iv2.valid_until_rid;

SELECT 'highest version''s until_rid not ''infinity''', * 
   FROM (SELECT id, MAX(version) AS version_max
         FROM item_versioned GROUP BY (id)) AS iv1
   JOIN item_versioned AS iv2 
      ON (iv2.id = iv1.id AND iv2.version = iv1.version_max)
   WHERE iv2.valid_until_rid != cp_rid_inf();

/* With Bug 1051, Arbitrary Attributes, byway_segment can no longer have a 
   simple CONSTRAINT, but would need to call a function to cross-reference 
   other tables. Since we assume our pyserver code is rock-solid, we can 
   avoid a messy PL/pgSQL function by just doing the work here. */

/* FIXME Test these! */
SELECT '*_node_id is not NULL if geofeature is a byway', * 
   FROM geofeature AS gf
   JOIN geofeature_layer AS gfl
      ON gfl.id = gf.geofeature_layer_id
         AND gf.layer_type = 'byway'
   WHERE gf.beg_node_id IS NULL OR gf.fin_node_id IS NULL;

SELECT '*_node_id is NULL if geofeature is not a byway', * 
   FROM geofeature AS gf
   JOIN geofeature_layer AS gfl
      ON gfl.id = gf.geofeature_layer_id
         AND gf.layer_type != 'byway'
   WHERE gf.beg_node_id IS NOT NULL OR gf.fin_node_id IS NOT NULL;

SELECT 'split_from_id is NULL if geofeature is not a byway', * 
   FROM geofeature AS gf
   JOIN geofeature_layer AS gfl
      ON gfl.id = gf.geofeature_layer_id
         AND gf.layer_type != 'byway_segment'
   WHERE gf.split_from_id IS NOT NULL;

/* Check that the CP geofeature_layer matches the PostGIS geometrytype. */
SELECT 'geometrytype matches geometry_type', * 
   FROM geofeature AS gf
   JOIN item_versioned iv
      ON iv.id = gf.id AND iv.version = gf.version
         AND iv.deleted = FALSE
   JOIN geofeature_layer AS gfl
      ON gfl.id = gf.geofeature_layer_id
   WHERE 
      geom IS NULL
--- FIXME this probably will not work, cannot call fcn. from where clause
      OR geometrytype(geom) != gfl_row.geometry_type;

SELECT 'one_way attribute is -1, 0 or 1', * 
   FROM link_value AS lv
   JOIN attribute AS att
      ON att.id = lv.lhs_id
         AND att.name = 'one_way'
   WHERE lv.value_integer != -1 
         AND lv.value_integer != 0
         AND lv.value_integer != 1;

SELECT 'tag is an attachment is a item_versioned', *
   FROM tag AS t
   FULL OUTER JOIN attachment AS att
      ON att.id = t.id
   FULL OUTER JOIN item_versioned AS iv
      ON iv.id = t.id
   WHERE att.id IS NULL or t.id IS NULL or iv.id IS NULL;
-- FIXME Check same for annotation, thread, post and attachment

-- FIXME Check for NULL geometry? Or is there a constraint for that?

-- FIXME check that geometry is not null or iv is marked deleted

/* Bug 2763: No funny email addresses. */

SELECT 'email has comma',
   email,
   enable_email,
   enable_email_research
FROM user_ WHERE email LIKE '%,%';

SELECT 'email has space',
   email,
   enable_email,
   enable_email_research
FROM user_ WHERE email LIKE '% %';

/* FIXME: Do a regex test. What does the RFC for email say are valid
          characters?
   FIXME: The bug isn't fixed; test setting a wacky email and fix it.
          Or wait until in-band registration is coded...
*/

/* All done. */

ROLLBACK;

