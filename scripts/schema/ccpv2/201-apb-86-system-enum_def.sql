/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Creates the enum_definition table and consumes other tables. */

\qecho 
\qecho This script creates and populates the enum_defintion table.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- .                    */
/* ==================================================================== */

/* FIXME: Can't decide which approach is better, so do both for now and figure
 *        it out later, i.e., which it gets implemented in pyserver, you can 
 *        try either method. */

/*
\qecho 
\qecho Creating the digest_frequency lookup table
\qecho 

CREATE TABLE access_scope (
   id INTEGER NOT NULL,
   scope_name TEXT
);

ALTER TABLE access_scope 
   ADD CONSTRAINT access_scope_pkey 
   PRIMARY KEY (id);

CREATE INDEX access_scope_scope_name ON access_scope (scope_name);
*/

/* ==================================================================== */
/* Step (1) -- Create the new enum_definition table.                    */
/* ==================================================================== */

\qecho 
\qecho Creating the enum_definition table values
\qecho 

CREATE TABLE enum_definition (
   id INTEGER NOT NULL,
   enum_name TEXT,
   enum_description TEXT,
   enum_key INTEGER,
   enum_value TEXT,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE enum_definition 
   ADD CONSTRAINT enum_definition_pkey 
   PRIMARY KEY (id);

ALTER TABLE enum_definition 
   ADD CONSTRAINT enum_definition_unique_enum_name_and_key 
      UNIQUE (enum_name, enum_key);

CREATE INDEX enum_definition_enum_name 
   ON enum_definition (enum_name);

CREATE INDEX enum_definition_enum_key 
   ON enum_definition (enum_key);

CREATE INDEX enum_definition_enum_name_and_key 
   ON enum_definition (enum_name, enum_key);

CREATE SEQUENCE enum_definition_id_seq;

ALTER TABLE enum_definition 
   ALTER COLUMN id 
      SET DEFAULT NEXTVAL('enum_definition_id_seq');
/* See also ALTER SEQUENCE ... RESTART WITH ...; */

/* ==================================================================== */
/* Step (2) -- Populate new enums, from scratch.                        */
/* ==================================================================== */

\qecho 
\qecho Creating helper functions
\qecho 

/* NOTE: This fcn. is not temporary. */
CREATE FUNCTION public.cp_enum_definition_new(
   IN enum_name_ TEXT, 
   IN enum_key_ INTEGER, 
   IN enum_value_ TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'INSERT INTO enum_definition 
            (enum_name, enum_description, enum_key, enum_value, last_modified)
         VALUES (
            ''' || enum_name_ || ''', 
            '''', 
            ' || enum_key_ || ', 
            ''' || enum_value_ || ''', 
            now());';
END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE: This fcn. is not temporary. */
CREATE FUNCTION public.cp_enum_definition_get_key(
   IN enum_name_ TEXT,
   IN enum_value_ TEXT)
   RETURNS INTEGER AS $$
   DECLARE
      enum_key_ INTEGER;
   BEGIN
      SELECT enum_key FROM enum_definition
         WHERE enum_name = enum_name_
            AND enum_value = enum_value_
         INTO enum_key_;
      RETURN enum_key_;
END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho
\qecho Creating the digest frequency lookup values
\qecho

/* SYNC_ME: Search: Digest_Frequency table. */
SELECT cp_enum_definition_new('digest_frequency', 0, 'never');
SELECT cp_enum_definition_new('digest_frequency', 1, 'immediately');
SELECT cp_enum_definition_new('digest_frequency', 2, 'daily');
SELECT cp_enum_definition_new('digest_frequency', 3, 'weekly');

\qecho 
\qecho Creating the thread type lookup values
\qecho 

/* SYNC_ME: Search: thread_type_id. */
SELECT cp_enum_definition_new('thread_type', 0, 'default');
SELECT cp_enum_definition_new('thread_type', 1, 'general');
SELECT cp_enum_definition_new('thread_type', 2, 'reaction');

\qecho 
\qecho Cleaning up helper function
\qecho 

/* NOTE: Not dropping these fcns. Let's keep for later scripts.
DROP FUNCTION cp_enum_definition_new(IN enum_name_ TEXT,
                                     IN enum_key_ INTEGER,
                                     IN enum_value_ TEXT);
DROP FUNCTION cp_enum_definition_get_key(IN enum_name_ TEXT,
                                         IN enum_value_ TEXT);
*/

/* ==================================================================== */
/* Step (3) -- Populate new enums, from existing tables.                */
/* ==================================================================== */

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'access_infer', '', id, infer_name, now() FROM access_infer);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'access_level', '', id, description, now() FROM access_level);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'access_scope', '', id, scope_name, now() FROM access_scope);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'access_style', '', id, style_name, now() FROM access_style);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'item_type', '', id, type_name, now() FROM item_type);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'tag_preference_type', '', id, text, last_modified 
    FROM tag_preference_type);

INSERT INTO enum_definition (enum_name, enum_description, enum_key, enum_value,
                             last_modified)
   (SELECT 'viz', '', id, name, now() FROM viz);

/* ==================================================================== */
/* Step (4) -- Fix all tables' references to old enum tables.           */
/* ==================================================================== */

/* FIXME: Implement, maybe in later script. */

/* ==================================================================== */
/* Step (5) -- Drop old enum tables.                                    */
/* ==================================================================== */

/* FIXME: Implement, maybe in later script. */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

