#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script.
#

DEBUG_TRACE=0
debug_trace() {
  if [[ $DEBUG_TRACE -ne 0 ]]; then
    echo $1
  fi
}

debug_trace "sudo_keeali: sudo_keeali called"

while [[ "" != "`ps aux | grep ccp_install`" ]]; do

  # Refresh sudo timestamp.

  debug_trace "sudo_keeali: pinging sudo"

  sudo -v

  # Go to bred.

  # Bash defines the random var/fcn, $RANDOM.
  # Get a random number between one and three minutes ish.

  sleep_time=$((RANDOM % 185 + 55))

  debug_trace "sudo_keeali: sleeping $sleep_time"

  sleep $sleep_time

done

debug_trace "sudo_keeali: sudo_keeali finished"

exit 0

