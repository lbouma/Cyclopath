#!/bin/bash

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# *** Debug Options

DEBUG_TRACE=false
DEBUG_TRACE=true

# *** Prerequisites

#OGR2OGR=/ccp/opt/gdal-1.9.0/bin/ogr2ogr
OGR2OGR=/ccp/opt/gdal-1.10.1/bin/ogr2ogr

if [[ ! -x "${OGR2OGR}" ]]; then
  echo "ogr2ogr not found or not executable at ${OGR2OGR}."
  exit
fi

if [[ -z "${INSTANCE}" ]]; then
  echo "Please specify the INSTANCE environment variable."
  exit
fi

if [[ -z "${PYSERVER_HOME}" ]]; then
  #CCP_WORKING=${script_relbase}/../..
  #PYSERVER_HOME=${CCP_WORKING}/pyserver
  echo "Please specify the PYSERVER_HOME environment variable."
  exit
fi

# *** Setup

. ${PYSERVER_HOME}/../scripts/util/ccp_base.sh

# *** Today's Date

#PUBLISH_DATE=`date +%F`
PUBLISH_DATE=`date +%Y.%m.%d`

# On the first day of every third month, we'll capture a quarterly backup.
PUBLISH_QUARTERLY=false
DATE_DAY=`echo $PUBLISH_DATE | /bin/sed -r 's/([0-9]{4}).([0-9]{2}).([0-9]{2})/\3/'`
DATE_MON=`echo $PUBLISH_DATE | /bin/sed -r 's/([0-9]{4}).([0-9]{2}).([0-9]{2})/\2/'`
if [[ $DATE_DAY == '01' ]]; then
  if [[    $DATE_MON == '03' \
        || $DATE_MON == '06' \
        || $DATE_MON == '09' \
        || $DATE_MON == '12' ]]; then
    PUBLISH_QUARTERLY=true
  fi
fi

# *** Runtime Options

# We expect that ccp_base.sh set the name of the database used by this
# installation.
if [[ -z "${CCP_DB_NAME}" ]]; then
  echo "Unable to figure out the name of the database from ${PYSERVER_HOME}/CONFIG."
  exit
fi

# *** Setup directories and paths

# Since the daily.runic.sh script runs scripts in parallel, we need a unique
# location to avoid overlapped problems.
unique_tmp_location=$1
if [[ -z ${unique_tmp_location} ]]; then
  echo "WARNING: unique_tmp_location not specified"
  CCP_EXPORT_TEMPDIR=ccp_export-${PUBLISH_DATE}
  CCP_EXPORT_WORKING=/tmp/${CCP_EXPORT_TEMPDIR}
else
  CCP_EXPORT_WORKING=${unique_tmp_location}
  if [[ -e ${unique_tmp_location} ]]; then
    echo "WARNING: unique_tmp_location already in use: ${unique_tmp_location}"
  fi
fi
/bin/mkdir -p ${CCP_EXPORT_WORKING}

# SYNC_ME: BASE_EXPORTS/BASE_REPORTS ccp_export*.sh/daily.runic.sh.
BASE_EXPORTS=${PYSERVER_HOME}/../htdocs/exports
DEVS_EXPORTS=${PYSERVER_HOME}/../htdocs/exports/devs
BASE_REPORTS=${PYSERVER_HOME}/../htdocs/reports

/bin/mkdir -p ${BASE_EXPORTS}
if [[ ! -d ${BASE_EXPORTS} ]]; then
  echo "Cannot create ${BASE_EXPORTS} or not a directory."
  exit
fi
#
/bin/mkdir -p ${DEVS_EXPORTS}
if [[ ! -d ${DEVS_EXPORTS} ]]; then
  echo "Cannot create ${DEVS_EXPORTS} or not a directory."
  exit
fi
#
/bin/mkdir -p ${BASE_REPORTS}
if [[ ! -d ${BASE_REPORTS} ]]; then
  echo "Cannot create ${BASE_REPORTS} or not a directory."
  exit
fi

EXPORTS_DAILY=${BASE_EXPORTS}/daily
/bin/mkdir -p ${EXPORTS_DAILY}
/bin/chmod 2775 ${EXPORTS_DAILY}
PREFIX_EXPORTS_DAILY=${EXPORTS_DAILY}/${PUBLISH_DATE}
/bin/cp -f ${PYSERVER_HOME}/../scripts/daily/export_docs/daily/README \
  ${EXPORTS_DAILY}/
#
REPORTS_DAILY=${BASE_REPORTS}/daily
/bin/mkdir -p ${REPORTS_DAILY}
/bin/chmod 2775 ${REPORTS_DAILY}
PREFIX_REPORTS_DAILY=${REPORTS_DAILY}/${PUBLISH_DATE}
/bin/cp -f ${PYSERVER_HOME}/../scripts/daily/export_docs/README \
  ${REPORTS_DAILY}/

EXPORTS_QUARTERLY=${BASE_EXPORTS}/quarterly
/bin/mkdir -p ${EXPORTS_QUARTERLY}
/bin/chmod 2775 ${EXPORTS_QUARTERLY}
PREFIX_EXPORTS_QUARTERLY=${EXPORTS_QUARTERLY}/${PUBLISH_DATE}
/bin/cp -f ${PYSERVER_HOME}/../scripts/daily/export_docs/quarterly/README \
  ${EXPORTS_QUARTERLY}/
#
REPORTS_QUARTERLY=${BASE_REPORTS}/quarterly
/bin/mkdir -p ${REPORTS_QUARTERLY}
/bin/chmod 2775 ${REPORTS_QUARTERLY}
PREFIX_REPORTS_QUARTERLY=${REPORTS_QUARTERLY}/${PUBLISH_DATE}
/bin/cp -f ${PYSERVER_HOME}/../scripts/daily/export_docs/README \
  ${REPORTS_QUARTERLY}/

# *** Make the Metadata

#cd ${CCP_EXPORT_WORKING}
pushd ${CCP_EXPORT_WORKING} &> /dev/null

CCP_DB_NAME=${CCP_DB_NAME} \
INSTANCE=${INSTANCE} \
CCP_EXPORT_DATE=${PUBLISH_DATE} \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/gen_metadata.sh

# Copy the LICENSE.
/bin/cp -f \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/LICENSE.txt \
  .

popd &> /dev/null

