#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# SYNC_ME: This file is C.f. but more concise than check_cache_now-template.sh.

# *** Test sandbox

__usage_examples__='

cd /ccp/dev/cp/mapserver
./kill_cache_check.sh

'

# *** Common config

script_relbase=$(dirname $0)

source ${script_relbase}/../scripts/util/ccp_base.sh
if [[ ! -d ${PYSERVER_HOME} ]]; then
  echo "Unexpected: Where's pyserver/?"
  exit 1
fi

PYTHONPATH=${ccp_python_path}

# ***

PYTHONPATH=${PYTHONPATH} \
  PYSERVER_HOME=${PYSERVER_HOME} \
  ./apache_kill_cache_check.sh

