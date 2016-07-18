#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./dir_prepare.sh
#  (also called from ccp_install.sh)

# NOTE: This script is meant to be run on the CS network at the U.

# NOTE: This script calls sudo a few times, so you gotta be staff with lab-wide
# sudo to run this script.

# Exit on error.
set -e

script_relbase=$(dirname $0)
script_absbase=`pwd $script_relbase`

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its 
#          variables become ours.
. $script_absbase/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,
#            reload_databases, PYTHONVERS, and httpd_user.

# Check that the master's ccp/ dir is accessible.
if ! [[ -d /scratch/$masterhost/ccp/dev ]]; then
  if [[ "$masterhost" != "$HOSTNAME" ]]; then
    echo "Error: Master ccp/ dir not found"
    exit 1
  fi
fi

# *** Begin.

echo
echo "Preparing ccp/* from master: $masterhost"

# Kick sudo. Prompt user now rather than later.
sudo -v

# *** Setup ccp/

# Make the ccp/ directory.
#if [[ -d /export/scratch ]]; then
# 2016-07-17: On a managed host; server doesn't need to use scratch.
if [[ -d /export/scratch/${HOSTNAME} ]]; then
  ccp_mkdir /export/scratch/ccp
  # Make a convenience link. (-h checks that /ccp is a link.)
  #
  # FIXME: On the production server, /ccp/var is on a different
  #        hard drive, which is mapped from /export/scratch2,
  #        so you might have to move /export/scratch/ccp/var
  #        to /export/scratch2/ccp/var, and then make a link
  #        from /export/scratch/ccp/var.
  if [[ -h /ccp ]]; then
    sudo /bin/rm -f /ccp
  elif [[ -e /ccp ]]; then
    echo "ERROR: The /ccp exists and is not a link."
    exit 1
  fi
  sudo ln -s /export/scratch/ccp /ccp
else
  if [[ ! -e /ccp ]]; then
    sudo /bin/mkdir -p /ccp
    sudo /bin/chgrp $targetgroup /ccp
    sudo /bin/chmod 2775 /ccp
  fi
fi

# *** Setup ccp/bin

echo 
echo "Checking out the machine scripts"

# Checkout the machine scripts.
mkdir -p /ccp/bin
#sudo /bin/rm -rf /ccp/bin/ccpdev
if [[ -d /ccp/bin/ccpdev ]]; then
  cd /ccp/bin/ccpdev
  svn update
  # MAYBE: 2012.11.13: [lb] moved the SVN repository so existing dev machines
  #                    should have "svn switch ..." run on them.
elif [[ "$MACHINE_DOMAIN" == "cs.umn.edu" ]]; then
  svn co $svnroot/ccpdev \
    /ccp/bin/ccpdev \
    > /dev/null
# else: a developer machine; ccpdev not required.
fi

if [[ -d /ccp/bin/ccpdev ]]; then
  sudo chown -R $targetuser /ccp/bin/ccpdev
  sudo chgrp -R $targetgroup /ccp/bin/ccpdev
fi

# Change the SVN URL to reflect the target user.
# FIXME: You can't change svnroot to point to $targetuser because it'll ask you
# for their password. So I tried the relocate command but it ignored my changes
# to the username...
#cd /ccp/bin/ccpdev
#svn sw --relocate \
#  svn+ssh://${LOGNAME}@${CS_PRODUCTION}/project/Grouplens/svn/cyclingproject/public/ccpv2 \
#  svn+ssh://${targetuser}@${CS_PRODUCTION}/project/Grouplens/svn/cyclingproject/public/ccpv2
#
# FIXME: Maybe you can checkout without your username? On itamae:
# URL: svn+ssh://runic/project/Grouplens/svn/cyclingproject/releases/53

# *** Setup ccp/opt

ccp_mkdir /ccp/opt
ccp_mkdir /ccp/opt/.downloads
ccp_mkdir /ccp/opt/usr
ccp_mkdir /ccp/opt/usr/lib
ccp_mkdir /ccp/opt/usr/lib/python

# *** Setup ccp/var

ccp_mkdir /ccp/var
ccp_mkdir /ccp/var/log
# NOTE: We save historic Apache logs but not historic Postgresql logs.
ccp_mkdir /ccp/var/log/apache2
ccp_mkdir /ccp/var/log/apache2/historic
ccp_mkdir /ccp/var/log/postgresql
ccp_mkdir /ccp/var/log/pyserver # Our server and service logs.
ccp_mkdir /ccp/var/log/daily # Our cron logs.
ccp_mkdir /ccp/var/log/daily/cache # For check_cache_now.sh.
ccp_mkdir /ccp/var/log/mediawiki # Our mediawiki logs.
ccp_mkdir /ccp/var/log/statistics # See scripts/analyze/sql/*.
# Make sure the daily log is world readable-writable.
# (This is for tilecache_update.py when it runs via apache user.)
sudo chmod 2777 /ccp/var/log/daily
sudo chmod 2777 /ccp/var/log/daily/cache

# 2012.08.21: Move pyserver dumps here, from /tmp/pyserver_dumps.
ccp_mkdir /ccp/var/log/pyserver_dumps
# Make sure it's world readable-writable.
sudo chmod 2777 /ccp/var/log/pyserver_dumps

# FIXME: 2012.08.21: There are a few other dirs to add, too... See daily.sh.

# Make the dummy log for logcheck.
touch /ccp/var/log/dummy_log
chmod 664 /ccp/var/log/dummy_log

# Make the pyserver log location world-writable, for www-data.
# FIXME: It's probably okay now -- We touch and chown these logs to www-data.
#        So I think we don't need to chmod 2777....
#sudo chmod 2777 /ccp/var/log/pyserver

# Ug. When postgres makes its logs, they're private. Preemptively fix that.
# SYNC_ME: Search postgresql-%a.log
for day_of_week in "Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"; do
  filepath=/ccp/var/log/postgresql/postgresql-${day_of_week}.log
  sudo touch $filepath
  sudo chmod 664 $filepath
  sudo chown postgres $filepath
  sudo chgrp $targetgroup $filepath
done

# Same for Apache
for log_file in "access.log" "error.log"; do
  filepath=/ccp/var/log/apache2/${log_file}
  sudo touch $filepath
  sudo chmod 664 $filepath
  # These default to owned by root. Is that vital?
  #sudo chown www-data $filepath
  sudo chown root $filepath
  sudo chgrp $targetgroup $filepath
done

# I'm not sure if these need to be world-readable for logcheck, but do it 
# anyway (I got a logcheck email because of either missing files or lack of 
# permissions...).
# FIXME: rename log/pyserver since pyserver is already a folder name? it
#        confused me earlier today whilst in a terminal... i saw pyserver but
#        there was no ccp.py.
for instance_name in "colorado" "minnesota" "no_instance"; do
  for service_name in "apache" "misc" "mr_do" "routed" "spark" "tilecache"; do
    filename=${instance_name}-${service_name}.log
    filepath=/ccp/var/log/pyserver/${filename}
    sudo touch $filepath
    sudo chmod 664 $filepath
    sudo chown $httpd_user $filepath
    sudo chgrp $targetgroup $filepath
  done

# FIXME: route analysis ccp.py must run as apache, so... either need 666,
# apache should be in cyclop group, or, apache is owner and our group is
# group...
#         usermod -a -G $targetgroup postgres
#         usermod -a -G $targetgroup $httpd_user
  # Actually, the 'misc' log is not owned by apache. Probably doesn't matter.
  filename=${instance_name}-misc.log
  filepath=/ccp/var/log/pyserver/${filename}
  sudo chown $targetuser $filepath

done

# Make a few dirs.

ccp_mkdir /ccp/var/cpdumps
ccp_mkdir /ccp/var/dbdumps
ccp_mkdir /ccp/var/.dbdumps.daily

# Make the path_helper_lock for merge_job_import. Using sudo in case we've 
# already run auto_install, in which case apache owns it.
sudo touch /ccp/var/cpdumps/.path_helper_lock
sudo chmod 664 /ccp/var/cpdumps/.path_helper_lock
# Apache owns the cpdumps.
sudo chown -R $httpd_user /ccp/var/cpdumps/
sudo chgrp -R $httpd_user /ccp/var/cpdumps/
# NOTE: I don't think there's any reason to give grplens group-access.
#sudo chgrp -R $targetgroup /ccp/var/cpdumps/

# Copy the elevation.

ccp_mkdir /ccp/var/elevation

if [[ "$masterhost" != "$HOSTNAME" ]]; then

  echo 
  echo "Copying elevation DEMs"

  #cp -rf /scratch/$masterhost/ccp/var/elevation/* \
  #  /ccp/var/elevation
  if ! [[ -e /ccp/var/elevation/minnesota.dem ]]; then
    cp -rf /scratch/$masterhost/ccp/var/elevation/minnesota.dem \
      /ccp/var/elevation/minnesota.dem
  fi
  if ! [[ -e /ccp/var/elevation/colorado.tif ]]; then
    cp -rf /scratch/$masterhost/ccp/var/elevation/colorado.tif \
      /ccp/var/elevation/colorado.tif
  fi

  sudo chown -R $targetuser /ccp/var/elevation 
  sudo chgrp -R $targetgroup /ccp/var/elevation 

fi

if [[ ! -e /ccp/var/elevation/minnesota.dem ]]; then

  echo 
  echo "Downloading elevation DEMs"

  # FIXME/SYNC_ME: We should get this from pyserver/CONFIG::elevation_tiff...
  wget -N -O /ccp/var/elevation/minnesota.dem \
    http://cycloplan.cyclopath.org/exports/devs/minnesota.dem

fi

# Copy the transit data.

ccp_mkdir /ccp/var/transit
ccp_mkdir /ccp/var/transit/metc

if [[ "$masterhost" != "$HOSTNAME" ]]; then

  if ! [[ -e /ccp/var/transit/metc/minnesota.gdb ]]; then
    echo 
    echo "Copying transit data"
    cp -f \
      /scratch/$masterhost/ccp/var/transit/metc/google_transit.zip \
      /scratch/$masterhost/ccp/var/transit/metc/minnesota.gdb \
      /scratch/$masterhost/ccp/var/transit/metc/minnesota.gtfsdb \
      /ccp/var/transit/metc
  fi

fi

# NOTE: prepare_ccp.sh will download google_transit.zip and make minnesota.g*.

echo 
echo "Fixing transit data owner and group"
sudo chown -R $targetuser /ccp/var/transit 
sudo chgrp -R $targetgroup /ccp/var/transit 

# Setup TileCache.

ccp_mkdir /ccp/var/tilecache-cache
# Skipping: ccp_mkdir /ccp/var/tilecache-cache/minnesota
# Skipping: ccp_mkdir /ccp/var/tilecache-cache/colorado

# Apache owns the tilecache cache.
sudo chown -R $httpd_user /ccp/var/tilecache-cache/
sudo chgrp -R $httpd_user /ccp/var/tilecache-cache/

# Make a few more dirs.

# The upgrade scripts grab shapefiles from here:
ccp_mkdir /ccp/var/shapefiles

# Svnserve serves from herein:
ccp_mkdir /ccp/var/subversion

# We can off-line bulky data to another drive
# so it doesn't live next with the source code.
ccp_mkdir /ccp/var/htdocs
if [[ $isprodserver -ne 0 ]]; then
  ccp_mkdir /ccp/var/htdocs/cycloplan_live/exports
  ccp_mkdir /ccp/var/htdocs/cycloplan_live/reports
else
  ccp_mkdir /ccp/var/htdocs/cp/exports
  ccp_mkdir /ccp/var/htdocs/cp/reports
fi

# *** Setup flex sdk

echo
echo "Fetching Flex SDK"

# Choose a version of Free Flex SDK.

# Flex 3.4, used circa 2006 to 2011.
flex_vers_name_34=""
flex_vers_wget_34=""
# Flex 3.4a, used circa 2012.
flex_vers_name_34a="flex_sdk_3.4.0.9271A"
flex_vers_wget_34a="http://fpdownload.adobe.com/pub/flex/sdk/builds/flex3/flex_sdk_3.4.0.9271A.zip"
# Flex 3.6a, Summer 2013.
flex_vers_name_36a="flex_sdk_3.6a"
#flex_vers_wget_36a="http://download.macromedia.com/pub/flex/sdk/flex_sdk_3.6a.zip"
flex_vers_wget_36a="https://fpdownload.adobe.com/pub/flex/sdk/builds/flex3/flex_sdk_3.6.0.16995A.zip"
# BUG nnnn/NEVER: Upgrade to Flex 4.6
flex_vers_name_46="flex_sdk_4.6"
flex_vers_wget_46="http://download.macromedia.com/pub/flex/sdk/flex_sdk_4.6.zip"

flex_vers_name=${flex_vers_name_36a}
flex_vers_wget=${flex_vers_wget_36a}

# Cannot combine -N -O, as in wget -N -O, so
if ! [[ -e /ccp/opt/.downloads/${flex_vers_name}.zip ]]; then
  wget -O/ccp/opt/.downloads/${flex_vers_name}.zip \
    ${flex_vers_wget}
fi
/bin/rm -rf /ccp/opt/${flex_vers_name}
echo "Inflating flex SDK zip"
# -q quietly (or -qq for quieterly)
unzip -q \
  /ccp/opt/.downloads/${flex_vers_name}.zip \
  -d /ccp/opt/${flex_vers_name}
# Make a link for the makefile.
/bin/rm -f /ccp/opt/flex
ln -s /ccp/opt/${flex_vers_name} /ccp/opt/flex

# There's something funky about the 3.6 file permissions.
# Thanks to
# http://www.unixlore.net/articles/speeding-up-bulk-file-operations.html
#  (Except [lb] finds the 2775 must come first.)
# FIXME/MAYBE: Should fixperms --public really just do this instead??
sudo find /ccp/opt/${flex_vers_name}/ -type d -print0 | xargs -0 chmod 2775
sudo find /ccp/opt/${flex_vers_name}/ -type f -print0 | xargs -0 chmod 664
# Make the Flex tools executable.
/bin/chmod 775 /ccp/opt/flex/bin/*

# *** Setup third-party Flex libraries.

DATE_EXT=`date +%Y.%m.%d`

ccp_mkdir /ccp/opt/flex_util

ccp_mkdir /ccp/opt/flex_util/purePDF
if ! [[ -d /ccp/opt/flex_util/purePDF/purePDF_$DATE_EXT ]]; then
  git clone https://github.com/sephiroth74/purePDF.git \
    /ccp/opt/flex_util/purePDF/purePDF_$DATE_EXT
fi
if ! [[ -e /ccp/opt/flex_util/purePDF/purePDF_0.77.20110116.zip ]]; then
  wget -O/ccp/opt/flex_util/purePDF/purePDF_0.77.20110116.zip \
    https://purepdf.googlecode.com/files/purePDF_0.77.20110116.zip
  unzip /ccp/opt/flex_util/purePDF/purePDF_0.77.20110116.zip \
    -d /ccp/opt/flex_util/purePDF/purePDF_0.77.20110116
  ln -s \
    /ccp/opt/flex_util/purePDF/purePDF_0.77.20110116/purePDF.swc \
    /ccp/opt/flex_util/purePDF/purePDF.swc
  ln -s \
    /ccp/opt/flex_util/purePDF/purePDF_0.77.20110116/purePDFont.swc \
    /ccp/opt/flex_util/purePDF/purePDFont.swc
fi
if ! [[ -e /ccp/opt/flex_util/purePDF/asdoc-output.zip ]]; then
  wget -O/ccp/opt/flex_util/purePDF/asdoc-output.zip \
    https://purepdf.googlecode.com/files/asdoc-output.zip
  unzip /ccp/opt/flex_util/purePDF/asdoc-output.zip \
    -d /ccp/opt/flex_util/purePDF/asdoc-output
fi

ccp_mkdir /ccp/opt/flex_util/as3corelib
if ! [[ -d /ccp/opt/flex_util/as3corelib/as3corelib_$DATE_EXT ]]; then
  git clone https://github.com/mikechambers/as3corelib.git \
    /ccp/opt/flex_util/as3corelib/as3corelib_$DATE_EXT
fi

ccp_mkdir /ccp/opt/flex_util/SWFExplorer
if ! [[ -e /ccp/opt/flex_util/SWFExplorer/SWFExplorer-0.7.1.zip ]]; then
  wget -O/ccp/opt/flex_util/SWFExplorer/SWFExplorer-0.7.1.zip \
    https://swfexplorer.googlecode.com/files/SWFExplorer%200.7.1.zip
fi

# *** Make it all public

echo
echo "Fixing perms on ccp/"

# 2013.06.10: MAYBE: Can we not do tilecache-cache, in the interest of time?
#             [lb] implement some for loops to do everything under /ccp except
#                  for /ccp/var/*tilecache*
#sudo ${script_absbase}/../../util/fixperms.pl --public /ccp/ \
#  2> /dev/null
cd /ccp
echo "in /ccp"
for ccp_dir in `ls | grep -v var`; do
  #echo $ccp_dir
  echo -n " on ${ccp_dir}... "
  sudo ${script_absbase}/../../util/fixperms.pl \
    --public /ccp/${ccp_dir}/ 
  #\
  #  2> /dev/null
  echo "ok"
done
echo "in /ccp/var"
cd /ccp/var
for var_dir in `ls | grep -v tilecache`; do
  #echo $var_dir
  echo -n " on ${var_dir}... "
  sudo ${script_absbase}/../../util/fixperms.pl \
    --public /ccp/${var_dir}/ \
    2> /dev/null
  echo "ok"
done
echo "skipped /ccp/var/*tilecache*"

# *** Restore location

cd $script_path

# *** All done!

echo
echo "Done setting up ccp/."

exit 0

