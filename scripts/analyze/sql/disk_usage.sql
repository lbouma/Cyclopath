/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script lists all tables and their sizes. */

SELECT
   table_name,
   to_char(1.0 * pg_total_relation_size(table_name) / (1024*1024),
           '9999.9') AS megabytes,
   to_char(100.0 * pg_total_relation_size(table_name)
           / (SELECT sum(pg_total_relation_size(table_name))
              FROM information_schema.tables
              WHERE
                 table_schema = 'public'
                 AND table_type = 'BASE TABLE'),
           '99.99') AS percent
FROM information_schema.tables
WHERE
   table_schema = 'public'
   AND table_type = 'BASE TABLE'
ORDER BY megabytes DESC;

