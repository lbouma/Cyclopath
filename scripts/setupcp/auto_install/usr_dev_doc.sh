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

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its 
#          variables become ours.
. $script_relbase/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,
#            reload_databases, PYTHONVERS2, and httpd_user.

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

# *** Setup ccp/doc

echo 
echo "Copying documentation"

ccp_mkdir /ccp/doc

cd /ccp/doc/

# Copy from masterhost

#cp -f /scratch/$masterhost/ccp/doc/devguide_flex3.pdf /ccp/doc
#cp -f /scratch/$masterhost/ccp/doc/progAS_flex3.pdf /ccp/doc
#cp -f /scratch/$masterhost/ccp/doc/gnuplot-4.4.pdf /ccp/doc
#cp -f /scratch/$masterhost/ccp/doc/postgis-1.5.3.pdf /ccp/doc
#cp -f /scratch/$masterhost/ccp/doc/MapServer-6.0.1.pdf /ccp/doc
#/bin/rm -rf /ccp/doc/Python-Docs-2.7.2
#cp -rf /scratch/$masterhost/ccp/doc/Python-Docs-2.7.2 /ccp/doc
#/bin/rm -rf /ccp/doc/Graphserver
#cp -rf /scratch/$masterhost/ccp/doc/Graphserver /ccp/doc

# Download from interjungle

# Python 2.6
if ! [[ -d /ccp/doc/python-2.6.7 ]]; then
  wget -N http://docs.python.org/ftp/python/doc/2.6.7/python-2.6.7-docs-pdf-letter.tar.bz2
  /bin/rm -rf /ccp/doc/docs-pdf
  /bin/rm -rf /ccp/doc/python-2.6.7
  tar xvf python-2.6.7-docs-pdf-letter.tar.bz2 \
    > /dev/null
  /bin/mv /ccp/doc/docs-pdf /ccp/doc/python-2.6.7
  /bin/rm -rf /ccp/doc/python-2.6.7-docs-pdf-letter.tar.bz2
fi

# Python 2.7
if ! [[ -d /ccp/doc/python-2.7.2 ]]; then
  wget -N http://docs.python.org/ftp/python/doc/2.7.2/python-2.7.2-docs-pdf-letter.tar.bz2
  /bin/rm -rf /ccp/doc/docs-pdf
  /bin/rm -rf /ccp/doc/python-2.7.2
  tar xvf python-2.7.2-docs-pdf-letter.tar.bz2 \
    > /dev/null
  /bin/mv /ccp/doc/docs-pdf /ccp/doc/python-2.7.2
  /bin/rm -rf /ccp/doc/python-2.7.2-docs-pdf-letter.tar.bz2
fi

# Mod_Python
if ! [[ -e /ccp/doc/mod_python-2.7.pdf ]]; then
  wget -N http://www.modpython.org/live/mod_python-2.7.8/modpython.pdf
  /bin/mv -f /ccp/doc/modpython.pdf \
    /ccp/doc/mod_python-2.7.pdf
fi

# MapServer
if ! [[ -e /ccp/doc/mapserver-6.0.1.pdf ]]; then
  wget -N http://mapserver.org/MapServer.pdf
  /bin/mv -f /ccp/doc/MapServer.pdf \
    /ccp/doc/mapserver-6.0.1.pdf
fi

# USGS National Hydrology Dataset
if ! [[ -e /ccp/doc/mapserver-6.0.1.pdf ]]; then
  wget -N http://nhd.usgs.gov/NHDv2.0_poster_6_2_2010.pdf
fi

# PostGIS
#wget -N http://postgis.refractions.net/download/postgis-1.5.4.pdf
wget -N http://postgis.refractions.net/download/postgis-2.0.0.pdf
wget -N http://download.osgeo.org/postgis/docs/postgis-2.1.0.pdf
#wget -N http://postgis.net/stuff/postgis-2.1.1dev.pdf

# gnuplot
if ! [[ -e /ccp/doc/gnuplot-4.4.pdf ]]; then
  wget -N http://www.gnuplot.info/docs_4.4/gnuplot.pdf
  /bin/mv -f /ccp/doc/gnuplot.pdf \
    /ccp/doc/gnuplot-4.4.pdf
fi

# Flex 3
#wget -N http://livedocs.adobe.com/flex/3/devguide_flex3.pdf
#wget -N http://livedocs.adobe.com/flex/3/progAS_flex3.pdf
#wget -N http://livedocs.adobe.com/flex/3/createcomps_flex3.pdf
#wget -N http://livedocs.adobe.com/flex/3/build_deploy_flex3.pdf
# 2014.01.17: Hrmpf. Adobe has a dead link on
#  http://www.adobe.com/support/documentation/en/flex/flex3.html
# It's the same wget we're using, but it goes to a generic doc
# index and not to the zip file.
if ! [[ -d /ccp/doc/flex3 ]]; then
  wget -N http://livedocs.adobe.com/flex/3/flex3_documentation.zip
  set +e # Stay on error
  unzip -q \
    /ccp/doc/flex3_documentation.zip \
    -d /ccp/doc/flex3
  if [[ $? -ne 0 ]]; then
    echo "WARNING: Adobe moved or borked flex3_documentation.zip"
  fi
  set -e
  /bin/rm -f /ccp/doc/flex3_documentation.zip
fi

# GraphServer
ccp_mkdir /ccp/doc/graphserver
cd /ccp/doc/graphserver
# Get the single GraphServer Web page
if ! [[ -e /ccp/doc/graphserver/graphserver.html ]]; then
  /bin/rm -rf /ccp/doc/graphserver/graphserver.html
  wget -Ographserver.html http://graphserver.github.com/graphserver/
fi
# Get the GTFS spec.
if ! [[ -e /ccp/doc/graphserver/transit_feed_spec.html ]]; then
  /bin/rm -rf /ccp/doc/graphserver/transit_feed_spec.html
  wget -Otransit_feed_spec.html \
    https://developers.google.com/transit/gtfs/reference
fi

# # MnDOT MUTCD: Minnesota Manual on Uniform Traffic Control Devices
# cd /ccp/doc
# if ! [[ -e /ccp/doc/mnmutcd.pdf ]]; then
#   wget http://www.dot.state.mn.us/trafficeng/publ/mutcd/mnmutcd2013/mnmutcd.pdf
# fi
# # USDOT Manual on Uniform Traffic Control Devices
# if ! [[ -e /ccp/doc/mutcd2009r1r2edition.pdf ]]; then
#   wget http://mutcd.fhwa.dot.gov/pdfs/2009r1r2/mutcd2009r1r2edition.pdf
# fi

# MediaWiki cheat sheet, for editing our text wiki.
ccp_mkdir /ccp/doc/mediawiki
cd /ccp/doc/mediawiki
# CAVEAT: This reference is pretty good, but it's missing some syntax,
#         such as how to set variables on a page.
set +e
wget -N https://upload.wikimedia.org/wikipedia/meta/e/e7/MediaWikiRefCard.png
if [[ $? -ne 0 ]]; then
  echo
  echo "WHATEVER: Not found: MediaWikiRefCard.png"
  echo
fi
# To view, try: eog MediaWikiRefCard.png &
wget -N https://upload.wikimedia.org/wikipedia/meta/6/66/MediaWikiRefCard.pdf
if [[ $? -ne 0 ]]; then
  echo
  echo "WHATEVER: Not found: MediaWikiRefCard.png"
  echo
fi
set -e

# Daring Fireball Markdown Syntax Documentation, for BitBucket README.md.
ccp_mkdir /ccp/doc/markdown
cd /ccp/doc/markdown
wget -E -H -k -K -p http://daringfireball.net/projects/markdown/syntax
# You can make a browser bookmark for:
#  file:///ccp/doc/markdown/daringfireball.net/projects/markdown/syntax.html

# Git help.
ccp_mkdir /ccp/doc/git
cd /ccp/doc/git
wget -N https://github.s3.amazonaws.com/media/progit.en.pdf
#wget -N https://github.s3.amazonaws.com/media/pro-git.en.mobi
#wget -N https://github.s3.amazonaws.com/media/progit.epub
set +e
wget -N \
 https://na1.salesforce.com/help/doc/en/salesforce_git_developer_cheatsheet.pdf
if [[ $? -ne 0 ]]; then
  echo
  echo "WHATEVER: Not found: MediaWikiRefCard.png"
  echo
fi
wget -E -H -k -K -p http://ndpsoftware.com/git-cheatsheet.html
if [[ $? -ne 0 ]]; then
  echo
  echo "WHATEVER: Not found: MediaWikiRefCard.png"
  echo
fi
set -e

# Fix perms
sudo chown -R $targetuser /ccp/doc 
sudo chgrp -R $targetgroup /ccp/doc 

# *** Restore location

cd $script_path

# *** All done!

echo
echo "Done setting up ccp/."

exit 0

