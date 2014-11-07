/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Split schema; all tables with records specific to the Twin Cities instance
 * are moved to the 'minnesota' schema while general Cyclopath tables (mostly
 * user tables and enums) remain in 'public'.
 */

BEGIN TRANSACTION;

SET search_path = minnesota, public;

CREATE FUNCTION move_tables(schema TEXT) RETURNS VOID AS $$
  -- Move all tables and views in public to a separate schema, except:
  --   type tables, draw parameters, & other enums
  --   user-related
  --   PostGIS-related
  -- Curiously, ALTER TABLE is also used to modify views.
  DECLARE
    t RECORD;
  BEGIN
    FOR t IN SELECT name FROM tables_views WHERE schemaname='public' 
             AND name NOT LIKE '%_type' AND name NOT like 'draw_%'
             AND name NOT IN ('viz', 'work_hint_status', 'permissions')
             AND name NOT IN ('alias_source', 'auth_fail_event', 'ban')
             AND name NOT IN ('user_', 'user_preference_event')
             AND name NOT IN ('geometry_columns', 'spatial_ref_sys')
             AND name NOT IN ('upgrade_event')
    LOOP
      EXECUTE 'ALTER TABLE ' || t.name || ' SET SCHEMA ' || schema;
    END LOOP;
  END 
$$ LANGUAGE PLPGSQL;

CREATE TEMPORARY VIEW tables_views (name, schemaname) AS
SELECT tablename, schemaname FROM pg_tables UNION
SELECT viewname, schemaname FROM pg_views;

SELECT move_tables('minnesota');

-- Don't need to move indexes, constraints or most sequences since they are
-- moved with their tables.  But these sequences might not be moved
-- automatically:
ALTER SEQUENCE feature_id_seq SET SCHEMA minnesota;
ALTER SEQUENCE log_event_id_seq SET SCHEMA minnesota;

-- Don't need to move most functions, except this one since it has a hardcoded
-- spatial reference system.
ALTER FUNCTION revision_geosummary_update(INT) SET SCHEMA minnesota;

-- Update PostGIS table
UPDATE geometry_columns SET f_table_schema = 'minnesota' WHERE f_table_name IN
  (SELECT name FROM tables_views WHERE schemaname='minnesota');

-- Won't need this any more
DROP FUNCTION move_tables(text);

\d
-- SELECT * FROM geometry_columns;

--ROLLBACK;
COMMIT;
