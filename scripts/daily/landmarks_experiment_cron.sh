#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# ABOUT:
#
# LANDMARKS EXPERIMENT

# ===========================================================================
# *** Debug options

DEBUG_TRACE=false
# DEVS: Uncomment this if you want a cron email.
#DEBUG_TRACE=true

# ===========================================================================
# Utility fcns. and vars.

# This script expects to be run from its directory.
# E.g., /dev/ccp/cp/scripts/daily/landmarks_experiment_cron.sh.
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
# Asynchronous lockdown -- since this script is run by cron, which is pretty
# ignorant about the State of Things, make sure we don't run if we're already
# running (stated differently, cron runs this script every minute, so make sure
# no more than one instance of this script runs at once).

LANDMARKS_EXPERIMENT_LOCKDIR="${CCP_WORKING}/scripts/daily/${script_name}-lock"

# Get the script lock or die trying.

DONT_FLOCKING_CARE=0
FLOCKING_REQUIRED=1
NUM_FLOCKING_TRIES=1
FLOCKING_TIMELIMIT=30
flock_dir \
  "${LANDMARKS_EXPERIMENT_LOCKDIR}" \
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
PYSERVER_HOME=${CCP_WORKING}/pyserver \
INSTANCE=minnesota \
PYTHONPATH=${ccp_python_path} \
  ${script_relbase}/landmarks_experiment_email.py

popd &> /dev/null

# ===========================================================================
# Unlock async lock.

/bin/rmdir "${LANDMARKS_EXPERIMENT_LOCKDIR}" &> /dev/null
/bin/rmdir "${LANDMARKS_EXPERIMENT_LOCKDIR}-${script_name}" &> /dev/null

# ===========================================================================
# Print elapsed time

# bash_base.sh initialized $script_time_0. Say how long we've run.
script_finished_print_time

# ===========================================================================
# All done.

exit 0

# ***

