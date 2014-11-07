
/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Use information from apache_event to fill in ip address for old routes 
   @once-per-instance */

\set percent 'ROUND(100.0 * COUNT(route_id)/(SELECT COUNT(*) FROM route), 3) || \'%\' AS "percent of all routes"'

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;
SET CONSTRAINTS ALL DEFERRED;

SELECT 
  COUNT(*) AS "Total Routes", 
  COUNT(*) - COUNT(host) AS "Routes without ip addresses"
FROM route;

SELECT 
  MIN(created) AS "First no-ip route", 
  MAX(created) AS "Last no-ip route"
FROM route
WHERE host IS NULL;

CREATE TEMPORARY TABLE apache_event_route AS
SELECT 
  id,
  client_host::inet,
  timestamp_tz AS start_time, 
  timestamp_tz 
      + (time_consumed * interval '1 second') 
      + interval '2 second'
    AS end_time
FROM
  apache_event WHERE wfs_request='GetRoute'
  -- Exclude the 1 request that somehow got an actual hostname instead of an IP
  AND client_host !~ '[a-z]';

CREATE INDEX stindex on apache_event_route(start_time);
CREATE INDEX etindex on apache_event_route(end_time);

\qecho Matching routes to events, this will take a few minutes
CREATE TEMPORARY TABLE route_event_matchup as
SELECT
  r.id AS route_id,
  r.host AS route_host,
  aer.id AS ae_id,
  aer.client_host AS ae_host
FROM
  route r LEFT OUTER JOIN
  apache_event_route aer 
  ON (r.created >= aer.start_time AND r.created <= aer.end_time);

-- Some corner cases; these should be dealt with at some point (see bug 1775)
\qecho Routes with no event found
SELECT COUNT(route_id), :percent FROM route_event_matchup WHERE ae_id IS NULL;
DELETE FROM route_event_matchup WHERE ae_id IS NULL;

\qecho Routes with multiple events found (with different ips)
SELECT COUNT(route_id), :percent FROM
  (SELECT route_id FROM route_event_matchup
   GROUP BY route_id 
   HAVING COUNT(ae_id) > 1 AND COUNT(DISTINCT ae_host) > 1) AS a;

DELETE FROM route_event_matchup WHERE route_id IN
  (SELECT route_id FROM route_event_matchup
   GROUP BY route_id 
   HAVING COUNT(ae_id) > 1 AND COUNT(DISTINCT ae_host) > 1);

-- Sanity check: make sure ae_host matches route_host for existing routes.
\qecho Routes that we know are matched to the wrong event
SELECT COUNT(route_id), :percent FROM route_event_matchup
  WHERE route_host != ae_host;

-- The actual update
UPDATE route r SET host=ae_host FROM route_event_matchup rem
  WHERE rem.route_id = r.id AND r.host IS NULL;

SELECT 
  COUNT(*) AS "Total Routes", 
  COUNT(*) - COUNT(host) AS "Routes still without ip addresses"
FROM route;

\qecho Done!
--ROLLBACK
COMMIT;
