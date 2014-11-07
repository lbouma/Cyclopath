#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: analyze.sh DB_NAME OUTPUT_DIR

DEBUG_TRACE=false
#DEBUG_TRACE=true

# ***

script_relbase=$(dirname $0)
source ${script_relbase}/../../util/ccp_base.sh

# ***

# Exit on error
set -e
umask 0003

# ***

scripts_dir=$(readlink -f $script_relbase) # convert to absolute path

PSQL_WRAP=/ccp/dev/cp_cron/scripts/util/psql_wrap.sh

db_name=$1

# Send pushd output to /dev/null so we don't get cron email.
pushd $2 &> /dev/null

for i in $scripts_dir/*.sql; do

  time_sub_0=$(date +%s.%N)
  $DEBUG_TRACE && echo "Running SQL on: $i"

  ${PSQL_WRAP} $i $db_name -qtA -F' '

  time_sub_1=$(date +%s.%N)
  $DEBUG_TRACE && printf "Ran SQL in: %.2F mins.\n" \
    $(echo "($time_sub_1 - $time_sub_0) / 60.0" | bc -l)

done

# pushd /ccp/var/log/statistics
# scripts_dir=/ccp/dev/cp_cron/scripts/daily/usage/


for i in $scripts_dir/*.gnuplot; do

  time_sub_0=$(date +%s.%N)
  $DEBUG_TRACE && echo "Running Gnuplot on: $i"

  gnuplot $i

  time_sub_1=$(date +%s.%N)
  $DEBUG_TRACE && printf "Ran Gnuplot in: %.2F mins.\n" \
    $(echo "($time_sub_1 - $time_sub_0) / 60.0" | bc -l)

done

# 2013.05.24: For Apache:
/bin/chmod 664 *.png

popd &> /dev/null

# ===========================================================================
# Print elapsed time

script_finished_print_time

# ===========================================================================
# All done!

exit 0

