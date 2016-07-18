#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./prepare_ccp.sh
#  (also called from ccp_install.sh)

# NOTE: This script calls sudo a few times. If this is your own virtual
#       machine, that's great, otherwise, you gotta be staff at the U
#       and have lab-wide sudo to run this script.

# FIXME: The Cyclopath db schema, 'minnesota', is hard coded throughout.

# Exit on error.
set -e

#script_relbase=$(dirname $0)
#script_absbase=`pwd $script_relbase`
echo "SCRIPT_DIR=\$(dirname \$(readlink -f $0))"
SCRIPT_DIR=$(dirname $(readlink -f $0))

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its 
#          variables become ours.
. ${SCRIPT_DIR}/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,
#            reload_databases, PYTHONVERS, and httpd_user.

# *** Helper fcns.

# Load the helpers, i.e., ccp_mkdir.

# FIXME: del me if works from check_parms
#. ${SCRIPT_DIR}/helpers_lib.sh

# *** Begin.

echo
echo "Preparing Cyclopath!"

# Kick sudo. Prompt user now rather than later.
sudo -v

# *** Setup ccp/dev

# *** Prepare the transit cache.

# Download and compile

compile_tx_data=0
if ! [[ -e /scratch/$masterhost/ccp/var/transit/metc/minnesota.gdb ]]; then
  compile_tx_data=1
fi
if [[ "$masterhost" == "$HOSTNAME" ]]; then
  compile_tx_data=1
fi

if [[ 0 -ne $compile_tx_data ]]; then

  # Download the Met Council transit data.

  # MAGIC_NUMBER/SYNC_ME: See: /ccp/dev/cp/pyserver/CONFIG|291|
  #     transit_db_source: ftp://gisftp.metc.state.mn.us/google_transit.zip

  echo -n "Downloading transit data... "
  /bin/mkdir -p /ccp/var/transit/metc
  cd /ccp/var/transit/metc
  set +ex
  wget_resp="`wget -N ftp://gisftp.metc.state.mn.us/google_transit.zip \
              |& grep 'not retrieving.$'`"
  set -e
  echo "ok"
  echo

  # If wget wgot a new file, compile it. Otherwise, it should already be
  # compiled.
  if [[ -z "$wget_resp" || ! -e /ccp/var/transit/metc/minnesota.gdb ]]; then
    echo -n "Compiling transit data... "
    gs_gtfsdb_compile google_transit.zip minnesota.gtfsdb
    gs_import_gtfs minnesota.gdb minnesota.gtfsdb
    # Fix permissions.
    sudo chmod 664 /ccp/var/transit/metc/*.*
    # To test:
    #       gs_gdb_inspect minnesota.gdb sta-3622
    echo "ok"
  echo
  fi

else

  # Rather than compile the transit data, just copy from the master host.

  /bin/cp -f /scratch/$masterhost/ccp/var/transit/metc/minnesota.gdb \
    /ccp/var/transit/metc/minnesota.gdb

  /bin/cp -f /scratch/$masterhost/ccp/var/transit/metc/minnesota.gtfsdb \
    /ccp/var/transit/metc/minnesota.gtfsdb

  /bin/cp -f /scratch/$masterhost/ccp/var/transit/metc/google_transit.zip \
    /ccp/var/transit/metc/google_transit.zip

fi

# Share rights with www-data, so it can update the transit database, too.

# This isn't necessary in CcpV2, is it, because the branch maintainer's account
# does the update and not the www-data user?
# Not needed?: /bin/sudo chmod 666 /ccp/var/transit/metc/*.*

# *** Download and setup the sources

ccp_mkdir /ccp/dev

ccp_kill_fcsh () {
  # Kill the compiler.
  # NOTE: fcsh-wrap has been updated to do this, too, so 'make clean' should
  # finally work as expected (and actually find and kill fcsh-wrap, rather than
  # relying on out of data PID files that tell lies).
  set +e
  echo -n "Killing fcsh... "
  pids=$(ps aux \
         | grep -e bin/fcsh$ -e lib/fcsh.jar$ -e "python ./fcsh-wrap" \
         | grep -v grep \
         | awk '{print $2}')
  for pid in $pids; do
     sudo kill -s 9 $pid > /dev/null
  done
  echo "ok"
  set -e
}

killfc () {
  ccp_kill_fcsh
}

remake () {
  killfc
  sleep 1
  make clean
  make one
  max_tries=5
  success=1
  while [[ $max_tries -gt 0 ]]; do
     make again
     # Running grep works, but it outputs, so rather than redirect...
     #   grep Error /tmp/flashclient_make
     #     if [[ $? == 0 ]]; then ... fi
     if [[ "`cat /tmp/flashclient_make | grep Error`" ]]; then
        max_tries=$((max_tries-1))
     else
        max_tries=-1
        success=0
     fi
  done
  if [[ $max_tries -eq 0 ]]; then
     echo 'I give up!'
  fi
  # Get the ccp working directory, i.e., ../..
  working_dir=$(basename `dirname $PWD`)
  ${SCRIPT_DIR}/../../util/fixperms.pl --public ../../${working_dir}/
  # FIXME: Add wincopy behavior (from flashclient/Makefile)
  return $success
}
#
remake-pdf () {
  killfc
  sleep 1
  make -f Makefile-pdf clean
  make -f Makefile-pdf one
  max_tries=5
  success=1
  while [[ $max_tries -gt 0 ]]; do
    make -f Makefile-pdf again
    if [[ ! -e build-print/main.swf  ]]; then
      max_tries=$((max_tries-1))
    else
      max_tries=-1
      success=0
    fi
  done
  if [[ $max_tries -eq 0 ]]; then
    echo 'I give up!'
  fi
  # Get the ccp working directory, i.e., ../..
  working_dir=$(basename `dirname $PWD`)
  ${SCRIPT_DIR}/../../util/fixperms.pl --public ../../${working_dir}/
  # FIXME: Add wincopy behavior (from flashclient/Makefile)
  return $success
}

ccp_setup_branch () {

  # Usage: $0 checkout_path checkout_from checkout_dump

  echo 1 $1
  echo 2 $2
  echo 3 $3
  echo 4 $4
  echo 5 $5
  echo 6 $6
  echo 7 $7

  if [[ -z "$1" \
     || -z "$2" \
     || -z "$3" \
     || -z "$4" \
     || -z "$5" \
     || -z "$6" \
     || -z "$7" ]]; then
    echo
    echo "Error: Silly programmer."
    echo "You forgot all the parms!"
    exit 1
  fi
  checkout_path=$1
  httpd_host_alias=$2
  httpd_port_num=$3
  checkout_from=$4
  checkout_dump=$5
  do_load_dbase=$6
  instance_br_list=$7

  echo 
  echo "Checking out Cyclopath branch: ${checkout_from} (to ${checkout_path})"

  # Checkout the Cyclopath source.
  if [[ -d /ccp/dev/${checkout_path} ]]; then
    # The checkout already exists. At least change the permissions so we can 
    # build it. Only update the source if the installer okayed it.
    sudo chown -R $USER /ccp/dev/${checkout_path}
    sudo chgrp -R $targetgroup /ccp/dev/${checkout_path}
    if [[ $svn_update_sources -ne 0 ]]; then
      cd /ccp/dev/${checkout_path}
      echo -n " .. updating ${checkout_from}... "
      svn update > /dev/null
      echo "ok"
    elif [[ $git_update_sources -ne 0 ]]; then
      cd /ccp/dev/${checkout_path}
      echo -n " .. updating ${checkout_from}... "
      git pull -a > /dev/null
      echo "ok"
    else
      echo " .. checkout exists; told to skip updates."
    fi
  else
    echo -n " .. checkingout ${checkout_from}... "

    echo
    echo "FATAL: 2016-07-18: SVN is deprecated. Get from git instead."
    echo
    exit 1

    # NOTE: $svnroot is set by check_parms.sh. For local devs, it's, i.e.,
    #       ssh://$USER@$HOSTNAME.cs.umn.edu; for other devs, it's the
    #       public svn address, svn://cycloplan.cyclopath.org/cyclingproject.
    svn co $svnroot/${checkout_from} \
      /ccp/dev/${checkout_path} \
      > /dev/null
      echo "ok"
  fi
  echo

  # Seed it.

  # See: check_parms.sh:
  #
  #   ccp_m4_defines="
  #     --define=TARGETUSER=$targetuser
  #     --define=TARGETHOST=$HOSTNAME
  #     --define=TARGETDOMAIN=$targetdom
  #     --define=SERVERMACHINE=$servermach
  #     --define=PYTHONVERS2=$PYTHONVERS2
  #     --define=PYVERSABBR2=$PYVERSABBR2
  #     --define=PGSQL_SHBU=$PGSQL_SHBU
  #     --define=MACHINE_IP=$MACHINE_IP
  #     --define=HTTPD_USER=$httpd_user
  #     --define=MAILFROMADDR=$mail_from_addr
  #     --define=INTERNALMAIL=$internal_email
  #     "
  #     
  # Note: uuidgen is provided by e2fsprogs.
  #
  # The bash_base.sh sets MACHINE_IP to the real IP, but for
  # community devs, the IP isn't likely to be static.
  if [[ "$MACHINE_DOMAIN" != "cs.umn.edu" ]]; then
    MACHINE_IP=127.0.0.1
  fi
  #
  ext_m4_defines="
    $ccp_m4_defines
    --define=VIRTUAL_HOSTNAME=$checkout_path
    --define=CCP_DB_NAME=$(echo $checkout_dump | sed "s/\.dump$//")
    --define=CHECKOUT_PATH=$checkout_path
    --define=SSEC_UUID="`uuidgen`"
    --define=MACHINE_IP=$MACHINE_IP
    --define=HTTPD_PORT_NUM=$httpd_port_num
    --define=INSTANCE_BRANCH_LIST="'$instance_br_list'"
    "

  # ... pyserver/

  if [[ -e /ccp/dev/${checkout_path}/pyserver/CONFIG ]]; then
    /bin/mv \
      /ccp/dev/${checkout_path}/pyserver/CONFIG \
      /ccp/dev/${checkout_path}/pyserver/CONFIG-OLD.`uuidgen`
  fi
  m4 \
    $ext_m4_defines \
    ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/pyserver/CONFIG \
    > /ccp/dev/${checkout_path}/pyserver/CONFIG

  # ... flashclient/

  if [[ -e /ccp/dev/${checkout_path}/flashclient/Conf_Instance.as ]]; then
    /bin/mv \
      /ccp/dev/${checkout_path}/flashclient/Conf_Instance.as \
      /ccp/dev/${checkout_path}/flashclient/Conf_Instance.as-OLD.`uuidgen`
  fi
  if [[ $isprodserver -eq 0 ]]; then
    m4 \
      $ext_m4_defines \
      --define=HTTPD_PORT_NUM=$httpd_port_num \
      ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/flashclient/Conf_Instance-dev.as \
          > /ccp/dev/${checkout_path}/flashclient/Conf_Instance.as
  else
    m4 \
      $ext_m4_defines \
      --define=HTTPD_PORT_NUM=$httpd_port_num \
      ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/flashclient/Conf_Instance-srv.as \
          > /ccp/dev/${checkout_path}/flashclient/Conf_Instance.as
  fi

  if [[ $isprodserver -eq 0 ]]; then
    /bin/cp -rf \
      /ccp/dev/${checkout_path}/flashclient/macros_development.m4 \
      /ccp/dev/${checkout_path}/flashclient/macros.m4
  else
    /bin/cp -rf \
      /ccp/dev/${checkout_path}/flashclient/macros_production.m4 \
      /ccp/dev/${checkout_path}/flashclient/macros.m4
  fi

  /bin/cp -rf \
    ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/flashclient/Makefile \
    /ccp/dev/${checkout_path}/flashclient/Makefile

  # ... mapserver/

  #
  if [[ -e /ccp/dev/${checkout_path}/mapserver/database.map ]]; then
    /bin/mv \
      /ccp/dev/${checkout_path}/mapserver/database.map\
      /ccp/dev/${checkout_path}/mapserver/database.map-OLD.`uuidgen`
  fi
  m4 \
   $ext_m4_defines \
   --define=CCP_DB_NAME=$checkout_path \
   ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/mapserver/database.map \
    > /ccp/dev/${checkout_path}/mapserver/database.map

  #
  if [[ -e /ccp/dev/${checkout_path}/mapserver/check_cache_now.sh ]]; then
    /bin/mv \
      /ccp/dev/${checkout_path}/mapserver/check_cache_now.sh\
      /ccp/dev/${checkout_path}/mapserver/check_cache_now.sh-OLD.`uuidgen`
  fi
  m4 \
   $ext_m4_defines \
   --define=CCP_DB_NAME=$checkout_path \
   ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/mapserver/check_cache_now.sh \
    > /ccp/dev/${checkout_path}/mapserver/check_cache_now.sh

  #
  if [[ -e /ccp/dev/${checkout_path}/mapserver/kill_cache_check.sh ]]; then
    /bin/mv \
      /ccp/dev/${checkout_path}/mapserver/kill_cache_check.sh\
      /ccp/dev/${checkout_path}/mapserver/kill_cache_check.sh-OLD.`uuidgen`
  fi
  m4 \
   $ext_m4_defines \
   --define=CCP_DB_NAME=$checkout_path \
   ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/mapserver/kill_cache_check.sh \
    > /ccp/dev/${checkout_path}/mapserver/kill_cache_check.sh

  # Note that the mapserver directory needs to be writeable by apache user.
  # FIXME: Move this and other generated files somewhere outside of the source
  #        checkout...
  chmod 2777 /ccp/dev/${checkout_path}/mapserver

  # ... htdocs/

  # 2013.11.11: Link to /ccp/var, for two reasons:
  #   1. on the prod server, /ccp/var is on a larger hard drive than /ccp/dev;
  #   2. to do zero-downtime Cyclopath software upgrades, we switch back and
  #      forth between two folders where one is always the test install and
  #      the other is the live install, but they share some resources (like
  #      htdocs/ files, many of which are not source files checked into SVN,
  #      so they should be the same for both installs).
  ccp_mkdir /ccp/var/htdocs

# FIXME: Do what the production server does and make two dirs and symlink
#        exports and report to /ccp/var...

  # For nightly GIS exports.
  #ccp_mkdir /ccp/dev/${checkout_path}/htdocs/exports
  ccp_mkdir /ccp/var/htdocs/${checkout_path}/exports
  # The links already exist in the source, but they point elsewhere:
  #  /ccp/var/htdocs/cycloplan_live/exports
  /bin/rm -f /ccp/dev/${checkout_path}/htdocs/exports
  /bin/ln -s /ccp/var/htdocs/${checkout_path}/exports \
             /ccp/dev/${checkout_path}/htdocs/exports
  # For protected GIS exports.
  #ccp_mkdir /ccp/dev/${checkout_path}/htdocs/reports
  ccp_mkdir /ccp/var/htdocs/${checkout_path}/reports
  /bin/rm -f /ccp/dev/${checkout_path}/htdocs/reports
  /bin/ln -s /ccp/var/htdocs/${checkout_path}/reports \
             /ccp/dev/${checkout_path}/htdocs/reports
  #
  # For community developers.
  #ccp_mkdir /ccp/dev/${checkout_path}/htdocs/exports/devs
  ccp_mkdir /ccp/var/htdocs/${checkout_path}/exports/devs
  # The maint lock lives here so make sure apache can write it.
  sudo chown -R $httpd_user /ccp/var/htdocs/${checkout_path}/exports/devs
  sudo chgrp -R $httpd_user /ccp/var/htdocs/${checkout_path}/exports/devs
  # For the old /ccp/dev/cp/htdocs/misc files.
  ccp_mkdir /ccp/var/htdocs/${checkout_path}/misc2
  /bin/rm -f /ccp/dev/${checkout_path}/htdocs/misc2
  /bin/ln -s /ccp/var/htdocs/${checkout_path}/misc2 \
             /ccp/dev/${checkout_path}/htdocs/misc2

  # For images generated for the text Wiki.
  # NOTE/MAYBE: Unlike exports/, reports/, and misc2/, this
  #             is not -- but could be -- a symbolic link to,
  #             e.g., /ccp/var/htdocs/cp/statistics.
  ccp_mkdir /ccp/dev/${checkout_path}/htdocs/statistics

  /bin/rm -f /ccp/dev/${checkout_path}/htdocs/main.html
  /bin/rm -f /ccp/dev/${checkout_path}/htdocs/crossdomain.xml
  if [[ $isprodserver -eq 0 ]]; then
    /bin/ln -s /ccp/var/htdocs/${checkout_path}/main.html.prod \
               /ccp/dev/${checkout_path}/htdocs/main.html
    /bin/ln -s /ccp/var/htdocs/${checkout_path}/crossdomain.xml.prod \
               /ccp/dev/${checkout_path}/htdocs/crossdomain.xml
  else
    /bin/ln -s /ccp/var/htdocs/${checkout_path}/main.html.dev \
               /ccp/dev/${checkout_path}/htdocs/main.html
    /bin/ln -s /ccp/var/htdocs/${checkout_path}/crossdomain.xml.dev \
               /ccp/dev/${checkout_path}/htdocs/crossdomain.xml
  fi

  # Build it.

  # FIXME: The MapServer map file and the TileCache config file are now
  #        generated by mapserver/check_cache_now.sh. How is that script
  #        scheduled? crontab?
  #
 # /bin/cp -rf \
 # ${SCRIPT_DIR}/../ao_templates/common/ccp/dev/cp/mapserver/tilecache.cfg\
 #   /ccp/dev/${checkout_path}/mapserver/tilecache.cfg

  # This is just temporary. The user should make sure to do this in their
  # startup script.
  export PATH=/ccp/opt/flex/bin:$PATH

  # Build it.
  # NOTE: Not checking build-print/pdf_printer.swf.
  if ! [[ \
    -e /ccp/dev/${checkout_path}/flashclient/build/main.swf ]];
  then

    echo
    echo -n "Killing fcsh..."
    echo

    cd /ccp/dev/${checkout_path}/flashclient

    # Kill the flex compiler and clean the flashclient build.
    # NOTE: Do an || : so, if kill fails, this fcn. returns 0.
    ps aux | grep -e bin/fcsh$ -e lib/fcsh.jar$ -e "python ./fcsh-wrap" \
      | awk '{print $2}' | xargs sudo kill -s 9 > /dev/null 2>&1 || :

    echo " ok."

    # FIXME: is this failing?
    # Maybe don't make clean?
    #make clean
    ##make clean > /dev/null 2>&1
    # NOTE: make sometimes sillily fails, but a subsequent make works. E.g., 
    #           Error: Access of possibly undefined property pad through a 
    #                  reference with static type main. 
    #                     paddingRight="{G.app.pad}"
    #       I [lb] am guessing that the compiler is multi-threaded?
    # FIXME: Should I make a 'make' wrapper that does this?:
    set +e

    echo
    if false; then
      echo -n "Building flashclient... "
      still_making=6
      while [[ "$still_making" -gt 0 ]]; do
        #make
        make > /dev/null 2>&1
        if [[ "$?" -ne 0 ]]; then
          echo "oops (fcsh failed; trying again)"
          echo -n "Building flashclient... "
          # Remember: In bash, things are strings unless you $((interpret)) them.
          still_making=$(($still_making-1))
        else
          echo "ok"
          still_making=-1
        fi
      done
      if [[ "$still_making" -ne -1 ]]; then
        echo "gave up... failed!"
      fi
    else
      echo "Building flashclient..."
      cd /ccp/dev/${checkout_path}/flashclient
      make clean
      remake
      if [[ $? -eq 0 ]]; then
        echo "Flashclient built!"
        still_making=-1
      else
        echo "WARNING: No flashclient built!!"
        still_making=0
      fi
    fi
    echo
    ccp_kill_fcsh
    sleep 1

    echo
    if [[ "$still_making" -eq -1 ]]; then
      #
      echo -n "Building pdf_printer... "
      if false; then
        still_making=6
        while [[ "$still_making" -gt 0 ]]; do
          #make -f Makefile-pdf > /dev/null 2>&1
          make -f Makefile-pdf #> /dev/null 2>&1
          if [[ "$?" -ne 0 ]]; then
            echo "oops (fcsh failed; trying again)"
            echo -n "Building pdf_printer... "
            # Remember: In bash, things are strings unless you $((interpret)).
            still_making=$(($still_making-1))
          else
            echo "ok"
            still_making=-1
          fi
        done
        if [[ "$still_making" -ne -1 ]]; then
          echo "gave up... failed!"
        fi
      else
        remake-pdf
      fi
      ccp_kill_fcsh
    sleep 1
    else
      # Don't bother with the other swf if flashclient failed to build.
      echo "Skipping building pdf_printer."
    fi
    echo

    set -e

    # Kill fcsh.
    ccp_kill_fcsh
    # Do we need to sleep a sec. to let it die?
    sleep 1

  fi
  echo

  # *** Fix permissions

  echo -n "Fixing perms on /ccp/dev/${checkout_path}... "

  # FIXME: Make sudo optional, so students can run this script.
  sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public \
    /ccp/dev/${checkout_path}/ \
    > /dev/null 2>&1

  sudo chown -R $targetuser /ccp/dev/${checkout_path}
  sudo chgrp -R $targetgroup /ccp/dev/${checkout_path}

  echo "ok"
  echo

  # *** Seed the database.

  if [[ "$masterhost" != "$HOSTNAME" ]]; then
    echo -n "Copying the database... "
    ccp_mkdir /ccp/var/dbdumps
    if ! [[ -e /ccp/var/dbdumps/${checkout_dump} ]]; then
      if ! [[ -e /scratch/$masterhost/ccp/var/dbdumps/${checkout_dump} ]]; then
        echo
        echo "WARNING: Cannot find dump: ${checkout_dump}"
        echo
      else
        cp -f /scratch/$masterhost/ccp/var/dbdumps/${checkout_dump} \
          /ccp/var/dbdumps
        sudo chown -R $targetuser /ccp/var/dbdumps
        sudo chgrp -R $targetgroup /ccp/var/dbdumps
      fi
    fi
    echo "ok"
    echo
  fi

  if [[ $reload_databases -ne 0 \
        && $do_load_dbase -ne 0 \
        && -e /ccp/var/dbdumps/${checkout_dump} ]]; then

    # Note: Calling the database the same name as the /ccp/dev/checkout name.
    echo -n "Loading database <${checkout_dump}> to <${checkout_path}>..."
    # Note: not calling the checkedout branch's db_load but the V2 $HEAD's.
    # NO: /ccp/dev/${checkout_path}/scripts/db_load.sh \
    /ccp/dev/cp/scripts/db_load.sh \
      /ccp/var/dbdumps/${checkout_dump} \
      ${checkout_path} \
      > /dev/null
      #> /dev/null 2>&1
    # Check for errors.
    if [[ $? -ne 0 ]]; then
      echo "failed!"
      echo "ERROR: db_load.sh failed: Please see: ${LOG_FILE}"
      echo ""
      # Dump the log to our log.
      #cat ${LOG_FILE}
      exit 1
    fi
    echo "ok"
    $DEBUG_TRACE && echo `date`

    # NOTE: You'll see these errors!
    # 
    # ERROR: language "plpgsql" already exists
    # ERROR: function "_st_dumppoints" already exists with same argument types
    # ERROR: function "populate_geometry_columns" alrdy exists w/ same arg typs
    # ERROR: function "st_minimumboundingcircle" alrdy exists w/ same arg types
    # ERROR: cast from type geography to type geography already exists
    # ERROR: relation "geography_columns" already exists
    # NOTICE: no notnull values, invalid stats
    # NOTICE: ... etc.

    ## Run any schema scripts not run. This is generally a no-op.
    #echo -n "Updating the database... "
    #cd /ccp/dev/${checkout_path}/scripts
    #./schema-upgrade.py ccpv2 yesall \
    #  > /dev/null 2>&1
    #echo "ok"

  else

    echo "Not loading the database."

  fi
  echo

  # *** Populate transit cache.

  # FIXME: Can I make this part of ccpv2.dump? For now, we have to build this
  # after getting the transit db.

  # FIXME: Nixxing this code for now. This should be part of the dump.
  if [[ 0 -ne 0 ]]; then
    # Don't run on V1, just V2.
    if [[ -d /ccp/dev/${checkout_path}/scripts/daily ]]; then
      echo -n "Building the Cyclopath transit cache... "
      # NOTE: If this script takes a while, it's because you need to vacuum
      # before running it. If you vacuum first, this script should execute w/in
      # a few mins
      cd /ccp/dev/${checkout_path}/scripts/daily
      # FIXME: How do you handle minnesota v. colorado schemas??
      # For now, this runs on minnesota because that's why my .psqlrc says!
      ./gtfsdb_build_cache.py
      echo "ok"
      echo
    fi
  fi

  # NOTE: We don't edit /etc/hosts here. You might want to add virtual names.

  # *** Setup the apache conf.

  echo "Installing Apache httpd.conf"

  system_file_diff_n_replace "etc/apache2/sites-available" \
    "cyclopath-template" "${checkout_path}.conf" "${checkout_path}" \
    "--define=HTTPD_PORT_NUM=${httpd_port_num}
     --define=HTTPD_HOST_ALIAS=${httpd_host_alias}
     --define=PY_INTERPRETER=minnesota___${checkout_path}"

  if $apache_activate; then

    echo -n "Configuring Apache sites-enabled..."

    if [[ -e /etc/apache2/sites-available/${checkout_path}.conf ]]; then
      # Remove the possibly existing link without asking.
      /bin/rm -f /etc/apache2/sites-enabled/${checkout_path}.conf
      ln -s /etc/apache2/sites-available/${checkout_path}.conf \
        /etc/apache2/sites-enabled/${checkout_path}.conf
      echo " ok."
    else
      echo " failed."
      echo "ERROR: Where's the sites-available config?: \"${checkout_path}\""
    fi

    echo

  fi

} # end of ccp_setup_branch

# ***

# Kill fcsh.
ccp_kill_fcsh
# Do we need to sleep a sec. to let it die?
sleep 1

# Flashclient's fcsh-wrap writes to a temporary file.
# Make sure we can write to it.
sudo touch /tmp/flashclient_make
sudo chmod 664 /tmp/flashclient_make
sudo chown $targetuser /tmp/flashclient_make
sudo chgrp $targetgroup /tmp/flashclient_make

# Install source code and database.

# MAGIC_NUMBERS/NAMES. These are hardcoded directory paths and whatnot.
# The CCPV3_SVN_TRUNK is the subpath after $svnroot.
CCPV3_SVN_TRUNK="public/ccpv3_trunk"
#CCP_DEV_TARGET="ccpv3_trunk"
# The CCP_DEV_TARGET is the name of the /ccp/dev/ folder and apache conf.
#CCP_DEV_TARGET="cyclopath"
CCP_DEV_TARGET="working"
CCP_DEV_TRUNK="trunk"
#CCP_DEV_TARGET="ccp_working"
#CCP_DEV_TRUNK="ccp_trunk"

# Whatever database dump we'll load must be on a local hard drive.
# Verify or find it.
if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then
  if [[ $isprodserver -eq 0 ]]; then
    CCPV3_DDUMP="ccpv3_lite.dump"
  else
    # Production server.
    CCPV3_DDUMP="ccpv3_full.dump"
  fi
  if [[ ! -e /ccp/var/dbdumps/${CCPV3_DDUMP} ]]; then
    # See if the dump is on another machine.
    if [[ "$masterhost" != "$HOSTNAME" ]]; then
      /bin/cp /scratch/$masterhost/ccp/var/dbdumps/${CCPV3_DDUMP} \
        /ccp/var/dbdumps/${CCPV3_DDUMP}
    else
      # Is this a warning? We can still dwnld schema, base data, and Shapefile.
      echo
      echo "MAYBE: Cannot locate database to load: ${CCPV3_DDUMP}"
      echo
    fi
  fi
else
  # This is an offline developer.
  if [[ ! -e /ccp/var/dbdumps/${CCPV3_DDUMP} ]]; then
    # See if the dump is available online.
    if [[ -n $USE_DATABASE_SCP ]]; then
      # E.g., CCPV3_DDUMP="ccpv3_anon.dump"
      CCPV3_DDUMP=$(basename $USE_DATABASE_SCP)
      scp $USE_DATABASE_SCP /ccp/var/dbdumps/${CCPV3_DDUMP}
    else
      # Is this a warning? We can still dwnld schema, base data, and Shapefile.
      echo
      echo "MAYBE: Please specify database to load using USE_DATABASE_SCP"
      echo
    fi
  fi
fi
if [[ -z ${CCPV3_DDUMP} ]]; then
  # Use a fake name to keep ccp_setup_branch happy.
  CCPV3_DDUMP="ccpv3_anon.dump"
fi

if [[ ! -e /ccp/var/dbdumps/${CCPV3_DDUMP} ]]; then

  echo
  echo "WARNING/FIXME: This a community dev install and there's no ready db."
  echo "               We can at least load the schema and base data."
  echo "               Implement me: Download and import Shapefile."
  echo

  # See: http://mediawiki/index.php/Tech:Source_Code

  # Note that dir_prepare.sh downloads
  #  http://cycloplan.cyclopath.org/exports/devs/minnesota.dem
  #  to /ccp/var/elevation/minnesota.dem

  # Huh. I guess trying to use -O with -N doesn't work.
  #  wget -N -O /ccp/var/dbdumps/schema.sql \
  #    http://cycloplan.cyclopath.org/exports/devs/schema.sql
  #  wget -N -O /ccp/var/dbdumps/data.sql \
  #    http://cycloplan.cyclopath.org/exports/devs/data.sql
  pushd /ccp/var/dbdumps
  wget -N http://cycloplan.cyclopath.org/exports/devs/schema.sql
  wget -N http://cycloplan.cyclopath.org/exports/devs/data.sql
  popd

  if [[ -e /ccp/var/dbdumps/schema.sql \
     && -e /ccp/var/dbdumps/data.sql ]]; then
    # http://stackoverflow.com/questions/14549270/
    #  check-if-database-exists-in-postgresql-using-shell
    if ! psql --no-psqlrc -U cycling -lqt | cut -d \| -f 1 \
         | grep -w ${CCP_DEV_TARGET};
      then

# FIXME: This is wrong. We need to use the postgis import script, eh?

      createdb -U postgres -e --template template0 ${CCP_DEV_TARGET}
      psql --no-psqlrc -U cycling ${CCP_DEV_TARGET} \
        < /ccp/var/dbdumps/schema.sql
      # Run as psql superuser to avoid, e.g., ERROR:permission denied:
      #              "RI_ConstraintTrigger_22528" is a system trigger
      psql --no-psqlrc -U postgres ${CCP_DEV_TARGET} \
        < /ccp/var/dbdumps/data.sql
    else
      echo "The database, ${CCP_DEV_TARGET}, exists and will not be overwrit."
    fi
  else
    echo
    echo "ERROR: Could not download schema.sql and/or data.sql."
    echo
  fi
  # FIXME: Download and import Shapefile of Hennepin County.
  # FIXME: Run make_new_branch.py to make user arbiter
  #        and maybe add a new branch and download
  #        Ramsey to that to show working with branches.

fi

if true; then

  # During a fresh OS install, cp might be mapped to a working dir somewhere.
  if [[ ! -e /ccp/dev/cp && ! -L /ccp/dev/cp ]]; then
    ln -s /ccp/dev/${CCP_DEV_TARGET} /ccp/dev/cp
  # else, it's up to you, the dev, to fix the /ccp/dev/cp link.
  fi

  # NOTE: The bash -e test resolves the symlink, so it returns false if the
  #       symlink links a nonexistant file or folder. To avoid this problem,
  #       the -L (also -h) test checks if the file is a symlink.
  if [[ ! -e /ccp/dev/cp_cron && ! -L /ccp/dev/cp_cron ]]; then
    ln -s /ccp/dev/${CCP_DEV_TARGET} /ccp/dev/cp_cron
  fi
  #if [[ ! -e /ccp/dev/ccpv3_trunk && ! -L /ccp/dev/ccpv3_trunk ]]; then
  #  ln -s /ccp/dev/${CCP_DEV_TARGET} /ccp/dev/ccpv3_trunk
  #fi

  if [[ -z $CHECK_CACHES_BR_LIST ]]; then
    echo
    echo "WARNING: CHECK_CACHES_BR_LIST not set; guessing."
    echo
    CHECK_CACHES_BR_LIST="\"minnesota\" \"Minnesota\""
  fi

  # Now setup the branch.
  checkout_path="${CCP_DEV_TARGET}"
  httpd_host_alias="ccp"
  httpd_port_num="80"
  checkout_from="${CCPV3_SVN_TRUNK}"
  checkout_dump="${CCPV3_DDUMP}"
  do_load_dbase=1
  instance_br_list="${CHECK_CACHES_BR_LIST}"
  echo "Setting up main source code branch..."
  ccp_setup_branch \
    "${checkout_path}" \
    "${httpd_host_alias}" \
    "${httpd_port_num}" \
    "${checkout_from}" \
    "${checkout_dump}" \
    "${do_load_dbase}" \
    "${instance_br_list}"

  echo "Installing maintenance apache conf."
  # SYNC_ME: Search: Apache maintenance conf.
  system_file_diff_n_replace "etc/apache2/sites-available" \
    "maintenance" "maintenance" "${CCP_DEV_TARGET}" \
    "--define=HTTPD_PORT_NUM=80"

  echo "Removing svn directory from /ccp/dev/working."
  # We'll have two dirs: ccp_working and ccp_trunk.
  /bin/cp -rf /ccp/dev/${CCP_DEV_TARGET} /ccp/dev/${CCP_DEV_TRUNK}
  # Remove svn directories from the working directory.
  /bin/rm -rf /ccp/dev/${CCP_DEV_TARGET}/.svn

fi

echo "Reloading Apache..."

ccp_apache_reload

#
#
#
#
# *** NOTE: None of the remaining code executes except on cs.umn.edu. ***
#
#
#
#

# FIXME: What about tiles on the guest machine?
# FIXME: What about the route finder and Mr. Do!?
#         Just tell the user to start them as needed?
#        Not quite the killer app...
#        I think you need to load the Mpls city export
#         and then the memory usage won't be so demanding,
#         and adding mr do and cyclopath to /etc/init.d
#         will be okay, and the startup time will be
#         30 seconds, right? =)

# *** Build all of the tiles.

# FIXME: CcpV3: The tile cache path is based on branch ID in the database dump.

if [[ "$masterhost" != "$HOSTNAME" ]]; then

  if ! [[ -d /ccp/var/tilecache-cache/minnesota/00 ]]; then

    echo -n "Copying tiles... "

    sudo chown -R $USER /ccp/var/tilecache-cache/
    sudo chgrp -R $targetgroup /ccp/var/tilecache-cache/
    /bin/rm -rf /ccp/var/tilecache-cache/minnesota
    /bin/cp -rf /scratch/$masterhost/ccp/var/tilecache-cache/minnesota \
      /ccp/var/tilecache-cache
    # Apache owns the tilecache cache.
    sudo chown -R $httpd_user /ccp/var/tilecache-cache/
    sudo chgrp -R $httpd_user /ccp/var/tilecache-cache/

  fi

fi

# else, FIXME: Tell user to build tiles, or download them from server?

# It takes too long to build tiles, so don't do it here. We'll schedule the
# cron job to do it.
#
# else
#   if [[ 0 -ne $reload_databases ]]; then
#     echo -n "Building tiles... "
#     cd /ccp/dev/cp/mapserver
#      sudo -u $httpd_user \
#        INSTANCE=minnesota \
#        PYTHONPATH=$ccp_python_path \
#        PYSERVER_HOME=/ccp/dev/cp/pyserver \
#        ./tilecache_update.py --all --branch -1 --zoom 9 15 --skin bikeways
#     echo "ok"
#   fi
# fi

# *** Install cronjobs.

if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then

  echo -n "Installing cron jobs... "

  # FIXME: Make all RANDOM_NAME use uuidgen
  RANDOM_NAME="`uuidgen`"
  RANDOM_NAME=/tmp/ccp_setup_cron_$RANDOM_NAME
  mkdir $RANDOM_NAME

  if [[ $isbranchmgr -ne 0 ]]; then
    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/cron.d/crontab.USER \
      > $RANDOM_NAME/crontab.USER
      sudo crontab -u $targetuser $RANDOM_NAME/crontab.USER

  elif [[ $isprodserver -ne 0 ]]; then

    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/cron.d/crontab.PRODUCTION \
      > $RANDOM_NAME/crontab.PRODUCTION
      sudo crontab -u $targetuser $RANDOM_NAME/crontab.PRODUCTION

  fi

  # 2012.03.08: The root crontab just restarts apache daily. Skip it.
  if false; then
    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/cron.d/crontab.root \
      > $RANDOM_NAME/crontab.root
      sudo crontab -u root $RANDOM_NAME/crontab.root
  fi

  # Install the www-data cron, which calls check_cache_now.sh every minute.

  # NOTE: Not configuring on dev machines. Just branch-mgr and production.
  if [[ $isbranchmgr -ne 0 || $isprodserver -ne 0 ]]; then
    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/cron.d/crontab.www-data \
        > $RANDOM_NAME/crontab.www-data
      sudo crontab -u www-data $RANDOM_NAME/crontab.www-data
  fi

  # Cleanup.
  /bin/rm -rf $RANDOM_NAME

  echo "ok"

fi

# *** Configuring boot services

#$ ll /etc/rc0.d/ | grep cyclopath
# K01cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc1.d/ | grep cyclopath
# K01cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc2.d/ | grep cyclopath
# S99cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc3.d/ | grep cyclopath
# S99cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc4.d/ | grep cyclopath
# S99cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc5.d/ | grep cyclopath
# S99cyclopath-routed -> ../init.d/cyclopath-routed*
#$ ll /etc/rc6.d/ | grep cyclopath
# K01cyclopath-routed -> ../init.d/cyclopath-routed*

# FIXME: Should we do this on all dev machines?
if [[ $isbranchmgr -ne 0 || $isprodserver -ne 0 ]]; then

  echo -n "Copying init.d scripts... "

  if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
    # echo Ubuntu!
    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/init.d/cyclopath-routed \
      > /tmp/cyclopath-routed
    sudo mv -f /tmp/cyclopath-routed /etc/init.d/
    sudo chmod 755 /etc/init.d/cyclopath-routed
    sudo chown root /etc/init.d/cyclopath-routed
    sudo chgrp root /etc/init.d/cyclopath-routed
    sudo update-rc.d cyclopath-routed defaults
    # /etc/rc0.d/K20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc1.d/K20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc6.d/K20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc2.d/S20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc3.d/S20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc4.d/S20cyclopath-routed -> ../init.d/cyclopath-routed
    # /etc/rc5.d/S20cyclopath-routed -> ../init.d/cyclopath-routed
    #
    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/init.d/cyclopath-mr_do \
      > /tmp/cyclopath-mr_do
    sudo mv -f /tmp/cyclopath-mr_do /etc/init.d/
    sudo chmod 755 /etc/init.d/cyclopath-mr_do
    sudo chown root /etc/init.d/cyclopath-mr_do
    sudo chgrp root /etc/init.d/cyclopath-mr_do
    sudo update-rc.d cyclopath-mr_do defaults
    echo "ok."
  elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
    # echo Red Hat!
    echo "failed."
    echo
    echo "Error: FIXME: setup startup scripts for Fedora."
  else
    echo "failed."
    echo
    echo "Error: Unknown OS!"
    exit 1
  fi

fi

# *** Configuring logcheck

if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then

  # logcheck needs to be in the www-data group.
  # You can run 'groups logcheck' to verify.
  #   $ groups logcheck
  #   logcheck : logcheck adm www-data

  sudo adduser logcheck www-data > /dev/null

  # Verify: `groups logcheck | grep www-data`

  # NOTE: The files under /etc/logcheck are initially owned by root and belong to
  # the logcheck group. But we change ownership so the user can edit these (and
  # maybe so logcheck can run with the user's permissions?).

  sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public \
    /etc/logcheck/ \
    > /dev/null 2>&1
  sudo chown -R $targetuser /etc/logcheck
  sudo chgrp -R $targetgroup /etc/logcheck

  # Copy the logcheck configuration file.
  #
  # We've only edited one variable, SENDMAILTO.

  if [[ $isbranchmgr -ne 0 ]]; then

    m4 \
      $ccp_m4_defines \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/logcheck/logcheck.conf.USER \
      > /etc/logcheck/logcheck.conf

  elif [[ $isprodserver -ne 0 ]]; then

    m4 \
      $ccp_m4_defines \
     ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/logcheck/logcheck.conf.PRODUCTION \
      > /etc/logcheck/logcheck.conf

  fi

  # Copy the list of logfiles to monitor and the logcheck rules.
  #
  # See /usr/share/doc/logcheck-database/README.logcheck-database.gz for hints on
  # how to write, test and maintain rules.

  if [[ $isbranchmgr -ne 0 || $isprodserver -ne 0 ]]; then

    cp -f \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/logcheck/logcheck.logfiles \
      /etc/logcheck/logcheck.logfiles

    cp -f \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/etc/logcheck/ignore.d.server/local-CYCLOPATH \
      /etc/logcheck/ignore.d.server/local-CYCLOPATH

  fi

  sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public \
    /etc/logcheck/ \
    > /dev/null 2>&1
  sudo chown -R $targetuser /etc/logcheck
  sudo chgrp -R $targetgroup /etc/logcheck

fi

# FIXME: Daemons are not starting. Must be PYTHONPATH?

#Starting service: 
#    /ccp/dev/cp_trunk_v2/pyserver/../services/mr_do.py
#  Traceback (most recent call last):
#    File "/ccp/dev/cp_trunk_v2/pyserver/../services/mr_do.py",
#      line 117, in <module>
#        from item.feat import branch
#    File "/ccp/dev/cp_trunk_v2/pyserver/item/feat/branch.py", 
#      line 7, in <module>
#        import psycopg2
#    File "/ccp/opt/usr/lib/python2.7/site-packages/psycopg2/__init__.py", 
#      line 67, in <module>
#        from psycopg2._psycopg import BINARY, NUMBER, STRING, DATETIME, ROWID
#ImportError: No module named _psycopg

# *** Start the work queue daemon.

# FIXME: Make these optional?
if false; then

  # FIXME: Stop the services first?

  echo -n "Starting the work queue... "
  cd /ccp/dev/cp/services
  sudo -u $httpd_user \
    INSTANCE=minnesota \
    PYTHONPATH=$ccp_python_path \
    PYSERVER_HOME=/ccp/dev/cp/pyserver \
    ./mr_doctl start
  echo "ok"

  # *** Start the route-finders.

  echo -n "Starting the p1 route-finder... "
  cd /ccp/dev/cp/services
  sudo -u $httpd_user \
    INSTANCE=minnesota \
    PYTHONPATH=$ccp_python_path \
    PYSERVER_HOME=/ccp/dev/cp/pyserver \
    ./routedctl --routed_pers=p1 --purpose=general start
  echo "ok"

  #

  echo -n "Starting the p2 route-finder... "
  cd /ccp/dev/cp/services
  sudo -u www-data \
    INSTANCE=minnesota \
    PYTHONPATH=$ccp_python_path \
    PYSERVER_HOME=/ccp/dev/cp/pyserver \
    ./routedctl --routed_pers=p2 --purpose=general start
  echo "ok"

fi

# *** Restore location

cd $script_path

# *** All done!

echo
echo "Done preparing Cyclopath. Test it at:"
echo
echo "  http://localhost:80   [if local]"
echo "    or "
echo "  http://localhost:8080 [if ssh'ing]"
echo "    and "
echo "  http://localhost:8081, http://localhost:8082, etc."

exit 0

