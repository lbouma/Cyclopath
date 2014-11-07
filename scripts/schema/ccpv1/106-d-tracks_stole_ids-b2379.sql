/* Copyright (c) 2006-2012 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script fixes two errant tracks.
\qecho 
\qecho See Bug 2379.
\qecho 
\qecho   http://bugs.grouplens.org/show_bug.cgi?id=2379
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO minnesota, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

/* ========================================================================= */
/* Step (1) -- Discussion                                                    */
/* ========================================================================= */

/*

   From ccpv2_tmp:

      SELECT iv1.stack_id FROM item_versioned AS iv1
      JOIN item_versioned AS iv2
      ON (
         iv1.branch_id = iv2.branch_id
         AND iv1.stack_id = iv2.stack_id
         AND iv1.valid_until_rid = iv2.valid_until_rid)
      WHERE iv1.system_id != iv2.system_id;

       stack_id 
      ----------
        1534037
        1534037
        1534051
        1534051
      (4 rows)

   But this is CcpV1, so:

      SELECT DISTINCT(track.id) FROM track
      JOIN route ON (route.id = track.id);

         id    
      ---------
       1534037
       1534051
      (2 rows)

*/

/* ========================================================================= */
/* Step (2) -- Application                                                   */
/* ========================================================================= */

CREATE FUNCTION tracks_eradicate_identity_thieves()
   RETURNS VOID AS $$
   DECLARE
      itamaes_uuid TEXT;
      instance_uuid TEXT;
      count_ids INTEGER;
      r RECORD;
   BEGIN

      /* First check that the same number of IDs exist as when this script was
       * first writ. */
      EXECUTE 'SELECT COUNT(DISTINCT(track.id)) FROM track
               JOIN route ON (route.id = track.id);'
         INTO STRICT count_ids;
      IF count_ids != 2 THEN
         RAISE EXCEPTION 'Unexpected track error count!';
      END IF;

      /* Next go through the IDs and check they're the same, and delete their
       * rows. */
      FOR r IN 
            SELECT DISTINCT track.id FROM track 
            JOIN route ON (route.id = track.id) LOOP
         IF (r.id != 1534037) AND (r.id != 1534051) THEN
            RAISE EXCEPTION 'Unexpected track id!: %', r.id;
         END IF;
         DELETE FROM track_point WHERE track_id = r.id;
         DELETE FROM track WHERE id = r.id;
      END LOOP;

      EXECUTE 'SELECT COUNT(DISTINCT(track.id)) FROM track
               JOIN route ON (route.id = track.id);'
         INTO STRICT count_ids;
      IF count_ids != 0 THEN
         RAISE EXCEPTION 'Track error count not zero!';
      END IF;

   END;
$$ LANGUAGE plpgsql VOLATILE;

/* */

SELECT run_maybe('minnesota', 'tracks_eradicate_identity_thieves');

/* ========================================================================= */
/* Step (3) -- Cleanup                                                       */
/* ========================================================================= */

DROP FUNCTION tracks_eradicate_identity_thieves();

/* ========================================================================= */
/* Step (n) -- All done!                                                     */
/* ========================================================================= */

\qecho 
\qecho Done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;

