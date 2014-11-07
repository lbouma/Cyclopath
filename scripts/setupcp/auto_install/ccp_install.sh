#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./ccp_install.sh

# 
# THIS SCRIPT IS CANNOT BE RUN UNATTENDED. YOU MUST BE LOGGED ON. 
# AND HOPEFULLY YOU WILL ONLY BE ASKED FOR YOUR PASSWORD ONCE.
#

# NOTE: This script calls scripts which call sudo. Ask a Staffer or Systemser 
#       to run it.

# NOTE: If you're installing over ssh, you'll want to map 8080 (or 8081?) to 
#       test that Cyclopath was not only installed but also prepared for
#       development.
#
#ssh -L 8080:localhost:80 -L 8081:localhost:8081 $USERNAME@$HOSTNAME.cs.umn.edu

# PREREQUISITES:
# Set PYTHONPATH before installing. See below.

# Exit on error.
set -e

script_relbase=$(dirname $0)
script_absbase=`pwd $script_relbase`

HOST=$(hostname)

echo 
echo "Installing Cyclopath on $HOST"
echo 

# Start a timer.
ccp_time_0=$(date +%s.%N)

# *** Check input options

echo -n "Checking input options..."

# SYNC_ME: This block of code is shared.
$script_absbase/check_parms.sh $*
if [[ $? -ne 0 ]]; then
  exit
fi
masterhost=$1
targetuser=$2

echo " options ok"

# *** Ask a few questions.

isbranchmgr=0
isprodserver=0

echo 
echo -n "Are you setting up the branch manager's machine? (y/[N]) "
read sure
if [[ "$sure" == "y" || "$sure" == "Y" ]]; then
  isbranchmgr=1
else
  echo 
  echo -n "Are you setting up the production server? (y/[N]) "
  read sure
  if [[ "$sure" == "y" || "$sure" == "Y" ]]; then
    isprodserver=1
  fi
fi

# *** Check if we've done this before.

# See if the target's ccp/ dir already exists.

svn_update_sources=1
reprepare_dirs=1
reoverlay_etc=1
reinstall_flash=1
reinstall_software=1
reinstall_cyclopath=1
if [[ -e /ccp ]]; then
  if ! [[ -d /ccp ]]; then
    echo "Error: /ccp exists but not a directory."
    exit 1
  else
    echo 
    echo "Warning: /ccp already exists"
    echo -n "Continue anyway and overwrite or merge dirs? (y/[N]) "
    read sure
    if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
      echo 
      echo "User opted not to install anyway. Exiting."
      exit 0;
    fi
    if [[ -d /ccp/dev ]]; then
      echo 
      echo -n "Would you like to 'svn update' Cyclopath sources? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        svn_update_sources=0
      fi
    fi
    #if [[ -d /ccp/dev ]]; then
      echo 
      echo -n "Call dir_prepare.sh to setup /ccp structure? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        reprepare_dirs=0
      fi
    #fi
    #if [[ -d /ccp/dev ]]; then
      echo 
      echo -n "Call etc_overlay.sh to configure services? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        reoverlay_etc=0
      fi
    #fi
    #if [[ -d /ccp/dev ]]; then
      echo 
      echo -n "Call flash_debug.sh to install Flash? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        reinstall_flash=0
      fi
    #fi
    if [[ -d /ccp/opt ]]; then
      echo 
      echo -n "Call gis_compile.sh to reinstall software? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        reinstall_software=0
      fi
    fi
    if [[ -d /ccp/dev ]]; then
      echo 
      echo -n "Call prepare_ccp.sh to install Cyclopath? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        reinstall_cyclopath=0
      fi
    fi
  fi
fi

# *** Check if the database has been created.

#reload_database=1
#set +e # don't bail if psql fails
## FIXME: ccpv2 is used throughout these scripts. Make global.
#psql -U cycling -c '\d item_type' ccpv2 > /dev/null 2>&1
#if [[ 0 -eq $? ]]; then
#  echo 
#  echo -n "Would you like to keep already-loaded database? (y/[N]) "
#  read sure
#  if ! [[ "$sure" != "y" && "$sure" != "Y" ]]; then
#    reload_database=0
#  fi
#fi
#set -e
reload_databases=0
echo 
echo -n "Would you like to reload already-loaded database(s)? (y/[N]) "
read sure
if [[ "$sure" == "y" || "$sure" == "Y" ]]; then
  reload_databases=1
fi

# *** Ask for user's password just this once.

# Update the user's sudo timestamp, so we can keep it fresh.

echo
echo "We need you to be sudo, so you may need to enter your password now."
echo "And maybe in the future, too, but we'll try to keep the timestamp alive."

sudo -v

echo

# Run a background sudo updater

cleanup()
{
  # Kill the background process
  echo "Killing sudo_keeali"
  # FIXME: Even with the /dev/null 2>&1 I'm still seeing output:
  # ./ccp_install.sh: line 157: 13428 Killed     $script_absbase/sudo_keeali.sh
  ps aux \
    | grep -e "/bin/bash ./sudo_keeali.sh" \
    | awk '{print $2}' \
    | xargs sudo kill -s 9 \
    > /dev/null 2>&1
  #return $?
}

control_c()
{
  echo -en "\n*** Ouch! Exiting ***\n"
  cleanup
  exit $?
}
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT

# FIXME: I don't think the sudo kicker _always_ works. I think calling sudo -v
# from this script works, but when another script asks for it, I get prompted;
# e.g., whenever 'make clean' is called, I get prompted for my password, even
# if I just gave it....
# 2014.01.17: This never really worked, because of either the sudo password
# timeout, or because this work-around just doesn't work. But if you set up
# sudoers so your terminal doesn't time out, you'll be okay... except you
# probably can't edit sudoers on the corporate network without getting in
# trouble; maybe ask Systems for help?
#echo 
echo -n "Would you like to run the background sudo kicker? (y/[N]) "
read sure
if [[ "$sure" == "y" || "$sure" == "Y" ]]; then
  # Keep sudo alive
  # FIXME: What this is killed, I think it prints to stdout/err:
  # ./ccp_install.sh: line 157: 13428 Killed     $script_absbase/sudo_keeali.sh
  $script_absbase/sudo_keeali.sh &
  # Let the script run and output a line
  #sleep 1
fi
echo

# *** Check that packages are setup properly.

read -p "Would you like to run package verification? (y/[N]) " sure
if [[ "$sure" == "y" || "$sure" == "Y" ]]; then
  echo
  echo -n "Checking packages... "
  if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
    # echo Ubuntu!
    if [[ "`$script_absbase/ok_packages.sh`" ]]; then
      echo "flagged"
      echo
      echo "Warning: Packages not configured as expected"
      echo "============================================"
      echo "Showing discrepencies:"
      echo 
      # Show the list of packages.
      $script_absbase/show_pkg_es.sh
      # Ask for confirmation.
      echo 
      read -p "Would you like to install anyway? (y/[N]) " sure
      echo
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        #echo "Aborting."
        exit 0;
      fi
    else
      echo "ok"
    fi
  elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
    # echo Red Hat!
    # FIXME: Implement...
    echo "skipping (Fedora)."
  else
    echo "?"
    echo "Error: Unknown OS!"
    exit
  fi;
fi;

# If we're overlaying the install, we need to fixperms.
if [[ -d /ccp ]]; then
  if [[ "$masterhost" != "$HOSTNAME" && -d /ccp ]]; then
    echo 
    echo -n "Run fixperms on existing /ccp/? (y/[N]) "
    read sure_fix_perms
  fi
fi

# *** Dummy prompt, so user knows when the script actually starts.

echo
read -p "Are you ready?! (y/[N]) " sure
if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
  echo  "                        Too bad!"
fi

# *** Fix permissions

# If we're overlaying the install, we need to fixperms.
if [[ -d /ccp ]]; then
  if [[ "$masterhost" != "$HOSTNAME" && -d /ccp ]]; then
    # See earlier for prompt.
    if [[ "$sure_fix_perms" == "y" || "$sure_fix_perms" == "Y" ]]; then
      # This can take a while if you have, e.g., lots of tiles.
      echo
      echo -n "Fixing permissions before overlay... "
      #if [[ -e /ccp/bin/ccpdev/bin/fixperms ]]; then
      #  sudo /ccp/bin/ccpdev/bin/fixperms --public /ccp/ \
      #    > /dev/null 2>&1
      #elif [[ -e /ccp/dev/cp/scripts/util/fixperms.pl ]]; then
      #  sudo /ccp/dev/cp/scripts/util/fixperms.pl --public /ccp/ \
      #    > /dev/null 2>&1
      #else
      #  echo
      #  echo "WARNING: Could not fixperms /ccp"
      #  echo
      #fi
      sudo ${script_absbase}/../../util/fixperms.pl --public /ccp/ \
          > /dev/null 2>&1
      echo "ok"
    fi
  fi
fi

# *** Run the scripts

echo
echo "Installing Cyclopath..."

# Reset the positional parameters
set -- $masterhost $targetuser $isbranchmgr $isprodserver \
       $reload_databases $svn_update_sources

echo
echo "Using params: $*"

# Prepare the /ccp/* directory structure and copy files from the master
# (another Cyclopath machine that's already setup).

if [[ $reprepare_dirs -ne 0 ]]; then
  $script_absbase/dir_prepare.sh $*
  $script_absbase/usr_dev_doc.sh $*
fi

# Setup Apache and Postgresql.

if [[ $reoverlay_etc -ne 0 ]]; then
  $script_absbase/etc_overlay.sh $*
fi

# Setup the debug flash player.

if [[ $reinstall_flash -ne 0 \
      && $isprodserver -eq 0 ]]; then
  $script_absbase/flash_debug.sh $*
fi

# Compile the GIS suite.

if [[ $reinstall_software -ne 0 ]]; then
  $script_absbase/gis_compile.sh $*
fi

# Prepare Cyclopath so user can hit http://localhost:8081.

# FIXME: Fix prepare_ccp: it calls a few things that should only happen when
# updating to CcpV2, but not once we're updated.

if [[ $reinstall_cyclopath -ne 0 ]]; then
  $script_absbase/prepare_ccp.sh $*
fi

# *** Print a reminder(s)

# If we were to use Python 2.7 -- but we're not, because of mod_python -- we'd
# suggest here: 
#   module load soft/python/2.7

echo
cat startup_eg.txt
echo

# *** Print the install time.

ccp_time_n=$(date +%s.%N)
echo "Install started at: $ccp_time_0"
echo "Install finishd at: $ccp_time_n"
ccp_elapsed=$(echo "$ccp_time_n - $ccp_time_0" | bc -l)
echo "Elapsed: $ccp_elapsed secs."
echo

# *** Stop the background sudo hack

set +e
cleanup
set -e

# *** Restore location.

cd $script_path

# *** And away we go.

echo
echo "Thanks for installing Cyclopath!"
echo

exit 0

