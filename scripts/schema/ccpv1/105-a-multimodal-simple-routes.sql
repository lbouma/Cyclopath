/* Copyright (c) 2006-2012 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds support for the Google Transit Feed Specification. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds a travel_mode column to the route table.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Alter route table                                        */
/* ==================================================================== */

\qecho 
\qecho Altering the route table.
\qecho 

ALTER TABLE route ADD COLUMN travel_mode SMALLINT;

/* BUG 2328: Consolidate route_priority table and route.transit_pref and
 * depart_at. */
ALTER TABLE route ADD COLUMN transit_pref SMALLINT;
ALTER TABLE route ADD COLUMN depart_at TEXT;

/* ==================================================================== */
/* Step (2) -- Updating existing routes                                 */
/* ==================================================================== */

\qecho 
\qecho Updating column values.
\qecho 

/* MAGIC NUMBER: 1 is 'bicycle'. */
UPDATE route SET travel_mode = 1;

/* ==================================================================== */
/* Step (3) -- Add Multimodal routes                                    */
/* ==================================================================== */

CREATE FUNCTION consume_mm_routes()
   RETURNS VOID AS $$
   DECLARE
      rid_inf_ INTEGER;
      evt_count INTEGER;
      evt_row RECORD;
      route_id INTEGER;
      owner_query TEXT;
      subquery_find_routes TEXT;
      query_route_count TEXT;
      query_find_route TEXT;
      found_route_count INTEGER;
      found_route_first_id INTEGER;
   BEGIN
      rid_inf_ := rid_inf();
      BEGIN
         /* NOTE: The query seems slower without the date in WHERE. */
         /* MAGIC NUMBER: We released MM on June 30, so we're only interested 
          *               in records created after the 29th. */
         EXECUTE 'SELECT COUNT(*) FROM apache_event 
                     WHERE wfs_request=''GetRoute''
                           AND request LIKE ''%travel_mode=transit%''
                           AND timestamp_tz > ''2011-06-29'';'
            INTO STRICT evt_count;
         RAISE INFO 'Found % records', evt_count;
         FOR evt_row IN SELECT * FROM apache_event 
               WHERE wfs_request='GetRoute' 
                     AND request LIKE '%travel_mode=transit%' 
                     AND timestamp_tz > '2011-06-29' LOOP
            /* Find the existing route record. Which has a later timestamp than
             * the apache event record. */
            RAISE INFO 'Looking at apache event: %.', evt_row;
            /* This is smudgy: the route timestamp is some number of seconds
             * after the apache timestamp. This is an inexact science! =) */
            IF evt_row.username IS NULL THEN
               owner_query := 'owner_name IS NULL';
            ELSE
               owner_query := 'owner_name = ''' || evt_row.username || '''';
            END IF;
            subquery_find_routes :=
               'route 
                  WHERE
                     ' || owner_query || '
                     AND host = ''' || evt_row.client_host || '''::INET
                     AND session_id = ''' || evt_row.sessid || '''
                     AND (''' || evt_row.timestamp_tz || ''', 
                           INTERVAL ''2 minutes'') 
                          OVERLAPS (created, created)';
            RAISE INFO 'subquery_find_routes: %', subquery_find_routes;
            query_route_count := 'SELECT COUNT(*) FROM ' 
                                 || subquery_find_routes || ';';
            EXECUTE query_route_count INTO STRICT found_route_count;
            RAISE INFO 'query_route_count: %', found_route_count;
            IF found_route_count > 0 THEN
               query_find_route := 'SELECT id FROM '
                                    || subquery_find_routes || ' 
                                    ORDER BY created ASC 
                                    LIMIT 1;';
               EXECUTE query_find_route INTO STRICT found_route_first_id;
               RAISE INFO 'Found route ID: %', found_route_first_id;
               /* MAGIC NUMBER: travel_mode: 2 is 'transit'. */
               /* FIXME: It'd be nice to capture transit_pref and depart_at...
                *        but it doesn't seem worth parsing it out. Is it easy
                *        to datamine an SQL TEXT field? 
                            AND transit_pref = ' || evt_row.transit_pref || '
                            AND depart_at = ''' || evt_row.depart_at || '''
                */
               EXECUTE 'UPDATE route 
                        SET travel_mode = 2
                        WHERE id = ' || found_route_first_id || ';';
            /* ELSE: routed was not started, so this route failed (but the
             *       apache event was still recorded). */
            END IF;
         END LOOP;
      EXCEPTION WHEN undefined_table THEN
         RAISE INFO 'apache_event table not defined: must be a dev machine.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT consume_mm_routes();

DROP FUNCTION consume_mm_routes();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

