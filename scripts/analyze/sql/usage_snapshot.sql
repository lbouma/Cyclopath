/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script prints out some basic usage statistics. */

BEGIN;

/* Load temp. VIEWs. */
\i ../../daily/usage/ccp_common.sql

\qecho -- NOTE: These count include user-generated and auto-generated content.

\qecho -- Places
SELECT count(*) FROM _gf WHERE item_type_id = cp_item_type_id('waypoint');

/* MEH: CcpV2: There's probably a better way to do this: like running ccp.py
                 and fetching link_values by attachment and geofeature types.

\qecho -- Places with a non-null comment
SELECT count(*) FROM point
WHERE
   comments is not null
   and valid_until_rid = cp_rid_inf() and not deleted;
   */

\qecho -- Notes
SELECT count(*) FROM annotation
   JOIN item_versioned AS iv USING (system_id)
   WHERE iv.valid_until_rid = cp_rid_inf() and not iv.deleted;

/* MEH: CcpV2: See comment above about re-implementing with ccp.py.

\qecho -- Note applications
SELECT count(*) FROM annot_bs_geo
WHERE valid_until_rid = cp_rid_inf() and not deleted;
   */

\qecho -- Revisions
\qecho -- NOTE: This does not exclude revisions made for discussions
SELECT count(*) FROM revision;

\qecho -- Bikeability ratings
/* Ratings which have been changed from a rating to "don't know" */
SELECT count(*) FROM user_rating WHERE value >= 0;

\qecho -- Users who have logged in at least once (takes ~90 seconds).
SELECT count(DISTINCT u.username)
   FROM user_ AS u
   JOIN apache_event AS ae
      ON (u.username = ae.username);

\qecho -- Number of routes
SELECT count(*) FROM route;

ROLLBACK;

