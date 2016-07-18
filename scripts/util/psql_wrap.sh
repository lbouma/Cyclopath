#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Wrapper for psql since we can't specify schema names via the prompt.
# Also includes some basic sanity checks.

SCRIPT=$1
DBNAME=$2

# Make sure at least 2 arguments were provided
if [[ -z "$SCRIPT" || -z "$DBNAME" ]]; then
  echo "ERROR: Usage: $0 SQL_SCRIPT DATABASE [arguments to psql]"
  exit 1
fi
shift 2

# Make sure script exists
if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist or is not a regular file."
  exit 1
fi

# Make sure INSTANCE is set
if [[ -z "$INSTANCE" ]]; then
  echo "ERROR: Please set the INSTANCE environment variable (psql_wrap)."
  exit 1
fi

# Make sure INSTANCE schema exists in this database
SETPATH="SET search_path TO $INSTANCE, public;"
if ! psql -U cycling -d $DBNAME -c "$SETPATH" -q; then
  # psql will print it's own error message
  # echo "Unable to connect to $DBNAME and/or load the $INSTANCE schema."
  exit
fi

# Run the script by piping it to psql
(echo $SETPATH && cat $SCRIPT) | psql -U cycling -d $DBNAME --no-psqlrc "$@"

