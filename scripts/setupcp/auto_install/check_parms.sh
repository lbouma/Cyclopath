#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script.
#

script_relbase=$(dirname $0)
script_absbase=`pwd $script_relbase`

USAGE="Usage: $0 MASTER_HOSTNAME|- TARGET_USERNAME|-"
# Skipping: $3, $4, and $5, which is used internally.

masterhost=$1
targetuser=$2
isbranchmgr=$3
isprodserver=$4
reload_databases=$5
svn_update_sources=$6

# Check that the name of the master host is supplied.
if [[ -z "$masterhost" ]]; then
  echo -e "\nError: Please specify the name of the master host."
  echo "The master host is a machine already setup for Cyclopath."
  echo -e "\n$USAGE"
  exit 1
fi
# Check that the master's ccp/ dir is accessible.
if [[ "$masterhost" == "-" ]]; then
  masterhost=$HOSTNAME
  echo -e "\Master host not supplied; using: $masterhost"
fi
if ! [[ -d /scratch/$masterhost/ccp/dev ]]; then
  if [[ "$masterhost" != "$HOSTNAME" ]]; then
    echo -e "\nError: Master host's ccp/dev dir not found."
    echo "I.e., not found: /scratch/$masterhost/ccp/dev"
    exit 1
  fi
fi

# Check that the name of the target user is supplied.
if [[ "$targetuser" == "-" ]]; then
  targetuser=$LOGNAME
  echo -e "\nUsername not supplied; using: $targetuser"
fi
if [[ -z "$targetuser" ]]; then
  echo -e "\nError: Please specify the name of the target user."
  echo "The target user is the username of the developer for whom you are"
  echo "installing Cyclopath."
  echo -e "\n$USAGE"
  exit 1
fi
# Check that the target is a user. Implicit $? check.
# NOTE: If user is not recognized, you'll see stderr. And 
#       this does not work: id $targetuser 2> /dev/null
#       this does not work: id $targetuser > /dev/null 2>&1
if ! [[ "`id $targetuser`" ]]; then
  echo -e "\nError: User not recognized: $targetuser"
  exit 1
fi

# FIXME: We only support CS network installs. 
#        To support offline installs: 
#        (1) checkin files from ccpdev to the public repos
#        (2) do not rely upon masterhost for copying files

# Only warn once. The bash test -v checks if env var is set/unset.
# Hrmm. This works in:
#  GNU bash, version 4.2.45(1)-release (x86_64-pc-linux-gnu)
# but not:
#  GNU bash, version 4.1.5(1)-release (x86_64-pc-linux-gnu)
# so avoid this:
#  if [[ ! -v CHECK_PARMS_WARNED ]]; then ... fi
if [[ -z $CHECK_PARMS_WARNED ]]; then
  WARN_UNSUPPORTED=false
  # The `dnsdomainname` command == `hostname --domain`
  MACHINE_DOMAIN=`hostname --domain`
  if [[ -z "$MACHINE_DOMAIN" ]]; then
    WARN_UNSUPPORTED=true
  elif [[ "$MACHINE_DOMAIN" != "cs.umn.edu" ]]; then
    WARN_UNSUPPORTED=true
  fi

  # FIXME: Remove the WARN_UNSUPPORTED code: [lb] got
  #        the scripts running on a Mint 16 virtual machine.
  WARN_UNSUPPORTED=false

  if $WARN_UNSUPPORTED; then
    # This previous output is on the same line ("Checking input options...") so
    # echo twice to achieve newline status.
    echo
    echo
    echo "Notice: This installer is mostly tested locally at the Univ. of MN."
    echo "I.e., instead of 'cs.umn.edu', your domain says (or doesn't say):"
    echo "      '$MACHINE_DOMAIN'."
    echo
    echo -n "Would you like to try installing anyway? ([Y]/n) "
    read sure
    echo 
    if [[ "$sure" != "y" && "$sure" != "Y" && "$sure" != "" ]]; then
      echo "User opted not to try installing anyway. Exiting."
      exit 1
    fi
  fi
  export CHECK_PARMS_WARNED=true
fi

# If the caller is the mint installer, we might have not rebooted since
# assigning the hostname, so we can take it explicitly.
if [[ -n $USE_DOMAIN ]]; then
  MACHINE_DOMAIN=$USE_DOMAIN
fi

#forceinstall=$3
## Check that the name of the target user is supplied.
## EXPLAIN: Why doesn't == work? Bash tries to run it.
##            if [[ "$forceinstall" == "--force" ]]; then
##  causes: [: 62: --force: unexpected operator
##          But using != works just fine...
#if [[ "$forceinstall" != "--force" ]]; then
#  #echo "Not using --force"
#  forceinstall=false
#else
#  #echo "Detected --force"
#  forceinstall=true
#fi

# Check that the SVN is specified
if [[ -z "$svnroot" ]]; then
  svnroot=$SVNROOT
fi

# Set the targetgroup according to the domain (if on the CS network or not).
if [[ "$MACHINE_DOMAIN" == "cs.umn.edu" ]]; then
  targetgroup=grplens
  if [[ -z "$svnroot" ]]; then
    echo
    #echo "Error: Please specify \$svnroot or \$SVNROOT."
    svnroot="svn+ssh://$USER@$HOSTNAME.cs.umn.edu/project/Grouplens/svn/cyclingproject"
    echo "Warning: \$svnroot or \$SVNROOT not found. But we can guess..."
    echo
  fi
else
  # FIXME: The cyclop group is not automatically created...
  # FIXME: also, make apache and postgres members of the group?
  #         usermod -a -G $targetgroup postgres
  #         usermod -a -G $targetgroup $httpd_user
  targetgroup=cyclop
  if [[ -z "$svnroot" ]]; then
    svnroot="svn://cycloplan.cyclopath.org/cyclingproject"
  fi
fi
echo "Using svnroot: $svnroot"

# Setup PYTHONVERS, PYVERSABBR, httpd_user, httpd_etc_dir.

PYSERVER_HOME=/dev/null
CCP_WORKING=${script_absbase}/../../../
source ${script_absbase}/../../util/ccp_base.sh

# Setup common paths.

# What about Ubuntu 12.04? What about Fedora?
#CCPDEV_PSQL_TARGET="setup/ubuntu10.04-target"

# Reference the right setup files, e.g., at
#  /ccp/bin/ccpdev/setup/ubuntu12.04-target
#AO_TEMPLATE_BASE="/ccp/bin/ccpdev/setup"
AO_TEMPLATE_BASE="${script_absbase}/../ao_templates"
if [[ -n "${FEDORAVERSABBR}" ]]; then
  # FIXME/BUG nnnn: Support Fedora.
# FIXME: The Ccpdev source and target for Fedora have not been created  yet.
  CCPDEV_PSQL_SOURCE="fedora${FEDORAVERSABBR}-source"
  CCPDEV_PSQL_TARGET="fedora${FEDORAVERSABBR}-target"
elif [[ -n "${UBUNTUVERSABBR}" ]]; then
  CCPDEV_PSQL_SOURCE="ubuntu${UBUNTUVERSABBR}-source"
  CCPDEV_PSQL_TARGET="ubuntu${UBUNTUVERSABBR}-target"
elif [[ -n "${MINTVERSABBR}" ]]; then
  CCPDEV_PSQL_SOURCE="mint${MINTVERSABBR}/source"
  CCPDEV_PSQL_TARGET="mint${MINTVERSABBR}/target"
else
  echo "ERROR: Not Fedora or Ubuntu or Mint."
  exit 1
fi

# Setup m4 definitions.

# Determine the physical RAM available, and compute an appropriate value for
# Postgresql's shared_buffers setting.
# NOTE: `cat /proc/meminfo` shows system memory info. We're interested in
# MemTotal, e.g., MemTotal:        3091520 kB
# NOTE: Why doesn't \d work in sed? According to `info sed`, it supports,
#       e.g., \w and \W, but not \d?
# Get the total system memory, in Kbs.
tot_sys_mem=`cat /proc/meminfo | grep MemTotal | sed s/[^0-9]//g`
# FIXME: 2012.06.02: Test this on huffy and runic and satisfy things work
# soundly (and hopefully soundlier) and then remove this FIXME comment.
PGSQL_SHBU=$(($tot_sys_mem / 3))kB

if [[ -n "$MACHINE_DOMAIN" ]]; then
  targetdom=$MACHINE_DOMAIN
else
  targetdom="yourdomain.com"
fi

if [[ "$MACHINE_DOMAIN" == "cs.umn.edu" ]]; then
  mail_from_addr="info@cyclopath.org"
  internal_email="grpcycling@cs.umn.edu"
else
  mail_from_addr="$USER@$HOSTNAME"
  internal_email="$USER@$HOSTNAME"
fi

# MAGIC_NUMBER: Excuse the hard-coding. We only ever have one production
# machine (at least until we build the cloud solution) so it's not that
# big of a deal to specify its name here.
servermach="runic"

# These are common switches we send to m4 when converting templates to 
# user- and machine-specific files.
# NOTE: Some fcns. define a few more local defines, e.g.,
#  --define=CCPBASEDIR=$ccp_target \
#  --define=CCP_DB_NAME=$checkout_path \
ccp_m4_defines="
  --define=TARGETUSER=$targetuser
  --define=TARGETHOST=$HOSTNAME
  --define=TARGETDOMAIN=$targetdom
  --define=SERVERMACHINE=$servermach
  --define=PYTHONVERS=$PYTHONVERS
  --define=PYVERSABBR=$PYVERSABBR
  --define=PGSQL_SHBU=$PGSQL_SHBU
  --define=MACHINE_IP=$MACHINE_IP
  --define=HTTPD_USER=$httpd_user
  --define=MAILFROMADDR=$mail_from_addr
  --define=INTERNALMAIL=$internal_email
  "
#  --define=SSEC_UUID=`uuidgen`"
# FIXME: put 'changecom' at top of m4 files so that comments are ignored (and
# things in comments are converted)

# Load helper libs.

source ${script_absbase}/helpers_lib.sh

# NOTE: Do not call exit. The calling script sourced us, so if we exit, we'll
# take the caller with us.
#exit 0

