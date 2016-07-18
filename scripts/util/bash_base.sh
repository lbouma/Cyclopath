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

script_name=$(basename $0)

script_relbase=$(dirname $0)

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
# *** Chattiness

# If the user is running from a terminal (and not from cron), always be chatty.
# But don't change the debug trace flag if caller set it before calling us.
# NOTE -z is false if DEBUG_TRACE is true or false and true if it's unset.
if [[ -z $DEBUG_TRACE ]]; then
  if [[ "dumb" != "${TERM}" ]]; then
    DEBUG_TRACE=true
  else
    DEBUG_TRACE=false
  fi
fi

# Say hello to the user.

$DEBUG_TRACE && echo "Hello, ${LOGNAME}. (From: bash_base!)"
$DEBUG_TRACE && echo ""

# Time this script

script_time_0=$(date +%s.%N)

# ============================================================================
# *** Apache-related

# Determine the name of the apache user.
if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
  # echo Ubuntu.
  httpd_user=www-data
  httpd_etc_dir=/etc/apache2
elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
  # echo Red Hat.
  httpd_user=apache
  httpd_etc_dir=/etc/httpd
else
  echo "Error: Unknown OS."
  exit 1
fi;

# Reload the Web server.
ccp_apache_reload () {
  if [[ -z "$1" ]]; then
    COMMAND="reload"
  elif [[ $1 -ne 1 ]]; then
    COMMAND="reload"
  else
    COMMAND="restart"
  fi
  if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
    # echo Ubuntu.
    sudo /etc/init.d/apache2 $COMMAND
  elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
    # echo Red Hat.
    sudo service httpd $COMMAND
  else
    echo "Error: Unknown OS."
    exit 1
  fi;
}

# ============================================================================
# *** Python-related

# Determine the Python version-path.

# NOTE: The |& redirects the python output (which goes to stderr) to stdout.

# FIXME: Delete this and use the parsing version below.
#
## FIXME: Is this flexible enough? Probably...
## 2012.08.21: Ubuntu 8.04 does not support the |& redirection syntax?
#if [[ -n "`cat /etc/issue | grep '^Ubuntu 8.04'`" ]]; then
#  PYTHONVERS=python2.5
#  PYVERSABBR=py2.5
#elif [[ -n "`python --version |& grep 'Python 2.7'`" ]]; then
#  PYTHONVERS=python2.7
#  PYVERSABBR=py2.7
#elif [[ -n "`python --version |& grep 'Python 2.6'`" ]]; then
#  PYTHONVERS=python2.6
#  PYVERSABBR=py2.6
#else
#  echo 
#  echo "Unexpected Python version."
#  exit 1
#fi

# Here's another way:
#if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
#  if [[ -n "`cat /etc/issue | grep '^Ubuntu 11.04'`" ]]; then
#    PYTHONVERS=python2.7
#    PYVERSABBR=py2.7
#  elif [[ -n "`cat /etc/issue | grep '^Ubuntu 10.04'`" ]]; then
#    PYTHONVERS=python2.6
#    PYVERSABBR=py2.6
#  else
#    echo "Warning: Unexpected host OS: Cannot set PYTHONPATH."
#  fi
#elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
#  PYTHONVERS=python2.7
#fi

# Convert, e.g., 'Python 2.7.6' to '2.7'.
PYVERS_RAW=`python --version \
	|& /usr/bin/awk '{print $2}' \
	| /bin/sed -r 's/^([0-9]+\.[0-9]+)\.[0-9]+/\1/g'`
PYVERS_DOTLESS=`python --version \
	|& /usr/bin/awk '{print $2}' \
	| /bin/sed -r 's/^([0-9]+)\.([0-9]+)\.[0-9]+/\1\2/g'`
if [[ -z $PYVERS_RAW ]]; then
	echo "Unexpected: Could not parse Python version."
	exit 1
fi
PYVERS_RAW=python${PYVERS_RAW}
PYVERS_RAW_m=python${PYVERS_RAW}m
PYVERS_CYTHON=${PYVERS_DOTLESS}m
#
PYTHONVERS=python${PYVERS_RAW}
PYVERSABBR=py${PYVERS_RAW}

# ============================================================================
# *** Postgres-related

# Set this to, e.g., '8.4' or '9.1'.
#
# Note that if you alias sed, e.g., sed='sed -r', then you'll get an error if
# you source this script from the command line (e.g., it expands to sed -r -r).
# So use /bin/sed to avoid any alias.
POSTGRESABBR=$( \
  psql --version \
  | grep psql \
  | /bin/sed -r 's/psql \(PostgreSQL\) ([0-9]+\.[0-9]+)\.[0-9]+/\1/')
POSTGRES_MAJOR=$( \
  psql --version \
  | grep psql \
  | /bin/sed -r 's/psql \(PostgreSQL\) ([0-9]+)\.[0-9]+\.[0-9]+/\1/')
POSTGRES_MINOR=$( \
  psql --version \
  | grep psql \
  | /bin/sed -r 's/psql \(PostgreSQL\) [0-9]+\.([0-9]+)\.[0-9]+/\1/')

# ============================================================================
# *** Ubuntu-related

# In the regex, \1 is the Fedora release, e.g., '14', and \2 is the friendly
# name, e.g., 'Laughlin'.
FEDORAVERSABBR=$(cat /etc/issue \
                 | grep Fedora \
                 | /bin/sed 's/^Fedora release ([0-9]+) \((.*)\)$/\1/')
# /etc/issue is, e.g., 'Ubuntu 12.04 LTS (precise) \n \l'
#UBUNTUVERSABBR=$(cat /etc/issue \
#                 | grep Ubuntu \
#                 | /bin/sed -r 's/^Ubuntu ([.0-9]+) [^(]*\((.*)\).*$/\1/')
UBUNTUVERSABBR=$(cat /etc/issue | grep Ubuntu | /bin/sed -r 's/^Ubuntu ([.0-9]+) .*$/\1/')
# /etc/issue is, e.g., 'Linux Mint 16 Petra \n \l'
MINTVERSABBR=$(cat /etc/issue \
               | grep "Linux Mint" \
               | /bin/sed -r 's/^Linux Mint ([.0-9]+) .*$/\1/')

# ============================================================================
# *** Common script fcns.

check_prev_cmd_for_error () {
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 last_status log_file [no_errexit] [ignr_case] [just_tail]"
    exit 1;
  fi;
  PREV_CMD_VALUE=$1
  SAVED_LOG_FILE=$2
  DONT_EXIT_ON_ERROR=$3
  ERROR_IGNORE_CASE=$4
  JUST_TAIL_FILE=$5
  #
  if [[ -z $JUST_TAIL_FILE ]]; then
    JUST_TAIL_FILE=0
  fi
  #
  #$DEBUG_TRACE && echo "check_prev: ext code: ${PREV_CMD_VALUE}"
  #$DEBUG_TRACE && echo "check_prev: grep err: " `grep ERROR ${SAVED_LOG_FILE}`
  #
  # pyserver's logging2.py uses 4-char wide verbosity names, so ERROR is ERRR.
  # NOTE: We're usually case-sensitive. Real ERRORs should be capitalized.
  #       BUT: Sometimes you don't want to care.
  if [[ -z ${ERROR_IGNORE_CASE} || ${ERROR_IGNORE_CASE} -eq 0 ]]; then
    GREP_CMD="/bin/grep 'ERRO\?R'"
  else
    GREP_CMD="/bin/grep -i 'ERRO\?R'"
  fi
  if [[ -z ${JUST_TAIL_FILE} || ${JUST_TAIL_FILE} -eq 0 ]]; then
    FULL_CMD="${GREP_CMD} ${SAVED_LOG_FILE}"
  else
    FULL_CMD="tail -n ${JUST_TAIL_FILE} ${SAVED_LOG_FILE} | ${GREP_CMD}"
  fi
  # grep return 1 if there's no match, so make sure we don't exit
  set +e
  GREP_RESP=`eval $FULL_CMD`
  #set -e
  if [[ ${PREV_CMD_VALUE} -ne 0 || -n "${GREP_RESP}" ]]; then
    echo "Some script failed. Please examine the output in"
    echo "   ${SAVED_LOG_FILE}"
    # Also append the log file (otherwise error just goes to, e.g., email).
    echo "" >> ${SAVED_LOG_FILE}
    echo "ERROR: check_prev_cmd_for_error says we failed" >> ${SAVED_LOG_FILE}
    # (Maybe) stop everything we're doing.
    if [[ -z $DONT_EXIT_ON_ERROR || $DONT_EXIT_ON_ERROR -eq 0 ]]; then
      exit 1
    fi
  fi
}

exit_on_last_error () {
  LAST_ERROR=$1
  LAST_CMD_HINT=$2
  if [[ $LAST_ERROR -ne 0 ]]; then
    echo "ERROR: The last command failed: '$LAST_CMD_HINT'"
    exit 1
  fi
}

wait_bg_tasks () {

  WAITPIDS=$1
  WAITLOGS=$2
  WAITTAIL=$3

  $DEBUG_TRACE && echo "Checking for background tasks: WAITPIDS=${WAITPIDS[*]}"
  $DEBUG_TRACE && echo "                           ... WAITLOGS=${WAITLOGS[*]}"
  $DEBUG_TRACE && echo "                           ... WAITTAIL=${WAITTAIL[*]}"

  if [[ -n ${WAITPIDS} ]]; then

    time_1=$(date +%s.%N)
    $DEBUG_TRACE && printf "Waiting for background tasks after %.2F mins.\n" \
        $(echo "(${time_1} - ${script_time_0}) / 60.0" | bc -l)

    # MAYBE: It'd be nice to detect and report when individual processes
    #        finish. But wait doesn't have a timeout value.
    wait ${WAITPIDS[*]}
    # Note that $? is the exit status of the last process waited for.

    # The subprocesses might still be spewing to the terminal so hold off a
    # sec, otherwise the terminal prompt might get scrolled away after the
    # script exits if a child process output is still being output (and if that
    # happens, it might appear to the user that this script is still running
    # (or, more accurately, hung), since output is stopped but there's no
    # prompt (until you hit Enter and realize that script had exited and what
    # you're looking at is background process blather)).

    sleep 1

    $DEBUG_TRACE && echo "All background tasks complete!"
    $DEBUG_TRACE && echo ""

    time_2=$(date +%s.%N)
    $DEBUG_TRACE && printf "Waited for background tasks for %.2F mins.\n" \
        $(echo "(${time_2} - ${time_1}) / 60.0" | bc -l)

  fi

  # We kept a list of log files that the background processes to done wrote, so
  # we can analyze them now for failures.
  no_errexit=1
  if [[ -n ${WAITLOGS} ]]; then
    for logfile in ${WAITLOGS[*]}; do
      check_prev_cmd_for_error $? ${logfile} ${no_errexit}
    done
  fi

  if [[ -n ${WAITTAIL} ]]; then
    # Check the log_jammin.py log file, which might contain free-form
    # text from the SVN log (which contains the word "error").
    no_errexit=1
    ignr_case=1
    just_tail=25
    for logfile in ${WAITTAIL[*]}; do
      check_prev_cmd_for_error $? ${logfile} \
        ${no_errexit} ${ignr_case} ${just_tail}
    done
  fi

}

# ============================================================================
# *** Machine I.P. address

# There are lots of ways to get the machine's IP address:
#   $ ip addr show
# or, to filter,
#   $ ip addr show eth0
#   2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP ...
#       link/ether d4:ae:52:73:42:c4 brd ff:ff:ff:ff:ff:ff
#       inet 128.101.34.16/24 brd 128.101.34.255 scope global eth0
# You can also use nslookup:
#   $ nslookup runic
#   Server:   128.101.34.21
#   Address:  128.101.34.21#53
#   Name:     ccp.server.tld
#   Address:  123.456.78.90
# Or ifconfig, again filtering by device,
#   $ ifconfig eth0
#   eth0      Link encap:Ethernet  HWaddr d4:ae:52:73:42:c4  
#             inet addr:128.101.34.16  Bcast:128.101.34.255  Mask:255.255.255.0
#             ...
# But probably the easiest to parse is host:
#   $ host -t a ${CP_PRODNAME}
#   ${CS_PRODUCTION} has address 123.456.78.90

test_opts=`echo $SHELLOPTS | grep errexit` >/dev/null 2>&1
errexit_was_set=$?
set +e

MACHINE_IP=`host -t a ${HOSTNAME} | awk '{print $4}' | egrep ^[1-9]`
if [[ $? != 0 ]]; then
  MACHINE_IP=`ifconfig eth0 | grep "inet addr" \
              | sed "s/.*inet addr:([.0-9]+).*/\1/" \
              2> /dev/null`
  if [[ $? != 0 ]]; then
    MACHINE_IP=`ifconfig eth0 | grep "inet addr" \
                | sed "s/.*inet addr:\([.0-9]\+\).*/\1/" \
                2> /dev/null`
  fi
  if [[ $? != 0 ]]; then
    echo -e "\nWARNING: Could not determine the machine's IP address."
  fi
fi

if [[ $errexit_was_set == 0 ]]; then
  set -e
fi

# ============================================================================
# *** Script timering

script_finished_print_time () {
  time_1=$(date +%s.%N)
  $DEBUG_TRACE && echo ""
  $DEBUG_TRACE && printf "All done: Elapsed: %.2F mins.\n" \
      $(echo "($time_1 - $script_time_0) / 60.0" | bc -l)
}

# ============================================================================
# *** Bash array contains

# Named after flashclient.utils.misc.Collection.array_in:
# and graciously c/x/p/d/ed from
#   http://stackoverflow.com/questions/3685970/bash-check-if-an-array-contains-a-value
array_in () {
  local elem
  for elem in "${@:2}"; do
    if [[ "$elem" == "$1" ]]; then
      return 0;
    fi
  done
  # WATCH_OUT: If the calling script is using 'set -e' it's going to exit!
  # MAYBE: Can we call 'set +e' here, before returning? Or warn?
  return 1
}

# ============================================================================
# *** Bash array multidimensionalization

# In Bash, arrays are one-dimensional, though they allow multiple word entries.
# But when you pass an array as a function parameter, it gets flattened.
#
# Consider an array of names and ages. You cannot use =() when entries have
# multiple words. E.g., this is wrong,
#
#   people=("'chester a. arthur' 45" "'maurice moss' 26")
#
# because ${people[1][0]} => 'maurice moss' 26
#
# And you cannot set another list (multidimensionality); this doesn't work,
#
#   people[0]=("chester a. arthur" 45)
#
# But you can make a long, flat list.
#
#   people=("chester a. arthur" "45"
#           "maurice moss" "26")
#
# where ${people[2]} => maurice moss
# 
# So this fcn. wraps a flat list and treats it as a 2-dimensional array,
# using the elements in each sub-array as arguments to the function on
# which we're iterating.

arr2_fcn_iter () {
  the_fcn=$1
  cols_per_row=$2
  # This is a sneaky way to pass an array in Bash -- pass it's name.
  # The bang operator here resolves a name to a variable value.
  two_dim_arr=("${!3}")
  arr_total_rows=$((${#two_dim_arr[@]} / ${cols_per_row}))
  for arr_index in $(seq 0 $((${arr_total_rows} - 1))); do
    beg_index=$((${arr_index} * ${cols_per_row}))
    fin_index=$((${beg_index} + ${cols_per_row}))
    # This doesn't work:
    #   the_fcn ${two_dim_arr[*]:${beg_index}:${fin_index}}
    # because if you have spaces in any one param the fcn. will get
    # words around the spaces as multiple params.
    # WHATEVER: [lb] doesn't care anymore. Ignoring $cols_per_row
    #                                      and hard-coding))]}.
    if [[ ${cols_per_row} -lt 10 ]]; then
      ${the_fcn} "${two_dim_arr[$((${beg_index} + 0))]}" \
                 "${two_dim_arr[$((${beg_index} + 1))]}" \
                 "${two_dim_arr[$((${beg_index} + 2))]}" \
                 "${two_dim_arr[$((${beg_index} + 3))]}" \
                 "${two_dim_arr[$((${beg_index} + 4))]}" \
                 "${two_dim_arr[$((${beg_index} + 5))]}" \
                 "${two_dim_arr[$((${beg_index} + 6))]}" \
                 "${two_dim_arr[$((${beg_index} + 7))]}" \
                 "${two_dim_arr[$((${beg_index} + 8))]}" \
                 "${two_dim_arr[$((${beg_index} + 9))]}"
    else
      echo "Too many arguments for arr2_fcn_iter, sorry!" 1>&2
      exit 1
    fi
  done
}

# ============================================================================
# *** Llik gnihtemos.

killsomething () {
  something=$1
  # The $2 is the awk way of saying, second column. I.e., ps aux shows
  #   apache 27635 0.0 0.1 238736 3168 ? S 12:51 0:00 /usr/sbin/httpd
  # and awk splits it on whitespace and sets $1..$11 to what was split.
  # You can even {print $99999} but it's just a newline for each match.
  somethings=`ps aux | grep "${something}" | awk '{print $2}'`
  # NOTE: This does the same thing.
  # somethings=`ps aux | grep "${something}" | awk {'print $2'}`
  count_it=0
  if [[ "$somethings" != "" ]]; then
    echo $somethings | xargs sudo kill -s 9 >/dev/null 2>&1
    count_it=$((count_it + 1))
  fi
  # ?: ps aux | grep routedctl | awk '{print $2}' | xargs sudo kill -s 9
  #echo "Kill count: ${count_it}."
  KILL_COUNT=$((${KILL_COUNT} + ${count_it}))
  return 0
}

# ============================================================================
# *** Call ista Flock hart

# Tries to mkdir a directory that's been used as a process lock.
#
# DEVS: This fcn. calls `set +e` but doesn't reset it ([lb] doesn't know how
# to find the current value of that option so we can restore it; oh well).

flock_dir () {

  not_got_lock=1

  FLOCKING_DIR_PATH=$1
  DONT_FLOCKING_CARE=$2
  FLOCKING_REQUIRED=$3
  FLOCKING_RE_TRIES=$4
  FLOCKING_TIMELIMIT=$5
  if [[ -z $FLOCKING_DIR_PATH ]]; then
    echo "Missing flock dir path"
    exit 1
  fi
  if [[ -z $DONT_FLOCKING_CARE ]]; then
    DONT_FLOCKING_CARE=0
  fi
  if [[ -z $FLOCKING_REQUIRED ]]; then
    FLOCKING_REQUIRED=0
  fi
  if [[ -z $FLOCKING_RE_TRIES ]]; then
    # Use -1 to mean forever, 0 to mean never, or 1 to mean once, 2 twice, etc.
    FLOCKING_RE_TRIES=0
  fi
  if [[ -z $FLOCKING_TIMELIMIT ]]; then
    # Use -1 to mean forever, 0 to ignore, or max. # of secs.
    FLOCKING_TIMELIMIT=0
  fi

  set +e # Stay on error

  fcn_time_0=$(date +%s.%N)

  $DEBUG_TRACE && echo "Attempting grab on mutex: ${FLOCKING_DIR_PATH}"

  resp=`/bin/mkdir "${FLOCKING_DIR_PATH}" 2>&1`
  if [[ $? -eq 0 ]]; then
    # We made the directory, meaning we got the mutex.
    $DEBUG_TRACE && echo "Got mutex: yes, running script."
    $DEBUG_TRACE && echo ""
    not_got_lock=0
  elif [[ ${DONT_FLOCKING_CARE} -eq 1 ]]; then
    # We were unable to make the directory, but the dev. wants us to go on.
    #
    # E.g., mkdir: cannot create directory `tmp': File exists
    if [[ `echo $resp | grep exists` ]]; then
      $DEBUG_TRACE && echo "Mutex exists and owned but: DONT_FLOCKING_CARE."
      $DEBUG_TRACE && echo ""
    #
    # E.g., mkdir: cannot create directory `tmp': Permission denied
    elif [[ `echo $resp | grep denied` ]]; then
      $DEBUG_TRACE && echo "Mutex cannot be created but: DONT_FLOCKING_CARE."
      $DEBUG_TRACE && echo ""
    #
    else
      $DEBUG_TRACE && echo "ERROR: Unexpected response from mkdir: $resp."
      $DEBUG_TRACE && echo ""
      exit 1
    fi
  else
    # We could not get the mutex.
    #
    # We'll either: a) try again; b) give up; or c) fail miserably.
    #
    # E.g., mkdir: cannot create directory `tmp': Permission denied
    if [[ `echo $resp | grep denied` ]]; then
      # This is a developer problem. Fix perms. and try again.
      echo ""
      echo "=============================================="
      echo "ERROR: The directory could not be created."
      echo "Hey, you, DEV: This is probably _your_ fault."
      echo "Try: chmod 2777 `dirname ${FLOCKING_DIR_PATH}`"
      echo "=============================================="
      echo ""
    #
    # We expect that the directory already exists... though maybe the other
    # process deleted it already!
    #   elif [[ ! `echo $resp | grep exists` ]]; then
    #     $DEBUG_TRACE && echo "ERROR: Unexpected response from mkdir: $resp."
    #     $DEBUG_TRACE && echo ""
    #     exit 1
    #   fi
    else
      # Like Ethernet, retry, but with a random backoff. This is because cron
      # might be running all of our scripts simultaneously, and they might each
      # be trying for the same locks to see what to do -- and it'd be a shame
      # if every time cron ran, the same script won the lock contest and all of
      # the other scripts immediately bailed, because then nothing would
      # happen!
      #
      # NOTE: If your wait logic here could exceed the interval between crons,
      #       you could end up with always the same number of scripts running.
      #       E.g., consider one instance of a script running for an hour, but
      #       every minute you create a process that waits up to three minutes
      #       for the lock -- at minute 0 is the hour-long process, and minute
      #       1 is a process that tries for the lock until minute 4; at minute
      #       2 is a process that tries for the lock until minute 5; and so
      #       on, such that, starting at minute 4, you'll always have the
      #       hour-long process and three other scripts running (though not
      #       doing much, other than sleeping and waiting for the lock every
      #       once in a while).
      #
      spoken_once=false
      while [[ ${FLOCKING_RE_TRIES} -ne 0 ]]; do
        if [[ ${FLOCKING_RE_TRIES} -gt 0 ]]; then
          FLOCKING_RE_TRIES=$((FLOCKING_RE_TRIES - 1))
        fi
        # Pick a random number btw. 1 and 10.
        RAND_0_to_10=$((($RANDOM % 10) + 1))
        #$DEBUG_TRACE && echo \
        #  "Mutex in use: will try again after: ${RAND_0_to_10} secs."
        if ! ${spoken_once}; then
          $DEBUG_TRACE && echo \
            "Mutex in use: will retry at most ${FLOCKING_RE_TRIES} times " \
            "or for at most ${FLOCKING_TIMELIMIT} secs."
          spoken_once=true
          spoken_time_0=$(date +%s.%N)
        fi
        sleep ${RAND_0_to_10}
        # Try again.
        resp=`/bin/mkdir "${FLOCKING_DIR_PATH}" 2>&1`
        success=$?
        # Get the latest time.
        fcn_time_1=$(date +%s.%N)
        elapsed_time=$(echo "($fcn_time_1 - $fcn_time_0) / 1.0" | bc -l)
        # See if we made it.
        if [[ ${success} -eq 0 ]]; then
          $DEBUG_TRACE && echo "Got mutex: took: ${elapsed_time} secs." \
                                "/ tries left: ${FLOCKING_RE_TRIES}."
          $DEBUG_TRACE && echo ""
          not_got_lock=0
          FLOCKING_RE_TRIES=0
        elif [[ ${FLOCKING_TIMELIMIT} > 0 ]]; then
          # [lb] doesn't know how to compare floats in bash, so divide by 1
          #      to convert to int.
          if [[ $elapsed_time -gt ${FLOCKING_TIMELIMIT} ]]; then
            $DEBUG_TRACE && echo "Could not get mutex: ${FLOCKING_DIR_PATH}."
            $DEBUG_TRACE && echo "Waited too long for mutex: ${elapsed_time}."
            $DEBUG_TRACE && echo ""
            FLOCKING_RE_TRIES=0
          else
            # There's still time left, but see if an echo is in order.
            last_spoken=$(echo "($fcn_time_1 - $spoken_time_0) / 1.0" | bc -l)
            # What's a good time here? Every ten minutes?
            if [[ $last_spoken -gt 600 ]]; then
              elapsed_mins=$(echo "($fcn_time_1 - $fcn_time_0) / 60.0" | bc -l)
              $DEBUG_TRACE && echo "Update: Mutex still in use after: "\
                                   "${elapsed_mins} mins.; still trying..."
              spoken_time_0=$(date +%s.%N)
            fi
          fi
        # else, loop forever, maybe. ;)
        fi
      done
    fi
  fi

  if [[ ${not_got_lock} -eq 0 ]]; then
    /bin/chmod 2777 "${FLOCKING_DIR_PATH}" &> /dev/null
    # Let the world know who's the boss
    /bin/mkdir -p "${FLOCKING_DIR_PATH}-${script_name}"
  elif [[ ${FLOCKING_REQUIRED} -ne 0 ]]; then
    $DEBUG_TRACE && echo "Mutex in use: giving up!"
  
    $DEBUG_TRACE && echo "Could not secure flock dir: Bailing now."
    $DEBUG_TRACE && echo "FLOCKING_DIR_PATH: ${FLOCKING_DIR_PATH}"
    exit 1
  fi

  return $not_got_lock
}

# ============================================================================
# *** Logs Rot.

# This fcn. is not used. It was writ for logrotate but an alternative solution
# was implemented.
logrot_backup_file () {
  log_path=$1
  if [[ -f ${log_path} ]]; then
    log_name=$(basename $log_path)
    log_relbase=$(dirname $log_path)
    last_touch=${log_relbase}/archive-logcheck/${log_name}
    # Using the touch file wouldn't be necessary if logrotate's
    # postrotate worked with apache, but the server has to be
    # restarted, so we use lastaction, and at that point, we
    # don't know if the log file we're looking at has been backed
    # up or not. So we use a touch file to figure it out.
    if [[ ! -e ${last_touch} || ${log_path} -nt ${last_touch} ]]; then
      # Remember not to backup again.
      touch ${last_touch}
      # How to remove the file extension from the file name. Thanks to:
      # http://stackoverflow.com/questions/125281/how-do-i-remove-the-
      #        file-suffix-and-path-portion-from-a-path-string-in-bash
      # $ x="/foo/fizzbuzz.bar.quux"
      # $ y=${x%.*}
      # $ echo $y
      # /foo/fizzbuzz.bar
      # $ y=${x%%.*}
      # $ echo $y
      # /foo/fizzbuzz
      extless=${log_name%.*}
      today=`date '+%Y.%m.%d'`
      bkup=${log_relbase}/archive-logcheck/${extless}-${today}.gz
      # "-c --stdout Write output on std out; keep orig files unchanged"
      # "-9 --best indicates the slowest compression method (best comp.)"
      gzip -c -9 ${log_path} > ${bkup}
    fi
  fi
}

# ============================================================================
# *** No more bashy goodness.

