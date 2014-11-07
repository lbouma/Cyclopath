#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# *** Test sandbox

__usage_examples__='

# Dev:

sudo su - $httpd_user
#
/bin/bash
#
cd /ccp/dev/cp/mapserver
./check_cache_now.sh

nohup ./check_cache_now.sh \
  | tee /ccp/var/log/daily/daily-check_cache_now.log \
  2>&1 &

# Cron:

export EDITOR=/usr/bin/vim.basic
crontab -e

# 2013.12.07: Production:

# NOTE: You cannot copy-and-paste these commands.

# First sudo.
sudo su - $httpd_user

# Next, choose Bash.
/bin/bash

# Finally, cxpx freely. [lb] reminds himself of the foreclosure department at 
# Wells Fargo, wherein employees who had trouble making daily quotas b/c they
# could not get signatures would just cxpx freely.

cd /ccp/dev/cycloplan_work/mapserver
nohup ./check_cache_now.sh \
  | tee /ccp/var/log/daily/`date +%Y.%m.%d`.daily-check_cache_now.log \
  2>&1 &

# ^D
# ^D
cd /ccp/var/log/daily/cache
tail -F ../`date +%Y.%m.%d`.daily-check_cache_now.log tc_tiles-*-zooms_*

# ***

# This is if you ./kill_cache_check.sh to start over: that script does not
# remove the flocks or zoom key-vals.

rmdir apache_check_cache_now.sh-lock/
rmdir apache_check_cache_now.sh-lock-apache_check_cache_now.sh/
rm last_rev-minnesota-Mpls-St._Paul.touch

BEGIN;

DELETE FROM key_value_pair WHERE key IN (
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_5',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_6',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_7',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_10',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_8',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_9',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_11',
 'tilecache-last_rid-branch_2500677-skin_bikeways-zoom_12'
 );
-- 8 total

--UPDATE key_value_pair SET value = '1' \
--  WHERE key = 'tilecache-last_rid-branch_2500677';

COMMIT;

'

# *** Common config

script_relbase=$(dirname $0)

# PYSERVER_HOME=${script_relbase}/../pyserver
# if [[ ! -d ${PYSERVER_HOME} ]]; then
#   echo "Unexpected: Where's pyserver/?"
#   exit 1
# fi
# source ${PYSERVER_HOME}/../scripts/util/ccp_base.sh

source ${script_relbase}/../scripts/util/ccp_base.sh
if [[ ! -d ${PYSERVER_HOME} ]]; then
  echo "Unexpected: Where's pyserver/?"
  exit 1
fi

PYTHONPATH=${ccp_python_path}

# *** Installation-specific config

CCP_SKIP_LOCKDIR=0
if [[ $1 == '--force' ]]; then
  CCP_SKIP_LOCKDIR=1
fi

# DEVS: Use this switch you want check_cache_now to look for a database from
# upgrade_ccpv1-v2.sh.
# WARNING: Don't do this for production.
CCP_CONSUME_FRESH_DB=''
#CCP_CONSUME_FRESH_DB='ccpv2_raw'

# [lb] tried making an array and passing the array to a bash shell script,
#      but arguments with whitespace get split into multiple arguments.
#      Even the trick for passing an array to a function doesn't work (see,
#      e.g., arr2_fcn_iter).

# We're already here:
#  cd ${PYSERVER_HOME}/../mapserver

# NOTE: Not logging output. Send to stdout (i.e., cron email).

PYTHONPATH=${PYTHONPATH} \
  PYSERVER_HOME=${PYSERVER_HOME} \
  CCP_SKIP_LOCKDIR=${CCP_SKIP_LOCKDIR} \
  CCP_CONSUME_FRESH_DB=${CCP_CONSUME_FRESH_DB} \
  ./apache_check_cache_now.sh INSTANCE_BRANCH_LIST()

