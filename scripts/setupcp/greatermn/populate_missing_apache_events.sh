#!/bin/bash

# ===========================================================================
# Redo nine months of missing apache_event logs.

# See Bug nnnn: The apache2sql has been not working for a long period
# of time. This happened a few years ago and the event table was rebuilt
# during the CcpV1->V2 update. And now it happened again, between
# January, 2014, and September. The /ccp/var/log/daily logfile shows the
# error, but for whatever reason cron was not complaining about the error!

__USAGE__="

  cd /ccp/dev/cycloplan_live
  setcp
  cd scripts/setupcp/greatermn

  nohup ./populate_missing_apache_events.sh \
  | tee populate_missing_apache_events.log 2>&1 &

  # Note that the tee'd log will be empty unless DEBUG_TRACE is true.

  # You can tail the apache2sql scripts as they add to their log file:
  tail -F /ccp/var/log/daily/2014.01-09.apache2sql-mn.log
"

# NOTE: This script takes a while.

# ============================================================================
# *** Debug options

DEBUG_TRACE=false
# Set this to true if you want verbose output.
#DEBUG_TRACE=true

# *** Default debug options (all 0/null/zip/nada)

# DEVS: Do not edit this section. Uncomment lines in the next section.
SKIP_APACHE_EVENT_RELOAD=0

# *** Debug overrides.

#SKIP_APACHE_EVENT_RELOAD=1

# ============================================================================

# DB_INSTANCES[0]="minnesota mn"
# DB_INSTANCES[1]="colorado co"
#DB_INSTANCES=("minnesota mn" "colorado co")
DB_INSTANCES=("minnesota mn")
CCP_DB_NAME="ccpv3_live"

CCP_WORKING=/ccp/dev/cycloplan_live

export PYSERVER_HOME=${CCP_WORKING}/pyserver

. $CCP_WORKING/scripts/util/ccp_base.sh

if [[ -z "${CCP_LOG}" ]]; then
  echo "Missing: CCP_LOG"
  exit 1
fi
if [[ -z "${CCP_LOG_DAILY}" ]]; then
  echo "Missing: CCP_LOG_DAILY"
  exit 1
fi

archive_dir=${CCP_LOG}/apache2/archive_2014_rescan_dupls

# ============================================================================

# The fcn. is mostly copied from /ccp/bin/ccpdev/daily/upgrade_ccpv1-v2.sh

run_apache2sql_instance () {

  db_instance=$1
  db_nickname=$2

  if [[ -z "${db_instance}" ]]; then
    echo "Please specify the instance."
    exit 1
  fi

  # Ignore all but 'minnesota' instance (i.e., 'colorado' isn't running).
  if [[ "${db_instance}" != "minnesota" ]]; then
    $DEBUG_TRACE && echo \
      "run_apache2sql_instance: skipping uninteresting inst: ${db_instance}"
    return 0
  fi

  export INSTANCE=${db_instance}

  SETPATH="SET search_path TO ${db_instance}, public;"

  #debug_skip_copy=false
  # I ran this manually, so:
  debug_skip_copy=true

  if ! ${debug_skip_copy}; then

    $DEBUG_TRACE && echo ""
    $DEBUG_TRACE && echo \
      "populate_missing_apache_events: Copying access logs from local dir"

    if [[ -d ${archive_dir} ]]; then
      /bin/rm -rf ${archive_dir}.last
      /bin/mv ${archive_dir} ${archive_dir}.last
    fi
    /bin/mkdir -p ${archive_dir}

    /bin/cp -ra ${CCP_LOG}/apache2/access.log ${archive_dir}
    /bin/cp -ra ${CCP_LOG}/apache2/access.log.1 ${archive_dir}
    /bin/cp -ra ${CCP_LOG}/apache2/access.log.2.gz ${archive_dir}
    /bin/cp -ra ${CCP_LOG}/apache2/archive/access.log/*.gz ${archive_dir}

  fi

  # 2014.09.17: Look for the missing dates.
  __2014_09_17_some_sqsl__="

  SELECT DISTINCT event_date FROM (
    SELECT DATE_TRUNC('DAY', timestamp_tz) AS event_date
      FROM apache_event
     ORDER BY timestamp_tz DESC
    ) AS foo
  ORDER BY event_date DESC
  ;

       event_date       
------------------------
 2014-09-17 00:00:00-05
 2014-09-16 00:00:00-05
 2014-09-15 00:00:00-05
 2014-09-14 00:00:00-05
 2014-09-13 00:00:00-05
 2014-09-12 00:00:00-05
 2014-09-11 00:00:00-05
 2014-09-10 00:00:00-05
### MISSING almost eight months ##########
 2014-01-24 00:00:00-06
 2014-01-23 00:00:00-06
 ...
 2013-11-01 00:00:00-05
### MISSING one month ##########
 2013-09-23 00:00:00-05
 ...
 2008-05-07 00:00:00-05

  -- Too slow:
  SELECT timestamp_tz FROM (
    SELECT DATE_TRUNC('DAY', timestamp_tz) AS event_date
           , timestamp_tz
      FROM apache_event
     WHERE DATE_TRUNC('DAY', timestamp_tz)
           IN (-- First missing window:
               '2014-09-10 00:00:00-05',
               '2014-01-23 00:00:00-06',
               -- Second missing window:
               '2013-11-01 00:00:00-05',
               '2013-09-23 00:00:00-05')
     ORDER BY timestamp_tz DESC
    ) AS foo
  ORDER BY timestamp_tz DESC
  ;

  -- Try instead:

  SELECT timestamp_tz
    FROM apache_event
   WHERE timestamp_tz < '2014-09-11 00:00:00-05'
     AND timestamp_tz > '2014-09-09 00:00:00-05'
   ORDER BY timestamp_tz DESC
   ;
IGNORE EVENTS WITH DATE EQUAL TO OR AFTER:
2014-09-10 07:40:29-05

  SELECT timestamp_tz
    FROM apache_event
   WHERE timestamp_tz < '2014-01-25 00:00:00-06'
     AND timestamp_tz > '2014-01-23 00:00:00-06'
   ORDER BY timestamp_tz DESC
   ;
IGNORE EVENTS WITH DATE EQUAL TO OR BEFORE:
 2014-01-24 01:34:43-06

  SELECT timestamp_tz
    FROM apache_event
   WHERE timestamp_tz < '2013-11-02 00:00:00-05'
     AND timestamp_tz > '2013-10-31 00:00:00-05'
   ORDER BY timestamp_tz DESC
   ;
IGNORE EVENTS WITH DATE EQUAL TO OR AFTER:
 2013-11-01 08:02:19-05

  SELECT timestamp_tz
    FROM apache_event
   WHERE timestamp_tz < '2013-09-24 00:00:00-05'
     AND timestamp_tz > '2013-09-22 00:00:00-05'
   ORDER BY timestamp_tz DESC
   ;
IGNORE EVENTS WITH DATE EQUAL TO OR BEFORE:
 2013-09-23 01:40:31-05

landonb@runic:archive_2014_rescan_dupls$ p
/ccp/var/log/apache2/archive_2014_rescan_dupls
landonb@runic:archive_2014_rescan_dupls$ ll
total 406M
drwxrws--x 2 landonb  grplens 4.0K 2014-09-17 16:04 ./
drwxrwsr-x 7 www-data grplens 4.0K 2014-09-17 15:36 ../
-rw-r--r-- 1 landonb  grplens 4.9M 2014-09-17 16:06 2013-10-01.gz <-- EDITED
-rw-r--r-- 1 landonb  grplens 7.8M 2013-11-01 08:01 2013-10-16.gz
-rw-r--r-- 1 landonb  grplens 106M 2013-11-18 07:46 2013-11-01
-rw-r--r-- 1 landonb  grplens 1.4M 2014-09-17 15:59 2014-01-27.gz <-- EDITED
-rw-r--r-- 1 landonb  grplens 7.9M 2014-03-02 07:56 2014-02-16.gz
-rw-r--r-- 1 landonb  grplens 7.5M 2014-03-15 08:04 2014-03-02.gz
-rw-r--r-- 1 landonb  grplens 6.8M 2014-03-30 07:58 2014-03-15.gz
-rw-r--r-- 1 landonb  grplens 7.1M 2014-04-14 07:36 2014-03-30.gz
-rw-r--r-- 1 landonb  grplens 7.3M 2014-04-23 07:39 2014-04-14.gz
-rw-r--r-- 1 landonb  grplens 8.3M 2014-04-30 07:38 2014-04-23.gz
-rw-r--r-- 1 landonb  grplens 7.2M 2014-05-07 07:40 2014-04-30.gz
-rw-r--r-- 1 landonb  grplens 7.1M 2014-05-17 08:05 2014-05-07.gz
-rw-r--r-- 1 landonb  grplens 8.0M 2014-05-26 07:36 2014-05-17.gz
-rw-r--r-- 1 landonb  grplens 7.3M 2014-06-04 07:45 2014-05-26.gz
-rw-r--r-- 1 landonb  grplens 7.4M 2014-06-14 07:37 2014-06-04.gz
-rw-r--r-- 1 landonb  grplens 8.2M 2014-06-22 08:05 2014-06-14.gz
-rw-r--r-- 1 landonb  grplens 7.6M 2014-06-30 07:56 2014-06-22.gz
-rw-r--r-- 1 landonb  grplens 8.0M 2014-07-07 08:00 2014-07-01.gz
-rw-r--r-- 1 landonb  grplens 7.6M 2014-07-14 07:44 2014-07-07.gz
-rw-r--r-- 1 landonb  grplens 8.0M 2014-07-22 07:56 2014-07-14.gz
-rw-r--r-- 1 landonb  grplens  12M 2014-07-26 07:41 2014-07-22.gz
-rw-r--r-- 1 landonb  grplens 8.7M 2014-07-28 08:01 2014-07-26.gz
-rw-r--r-- 1 landonb  grplens  14M 2014-07-30 07:55 2014-07-28.gz
-rw-r--r-- 1 landonb  grplens 9.0M 2014-08-02 07:43 2014-07-30.gz
-rw-r--r-- 1 landonb  grplens 9.8M 2014-08-05 07:38 2014-08-02.gz
-rw-r--r-- 1 landonb  grplens 8.7M 2014-08-08 07:42 2014-08-05.gz
-rw-r--r-- 1 landonb  grplens 9.3M 2014-08-11 07:49 2014-08-08.gz
-rw-r--r-- 1 landonb  grplens 8.5M 2014-08-14 07:56 2014-08-11.gz
-rw-r--r-- 1 landonb  grplens 9.1M 2014-08-17 07:47 2014-08-14.gz
-rw-r--r-- 1 landonb  grplens 8.4M 2014-08-21 08:01 2014-08-17.gz
-rw-r--r-- 1 landonb  grplens  11M 2014-08-25 07:41 2014-08-21.gz
-rw-r--r-- 1 landonb  grplens 9.8M 2014-08-29 07:49 2014-08-25.gz
-rw-r--r-- 1 landonb  grplens 9.7M 2014-09-02 07:44 2014-08-29.gz
-rw-r--r-- 1 landonb  grplens 8.9M 2014-09-06 07:41 2014-09-02.gz
-rw-r--r-- 1 landonb  grplens  11M 2014-09-10 07:40 2014-09-06.gz
-rw-r--r-- 1 landonb  grplens  11M 2014-09-14 07:53 2014-09-10.gz
-rw-rw-r-- 1 landonb  grplens  11M 2014-09-10 07:40 access.log.2.gz

  "

  # Process each file -- unpack it, maybe, and parse into apache_event table.
  #
  #echo "files: `/bin/ls`"
  #echo "pwd: `/bin/pwd`"

  #$DEBUG_TRACE && echo ""
  #$DEBUG_TRACE && echo "2014.09.17: ?? mins. (runic)"

  LOG_FILE=${CCP_LOG_DAILY}/2014.01-09.apache2sql-${db_nickname}.log
  echo "" > ${LOG_FILE}

  $DEBUG_TRACE && echo ""

  cd ${archive_dir}

  #for fn in *; do
  #for fn in `ls * | sort`; do
  # NOTE: Skipping all error.* and access-co.*.
  # Do a simple sort so the loop is the same between runs, to help with
  # debugging (I'd sort by date, but ccp doesn't preserve date).
  #for fn in `ls access.* | sort`; do
  for fn in `ls -t`; do

    access_log=""

    #$DEBUG_TRACE && echo ""

    cd ${archive_dir}

    # This matches, e.g., access.log.2.gz, access.log.12.gz, etc.
    #is_gz=$(echo $fn | grep "^access.log\(.[[:digit:]]\+\).gz$")
    is_gz=$(echo $fn | grep "^.*.gz$")
    # grep sets $?, but we can check stdout, too.
    if [[ -n "${is_gz}" ]]; then
      # Unpack the archive first. Note that gunzip generally replaces the
      # source, so send to output to a file instead.
      # Replace archive with unarchive: gunzip ${fn}
      #$DEBUG_TRACE && echo "Unpacking archive: ${fn}"
      access_log=$(echo $fn | sed "s/.gz$//")
      gunzip -c ${fn} > ${access_log}
      exit_on_last_error $? "gunzip: -c ${fn}"
    else
      # MAYBE: Process access-co? Who cares.
      #is_aclg=$(echo $fn | grep "^access-co.log(?.\d+)$")
      # This matches, e.g., access.log, access.log.1, access.log.12, etc.
      is_aclg=$(echo $fn | grep "^access.log\(.[[:digit:]]\+\)\?$")
      is_ungz=$(echo $fn | grep "^[-[:digit:]]\+$")
      if [[ -n "${is_aclg}" ]]; then
        #$DEBUG_TRACE && echo "Found logfile: ${fn}"
        access_log=$fn
      elif [[ -n "${is_ungz}" ]]; then
        #$DEBUG_TRACE && echo "Found logfile: ${fn}"
        access_log=$fn
      else
        #$DEBUG_TRACE && echo "Skipping non-'access' logfile or archive: ${fn}"
        # This is an unexpected path.
        echo "ERROR: Unexpected file found: ${archive_dir}/${fn}"
        echo "ERROR: Unexpected code path. Verify for-loop's ls | sort, above."
        exit 1
      fi
    fi

    if [[ -n "${access_log}" ]]; then

      logfile_path=${archive_dir}/${access_log}

      # This is too chatty:
      #  $DEBUG_TRACE && echo -n "Parsing: ${logfile_path}..."

      # 2013.08.20: Huh? Permission denied?
      # ERRR     apache2sql.py  #  Unable to open logfile:
      # /ccp/var/log/apache2/known_issues.log: [Errno 13] Permission denied...
      #  sudo /bin/chmod 664 /ccp/var/log/apache2/known_issues.log
      #  sudo /bin/chmod 664 /ccp/var/log/apache2/access.log
      #  sudo /bin/chmod 664 /ccp/var/log/apache2/error.log
      # 2013.08.21: [lb] changed /etc/logrotate.d/apache2 to create 664, so
      #             this should be fixed.

      cd ${CCP_WORKING}/scripts/daily
      #LOG_FILE=${CCP_LOG_DAILY}/v1-v2u.apache2sql-${db_nickname}-${access_log}.log
      #$DEBUG_TRACE && echo -n "Partially populating the apache2sql table... "
      time_sub_sub_0=$(date +%s.%N)
      #$DTRACE_PIDS && echo "WAITPIDS=${WAITPIDS[*]} / beg: `date +%s.%N`"
      __2014_09_17__1_="
      cd /ccp/dev/cycloplan_live/scripts/daily
      /ccp/dev/cycloplan_live/scripts/daily/apache2sql.py \
       --access-log /ccp/var/log/apache2/archive_2014_rescan_dupls/2013-11-01 \
       --skip-date-check --skip-analyze

      Or even:

      echo PYSERVER_HOME=${CCP_WORKING}/pyserver \
        INSTANCE=${db_instance} \
        PYTHONPATH=${ccp_python_path} \
          ${CCP_WORKING}/scripts/daily/apache2sql.py \
          --access-log ${logfile_path} \
          --skip-date-check \
          --skip-analyze ${LOG_FILE}

      PYSERVER_HOME=${CCP_WORKING}/pyserver \
        INSTANCE=${db_instance} \
        PYTHONPATH=${ccp_python_path} \
          ${CCP_WORKING}/scripts/daily/apache2sql.py \
          --help >> ${LOG_FILE} 2>&1

      # TESTING
      if false; then

      "

      PYSERVER_HOME=${CCP_WORKING}/pyserver \
        INSTANCE=${db_instance} \
        PYTHONPATH=${ccp_python_path} \
          ${CCP_WORKING}/scripts/daily/apache2sql.py \
          --access-log ${logfile_path} \
          --skip-date-check \
          --skip-analyze \
        >> ${LOG_FILE} 2>&1
      #  > ${LOG_FILE} 2>&1
      #check_prev_cmd_for_error $? ${LOG_FILE}
      exit_on_last_error $? "apache2sql.py: --access-log ${logfile_path}"
      # This is too chatty:
      #  time_sub_sub_1=$(date +%s.%N)
      #  $DEBUG_TRACE && printf " %.2F secs.\n" \
      #      $(echo "($time_sub_sub_1 - $time_sub_sub_0) / 1.0" | bc -l)

      __2014_09_17__2_="
      # TESTING
      fi
      "

      # FIXME: Can we do all these in parallel?
      #--logfile_path ... \
      #&
      #WAITPIDS+=("${!}")
      ## No extra log: Skipping: WAITLOGS+=("${LOG_FILEPATH}")
      ##   (So, if apache2sql.py says anything, it gets interleaved herein.)
      #$DTRACE_PIDS && echo "WAITPIDS=${WAITPIDS[*]} / end: `date +%s.%N`"

      # Cleanup the access log if we unpacked/created it.
      if [[ -n "${is_gz}" ]]; then
        /bin/rm -f ${logfile_path}
      fi

    else
      # This is unexpected. The for loop above only gets file we expect to have
      # to process.
      echo "ERROR: Unexpected code path. Verify for-loop's ls | sort, above."
      exit 1
    fi

  done

  check_prev_cmd_for_error 0 ${LOG_FILE}
}

if [[ ${SKIP_APACHE_EVENT_RELOAD} -eq 0 ]]; then
  set +e # Don't exit on error
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Running apache event reload..."
  for arr_index in ${!DB_INSTANCES[*]}; do
    run_apache2sql_instance ${DB_INSTANCES[$arr_index]}
    ON_DB_INSTANCE=$((ON_DB_INSTANCE + 1))
  done
  $DEBUG_TRACE && echo `date`
  $DEBUG_TRACE && echo ""
  set -e # Exit on error

# FIXME: Vacuum analyze... or don't, because db_load will do it?

fi

# ===========================================================================
# Print elapsed time

script_finished_print_time

# ===========================================================================
# All done!

exit 0

