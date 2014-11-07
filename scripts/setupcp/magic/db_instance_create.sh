#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Create schema for another Cyclopath instance, using the minnesota schema as a
# template by replacing the schema name and SRID as appropriate before
# reloading.

# This script is deprecated... but [lb] isn't sure there's another way to make
# a fresh database other than loading the schema and then loading the
# as-of-yet-to-be-dumped minimal db dump, i.e., from the production database,
# dump the schema and then dump the public definition tables, like item_type
# and whatnot.
echo "This script is Deprecated."
exit

SFILE="new-schema-temp.sql"
dbname=$1
newschema=$2
newsrid=$3

if [ -z "$dbname" || -z "$newschema" || -z "$newsrid" ]; then
  echo "Usage: $0 DATABASE NEW_SCHEMA NEW_SRID"
  exit
fi

# Dump minnesota schema to create DDL for new instance
pg_dump -Ucycling -n minnesota --schema-only $dbname > $SFILE
sed -i -e s/minnesota/$newschema/g -e s/26915/$newsrid/g $SFILE

psql -Upostgres $dbname < $SFILE

psql -Ucycling $dbname -c "
SET search_path = $newschema, public;

INSERT INTO geometry_columns (
  f_table_catalog,
  f_table_schema,
  f_table_name,
  f_geometry_column,
  coord_dimension,
  srid,
  type)
SELECT
  f_table_catalog,
  '$newschema',
  f_table_name,
  f_geometry_column,
  coord_dimension,
  '$newsrid',
  type
FROM geometry_columns
WHERE f_table_schema = 'minnesota';

INSERT INTO revision (id, timestamp, host) 
   VALUES (cp_rid_inf(), now(), '_DUMMY');
"

