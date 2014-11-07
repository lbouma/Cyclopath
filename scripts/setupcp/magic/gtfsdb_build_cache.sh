#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# ***

DEBUG_TRACE=false
# DEVS: Uncomment this if you want a cron email.
#DEBUG_TRACE=true

script_relbase=$(dirname $0)
#PYSERVER_HOME=${script_relbase}/../pyserver
PYSERVER_HOME=${script_relbase}/../../../pyserver

PATH+=:/export/scratch/ccp/opt/usr/bin

PYTHONPATH=/export/scratch/ccp/opt/usr/lib/python
PYTHONPATH+=:/export/scratch/ccp/opt/usr/lib/python2.5/site-packages
PYTHONPATH+=:/export/scratch/ccp/opt/gdal/lib/python2.5/site-packages
export PYTHONPATH=${PYTHONPATH}

# C.f. auto_install/prepare_ccp.py 

$DEBUG_TRACE && echo "Updating transit database..."

if true; then

  # Download the Met Council transit data.

  $DEBUG_TRACE && echo -n "Downloading transit data... "

  cd /export/scratch/ccp/var/transit/metc

  wget_resp="`wget -N ftp://gisftp.metc.state.mn.us/google_transit.zip \
              2>&1 | grep 'not retrieving.$'`"

  $DEBUG_TRACE && echo "ok"

  # If wget wgot a new file, compile it. Otherwise, it should already be
  # compiled.

  # Note that grep set $? to 0 on wget success (no grep match) and to 1
  # otherwise (so if $wget_resp == '', then $? is 1).
  if [[ -z "$wget_resp" ]]; then

    $DEBUG_TRACE && echo -n "Compiling transit data... "

    gs_gtfsdb_compile google_transit.zip minnesota.gtfsdb

    gs_import_gtfs minnesota.gdb minnesota.gtfsdb

    # Fix permissions.
    /bin/chmod --silent 666 /export/scratch/ccp/var/transit/metc/*.*

    # To test:
    #       gs_gdb_inspect minnesota.gdb sta-3622

    $DEBUG_TRACE && echo "ok"

    $DEBUG_TRACE && echo -n "Restarting the route finder... "

    cd ${PYSERVER_HOME}
    INSTANCE=minnesota \
    PYTHONPATH=${PYTHONPATH} \
    PYSERVER_HOME=${PYSERVER_HOME} \
      ${PYSERVER_HOME}/routedctl \
        --routed_ver=v2 \
        restart

  else

    $DEBUG_TRACE && echo -n " ... already up to date. See ya!"

  fi

fi

