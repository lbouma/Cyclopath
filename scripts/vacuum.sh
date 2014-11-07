#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script runs VACUUM ANALYZE on everything but the apache_event table.

VERBOSE=""
#VERBOSE="VERBOSE"

script_relbase=$(dirname $0)

# Load ${CCP_DB_NAME}
PYSERVER_HOME=
. ${script_relbase}/util/ccp_base.sh

if [[ -z "${CCP_DB_NAME}" ]]; then
  echo "Unable to determine name of database from ${PYSERVER_HOME}/CONFIG."
  exit
fi

for table in \
  $(psql -U postgres ${CCP_DB_NAME} --tuples-only --no-align -c \
    "SELECT schemaname || '.' || tablename \
     FROM pg_tables \
     WHERE tablename \
       NOT IN ( \
         'apache_event' \
       )\
    "); do
  # psql prints 'VACUUM' once for each table, so we should at least say
  # something, too.
  echo "Vacuuming ${CCP_DB_NAME}: ${table}"
  psql -U postgres ${CCP_DB_NAME} -c "VACUUM ${VERBOSE} ANALYZE ${table}"
done

exit 0

