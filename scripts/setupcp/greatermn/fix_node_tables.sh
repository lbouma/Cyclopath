#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script asynchronously rebuilds the node_* tables.
#
# You could just run node_cache_maker.py on its own to rebuild
# the node cache tables, but if you've got 100,000s of nodes and
# 1,000,000s of byways, you'll want to use this script to do the
# work in parallel... otherwise you'll be waiting for 1s of days.

# Usage: ./fix_node_tables.sh
#
# ./litemaint.sh '30 mins' '4 hours'
# ./fix_node_tables.sh > /ccp/var/log/daily/`date +%Y.%m.%d`.fix_node_tables.log 2>&1 &
#
# 2014.09.21: On Greater MN and MetC: Elapsed: 157.00 mins.

script_time_0=$(date +%s.%N)

# We'll split the work amongst multiple cores; choose how many to use.
# 2014.02.14: Runic has 24 cores, so... let's use half of 'em.
#CORE_COUNT=12
# Let's use more...
#  anecdotally, [lb] sees about 5.2 or 5.5 lps (loops per second) when
#  processing node_stack_ids for --populate-nodes, regardless of if its
#  one core or 8... but I haven't tested, ya know, like 32.
CORE_COUNT=17

#CCP_DATABASE=ccpv3_live
#CCP_DATABASE=ccpv3_lite
#CCP_DATABASE=ccpv3_demo
if [[ -z "$CCP_DATABASE" ]]; then
  echo "ERROR: Please set CCP_DATABASE to the database to 'fix'"
  exit 1
fi

CCP_BRANCHES=("Mpls-St. Paul" "Metc Bikeways 2012")

# NOTE: You need to set search_path in ~/.psqlrc with the same, and public.
#INSTANCE="minnesota"
if [[ -z "$INSTANCE" ]]; then
  echo "ERROR: Please set INSTANCE to db namespace (SET search_path TO ...)"
  exit 1
fi

cd /ccp/dev/cp_cron/scripts/setupcp/

todays_date=`date +%Y.%m.%d`

# *** STEP 1: Drop existing node_* tables and recreate 'em.

./node_cache_maker.py \
  --database ${CCP_DATABASE} \
  --create-tables

# *** STEP 2: Populate node_endpoint table.

if false; then

   # For Devs to cxpx for testing...
  ./node_cache_maker.py --instance-master
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset     0
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset   500
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset  1000
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset  1500
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset  2000
  ./node_cache_maker.py --populate-nodes --branch 0 \
    --instance-worker --items-limit 500 --items-offset  2500
  # etc...

  # You can also use nohup...
  nohup ./node_cache_maker.py --populate-nodes --branch "$branch_name" \
    --instance-worker --items-limit 25000 --items-offset 350000 \
    | tee /ccp/var/log/daily/2014.02.14.node_cache_make-worker-350.log 2>&1 &

else

  # Iterate over every branch...
  for arr_index in $(seq 0 $((${#CCP_BRANCHES[@]} - 1))); do

    # For cxpx testing:
    if false; then
      arr_index=0
      branch_name="Mpls-St. Paul"
      arr_index=1
      branch_name="Metc Bikeways 2012"
    fi
    #
    # But this is really what we want:
    branch_name=${CCP_BRANCHES[$arr_index]}
    echo "Processing branch: populate-nodes: $branch_name"

    # NOTE: Not using ${branch_name} because too lazy to convert spaces to
    #       underscores.
    log_file_base="/ccp/var/log/daily/${todays_date}.fix_nodes.${arr_index}"

    WAITPIDS=()
    time_0=$(date +%s.%N)

    # Start the so-called master instance that gets and sits on the rev. lock.
    # NOTE: Use --has-revision-lock because, if you've been a good dev. and
    #       have run litemaint.sh, then pyserver won't let you try to lock
    #       the revision table unless you're a local script deliberately
    #       trying to lock it.
    ./node_cache_maker.py \
        --database ${CCP_DATABASE} \
        --branch "$branch_name" \
        --instance-master \
        --has-revision-lock \
        -m "Reset node cache: --populate-nodes" \
        > ${log_file_base}-master.log 2>&1 &
    # Get the process ID of the last command (last/lastest pid)
    MASTER_PID="${!}"

    # 2014.02.14: Total nodes: 376688 distinct, non-null in geofeature
    if false; then
      # Explicitly set limit and offset.
      limit_size=25000
      last_offset=375000
    else
      # Otherwise, programmatically figure it out.
      sql_node_count="
        SELECT COUNT(*) FROM (
           SELECT DISTINCT (node_id) FROM (
              SELECT beg_node_id FROM ${INSTANCE}.geofeature
              UNION
                 SELECT fin_node_id FROM ${INSTANCE}.geofeature
              ) AS node_id
              WHERE node_id IS NOT NULL
           ) AS foo
           ;
        "
        number_nodes=$(psql -U postgres --no-psqlrc -d ${CCP_DATABASE} \
                            --tuples-only -c "$sql_node_count")
        echo "Node count: $number_nodes"
        # Find the page size limit according to the number of cores sacrificed.
        # Add one to adjust for possible floating point truncation.
        limit_size=$((($number_nodes / $CORE_COUNT) + 1))
        echo "Limit size: $limit_size"
        # Get the floor of the node count w.r.t. the limit value.
        last_offset=$((($number_nodes) / $limit_size * $limit_size))
        echo "Last offset: $last_offset"
    fi

    # 2014.02.14: Running 6 processes asynchronously on 25,000 nodes each
    #             takes about 1.25 hours.
    init_offset=0
    for seq_offset in $(seq $init_offset $limit_size $last_offset); do
      echo "On offset: $seq_offset"
      ./node_cache_maker.py \
        --database ${CCP_DATABASE} \
        --branch "$branch_name" \
        --populate-nodes \
        --instance-worker \
        --has-revision-lock \
        --items-limit $limit_size \
        --items-offset $seq_offset \
        > ${log_file_base}-worker-$seq_offset.log 2>&1 &
      WAITPIDS+=("${!}")
    done # loop over each limit/offset

    # 2014.02.21: Processing branch: populate-nodes: Mpls-St. Paul
    #             Node count:  376688
    #             Background tasks complete after 89.00 mins.
    #             Processing branch: populate-nodes: Metc Bikeways 2012
    #             Background tasks complete after 67.00 mins.

    # Wait for all children to finish, and then finalize the revision.
    printf "Waiting for background tasks to complete...\n"
    echo "WAITPIDS: ${WAITPIDS[*]}"
    #
    wait ${WAITPIDS[*]}
    #
    sleep 1
    #
    time_1=$(date +%s.%N)
    $DEBUG_TRACE && printf "Background tasks complete after %.2F mins.\n" \
      $(echo "(${time_1} - ${time_0}) / 60.0" | bc -l)

    # Ctrl-C the master thread
    if true; then
      # Get the process details, e.g.,
      # $USER $PID 0.1 0.0 158172 27408 pts/2 S 14:08 0:06 /usr/bin/python \
      #  ./node_cache_maker.py --instance-master
      proc_details=`ps aux \
                    | grep node_cache_maker \
                    | grep -- "--instance-master"`
      set -- junk $proc_details
      shift
      master_proc_pid=$2
      if [[ $MASTER_PID -ne $master_proc_pid ]]; then
        echo "WARNING: Unexpected Master PID: $MASTER_PID not $master_proc_pid"
      fi
      echo "Killing master process: PID $master_proc_pid"
      kill -s 2 $master_proc_pid
      # We probably don't need to sleep, but maybe commit takes a sec.
      sleep 1
    fi

  done # loop over each branch

fi # done with --populate-nodes

# *** STEP 3: Perform final two activities.

for arr_index in $(seq 0 $((${#CCP_BRANCHES[@]} - 1))); do

  # For cxpx testing:
  if false; then
    branch_name="Mpls-St. Paul"
    branch_name="Metc Bikeways 2012"
  fi
  #
  # But this is really what we want:
  branch_name=${CCP_BRANCHES[$arr_index]}
  echo "Processing branch: internals and routes: $branch_name"

  # NOTE: Not using ${branch_name} because too lazy to convert spaces to
  #       underscores.
  log_file_base="/ccp/var/log/daily/${todays_date}.fix_nodes.${arr_index}"

  # 2013.02.21: For Greater MN,         12.18 mins.
  # 2013.02.21: For Metc Bikeways 2012,  4.08 mins.
  ./node_cache_maker.py \
    --add-internals \
    --branch "$branch_name" \
    --has-revision-lock \
    -m "Reset node cache: --add-internals" \
    > ${log_file_base}-internals.log 2>&1 &

  # 2013.02.21: For Greater MN,          2.10 mins.
  # 2013.02.21: For Metc Bikeways 2012, 54.47 secs.
  ./node_cache_maker.py \
    --update-route \
    --branch "$branch_name" \
    --has-revision-lock \
    -m "Reset node cache: --update-route" \
    > ${log_file_base}-routes.log 2>&1 &

done

# *** STEP 4: Recreate the VIEWs that we dropped.

cd /ccp/dev/cp_cron/scripts/dev

# This won't work: --no-psqlrc... so ~/.psqlrc should specify the schemas.
psql -U cycling -d ${CCP_DATABASE} \
   < /ccp/dev/cp_cron/scripts/dev/convenience_views.sql

# *** STEP 5: Vacuum me maybe.

# MAYBE: vacuum...
if false; then
   psql -U postgres -d ${CCP_DATABASE} -c "VACUUM ANALYZE;"
fi

# *** Print elapsed time.

time_1=$(date +%s.%N)
printf "All done: Elapsed: %.2F mins.\n" \
  $(echo "($time_1 - $script_time_0) / 60.0" | bc -l)

# *** All done.

exit 0

