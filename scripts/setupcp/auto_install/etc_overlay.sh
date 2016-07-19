#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./etc_overlay.sh
#  (also called from ccp_install.sh)

# Fcns below:
#   setup_ccp_var_pgdata
#   setup_shmmax_and_shmall
#   setup_psql_config_files
#   setup_install_psycopg2
#   setup_pgbouncer
#   setup_apache
#   setup_mod_python

# NOTE: This script is meant to be run on the CS network at the U.

# NOTE: This script calls sudo a few times, so you gotta be staff with lab-wide
# sudo to run this script.

# NOTE: If this was just /bin/sh and not bash, then $HOSTNAME is not set.

#script_relbase=$(dirname $0)
#script_absbase=`pwd $script_relbase`
echo "SCRIPT_DIR=\$(dirname \$(readlink -f $0))"
SCRIPT_DIR=$(dirname $(readlink -f $0))

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its
#          variables become ours.
. ${SCRIPT_DIR}/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,
#            reload_databases, PYTHONVERS2, and httpd_user.

# *** Keep sudo alive

sudo -v

# *** Don't exit on error.

# NOTE: Not calling 'set -e'.
# EXPLAIN: Why does this script not exit on error like the other auto_install
#          scripts?

# *** Postgres.

# Make sure we figured out the postgres version.
if [[ -z "${POSTGRESABBR}" ]]; then
  echo
  echo "Error: POSTGRESABBR not set?"
  exit 1
fi

ccp_service_postgres () {
  # Usage: $0 service_cmd
  if [[ -z "$1" ]]; then
    echo
    echo "Error: Silly programmer. You forgot the service command!"
    exit 1
  fi
  if [[ -e /etc/init.d/postgresql-${POSTGRESABBR} ]]; then
    # Ubuntu 10.04
    sudo /etc/init.d/postgresql-${POSTGRESABBR} $1
  else
    # Ubuntu 11.04 / Fedora 14
    sudo /etc/init.d/postgresql $1
  fi
}

echo
echo "Preparing postgresql from master: $masterhost"
echo

# Normally, the U sets up postgres to use scratch space for the
# database, but not always (maybe just for dev machines but not
# for production servers?).

# NOTE: You can set the pgdata path in postgresql.conf. Or you can just make a
# symbolic link....

# Run these commands before re-running ./ccp_install if you need to wipe
# pgdata and start anew.
if false; then
  IGNORE_ME="
  sudo /etc/init.d/postgresql-${POSTGRESABBR} stop
  sudo rm /var/lib/postgresql/${POSTGRESABBR}/main
  # BE VERY CAREFUL/DELIBERATE!
  sudo rm -rf /ccp/var/pgdata-${POSTGRESABBR}
  "
fi

function setup_ccp_var_pgdata () {

  # See if the link already exists.
  if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then

    # Only setup /ccp/var/pgdata-9.5/ is not already symlinked from /var/lib.
    if [[ ! -h /var/lib/postgresql/${POSTGRESABBR}/main ]]; then

      echo "Found pgdata at default location; converting to symlink."

      if [[ -e /var/lib/postgresql/${POSTGRESABBR}/main ]]; then
        ccp_service_postgres stop
      fi

      if [[ -d /var/lib/postgresql/${POSTGRESABBR}/main ]]; then
        sudo mv /var/lib/postgresql/${POSTGRESABBR}/main \
                /var/lib/postgresql/${POSTGRESABBR}/main-ORIG
      fi

      # Systems normally installs the directory
      #   at /export/scratch/pgdata-${POSTGRESABBR}.
      # But I [lb] like keeping space-hungry folders under /ccp/var.

      # Start by making the directory and mucking with permissions.

      mkdir /ccp/var/pgdata-${POSTGRESABBR}
      chmod 0700 /ccp/var/pgdata-${POSTGRESABBR}
      # Not sure why the sticky bit gets set, or if it matters, but it's not set
      # on the original directory, so unstick it.
      chmod g-s /ccp/var/pgdata-${POSTGRESABBR}
      sudo chown postgres /ccp/var/pgdata-${POSTGRESABBR}

      # Create the new PostgreSQL database cluster.
      # NOTE: initdb is not on path, so use full pathname.
      # NOTE: Cannot sudo. Get weird error:
      # Sorry, user landonb is not allowed to execute '...' as postgres on runic.
      #sudo -u postgres \
      #  /usr/lib/postgresql/${POSTGRESABBR}/bin/initdb \
      #  -U cycling \
      #  --pgdata=/ccp/var/pgdata-${POSTGRESABBR}
      # NO: sudo su postgres ; ... ; logout... hahaha
      # NOTE: Don't use -U cycling.
      sudo su -c "/usr/lib/postgresql/${POSTGRESABBR}/bin/initdb \
        -U postgres \
        --pgdata=/ccp/var/pgdata-${POSTGRESABBR}" \
        postgres
      # Success. You can now start the database server using:
      #  /usr/lib/postgresql/${POSTGRESABBR}/bin/postgres \
      #     -D /ccp/var/pgdata-${POSTGRESABBR}
      # or
      # /usr/lib/postgresql/${POSTGRESABBR}/bin/pg_ctl
      #     -D /ccp/var/pgdata-${POSTGRESABBR} -l logfile start

      # Add the certificate/key links.
      # EXPLAIN: What are these?
      sudo ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem \
                 /ccp/var/pgdata-${POSTGRESABBR}/server.crt
      sudo ln -s /etc/ssl/private/ssl-cert-snakeoil.key \
                 /ccp/var/pgdata-${POSTGRESABBR}/server.key

      # Disable the config files that initdb made so that users can edit them via
      # /etc/postgresql/${POSTGRESABBR}/main (well, technically, they can edit
      # them in the pgdata directory, but they need the full path; i.e., the
      # directory has 700 permissions, so users cannot 'ls' the directory, but
      # they can manipulate files therein if they know the filenames).
      sudo mv /ccp/var/pgdata-${POSTGRESABBR}/pg_hba.conf \
              /ccp/var/pgdata-${POSTGRESABBR}/pg_hba.conf.`uuidgen`
      sudo mv /ccp/var/pgdata-${POSTGRESABBR}/pg_ident.conf \
              /ccp/var/pgdata-${POSTGRESABBR}/pg_ident.conf.`uuidgen`
      sudo mv /ccp/var/pgdata-${POSTGRESABBR}/postgresql.conf \
              /ccp/var/pgdata-${POSTGRESABBR}/postgresql.conf.`uuidgen`

      # Link the cluster to PGDATA.
      sudo ln -s /ccp/var/pgdata-${POSTGRESABBR} \
                 /var/lib/postgresql/${POSTGRESABBR}/main

      ccp_service_postgres start

    fi

    # Leave data dir where Systems put it.
    # (See the link at /var/lib/postgresql/${POSTGRESABBR}/main)
    if ! [[ -d /export/scratch/pgdata-${POSTGRESABBR} \
            || -d /ccp/var/pgdata-${POSTGRESABBR} ]]; then
      echo "Error: Where's the pgdata dir?"
      exit 1
    fi

  fi # end: $MACHINE_DOMAIN == "cs.umn.edu"

} # end: setup_ccp_var_pgdata
setup_ccp_var_pgdata

# Increase memory limits.

# The default value of shmmax is something like 32 MB. ([lb] would document it
# but that would require editing sysctl.conf and rebooting, since simply
# commenting-out the value and calling sysctl -p didn't change things.)

# shmmax is the maximum amount of memory that Linux will allocate for shared
# memory. Postgres uses lots of shared memory. ([lb] assumes because it forks
# to process requests? I guess I'm not sure why Postgres is a special user of
# shared memory, but it is, and Postgres users generally have to tune shmmax
# as part of the setup process.)

# Historically, Cyclopath has just changed shmmax from its 32MB default to 1GB.

# Circa June, 2012, [lb] was reading the new PostGIS 2.0 documentation which
# suggests setting postgresql.conf's shared_buffers to one-third of available
# RAM. However, this is larger than shmmax, so pgsql won't start if we keep
# shmmax at 1GB. There's not much info. online about shmmax (probably because
# only Postgres users have to tweak it), but here's what I found.

# [lb] is having trouble finding official documentation on SHMMAX and SHMALL.
# Also, there are comments on forums suggesting SHMMAX should be 50% or so of
# RAM (and Postgres's shared_buffers should be 1/3 of RAM, to use a lot of
# SHMMAX but to still leave some leftover for other processes).
# BUG nnnn: Figure out ideal SHMMAX value and add to auto_install.
#           IMPORTANTLY: How does this relate to the route finders?

# An IBM Web page defines the kernel parameters we want to edit as the
# "Shared Memory Limits".
#  SHMMNI: max number of segments
#  SHMMAX: max seg size (kbytes)
#  SHMALL: max total shared memory (kbytes)

# Also, this is a hilarious read:
#   http://www.pythian.com/news/245/the-mysterious-world-of-shmmax-and-shmall/
# Though I'm not sure the information is accurate...
# "Just to make it fun, the actual setting is derived...
#  the maximum amount of memory = shmall * pagesize
#  where pagesize = getconf PAGE_SIZE and shmall = cat /proc/sys/kernel/shmall"
# 2012.06.02: On Ubuntu and Fedora, i.e., runic, huffy and pluto,
#     cat /proc/sys/kernel/shmall ==> 2097152, or 2MB, and
#     getconf PAGE_SIZE ==> 4096. Per usual...
#  So max amount of shared memory that the OS allocates is 2MB * 4K, or 8 GB...

# The shmmax_calc script found on a Postgres forum suggests setting shmmax to
# 50% of RAM and adjusting shmall according.
# kernel.shmmax / Maximum shared segment size in bytes
#   pluto: 1582858240
#   huffy: 2074161152
#   runic: 25368768512
# kernel.shmall / Maximum number of shared memory segments in pages
#   pluto: 386440  ( 18% of 2MB default)
#   huffy: 506387  ( 24% of 2MB default)
#   runic: 6193547 (295% of 2MB default)

function setup_shmmax_and_shmall () {

  . ${SCRIPT_DIR}/shmmax_calc.sh $*

  # See if we have to edit sysctl.conf or not.

  ADD_SHMMAX=0
  echo -n "/etc/sysctl.conf: scanning for shmmax setting... "
  if [[ -z "`cat /etc/sysctl.conf | grep 'kernel.shmmax'`" ]]; then
    echo "not found."
    ADD_SHMMAX=1
  else
    echo "found."
    gr_shmmax="cat /etc/sysctl.conf \
               | grep '^kernel.shmmax' \
               | grep -v '^kernel.shmmax = $shmmax\$'"
    if [[ "" != "`eval $gr_shmmax`" ]]; then
      echo "Error: sysctl.conf sets shmmax, but not to 50% of RAM, or $shmmax."
      echo -n "Would you like to continue with existing shmmax value? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        # MEH: We could maybe use sed to correct the value. I.e., pipe
        # sysctl.conf through sed to a tmp file, and then copy the tmp file back
        # to /etc. But it's not that important.
        echo "Error: Fix shmmax and shmall in sysctl.conf and sudo sysctl -p"
        exit 1
      else
        # If caller edited sysctl manually, make sure the kernel knows about it.
        sudo sysctl -p
      fi
    # else, /etc/sysctl.conf ready to go.
    fi
  fi

  ADD_SHMALL=0
  echo -n "/etc/sysctl.conf: scanning for shmall setting... "
  if [[ -z "`cat /etc/sysctl.conf | grep 'kernel.shmall'`" ]]; then
    echo "not found."
    ADD_SHMALL=1
  else
    echo "found."
    gr_shmall="cat /etc/sysctl.conf \
               | grep '^kernel.shmall' \
               | grep -v '^kernel.shmall = $shmall\$'"
    if [[ "" != "`eval $gr_shmall`" ]]; then
      echo "Error: sysctl.conf sets shmall, but not to shmmax / page_size."
      echo "       E.g., \$shmall = $shmmax / $page_size = $shmall."
      echo -n "Would you like to continue with existing shmall value? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        # MEH: We could maybe use sed to correct the value. I.e., pipe
        # sysctl.conf through sed to a tmp file, and then copy the tmp file back
        # to /etc. But it's not that important.
        echo "Error: Fix shmmax and shmall in sysctl.conf and sudo sysctl -p"
        exit 1
      else
        # If caller edited sysctl manually, make sure the kernel knows about it.
        sudo sysctl -p
      fi
    # else, /etc/sysctl.conf ready to go.
    fi
  fi

  if [[ 0 -ne $ADD_SHMMAX && 0 -ne $ADD_SHMALL ]]; then
    echo "Adding shmmax and shmall to /etc/sysctl.conf"
    RANDOM_NAME=/tmp/ccp_setup_ljklahsdf8sdffklh234asd1234
    mkdir $RANDOM_NAME
    #
    (echo "# [Cyclopath]
# Make postgresql happy by increasing the shared memory limits.
#
# CcpV1: Increase shared memory limit from 32MB to 1GB.
#   kernel.shmmax = 1073741824
# CcpV2: 2012.06.02: Per Postgres forum suggestion
#   http://postgresql.1045698.n5.nabble.com/The-right-SHMMAX-and-FILE-MAX-tp4362375p4363380.html
# Use 50% of RAM for shared memory maximum segment size.
#   Note also the shmmax needs to be larger than Postgresql.conf's
#   shared_buffers.
# Also, set shmall to shmmax / page size. (Page size is almost always 4 Kb.)
kernel.shmmax = $shmmax
kernel.shmall = $shmall
" ; cat /etc/sysctl.conf) > $RANDOM_NAME/sysctl.conf
    #
    sudo cp $RANDOM_NAME/sysctl.conf /etc/sysctl.conf
    #
    # Cleanup.
    /bin/rm -f $RANDOM_NAME/sysctl.conf
    rmdir $RANDOM_NAME
    #
    # Tell the kernel about the changes.
    sudo sysctl -p
  elif [[ 0 -eq $ADD_SHMMAX && 0 -eq $ADD_SHMALL ]]; then
    echo "Skipping /etc/sysctl.conf (already set correctly)."
  elif [[ 0 -ne $ADD_SHMMAX ]]; then
    echo "Error: Please manually edit sysctl.conf and add shmmax"
    exit 1
  elif [[ 0 -ne $ADD_SHMALL ]]; then
    echo "Error: Please manually edit sysctl.conf and add shmall"
    exit 1
  else
    # This shouldn't happen.
    echo "Error: Unexpected code path."
    exit 1
  fi

} # end: setup_shmmax_and_shmall
setup_shmmax_and_shmall

# Copy config files from master.

# NOTE: The default 10.04 files are the same as the 11.04 default files.

# Check that the files have not changed.

# NOTE: The Postgresql conf files are edited often (or, at least, circa March
# 2012, they're being edited often), so rather than fail if the files are
# different than expectd, ask the installer if it's okay to overwrite them.

function setup_psql_config_files () {

  if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then

    echo "Fixing Postgresql accesses..."

# /ccp/var/pgdata-${POSTGRESABBR}

    PSQL_BASE_DIR="etc/postgresql"
    PSQL_CONF_DIR="${PSQL_BASE_DIR}/${POSTGRESABBR}"
    PSQL_MAIN_DIR="${PSQL_CONF_DIR}/main"
    if ! [[ -d "/${PSQL_MAIN_DIR}" ]]; then
      echo "ERROR: Missing ${PSQL_MAIN_DIR}; cannot continue."
      exit 1
    fi

    #sudo chown -R $targetuser /${PSQL_CONF_DIR}
    sudo chgrp -R $targetgroup /${PSQL_CONF_DIR}
    #sudo chgrp -R $targetgroup /etc/postgresql/${POSTGRESABBR}/main
    sudo chmod 2775 /${PSQL_CONF_DIR}
    sudo chmod 2775 /${PSQL_MAIN_DIR}
    sudo chmod 664 /${PSQL_MAIN_DIR}/*.conf
    sudo chmod 664 /${PSQL_MAIN_DIR}/environment

    echo "Copying Postgresql conf files..."

    system_file_diff_n_replace $PSQL_MAIN_DIR "pg_hba.conf"
    system_file_diff_n_replace $PSQL_MAIN_DIR "pg_ident.conf"
    system_file_diff_n_replace $PSQL_MAIN_DIR "postgresql.conf"

    # If Systems didn't setup postgres beforehand, we may have created new files
    # that we own.
    sudo chown -R postgres /etc/postgresql/${POSTGRESABBR}/main

    # NOTE: We don't diff against the pgdata directory -- we just clobber instead!
    if [[ -d /ccp/var/pgdata-${POSTGRESABBR} ]]; then
      sudo chmod 0700 /ccp/var/pgdata-${POSTGRESABBR}
      sudo chmod g-s /ccp/var/pgdata-${POSTGRESABBR}
    #  sudo cp /$PSQL_MAIN_DIR/pg_hba.conf \
    #          /ccp/var/pgdata-${POSTGRESABBR}/pg_hba.conf
    #  sudo cp /$PSQL_MAIN_DIR/pg_ident.conf \
    #          /ccp/var/pgdata-${POSTGRESABBR}/pg_ident.conf
    #  sudo cp /$PSQL_MAIN_DIR/postgresql.conf \
    #          /ccp/var/pgdata-${POSTGRESABBR}/postgresql.conf
      sudo chown -R postgres /ccp/var/pgdata-${POSTGRESABBR}
      sudo chgrp -R $targetgroup /ccp/var/pgdata-${POSTGRESABBR}
    #  sudo chmod 664 /ccp/var/pgdata-${POSTGRESABBR}/pg_hba.conf
    #  sudo chmod 664 /ccp/var/pgdata-${POSTGRESABBR}/pg_ident.conf
    #  sudo chmod 664 /ccp/var/pgdata-${POSTGRESABBR}/postgresql.conf
    fi

    # If Systems didn't setup postgres beforehand, we called initdb, so the config
    # files under /etc/postgresql/${POSTGRESABBR}/main are ignored.
    # FIXME: What does Systems do differently so those files _do_ work?

    # FIXME: When [[ $isprodserver -ne 0 ]]; then
    #        we should copy different files.
    #        Should we use different path, or is cp_trunk_v2 ok?
    #        what about calling it production rather than ccpv2?

    # Move the logfile
    # FIXME: Implement moving the logfile?
    #   var/pgsql/logfile (can I do that?)

    # Fix permissions

    echo "Setting postgres permissions"

    sudo chmod 2775 /etc/postgresql/${POSTGRESABBR}/main/
    #sudo chmod 2775 /var/log/postgresql/

    sudo chmod 664 /etc/postgresql/${POSTGRESABBR}/main/*
    #sudo chmod 664 /var/log/postgresql/*

    # Own the log and conf.

    sudo chown -R postgres /etc/postgresql/${POSTGRESABBR}/main/
    sudo chgrp -R $targetgroup /etc/postgresql/${POSTGRESABBR}/main/

    # Make the logfile location writeable by postgres.
    sudo chown -R postgres /var/log/postgresql/
    sudo chgrp -R $targetgroup /var/log/postgresql/
    #
    sudo chown -R postgres /ccp/var/log/postgresql
    sudo chgrp -R $targetgroup /ccp/var/log/postgresql

    # Verify the permissions of the folders.

    echo "Verifying postgres permissions"

    #CHECK_ME=`((ls -l /etc/postgresql/${POSTGRESABBR}/main ; \
    #            ls -l /var/log/postgresql/) \
    #            | grep -v "^total " \
    #            | grep -v "postgres $targetgroup" ; \
    #           ls -l /etc/postgresql/${POSTGRESABBR}/main/pg_ident.conf \
    #            | grep -v "\-rw-rw-r-- 1 postgres $targetgroup")`
    CHECK_ME=`((ls -l /etc/postgresql/${POSTGRESABBR}/main ; \
                ls -l /var/log/postgresql/) \
              | grep -v "^total " | grep -v "postgres $targetgroup")`
    if ! [[ -z "$CHECK_ME" ]]; then
      echo "ERROR: Check perms on Postgresql dirs"
      exit 1
    fi

    # Restart the database.

    # NOTE: If we initdb'd earlier, even though we sudo chmod'd the pgdata
    # directory, it got 777'd, for some reason.
    if [[ -d /ccp/var/pgdata-${POSTGRESABBR} ]]; then
      sudo chmod 700 /ccp/var/pgdata-${POSTGRESABBR}
      sudo chmod g-s /ccp/var/pgdata-${POSTGRESABBR}
    fi

    echo "Restarting postgres"

    # Trying to be nice, so skipping: ccp_service_postgres restart
    ccp_service_postgres reload

    # Make the logfile readable by the user.
    # This is the old way. We now store the logs under /ccp/var/log/postgresql
    #  touch /ccp/var/pgsql/logfile
    #  sudo chmod 640 /ccp/var/pgsql/logfile
    #  sudo chown postgres /ccp/var/pgsql/logfile
    #  sudo chgrp $targetgroup /ccp/var/pgsql/logfile

    # Make the 'cycling' user.

    # NOTE: We used to dropdb created by the role and then dropuser to make sure
    # that createuser works, but that's too destructive. Fortunately, with a little
    # bit of tenacious coding, we can just call createuser.  First, try to create
    # the user. This fails if the user is already created or for other reasons.
    set +e
# FIXME: 2016-07-18: It seemed like it took a while for postgres to start...
    createuser -U postgres -SDR cycling 2> /dev/null
    if [[ $? -ne 0 ]]; then
      # Run the command a second time and see if the problem is just that the
      # role already exists.
      CREATEUSER_RESP="`createuser -U postgres -SDR cycling \
                        |& grep -v 'already exists'`"
      # NOTE: If you don't quote the env var, even if it's empty, -n return true.
      if [[ -n "$CREATEUSER_RESP" ]]; then
        # Run the command a third time to get the whole error. The error goes to
        # stderr so we have to do some redirection magic.
        CREATEUSER_RESP="`createuser -U postgres -SDR cycling |& cat`"
        echo
        echo "Error: Cannot createuser: $CREATEUSER_RESP"
        exit 1
      fi
    fi
    # This script runs as 'set +e', so errors are ignored...
    #   NO: set -e

  fi # end: $MACHINE_DOMAIN == "cs.umn.edu"

} # end: setup_psql_config_files
setup_psql_config_files

# *** psycopg2

function setup_install_psycopg2 () {

  echo
  echo "Installing psycopg2"

  #psycopg2_version="psycopg2-2.4.4"
  #psycopg2_version="psycopg2-2.4.6"
  # 2016-07-18: Giving a whack at a double minor jump.
  psycopg2_version="psycopg2-2.6.2"
  cd /ccp/opt/.downloads
  #wget -N http://initd.org/psycopg/tarballs/PSYCOPG-2-4/$psycopg2_version.tar.gz
  wget -N http://initd.org/psycopg/tarballs/PSYCOPG-2-6/$psycopg2_version.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/$psycopg2_version
  tar xvf $psycopg2_version.tar.gz \
    > /dev/null
  cd $psycopg2_version

  # FIXME: If wget says
  # "Server file no newer than local file `psycopg2-2.4.4.tar.gz' -- not retrieving."
  # we shouldn't rebuild...
  echo -n "Compiling and installing psycopg2... "
  PYTHONPATH=$ccp_python_path \
    PATH=/usr/bin/pg_config:$PATH \
    python setup.py install --prefix=/export/scratch/ccp/opt/usr \
    > /dev/null
  echo "ok."

  # Fix the permissions on the psycopg2 folder so apache can load it.

  sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public /ccp/opt/usr/ \
    > /dev/null 2>&1

} # end: setup_install_psycopg2
setup_install_psycopg2

# *** PgBouncer

# 2013.07.08: The old production server, itamae, for the past few weeks has
# been having Postgres connection issues, e.g.,
#   ProgrammingError: ERROR: current transaction is aborted,
#                            commands ignored until end of transaction block
# This is related to postgresql.conf's max_connections, which defaults to 100,
# but if you look online you'll find that most people suggest using a database
# connection pool rather than increasing max_connections.
#
# (We might also have a problem not closing connections, i.e., not cleaning up
# properly, but in either case, using a connection pool is a wise thing to do
# for a production Web site.)
#
# See:
#   https://wiki.postgresql.org/wiki/PgBouncer
#   http://pgfoundry.org/projects/pgbouncer/

# Prerequisite: libevent
#   http://monkey.org/~provos/libevent/
# libevent is installed on U. machines but on itamae it's version 1.x and we
# want version 2.x.

function setup_pgbouncer () {

  echo
  echo "Installing libevent"

  cd /ccp/opt/.downloads
  wget -N \
   https://github.com/downloads/libevent/libevent/libevent-2.0.21-stable.tar.gz \
    --no-check-certificate
  /bin/rm -rf /ccp/opt/.downloads/libevent-2.0.21-stable
  tar xvf libevent-2.0.21-stable.tar.gz \
    > /dev/null

  cd libevent-2.0.21-stable
  ./configure --prefix=/ccp/opt/usr
  make
  make verify
  #sudo make install
  make install

  # FIXME: 2013: PgBouncer is disabled until we figure out how to make it work!

  if false; then

    echo
    echo "Installing PgBouncer"

    # MAYBE: Use git instead? Then we don't have to manually update the version
    #        number of the wget file.

    # $ git clone git://git.postgresql.org/git/pgbouncer.git
    # $ cd pgbouncer
    # $ git submodule init
    # $ git submodule update
    # $ ./autogen.sh
    # $ ./configure ...
    # $ make
    # $ make install

    cd /ccp/opt/.downloads
    wget -N http://pgfoundry.org/frs/download.php/3393/pgbouncer-1.5.4.tar.gz
    /bin/rm -rf /ccp/opt/.downloads/pgbouncer-1.5.4
    tar xvf pgbouncer-1.5.4.tar.gz \
      > /dev/null
    cd pgbouncer-1.5.4

    ./configure --prefix=/ccp/opt/usr \
      --with-libevent=/ccp/opt/usr/lib
    #  > /dev/null
    make
    make install

    ccp_mkdir /ccp/opt/pgbouncer
    chmod 2777 /ccp/opt/pgbouncer
    #
    ccp_mkdir /ccp/var/log/pgbouncer
    touch /ccp/var/log/pgbouncer/pgbouncer.log
    /bin/chmod 664 /ccp/var/log/pgbouncer/pgbouncer.log
    sudo chown -R postgres /ccp/var/log/pgbouncer/pgbouncer.log

    #system_file_diff_n_replace "etc/logrotate.d" "apache2"
    /bin/cp -f \
      ${SCRIPT_DIR}/../ao_templates/common/ccp/opt/pgbouncer/pgbouncer.ini \
      /ccp/opt/pgbouncer
    /bin/chmod 664 /ccp/opt/pgbouncer/pgbouncer.ini

    /bin/cp -f \
      ${SCRIPT_DIR}/../ao_templates/common/ccp/opt/pgbouncer/userlist.txt \
      /ccp/opt/pgbouncer
    /bin/chmod 664 /ccp/opt/pgbouncer/userlist.txt

  fi

} # end: setup_pgbouncer
setup_pgbouncer

# *** Apache

# FIXME: Some of this is specific to Ubuntu.

function setup_apache () {

  echo
  echo "Preparing apache from master: $masterhost"
  echo

  # Add user to apache group (so they can, e.g., modify /ccp/var/tilecache-cache)

  sudo usermod -a -G $httpd_user $targetuser

  # Own the confs and log.

  sudo chgrp -R $targetgroup /etc/apache2
  sudo chgrp -R $targetgroup /var/log/apache2

  if [[ $MACHINE_DOMAIN == "cs.umn.edu" ]]; then

    # Check /etc/logrotate.d/apache2
    #
    # In the file, find 'create 640 root adm' and change to
    # 'create 640 root $targetgroup'

    echo "Copying Apache conf files..."

    # Update logrotate to use group '$targetgroup' instead of 'adm'.
    # I.e., /etc/logrotate.d/apache2
    # FIXME: What to do for production server?
    system_file_diff_n_replace "etc/logrotate.d" "apache2"

    # Update ports.conf to specify more than just port 80, i.e., 8081, 8082, ....
    # I.e., /etc/apache2/ports.conf
    # FIXME: What to do for production server?
    system_file_diff_n_replace "etc/apache2" "ports.conf"

    # Enable two Apache modules.
    #
    # EXPLAIN What are these used for?

    echo -n "Enabling Apache modules... "

    # See
    #  ll /etc/apache2/mods-available
    #  ll /etc/apache2/mods-enabled

    if ! [[ -e /etc/apache2/mods-enabled/deflate.load ]]; then
      echo "Error: Expected deflate module to be loaded."
      exit 1
    fi

    sudo a2enmod headers > /dev/null
    sudo a2enmod rewrite > /dev/null

    echo "ok."

    # *** Configure sites-available

    echo "Removing default Apache httpd.conf."

    /bin/rm -f /etc/apache2/sites-enabled/000-default

    # Fix permissions.

    sudo chmod 664 /etc/apache2/sites-available/*

    # Since we copied files to /etc/apache2, fix their ownership.
    # These were created as owned by 'root' but nuts to that.
    sudo chown -R $targetuser /etc/apache2
    sudo chgrp -R $targetgroup /etc/apache2

    # Make the logfile location writeable by apache.
    ccp_mkdir /ccp/var/log/apache2
    sudo chown -R $httpd_user /ccp/var/log/apache2
    sudo chgrp -R $targetgroup /ccp/var/log/apache2

    # Verify the permissions of the folders.

    CHECK_ME=`ls -l /etc/apache2 \
              | grep -v "^total " \
              | grep -v "$targetuser $targetgroup"`

    if ! [[ -z "$CHECK_ME" ]]; then
      echo "ERROR: Check perms on Apache dirs"
      exit 1
    fi

    CHECK_ME=`ls -l /var/log/apache2 \
              | grep -v "^total " \
              | grep -v "root $targetgroup"`

    if ! [[ -z "$CHECK_ME" ]]; then
      echo "ERROR: Check perms on Apache dirs"
      exit 1
    fi

  fi

} # end: setup_apache
setup_apache

# *** mod_python

# NOTE: Not installing mod_python. Too difficult do given the U's I.T.
# infrastructure. That is, we'd either have to rebuild Apache, or we have to
# compile and install using the so-called DSO method. It's easier just to
# support Python 2.6 for Ubuntu 10.04 and also to support Python 2.7 for Ubuntu
# 11.04.

function setup_mod_python () {

  #echo
  #echo "Installing mod_python"
  #
  #cd /ccp/opt/.downloads
  #wget -N https://archive.apache.org/dist/httpd/modpython/mod_python-2.7.11.tgz
  #/bin/rm -rf /ccp/opt/.downloads/mod_python-2.7.11
  #tar xvf mod_python-2.7.11.tgz \
  #  > /dev/null
  #cd mod_python-2.7.11
  #
  # I think apxs is from a dev package:
  # p   apache2-prefork-dev        - Apache development headers - non-threaded
  # p   apache2-threaded-dev       - Apache development headers - threaded MPM
  #
  #./configure --prefix=/ccp/opt/modpython-2.7 \
  #  --with-apxs=/usr/local/apache/sbin/apxs
  #
  # make dso
  # sudo make install
  #
  #sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public blah blah blah

} # end: setup_mod_python
setup_mod_python

# *** Reload Apache (we could restart but this is nicer).

echo "Reloading Apache"

ccp_apache_reload

# FIXME: Fedora:
# sudo /etc/init.d/httpd reload

# *** Restore location

cd $script_path

# *** All done!

echo
echo "Done setting up apache and postgres."

exit 0

