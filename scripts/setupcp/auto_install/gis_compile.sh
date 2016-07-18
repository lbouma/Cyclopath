#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script is derived from a Wiki page. The Wiki page is more
# descriptive and more likely to be up to date.
#
#  http://cyclopath.org/wiki/Tech:CcpV2/Install_Guide/Install_Cyclopath/Linux/GIS_Apps
#

# Usage: ./gis_compile.sh [MASTER_HOSTNAME] [TARGET_USERNAME]
#  (also called from ccp_install.sh)

# NOTE: This script calls sudo a few times, so you gotta be staff with lab-wide
# sudo to run this script.

echo
echo "Compiling GIS software!"

# *** Choke on error.

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

# Make a spot for the downloads...

#mkdir -p /ccp/opt/.downloads

# *** Use machine's GCC, not System's.

# On the CS network, MODULESHOME is set.
if [[ -n "$MODULESHOME" ]]; then
  # 2014.08.21: Rebuilding GDAL 1.10.1 because of ye olde error:
  #   /var/log/apache2/error.log || /ccp/opt/mapserver/mapserv:
  #   /usr/lib/libstdc++.so.6: version `GLIBCXX_3.4.14' not found
  #     (required by /ccp/opt/gdal-1.10.1/lib/libgdal.so.1)
  # I.e., I ran tilecache_update to generate tiles and gdal would
  # not load because it had been built using the network gcc, which
  # is a few versions ahead of what's installed on the machine (which
  # is what www-data user uses). See: `module list`: it says 4.5.2,
  # but if you run `/usr/bin/gcc` you'll see 4.4.3.
  . ${MODULESHOME}/init/sh
  module unload soft/gcc/4.5.2
fi

# *** Begin.

echo
echo "Preparing GIS software suite."

# Kick sudo. Prompt user now rather than later.
sudo -v

# FIXME: Make quieter?
#        > /dev/null 2>&1

# Own the opt directory while we work on it.
#sudo chown -R $USER /ccp/opt
#sudo chgrp -R $targetgroup /ccp/opt

# *** setuptools

# This is now installed by Systems (sudo aptitude install python-setuptools)

#echo
#echo "Installing Python setuptools"
#
#if [[ -n "`python --version |& grep 'Python 2.7'`" ]]; then
#  PYTHONNUMB=2.7
#  PYDOWNLOAD=http://pypi.python.org/packages/2.7/s/setuptools/setuptools-0.6c11-py2.7.egg#md5=fe1f997bc722265116870bc7919059ea
#elif [[ -n "`python --version |& grep 'Python 2.6'`" ]]; then
#  PYTHONNUMB=2.6
#  PYDOWNLOAD=http://pypi.python.org/packages/2.6/s/setuptools/setuptools-0.6c11-py2.6.egg#md5=bfa92100bd772d5a213eedd356d64086
#else
#  echo
#  echo "Unexpected Python version."
#  exit 1
#fi
#
#cd /ccp/opt/.downloads
#wget -N $PYDOWNLOAD
#sh setuptools-0.6c11-py$PYTHONNUMB.egg \
#  --prefix=/ccp/opt/usr

# *** GEOS

echo
echo "Installing GEOS"

# http://trac.osgeo.org/geos/

cd /ccp/opt/.downloads
wget -N http://download.osgeo.org/geos/geos-3.4.2.tar.bz2
/bin/rm -rf /ccp/opt/.downloads/geos-3.4.2
# 2013.10.13: Upgrading from 3.3.2, so make sure that's scrubbed.
/bin/rm -rf /ccp/opt/.downloads/geos-3.3.2
#
tar xvf geos-3.4.2.tar.bz2 \
  > /dev/null
cd geos-3.4.2
#
./configure --prefix=/ccp/opt/geos-3.4.2
make check
make install
#
#sudo chmod 2755 /ccp/opt/geos-3.4.2
chmod 2755 /ccp/opt/geos-3.4.2
${SCRIPT_DIR}/../../util/fixperms.pl --public /ccp/opt/geos-3.4.2/
#
/bin/rm -f /ccp/opt/geos
ln -s /ccp/opt/geos-3.4.2 /ccp/opt/geos
#
# See if we have to edit ld.so.conf or not.
if [[ "`cat /etc/ld.so.conf \
        | grep '/ccp/opt/geos/lib'`" ]]; then
  # No-op. Entry already exists.
  echo "Skipping ld.so.conf"
else
  RANDOM_NAME=/tmp/ccp_setup_ljklahsdf897asdfjklh234asd1234
  mkdir $RANDOM_NAME
  cp /etc/ld.so.conf $RANDOM_NAME/
  echo "/ccp/opt/geos/lib" >> $RANDOM_NAME/ld.so.conf
  sudo cp $RANDOM_NAME/ld.so.conf /etc/ld.so.conf
  # The tmp file is owned by the script runner but the sudo cp preserves
  # the original 664 root root perms.
  # Cleanup.
  /bin/rm -f $RANDOM_NAME/ld.so.conf
  rmdir $RANDOM_NAME
fi;
#
# Configure dynamic linker run-time bindings (reload ld.so.conf).
sudo ldconfig

sudo -v # keep sudo alive

# *** ODBC

echo
echo "Installing ODBC"

# http://www.unixodbc.org/

cd /ccp/opt/.downloads
wget -N ftp://ftp.unixodbc.org/pub/unixODBC/unixODBC-2.3.2.tar.gz
/bin/rm -rf /ccp/opt/.downloads/unixODBC-2.3.2
# 2013.10.13: Upgrading from 2.3.1, so make sure that's scrubbed.
/bin/rm -rf /ccp/opt/.downloads/unixODBC-2.3.1
#
tar xvf unixODBC-2.3.2.tar.gz \
  > /dev/null
cd unixODBC-2.3.2
#
./configure --prefix=/ccp/opt/unixODBC-2.3.2
make
make install

sudo -v # keep sudo alive

# FIXME: [lb] sees /export/scratch/ccp/opt/unixODBC-2.3.1/lib
#                  in /etc/ld.so.conf
#        1. Where's the code here that should add the path?
#           (and call sudo ldconfig)
#        2. Why is unixODBS-2.3.1 hard coded and not a symbolic path?
#        2013.10.31: I manually added the hard path...
#                     /ccp/opt/unixODBC-2.3.2/lib

# *** GDAL

echo
echo "Installing GDAL"

# http://gdal.org/

cd /ccp/opt/.downloads
#wget -N http://download.osgeo.org/gdal/gdal-1.5.1.tar.gz
#wget -N http://download.osgeo.org/gdal/gdal-1.7.3.tar.gz
#wget -N http://download.osgeo.org/gdal/gdal-1.9.0.tar.gz
# SYNC_ME: When you change GDAL versions, change the apache
#          confs' references to it (search /ccp/bin/ccpdev/private)
#          and update the /scripts/daily code that references its
#          /bin/ folder.
wget -N http://download.osgeo.org/gdal/1.10.1/gdal-1.10.1.tar.gz
# later: wget -N http://download.osgeo.org/gdal/CURRENT/gdal-1.11.0.tar.gz
# Remove old versions.
/bin/rm -rf /ccp/opt/.downloads/gdal-1.11.0
/bin/rm -rf /ccp/opt/.downloads/gdal-1.10.1
/bin/rm -rf /ccp/opt/.downloads/gdal-1.9.0
/bin/rm -rf /ccp/opt/.downloads/gdal-1.7.3
/bin/rm -rf /ccp/opt/.downloads/gdal-1.5.1
tar xvf gdal-1.10.1.tar.gz \
  > /dev/null
cd gdal-1.10.1
#
# Use --with-python so we get "from osgeo import osr"
./configure \
  --prefix=/ccp/opt/gdal-1.10.1 \
  --with-geos=/ccp/opt/geos-3.4.2/bin/geos-config \
  --with-odbc=/ccp/opt/unixODBC-2.3.2 \
  --with-pg=/usr/bin/pg_config \
  --with-python
# I [lb] couldn't find a configure option for the python library, so edit the
# cfg directly.
echo "[easy_install]
install_dir=/ccp/opt/usr/lib/$PYTHONVERS/site-packages
" >> /ccp/opt/.downloads/gdal-1.10.1/swig/python/setup.cfg
# Make sure the directory exists.
# FIXME: Should this be lib64? Or doesn't it matter?
mkdir -p /ccp/opt/usr/lib/$PYTHONVERS/site-packages
#
# NOTE: The make takes minutes to complete.
sudo -v # keep sudo alive
make
sudo -v # keep sudo alive
make install
#
#sudo chmod 2755 /ccp/opt/gdal-1.10.1
chmod 2755 /ccp/opt/gdal-1.10.1
# Set public for Apache.
${SCRIPT_DIR}/../../util/fixperms.pl --public /ccp/opt/gdal-1.10.1/
#
/bin/rm -f /ccp/opt/gdal
ln -s /ccp/opt/gdal-1.10.1 /ccp/opt/gdal
#
${SCRIPT_DIR}/../../util/fixperms.pl --public \
 /ccp/opt/usr/lib/$PYTHONVERS/site-packages/GDAL-1.10.1-${PYVERSABBR}-linux-x86_64.egg/
#
# See if we have to edit ld.so.conf or not. This permanently sets
# LD_LIBRARY_PATH, so if we run python from the command line or if Apache runs
# python, the gdal libs will always be loaded. The counterpart to this is its
# Python site-packages path, which we set in our .bashrc and in httpd.conf.
if [[ "`cat /etc/ld.so.conf | grep '/ccp/opt/gdal/lib'`" ]]; then
  # No-op. Entry already exists.
  echo "Skipping ld.so.conf"
else
  RANDOM_NAME=/tmp/ccp_setup_lj123gklj094dfjklh234asd1234
  mkdir $RANDOM_NAME
  cp /etc/ld.so.conf $RANDOM_NAME/
  echo "/ccp/opt/gdal/lib" >> $RANDOM_NAME/ld.so.conf
  sudo cp $RANDOM_NAME/ld.so.conf /etc/ld.so.conf
  # The tmp file is owned by the script runner but the sudo cp preserves
  # the original 664 root root perms.
  # Cleanup.
  /bin/rm -f $RANDOM_NAME/ld.so.conf
  rmdir $RANDOM_NAME
fi;
#
# Configure dynamic linker run-time bindings (reload ld.so.conf).
sudo ldconfig

sudo -v # keep sudo alive

# *** libxml2

echo
echo "Installing libxml2"

# http://xmlsoft.org/

cd /ccp/opt/.downloads
wget -N ftp://xmlsoft.org/libxml2/libxml2-2.9.1.tar.gz
# Remove versions we've used in the past.
/bin/rm -rf /ccp/opt/.downloads/libxml2-2.7.8
/bin/rm -rf /ccp/opt/.downloads/libxml2-2.9.1
#
tar -xvzf libxml2-2.9.1.tar.gz \
  > /dev/null
cd libxml2-2.9.1

# 2013.11.04: FIXME: We need to not install Python bindings,
#                    or we need to install them to a local folder,
#                    or we need to run sudo -- at least on Ubuntu.
#                    (EXPLAIN: Why isn't sudo necessary on Fedora? On Ubuntu,
#                    if you don't use --with-python={dir} or --without-python,
#                    you have to `sudo make install`.)
#./configure --prefix=/ccp/opt/libxml2-2.9.1
# FIXME: Test this/these:
#./configure --prefix=/ccp/opt/libxml2-2.9.1 --with-python=/ccp/opt/python
./configure --prefix=/ccp/opt/libxml2-2.9.1 --without-python
make
# 2013.11.04: I installed on runic using sudo, without using --with-python or
#             --without-python, so this bit of code may not work (I'm moving
#             on with statewide code and don't have time to fidget with this).
#sudo make install
make install

# 2013.11.04: [lb]: I ran `make install` recently on Fedora 14 and it worked
# just fine. And I've run it previously on Ubuntu 10.04, albeit with
# libxml2-2.7.8 and not -2.9.1. But I can't imagine these files wouldn't
# have been installed in the past. Maybe the configure command doesn't
# know about /ccp/opt/usr, our local (non-root) install directory...?
#
# Here's the complaint on `make install`:
#
#  /usr/bin/install: cannot create regular file
#   `/usr/lib/python2.6/dist-packages/drv_libxml2.py': Permission denied
#  /usr/bin/install: cannot create regular file
#   `/usr/lib/python2.6/dist-packages/libxml2.py': Permission denied
#  
# After `sudo make install`, these went to /usr/lib/python2.6/dist-packages:
#
#  -rw-r--r--  1 root root  338K 2013-11-04 10:56 libxml2.py
#  -rw-r--r--  1 root root   15K 2013-11-04 10:56 drv_libxml2.py
#  -rwxr-xr-x  1 root root 1002K 2013-11-04 10:56 libxml2mod.so*
#  -rwxr-xr-x  1 root root  1.1K 2013-11-04 10:56 libxml2mod.la*
#  -rw-r--r--  1 root root  1.5M 2013-11-04 10:56 libxml2mod.a
#
# and everything else went to /ccp/opt/libxml2-2.9.1.

#
#sudo chmod 2755 /ccp/opt/libxml2-2.9.1
chmod 2755 /ccp/opt/libxml2-2.9.1
#${SCRIPT_DIR}/../../util/fixperms.pl --public \
#  /ccp/opt/libxml2-2.9.1/

sudo -v # keep sudo alive

# *** PROJ.4 - Cartographic Projections Library

echo
echo "Installing PROJ.4"

# https://trac.osgeo.org/proj/

# Datum shift grids:
# proj-datumgrid-1.5.zip: US, Canadian, French and New Zealand datum shift
#   grids - unzip in the nad directory before configuring to add NAD27/NAD83
#   and NZGD49 datum conversion. 

cd /ccp/opt/.downloads
wget -N http://download.osgeo.org/proj/proj-4.8.0.tar.gz
/bin/rm -rf /ccp/opt/.downloads/proj-4.8.0
tar -xvzf proj-4.8.0.tar.gz \
  > /dev/null

cd /ccp/opt/.downloads
wget -N http://download.osgeo.org/proj/proj-datumgrid-1.5.zip
unzip proj-datumgrid-1.5.zip -d /ccp/opt/.downloads/proj-4.8.0/nad

# This is for MapServer.
#
# Edit Proj's epsg definitions and add an obscure Mercator projection.
#
# In /ccp/opt/proj-4.8.0/share/proj/epsg, you'll find similar defn's
# (they just jave an extra +wktext)
#
#   WGS 84 / Pseudo-Mercator
#     <3857> +proj=merc {same as our 900913 def} +wktext  +no_defs <>
#   Popular Visualisation CRS / Mercator (deprecated)
#     <3785> +proj=merc {same as our 900913 def} +wktext  +no_defs <>
#
echo "# [Cyclopath] Mercator projection (for MapServer)
<900913> +proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +no_defs <>" \
  >> /ccp/opt/.downloads/proj-4.8.0/nad/epsg

cd /ccp/opt/.downloads/proj-4.8.0
./configure --prefix=/ccp/opt/proj-4.8.0

# 2013.12.13: [lb] compiled proj4 just 4ine on runic and good, but ika
# is complaining,
#   jniproj.c:52:26: fatal error: org_proj4_PJ.h: No such file or directory
# There's a bug ticket suggesting including a differ header,
#   http://trac.osgeo.org/proj/ticket/153
# Doesn't work: ln -s src/org_proj4_Projections.h src/org_proj4_PJ.h
# But copying the file seems to work...
# 2013.12.13: [lb] is not going to check this in:
#             on pluto I don't have this file, either,
#             and proj4 compiled just fine... so, well,
#             figure this out later.
if false; then
  if [[ ! -e src/org_proj4_PJ.h ]]; then
    cp src/org_proj4_Projections.h src/org_proj4_PJ.h
  fi
fi

make
make install

#sudo chmod 2755 /ccp/opt/proj-4.8.0
chmod 2755 /ccp/opt/proj-4.8.0
#${SCRIPT_DIR}/../../util/fixperms.pl --public \
#  /ccp/opt/proj-4.8.0/

# Make sure everyone uses the new binary and library, and not the system ones.
if [[ "`cat /etc/ld.so.conf \
        | grep '/ccp/opt/proj-4.8.0/lib'`" ]]; then
  # No-op. Entry already exists.
  echo "Skipping ld.so.conf"
else
  RANDOM_NAME=/tmp/ccp_setup_lsadfas09sd0f9sdflj234b4
  mkdir $RANDOM_NAME
  cp /etc/ld.so.conf $RANDOM_NAME/
  echo "/ccp/opt/proj-4.8.0/lib" >> $RANDOM_NAME/ld.so.conf
  sudo cp $RANDOM_NAME/ld.so.conf /etc/ld.so.conf
  # The tmp file is owned by the script runner but the sudo cp preserves
  # the original 664 root root perms.
  # Cleanup.
  /bin/rm -f $RANDOM_NAME/ld.so.conf
  rmdir $RANDOM_NAME
fi;
#
# Configure dynamic linker run-time bindings (reload ld.so.conf).
sudo ldconfig

sudo -v # keep sudo alive

# User manuals: We shouldn't need this, since we only use libraries that use
# this library.
# 
# The main users manual for PROJ; however, this dates from PROJ.3.
#  ftp://ftp.remotesensing.org/proj/OF90-284.pdf
# The PROJ.4 addendum.
#  ftp://ftp.remotesensing.org/proj/proj.4.3.pdf
# Lots of math.
#  ftp://ftp.remotesensing.org/proj/proj.4.3.I2.pdf
#  ftp://ftp.remotesensing.org/proj/swiss.pdf

# *** json-c

echo
echo "Installing json-c"

# https://github.com/json-c/json-c

cd /ccp/opt/.downloads
wget -N https://github.com/json-c/json-c/archive/json-c-0.11-20130402.tar.gz

# 2014.01.17: I guess the json-c peeps fixed the name problem
#mv json-c-0.11-20130402 json-c-0.11-20130402.tar.gz
if [[ -e json-c-0.11-20130402 ]]; then
  mv json-c-0.11-20130402 json-c-0.11-20130402.tar.gz
fi

# Remove old archives.
/bin/rm -rf /ccp/opt/.downloads/json-c-json-c-0.11-20130402
#
tar -xvzf json-c-0.11-20130402.tar.gz \
  > /dev/null
cd json-c-json-c-0.11-20130402
#
./configure --prefix=/ccp/opt/json-c-json-c-0.11-20130402
make
make install

#sudo chmod 2755 /ccp/opt/json-c-json-c-0.11-20130402
chmod 2755 /ccp/opt/json-c-json-c-0.11-20130402
#${SCRIPT_DIR}/../../util/fixperms.pl --public \
#  /ccp/opt/json-c-0.11-20130402/

sudo -v # keep sudo alive

# *** PostGIS

echo
echo "Installing PostGIS"

#PGIS_VERS=postgis-1.5.4
# FIXME: Test postgis-2.0.0...
#PGIS_VERS=postgis-2.0.0
# NOTE: PostGIS 2.0 is the last major version to support psql 8.4.
PGIS_VERS=postgis-2.0.4
# BUG nnnn: Upgrade to PostgresSQL 9.x and install PostGIS 2.1.0.
#  configure: error: PostGIS requires PostgreSQL >= 9.0
# PGIS_VERS=postgis-2.1.0

cd /ccp/opt/.downloads
#wget -N http://postgis.refractions.net/download/$PGIS_VERS.tar.gz
wget -N http://download.osgeo.org/postgis/source/$PGIS_VERS.tar.gz
/bin/rm -rf /ccp/opt/.downloads/$PGIS_VERS
# Remove old versions that may have been installed on this machine.
/bin/rm -rf /ccp/opt/.downloads/postgis-1.5.4
/bin/rm -rf /ccp/opt/.downloads/postgis-2.0.0
/bin/rm -rf /ccp/opt/.downloads/postgis-2.0.4
/bin/rm -rf /ccp/opt/.downloads/postgis-2.1.0
#
tar xvf $PGIS_VERS.tar.gz \
  > /dev/null
cd $PGIS_VERS
#
# 2013.10.31: [lb] added --with-projdir and --with-gdalconfig.
# FIXME: What about json-c? Or whatever: it's optional, anyway
#        (it's only used if you call PostGIS's ST_GeomFromGeoJson).
./configure \
  --prefix=/ccp/opt/$PGIS_VERS \
  --with-geosconfig=/ccp/opt/geos-3.4.2/bin/geos-config \
  --with-pgconfig=/usr/bin/pg_config \
  --with-xml2config=/ccp/opt/libxml2-2.9.1/bin/xml2-config \
  --with-projdir=/ccp/opt/proj-4.8.0 \
  --with-gdalconfig=/ccp/opt/gdal/bin/gdal-config
#
make
#
sudo make install

# FIXME: Why is prefix being ignored?
#sudo chmod 2775 /ccp/opt/$PGIS_VERS
##${SCRIPT_DIR}/../../util/fixperms.pl --public \
##  /ccp/opt/$PGIS_VERS/
#${SCRIPT_DIR}/../../util/fixperms.pl --public \
#  /ccp/opt/.downloads/$PGIS_VERS

# This is db_load. So we want the source code and not the library-containing
# (.so) folder.
/bin/rm -f /ccp/opt/postgis
#ln -s /ccp/opt/.downloads/$PGIS_VERS/postgis /ccp/opt/postgis
ln -s /ccp/opt/.downloads/$PGIS_VERS /ccp/opt/postgis

sudo -v # keep sudo alive

# *** Xerces

# 2014.01.17: This is not installed on Debian.
# "Xerces-C++ makes it easy to give your application
#  the ability to read and write XML data."
if [[ "`cat /proc/version | grep Red\ Hat`" ]]; then

  cd /ccp/opt/.downloads
  wget -N http://www.motorlogy.com/apache//xerces/c/2/sources/xerces-c-src_2_8_0.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/xerces-c-src_2_8_0
  tar xvf xerces-c-src_2_8_0.tar.gz \
    > /dev/null
  cd xerces-c-src_2_8_0

  export XERCESCROOT=/ccp/opt/.downloads/xerces-c-src_2_8_0
  cd src/xercesc
  ./runConfigure -plinux -cgcc -xg++ -minmem -nsocket -tnative -rpthread
  make

fi

# *** MapServer

echo
echo "Installing MapServer"

# NOTE: For MapServer 5 to work with PostGIS 2, we need to edit a source file.
# http://postgis.17.x6.nabble.com/Compatibility-between-postgis-2-amp-mapserver-td3599085.html
# "Everyting's in "mappostgis.c", there are just four lines to edit (at
#  least in MS 5.6.5) containing:
#   GeomFromText -> ST_GeomFromText
#   AsBinary -> ST_AsBinary
#   force_collection -> ST_Force_Collection
#   force_2d -> ST_Force_2D"
#
#  gvim /ccp/opt/.downloads/mapserver-5.6.9/mappostgis.c
#  # Edit the file.
#  mkdir -p ${SCRIPT_DIR}/../ao_templates/common/ccp/opt/.downloads/mapserver-5.6.9
#  cp /ccp/opt/.downloads/mapserver-5.6.9/mappostgis.c \
#   ${SCRIPT_DIR}/../ao_templates/common/ccp/opt/.downloads/mapserver-5.6.9

# FIXME: Compiling MapServer on Fedora is tricky enough, but trying to run it
# and seeing it complain about a bunch of missing old-versioned libraries is
# another.
#   For now, just sudo yum install mapserver, ug.
if [[ "`cat /proc/version | grep Ubuntu`" ]]; then

  # Ubuntu 10.04 doesn't care, but Ubuntu 11.04 is particular about -ledit.
  # I.e., g++ fails on: /usr/bin/ld: cannot find -ledit
  # NOTE: The following is necessary w/out 'sudo aptitude install libedit-dev'
  #if [[ -n "`cat /etc/issue | grep '^Ubuntu 11.04'`" ]]; then
  #  cd /usr/lib
  #  if ! [[ -e /usr/lib/libedit.so ]]; then
  #    sudo ln -s libedit.so.2.11 libedit.so
  #  fi
  #fi

  # "configure: error: Could not find gd.h or libgd.a/libgd.so in /usr/local.
  #  Make sure GD 2.0.16 or higher is compiled before calling configure. You
  #  may also get this error if you didn't specify the appropriate location
  #  for one of GD's dependencies (freetype, libpng, libjpeg or libiconv)."

  if [[ "`uname -m | grep x86_64`" ]]; then
    : # A 64-bit machine.
  else
    # else, a 32-bit machine.
    # 2013.06.10: From bad.cs, which is 32-bit: "configure: error: ...".
    # [lb] tried --with-gd=/usr/lib/x86_64-linux-gnu and LDFLAGS= but
    # neither worked. Oh, well, who cares about Mapserver on 32-bit Linux?
    # Oh, wait, we can cheat and make the links...
    cd /usr/lib
    if ! [[ -e /usr/lib/libgd.a ]]; then
      sudo ln -s x86_64-linux-gnu/libgd.a libgd.a
    fi
    if ! [[ -e /usr/lib/libgd.so ]]; then
      sudo ln -s x86_64-linux-gnu/libgd.so libgd.so
    fi
  fi

  cd /ccp/opt/.downloads
  # DEVS: If you upgrade to MapServer 6.x, you can probably remove the
  #       mappostgis.c fix. At least check the new source file.
  #wget -N http://download.osgeo.org/mapserver/mapserver-5.6.6.tar.gz
  #wget -N http://download.osgeo.org/mapserver/mapserver-5.6.8.tar.gz
  wget -N http://download.osgeo.org/mapserver/mapserver-5.6.9.tar.gz

  /bin/rm -rf /ccp/opt/.downloads/mapserver-5.6.9
  tar xvf mapserver-5.6.9.tar.gz \
    > /dev/null
  cd mapserver-5.6.9

  # Fix the source file we mentioned earlier.
  /bin/cp -f \
    ${SCRIPT_DIR}/../ao_templates/common/ccp/opt/.downloads/mapserver-5.6.9/mappostgis.c \
    /ccp/opt/.downloads/mapserver-5.6.9

  # Avoid this error:
  # configure: error: Could not find gd.h or libgd.a/libgd.so in 
  # /usr/include.  Make sure GD 2.0.16 or higher is compiled before
  # calling configure. You may also get this error if you did not
  # specify the appropriate location for one of GDs dependencies
  # (freetype, libpng, libjpeg or libiconv).
  cd /usr/include
  sudo ln -s /usr/lib/x86_64-linux-gnu/libgd.a libgd.a
  sudo ln -s /usr/lib/x86_64-linux-gnu/libgd.so libgd.so

  #
  # NOTE: On Ubuntu, /usr/lib/postgresql/8.4/bin/pg_config is same as
  #       /usr/bin/pg_config. On Fedora, only the latter exists
  cd /ccp/opt/.downloads/mapserver-5.6.9
  ./configure                                                 \
    --prefix=/ccp/opt/mapserver-5.6.9                         \
    --with-geos=/ccp/opt/geos-3.4.2/bin/geos-config           \
    --with-gdal=/ccp/opt/gdal-1.10.1/bin/gdal-config          \
    --with-postgis=/usr/bin/pg_config                         \
    --with-proj                                               \
    --with-xml2-config=/ccp/opt/libxml2-2.9.1/bin/xml2-config \
    --with-gd=/usr/include
  # --with-gd
  # --with-postgis=/usr/lib/postgresql/8.4/bin/pg_config

  # WTF. On Fedora, complains: /usr/bin/ld: cannot find -lpgport
  #      because Fedora doesn't want you to link against static libs.
  #      If you dig into the src rpm for Fedora 14's mapserver, per
  #       http://linux.derkeiler.com/Mailing-Lists/Fedora/2011-02/msg01038.html
  #      you'll see that they just omit that link
  # FIXME: Does this mean MapServer doesn't support PostGIS? Probably. And we
  #        probably don't care, since we don't use the two together.
  if [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
    # echo Red Hat!
    for makefile in `find . -type f -name 'Makefile'`; do
      sed -i 's|-lpgport||g' $makefile
    done
  fi

  # Make MapServer on Mint 16!
  LD_RUN_PATH=/ccp/opt/gdal-1.10.1/lib:/ccp/opt/unixODBC-2.3.2/lib make

  # FIXME: Fedora needs the lib path setup, even though we edited ldconfig...
  # sudo yum install hdf5-devel
  #LD_LIBRARY_PATH=/ccp/opt/gdal-1.10.1/lib:/ccp/opt/unixODBC-2.3.2/lib:/ccp/opt/.downloads/xerces-c-src_2_8_0/lib ../../mapserver/mapserv

  # Make a link for httpd.conf.
  /bin/rm -f /ccp/opt/mapserver
  ln -s /ccp/opt/.downloads/mapserver-5.6.9 \
    /ccp/opt/mapserver

  sudo -v # keep sudo alive

fi

# NOTE: This is for MapServer.
#
# Update /usr/share/proj/epsg so it supports Mercator.
#
# Doing sudo -s kinda works but leaves us at a root prompt. Weird.
# sudo -s "echo '# [Cyclopath] Mercator projection (for MapServer)
#   <900913> +proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +no_defs <>
#   ' >> /usr/share/proj/epsg"
#
# DEPRECATED: See above, where we install PROJ.4. It's no longer necessary to
#             edit /usr/share/proj/epsg since we've updated ld.so.conf to use
#             the new library...
#  if [[ "`cat /usr/share/proj/epsg \
#          | grep '\[Cyclopath\] Mercator projection'`" ]]; then
#    # The file is already updated.
#    echo "Skipping /usr/share/proj/epsg"
#  else
#    /bin/cp -f /usr/share/proj/epsg /tmp/proj_epsg
#    echo "# [Cyclopath] Mercator projection (for MapServer)
#  <900913> +proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +no_defs <>" \
#      >> /tmp/proj_epsg
#    sudo mv -f /tmp/proj_epsg /usr/share/proj/epsg
#    sudo chown root /usr/share/proj/epsg
#    sudo chgrp root /usr/share/proj/epsg
#    sudo chmod 644 /usr/share/proj/epsg
#  fi

# *** TileCache

echo
echo "Installing TileCache"

cd /ccp/opt/.downloads
wget -N http://tilecache.org/tilecache-2.11.tar.gz
/bin/rm -rf /ccp/opt/.downloads/tilecache-2.11
tar xvf tilecache-2.11.tar.gz \
  > /dev/null
cd tilecache-2.11
#
#sudo chmod 2775 /ccp/opt/.downloads/tilecache-2.11
chmod 2775 /ccp/opt/.downloads/tilecache-2.11
#${SCRIPT_DIR}/../../util/fixperms.pl --public \
#  /ccp/opt/.downloads/tilecache-2.11/
#
# Make a link for httpd.conf.
/bin/rm -f /ccp/opt/tilecache
ln -s /ccp/opt/.downloads/tilecache-2.11 \
  /ccp/opt/tilecache
#
# 2013.01.14: The TileCache config got moved to /ccp/var/ when the
# check_cache_now, gen_tilecache_cfg, and make_mapfile scripts were writ.
mv /ccp/opt/.downloads/tilecache-2.11/tilecache.cfg \
   /ccp/opt/.downloads/tilecache-2.11/tilecache.cfg-ORIG
#
# ln -s /ccp/dev/cp/mapserver/tilecache.cfg \
#       /ccp/opt/.downloads/tilecache-2.11/tilecache.cfg
# NOTE: The target might not exist. See check_cache_now cron job.
# NOTE: To allow multiple instances with difference tilecache.cfg files,
#       use --config= when you call tilecache_seed.py.
# 2013.04.21: See mapserver/check_cache_now.sh and related. We'll deal
#             with tilecache on an installation-by-installation basis.
# ln -s /ccp/var/tilecache-cache/tilecache.cfg \
#       /ccp/opt/.downloads/tilecache-2.11/tilecache.cfg

# FIXME: Because of bg sudo -v we don't need this anymore... right?
sudo -v # keep sudo alive

# *** Graphserver

echo
echo "Installing spatialindex"

cd /ccp/opt/.downloads
wget -N http://download.osgeo.org/libspatialindex/spatialindex-src-1.8.1.tar.gz
# Remove old downloads.
/bin/rm -rf /ccp/opt/.downloads/spatialindex-src-1.6.1
/bin/rm -rf /ccp/opt/.downloads/spatialindex-src-1.8.1
#
tar -xvzf spatialindex-src-1.8.1.tar.gz
cd spatialindex-src-1.8.1
./configure --prefix=/ccp/opt/usr
make
make install

echo
echo "Installing RTree"

#mkdir -p /ccp/opt/usr/lib/python2.5/site-packages
#mkdir -p /ccp/opt/usr/lib/python2.6/site-packages
#mkdir -p /ccp/opt/usr/lib/python2.7/site-packages

# FIXME:
#landonb@huffy:spatialindex-src-1.8.1$ easy_install --prefix=/ccp/opt/usr RTree
#Searching for RTree
#Reading http://pypi.python.org/simple/RTree/
#Reading http://trac.gispython.org/projects/PCL/wiki/ArrTree
#Reading http://trac.gispython.org/lab/wiki/Rtree
#Reading http://toblerity.github.com/rtree/
#Reading http://trac.gispython.org/projects/PCL/wiki/Rtree
#Reading http://trac.gispython.org/projects/PCL/wiki/RTree
#Best match: Rtree 0.7.0
#Downloading http://pypi.python.org/packages/source/R/Rtree/Rtree-0.7.0.tar.gz#md5=84e75e5a9fdf7bd092435588be9084ac
#Processing Rtree-0.7.0.tar.gz
#Running Rtree-0.7.0/setup.py -q bdist_egg --dist-dir /tmp/easy_install-Oq3Ton/Rtree-0.7.0/egg-dist-tmp-kBHLW4
#error: None

#LD_LIBRARY_PATH=/ccp/opt/usr/lib easy_install --prefix=/ccp/opt/usr RTree

# I think this works:
cd /ccp/opt/.downloads
wget -N http://pypi.python.org/packages/source/R/Rtree/Rtree-0.7.0.tar.gz#md5=84e75e5a9fdf7bd092435588be9084ac
/bin/rm -rf /ccp/opt/.downloads/Rtree-0.7.0
tar xvf Rtree-0.7.0.tar.gz
cd Rtree-0.7.0
echo "[easy_install]
install_dir=/ccp/opt/usr/lib/$PYTHONVERS/site-packages
" >> /ccp/opt/.downloads/Rtree-0.7.0/setup.cfg
LD_LIBRARY_PATH=/ccp/opt/usr/lib python setup.py build
LD_LIBRARY_PATH=/ccp/opt/usr/lib python setup.py install

# *** Simplejson

echo
echo "Installing simplejson"

# FIXME: There's a 2.2.1 and 2.3.3 of simplejson
cd /ccp/opt/.downloads
# wget -N http://pypi.python.org/packages/source/s/simplejson/simplejson-2.1.6.tar.gz#md5=2f8351f6e6fe7ef25744805dfa56c0d5
# Hmm, certificate problems.
# wget -N https://pypi.python.org/packages/source/s/simplejson/simplejson-3.3.1.tar.gz
#   ERROR: certificate common name “*.a.ssl.fastly.net” doesn't match requested host name “pypi.python.org”.
#   To connect to pypi.python.org insecurely, use '--no-check-certificate'.
# Is this safe?:
wget --no-check-certificate -N https://pypi.python.org/packages/source/s/simplejson/simplejson-3.3.1.tar.gz

# Remove old downloads.
/bin/rm -rf /ccp/opt/.downloads/simplejson-2.1.6
/bin/rm -rf /ccp/opt/.downloads/simplejson-3.3.1
#
tar xvzf simplejson-3.3.1.tar.gz
cd simplejson-3.3.1

# 2012.08.22: NOTE: [ln] tried installing on itamae, but itamae is an old
#                   Ubuntu machine with earlier versions of software, so
#                   things didn't work out well...
#
# running install
# error: can't create or remove files in install directory
#
# The following error occurred while trying to add or remove files in the
# installation directory:
#
#   [Errno 2] No such file or directory:
#   '/ccp/opt/usr/lib/python/test-easy-install-18584.write-test'
#
# The installation directory you specified (via --install-dir, --prefix, or
# the distutils default setting) was:
#
#   /ccp/opt/usr/lib/python/
#
# This directory does not currently exist.  Please create it and try again, or
# choose a different installation directory (using the -d or --install-dir
# option).
#
# DON'T_BOTHER: We shouldn't worry about itamae, but if we cared, we might have
#               to create the library directory...
# mkdir /ccp/opt/usr/lib/python/
# chmod 2775 /ccp/opt/usr/lib/python/

python setup.py install --home=/ccp/opt/usr

# *** servable

echo
echo "Installing servable"

cd /ccp/opt/.downloads
if [[ -d /ccp/opt/.downloads/servable_trunk ]]; then
  cd servable_trunk
  svn update
else
  svn checkout http://servable.googlecode.com/svn/trunk/ servable_trunk
  cd servable_trunk
fi

# Setup fails if this directory isn't available, so make sure it is.
mkdir -p /ccp/opt/usr/lib/python/

# 2012.08.22: Another reason to not worry about itamae, which crokes here:
#  File "/usr/lib/python2.5/site-packages/setuptools/command/sdist.py", line 98, in entries_finder
#    log.warn("unrecognized .svn/entries format in %s", dirname)
# NameError: global name 'log' is not defined

python setup.py install --home=/ccp/opt/usr

# *** pytz

echo
echo "Installing pytz: World Timezone Definitions for Python"

# FIXME: 2012.08.21: Latest is 25-Jul-2012: pytz-2012d-py2.5.egg

# NOTE: Ubuntu 8.04 does not support the |& syntax... and I'm too lazy to
# figure out another way (other than writing to a file and then reading
# from that file).
if [[ -n "`cat /etc/issue | grep '^Ubuntu 8.04'`" ]]; then
  PYTHONNUMB=2.5
  #PYDOWNLOAD=http://pypi.python.org/packages/2.5/p/pytz/pytz-2011g-py2.5.egg
  PYDOWNLOAD=https://pypi.python.org/packages/2.5/p/pytz/pytz-2013.7-py2.5.egg#md5=a647a7d0aeb3ed243c8974f73a01c42b
elif [[ -n "`python --version |& grep 'Python 2.7'`" ]]; then
  PYTHONNUMB=2.7
  #PYDOWNLOAD=http://pypi.python.org/packages/2.7/p/pytz/pytz-2011g-py2.7.egg#md5=96d8b4b7fe225134376d42c195b4e0cf
  PYDOWNLOAD=https://pypi.python.org/packages/2.7/p/pytz/pytz-2013.7-py2.7.egg#md5=99d1e2b798f022e1d011ac6831c767f5
elif [[ -n "`python --version |& grep 'Python 2.6'`" ]]; then
  PYTHONNUMB=2.6
  #PYDOWNLOAD=http://pypi.python.org/packages/2.6/p/pytz/pytz-2011g-py2.6.egg#md5=d5b33397f1b3350e36e226cff1844d7c
  PYDOWNLOAD=https://pypi.python.org/packages/2.6/p/pytz/pytz-2013.7-py2.6.egg#md5=bfbcad5e23e8647e965b6d3ca28f9f33
else
  echo
  echo "Unexpected Python version."
  exit 1
fi

cd /ccp/opt/.downloads
# See above: certificate problem.
#wget -N $PYDOWNLOAD
wget --no-check-certificate -N $PYDOWNLOAD
# 2013.01.24: You might have a problem if there are multiple easy_install
# binaries installed: you might want to always use the one for the right
# version of Python.
#easy_install --prefix=/ccp/opt/usr \
#easy_install-${PYTHONNUMB} --prefix=/ccp/opt/usr \
#  pytz-2011g-py${PYTHONNUMB}.egg
easy_install-${PYTHONNUMB} --prefix=/ccp/opt/usr \
  pytz-2013.7-py${PYTHONNUMB}.egg

# Skipping: Python nose for itamae
#
# echo
# echo "Installing python-nose"
#
# # 2012.08.23: This is necessary for itamae, which runs Ubuntu 8.04 and an old
# # version of nose.
# cd /ccp/opt/.downloads
# wget -N http://pypi.python.org/packages/source/n/nose/nose-0.11.4.tar.gz#md5=230a3dfc965594a06ce2d63def9f0d98
# /bin/rm -rf /ccp/opt/.downloads/nose-0.11.4
# tar xvzf nose-0.11.4.tar.gz
# cd nose-0.11.4
# # Can we install this locally, or not? Graphserver is just downloaded, not
# # compiled, so it probably won't find nose unless we can tell Graphserver its
# # # path. Until then, sudo seems simpler.
# # MAYBE: python setup.py install --home=/ccp/opt/usr
# sudo python setup.py install

# *** Graphserver

echo
echo "Installing Graphserver"

cd /ccp/opt/.downloads
# FIXME: Use 'git clone'? What's the update command? Or just stick to static
# version? But what about recent bugfixes? Or maybe there are none...
#git https://github.com/graphserver/graphserver.git
if ! [[ -e graphserver_1.0.0.tar.gz ]]; then
  wget -Ographserver_1.0.0.tar.gz \
    http://github.com/graphserver/graphserver/tarball/14102010
  # 2012.08.22: On itamae, had to run:
  # wget --no-check-certificate -Ographserver_1.0.0.tar.gz \
  #   http://github.com/graphserver/graphserver/tarball/14102010
fi

#If you get a certificate verification error, e.g.,
#
# ERROR: Certificate verification error for github.com: unable to get local issuer certificate
#
#Run this command instead:
#
# wget --no-check-certificate -O graphserver_1.0.0.tar.gz http://github.com/graphserver/graphserver/tarball/14102010

/bin/rm -rf graphserver_1.0.0
tar xvzf graphserver_1.0.0.tar.gz
mv graphserver-graphserver-e999ef5 graphserver_1.0.0

cd /ccp/opt/.downloads
DATE_EXT=`date +%Y.%m.%d`
if ! [[ -d graphserver_$DATE_EXT ]]; then
  git clone git://github.com/graphserver/graphserver.git graphserver_$DATE_EXT
fi

#Compare the two.
#
# #meld graphserver_1.0.0 graphserver_`date +%Y.%m.%d` &
# meld graphserver_1.0.0 graphserver_$DATE_EXT &
#
#If the trunk looks good, make it The One.

/bin/rm -f /ccp/opt/graphserver
# FIXME: Do we need to link?
#ln -s /ccp/opt/.downloads/graphserver_$DATE_EXT \
#  /ccp/opt/graphserver

#Install Graphserver to, e.g., /usr/lib/python2.7/site-packages/.

#cd /ccp/opt/graphserver/pygs
cd /ccp/opt/.downloads/graphserver_$DATE_EXT/pygs
python setup.py install --home=/ccp/opt/usr

# *** Yaml

# NOTE: Yaml is accessible from user Python sessions, but not from www-data.

echo
echo "Installing libyaml"

cd /ccp/opt/.downloads
wget -N http://pyyaml.org/download/libyaml/yaml-0.1.4.tar.gz
/bin/rm -rf /ccp/opt/.downloads/yaml-0.1.4
tar -xvzf yaml-0.1.4.tar.gz
cd yaml-0.1.4

./configure --prefix=/ccp/opt/yaml-0.1.4
make
make install

echo
echo "Installing yaml"

cd /ccp/opt/.downloads
wget -N http://pyyaml.org/download/pyyaml/PyYAML-3.10.tar.gz
/bin/rm -rf /ccp/opt/.downloads/PyYAML-3.10
tar -xvzf PyYAML-3.10.tar.gz
cd PyYAML-3.10

python setup.py install --home=/ccp/opt/usr
# NOTE: test fails on Fedora but the module appears to be installed.
#   pee@pluto:PyYAML-3.10$ python setup.py test
#   running test
#   running build_py
#   running build_ext
#   ..............EEEEEEEEEEEEEEEEEEEEEEEEEEEEE
#   ===========================================================================
#   test_c_emitter(tests/data/emit-block-scalar-in-simple-key-context-bug.data,
#     tests/data/emit-block-scalar-in-simple-key-context-bug.canonical): ERROR
#   Traceback (most recent call last):
#     File "tests/lib/test_appliance.py", line 64, in execute
#     File "tests/lib/test_yaml_ext.py", line 230, in test_c_emitter
#     File "tests/lib/test_yaml_ext.py", line 199, in _compare_emitters
#     File "build/lib.linux-x86_64-2.7/yaml/__init__.py", line 121, in emit
#   AttributeError: 'CDumper' object has no attribute 'dispose'
#   ---------------------------------------------------------------------------
#   tests/data/emit-block-scalar-in-simple-key-context-bug.data:
#   error: tests/data/emit-block-scalar-in-simple-key-context-bug.data:
#           Too many open files
if [[ -z "${FEDORAVERSABBR}" ]]; then
  # This is a not-Fedora.
  python setup.py test
fi

# *** OAuth library

# Okay, this isn't a GIS application, so maybe this setup code doesn't belong
# in gis_compile.sh, but this script is also the auto_install script with the
# most third-party application installations, so maybe this is the right file.

echo
echo "Installing Python-OAuth2"

# Needed by Python-Twitter.

cd /ccp/opt/.downloads
if ! [[ -d /ccp/opt/.downloads/python-oauth2 ]]; then
  git clone https://github.com/simplegeo/python-oauth2.git
  cd /ccp/opt/.downloads/python-oauth2
else
  cd /ccp/opt/.downloads/python-oauth2
  git pull --rebase
fi

python setup.py build
python setup.py install --prefix=/ccp/opt/usr

# NOTE: You can test by firing up python and trying:
#         import oauth2

# This application for installed for alleyoop.
#
# 2013.05.08: Alleyoop also needs simplejson, which was already installed
#             (import simplejson), and Httplib2 (import httplib2), which
#             seems to have been installed by Systems or is maybe included
#             in the distros (since [lb] found it installed on both Ubuntu
#             and Fedora).
#
# References:
#   https://github.com/simplegeo/python-oauth2
#   http://code.google.com/p/httplib2/
#   https://pypi.python.org/pypi/simplejson
#     http://simplejson.readthedocs.org/en/latest/

# *** Python-Twitter library

echo
echo "Installing Python-Twitter"

# References:
#   https://github.com/bear/python-twitter

cd /ccp/opt/.downloads
if ! [[ -d /ccp/opt/.downloads/python-twitter ]]; then
  git clone https://github.com/bear/python-twitter.git
  cd /ccp/opt/.downloads/python-twitter
else
  cd /ccp/opt/.downloads/python-twitter
  git pull --rebase
fi

python setup.py build
python setup.py install --prefix=/ccp/opt/usr

# You can test via:
#   python twitter_test.py
#
# You can read docs:
#
#   pydoc twitter.Status
#   pydoc twitter.User
#   pydoc twitter.DirectMessage

# *** NetworkX

# Needed by alleyoop for simple TSP homebrew (travelling salesperson problem).

# http://networkx.lanl.gov

if [[ -n "`python --version |& grep 'Python 2.7'`" ]]; then
  PYTHONNUMB=2.7
  #PYDOWNLOAD=https://pypi.python.org/packages/2.7/n/networkx/networkx-1.7-py2.7.egg#md5=1d4c59f1e894f39f8928be8718905969
  PYDOWNLOAD=https://pypi.python.org/packages/2.7/n/networkx/networkx-1.8.1-py2.7.egg#md5=ba29a8e2528114367b4fd9c4badb138b
elif [[ -n "`python --version |& grep 'Python 2.6'`" ]]; then
  PYTHONNUMB=2.6
  #PYDOWNLOAD=https://pypi.python.org/packages/2.6/n/networkx/networkx-1.7-py2.6.egg#md5=3305b39272b5b62e6f7be0022d85f14a
  PYDOWNLOAD=https://pypi.python.org/packages/2.6/n/networkx/networkx-1.8.1-py2.6.egg#md5=1399cc1cf4509201453ca12ddaef8be8
else
  echo
  echo "Unexpected Python version."
  exit 1
fi

cd /ccp/opt/.downloads
# 2013.06.25: FIXME: What's this all about?:
#    pee@pluto:.downloads$ wget -N https://pypi.python.org/packages/2.7/n
#                                   /networkx/networkx-1.7-py2.7.egg
#    --2013-06-25 22:12:26--  https://pypi.python.org/packages/2.7/n
#                                   /networkx/networkx-1.7-py2.7.egg
#    Resolving pypi.python.org... 199.27.73.129, 199.27.73.192
#    Connecting to pypi.python.org|199.27.73.129|:443... connected.
#    ERROR: certificate common name “*.a.ssl.fastly.net” doesn't match
#       requested host name “pypi.python.org”.
#    To connect to pypi.python.org insecurely, use '--no-check-certificate'.
#wget -N $PYDOWNLOAD
wget --no-check-certificate -N $PYDOWNLOAD
#easy_install-${PYTHONNUMB} --prefix=/ccp/opt/usr \
#  networkx-1.7-py${PYTHONNUMB}.egg
easy_install-${PYTHONNUMB} --prefix=/ccp/opt/usr \
  networkx-1.8.1-py${PYTHONNUMB}.egg

# Apply the patch for the Cyclopath p3 planner:
# change astar to be able to call edge weight fcn.
patch \
  /ccp/opt/usr/lib/$PYTHONVERS/site-packages/networkx-1.8.1-py${PYTHONNUMB}.egg/networkx/algorithms/shortest_paths/astar.py \
  < /ccp/dev/cp/scripts/setupcp/ao_templates/common/other/astar.patch

# To test: $ py / import networkx

# *** NumPy

# - Has some interesting math functions.
# Originally, just used for testing TSP code.
# But since 2013 some Cyclopath devs use NumPy and SciPy for research.
#

# Don't do this: It conflicts with apt-get's scipy:

__install_numpy__ () {

  echo
  echo "Installing NumPy"

  # http://scipy.org/NumPy

  # Note that numpy is part of the distro but it's probably aged.

  cd /ccp/opt/.downloads
  # wget \
  #  -N http://sourceforge.net/projects/numpy/files/NumPy/1.7.0/numpy-1.7.0.tar.gz/download \
  #  -O numpy-1.7.0.tar.gz
  wget \
    -N "http://downloads.sourceforge.net/project/numpy/NumPy/1.8.0/numpy-1.8.0.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fnumpy%2Ffiles%2FNumPy%2F1.7.2%2F&ts=1394309689&use_mirror=iweb" \
    -O numpy-1.8.0.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/numpy-1.8.0
  tar -xvzf numpy-1.8.0.tar.gz \
    > /dev/null
  cd /ccp/opt/.downloads/numpy-1.8.0

  python setup.py build --fcompiler=gnu95

  python setup.py install \
    --prefix=/ccp/opt/usr

  # To test:
  #
  #   $ python
  #
  #   > import numpy
  #   > numpy.test()
  #   > numpy.__version__

}

__dev_stall_scipy_etc__ () {

  sudo apt-get install \
    python-numpy \
    python-scipy \
    python-matplotlib \
    ipython \
    ipython-notebook \
    python-pandas \
    python-sympy \
    python-nose

}

# *** Fiona, The Pythonic OGR Wrapper

# 2014.03.09: The Fiona library has been around for years.
#             Why have we been punishing ourselves with OGR?

__install_fiona__ () {

  echo
  echo "Installing Fiona"

  # https://pypi.python.org/pypi/Fiona

  # Note that Fiona is not part of the Debian repositories.

  # If you're running virtualenv (you are if you're on the corporate network), 
  # you can supposedly use the following commands:
  #   $ mkdir fiona_env
  #   $ virtualenv fiona_env
  #   $ source fiona_env/bin/activate
  #   (fiona_env)$ pip install Fiona
  # And if you're not running virtualenv, supposedly the final pip command
  # works, but [lb] notes that pip is not installed on the corporate network,
  # nor for the dev machines necessarily have it installed. So we'll do a
  # manual install.

  cd /ccp/opt/.downloads
  # NOTE: From a dev. machine, --no-check-certificate doesn't seem to be
  #       necessary. Only on the CS machines.
  wget --no-check-certificate -N \
    https://pypi.python.org/packages/source/F/Fiona/Fiona-1.1.4.tar.gz

  /bin/rm -rf /ccp/opt/.downloads/Fiona-1.1.4

  tar xvf Fiona-1.1.4.tar.gz \
    > /dev/null
  cd Fiona-1.1.4

  # Install for everyone:
  #  sudo \
  #    python \
  #      setup.py \
  #      build_ext \
  #      -I/ccp/opt/gdal/include \
  #      -L/ccp/opt/gdal/lib \
  #      -lgdal \
  #      --prefix=/ccp/opt/usr \
  #      install

  # Install just for Ccp:
  python setup.py \
    build_ext \
    -I/ccp/opt/gdal/include \
    -L/ccp/opt/gdal/lib \
    -lgdal
  python setup.py install --prefix=/ccp/opt/usr

}

__install_fiona__

# *** Levenshtein Distance library

__install_levenshtein__ () {

  echo
  echo "Installing Levenshtein"

  # See: https://pypi.python.org/pypi/python-Levenshtein/
  #      https://github.com/ztane/python-Levenshtein/
  #      http://en.wikipedia.org/wiki/Levenshtein_distance

  cd /ccp/opt/.downloads
  # To connect to pypi.python.org insecurely, use '--no-check-certificate'.
  wget --no-check-certificate -N \
    https://pypi.python.org/packages/source/p/python-Levenshtein/python-Levenshtein-0.11.2.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/python-Levenshtein-0.11.2

  tar xvf python-Levenshtein-0.11.2.tar.gz \
    > /dev/null
  cd python-Levenshtein-0.11.2

  python setup.py build
  python setup.py install --prefix=/ccp/opt/usr

  # https://github.com/joncasdam/python-Levenshtein/blob/master/genextdoc.py
  wget --no-check-certificate \
    https://raw.github.com/joncasdam/python-Levenshtein/master/genextdoc.py
  ./gendoc.sh --selfcontained
  # In your Web browser:
  #  file:///ccp/opt/.downloads/python-Levenshtein-0.11.2/
  #  file:///ccp/opt/.downloads/python-Levenshtein-0.11.2/Levenshtein.html
  #  file:///ccp/opt/.downloads/python-Levenshtein-0.11.2/NEWS.xhtml

}    

# Not necessary unless you want the latestgreatest:
#   __install_levenshtein__
# See instead:
#   sudo apt-get install python-levenshtein

# *** swfobject

# 2014.05.02: "Error" page for ipad and phones.

# https://code.google.com/p/swfobject/
# https://stackoverflow.com/questions/9493952/
#  redirect-to-a-html-page-when-site-opens-in-non-flash-browser
# https://code.google.com/p/swfobject/wiki/documentation

cd /ccp/opt/.downloads
wget -N https://swfobject.googlecode.com/files/swfobject_2_2.zip
unzip swfobject_2_2.zip -d /ccp/opt/.downloads/swfobject_2_2

# *** QSopt Linear Programming Solver

# Used by Concorde TSP.

# NOTE: QSopt was compiled for RedHat but says it should work on other distros.

# See comments below: These are 32-bit libraries. Don't bother with 'em!
# cd /ccp/opt/.downloads
# wget -N http://www2.isye.gatech.edu/~wcook/qsopt/downloads/codes/linux24/QS.tar.gz \
#   -O QSopt-QS.tar.gz
# /bin/rm -rf /ccp/opt/.downloads/QSopt_LPS
# tar -xvzf QSopt-QS.tar.gz \
#   > /dev/null
# mv QS QSopt_LPS
# cd /ccp/opt/.downloads/QSopt_LPS
# # NOTE: The last path is a library path we'll need to make Concorde.

# See beta libs for x64 on:
# http://www2.isye.gatech.edu/~wcook/qsopt/beta/index.html

cd /ccp/opt/.downloads
/bin/rm -rf /ccp/opt/.downloads/QSopt_LPS
/bin/mkdir /ccp/opt/.downloads/QSopt_LPS
cd /ccp/opt/.downloads/QSopt_LPS
# Function library.
wget -N http://www2.isye.gatech.edu/~wcook/qsopt/beta/codes/linux64/qsopt.a
# C include file.
wget -N http://www2.isye.gatech.edu/~wcook/qsopt/beta/codes/linux64/qsopt.h
# Solver executable.
# EXPLAIN: Can we run this?
wget -N http://www2.isye.gatech.edu/~wcook/qsopt/beta/codes/linux64/qsopt

# Get QSopt documentation.
cd /ccp/doc/
wget -N http://www2.isye.gatech.edu/~wcook/qsopt/downloads/users.pdf \
  -O QSopt-users.pdf

wget -N \
  http://www.iwr.uni-heidelberg.de/groups/comopt/software/TSPLIB95/DOC.PS \
  -O TSPLIB_DOC.PS

# *** CPLEX (IBM ILOG CPLEX Optimization Studio)

# Nevermind: CPLEX is proprietary.
#
# http://www-03.ibm.com/software/products/us/en/ibmilogcpleoptistud/
#
# We can just use QSopt with Concorde.

# *** Concorde TSP

# In Python, [lb]'s simple TSP algorithm can solve 11 nodes quickly, 12 nodes
# in a minutes, and then things start getting ugly after that. But I guess the
# Consorde TSP can quickly solve TSP problems of ten of thousands of nodes.

# Note that Concorde must be pretty mature- The last push was 19 Dec 2003.

cd /ccp/opt/.downloads
wget -N http://www.tsp.gatech.edu/concorde/downloads/codes/src/co031219.tgz \
  -O concorde-tsp-co031219.tgz

# Note that SQopt is 32-bit. [lb] wants to try both 23- and 64-bit Concordes.

# # 64-bit, without QSoft.
# 
# cd /ccp/opt/.downloads
# /bin/rm -rf /ccp/opt/.downloads/concorde-tsp-co031219
# tar -xvzf concorde-tsp-co031219.tgz \
#   > /dev/null
# /bin/mv concorde concorde-tsp-co031219
# cd /ccp/opt/.downloads/concorde-tsp-co031219
#
# ./configure \
#   --prefix=/ccp/opt/concorde
# make
#
# # To test:
# #   ./TSP/concorde -s 99 -k 100
# # Outputs:
# #   "need to link an lp solver to use this function
# #    CClp_create_info failed"

# 32-bit, with QSoft

cd /ccp/opt/.downloads
/bin/rm -rf /ccp/opt/.downloads/concorde-tsp-co031219
tar -xvzf concorde-tsp-co031219.tgz \
  > /dev/null
/bin/mv concorde concorde-tsp-co031219
cd /ccp/opt/.downloads/concorde-tsp-co031219

# Note: Without gcc flags,
#
#   ./configure \
#      --prefix=/ccp/opt/concorde \
#      --with-qsopt=/ccp/opt/.downloads/QSopt_LPS
#
# you'll get this warning on ./configure:
#
#   checking host system type... Invalid configuration
#   `x86_64-unknown-linux-gnu': machine `x86_64-unknown' not recognized
#
# and you can start make, but it fails trying to link concorde:
#
#   .../QSopt_LPS/qsopt.a: could not read symbols: File in wrong format
#
# because QSopt is old and 32-bit (as confirmed via 
# objdump -f qsopt.a | grep ^architecture).
#
# [lb] read somewhere that -m32 is the proper compiler option, but
# configure rejects it, e.g., CFLAGS="-m32" ./configure ... spits,
#
#   checking whether the C compiler (gcc -m32 ) works... no
#   configure: error: installation or configuration problem:
#                     C compiler cannot create executables.
#
# Argh. Found the rights libraries (betas! on a different site!). See
# new code above in the QSopt section.
#
# Thanks to
# http://wiki.evilmadscience.com/Obtaining_a_TSP_solver#Concorde_TSP_on_Linux

# Skipping: ./configure --with-cplex, which is $18,000 IBM code.
#           Hey, Cyclopath is worth more at least that!

./configure \
  --prefix=/ccp/opt/concorde \
  --with-qsopt=/ccp/opt/.downloads/QSopt_LPS
make

# To test:
#   ./TSP/concorde -s 99 -k 100
#   ./TSP/concorde --help

# Test data, from
#   http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/
# for Sequential ordering problem (SOP).

cd /ccp/opt/.downloads/concorde-tsp-co031219
/bin/rm -rf /ccp/opt/.downloads/concorde-tsp-co031219/ccp_tests
mkdir /ccp/opt/.downloads/concorde-tsp-co031219/ALL_tsp
cd /ccp/opt/.downloads/concorde-tsp-co031219/ALL_tsp
wget -N http://www.iwr.uni-heidelberg.de/groups/comopt/software/TSPLIB95/tsp/ALL_tsp.tar.gz
tar -xvzf ALL_tsp.tar.gz \
  > /dev/null
# Skipping SOP tests. Alleyoop is a SOP solver, but Concorde doesn't recognize
# the input. Also, SOP is a constrained version of TSP, so we should be able
# to force the issue using edge costs?
# wget -N http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/sop/ALL_sop.tar
# gunzip br17.10.sop.gz
# ../TSP/concorde br17.10.sop
# Not a TSP problem
# CCutil_gettsplib failed
# 
# Also, what's a TOUR file? gunzip a280.opt.tour.gz
cd /ccp/opt/.downloads/concorde-tsp-co031219
/bin/rm -rf /ccp/opt/.downloads/concorde-tsp-co031219/ccp_tests
mkdir /ccp/opt/.downloads/concorde-tsp-co031219/ccp_tests
cd /ccp/opt/.downloads/concorde-tsp-co031219/ccp_tests

# /bin/cp ../ALL_tsp/dantzig42.tsp.gz .
# gunzip dantzig42.tsp.gz
# # 42 cities:
# ../TSP/concorde dantzig42.tsp
# ../TSP/concorde -z 3 dantzig42.tsp
# Asymmetrical Traveling Salesperson Problem
# ../TSP/concorde -N 7 ftv64.atsp

# http://www.tsp.gatech.edu/concorde/downloads/codes/src/970827/README

# *** Using R with Concorde

# FIXME: Oh, no! It looks like you can use R with Concorde to solve SOP
#        problems! You replace the start and final node with a dummy,
#        combined node with different incoming and outgoing weights
#        (though [lb] read that Concorde graphs are undirected, but
#        maybe that was just something to do with the Windows GUI
#        (where I read that information)).
#
# Though maybe I can still just use Concorde with a dummy node...

# Journal of Statistical Software
# Authors: 	Michael Hahsler, Kurt Hornik
# Vol. 23, Issue 2, Dec 2007

# http://www.jstatsoft.org/v23/i02
cd /ccp/doc/
# Paper- TSP -- Infrastructure for the Traveling Salesperson Problem 
wget -N http://www.jstatsoft.org/v23/i02/paper \
  -O tsp_paper.pdf

/bin/rm -rf /ccp/opt/.downloads/cyclopath_tsp
/bin/mkdir /ccp/opt/.downloads/cyclopath_tsp
cd /ccp/opt/.downloads/cyclopath_tsp
# R source package
wget -N http://www.jstatsoft.org/v23/i02/supp/1 \
  -O TSP_0.2-1.tar.gz
# R example code from the paper
wget -N http://www.jstatsoft.org/v23/i02/supp/2 \
  -O v23i02.R

# FIXME: Now the SOL files make sense, maybe... they're for R.

# *** Fix permissions and Grant ownerships

echo
echo "Fixing permissions on /ccp/opt/"

sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public /ccp/opt/ \
  > /dev/null 2>&1
sudo chown -R $targetuser /ccp/opt
sudo chgrp -R $targetgroup /ccp/opt

# *** Restore our spot

cd $script_path

# *** Reset GCC

if [[ -n "$MODULESHOME" ]]; then
  module load soft/gcc/4.5.2
fi

# *** All done!

echo
echo "GIS software compiled!"

exit 0

