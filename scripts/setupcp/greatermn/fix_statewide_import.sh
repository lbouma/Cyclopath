#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script asynchronously fixes problems caused by the Statewide
# import. Namely, some line segments within the Metro area were
# duplicated, and existing line segments (created by users) outside
# of the Metro area conflicted with the new State data (e.g., someone
# added I-94 toward St. Cloud and Hwy 55 to the West and some communities
# thereabouts; and someone added roads and the Willard Munger trail to
# get to Duluth.

########################################################################

# This script was writ to run the import in a multi-thread fashion,
# but the bulk db import is pretty efficient. So just copy 'n paste
# commands instead.

exit 1

################################## COPY-N-PASTE EXECUTION
# STATEWIDE LINE SEGMENT FIXES

# 2014.04.09: Executed on server.

CCP_DATABASE=ccpv3_live
CCP_WORKING=/ccp/dev/cycloplan_live
PYSERVER_HOME=/ccp/dev/cycloplan_live/pyserver
SHP_SOURCE_DIR=/ccp/var/shapefiles/mn_cleanup
cd ${CCP_WORKING}/scripts/setupcp
./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --init-importer \
  --known-point-xy 480292.5 4980909.8 \
  --first-suspect ${FIRST_SUSPECT_SID} \
  --fix-silent-delete-issue \
  --use-old-stack-IDs-when-possible \
  2>&1 | tee ${SHP_SOURCE_DIR}/log-010-init-importer.log
#| tee ${SHP_SOURCE_DIR}/log-010-init-importer.log 2>&1 &

./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --instance-master \
  --has-revision-lock \
  -m "Fix Statewide import" \
  > ${SHP_SOURCE_DIR}/log-020-master.log 2>&1 &
# Get the process ID of the last command (last/lastest pid)
MASTER_PID=$!
echo "Started master script: PID: $MASTER_PID"

./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --try-matching \
  --first-suspect ${FIRST_SUSPECT_SID} \
  --has-revision-lock \
  --instance-worker
  > ${log_file_base}-worker-match.log 2>&1 &
  # See also:
  #  --show-conflations \
  #  --hide-fragments \

fst_offset=0
seq_limit=50000
consecutive_import () {
  for seq_offset in $(seq $fst_offset $seq_limit 500000); do
    #echo $seq_offset
    ./hausdorff_import.py \
      --database ${CCP_DATABASE} \
      --branch "Mpls-St. Paul" \
      --source-dir "${SHP_SOURCE_DIR}" \
      --process-edits \
      --merge-names \
      --friendly-names \
      --fix-gravel-unpaved-issue \
      --check-everything \
      --has-revision-lock \
      --instance-worker \
      --items-limit $seq_limit \
      --items-offset $seq_offset \
      | tee ${SHP_SOURCE_DIR}/log-040-process-edits-$seq_offset.log 2>&1 &
  done
  }

consecutive_import

kill -s 2 $master_proc_pid

################################## COPY-N-PASTE EXECUTION
# STATEWIDE REGIONS

# 2014.04.09: Executed on server.

# Run this on your development machine to do the preprocessing.

CCP_DATABASE=ccpv3_lite
CCP_WORKING=/ccp/dev/cp
PYSERVER_HOME=/ccp/dev/cp/pyserver
SHP_SOURCE_DIR=/ccp/var/shapefiles/statewide_regions
cd ${CCP_WORKING}/scripts/setupcp

# Export the Cyclopath regions first.
./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --export --item-type region 

# Put the Cyclopath and MnDOT files in the same directory and
# combine them, using the new MnDOT geometries for conflicts
# and deleting duplicates.
./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --init-importer \
  --import-fix-mndot-polies \
  --item-type region

# Copy the Prepared/ directory of Shapefiles to the server and run
# the import.
CCP_DATABASE=ccpv3_live
CCP_WORKING=/ccp/dev/cycloplan_live
PYSERVER_HOME=/ccp/dev/cycloplan_live/pyserver
SHP_SOURCE_DIR=/ccp/var/shapefiles/statewide_regions
cd ${CCP_WORKING}/scripts/setupcp
./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --import --item-type region \
  --check-everything \
  --changenote "Statewide counties, townships, and cities." \
  -U landonb --no-password

################################## COPY-N-PASTE EXECUTION
# GIA DATA BUG FIX

# 2014.04.09: Executed on server.

# The import script had a bug where the GIA record was not
# updated with the new item_versioned name. This fixed it.

$ psql -U cycling ccpv3_live
> begin;

> SELECT count(*) FROM group_item_access AS gia
  JOIN item_versioned AS iv ON (iv.system_id = gia.item_id)
  WHERE gia.name <> iv.name;

> UPDATE group_item_access AS gia SET name = iv.name
  FROM item_versioned AS iv WHERE gia.item_id = iv.system_id;

################################## END: COPY-N-PASTE EXECUTION
##############################################################

# Here's the original, multi-threaded script...

# *** Dev options.

DEBUG_TRACE=false

# FIXME: Set appropriately on runic:
CORE_COUNT=3
#CORE_COUNT=17

CCP_BRANCH="Mpls-St. Paul"

CCP_DATABASE=ccpv3_live
#CCP_DATABASE=ccpv3_lite
#CCP_DATABASE=ccpv3_demo
if [[ -z "$CCP_DATABASE" ]]; then
  echo "ERROR: Please set CCP_DATABASE to the database to 'fix'"
  exit 1
fi

SHP_SOURCE_DIR=/ccp/var/shapefiles/mn_cleanup
FIRST_SUSPECT_SID=2539702

# See also: --source-data, below; you'll want to list your source Shapefiles.

# *** Script setup.

#set -e

script_relbase=$(dirname $0)

source ${script_relbase}/../../util/ccp_base.sh

if [[ -z "$INSTANCE" ]]; then
  echo "ERROR: Please set INSTANCE to db namespace (SET search_path TO ...)"
  exit 1
fi

if [[ -z "$CCP_DB_NAME" ]]; then
  echo "ERROR: Please set CCP_DB_NAME"
  exit 1
fi

todays_date=`date +%Y.%m.%d`

log_file_base="/ccp/var/log/daily/${todays_date}.fix_statewide_import"

# *** STEP 0: Put the site into maintenance mode. Or get the prompts.

# DEVs: Do something like this before running the script:
#   cd $PYSERVER_HOME/../scripts
#   ./litemaint.sh '15 mins' '3 hours'
#   # and then wait 15 mins. for the maintenance window to open.

if [[ -e ${CP_MAINT_LOCK_PATH} ]]; then
  echo "The maint lock is already acquired: $CP_MAINT_LOCK_PATH"
  echo -n "Proceed anyway? (y/n) "
  read -a sure
  if [[ "$sure" != "y" ]]; then
    echo "Aborting."
    exit 1
  fi
fi

#CCP_DB_NAME=ccpv3_lite
in_maint_mode=$(
  psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
    -c "SELECT
          EXTRACT('epoch' FROM (value::TIMESTAMP - CURRENT_TIMESTAMP)) < 0
          FROM ${INSTANCE}.key_value_pair WHERE key = 'cp_maint_beg';" \
  2> /dev/null)
if [[ ${in_maint_mode} != 't' ]]; then
  echo "The maint mode window is not open (see key_value_pair.cp_maint_beg)"
  echo -n "Proceed anyway? (y/n) "
  read -a sure
  if [[ "$sure" != "y" ]]; then
    echo "Aborting."
    exit 1
  fi
fi

# *** STEP 1: See the import-fixxer-upper cache.

echo "======================================================================"
echo "Initializing the importer"
echo "======================================================================"

cd $PYSERVER_HOME/../scripts/setupcp
# NOTE: Not &'ing to background, unlike most other calls to hausdorff_import.
# 2014.03.17: Script completed in 3.14 mins.
./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --source-dir "${SHP_SOURCE_DIR}" \
  --init-importer \
  --known-point-xy 480292.5 4980909.8 \
  --first-suspect ${FIRST_SUSPECT_SID} \
  --fix-silent-delete-issue \
  --use-old-stack-IDs-when-possible \
  > ${log_file_base}-init-importer.log 2>&1

# *** STEP 2: Fetch the number of items to process.

echo "======================================================================"
echo "Counting features"
echo "======================================================================"

# Look for, e.g., "Feature Count: 289". The -so means "summary only".
process_count=$(
  /ccp/opt/gdal/bin/ogrinfo -so \
    ${SHP_SOURCE_DIR}/output/layer-process.shp "layer-process" \
    | grep "Feature Count" \
    | /bin/sed -r 's/(Feature Count: )//g')

echo "No. process features: $process_count"

suspect_count=$(
  /ccp/opt/gdal/bin/ogrinfo -so \
    ${SHP_SOURCE_DIR}/output/layer-suspect.shp "layer-suspect" \
    | grep "Feature Count" \
    | /bin/sed -r 's/(Feature Count: )//g')

echo "No. suspect features: $suspect_count"

audited_count=$(
  /ccp/opt/gdal/bin/ogrinfo -so \
    ${SHP_SOURCE_DIR}/output/layer-audited.shp "layer-audited" \
    | grep "Feature Count" \
    | /bin/sed -r 's/(Feature Count: )//g')

echo "No. audited features: $audited_count"

remains_count=$(
  /ccp/opt/gdal/bin/ogrinfo -so \
    ${SHP_SOURCE_DIR}/output/layer-remains.shp "layer-remains" \
    | grep "Feature Count" \
    | /bin/sed -r 's/(Feature Count: )//g')

echo "No. remains features: $remains_count"

# Find the page size limit according to the number of cores.
# Add one to adjust for possible floating point truncation.
process_limit_size=$((($process_count / $CORE_COUNT) + 1))
echo "Process Limit size: $process_limit_size"
# Get the floor of the count w.r.t. the limit value.
process_last_offset=$((
  $process_count / $process_limit_size * $process_limit_size))
echo "Process Last offset: $process_last_offset"

# Ditto for the items to conflate.
suspect_limit_size=$((($suspect_count / $CORE_COUNT) + 1))
echo "Suspect Limit size: $suspect_limit_size"
suspect_last_offset=$((
  $suspect_count / $suspect_limit_size * $suspect_limit_size))
echo "Suspect Last offset: $suspect_last_offset"

# *** STEP 3: Start the master process.

./hausdorff_import.py \
  --database ${CCP_DATABASE} \
  --branch "Mpls-St. Paul" \
  --instance-master \
  --has-revision-lock \
  -m "Fix Statewide import" \
  > ${log_file_base}-master.log 2>&1 &
# Get the process ID of the last command (last/lastest pid)
MASTER_PID=$!
echo "Started master script: PID: $MASTER_PID"

# *** STEP 4: Preprocess....

# Run hausdorff_import --try-matching on your own and edit the Shapefile.

# *** STEP 5: Start the worker threads.

WAITPIDS_EDITS=()
WAITPIDS_OTHER=()
time_0=$(date +%s.%N)

# Use one or more worked threads to process and save new and edited items.

# EXPLAIN: 2014.03.12: Record how long this takes...
seq_offset=0
init_offset=0
#process_limit_size=10
#process_limit_size=100
#process_limit_size=1000
#process_limit_size=10000
for seq_offset in $(seq $init_offset $process_limit_size \
                                     $process_last_offset); do
  echo "Starting Process-Edited instance: On offset: $seq_offset"
  ./hausdorff_import.py \
    --database ${CCP_DATABASE} \
    --branch "Mpls-St. Paul" \
    --source-dir "${SHP_SOURCE_DIR}" \
    --process-edits \
    --merge-names \
    --friendly-names \
    --fix-gravel-unpaved-issue \
    --check-everything \
    --instance-worker \
    --has-revision-lock \
    --items-limit $process_limit_size \
    --items-offset $seq_offset \
    > ${log_file_base}-worker-edits-$seq_offset.log 2>&1 &
  WAITPIDS_EDITS+=("${!}")
done # loop over each limit/offset

# *** STEP 6: Wait.

printf "Waiting for background editing tasks to complete...\n"
echo "WAITPIDS_EDITS: ${WAITPIDS_EDITS[*]}"
#
wait ${WAITPIDS_EDITS[*]}
#
sleep 1
#
time_1=$(date +%s.%N)
$DEBUG_TRACE && printf "Background editing tasks complete after %.2F mins.\n" \
  $(echo "(${time_1} - ${time_0}) / 60.0" | bc -l)

#   # *** STEP 7: Apply deleted items' attributes to reference items.
#   
#   time_0=$(date +%s.%N)
#   
#   # Use just one worked thread to process deleted items that
#   # specifically referenced another item.
#   
#   # EXPLAIN: 2014.03.12: Record how long this takes...
#   echo "Starting cleanup of deleted duplicates..."
#   ./hausdorff_import.py \
#     --database ${CCP_DATABASE} \
#     --branch "Mpls-St. Paul" \
#     --source-dir "${SHP_SOURCE_DIR}" \
#     --finalize-edits \
#     --has-revision-lock \
#     > ${log_file_base}-edits-finalize-$seq_offset.log 2>&1 &
#   WAITPIDS_OTHER+=("${!}")
#   
#   # *** STEP 8: Wait again.
#   
#   printf "Waiting for other background tasks to complete...\n"
#   echo "WAITPIDS_OTHER: ${WAITPIDS_OTHER[*]}"
#   #
#   wait ${WAITPIDS_OTHER[*]}
#   #
#   sleep 1
#   #
#   time_1=$(date +%s.%N)
#   $DEBUG_TRACE && printf "Background tasks complete after %.2F mins.\n" \
#     $(echo "(${time_1} - ${time_0}) / 60.0" | bc -l)

# *** STEP 9: Cleanup/commit changes.

# Ctrl-C the master thread
if true; then
  # Get the process details, e.g.,
  # $USER $PID 0.1 0.0 158172 27408 pts/2 S 14:08 0:06 /usr/bin/python \
  proc_details=`ps aux \
                | grep fix_statewide_import \
                | grep -- "--instance-master"`
  set -- junk $proc_details
  shift
  master_proc_pid=$2
  if [[ $MASTER_PID -ne $master_proc_pid ]]; then
    echo "WARNING: Unexpected Master PID: $MASTER_PID not $master_proc_pid"
  fi
  # kill -s 2 10207
  echo "Killing master process: PID $master_proc_pid"
  kill -s 2 $master_proc_pid
  # We probably don't need to sleep, but maybe commit takes a sec.
  sleep 1
fi

# *** STEP 10: All done.

script_finished_print_time

exit 0

