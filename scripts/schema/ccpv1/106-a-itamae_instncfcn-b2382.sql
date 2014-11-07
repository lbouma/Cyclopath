/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script adds a convenience fcn. to identify itamae''s UUIDs.
\qecho 
\qecho See Bug 2382.
\qecho 
\qecho   http://bugs.grouplens.org/show_bug.cgi?id=2382
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* NOTE We want to declare the fcn. in the public schema, but it access tables 
 *      only defined in the instance schemas, so we include one of the
 *      instances to fool Postgres into letting us create the function. */
SET search_path TO public, minnesota;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

/*

$ psql -U cycling production
SET
Welcome to psql 8.2.7, the PostgreSQL interactive terminal.

Type:  \copyright for distribution terms
       \h for help with SQL commands
       \? for help with psql commands
       \g or terminate with semicolon to execute query
       \q to quit

production=> select * from key_value_pair ;
        key         |                value                 
--------------------+--------------------------------------
 cp_instance_uuid   | de97691e-c393-11e0-b644-0013722cc302
 tilecache_last_rid | 15000
(2 rows)

production=> select current_schema();
 current_schema 
----------------
 minnesota
(1 row)

production=> set search_path to colorado, public;
SET
production=> select * from key_value_pair ;
        key         |                value                 
--------------------+--------------------------------------
 tilecache_last_rid | 87
 cp_instance_uuid   | da3a7406-c393-11e0-b644-0013722cc302
(2 rows)

*/

\qecho Creating fcn.: instance_verify_itamae

/* NOTE This is a Convenience fcn. for developers.
        This is not a temporary fcn.; we will not be deleting it. */
CREATE FUNCTION cp_instance_verify_itamae(IN instance_sought TEXT)
   RETURNS BOOLEAN AS $$
   DECLARE
      uuids_match BOOLEAN;
      current_uuid TEXT;
      itamae_uuid_minnesota TEXT;
      itamae_uuid_colorado TEXT;
   BEGIN

      /* SYNC_ME: Search key_value pair: cp_instance_uuid. */
      itamae_uuid_minnesota := 'de97691e-c393-11e0-b644-0013722cc302';
      itamae_uuid_colorado := 'da3a7406-c393-11e0-b644-0013722cc302';

      uuids_match := FALSE;

      IF (current_schema() = instance_sought) 
         AND (current_schema() != 'public') THEN

         /* NOTE: Postgres provides the current_schema() fcn., which also us to
          *       define this fcn. in the public schema, rather than defining
          *       it once per schema. */
         /* FIXME: If this works, re-write CcpV2's cp_srid()? */

         IF current_schema() = 'public' THEN
            RAISE EXCEPTION 'Unexpected schema: ''%''.', current_schema();
         END IF;

         EXECUTE 'SELECT value FROM key_value_pair
                  WHERE key = ''cp_instance_uuid'';'
            INTO STRICT current_uuid;

         IF current_schema() = 'minnesota' THEN
            IF current_uuid = itamae_uuid_minnesota THEN
               uuids_match := TRUE;
            END IF;
         ELSIF current_schema() = 'colorado' THEN
            IF current_uuid = itamae_uuid_colorado THEN
               uuids_match := TRUE;
            END IF;
         ELSE 
            RAISE EXCEPTION 'Unexpected schema: ''%''.', current_schema();
         END IF;

      END IF;

      RETURN uuids_match;

   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho Testing on schema: public
SET search_path TO public;
SELECT cp_instance_verify_itamae('public');     -- FALSE
SELECT cp_instance_verify_itamae('minnesota');  -- FALSE
SELECT cp_instance_verify_itamae('colorado');   -- FALSE
SELECT cp_instance_verify_itamae('fake');       -- FALSE

\qecho Testing on schema: minnesota
SET search_path TO minnesota, public;
SELECT cp_instance_verify_itamae('public');     -- FALSE
SELECT cp_instance_verify_itamae('minnesota');  -- TRUE
SELECT cp_instance_verify_itamae('colorado');   -- FALSE
SELECT cp_instance_verify_itamae('fake');       -- FALSE

\qecho Testing on schema: colorado
SET search_path TO colorado, public;
SELECT cp_instance_verify_itamae('public');     -- FALSE
SELECT cp_instance_verify_itamae('minnesota');  -- FALSE
SELECT cp_instance_verify_itamae('colorado');   -- TRUE
SELECT cp_instance_verify_itamae('fake');       -- FALSE

/* ==== */
/* DONE */
/* ==== */

\qecho 
\qecho All done!
\qecho 

COMMIT;

