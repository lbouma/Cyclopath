#!/bin/bash

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# *** Overview

# This script creates Cyclopath data products, i.e., downloadable data
# sets comprised of Shapefiles, metadata, and license information.

# The Shapefiles are created via two different means, either by exporting an
# existing VIEW or by creating and new Cyclopath export job. Obviously, the
# former option -- using a VIEW -- is a simple process, but the export job
# lets us include more sophisticated generated data in the output.

# *** Debug Options

DEBUG_TRACE=false
#DEBUG_TRACE=true

# *** Setup

. ${PYSERVER_HOME}/../scripts/daily/ccp_export_base.sh \
  "${PYSERVER_HOME}/../scripts/daily/tmp/ccp_export_routes"

# *** Setup directories and paths

#LOGFILE=/ccp/var/log/daily/ccp_export_routes.log

# *** Export VIEWs

# Circa 2010 and earlier: We redirected the ogr2ogr output to STDERR because of
# a few warnings that were produced. But Circa 2012 [lb] fixed it so there are
# no warnings, so ogr2ogr shouldn't produce output unless there's a problem (so
# it's cronsafe now; before, we had logcheck rummage through the output file.)
#
# Bug 2734: Scripts: Fix ogr2ogr warnings and other issues
#   - Remove geofeature exports and use ccp.py to make import/export job
#     instead. (And don't forget to make the nightly and quarterly downloads.)
#   - Add "-a_srs srs_def" so ArcGIS doesn't complain about missing spatial
#     reference information.
#   - Fix warnings:
#     -- "Warning 1:
#         Multi-column primary key in '...' detected but not supported."
#         Solution: Use qgis 1.6.0 or better (itamae was using 1.2.0).
#     -- "Warning 1: Unable to detect single-column primary key for '...'.
#         Use default 'ogc_fid'"
#         Solution: [lb] cannot remember.
#     -- "Warning 6:
#         Field rev_time create as date field, though DateTime requested."
#         Solution: Use qgis 1.7.0-r16894 or better and use -fieldTypeToString.
#         See: http://trac.osgeo.org/gdal/ticket/2968
#     -- "Warning 1:
#         Value '...' of field comments has been truncated to 80 characters."
#         Solution: 
#         See: Cast text columns to a wider width than just 80 characters.
#      http://lists.osgeo.org/pipermail/mapserver-users/2008-August/056997.html
#
# See: man bash: Parameter Expansion

# MAYBE:    Casting text columns directly affects the Shapefile file size.
#           Can we do anything about this? I.e., would we really want to
#           restrict text widths that users can enter, like, names must be
#           under 256 chars? [lb] doesn't like being restrictive. Also,
#           since comments and tags are aggregate values, we're eventually
#           going to hit a limit... that is, we can't just keep casting to
#           a longer width, since the Shapefile size grows and grows, too.
# MAYBE:    Do 'comments' and 'tags' values really need to be part of the 
#           Shapefile, or can they be externally linked? Unfortunately, [lb]
#           thinks the Shapefile format is pretty basic, so we're not going
#           to be able to do variable-length text fields, are we?


# Be destructive; clobber the exising logfile.
# FIXME: 2012.10.16: Don't redirect, since we shouldn't get warnings anymore.
#echo "" > ${LOGFILE}

# Start in the tmp. directory.
#cd ${CCP_EXPORT_WORKING} ; cd ..
#cd ${CCP_EXPORT_WORKING}
pushd ${CCP_EXPORT_WORKING} &> /dev/null

# MAYBE: Bash doesn't support arrays-of-arrays, so if you need a more robust
#        set of input parameters, you'll probably want to specify each element
#        of the for-loop as a set of switches,
#         i.e., for table_def in "blocks --cast comments --cast tags" \
#                                "regions" \
#                                etc.

if true; then

  # NOTE: These tables (views) are branch-agnostic.

  for table_def in "rt_line_segs   name "  \
                   "rt_endpoints        "  \
                   "rt_collected        "; do

    defn=( $table_def )

    gis_view=${defn[0]}

    # Get the length of the array and slice it.
    # NOTE: [*] same as [@].
    arr_len=${#defn[*]}
    cast_cols=${defn[*]:1:$arr_len}

    cast_col_sql="*"
    for col_name in $cast_cols; do
      # FIXME: Compare Shapefile file sizes: by casting some text fields, we're
      #        increasing the size of the Shapefile. For Statewide, this might
      #        not be acceptable (i.e., the difference btw. a 20 MB download
      #        and a 200 MB download).
      # FIXME: The Psql VIEW should also cast (i.e., cast down to 255), so that
      #        ogr2ogr doesn't complain when the text width is still greater
      #        than to what we're casting here.
      cast_col_sql="${cast_col_sql}, CAST($col_name AS CHARACTER(255))"
    done

    table_name=${INSTANCE}.gis_${gis_view}

    # FIXME: 2012.10.11: CcpV1 redirects to the logfile (unsuccessfully)
    #        because people didn't solve the warnings. I think the warnings
    #        are solved now. So we shouldn't need to redirect to a logfile...
    #        i.e., the output should be blank, so we can just run from cron and
    #        assume a clean run produces no output.

    # NOTE: Normally, the table name is the last parameter, but since we use
    #       --sql, the table name (or layer name, as ogr2ogr calls it) is
    #       ignored, so we don't specify it (lest we get WARNINGed at).

    # Some helpful ogr2ogr hints:
    #   See: ogr2ogr --long-usage
    #  Also: -nln name: Assign an alternate name to the new layer
    #   and: Last three parameters: dst_datasource_name (target directory)
    #                               src_datasource_name (Postgres database)
    #                               output layer name (i.e., Shapefile name)
    #  -overwrite: Overwrite layers in target Shapefile (i.e., if target
    #        Shapefile already exists -- so you could just /bin/rm the existing
    #        files).

    __2014_02_04__='
    /ccp/opt/gdal-1.10.1/bin/ogr2ogr -f "ESRI Shapefile" \
      -overwrite -nln gis_rt_line_segs \
      -a_srs EPSG:26915 -fieldTypeToString DateTime \
 -sql "SELECT *, CAST(name AS CHARACTER(255)) from minnesota.gis_rt_line_segs"\
      /ccp/dev/cp/pyserver/../scripts/daily/tmp/ccp_export_routes \
      PG:"host=localhost port=5432 user=postgres dbname=ccpv3_lite"
    '

    $DEBUG_TRACE && echo "Processing table: ${gis_view}"

    $OGR2OGR                                        \
      -f "ESRI Shapefile"                           \
      -overwrite                                    \
      -nln $gis_view                                \
      -a_srs EPSG:26915                             \
      -fieldTypeToString DateTime                   \
      -sql "SELECT $cast_col_sql from $table_name"  \
      ${CCP_EXPORT_WORKING}                         \
    PG:"host=localhost port=${CCP_DB_PORT} user=postgres dbname=${CCP_DB_NAME}"
    # \
    #  | tee --append ${LOGFILE} 2>&1
    #
    # NOTE: We used to skip stdout and wrote to the logfile only,
    #         e.g., 2>> ${LOGFILE}
    #
    # Some example warnings deom ogr2ogr:
    #    Warning 1: Field name2 of width 255 truncated to 254.
    #    Warning 1: Field 'name' already exists. Renaming it as 'name2'
    # 

  done

fi

popd &> /dev/null

# *** Make the Metadata

# This is done in ccp_export_base.sh.

# *** Make the Archives

$DEBUG_TRACE && echo "Zipping files..."

#cd ${CCP_EXPORT_WORKING}
pushd ${CCP_EXPORT_WORKING} &> /dev/null

# Create/update zip files. Name them using today's date.
zip -q ${PUBLISH_DATE}-ccp_rt_line_segs.zip rt_line_segs.* LICENSE.txt
zip -q ${PUBLISH_DATE}-ccp_rt_endpoints.zip rt_endpoints.* LICENSE.txt
zip -q ${PUBLISH_DATE}-ccp_rt_collected.zip rt_collected.* LICENSE.txt

popd &> /dev/null

# *** Publish the Archives

#cd ${BASE_EXPORTS}
pushd ${BASE_EXPORTS} &> /dev/null

# Make sure the access restrictions are current.
CCPBASEDIR=`dirname $PYSERVER_HOME`
CCPBASEDIR=`basename $CCPBASEDIR`
if [[ -d /ccp/bin/ccpdev/private/runic/ccp/dev/cp/htdocs/reports ]];
then
  #/bin/cp -f \
  #  /ccp/bin/ccpdev/private/runic/ccp/dev/cp/htdocs/reports/.htaccess \
  #  ${BASE_REPORTS}
  m4 \
    --define=CCPBASEDIR=$CCPBASEDIR \
    /ccp/bin/ccpdev/private/runic/ccp/dev/cp/htdocs/reports/.htaccess \
    > ${BASE_REPORTS}/.htaccess
  #
  /bin/cp -f \
    /ccp/bin/ccpdev/private/runic/ccp/dev/cp/htdocs/reports/.htpasswd \
    ${BASE_REPORTS}
fi

if ! $PUBLISH_QUARTERLY; then

  # Delete all of yesterdays' exports.
  yesterdays="${EXPORTS_DAILY}/*-ccp_rt_*.zip"
  $DEBUG_TRACE && echo "yesterdays: ${yesterdays}."
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all yesterday exports: ${yesterdays}."
    # NOTE: Since we're using the '*' wildcard, we cannot use quotes '' or "".
    #/bin/ls -la ${yesterdays}
    /bin/rm -f ${yesterdays}
  fi
  yesterdays="${EXPORTS_DAILY}/*-ccp_rt_*.htm"
  $DEBUG_TRACE && echo "yesterdays: ${yesterdays}."
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all yesterdays exports: ${yesterdays}."
    /bin/rm -f ${yesterdays}
  fi
  # Delete all of yesterdays' reports.
  yesterdays="${REPORTS_DAILY}/*-ccp_rt_*.zip"
  $DEBUG_TRACE && echo "yesterdays: ${yesterdays}."
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all yesterday's reports: ${yesterdays}."
    # NOTE: Since we're using the '*' wildcard, we cannot use quotes '' or "".
    #/bin/ls -la ${yesterdays}
    /bin/rm -f ${yesterdays}
  fi
  yesterdays="${REPORTS_DAILY}/*-ccp_rt_*.htm"
  $DEBUG_TRACE && echo "yesterdays: ${yesterdays}."
  if [[ -n "${yesterdays}" ]]; then
    $DEBUG_TRACE && echo "Cleaning up all yesterdays' reports: ${yesterdays}."
    /bin/rm -f ${yesterdays}
  fi

  $DEBUG_TRACE && echo "Moving to daily exports."
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_line_segs.zip \
    ${EXPORTS_DAILY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_line_segs.htm \
    ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.htm

  $DEBUG_TRACE && echo "Moving to daily reports."
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_endpoints.zip \
    ${REPORTS_DAILY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_endpoints.htm \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.htm
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_collected.zip \
    ${REPORTS_DAILY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_collected.htm \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.htm

else

  $DEBUG_TRACE && echo "Moving to quarterly exports."
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_line_segs.zip \
    ${EXPORTS_QUARTERLY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_line_segs.htm \
    ${PREFIX_EXPORTS_QUARTERLY}-ccp_rt_line_segs.htm

  $DEBUG_TRACE && echo "Moving to quarterly reports."
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_endpoints.zip \
    ${REPORTS_QUARTERLY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_endpoints.htm \
    ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_endpoints.htm
  #
  mv ${CCP_EXPORT_WORKING}/${PUBLISH_DATE}-ccp_rt_collected.zip \
    ${REPORTS_QUARTERLY}/
  mv ${CCP_EXPORT_WORKING}/ccp_rt_collected.htm \
    ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_collected.htm

  # Make a link from the daily location.
  /bin/ln -f -s ${PREFIX_EXPORTS_QUARTERLY}-ccp_rt_line_segs.zip \
    ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.zip
  /bin/ln -f -s ${PREFIX_EXPORTS_QUARTERLY}-ccp_rt_line_segs.htm \
    ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.htm
  #
  /bin/ln -f -s ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_endpoints.zip \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.zip
  /bin/ln -f -s ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_endpoints.htm \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.htm
  #
  /bin/ln -f -s ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_collected.zip \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.zip
  /bin/ln -f -s ${PREFIX_REPORTS_QUARTERLY}-ccp_rt_collected.htm \
    ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.htm

  # Update the LICENSE.
  /bin/cp -f \
    ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
    ${EXPORTS_QUARTERLY}
  /bin/cp -f \
    ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/quarterly/README \
    ${REPORTS_QUARTERLY}

fi

# Make well-known links to the new files.
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.zip \
  ${BASE_EXPORTS}/ccp_rt_line_segs.zip
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.htm \
  ${BASE_EXPORTS}/ccp_rt_line_segs.htm
#
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.zip \
  ${EXPORTS_DAILY}/ccp_rt_line_segs.zip
/bin/ln -f -s ${PREFIX_EXPORTS_DAILY}-ccp_rt_line_segs.htm \
  ${EXPORTS_DAILY}/ccp_rt_line_segs.htm

/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.zip \
  ${BASE_REPORTS}/ccp_rt_endpoints.zip
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.htm \
  ${BASE_REPORTS}/ccp_rt_endpoints.htm
#
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.zip \
  ${REPORTS_DAILY}/ccp_rt_endpoints.zip
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_endpoints.htm \
  ${REPORTS_DAILY}/ccp_rt_endpoints.htm

#
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.zip \
  ${BASE_REPORTS}/ccp_rt_collected.zip
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.htm \
  ${BASE_REPORTS}/ccp_rt_collected.htm
#
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.zip \
  ${REPORTS_DAILY}/ccp_rt_collected.zip
/bin/ln -f -s ${PREFIX_REPORTS_DAILY}-ccp_rt_collected.htm \
  ${REPORTS_DAILY}/ccp_rt_collected.htm

# Update the LICENSE.
/bin/cp -f \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
  ${EXPORTS_DAILY}
#
/bin/cp -f \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
  ${REPORTS_DAILY}

# Update the LICENSE.
/bin/cp -f \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
  ${BASE_EXPORTS}
/bin/cp -f \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
  ${BASE_REPORTS}

popd &> /dev/null

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

