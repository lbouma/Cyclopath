#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# ABOUT:
#
# Email users whose /user/alert_email link_value-attributes tell us to.

# ===========================================================================
# *** Debug options

DEBUG_TRACE=false
# DEVS: Uncomment this if you want a cron email.
#DEBUG_TRACE=true

# ===========================================================================
# Utility fcns. and vars.

# This script expects to be run from its directory.
# E.g., /dev/ccp/cp/scripts/daily/watchers_emailer.sh.
script_relbase=$(dirname $0)
source ${script_relbase}/../util/ccp_base.sh

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
# Asynchronous lockdown -- cron happily runs new instances of this script
# whenever we've scheduled it to do so, but really we only want one instance
# of the script to ever run at any one time.

WATCHERS_EMAILER_LOCKDIR="${CCP_WORKING}/scripts/daily/${script_name}-lock"

# Get the script lock or die trying.

DONT_FLOCKING_CARE=0
FLOCKING_REQUIRED=1
NUM_FLOCKING_TRIES=1
FLOCKING_TIMELIMIT=5
flock_dir \
  "${WATCHERS_EMAILER_LOCKDIR}" \
  ${DONT_FLOCKING_CARE} \
  ${FLOCKING_REQUIRED} \
  ${NUM_FLOCKING_TRIES} \
  ${FLOCKING_TIMELIMIT}

# If we're here, it means the lock succeeded; otherwise, flock_dir exits.

# ===========================================================================
# LANDMARKS EXPERIMENT
#
# If we're the only instance of this script, um, run the real script.
#
# NOTE: Cron will email us any script output. So the script should only babble
#       if there's an error.

pushd ${CCP_WORKING}/scripts/daily &> /dev/null

# FIXME: Hard-coding the INSTANCE just to make the script run without a lot of
#        fuss (or using the arr2_fcn_iter trick that the other cron
#        *.sh-template files use).
#        2013.10.18: [lb] discourages separate instances, anyway, since you
#                    can just as easily make disparate branches -- the only
#                    difference being storing all of the data in one table
#                    and WHEREing by branch_id, or storing halves of the
#                    data in tables in separate schemas, and then managing
#                    each schema specifically... anyway, 'minnesota' is all
#                    Cycloplan uses, so 'minnesota' it is.
# NOTE: ${CCP_INSTANCE} is not the same as the database schema instance (it's
#       the Cyclopath installation instance, or the /ccp/dev/{folder_name}.
PYTHONPATH=${PYTHONPATH} \
  PYSERVER_HOME=${CCP_WORKING}/pyserver \
  INSTANCE=minnesota \
    ${script_relbase}/watchers_emailer.py

popd &> /dev/null

# ===========================================================================
# Unlock async lock.

/bin/rmdir "${WATCHERS_EMAILER_LOCKDIR}" &> /dev/null
/bin/rmdir "${WATCHERS_EMAILER_LOCKDIR}-${script_name}" &> /dev/null

# ===========================================================================
# Print elapsed time

# bash_base.sh initialized $script_time_0. Say how long we've run.
script_finished_print_time

# ===========================================================================
# All done.

exit 0

# ***

