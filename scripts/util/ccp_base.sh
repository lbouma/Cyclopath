#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: Call this script from another script.
#

# ============================================================================
# *** Setup

# SYNC_ME: This setup code is shared btw.: bash_base.sh and ccp_base.sh.

# Make it easy to reference the script name and relative or absolute path.

# NOTE: The parent `source`d us, so $0 is _its_ name.
#       Unless the parent was also sourced.

if [[ `echo "$0" | grep "bash$" -` ]]; then
  # User sourcing us (via parent) from terminal.
  script_name=$BASH_SOURCE
  script_relbase=$(pwd -P)
else
  script_name=$(basename $0)
  script_relbase=$(dirname $0)
fi
#echo "script_name: $script_name"
#echo "script_relbase: $script_relbase"

# From our good friends at http://stackoverflow.com
#   /questions/7126580/expand-a-possible-relative-path-in-bash

dir_resolve () {
  # Change to the desired directory. Squash error msgs. but return error
  # status, maybe.
  cd "$1" 2>/dev/null || return $?
  # Use pwd's -P to return the full, link-resolved path.
  echo "`pwd -P`"
}

script_path=$(dir_resolve $script_relbase)

# ============================================================================
# *** Find bash_base.sh

# Pyserver home leads us to the installation folder, unless not specified.

# C.f. from pyserver_glue.py. Kinda. There's similar code that walks up the
# directory tree until we find a pyserver uncle or until we root out.
#
find_pyserver_uncle () {

  HERE_WE_ARE=$(dir_resolve ${script_relbase})

  while [[ ${HERE_WE_ARE} != '/' ]]; do
    if [[ -e "${HERE_WE_ARE}/pyserver/CONFIG" ]]; then
      # MAYBE: Really export? We were sourced, so maybe don't do this,
      #        so we don't clobber the user's working environment?
      export CCP_WORKING=${HERE_WE_ARE}
      export PYSERVER_HOME=${CCP_WORKING}/pyserver
      break
    else
      # Keep looping:
      HERE_WE_ARE=$(dir_resolve ${HERE_WE_ARE}/..)
    fi
  done

  if [[ ${HERE_WE_ARE} == '/' ]]; then
    echo "ERROR: Cannot suss out PYSERVER_HOME. Failing!"
    exit 1
  fi
}

if [[ "${PYSERVER_HOME}" == "/dev/null" ]]; then
  : # Nada. This is just ccp_install calling us, before Ccp is installed.
elif [[ -z "${PYSERVER_HOME}" ]]; then
  find_pyserver_uncle
else
  CCP_WORKING=$(dir_resolve ${PYSERVER_HOME}/..)
  export CCP_WORKING=${CCP_WORKING}
fi

# If the dev dir is symbolic link, be sure to use the qualified (hard path)
# instance name. E.g., on the production server, /ccp/dev/cycloplan_sib1 and
# /ccp/dev/cycloplan_sib2 both point to /ccp/dev/cycloplan_live.
# Note that we could do this earlier, for CCP_WORKING, but we just need it
# for CCP_INSTANCE to work, e.g., /ccp/var/tilecache/* uses instance name,
# so we could make symbolic links there, but then what other places use
# CCP_INSTANCE?

test_opts=$(echo $SHELLOPTS)
set +e
`echo $test_opts | grep errexit` >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  USING_ERREXIT=true
else
  USING_ERREXIT=false
fi
#
hard_path=`readlink $CCP_WORKING`
#
if $USING_ERREXIT; then
  set -e
fi

if [[ -z $hard_path ]]; then
  CCP_INSTANCE=$(basename $CCP_WORKING)
else
  CCP_INSTANCE=$(basename $hard_path)
fi

# This script needs some utility functions that we have defined next door.

BASH_BASE_PATH=${CCP_WORKING}/scripts/util/bash_base.sh
if [[ ! -e "${BASH_BASE_PATH}" ]]; then
  echo "ERROR: Where is bash_base.sh?"
fi
. ${BASH_BASE_PATH}

# ============================================================================
# *** Cyclopath's Well-known paths

# *** Cyclopath developer repository

# The ccpdev directory is used interally in cron jobs. If you're a community
# developer, you can ignore this setting (you won't find it used in the
# source).
CCPDEV_ROOT=/ccp/bin/ccpdev

# The typical CcpV2 source code installation folder.

CCP_DEV=/ccp/dev

# *** Cyclopath variable files storage

CCP_VAR=/ccp/var

# Where to store database dumps on the machine.
CCP_DBDUMPS=/ccp/var/dbdumps
CCP_DBDAILY=${CCP_VAR}/.dbdumps.daily

# Where the branch manager's and www-data's cron record their nightly
# activities (for, e.g., daily.runic.sh and check_cache_now.sh).
# Also where CcpV1->V2's upgrade_ccpv1-v2 and publish_ccpv1-v2 blather.
CCP_LOG=/ccp/var/log
CCP_LOG_DAILY=/ccp/var/log/daily

# TileCache Cache dir.
TILECACHE_BASE=/ccp/var/tilecache-cache

# ============================================================================
# *** Cyclopath's installation-specifics

# Get the name of the Cyclopath database used by this installation.

if [[ -e "${PYSERVER_HOME}/CONFIG" ]]; then
  #
  # FIXME: THIS DOESN'T RESPEK INSTANCE.
  #        E.g., [instance_minnesota]
  #        MAYBE: Deprecate $INSTANCE and go w/ one instance per
  #        CCP_INSTALLATION -- which is 100% more natural, except
  #        you can't share the user database... oh, dur, instead
  #        of instance, you should use a different branch...
  #        
  CCP_DB_NAME=`/bin/egrep "^database: +[_a-zA-Z0-9]+$" \
               ${PYSERVER_HOME}/CONFIG \
               | /bin/sed -r 's/^database: +//'`
  CCP_DB_PORT=`/bin/egrep "^port: +[0-9]+$" \
               ${PYSERVER_HOME}/CONFIG \
               | /bin/sed -r 's/^port: +//'`
fi

# Well-known psql wrapper. Sets up search_path for us.
PSQL_WRAP=${CCP_WORKING}/scripts/util/psql_wrap.sh

# This instance's tilecache cache folder.
TILECACHE_CACHE=${TILECACHE_BASE}/${CCP_INSTANCE}

# ============================================================================
# *** Cyclopath's Python path

# Oddly, if we don't include the GDAL path, 'from osgeo import osr' fails under
# Ubuntu 11.04 (Python 2.7). Works fine without under Ubuntu 10.04 (Python 2.6)
# This is usually used when sudo'ing a command, to supply the path to root or
# to httpd_user.
# No: /export/scratch/ccp/opt/gdal/lib/$PYTHONVERS/site-packages/GDAL-1.10.1-${PYVERSABBR}-linux-x86_64.egg:\
# No: /ccp/opt/usr/lib/python2.6/site-packages/networkx-1.8.1-py2.6.egg
#      (networkx is installed for users, but not for www-data...
#       you have to point the httpd.conf at the location).
ccp_python_path="\
/export/scratch/ccp/opt/usr/lib/python:\
/export/scratch/ccp/opt/usr/lib/$PYTHONVERS/site-packages:\
/export/scratch/ccp/opt/gdal/lib/$PYTHONVERS/site-packages:\
/export/scratch/ccp/opt/usr/lib64/$PYTHONVERS/site-packages"

# ============================================================================
# *** Crude miscellany

# FIXME: This fcn. is crude. It hardcodes instance names and branch names...
#        two things that don't belong in code.

ccp_base_branch_name_from_instance () {

  db_instance=$1

  if [[ -z "${db_instance}" ]]; then
    echo "Please specify the instance."
    exit 1
  fi

  # MAYBE: Make this a shell utility function.
  if [[ ${db_instance} == 'minnesota' ]]; then
    branch_name='Minnesota'
  elif [[ ${db_instance} == 'colorado' ]]; then
    branch_name='Denver-Boulder'
  else
    echo "Unknown instance: ${db_instance}."
    exit 1
  fi

  # You can only return error values in Bash, so print to stdin.
  # The caller runs, e.g., br_name=`ccp_base_branch_name_from_instance $instnc`
  echo ${branch_name}
}

# ============================================================================
# *** More Installation Specifics

ccp_latest_rev_id () {
  SETPATH="SET search_path TO ${INSTANCE}, public;"
  and_branch_id=""
  if [[ -n ${1} ]]; then
    # FIXME: This is fragile, and it's a weird place for complicated SQL.
    #        This select doesn't care about duplicates but uses an ORDER BY
    #        so if there are duplicates, the same one will always be returned.
    select_brid="\
      SELECT branch.stack_id FROM branch
        JOIN item_versioned USING (system_id)
        WHERE item_versioned.name = '${1}'
        ORDER BY stack_id DESC LIMIT 1"
     and_branch_id="AND branch_id = (${select_brid})"
  fi
  latest_rev_id=`
     PAGER=more \
     psql -U cycling ${CCP_DB_NAME} \
     --no-psqlrc \
     -c "${SETPATH}; \
         SELECT id \
         FROM ${INSTANCE}.revision \
         WHERE id != cp_rid_inf() \
         ${and_branch_id} \
         ORDER BY id DESC \
         LIMIT 1;" \
       -A -t`
   echo ${latest_rev_id}
}

ccp_latest_rev_ts () {
  SETPATH="SET search_path TO ${INSTANCE}, public;"
  # NOTE: Don't use $@, but $*.
  latest_rev_id=$(ccp_latest_rev_id "$*")
  latest_rev_ts=`
     PAGER=more \
     psql -U cycling ${CCP_DB_NAME} \
     --no-psqlrc \
     -c "${SETPATH}; \
         SELECT timestamp \
         FROM ${INSTANCE}.revision \
         WHERE id = ${latest_rev_id};" \
       -A -t`
  echo ${latest_rev_ts}
}

# ============================================================================
# *** Waiting for RouteGuffmanfinder

ccp_routed_ports_where () {

  rf_instance=$1
  if [[ $2 -ne 0 ]]; then
    rf_branch_id=$2
  else
    rf_branch_id="(SELECT cp_branch_baseline_id())"
  fi
  rf_routed_pers=$3
  if [[ -n $4 ]]; then
    rf_purpose=$4
  else
    rf_purpose='general'
  fi

  rf_where_clause="
        instance = '${rf_instance}'
    AND branch_id = ${rf_branch_id}
    AND routed_pers = '${rf_routed_pers}'
    AND purpose = '${rf_purpose}'"

    echo ${rf_where_clause}
}

ccp_routed_ports_ready () {

  # MAYBE: Is there a way to not have to poll?
  #        I.e., how does route analysis wait for its finders to start?

  # NOTE: Most callers will have been the one that started the route finder
  #       service, but there's not an easy way to get its PID, is there.

  rf_where_clause=`ccp_routed_ports_where $1 $2 $3 $4`

  SETPATH="SET search_path TO ${INSTANCE}, public;"
  rf_ready=`
     PAGER=more \
       psql -U cycling ${CCP_DB_NAME} \
     --no-psqlrc \
     -c "${SETPATH}; \
          SELECT ready FROM public.routed_ports \
          WHERE ${rf_where_clause}
          ORDER BY port DESC
          LIMIT 1
          ;" -A -t`

  echo ${rf_ready}
}

ccp_routed_ports_reset () {

  rf_where_clause=`ccp_routed_ports_where $1 $2 $3 $4`

  SETPATH="SET search_path TO ${INSTANCE}, public;"
  rf_deleted=`
     PAGER=more \
       psql -U cycling ${CCP_DB_NAME} \
     --no-psqlrc \
     -c "${SETPATH}; \
          DELETE FROM public.routed_ports \
          WHERE ${rf_where_clause}
          ;" -A -t
          `
  # rf_deleted is, e.g., "DELETE 1".
  # echo ${rf_deleted}
}

ccp_routed_ports_wait () {
  # From man echo
  # -n  do not output the trailing newline
  # -e  enable interpretation of backslash escapes
  #
  # E.g., try
  #  seq 1 1000000 | while read i; do echo -en "\r$i"; done
  time_0=$(date +%s.%N)
  #echo -n "Waiting for route daemon to have loaded... "
  still_waiting=1
  while [[ $still_waiting -ne 0 ]]; do
    time_1=$(date +%s.%N)
    time_e=$(echo "($time_1 - $time_0) / 1.0" | bc -l)
    rf_ready=`ccp_routed_ports_ready $1 $2 $3 $4`
    if [[ $rf_ready == 'f' ]]; then
      echo -en "\rRoute daemon still loading or dead... ${time_e} secs."
      sleep 1
    elif [[ $rf_ready == 't' ]]; then
      still_waiting=0
      # Clear to end of line. See:
      #   http://ascii-table.com/ansi-escape-sequences.php
      echo -en "\rRoute daemon ready after ${time_e} secs.\033[K"
      echo
    else
      still_waiting=0
      echo "WARNING: Route daemon not found in routed_ports."
    fi
  done
}

# ***

