#!/bin/bash

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# *** Debug Options

DEBUG_TRACE=false
DEBUG_TRACE=true

# *** Setup

branch_name=$1
branch__ed=`echo $branch_name | tr ' ' '_'`

. ${PYSERVER_HOME}/../scripts/daily/ccp_export_base.sh \
  "${PYSERVER_HOME}/../scripts/daily/tmp/ccp_export_branches-${branch__ed}"

# *** Setup directories and paths

#LOGFILE=/ccp/var/log/daily/ccp_export_branches.log

# *** Make the Metadata

# This is done in ccp_export_base.sh.

# *** Export the Data

# Note that merge_job_export copies the metadata, ccp_road_network.htm,
# and the license, LICENSE.txt, to the zipfile, but we still want to copy them
# to the Web location.

$DEBUG_TRACE && echo "Scheduling export job: ${branch_name}."

#cd ${PYSERVER_HOME}
pushd ${PYSERVER_HOME} &> /dev/null

ccp_script=./ccp.py

# MAYBE: Regional exports, e.g.,
#         -e filter_by_region "Seven County Metro Area" \
#         -e filter_by_region "Minneapolis--St. Paul" \

# BUG nnnn: Also export points, regions, and terrain.
# MAYBE: What are tag_points? CcpV1 exports: blocks, regions, points, basemaps,
#        and tag_points... is this different that what export already does,
#        i.e., it already includes tags, right?

$DEBUG_TRACE && echo "PUBLISH_QUARTERLY: ${PUBLISH_QUARTERLY}."

if ! $PUBLISH_QUARTERLY; then
  PUBLISH_PREFIX="${PREFIX_EXPORTS_DAILY}-${branch__ed}"
  # Delete all of yesterdays' exports.
  yesterdays="${EXPORTS_DAILY}/*-${branch__ed}*.zip"
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all of yesterdays: ${yesterdays}."
    # NOTE: This doesn't work, with quotes, maybe because of the '*'?
    # Nopes: /bin/ls -la "${yesterdays}"
    # Works: /bin/ls -la ${yesterdays}
    /bin/rm -f ${yesterdays}
  fi
  yesterdays="${EXPORTS_DAILY}/*-ccp_road_network.htm"
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all of yesterdays: ${yesterdays}."
    /bin/rm -f ${yesterdays}
  fi
else
  PUBLISH_PREFIX="${PREFIX_EXPORTS_QUARTERLY}-${branch__ed}"
fi
PUBLISH_RESULT="${PUBLISH_PREFIX}.zip"

$DEBUG_TRACE && echo "Calling ./ccp.py on ${PUBLISH_RESULT}."

PUBLISH_RESULT_TMP="${PUBLISH_PREFIX}.tmp.zip"

echo "
  $ccp_script \
    -U landonb --no-password \
    -b "${branch_name}" \
    -c -t merge_export_job \
    -m "Ignored." \
    -e job_local_run 1 \
    -e job_act "create" \
    -e name "" \
    -e for_group_id 0 \
    -e for_revision 0 \
    -e email_on_finish 0 \
    -e publish_result "${PUBLISH_RESULT_TMP}"
  "
__2014_02_04__='
    cd /ccp/dev/cp_cron/pyserver
    ./ccp.py \
      -U landonb --no-password \
      --database ccpv3_live \
      -b "Minnesota" \
      -c -t merge_export_job \
      -m "Ignored." \
      -e job_local_run 1 \
      -e job_act create \
      -e name "" \
      -e for_group_id 0 \
      -e for_revision 0 \
      -e email_on_finish 0 \
-e filter_by_region "Lynnhurst" \
      -e publish_result "/ccp/dev/cp_cron/pyserver/../htdocs/exports/daily/daily-Mpls-St._Paul.zip"


    ./ccp.py \
      -U landonb --no-password \
      -b "Metc Bikeways 2012" \
      -c -t merge_export_job \
      -m "Ignored." \
      -e job_local_run 1 \
      -e job_act create \
      -e name "" \
      -e for_group_id 0 \
      -e for_revision 0 \
      -e email_on_finish 0 \
-e filter_by_region "Lynnhurst" \
      -e publish_result "/ccp/dev/cp_cron/pyserver/../htdocs/exports/daily/daily-Metc_Bikeways_2012.zip"

/bin/cp -f \
  /ccp/dev/cp_cron/pyserver/../htdocs/exports/daily/daily-Metc_Bikeways_2012.zip \
  /win/Users/Pee\ Dubya/Desktop/_Cyclopath/_Cycloplan.Shapefiles/

From /ccp/var/log/daily/daily.ccp_export_branches-cycloplan_live-minnesota-Minnesota.log:

./ccp.py -U landonb --no-password -b Minnesota -c -t merge_export_job -m Ignored. -e job_local_run 1 -e job_act create -e name "" -e for_group_id 0 -e for_revision 0 -e email_on_finish 0 -e publish_result /ccp/dev/cycloplan_live/pyserver/../htdocs/exports/daily/2014.07.09-Minnesota.zip


cd /ccp/dev/cycloplan_test
setcp
cd pyserver
./ccp.py \
  -U landonb --no-password \
  -b Minnesota \
  -c -t merge_export_job \
  -m Ignored. \
  -e job_local_run 1 \
  -e job_act create \
  -e name "" \
  -e for_group_id 0 \
  -e for_revision 0 \
  -e email_on_finish 0 \
  -e publish_result /ccp/var/htdocs/cycloplan_live/exports/Minnesota.zip
./ccp.py \
  -U landonb --no-password \
  -b "Metc Bikeways 2012" \
  -c -t merge_export_job \
  -m Ignored. \
  -e job_local_run 1 \
  -e job_act create \
  -e name "" \
  -e for_group_id 0 \
  -e for_revision 0 \
  -e email_on_finish 0 \
  -e publish_result /ccp/var/htdocs/cycloplan_live/exports/Metc_Bikeways_2012.zip



  '
$ccp_script \
  -U landonb --no-password \
  -b "${branch_name}" \
  -c -t merge_export_job \
  -m "Ignored." \
  -e job_local_run 1 \
  -e job_act "create" \
  -e name "" \
  -e for_group_id 0 \
  -e for_revision 0 \
  -e email_on_finish 0 \
  -e publish_result "${PUBLISH_RESULT_TMP}" \
  --instance-worker \
  --has-revision-lock \
  --log-cleanly

# If the export fails, it clobbers the file, which is bad
# (if the export fails, we should keep the last good export we made).
if [[ -e ${PUBLISH_RESULT_TMP} ]]; then
  /bin/mv ${PUBLISH_RESULT_TMP} ${PUBLISH_RESULT}
fi

# BUG nnnn/FIXME: 2013.12.28: The counties don't have regions yet.
# So you can run this code, but it just causes lots of logcheck complaints.
#
# FIXME/BUG nnnn: Import counties: The base Ccp map seems to have all cities,
#               but just some counties (and not, e.g., Hennepin or Washington).
#
#if false; then
# 2014.09.16: This is too much work for the server.
#             It spins and spins, and no one else can get ins.
#             Turn off, then? Maybe someday move to dedicated machine?
#             BUG nnnn: Setup County exports, and other analysis tasks,
#                       on another machine.
#if true; then
if false; then

  __ignore_me__="
./ccp.py \
  -U landonb --no-password \
  -b 'Minnesota' \
  -c -t merge_export_job \
  -m 'Ignored.' \
  -e job_local_run 1 \
  -e job_act 'create' \
  -e name '' \
  -e for_group_id 0 \
  -e for_revision 0 \
  -e email_on_finish 0 \
  -e filter_by_region 'mahnomen' \
  -e publish_result '/ccp/var/htdocs/cp/exports/2014.01.30-Mpls-St._Paul-mahnomen.zip'
"

  if [[ ${INSTANCE} == 'minnesota' ]]; then

    # 2014.04.21: We use to check the MnDOT counties table, but now that we've
    # got real county-tagged regions, we can just look for those. Note that we
    # don't check permissions here, but if the export script cannot read the
    # region, it'll just not make the export Shapefile.

    SETPATH="SET search_path TO ${INSTANCE}, public;"

    ITYPE_ID_TAG=`
      psql -U cycling ${CCP_DB_NAME} -q -tA -c \
        "SELECT cp_item_type_id('tag');"`
    ITYPE_ID_REGION=`
      psql -U cycling ${CCP_DB_NAME} -q -tA -c \
      "SELECT cp_item_type_id('region');"`
    ITYPE_ID_LVAL=`
      psql -U cycling ${CCP_DB_NAME} -q -tA -c \
      "SELECT cp_item_type_id('link_value');"`
    TAG_SID_COUNTY=`
      psql -U cycling ${CCP_DB_NAME} -q -tA -c \
      "${SETPATH}; SELECT cp_tag_sid('county');"`
    RID_INF=`
      psql -U cycling ${CCP_DB_NAME} -q -tA -c \
      "SELECT cp_rid_inf();"`
    $DEBUG_TRACE && echo "ITYPE_ID_TAG: $ITYPE_ID_TAG"
    $DEBUG_TRACE && echo "ITYPE_ID_REGION: $ITYPE_ID_REGION"
    $DEBUG_TRACE && echo "ITYPE_ID_LVAL: $ITYPE_ID_LVAL"
    $DEBUG_TRACE && echo "TAG_SID_COUNTY: $TAG_SID_COUNTY"
    $DEBUG_TRACE && echo "RID_INF: $RID_INF"

    # Psql returns one line for each county, but bash just makes one big var.
    # E.g., this does not suffice:
    #  declare -a PSQL_LINES
    #  PSQL_LINES=($PSQL_REPLY)
    # [lb] thinks there's another way to do this (like, akin to find's -print0
    #   and xargs's -0) but this is the best I came up with so far: add a comma
    #   to the postgres output and then use Bash's IFS variable to split on
    #   commas rather than on whitespace when making the array.
    # Split the line into an array.
    PSQL_REPLY=$(psql -U cycling ${CCP_DB_NAME} -q -tA -c \
      "
      ${SETPATH};
      SELECT outer_gia.name || ',' AS county_name
      FROM group_item_access AS outer_gia
      WHERE outer_gia.item_type_id = ${ITYPE_ID_REGION}
        AND EXISTS (
          SELECT lv.system_id
          FROM link_value AS lv
          JOIN item_versioned AS iv
            USING (system_id)
          JOIN group_item_access AS inner_gia
            ON (lv.system_id = inner_gia.item_id)
            WHERE lv.lhs_stack_id = ${TAG_SID_COUNTY}
              AND lv.rhs_stack_id = outer_gia.stack_id
              AND NOT iv.DELETED
              AND iv.valid_until_rid = ${RID_INF}
              )
      ;
      ")
    IFS="," read -a PSQL_LINES -d "" <<< "${PSQL_REPLY}"

    # Make an export for each county.
    for arr_index in $(seq 0 ${#PSQL_LINES[@]}); do
      county_name=${PSQL_LINES[$arr_index]}
      # Remove leading and trailing whitespace (it's just leading whitespace
      # because of how `read` split on the ', ' delimiters.
      county_name=`echo $county_name | sed 's/^ +//g' | sed 's/ +$//g'`
      # We need to check -z because of the last entry in the list: there's
      # an empty string after the last comma.
      if [[ -n $county_name ]]; then
        $DEBUG_TRACE && echo "Exporting county data: ${county_name}."
        #echo c=$county_name=c
        county__ed=`echo $county_name | tr ' ' '_'`
        PUBLISH_COUNTY="${PUBLISH_PREFIX}-${county__ed}.zip"
        #echo c=$PUBLISH_COUNTY=c
        # 2014.08.13: The MetC branch doesn't have all the county regions, and
        # the job raises GWIS_Nothing_Found for unknown regions. Since region
        # exports aren't crucial (we really just care about the big state
        # shapefile), we can redirect this output to null so that the cron
        # job doesn't detect any errors.
        # 2014.09.07: Use --log-cleanly so logcheck doesn't complain.
        $ccp_script \
          -U landonb --no-password \
          -b "${branch_name}" \
          -c -t merge_export_job \
          -m "Ignored." \
          -e job_local_run 1 \
          -e job_act "create" \
          -e name "" \
          -e for_group_id 0 \
          -e for_revision 0 \
          -e email_on_finish 0 \
          -e filter_by_region "${county_name}" \
          -e publish_result "${PUBLISH_COUNTY}" \
          --instance-worker \
          --has-revision-lock \
          --log-cleanly \
          --ignore-job-fail \
          &> /dev/null
      fi
    done
  fi
fi

popd &> /dev/null

# *** Publish the Archives

if ! $PUBLISH_QUARTERLY; then
  $DEBUG_TRACE && echo "Moving to daily exports."
  mv ${CCP_EXPORT_WORKING}/ccp_road_network.htm \
    ${PREFIX_EXPORTS_DAILY}-ccp_road_network.htm
else
  $DEBUG_TRACE && echo "Moving to quarterly exports."
  mv ${CCP_EXPORT_WORKING}/ccp_road_network.htm \
    ${PREFIX_EXPORTS_QUARTERLY}-ccp_road_network.htm
  # Make a link from the daily location.
  /bin/ln -f -s ${PUBLISH_RESULT} \
    ${EXPORTS_DAILY}/${branch__ed}.zip
  /bin/ln -f -s ${PREFIX_EXPORTS_QUARTERLY}-ccp_road_network.htm \
    ${PREFIX_EXPORTS_DAILY}-ccp_road_network.htm
fi
# Make well-known links to the new files.
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-${branch__ed}.zip \
  ${BASE_EXPORTS}/${branch__ed}.zip
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-ccp_road_network.htm \
  ${BASE_EXPORTS}/ccp_road_network.htm
/bin/ln -f -s ${EXPORTS_DAILY}/${PUBLISH_DATE}-${branch__ed}.zip \
  ${EXPORTS_DAILY}/${branch__ed}.zip
/bin/ln -f -s ${EXPORTS_DAILY}/${PUBLISH_DATE}-ccp_road_network.htm \
  ${EXPORTS_DAILY}/ccp_road_network.htm

# *** Cleanup

if true; then
  /bin/rm -rf ${CCP_EXPORT_WORKING}
fi

# *** Fix permissions

${PYSERVER_HOME}/../scripts/util/fixperms.pl --public ${BASE_EXPORTS}
${PYSERVER_HOME}/../scripts/util/fixperms.pl --public ${BASE_REPORTS}

# *** Print elapsed time

time_1=$(date +%s.%N)

$DEBUG_TRACE && printf "All done: Elapsed: %.2F mins.\n" \
    $(echo "($time_1 - $script_time_0) / 60.0" | bc -l)

# *** All done!

exit 0

