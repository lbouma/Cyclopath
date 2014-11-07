#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# ABOUT:
#
# Run this script to create and install TileCache and MapServer
# config files and to generate cached tiles for specific Cyclopath
# installations and branches.
#
# This script is somewhat multi-processor aware/friendly.
#
# This script should be run by the apache/www-data user.

# SETUP_NOTES:
#
#    Schedule cron to run the wrapper script, check_cache_now.sh
#
#    Pass this script a list of instances and branches to process.
#    See further down for an example.

# ===========================================================================
# *** Debug options

DEBUG_TRACE=false
# DEVS: Uncomment this if you want a cron email.
#DEBUG_TRACE=true

DTRACE_PIDS=false
#DTRACE_PIDS=true

# 2013.05.17: Start being verbose whenever we load from scratch.
ALWAYS_TRACE_WHEN_FRESH=true
#ALWAYS_TRACE_WHEN_FRESH=false

SKIP_CONSUME_FRESH_DB=false
SKIP_REVID_CHECK=false
SKIP_CONFIG_FILES=false
SKIP_REPORT_SIZES=false


# FIXME, or maybe just NOTICE: The cluster cache takes a day to build
#        from scratch: which doesn't seem like something we want to
#        do very often... and this file is called from cron...
SKIP_TILECACHE_CACHE=false
SKIP_TILECACHE_TILES=false

# DEVS: Uncomment these if you want 
#SKIP_CONSUME_FRESH_DB=true
#SKIP_REVID_CHECK=true
#SKIP_CONFIG_FILES=true
#SKIP_REPORT_SIZES=true
#SKIP_TILECACHE_CACHE=true
#SKIP_TILECACHE_TILES=true

# ***

if    $SKIP_REVID_CHECK \
   || $SKIP_CONFIG_FILES \
   || $SKIP_REPORT_SIZES \
   || $SKIP_TILECACHE_CACHE \
   || $SKIP_TILECACHE_TILES \
  ; then
    echo ""
    echo "*****************************************"
    echo "*                                       *"
    echo "*    WARNING: Debug switches enabled    *"
    echo "*                                       *"
    echo "*****************************************"
    echo ""
fi

# ===========================================================================
# *** Test sandbox

__usage_examples__='

cd $cp/mapserver
rmdir apache_check_cache_now.sh-lock 2&>1 /dev/null; \
sudo -u $httpd_user \
   INSTANCE=minnesota \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   ./apache_check_cache_now.sh

# DEVS: To kill this script, and tilecache_update, and tilecache_seed, call:
./kill_cache_check.sh

# DEVS: Test from apache account.

sudo su - $httpd_user

cd /ccp/dev/cp/mapserver
INSTANCE=minnesota \
   PYTHONPATH=/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.6/site-packages:/ccp/opt/gdal/lib/python2.6/site-packages \
   PYSERVER_HOME=/ccp/dev/cp/pyserver \
  ./apache_check_cache_now.sh
Maybe:
--force

cd /ccp/dev/cp/mapserver
INSTANCE=minnesota \
   PYTHONPATH=/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.6/site-packages:/ccp/opt/gdal/lib/python2.6/site-packages \
   PYSERVER_HOME=/ccp/dev/cp/pyserver \
  ./tilecache_update.py \
    --branch Metc Bikeways 2012 \
    --changed --cyclopath-cache

sudo su - $httpd_user
cd /ccp/dev/cp/mapserver
./check_cache_now.sh

cd /ccp/var/tilecache-cache
nohup tar -cvzf cycloplan_live.tar.gz cycloplan_live | tee tar-cycloplan_live.log 2>&1 &


sudo su - $httpd_user
/bin/bash 
cd /ccp/dev/cp_v1v2-tcc/mapserver
./check_cache_now.sh

export EDITOR=/usr/bin/vim.basic
crontab -e

cd /ccp/var/tilecache-cache
tar -xzf cp_v1v2-tcc.tar.gz
mv cp_v1v2-tcc cycloplan_live
cd cycloplan_live
addr_and_port=ccpv3
cat tilecache.cfg \
  | /bin/sed -r \
   "s/url=http:\/\/[-_.:a-zA-Z0-9]+/url=http:\/\/${addr_and_port}/" \
  > tilecache.new
/bin/mv -f tilecache.new tilecache.cfg
fixperms --public ../cycloplan_live/
re
'

# ===========================================================================
# Utility fcns. and vars.

# NOTE: Setting PYSERVER_HOME relative to ccp_base.sh.
#PYSERVER_HOME=../../pyserver
# On second thought, make ccp_base.sh find PYSERVER_HOME, so it's set absolute.
PYSERVER_HOME=
source ../scripts/util/ccp_base.sh

if [[ -z "${CCP_WORKING}"
      || -z "${PYSERVER_HOME}"
      || -z "${CCP_INSTANCE}"
      || -z "${CCP_DB_NAME}"
      ]]; then
  echo "ERROR: Missing CCP_WORKING (${CCP_WORKING})
               and/or PYSERVER_HOME (${PYSERVER_HOME})
               and/or CCP_INSTANCE (${CCP_INSTANCE})
               and/or CCP_DB_NAME (${CCP_DB_NAME}).
               "
  exit 1
fi

# ===========================================================================
# *** Make input back into array, being smart about whitespace.

# Set the shell's Internal Field Separator to null.  Do this or
# whitespace will delimit things on the command line you put in
# quotes.
OLD_IFS=$IFS
IFS=''

CCP_INSTANCE_BRANCHES=()
while [[ "$1" != "" ]]; do
  CCP_INSTANCE_BRANCHES+=($1)
  shift
done

# Reset IFS to default.
IFS=$OLD_IFS

#echo "CCP_INSTANCE_BRANCHES[3] = " ${CCP_INSTANCE_BRANCHES[3]}

# Bash indexed arrays are always delimited by spaces so we put the
# branch last so we can coalesce it back together later with $*.
#
# Def'n: INSTANCE, INSTANCE___DEVPATH NICKNAME Full Branch Name in Database
if [[ $CCP_INSTANCE_BRANCHES = '' ]]; then
  echo "WARNING: Deprecated: You should specify CCP_INSTANCE_BRANCHES" \
       "in check_cache_now.sh"
  CCP_INSTANCE_BRANCHES=(
    "minnesota" "Minnesota"
    "minnesota" "Metc Bikeways 2012"
    );
fi
ccpsb_cols_per_row=2
ccp_number_servers=$((${#CCP_INSTANCE_BRANCHES[@]} / $ccpsb_cols_per_row))

#echo "ccpsb_cols_per_row = $ccpsb_cols_per_row"
#echo "CCP_INSTANCE_BRANCHES[3] = ${CCP_INSTANCE_BRANCHES[3]}"
#echo "ccp_number_servers = $ccp_number_servers"
#exit 0

if [[ ${#CCP_INSTANCE_BRANCHES[*]} -eq 0 ]]; then
  echo ""
  echo "==============================================="
  echo "WARNING: Nothing to do: No databases specified."
  echo "==============================================="
  echo ""
fi

# ===========================================================================
# *** Local machine configuration

CCP_LOG_CKCACHE=${CCP_LOG_DAILY}/cache
/bin/mkdir -p ${CCP_LOG_CKCACHE}
/bin/chmod 2775 ${CCP_LOG_CKCACHE}

CCP_ZIP_CKCACHE=${CCP_LOG_DAILY}/cache_
/bin/mkdir -p ${CCP_ZIP_CKCACHE}
/bin/chmod 2775 ${CCP_ZIP_CKCACHE}

# 2013.05.19: Not sure about this... I think dont_exit_on_error should be set.
dont_exit_on_error=1

# ===========================================================================
# Lock management helpers

# Don't unlock what we haven't locked.
SKIP_UNLOCK_CHECK_CACHE_NOW_LOCKDIR=1
SKIP_UNLOCK_UPGRADE_DUMPDIR=1
SKIP_UNLOCK_CHECK_CACHE_NOW_DUMPDIR=1

do_unlock_dump_locks () {
  # NOTE: Order here is important. Do this in the reverse order that you got
  #       the locks.
  if [[ ${SKIP_UNLOCK_CHECK_CACHE_NOW_DUMPDIR} -eq 0 ]]; then
    /bin/rmdir "${CHECK_CACHE_NOW_DUMPDIR}-${script_name}" &> /dev/null
    /bin/rmdir "${CHECK_CACHE_NOW_DUMPDIR}" &> /dev/null
    SKIP_UNLOCK_CHECK_CACHE_NOW_DUMPDIR=1
  fi
  if [[ ${SKIP_UNLOCK_UPGRADE_DUMPDIR} -eq 0 ]]; then
    /bin/rmdir "${CCPDEV_UPGRADE_DUMPDIR}-${script_name}" &> /dev/null
    /bin/rmdir "${CCPDEV_UPGRADE_DUMPDIR}" &> /dev/null
    SKIP_UNLOCK_UPGRADE_DUMPDIR=1
  fi
}

do_unlock_check_cache_now_lock () {
  if [[ ${SKIP_UNLOCK_CHECK_CACHE_NOW_LOCKDIR} -eq 0 ]]; then
    /bin/rmdir "${CHECK_CACHE_NOW_LOCKDIR}-${script_name}" &> /dev/null
    /bin/rmdir "${CHECK_CACHE_NOW_LOCKDIR}" &> /dev/null
    SKIP_UNLOCK_CHECK_CACHE_NOW_LOCKDIR=1
  fi
}

unlock_all_locks () {
  # Order here is important: first the dump locks, then the publish lock.
  do_unlock_dump_locks
  do_unlock_check_cache_now_lock
}

# ===========================================================================
# Engage lockdown

# We can't just check if we're running because, well, this instance of the
# script is running.
# No Good: if [[ "" != "`ps aux | grep $0`" ]]; do ...
# So we have to use a mutex, like a file lock. Using flocks is easy.

# In CcpV1, the tilecache_update script was only scheduled to run every 15
# minutes. But that's only because it didn't check to see if it was already
# running. In CcpV2, we see if it's running, otherwise we don't run (and just
# wait for the next cron iteration) -- this lets us schedule the cron job
# every minute, if we want.
# MAYBE: Have pyserver make a work_item and then Mr. Do! can run us.
#        We'd still have to check if we were already running, though.
# Use a mutually exclusive lock, or mutex, to make sure this script doesn't
# run when it's already running. Use a file lock is one approach, but it's
# easier to use mkdir, which is an atomic operation.
#
# MAYBE: Can we just row lock in tilecache_update? That way, we could start a
# lot of tilecache_update instances to run lots of tilecache_seeds in parallel.
# The lock is a directory named, e.g., apache_check_cache_now.sh-lock
# DEVS: Send --force to ignore lock dir.

CHECK_CACHE_NOW_SCRIPT="${CCP_WORKING}/mapserver/${script_name}"
CHECK_CACHE_NOW_LOCKDIR="${CHECK_CACHE_NOW_SCRIPT}-lock"
CHECK_CACHE_NOW_DUMPDIR="${CHECK_CACHE_NOW_SCRIPT}-dump"

# BUG nnnn: After we're doing with the V1->V2 scripts, we can maybe do away
#           with this reloading mechanism... or maybe we need it for when
#           we're preparing Cyclopath for other cities...
CCPDEV_UPGRADE_DUMPDIR="${CCPDEV_ROOT}/daily/upgrade_ccpv1-v2.sh-dump"

# Get the script lock or die trying.

DONT_FLOCKING_CARE=0
FLOCKING_REQUIRED=1
NUM_FLOCKING_TRIES=1
FLOCKING_TIMELIMIT=30
if [[ ${CCP_SKIP_LOCKDIR} -eq 1 ]] ; then
  DONT_FLOCKING_CARE=1
  FLOCKING_REQUIRED=0
fi
flock_dir \
  "${CHECK_CACHE_NOW_LOCKDIR}" \
  ${DONT_FLOCKING_CARE} \
  ${FLOCKING_REQUIRED} \
  ${NUM_FLOCKING_TRIES} \
  ${FLOCKING_TIMELIMIT}
if [[ $? -eq 0 ]]; then
  SKIP_UNLOCK_CHECK_CACHE_NOW_LOCKDIR=0
fi

# ===========================================================================
# Reload the dump file, if it's new and if that's what we do.

# By default, we only update the cache based on what's changed since the last
# time we ran.
TC_ALL_OR_CHANGED="--changed"

# But sometimes we redo the whole cache.
# NOTE: Using exclamation on true/false only works outside [[ ]].
if [[ -n ${CCP_CONSUME_FRESH_DB} ]]; then

  # 2013.12.07: This was just for testing, so deliberately edit
  #             this script if you want to start from scratch.
  #             That is, this script is run from cron, and on
  #             production, this if-block should never run; it's
  #             safer to make DEV uncomment this exit if they
  #             want to reload a database dump.
  echo "ERROR: Not on production!"
  exit 1

  reload_db=0

  # Try to get the dump lock, but if it's taken, we'll move on.
  DONT_FLOCKING_CARE=0
  FLOCKING_REQUIRED=0
  NUM_FLOCKING_TRIES=3
  FLOCKING_TIMELIMIT=30
  flock_dir \
    "${CCPDEV_UPGRADE_DUMPDIR}" \
    ${DONT_FLOCKING_CARE} \
    ${FLOCKING_REQUIRED} \
    ${NUM_FLOCKING_TRIES} \
    ${FLOCKING_TIMELIMIT}

  if [[ $? -ne 0 ]]; then
    if $ALWAYS_TRACE_WHEN_FRESH; then
      $DEBUG_TRACE && echo ""
      $DEBUG_TRACE && echo "Could not get lock: ${CCPDEV_UPGRADE_DUMPDIR}."
    fi
  else # if [[ $? -eq 0 ]]; then
    # Got it!
    SKIP_UNLOCK_UPGRADE_DUMPDIR=0

    CCP_DUMP_FILE=${CCP_DBDUMPS}/${CCP_CONSUME_FRESH_DB}.dump
    CCP_MAPSERVER=${CCP_WORKING}/mapserver
    CCP_LAST_LOAD=${CCP_MAPSERVER}/${script_name}-${CCP_CONSUME_FRESH_DB}

    $DEBUG_TRACE && echo "Looking for db dump: ${CCP_DUMP_FILE}"
    $DEBUG_TRACE && echo " ... last load file: ${CCP_LAST_LOAD}"
    $DEBUG_TRACE && echo ""

    if [[ ! -e ${CCP_DUMP_FILE} ]]; then
      echo "WARNING: Dump file not found: ${CCP_DUMP_FILE}"
      # Skipping: exit 1
    elif [[ ! -e ${CCP_LAST_LOAD} ]]; then
      $DEBUG_TRACE && echo "No last load file; loading dump: ${CCP_DUMP_FILE}"
      reload_db=1
    # NOTE: -nt means "newer than", meaning the file timestamp.
    elif [[ ${CCP_DUMP_FILE} -nt ${CCP_LAST_LOAD} ]]; then
      $DEBUG_TRACE && echo "Dump file is newer; loading dump: ${CCP_DUMP_FILE}"
      reload_db=1
    else
      $DEBUG_TRACE && echo "Dump file is not newer; skipping: ${CCP_DUMP_FILE}"
    fi
    $DEBUG_TRACE && echo ""

    if [[ ${reload_db} -eq 1 ]]; then
      # Remember to use --all rather than --changed for the update.
      TC_ALL_OR_CHANGED="--all"
      # If we're marked for reload, we general get verbose, since this is a
      # long, important process.
      if $ALWAYS_TRACE_WHEN_FRESH; then
        DEBUG_TRACE=true
        DTRACE_PIDS=true
      fi
      # Skip lengthy db_load, maybe.
      if [[ ${SKIP_CONSUME_FRESH_DB} == true ]]; then
        $DEBUG_TRACE && echo "SKIP_CONSUME_FRESH_DB is true; not reloading db"
        reload_db=0
      fi
    fi

    # Load the database.
    #set -e # Exit on error
    if [[ ${reload_db} -eq 1 ]]; then

      $DEBUG_TRACE && echo "Will look for dump: ${CCP_DUMP_FILE}"
      $DEBUG_TRACE && echo " .. last load file: ${CCP_LAST_LOAD}"
      $DEBUG_TRACE && echo ""

      # We need write access on the directory for the .ascii and .list files.
      if [[ ! -d ${CCP_DBDUMPS} ]]; then
        echo "FATAL ERROR: Is Cyclopath even installed on this machine?"
        exit 1
      fi
      touch ${CCP_DBDUMPS} &> /dev/null
      if [[ $? -ne 0 ]]; then
        # E.g., "touch: setting times of `/ccp/var/dbdumps': Permission denied"
        echo ""
        echo "=============================================="
        echo "ERROR: The dbdumps directory is not writeable."
        echo "Hey, you, DEV: This is certainly _your_ fault."
        echo "Try: chmod 2777 ${CCP_DBDUMPS}"
        echo "=============================================="
        echo ""
        exit 1
      fi

      $DEBUG_TRACE && echo ""
      $DEBUG_TRACE && echo -n "Loading newer database to ${CCP_DB_NAME}..."
      LOG_FILE="${CCP_LOG_CKCACHE}/db_load-${CCP_DB_NAME}.log"
      ${CCP_WORKING}/scripts/db_load.sh \
        ${CCP_DUMP_FILE} ${CCP_DB_NAME} \
        > ${LOG_FILE} 2>&1
      # Check for errors.
      if [[ $? -ne 0 ]]; then
        echo "failed!"
        echo "ERROR: db_load.sh failed: Please see: ${LOG_FILE}"
        echo ""
        # Dump the log to our log.
        #cat ${LOG_FILE}
        exit 1
      fi
      echo "ok"
      $DEBUG_TRACE && echo `date`
      # Remember when we did this.
      touch ${CCP_LAST_LOAD}
      /bin/chmod 664 ${CCP_LAST_LOAD}
    fi
    #set +e # Stay on error

    # Since we just reloaded the database, whack the tilecache cache directory.
    if [[ ${reload_db} -eq 1 ]]; then
      $DEBUG_TRACE && echo ""
      $DEBUG_TRACE && echo "Purging cache dir: ${TILECACHE_CACHE}"
      /bin/rm -rf "${TILECACHE_CACHE}" &> /dev/null

      # Also whack any old touch files, which are meaningless now.
      # See: RID_COMPARATOR.
      /bin/rm -f last_rev-*.touch
    fi

    # Free the lock now that the database is loaded.
    #  /bin/rmdir "${CCPDEV_UPGRADE_DUMPDIR}" &> /dev/null
    do_unlock_dump_locks

  fi # else, didn't get the lock, and we'll try again next cron.

# FIXME: Return now if there was no database to load -- that is,
#        CCP_CONSUME_FRESH_DB doesn't otherwise make tiles or do any work.
#
# FIXME: Enable this once we know the --changed problem in tilecache_update is
#        fixed.
#  if [[ ${reload_db} -eq 0 ]]; then
  if false; then
    $DEBUG_TRACE && echo ""
    $DEBUG_TRACE && echo "Didn't get lock or didn't reload database: done."
    exit 0
  fi

fi # end: if CCP_CONSUME_FRESH_DB and not SKIP_CONSUME_FRESH_DB.

# ===========================================================================
# Verify the database exists.

# [lb]'s PAGER is set to less, but we want more, i.e., less is interactive, and
#   more just dumps to stdout.
# Note that -A strips whitespace and dashes, and -t strips headers, so we're
#   just left with a number-string.
# Oh, but wait, www-data can't run as postgres, because pg_ident.conf says so.
# Oh, wait, www-data needs postgres access to be able to reload the database!
# Anyway, either of these approaches works:
#
# # Option 1:
#  ccp_db_exists=`
#    PAGER=more \
#    psql -U postgres postgres \
#      -c "SELECT COUNT(*) FROM pg_database WHERE datname = '${CCP_DB_NAME}';"\
#      -A -t`
# # Option 2:
psql -U cycling ${CCP_DB_NAME} -c "" --no-psqlrc &> /dev/null
errno=$?
if [[ $errno -eq 2 ]]; then
  # E.g., 'psql: FATAL:  database "ccpv3_blah" does not exist'
  echo "ERROR: Database does not exist: ${CCP_DB_NAME}"
  exit 1
elif [[ $errno -ne 0 ]]; then
  echo "ERROR: Database does not exist (unknown why): ${CCP_DB_NAME}"
  exit 1
fi

# ===========================================================================
# Fcns.

# ***

instance_branch_check_rid() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi

  $DEBUG_TRACE && echo "Looking for work for: ${db_instance}-${branch_name}"
  $DEBUG_TRACE && echo ""

  # FIXME: Should we move all the lock dirs and touch files
  #        to a different location? Things are getting cluttered.
  # REMEMBER: To continue a set-var cmd in bash you can't have any whitespace.
  RID_COMPARATOR=\
"${CCP_WORKING}/mapserver/last_rev-${db_instance}-${branch__ed}.touch"

  RID_CURRENTLY=\
"${CCP_WORKING}/mapserver/last_rev-${db_instance}-${branch__ed}.curr"

  export INSTANCE=${db_instance}
  latest_rev_ts=$(ccp_latest_rev_ts ${branch_name})
  if [[ -z ${latest_rev_ts} ]]; then
    echo "ERROR: Problem getting last revision timestamp for ${branch_name}"
    exit 1
  fi

  touch -d "${latest_rev_ts}" "${RID_CURRENTLY}"

  process_branch=true
  if [[ ! -e "${RID_COMPARATOR}" ]]; then
    # NOTE: Skipping DEBUG_TRACE.
    if [[ -n ${CCP_CONSUME_FRESH_DB} ]]; then
      echo "WARNING: No rid file: ${RID_COMPARATOR}"
    fi
    touch -d "${latest_rev_ts}" "${RID_COMPARATOR}"
  elif [[ "${RID_CURRENTLY}" -nt "${RID_COMPARATOR}" ]]; then
    $DEBUG_TRACE && echo "Latest branch revision is more recent; doing work."
  else
    $DEBUG_TRACE && echo "Not working on branch with no recent changes."
    $DEBUG_TRACE && echo "Comparator: ${RID_COMPARATOR}"
    $DEBUG_TRACE && echo " Currently: ${RID_CURRENTLY}"
    process_branch=false
  fi

  /bin/rm -f "${RID_CURRENTLY}"

  if ${process_branch} || $SKIP_REVID_CHECK; then
    $DEBUG_TRACE && echo "Adding: ${db_instance}-${branch_name}"
    CCP_WORKTODO_BRANCHES+=("$db_instance")
    CCP_WORKTODO_BRANCHES+=("$branch_name")
  fi
}

# ***

instance_config_write() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi

  INSTANCE="${db_instance}___${CCP_INSTANCE}"
  #TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

  /bin/mkdir -p "${TILECACHE_CACHE}" &> /dev/null
  /bin/chmod 2775 ${TILECACHE_CACHE}

  # ***

  # Install config to /ccp/var/tilecache-cache/[installation]...

  # ... wms_instance.map and fonts.
  mapserver_mapfile_install

  # ... tilecache.cfg.
  tilecache_config_install

  # WANTED: We could also auto-generate this script's wrapper?
  #         Okay, maybe not from here, but from somewhere else.
  #         (Since this script is justed called by www-data.
  #         We need to setup the wrapper from upgrade_ccpv1-v2.sh.)
  # Not here: ... check_cache_now.sh
}

# ***

mapserver_mapfile_install() {

  # MAYBE: Is this costly to do if we run every minute from cron?
  #        Would it be better to 'svn info $cp' and see if that changed... but
  #        then we'd have to worry about dev folders that are not svnified.

  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Recreating wms_instance.map."

  # SYNC_ME: This commands match some CxPx commands atop tilecache_update.py.

  # Start by making the map file for MapServer.
  # It's rather large, so we store it outside of the Cyclopath source tree.
  # SYNC: httpd.conf's MS_MAPFILE matches ${TILECACHE_CACHE}/wms_instance.map:
  cd ${CCP_WORKING}/mapserver
  # NOTE: make_mapfile doesn't say anything, so the log file is zero, zilch,
  #       empty.
  LOG_FILE="${CCP_LOG_CKCACHE}/make_mapfile-${CCP_INSTANCE}.log"
  LOCAL_TARGET=${CCP_WORKING}/mapserver/wms_instance.map
  FINAL_TARGET=${TILECACHE_CACHE}/wms_instance.map
  INSTANCE=${INSTANCE} \
    PYTHONPATH=${ccp_python_path} \
    PYSERVER_HOME=${CCP_WORKING}/pyserver \
    ${CCP_WORKING}/mapserver/make_mapfile.py \
      > ${LOG_FILE} 2>&1
  check_prev_cmd_for_error $? ${LOG_FILE} ${dont_exit_on_error}

  # Post-process with m4 to build one helluva mapfile.
  m4 ${CCP_WORKING}/mapserver/wms-${db_instance}.m4 > ${LOCAL_TARGET}

  # We can diff against locations that don't exist -- $? will be 2 (it's 1 for
  # existing files that differ or 0 for two files that match).
  install_mapfile=false
  if [[ -e "${FINAL_TARGET}" ]]; then
    $DEBUG_TRACE && echo " .. diffing against existing."
    mapfiles_diff=$(diff ${LOCAL_TARGET} ${FINAL_TARGET})
    if [[ "" != "${mapfiles_diff}" ]]; then
      #$DEBUG_TRACE && echo "Mapfiles are different."
      echo "WARNING: Mapfiles are different. Recreating, but not retiling."
      # MAYBE: Call tilecache_update.py --all so we rebuild all tiles?
      install_mapfile=true
    else
      $DEBUG_TRACE && echo " .. mapfile unchanged; leaving be."
      /bin/rm -f ${LOCAL_TARGET}
    fi
  else
    $DEBUG_TRACE && echo "NOTICE: Mapfile does not exist; creating."
    install_mapfile=true
  fi

  if ${install_mapfile}; then
    $DEBUG_TRACE && echo ""
    $DEBUG_TRACE && echo "Installing new mapile: from: ${LOCAL_TARGET}"
    $DEBUG_TRACE && echo "                      .. to: ${FINAL_TARGET}"
    /bin/mv -f ${LOCAL_TARGET} ${FINAL_TARGET}
    /bin/chmod 664 ${FINAL_TARGET}
    # We also want to copy the fonts.list and fonts/ directory.
    /bin/cp -f ${CCP_WORKING}/mapserver/fonts.list ${TILECACHE_CACHE}
    /bin/rm -rf ${TILECACHE_CACHE}/fonts
    /bin/cp -rf ${CCP_WORKING}/mapserver/fonts/ ${TILECACHE_CACHE}
    # Fix perms.
    /bin/chmod 664 ${TILECACHE_CACHE}/fonts.list
    /bin/chmod 2775 ${TILECACHE_CACHE}/fonts
    /bin/chmod 664 ${TILECACHE_CACHE}/fonts/*
    /bin/chmod 2775 ${TILECACHE_CACHE}
  else
    /bin/rm -f ${LOCAL_TARGET}
  fi

  # Clean up an intermediate file that make_mapfile created that
  # wms-instance.map needed.
  /bin/rm -f ${CCP_WORKING}/mapserver/byways_and_labels.map
}

# ***

tilecache_config_install() {

  # C.f. similar mapserver_mapfile_install, above.

  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Recreating tilecache.cfg."

  # Generate the tilecache.cfg and install or check for changes.

  cd ${CCP_WORKING}/mapserver
  LOG_FILE="${CCP_LOG_CKCACHE}/gen_tilecache_cfg-${CCP_INSTANCE}.log"
  LOCAL_TARGET=${CCP_WORKING}/mapserver/tilecache.cfg
  FINAL_TARGET=${TILECACHE_CACHE}/tilecache.cfg
  INSTANCE=${INSTANCE} \
    PYTHONPATH=${ccp_python_path} \
    PYSERVER_HOME=${CCP_WORKING}/pyserver \
    ${CCP_WORKING}/mapserver/gen_tilecache_cfg.py \
    > ${LOG_FILE} 2>&1
  check_prev_cmd_for_error $? ${LOG_FILE} ${dont_exit_on_error}

  diff ${LOCAL_TARGET} ${FINAL_TARGET} &> /dev/null
  if [[ $? -ne 0 ]] ; then
    echo "WARNING: Tilecache cfgs are different (or target d/n/e)."
    # MAYBE: Should we always overwrite existing cfg? Hrm...
    /bin/mv -f ${LOCAL_TARGET} ${FINAL_TARGET}
    /bin/chmod 664 ${FINAL_TARGET}
  else
    # Nothing changed, so just delete the new file.
    $DEBUG_TRACE && echo " .. tilecache cfg unchanged; leaving be."
    /bin/rm -f ${LOCAL_TARGET}
  fi
}

# ***

instance_update_cache() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi
  INSTANCE="${db_instance}___${CCP_INSTANCE}"
  #TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

  BRANCH_QUALIFIER="${CCP_INSTANCE}_${db_instance}_${branch__ed}"
  LOG_FILE="${CCP_LOG_CKCACHE}/tc_cache-${BRANCH_QUALIFIER}.log"

  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "  %33s:%12s:%22s:  starting... " \
    "${CCP_INSTANCE}" "${db_instance}" "${branch__ed}"

  __2013_05_29__='
    export INSTANCE=minnesota
    export PYSERVER_HOME=/ccp/dev/cp_v1v2-tcc/pyserver
    export PYTHONPATH=/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.6/site-packages:/ccp/opt/gdal/lib/python2.6/site-packages
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --cyclopath-cache

    sudo su - $httpd_user
    /bin/bash
    cd /ccp/dev/cycloplan_live/mapserver
    #export INSTANCE=minnesota
    export INSTANCE=minnesota___cycloplan_live
    export PYSERVER_HOME=/ccp/dev/cycloplan_live/pyserver
    export PYTHONPATH=/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.6/site-packages:/ccp/opt/gdal/lib/python2.6/site-packages
    LOG_FILE=/ccp/var/log/daily/cache/tc_cache-cycloplan_live_minnesota_Mpls-St._Paul.log
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --cyclopath-cache               \
      > ${LOG_FILE} 2>&1 &


DO THIS STILL:

    LOG_FILE=/ccp/var/log/daily/cache/tc_tiles-cycloplan_live_minnesota_Mpls-St._Paul-zooms_09_09.log
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --tilecache-tiles               \
      --zoom 09 09                          \
      > ${LOG_FILE} 2>&1 &

    LOG_FILE=/ccp/var/log/daily/cache/tc_tiles-cycloplan_live_minnesota_Mpls-St._Paul-zooms_10_13.log
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --tilecache-tiles               \
      --zoom 10 13                          \
      > ${LOG_FILE} 2>&1 &

    LOG_FILE=/ccp/var/log/daily/cache/tc_tiles-cycloplan_live_minnesota_Mpls-St._Paul-zooms_14_14.log
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --tilecache-tiles               \
      --zoom 14 14                          \
      > ${LOG_FILE} 2>&1 &

    LOG_FILE=/ccp/var/log/daily/cache/tc_tiles-cycloplan_live_minnesota_Mpls-St._Paul-zooms_15_15.log
    ./tilecache_update.py                   \
      --branch "Minnesota"                  \
      --all --tilecache-tiles               \
      --zoom 15 15                          \
      > ${LOG_FILE} 2>&1 &

also metc
    LOG_FILE=/ccp/var/log/daily/cache/tc_cache-cycloplan_live_minnesota_Metc_Bikeways_2012.log
    ./tilecache_update.py                   \
      --branch "Metc Bikeways 2012"         \
      --all --cyclopath-cache               \
      > ${LOG_FILE} 2>&1 &
and the zooms...



The cluster cache takes 24 hours to build... hrmmm

  '
  INSTANCE=${INSTANCE}                      \
    PYTHONPATH=${ccp_python_path}           \
    PYSERVER_HOME=${CCP_WORKING}/pyserver   \
    ./tilecache_update.py                   \
      --branch "${branch_name}"             \
      ${TC_ALL_OR_CHANGED}                  \
      --cyclopath-cache                     \
    > ${LOG_FILE}                           \
    2>&1                                    \
    &
  WAITPIDS+=("${!}")
  WAITLOGS+=("${LOG_FILE}")
  $DEBUG_TRACE && echo "ok!"
  $DTRACE_PIDS && echo "Added to WAITPIDS: ${!}"
  $DTRACE_PIDS && echo  WAITPIDS: ${WAITPIDS[*]}

}

# ***

branch_update_tiles() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi
  INSTANCE="${db_instance}___${CCP_INSTANCE}"
  #TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

  # ***

  # FIXME: Use work items to schedule tilecache_update.py to run on specific
  # installations and branches within installations only when required? For now
  # we're run periodically by cron and call tilecache_update.py on all servers,
  # branches, and zooms. This might not be a big deal, but [lb] hasn't profiled
  # the strain on the server that this script causes.

  # Early versions of this script went through the zooms one-by-one (and the
  # branches one-by-one above that, and the servers above those). But that
  # means we quickly build the higher zooms for some branch in whatever server
  # we pick first, and then we waste hours going through the lower zooms, and
  # then we move on to the next branch starting with the higher zooms to the
  # lower, iterating through branches until we're done with the first server
  # before moving on to the next server.
  #
  # But we can improves this in two ways.
  #
  # 1. We have a Big, Meaty server, so we should use more than just a single
  #    processor.
  # 2. It'd be nice if servers and branches didn't block one another, so that,
  #    e.g., we can quickly build all the higher zoom levels for all branches
  #    and all servers and not have to wait for any lower zoom levels to build.

  # SYNC_ME: Search conf.ccp_min_zoom and conf.ccp_max_zoom.
  #
  # DEVS: Here's the extra zooms, if you want:
  # for zoom in "9" "10" "11" "12" "13" "14" "15" "16" "17" "18" "19"; do
  #
  # DEVS: Here's to quicker testing.
  #       Though you might not want to use --branch -1, either.
  # for zoom in "9"; do
  #
  # SYNC_ME: See below; the min/max are 9/15.

  # 2013.04.23: The zooms 9 through 13 take a couple of hours to complete (a
  # few minutes on zooms 9 and 10, then doubling on each successive zoom).
  # The zoom 14 takes 2 hours, and the zoom 15 takes 4 hours. So if we use
  # three zoom groupings, each group should take a few to a four hours.

  BRANCH_QUALIFIER="${CCP_INSTANCE}_${db_instance}_${branch__ed}"
  LOGBASE="${CCP_LOG_CKCACHE}/tc_tiles-${BRANCH_QUALIFIER}"

  #zoom_groups=("09 13" "14 14" "15 15")
  #zoom_groups=("09 13")
  #zoom_groups=("07 09" "10 13" "14 14" "15 15")
  # MAYBE: Break into counties... the State of MN is 7x larger than MetC bbox.
  #zoom_groups=("06 09" "10 11" "12 12" "13 13" "14 14" "15 15")

  # 2014.09.08: [lb] doesn't want the public to be able to influence the
  # way-zoomed-out tiles, which are particularly hard to make beautiful,
  # especially since they use stack IDs from the database!! =)
  # In the skins file, see: l_restrict_stack_ids_major_trail_05 through
  #                         l_restrict_stack_ids_major_trail_08
  if [[ ${TC_ALL_OR_CHANGED} == "--all" ]]; then
    zoom_groups=("05 09" "10 11" "12 12" "13 13" "14 14" "15 15")
  elif [[ ${TC_ALL_OR_CHANGED} == "--changed" ]]; then
    zoom_groups=("09 11" "12 12" "13 13" "14 14" "15 15")
  else
    echo "Error: What's TC_ALL_OR_CHANGED?: ${TC_ALL_OR_CHANGED}"
    exit 1
  fi

# BUG nnnn/2014.08.25: Zoom 14 is now taking a day (Statewide MN);
#                      can we do a parallel build by bbox (either
#                      on different cores or different machines
#                      altogether).
#                 Add: --bbox

  $DEBUG_TRACE && echo ""

  for arr_index in ${!zoom_groups[*]}; do

    # MAYBE: Do we want to keep a running logfile? Do it for now, until
    #        script is more mature.
    # NOTE: You're going to end up with lots of logfiles...
    zooms=${zoom_groups[$arr_index]}
    zooms_=`echo $zooms | tr ' ' '_'`
    LOG_FILE="${LOGBASE}-zooms_${zooms_}.log"

    $DEBUG_TRACE && printf "  %23s:%12s:%22s:%7s: starting... " \
      "${CCP_INSTANCE}" "${db_instance}" "${branch__ed}" "${zooms_}"

    # NOTE: We don't have to use --all: the --changed option will repopulate
    #       everything if nothing exists for the zoom level. (But we still
    #       have the check_cache_now.sh-init folder to tell us to use --all
    #       anyway...).

    # EXPLAIN: We archive the logs later... do/should we keep them forever?
    INSTANCE=${INSTANCE}                      \
      PYTHONPATH=${ccp_python_path}           \
      PYSERVER_HOME=${CCP_WORKING}/pyserver   \
      ./tilecache_update.py                   \
        --branch "${branch_name}"             \
        ${TC_ALL_OR_CHANGED}                  \
        --zoom ${zooms}                       \
        --tilecache-tiles                     \
      > ${LOG_FILE}                           \
      2>&1                                    \
      &
    WAITPIDS+=("${!}")
    WAITLOGS+=("${LOG_FILE}")
    $DEBUG_TRACE && echo "ok!"
    $DTRACE_PIDS && echo "Added to WAITPIDS: ${!}"
    $DTRACE_PIDS && echo  WAITPIDS: ${WAITPIDS[*]}

  done
}

# ***

# In bash, you fork a command simply by running it with the ampersand
# appended to the command line. (You can't really fork in the middle
# of a script; you can exec, but that's not quite the same).
#
# There are a number of ways to detect when your new, background
# processes, as they're called, complete.
#
# See
# http://stackoverflow.com/questions/1455695/forking-multi-threaded-processes-bash
#
# One method is to start all your jobs and then bring each one to the
# foreground. The fg command blocks until the job finishes, or returns
# nonzero if there are no more jobs for this session.
# 
#   # Wait for all parallel jobs to finish.
#   while [ 1 ]; do fg 2> /dev/null; [ $? == 1 ] && break; done
# 
# Another method is to use WAITPID. E.g.,
#
#   sleep 3 & WAITPID=$!; wait $WAITPID
#
# Note that you can concatenate process IDs with spaces to wait on multiple.
#
# But the obvious solution is to use Bash's jobs command, which returns the
# process IDs of the jobs as a list. It's empty when the jobs are all done.
# UPDATE: That stackoverflow answer is wrong: jobs is an interactive-only
# command. From within a script it doesn't behave well, because of how child
# processes are spawned.
# http://stackoverflow.com/questions/690266/why-cant-i-use-job-control-in-a-bash-script

tilecache_updates_wait() {

  time_1=$(date +%s.%N)
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "Waiting for tilecache_updates after %.2F mins.\n" \
      $(echo "(${time_1} - ${script_time_0}) / 60.0" | bc -l)

  # Not using: wait $WAITPIDS
  #  since that waits on all PIDs, so it's all or nothing.
  # Instead we loop through the PIDs ourselves and check
  # with ps to see if each process is running.
  # 2013.05.16: Let's try this: looping through an array of PIDs...
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Waiting for ${#WAITPIDS[*]} processes to complete."
  while [[ ${#WAITPIDS[*]} > 0 ]]; do
    NEXTPIDS=()
    for cur_pid in ${WAITPIDS[*]}; do
      PROCESS_DETAILS=`ps h --pid ${cur_pid}`
      if [[ -n ${PROCESS_DETAILS} ]]; then
        NEXTPIDS+=(${cur_pid})
      else
        $DTRACE_PIDS && echo "No longer running: process ID: ${cur_pid}."
        time_2=$(date +%s.%N)
        $DEBUG_TRACE && printf "Since started waiting: %.2F mins.\n" \
            $(echo "(${time_2} - ${time_1}) / 60.0" | bc -l)
      fi
    done
    # Nonono: WAITPIDS=${NEXTPIDS}
    # This is how you copy an array:
    WAITPIDS=("${NEXTPIDS[@]}")
    if [[ ${#WAITPIDS[*]} > 0 ]]; then
      # MAYBE: Is this loop too tight?
      sleep 1
    else
      $DTRACE_PIDS && echo "No longer running: any child process."
    fi
  done
  
  # The subprocesses might still be spewing to the terminal so hold off a sec,
  # otherwise the terminal prompt might get scrolled away after the script
  # exits if a child process output is still being output (and if that happens,
  # it might appear to the user that this script is still running (or, more
  # accurately, hung), since output is stopped but there's no prompt (until you
  # hit Enter and realize that script had exited and what you're looking at is
  # background process blather)).

  sleep 1

  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "All tilecache_update.pys complete!"

  time_2=$(date +%s.%N)
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "Waited for background tasks for %.2F mins.\n" \
      $(echo "(${time_2} - ${time_1}) / 60.0" | bc -l)

  # We kept a list of log files that the background processes to done wrote, so
  # we can analyze them now for failures.
  dont_exit_on_error=1
  #dont_exit_on_error=0
  for logfile in ${WAITLOGS[*]}; do
    check_prev_cmd_for_error $? ${logfile} ${dont_exit_on_error}
  done
}

# ***

report_setup_sizes() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi
  INSTANCE="${db_instance}___${CCP_INSTANCE}"
  #TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

  # Print the initial size of the cache folder.
  du_resp=`du -m -s $TILECACHE_CACHE`
  cache_size_init=(`echo $du_resp | tr ' ' ' '`)

  arr_key="${CCP_INSTANCE}:${db_instance}:${branch__ed}"
  SERVER_BRANCH_ZOOM_SIZES[${arr_key}]=${cache_size_init[0]}
#  $DEBUG_TRACE && echo \
#    " || ${CCP_INSTANCE}:${db_instance}:${branch__ed}:" \
#    " || ${cache_size_init[0]} Mb."
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "  %33s:%12s:%22s:  %5d Mb.\n" \
    "${CCP_INSTANCE}" "${db_instance}" "${branch__ed}" "${cache_size_init[0]}"
}

report_delta_sizes() {

  db_instance=$1
  branch_name=$2
  branch__ed=`echo $branch_name | tr ' ' '_'`
  if [[ -z "${branch_name}" ]]; then
    echo "Please specify the db_instance and branch_name."
    exit 1
  fi
  INSTANCE="${db_instance}___${CCP_INSTANCE}"
  #TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

  du_resp=`du -m -s $TILECACHE_CACHE`
  cache_size_last=(`echo $du_resp | tr ' ' ' '`)
  
  arr_key="${CCP_INSTANCE}:${db_instance}:${branch__ed}"
  cache_size_early=${SERVER_BRANCH_ZOOM_SIZES[${arr_key}]}
  cache_size_delta=$((${cache_size_last[0]} - $cache_size_early))
#  $DEBUG_TRACE && echo \
#    "Final tilecache size ${CCP_INSTANCE}:${db_instance}:${branch__ed}:" \
#    "${cache_size_delta} Mb."
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "  %33s:%12s:%22s:  %5d Mb. +\n" \
    "${CCP_INSTANCE}" "${db_instance}" "${branch__ed}" "${cache_size_delta[0]}"
}

# ===========================================================================
# Application "main"

# *** Start of application...

$DEBUG_TRACE && echo "Welcome to check_cache_now!"
$DEBUG_TRACE && echo ""
$DEBUG_TRACE && echo "No. of server-branches: ${ccp_number_servers}"
$DEBUG_TRACE && echo ""

# Make an associate array to hold the directory sizes before.
declare -A SERVER_BRANCH_ZOOM_SIZES

# Pre-process each branch: check the latest revision ID and skip
# doing any work if the branch's latest rid is unchanged.
$DEBUG_TRACE && echo "Checking branches' last revision IDs..."
$DEBUG_TRACE && echo ""
CCP_WORKTODO_BRANCHES=()
arr2_fcn_iter 'instance_branch_check_rid' \
  ${ccpsb_cols_per_row} CCP_INSTANCE_BRANCHES[@]

# MAYBE: Do we skip the bbox computation if the revision hasn't changed?
#        Or do we waste a few seconds on each branch computing the bbox?
if ! $SKIP_CONFIG_FILES; then
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Creating and installing config files..."
  # This is a sneaky way in Bash to pass an array as an argument.
  # Use the array's name! In the fcn we're calling, it'll use the
  # bang operator to resolve the string we're sending to the array.
  arr2_fcn_iter 'instance_config_write' \
    ${ccpsb_cols_per_row} CCP_WORKTODO_BRANCHES[@]
fi

if ! $SKIP_REPORT_SIZES; then
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Initial tilecache directory sizes:"
  arr2_fcn_iter 'report_setup_sizes' \
    ${ccpsb_cols_per_row} CCP_WORKTODO_BRANCHES[@]
fi

if ! $SKIP_TILECACHE_CACHE; then
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Updating database caches w/ bg processes..."
  WAITPIDS=()
  WAITLOGS=()
  arr2_fcn_iter 'instance_update_cache' \
    ${ccpsb_cols_per_row} CCP_WORKTODO_BRANCHES[@]
  # Wait for child processes.
  tilecache_updates_wait
fi

# FIXME: 

if ! $SKIP_TILECACHE_TILES; then
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Recreating tilecache tiles w/ bg processes..."
  WAITPIDS=()
  WAITLOGS=()
  arr2_fcn_iter 'branch_update_tiles' \
    ${ccpsb_cols_per_row} CCP_WORKTODO_BRANCHES[@]
  # Wait for child processes.
  tilecache_updates_wait
fi

if ! $SKIP_REPORT_SIZES; then
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo "Delta tilecache directory sizes:"
  arr2_fcn_iter 'report_delta_sizes' \
    ${ccpsb_cols_per_row} CCP_WORKTODO_BRANCHES[@]
fi

# FIXME: Split branches from zooms, i.e., right now, sequence is:
#        basemap 9 to 15, metc 9 to 15, statewide 9 to 15
# maybe in cron:
#        run script for each installation for each branch,
#        maybe for 14 and 15 and 16 and 17 separately...

# ===========================================================================
# Dump the database and whack the lock.

# Don't continue if we can't get our dump lock -- a developer will have to
# clear this up if we can't.
# HACK: This gives ${TC_ALL_OR_CHANGED} a second meaning:
if [[ ${TC_ALL_OR_CHANGED} == "--all" ]]; then

  DONT_FLOCKING_CARE=0
  FLOCKING_REQUIRED=1
  NUM_FLOCKING_TRIES=-1
  FLOCKING_TIMELIMIT=3600
  flock_dir \
    "${CHECK_CACHE_NOW_DUMPDIR}" \
    ${DONT_FLOCKING_CARE} \
    ${FLOCKING_REQUIRED} \
    ${NUM_FLOCKING_TRIES} \
    ${FLOCKING_TIMELIMIT}
  if [[ $? -eq 0 ]]; then
    SKIP_UNLOCK_CHECK_CACHE_NOW_DUMPDIR=0
  fi

  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && echo `date`
  $DEBUG_TRACE && echo "Dumping tilecache'd database: ${CCP_DB_NAME}"
  #
  TCC_DUMP_FILE=${CCP_DBDUMPS}/${CCP_DB_NAME}.dump
  touch ${TCC_DUMP_FILE} &> /dev/null
  if [[ $? -ne 0 ]]; then
    echo ""
    echo "=============================================="
    echo "ERROR: The dump file is not writeable."
    echo "Hey, you, DEV: This is certainly _your_ fault."
    echo "Try: chmod 2777 ${TCC_DUMP_FILE}"
    echo "=============================================="
    echo ""
    exit 1
  else
    pg_dump ${HOSTNAME_SWITCH} -U cycling ${CCP_DB_NAME} -Fc -E UTF8 \
      > ${TCC_DUMP_FILE}
    # 2013.05.22: Weird: "Why is the dump owned by me, landonb?"
    #   /bin/chmod: changing permissions of `/ccp/var/dbdumps/ccpv2_tcc.dump':
    #   Operation not permitted
    /bin/chmod 664 ${TCC_DUMP_FILE}
  fi

  # Release the dump lock.
  #  /bin/rmdir "${CHECK_CACHE_NOW_DUMPDIR}" &> /dev/null
  do_unlock_dump_locks

fi

# ===========================================================================
# Archive all our logs

# Store to, i.e., /ccp/var/log/daily/cache_
ARCHIVE_NAME=${CCP_ZIP_CKCACHE}/ckcache-`date +%Y_%m_%d_%Hh%Mm`

$DEBUG_TRACE && echo ""
$DEBUG_TRACE && \
  echo "Archiving cache for ${script_name}: ${ARCHIVE_NAME}.tar.gz"

# Collect files from, i.e., /ccp/var/log/daily/cache
# NOTE: If you use the full path than the tarball includes the dir. ancestry.
#       tar -czf ${ARCHIVE_NAME}.tar.gz ${CCP_LOG_CKCACHE}/* \
#         > ${ARCHIVE_NAME}.log 2>&1
cd ${CCP_LOG_DAILY}
tar -czf ${ARCHIVE_NAME}.tar.gz cache/* \
  > ${ARCHIVE_NAME}.log 2>&1

# ===========================================================================
# Release lockdown

unlock_all_locks

# ===========================================================================
# Print elapsed time

script_finished_print_time

# ===========================================================================
# All done.

exit 0

# ***

