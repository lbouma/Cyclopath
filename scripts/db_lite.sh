#!/bin/bash

# Copyright (c) 2006-2012, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script copies one database to another.

# WARNING: This script will drop the target database, if it exists.

# Normal usage.
# 1. Make a 'lite' dump -- this dumps most tables but ignores some apache and
#    other stats tables, then reloads the schema for the missing tables, and
#    then dumps the resulting 'lite' database.
# ./db_lite.sh --verbose --src-db=ccpv1_live --dst-db ccpv1_lite \
#                        --dst-dump=/ccp/var/dbdumps/ccpv1_lite.dump
# 2. To load the lite dump, use db_load.sh. Note that you shouldn't bother
#    using db_lite.sh unless your dump is a primitive lite dump.
# ./db_load.sh /ccp/var/dbdumps/ccpv1_lite.dump ccpv1_lite

# It is discouraged to import using this script. If you have a lite DB created
# by this script, use db_load.sh. You could try to use this script with a lite
# database that's _missing_ tables, though, and it'll try to remake the
# missing schema table:
#   ./db_lite.sh --verbose --src-dump=/ccp/var/dbdumps/ccpv3_lite.dump \
#                          --dst-db ccpv3 --src-host huffy --src-db=ccpv3_live

__ignore_me__2013_10_31__ () {

  # Ideally, this is the command to run on the production server.
  # But PostGIS 2 is a different beast.
  #
  # So, save this for later, but this is a good example command:
  LOG_FILE=/ccp/var/log/daily/2013.11.27.db_lite-ccpv3_demo.log
  /ccp/dev/cp/scripts/db_lite.sh                        \
    --verbose                                           \
    --force-drop                                        \
    --src-db=ccpv3_demo                                 \
    --src-instances="minnesota"                         \
    --src-forgotten="colorado"                          \
    --dst-db=lite_ccpv3                                 \
    --dst-dump=/ccp/var/dbdumps/lite_ccpv3.dump         \
    > ${LOG_FILE} 2>&1


  # 2013.11.01: This exports from the server, running PostGIS 1.5,
  #             into a dump format that PostGIS 2.x can use.
  #
  # On production server:
  LOG_FILE=/ccp/var/log/daily/2013.10.31.db_lite-ccpv3_demo.log
  /ccp/dev/cp/scripts/db_lite.sh                        \
    --verbose                                           \
    --force-drop                                        \
    --src-db=ccpv3_demo                                 \
    --src-instances="minnesota"                         \
    --src-forgotten="colorado"                          \
    --dst-db=lite_ccpv3                                 \
    --dst-dump=/ccp/var/dbdumps/lite_ccpv3.dump         \
    --postgis-src=1                                     \
    --postgis-dst=2                                     \
    > ${LOG_FILE} 2>&1
  #
  # On development machine:
  cd /ccp/var/dbdumps
  scp $lbpr:/ccp/var/dbdumps/lite_ccpv3.dump ccpv3_lite-pgis2.dump
  cd /ccp/dev/cp/scripts
  ./db_load.sh /ccp/var/dbdumps/ccpv3_lite-pgis2.dump ccpv3_demo

}

# ***

set -e

# ***

DEBUG_TRACE=false
DEBUG_TRACE=true

# If the user is running from a terminal (and not from cron), always be chatty.
if [[ "dumb" != "${TERM}" ]]; then
  DEBUG_TRACE=true
fi

# ***

# We're in the scripts/ dir, and we want to load something from scripts/dev/.

# If you cxpx this code to a terminal (e.g., for testing), $0 is your shell.
if [[ $0 == "-bash" || $0 == "-tcsh" ]]; then
  # Assume we're already in the scripts/ directory.
  script_relbase=$PWD
  #script_absbase=`pwd -P`
  # 2016-07-18: readlink is preferred method nowadays...
  #SCRIPT_DIR=$(dirname $(readlink -f $0))
else
  # Otherwise, $0 is the path to db_lite.sh. Trim the filename to get the dir.
  script_relbase=$(dirname $0)
fi

if [[    ! -e $script_relbase/dev/db_lite_defs.sh \
      || ! -e $script_relbase/util/ccp_base.sh ]]; then
  echo "ERROR: db_lite_defs.sh and/or ccp_base.sh not found"
  exit 1
fi

. $script_relbase/dev/db_lite_defs.sh

PYSERVER_HOME=
. ${script_relbase}/util/ccp_base.sh

if [[ -z "${CCP_WORKING}" || -z "${PYSERVER_HOME}" ]]; then
  echo "ERROR: Missing CCP_WORKING and/or PYSERVER_HOME."
fi

# *** CLI Options

# The source database might be live on a psql server...
SRC_HOST=localhost
SRC_DB=""
# ... or it might just be a database dump.
SRC_DUMP=""

# The destination is a database on the local host.
DST_DB=""
# And might also include a dump file we should make.
DST_DUMP=""

# SYNC_ME: This is the default PostGIS version.
POSTGIS_SRC="2"
POSTGIS_DST="2"

FORCE_DROP=false

# *** Well Known Names

DB_LOAD_SH=$script_relbase/db_load.sh

# Where to store database dumps on your machine
CCP_DBDUMPS=/ccp/var/dbdumps

# SYNC_ME: This is the production server's name and database name.
# NO: Should probably not peg the production server to run this script.
#      PROD_HOST=itamae
#      PROD_DB=ccpv1_live
#
# MAGIC_NUMBER: The production server and database. Just so this script
#               can yell at you if you try to overwrite it.
# FIXME: These values should come from a conf file and not be hard coded here.
PROD_HOST=runic
PROD_DB=ccpv3_live
#
# FIXME: This should be in, what, a Bash CONFIG file? that each
#        Cyclopath dev has to customize for their own instances.
# MAGIC_NUMBER: These are the names of your install's instances.
DB_INSTANCES="minnesota colorado"

VERBOSE=false

# ***

exit_on_usage () {
  echo "$0: Usage: db_lite [opts]"
  echo "Try 'db_lite --help' for more."
  exit 1
}

# ***

while [[ "$1" != "" ]]; do
  case $1 in
    #
    --src-host)
      SRC_HOST=$2
      shift 2
      ;;
    --src-host=?*)
      SRC_HOST=${1#--src-host=}
      shift
      ;;
    #
    --src-db)
      SRC_DB=$2
      shift 2
      ;;
    --src-db=?*)
      SRC_DB=${1#--src-db=}
      shift
      ;;
    #
    --src-instances)
      SRC_INSTANCES=$2
      shift 2
      ;;
    --src-instances=?*)
      SRC_INSTANCES=${1#--src-instances=}
      shift
      ;;
    #
    --src-forgotten)
      SRC_FORGOTTEN=$2
      shift 2
      ;;
    --src-forgotten=?*)
      SRC_FORGOTTEN=${1#--src-forgotten=}
      shift
      ;;
    #
    --src-dump)
      SRC_DUMP=$2
      shift 2
      ;;
    --src-dump=?*)
      SRC_DUMP=${1#--src-dump=}
      shift
      ;;
    #
    --dst-db)
      DST_DB=$2
      shift 2
      ;;
    --dst-db=?*)
      DST_DB=${1#--dst-db=}
      shift
      ;;
    #
    --dst-dump)
      DST_DUMP=$2
      shift 2
      ;;
    --dst-dump=?*)
      DST_DUMP=${1#--dst-dump=}
      shift
      ;;
    #
    --postgis-src)
      POSTGIS_SRC=$2
      shift 2
      ;;
    --postgis-src=?*)
      POSTGIS_SRC=${1#--postgis-src=}
      shift
      ;;
    #
    --postgis-dst)
      POSTGIS_DST=$2
      shift 2
      ;;
    --postgis-dst=?*)
      POSTGIS_DST=${1#--postgis-dst=}
      shift
      ;;
    #
    --force-drop)
      FORCE_DROP=true
      shift
      ;;
    #
    --verbose)
      VERBOSE=true
      shift
      ;;
    #
    --help)
      echo "$0: Usage: db_clone [opts]"
      echo ""
      echo "Where [opts] is one or more of the following switches:"
      echo "  --src-host={hostname}       [default: 'localhost']"
      echo "  --src-db={database-name}    source database name"
      echo "  --src-instances={instances} only dump instance and public schema"
      echo "  --src-forgotten={instances} must also specify forgotten schemas"
      echo "  --src-dump={dumpfile}       source dumpfile, instead of db name"
      echo "  --dst-db={database-name}    destination database name"
      echo "  --dst-dump={dumpfile}       if specified, make lite dump"
      echo "  --postgis-src={1|2}         source postgis version [default: 2]"
      echo "  --postgis-dst={1|2}         destination postgis version [default: 2]"
      echo "  --force-drop                don't prompt if dst-db exists"
      echo "  --verbose                   "
      echo
      exit 1
      ;;
    #
    --*[^=]*)
      echo "Confused: ${1}"
      exit_on_usage
      ;;
    #
    *)
      echo "Confused: ${1}"
      exit_on_usage
      ;;
    #
  esac
done

if [[ "${SRC_DB}" != "" && "${SRC_DUMP}" != "" ]]; then
  echo "Please specify only the source database or dump file, but not both."
  echo
  exit_on_usage
fi

if [[ "${SRC_HOST}" != "localhost" && "${SRC_DUMP}" != "" ]]; then
  echo "This script can only load dump files from the host machine."
  echo
  exit_on_usage
fi

if [[ -z "${SRC_DB}" && -z "${SRC_DUMP}" ]]; then
  echo "Please specify a source database or a source dump file."
  echo
  exit_on_usage
fi

if [[ -z "${DST_DB}" ]]; then
  echo "Please specify a destination database."
  echo
  exit_on_usage
fi

if $VERBOSE; then
  DEBUG_TRACE=true
fi

# ***

$DEBUG_TRACE && echo
$DEBUG_TRACE && echo "Copying db $SRC_HOST:$SRC_DB to local db $DST_DB."
$DEBUG_TRACE && echo

if ! ${FORCE_DROP}; then
  # MAYBE: Check that the database actually exists and only prompt if so.
  echo -n "This will destroy database '$DST_DB'. Are you sure? (y/n) "
  read sure
  if [[ "$sure" != "y" ]]; then
    echo "Aborting."
    exit 1
  fi
fi

# ***

if [[ `hostname` == "${PROD_HOST}" && "${DST_DB}" == "${PROD_DB}" ]]; then
  # 2012.10.04: [lb] does like [rp]'s sense of humour. I like this warning txt!
  echo
  echo "WARNING WARNING WARNING!!!"
  echo "You are about to destroy the production database!"
  echo
  echo "Are you sure you want to DESTROY THE PRODUCTION DATABASE!?"
  echo
  echo "If you really want this, type 'destroy the production database'."
  echo
  echo -n "> "
  read sure
  if [[ "$sure" != "destroy the production database" ]]; then
    echo "Aborting."
    exit 1;
  fi
fi

# ***

PG_HOST=""
if [[ "$SRC_HOST" != "localhost" ]]; then
  PG_HOST="-h ${SRC_HOST}"
fi

# ***

# 2013.02.01: Option to make extra-lite by dumping just one instance
#             (e.g., so we can skip the 'colorado' instance).
# Add the public instance to the list of instances.
if [[ -n "${SRC_INSTANCES}" ]]; then
  # The user used --src-instances.
  ALL_INSTANCES="public ${SRC_INSTANCES}"
  # Update DB_INSTANCES to the user's chosen instances, excluding public.
  # We use the list to drop tables from the destination database. So, I guess,
  # it doesn't really matter that we set it, but what the hay.
  DB_INSTANCES=${SRC_INSTANCES}
  if [[ -z "${SRC_FORGOTTEN}" ]]; then
    echo "ERROR: --src-instances requires --src-forgotten"
    exit 1
  fi
else
  # The user did not specify --src-instances, so include 'em all.
  ALL_INSTANCES="public ${DB_INSTANCES}"
  # We don't need to touch DB_INSTANCES.
  SRC_FORGOTTEN=""
fi

# Assemble the -n (--schema) switches for pg_dump.
SRC_SCHEMAS=""
for INSTANCE in $ALL_INSTANCES; do
  # This is, e.g., "-n public -n minnesota". And -n same as --schema=.
  SRC_SCHEMAS="-n ${INSTANCE} ${SRC_SCHEMAS}"
done

# ***

# Dump the database.

LITE_DUMP_DATA=""

if [[ "${SRC_DB}" != "" ]]; then

  $DEBUG_TRACE && echo
  $DEBUG_TRACE && echo "Dumping source database..."

  LITE_DUMP_DATA=${CCP_DBDUMPS}/${SRC_DB}-lite-data.dump

  if [[ -e ${LITE_DUMP_DATA} ]]; then
    echo
    echo "WARNING: Overwriting existing lite dump data: ${LITE_DUMP_DATA}"
    echo
  fi

  $DEBUG_TRACE && echo "Dumping tables: schemas: $SRC_SCHEMAS"

  if [[ ${POSTGIS_SRC} == "2" ]]; then
    # PostGIS 2.0, per:
    # http://www.postgis.org/documentation/manual-svn/postgis_installation.html#hard_upgrade
    # include binary blobs (-b) and verbose (-v) output
    pg_dump \
      ${PG_HOST} \
      -U cycling \
      ${SRC_SCHEMAS} \
      -Fc -b -v -f "${LITE_DUMP_DATA}" \
      ${CCP_LITE_EXCLUDE_TABLES} \
      ${SRC_DB}
  else
    if [[ ${POSTGIS_SRC} != "1" ]]; then
      echo
      echo "WARNING: Unknown PostGIS version requested: ${POSTGIS_SRC}"
      echo
    fi
    pg_dump \
      ${PG_HOST} \
      -U cycling ${SRC_DB} \
      ${SRC_SCHEMAS} \
      -Fc -E UTF8 \
      ${CCP_LITE_EXCLUDE_TABLES} \
      > ${LITE_DUMP_DATA}
  fi
  exit_on_last_error $? "pg_dump: -U cycling ${SRC_DB} ${SRC_SCHEMAS}"
  SRC_DUMP=${LITE_DUMP_DATA}
fi

# ***

# Load the (possibly lite) database. (If the caller specified SRC_DB, then we
# dumped SRC_DB and used --exclude-tables, so the dump is already lite, but if
# the caller specified SRC_DUMP, then we're possibly loading a full dump (in
# which case we'll make it lite when we make sure certain tables are dropped).)

$DEBUG_TRACE && echo
$DEBUG_TRACE && echo "Loading dumped database..."

${DB_LOAD_SH} ${SRC_DUMP} ${DST_DB}

# ***

# Restore tables (possibly) omitted from the dump (or drop tables we don't care
# about, to save space).
# NOTE: See the anonymizer scripts for dropping data we wish not to see; this
#       script just concerns itself with saving hard drive space, for those of
#       us with laptops with limited space, or those of us who want not to wait
#       as long for a db_load to complete.

$DEBUG_TRACE && echo
$DEBUG_TRACE && echo "Restoring -lost- tables..."

LITE_DUMP_SCHEMA=${CCP_DBDUMPS}/${SRC_DB}-lite-omit.dump

$DEBUG_TRACE && echo

# Dump the schema of the tables we're missing.
# CAVEAT: [lb] finds that the -n switch doesn't seem to work with pg_dump. We
#         specify it anyway, but we need to make the missing schemas for
#         pg_restore to work.
if [[ "${SRC_DB}" != "" ]]; then
  $DEBUG_TRACE && echo "Making schema dump of missing tables: ${SRC_SCHEMAS}"
  # NOTE: Not checking ${POSTGIS_DST/SRC} == "2", because we don't need to do the
  #       "custom-format" dump that postgis_restore.pl requires.
  pg_dump \
    ${PG_HOST} \
    -U cycling ${SRC_DB} \
    ${SRC_SCHEMAS} \
    -Fc -E UTF8 \
    --schema-only \
      ${CCP_LITE_INCLUDE_TABLES} \
      ${CCP_LITE_INCLUDE_SEQS} \
    > ${LITE_DUMP_SCHEMA}
  exit_on_last_error $? "pg_dump: ${SRC_DB} ${SRC_SCHEMAS} --schema-only"
fi

# Make sure the tables are really deleted.
$DEBUG_TRACE && echo "Dropping missing tables from instance schema."
# NOTE: Redirecting to stderr to /dev/null since psql NOTICEs us for
# mundane things, like a table not existing, even though we use IF
# EXISTS.
#
# NOTE: We expect DB_INSTANCES to be a space-delimited list of schema names.
#       If the list was an array, there's a different way to iterate, e.g.,
#         DB_INSTANCES=("minnesota" "colorado");
#         for arr_index in ${!DB_INSTANCES[*]}; do
#           db_instance=${DB_INSTANCES[$arr_index]}
#           ...
for db_instance in ${DB_INSTANCES}; do
  $DEBUG_TRACE && echo "... dropping missing tables from $DST_DB.$db_instance."
  for table in ${CCP_LITE_IGNORE_TABLES_SCHEMA}; do
    psql -U cycling ${DST_DB} --no-psqlrc --quiet \
      -c "DROP TABLE IF EXISTS ${db_instance}.${table} CASCADE;" \
      &> /dev/null
    exit_on_last_error $? "psql: DROP TABLE ${db_instance}.${table}"
  done
  # In case the table was already dropped, make sure the sequence was,
  # too, otherwise pg_restore will complain that something already
  # exists.
  for seq in ${CCP_LITE_IGNORE_SEQS_SCHEMA}; do
    psql -U cycling ${DST_DB} --no-psqlrc --quiet \
      -c "DROP SEQUENCE IF EXISTS ${db_instance}.${seq};" \
      &> /dev/null
    exit_on_last_error $? "psql: DROP SEQUENCE ${db_instance}.${seq}"
  done
done
$DEBUG_TRACE && echo "Dropping missing tables from public schema."
for table in ${CCP_LITE_IGNORE_TABLES_PUBLIC}; do
  psql -U cycling ${DST_DB} --no-psqlrc --quiet \
    -c "DROP TABLE IF EXISTS public.${table} CASCADE;" \
    &> /dev/null
  exit_on_last_error $? "psql: DROP TABLE ${db_instance}.${table}"
done
for table in ${CCP_LITE_IGNORE_SEQS_PUBLIC}; do
  psql -U cycling ${DST_DB} --no-psqlrc --quiet \
    -c "DROP SEQUENCE IF EXISTS public.${table};" \
    &> /dev/null
  exit_on_last_error $? "psql: DROP SEQUENCE public.${table}"
done
# Load the forgotten tables from the schema dump.
if [[ -e "${LITE_DUMP_SCHEMA}" ]]; then
  # See comment above; pg_dump doesn't seem to honor the -n/--schema switch, so
  # we remake the missing schemas, even though they won't be populated with
  # data.
  $DEBUG_TRACE && echo "Remaking forgotten schemas."
  for SCHEMA_INSTANCE in ${SRC_FORGOTTEN}; do
    psql -U postgres ${DST_DB} --no-psqlrc --quiet \
      -c "CREATE SCHEMA ${SCHEMA_INSTANCE} AUTHORIZATION cycling;" \
      &> /dev/null
    exit_on_last_error $? "psql: CREATE SCHEMA ${SCHEMA_INSTANCE}"
  done
  # Now restore the tables we forgot.
  $DEBUG_TRACE && echo "Remaking forgotten tables."
  pg_restore \
    ${PG_HOST} \
    -U postgres -d ${DST_DB} \
    --schema-only ${LITE_DUMP_SCHEMA}
  exit_on_last_error $? "pg_restore: ${DST_DB} --schema-only"
fi

# 2013.09.16: [lb] is seeing this error in the logs while running
# daily.runic.sh... which is multithreaded, but I'm guess the error
# is coming from this script:
#
# 2013-09-16 16:59:02 CDT ERROR:  relation "geography_columns" already exists
# 2013-09-16 16:59:02 CDT STATEMENT:  CREATE VIEW geography_columns AS
#    SELECT current_database() AS f_table_catalog, n.nspname AS ...

# ***

# Cleanup the dump file.

$DEBUG_TRACE && echo
$DEBUG_TRACE && echo "Cleaning up intermediate files"

/bin/rm -f ${LITE_DUMP_DATA}
/bin/rm -f ${LITE_DUMP_SCHEMA}

# ***

# Create a new, lite(r) dump.

if [[ "${DST_DUMP}" != "" ]]; then

  $DEBUG_TRACE && echo
  $DEBUG_TRACE && echo "Dumping lite dump..."

  # NOTE: Ignoring ${PG_HOST}, since we've been working locally.
  if [[ ${POSTGIS_DST} == "2" ]]; then
    pg_dump \
      -U cycling \
      -Fc -b -v -f "${DST_DUMP}" \
      ${DST_DB}
  else
    if [[ ${POSTGIS_DST} != "1" ]]; then
      echo
      echo "WARNING: Unknown PostGIS version requested: ${POSTGIS_DST}"
      echo
    fi
    pg_dump \
      -U cycling ${DST_DB} \
      ${SRC_SCHEMAS} \
      -Fc -E UTF8 \
      > ${DST_DUMP}
  fi
  exit_on_last_error $? "pg_dump: ${DST_DB} ${SRC_SCHEMAS}"

  /bin/chmod 664 ${DST_DUMP}

fi

# ***

$DEBUG_TRACE && echo
$DEBUG_TRACE && echo "All done!"
$DEBUG_TRACE && echo

