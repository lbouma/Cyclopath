/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;

SET search_path = minnesota, public;

CREATE FUNCTION move_tables(schema TEXT) RETURNS VOID AS $$
  -- Move all tables from a separate schema to public.
  DECLARE
    t RECORD;
  BEGIN
    FOR t IN SELECT name FROM tables_views WHERE schemaname=schema
    LOOP
      EXECUTE 'ALTER TABLE ' || t.name || ' SET SCHEMA public';
    END LOOP;
  END 
$$ LANGUAGE PLPGSQL;

CREATE TEMPORARY VIEW tables_views (name, schemaname) AS
SELECT tablename, schemaname FROM pg_tables UNION
SELECT viewname, schemaname FROM pg_views;

SELECT move_tables('minnesota');

ALTER SEQUENCE feature_id_seq SET SCHEMA public;
ALTER SEQUENCE log_event_id_seq SET SCHEMA public;

ALTER FUNCTION revision_geosummary_update(INT) SET SCHEMA public;

-- Update PostGIS table
UPDATE geometry_columns SET f_table_schema = 'public'
WHERE f_table_schema = 'minnesota';

-- Won't need this any more
DROP FUNCTION move_tables(text);

\d
-- SELECT * FROM geometry_columns;

--ROLLBACK;
COMMIT;
