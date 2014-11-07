#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./pyzipcode-setup.sh

# DEVs: You should only need to run this once, or whenever the U.S. reregions
#       its ZIP codes.
#       See: scripts/schema/221-introducing-zipcodes.sql

mkdir -p /ccp/var/zipcodes

pushd /ccp/var/zipcodes

wget http://pablotron.org/files/zipcodes-csv-10-Aug-2004.zip

unzip zipcodes-csv-10-Aug-2004.zip

cp zipcodes-csv-10-Aug-2004/zipcode.csv \
   /ccp/var/zipcodes/2004.08.10.zipcode.csv

chmod 664 /ccp/var/zipcodes/2004.08.10.zipcode.csv

/bin/rm -rf /ccp/var/zipcodes/zipcodes-csv-10-Aug-2004
/bin/rm -f /ccp/var/zipcodes/zipcodes-csv-10-Aug-2004.zip

popd

echo ""
echo "======================================================="
echo "All setup! See /ccp/var/zipcodes/2004.08.10.zipcode.csv"
echo "======================================================="
echo ""

ls -la /ccp/var/zipcodes

