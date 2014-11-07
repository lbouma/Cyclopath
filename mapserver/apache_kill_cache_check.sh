#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./kill_cache_check.sh

# ===========================================================================
# Utility fcns. and vars.

# Unset PYSERVER_HOME, so ccp_base.sh finds it and sets it absolute.
PYSERVER_HOME=
source ../scripts/util/ccp_base.sh

# ===========================================================================
# *** Ask for user's password just this once.

# Update the user's sudo timestamp, so we can keep it fresh.

#echo
#echo "We need you to be sudo, so you may need to enter your password now."

sudo -v

#echo

# *** Kill, kill, kill.

KILL_COUNT=0
killsomething "tilecache_update\\.py"
killsomething "tilecache_seed\\.py"
killsomething "check_cache_now\\.sh"
echo "Kill count: ${KILL_COUNT}."

# *** Cleanup the lock table.

# The ccp_bash.sh script sets CCP_DB_NAME based on pyserver/CONFIG.

if [[ -z "${CCP_DB_NAME}" ]]; then
  echo "Unable to figure out the name of the database from" \
       "${PYSERVER_HOME}/CONFIG."
else
  echo "Cleaning up async_locks."
  # SYNC_ME: See last_rid_key_prefix in tilecache_update.py.
  echo "DELETE FROM async_locks WHERE lock_name LIKE 'tilecache-last_rid%';" \
    | psql -U cycling ${CCP_DB_NAME}
fi

# DEVS: If tilecache_seed complains about lock files, delete 'em all.
#
#   cd /ccp/var/tilecache-cache/cycloplan_live
#   find . -name ".lck" -type d -exec /bin/rm -rf {} \;
#
# FIXME: [lb] sees the stuck lock problem more often... maybe this should be
#        part of check_cache_now?
#
# find /ccp/var/tilecache-cache/ -name \".lck\" -type d -exec /bin/rm -rf {} \\;

# *** Cleanup the lock directory.

# Actually, don't, in case apache's cron runs check_cache_now.sh frequently.
# Let's not accidentally let it start running again.

# Skipping
#   LOCKDIR="${script_relbase}/${script_name}-lock"
#   /bin/rm -f "${LOCKDIR}"

