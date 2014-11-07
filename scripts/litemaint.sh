#!/bin/bash

# Copyright (c) 2006-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Enables/disables "lite maintenance mode" -- so client can
# politely tell user to save their changes, and to warn
# editors and new editors when in maintenance mode.

# Usage: To disable (editing enabled):
#             ./litemaint.sh 0
#        To start countdown to disabled editing, e.g., in 15 mins,
#           for an expected two-and-a-half hours or maintenance:
#             ./litemaint.sh '15 mins' '2.5 hours'
#        To revise the downtime estimate, e.g., to reset expected
#           downtime to two hours:
#             ./litemaint.sh '0 min' '2 hours'
#        Note the '0 min' is so that we remain in maintainence mode
#           or enable it if not already enabled (as opposed
#           to '0' which would disable maintenance mode).
#        To add a message to everyflashclient:
#             ./litemaint.sh 'Some <b>important</b> information.'
#        To disable said message:
#             ./litemaint.sh '-'

set -e

DEBUG_TRACE=false

script_relbase=$(dirname $0)

source ${script_relbase}/util/ccp_base.sh

if [[ ! -d ${PYSERVER_HOME} ]]; then
  echo "Unexpected: Where's pyserver/?"
  exit 1
fi

if [[ -z "${CCP_DB_NAME}" ]]; then
  echo "Unexpected: Please specify CCP_DB_NAME or setup pyserver/CONFIG"
  exit 1
fi

if [[ -z "${INSTANCE}" ]]; then
  echo "Unexpected: Please set the INSTANCE environment variable"
  exit 1
fi

MAINT_BEG=$1
MAINT_FIN=$2
MAINT_MSG=
if [[ -z $2 && -n $1 && $1 != '0' ]]; then
  MAINT_BEG=
  MAINT_MSG=$1
fi

update_cp_maint () {
  if [[ -z $2 || $2 == "0" ]]; then
    interval="''"
  else
    # Specify a date interval value. See:
    #  http://www.postgresql.org/docs/8.4/interactive/functions-datetime.html
    # E.g., '1 hour', '2.5 days', '15 mins'.
    interval="CURRENT_TIMESTAMP + INTERVAL '$2'"
  fi
  if [[ -n $3 && $3 != "0" ]]; then
    interval="${interval} + INTERVAL '$3'"
  fi
  response=$(
    psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
      -c "UPDATE ${INSTANCE}.key_value_pair \
          SET value = ${interval} \
          WHERE key = '$1';" \
    )
  if [[ $response == 'UPDATE 0' ]]; then
    psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
      -c "INSERT INTO ${INSTANCE}.key_value_pair \
          (value, key) VALUES (${interval}, '$1');"
  fi
}

display_cp_maint () {
  psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
    -c "SELECT value FROM ${INSTANCE}.key_value_pair \
        WHERE key = '$1';"
}

update_pyserver_msg () {
  response=$(
    psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
      -c "UPDATE ${INSTANCE}.key_value_pair \
          SET value = '$2' \
          WHERE key = '$1';" \
    )
  if [[ $response == 'UPDATE 0' ]]; then
    psql -U cycling --no-psqlrc -d ${CCP_DB_NAME} -tA \
      -c "INSERT INTO ${INSTANCE}.key_value_pair \
          (value, key) VALUES ('$2', '$1');"
  fi
}

if [[ -n $MAINT_BEG ]]; then
  echo "Setting cp_maint_beg and cp_maint_fin."
  update_cp_maint 'cp_maint_beg' "$MAINT_BEG"
  update_cp_maint 'cp_maint_fin' "$MAINT_FIN" "$MAINT_BEG"
elif [[ -n $MAINT_MSG ]]; then
  if [[ $MAINT_MSG != '-' ]]; then
    echo "Setting cp_pyserver_msg1."
    update_pyserver_msg 'cp_pyserver_msg1' "$MAINT_MSG"
  else
    echo "Clearing cp_pyserver_msg1."
    update_pyserver_msg 'cp_pyserver_msg1' ""
  fi
fi

# Always spit out the current values.

if [[ -z $MAINT_BEG && -z $MAINT_MSG ]]; then
  echo "USAGE:"
  echo "Turn off maintenance mode now: ${0} 0"
  echo "Turn on maintenance in x time"
  echo "                   for y time: ${0} '15 mins' '2.5 hours', e.g."
  echo "Extend maintenance for y time: ${0} '0 min' '2.5 hours', e.g."
  echo "Update pyserver message: ${0} 'Latest release: <b>Jun 12, 2014</b>'"
  echo "Remove pyserver message (use a dash): ${0} '-'"
fi

echo -n "cp_maint_beg: "
display_cp_maint 'cp_maint_beg'
echo -n "cp_maint_fin: "
display_cp_maint 'cp_maint_fin'

CP_MAINT_LOCK_PATH=`/bin/egrep "^cp_maint_lock_path: +" \
  ${PYSERVER_HOME}/CONFIG \
  | /bin/sed -r 's/^cp_maint_lock_path: +//'`
echo -n "cp_maint_lock: "
if [[ -e ${CP_MAINT_LOCK_PATH} ]]; then
  stat --format="%y" ${CP_MAINT_LOCK_PATH}
else
  echo "not locked"
fi

echo -n "cp_pyserver_msg1: "
display_cp_maint 'cp_pyserver_msg1'

