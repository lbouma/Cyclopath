#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./planner_tester.sh
#
#        or just copy-n-paste from herein to some terminals

# FIXME: This script is not runnable. Dig around and cxpx for now.
#        Hopefully someday this'll be a useful, runnable script.
#          --run-once # Run once to create the test diff files
#          --run-test # Run daily to test route requests
#        I.e., save known test results to a directory (and
#        inspect the results -- maybe this script runs each
#        route one at a time and asks for your confirmation?).
#        For the daily test, just compare output.
#        NOTE: You'll need to use stdout and not the logger,
#        otherwise you'll invalidate the known test results
#        files whenever you edit a trace statement.

script_relbase=$(dirname $0)
source ${script_relbase}/../util/ccp_base.sh

# ***

test_county_lake_prepare () {
  svccmd=$1
  #APACHE_INSTANCE=minnesota___cp_2628
  APACHE_INSTANCE=${INSTANCE}___${CCP_INSTANCE}
  PYSERVER_HOME=/ccp/dev/cp_2628/pyserver
  sudo -u $httpd_user \
    INSTANCE=$APACHE_INSTANCE \
    PYTHONPATH=$PYTHONPATH \
    PYSERVER_HOME=$PYSERVER_HOME \
    SHP_CACHE_DIR='/ccp/var/shapefiles/test' \
    SOURCE_SHP='/ccp/var/shapefiles/test/Cyclopath-Export/Cyclopath Export.shp' \
    $PYSERVER_HOME/../services/routedctl \
    --routed_pers=p3 \
    --source_zip='/ccp/var/shapefiles/test/2014.04.16-Mpls-St._Paul-lake.zip' \
    $svccmd
}

INSTANCE=minnesota
CCP_INSTANCE=cp_2628
APACHE_INSTANCE=${INSTANCE}___${CCP_INSTANCE}

cd $PYSERVER_HOME

test_county_lake_prepare stop

ccp_routed_ports_wait ${APACHE_INSTANCE} 0 p3

killrd
ccp_routed_ports_reset ${APACHE_INSTANCE} 0 p3
test_county_lake_prepare start
ccp_routed_ports_wait ${APACHE_INSTANCE} 0 p3

./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p3 --p3-weight length --p3-spread 4 --p3-burden 20

for weight in 'len' 'rat' 'fac' 'rac' 'prat' 'pfac' 'prac'; do
  ./ccp.py --route \
    --from "waldo road and airport road, two harbors" \
    --to "7th st and 8th av, two harbors" \
    --p3 --p3-weight ${weight} --p3-spread 4 --p3-burden 20
done

# Personalized routes.
./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p3 --p3-weight prat --p3-spread 4 \
  -U landonb --no-password
# Compare to:
./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p3 --p3-weight prat --p3-spread 4

# Classic planner transition: Omit --p1 and --p3 will handle.
./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p1-priority 0.625

all facil routes are river... but at least it shows
diff btw old finder and new finder...
w 50th st and dupont ave s, mpls
gateway fountain

pipestone
grand portage


# From routed_p3.route_finder:

# ./ccp.py --route --p3 --from 'Two Harbors, MN' --to 'Pipestone, MN'

# ./ccp.py --route --from "Gateway Fountain"             \
#     --to "7th st and 8th av, two harbors"              \
#     --p3 --p3-weight length --p3-spread 4 --p3-burden 20

# ./ccp.py --route                                                   \
#     --from "waldo road and airport road, two harbors"              \
#     --to "7th st and 8th av, two harbors"                          \
#     --p3 --p3-weight length --p3-spread 4 --p3-burden 20
# FIXME: w/ new IoError catch on geocode, returns "too close together"

# ./ccp.py --route --from "2h1" --to "2h2"               \
#     --p3 --p3-weight length --p3-spread 4 --p3-burden 20





for weight in 'len' 'rat' 'fac' 'rac' 'prat' 'pfac' 'prac'; do
  ./ccp.py --route \
    --from "gateway fountain" \
    --to "w 50th st and dupont ave s, mpls" \
    --p3 --p3-weight ${weight} --p3-spread 4 --p3-burden 20
done


./ccp.py --route \
  --from "gateway fountain" \
  --to "w 50th st and dupont ave s, mpls" \
  --p3 --p3-weight 'rat' --p3-spread 32

./ccp.py --route \
  --from "gateway fountain" \
  --to "w 50th st and dupont ave s, mpls" \
  --p3 --p3-weight 'rat' --p3-spread 2



# ***

# The p1 planner.

# FIXME/BUG nnnn: The avg_cost of each of these is 0.11?

./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p1 --p1-priority 0.625

./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p1 --p1-priority 0

./ccp.py --route \
  --from "waldo road and airport road, two harbors" \
  --to "7th st and 8th av, two harbors" \
  --p1 --p1-priority 1

# ***

# ***

# The whole state.

./ccp.py --route --p3 --from 'Two Harbors, MN' --to 'Pipestone, MN'

./ccp.py --route \
  --from "Gateway Fountain" \
  --to "7th st and 8th av, two harbors" \
  --p3 --p3-weight length --p3-spread 4 --p3-burden 20

# ***

