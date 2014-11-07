/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho This script fixes misc problems.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Delete obsolete attribute, /item/reminder_email.
\qecho

UPDATE group_item_access SET deleted = TRUE WHERE
   stack_id = (SELECT stack_id FROM attribute
               WHERE value_internal_name = '/item/reminder_email');

UPDATE item_versioned SET deleted = TRUE WHERE
   stack_id = (SELECT stack_id FROM attribute
               WHERE value_internal_name = '/item/reminder_email');

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Archive deprecated reaction_reminder table.
\qecho

/* BUG nnnn: Route reactions. See item_reminder_set.py, which uses
             the item_event_alert table. The reaction_reminder table
             is deprecated. But the minnesota schema has 38 records in
             the table that someone someday (probably no one, never)
             might care about. */

ALTER TABLE reaction_reminder RENAME TO __delete_me_ccpv1_reaction_reminder;

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Remake the revision convenience views.
\qecho

/* TABLE VIEW: Revision. */

/* The SUBSTRING on DATE_TRUNC is a hack: 16 is all chars up to the :seconds,
   since DATE_TRUNC doesn't really truncate in the string, in that it just
   changes values to 0. And there's not another string function to help us.
   So just use our vast counting skills and truncate the string at said count.
   */
DROP VIEW IF EXISTS _rev;
CREATE OR REPLACE VIEW _rev AS
   SELECT
      rev.id                     AS id
      , SUBSTRING(
         DATE_TRUNC('minute', rev.timestamp)::TEXT
            FOR 16)              AS timestamp
      , rev.host                 AS host
      , rev.username             AS user
      -- , rev.comment           AS comment
      , SUBSTRING(rev.comment FOR 30)
                                 AS comment
      -- , rev.bbox              AS bbox
      -- , rev.geosummary        AS geosummary
      -- , rev.geometry          AS geometry
      , to_char(ST_Perimeter(rev.bbox), 'FM999999999999999D9')
                                 AS bbox_perim
      , to_char(ST_Perimeter(rev.geosummary), 'FM999999999999999D9')
                                 AS gsum_perim
      , to_char(ST_Perimeter(rev.geometry), 'FM999999999999999D9')
                                 AS geom_perim
      -- , rev.permission        AS _prm -- DEPRECATED
      -- , rev.visibility        AS _vis -- DEPRECATED
      , rev.branch_id            AS br_id
      , rev.is_revertable        AS rvtok
      , rev.reverted_count       AS rvtct
      , rev.msecs_holding_lock   AS lcktm
      , rev.alert_on_activity    AS alrt
   FROM
      revision AS rev
   ORDER BY
      rev.id DESC
   ;

/* TABLE VIEW: Group Revision. */

DROP VIEW IF EXISTS _grev;
CREATE OR REPLACE VIEW _grev AS
   SELECT
      rev.id                     AS id
      , SUBSTRING(
         DATE_TRUNC('minute', rev.timestamp)::TEXT
            FOR 16)              AS timestamp
      --, rev.host                 AS host
      , rev.username             AS user
      --, gr.stack_id              AS gsid
      , gr.name                  AS gnom
      , SUBSTRING(rev.comment FOR 30)
                                 AS comment
      -- , rev.permission        AS _prm -- DEPRECATED
      -- , rev.visibility        AS _vis -- DEPRECATED
      , rev.branch_id            AS br_id
      , rev.is_revertable        AS rvtok
      , rev.reverted_count       AS rvtct
      , rev.msecs_holding_lock   AS lcktm
      , rev.alert_on_activity    AS alrt
      /* group_revision: */
      , grev.visible_items       AS n_vis
      , grev.is_revertable       AS ok_rvt
      -- Skipping: grev.date_created, which is same as rev.timestamp.
      -- Ignore grev.bbox and grev.geosummary and just show deets about geom.
      , to_char(ST_Perimeter(grev.geometry), 'FM999999999999999D9')
                                 AS grev_geom
   FROM
      group_revision AS grev
   JOIN
      group_ AS gr ON (grev.group_id = gr.stack_id)
   JOIN
      revision AS rev ON (rev.id = grev.revision_id)
   WHERE
   --     gr.valid_start_rid <= grev.revision_id
   -- AND gr.valid_until_rid > grev.revision_id
          gr.valid_start_rid <= grev.revision_id
      AND grev.revision_id < gr.valid_until_rid
   ORDER BY
      rev.id DESC
   ;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;

