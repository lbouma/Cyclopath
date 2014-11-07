#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script loads a database dump. No sanity checks. Use with care.

# Usage:
#
#   ./db_load.sh my_ccpv2.dump sql_dest_db
#   ./db_load.sh my_ccpv1.dump sql_dest_db v1
#
# To make a dump for PostGIS 2.x:
#
#   pg_dump -U cycling -Fc -b -v -f "/ccp/var/dbdumps/{target}.dump" {db_name}
#
# To be extra safe, rename the target db before reloading:
#
#   psql -U postgres postgres -c "ALTER DATABASE {nom} RENAME TO {TBD_nom}"
#

__cxpx__='''

cd /ccp/dev/cp/scripts
nohup ./db_load.sh /ccp/var/.dbdumps.daily/ccpv3_live.dump ccpv3_demo \
  | tee /ccp/var/log/daily/2013.10.09-db_load-ccpv3_demo.log 2>&1 &

'''

set -e

dump_file=$1
dest_db=$2
load_style=$3

# DEVS/CAVEAT: This script assumes: psql -h localhost -p 5432

if [[ -z "$load_style" ]]; then
  load_style="v2"
fi

if [[ -z "$dump_file" || -z "$dest_db" ]]; then
  echo "Usage: $0 dump_file psql_dest [v1|V2]"
  exit
fi

script_relbase=$(dirname $0)
source ${script_relbase}/util/ccp_base.sh
if [[ ! -d ${PYSERVER_HOME} ]]; then
  echo "Unexpected: Where's pyserver/?"
  exit 1
fi

#
#if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
#  # echo Ubuntu! Debian!
#  hostos='deb'
#elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
#  # echo Red Hat! Fedora!
#  hostos='red'
#else
#  echo "Unknown OS: `cat /proc/version`"
#  #echo Unknown OS "`cat /proc/version`"
#  return 0
#fi;

postgis_home="/ccp/opt/postgis"

POSTGIS_MAJOR_VERSION=0
POSTGIS_MINOR_VERSION=0

# FIXME: Close Bug 1999 (about dumping a psql 8.2 database and loading into an 
#                        8.3 db "fails" (by which I [lb] mean the database gets
#                        loaded, but the nonzero exit status causes this
#                        script to stop (so it doesn't call analyze after
#                        pg_restore). See the bug for more; this script
#                        currently works fine for 8.2 -> 8.2, but it does not
#                        work for 8.2 -> 8.3 (though you can just run it anyway
#                        and do the analyze manually).

if [[ "$load_style" = "v1" ]]; then

  echo "WARNING: Obsolete: Loading database with pg_restore."

  # Make sure to create a _truly_ empty database by specifying template0 
  # (just in case template1 has been modified)
  CMD_CREATE="createdb -U postgres -e --template template0 $dest_db"
  CMD_RESTORE="
    pg_restore -U postgres -d $dest_db --disable-triggers $dump_file"
  CMD_ANALYZE="psql -U postgres --no-psqlrc -d $dest_db -c \"ANALYZE;\""
  CMD_CLEANUP=""

elif [[ "$load_style" = "v2" ]]; then

  echo "Loading database with postgis_restore."

  CMD_CREATE=""

  # PostGIS 1.5.3.
  # 2012.03.05: Why did it take 'til now for PostGIS to complain about template
  # not being specified?
  #  createdb: database creation failed: 
  #    ERROR: new encoding (UTF8) is incompatible with the encoding of the 
  #    template database (SQL_ASCII) 
  #    HINT: Use the same encoding as in the template database, or use 
  #    template0 as template. 
  #    Database creation failed

  . $postgis_home/Version.config
  #echo "POSTGIS_MAJOR_VERSION: $POSTGIS_MAJOR_VERSION"
  #echo "POSTGIS_MINOR_VERSION: $POSTGIS_MINOR_VERSION"
  #echo "POSTGIS_MICRO_VERSION: $POSTGIS_MICRO_VERSION"

# FIXME: On huffy, postgis_restore sends --no-psqlrc to createdb, which rejects
# it. I think this was working find on pluto, though? Trying without it...

  # 2013.10.31: Still on pgsq 8.4 but now on pgis 2.0.
  # BUG nnnn: Postgres 9.0 and PostGIS 2.1, which is complains if not >= 9.

  if [[ $POSTGIS_MAJOR_VERSION -eq 2 && $POSTGIS_MINOR_VERSION -eq 0 ]]; then

    # PostGIS 2.x is markedly different than 1.x. In 1.x, we just called
    # the postgis_restore script; in 2.x, we created the database ourselves
    # and run a dozen setup scripts, and then we call the restore script.
    # So this is the last command we'll run, after a bunch of others.

    CMD_RESTORE="\
      $postgis_home/utils/postgis_restore.pl \"$dump_file\"
        | psql -U postgres $dest_db"

  elif [[ $POSTGIS_MAJOR_VERSION -eq 1 && $POSTGIS_MINOR_VERSION -eq 5 ]]; then

    # Skipping: --no-psqlrc"

    CMD_RESTORE="\
      PGUSER=postgres sh $postgis_home/utils/postgis_restore.pl
        $postgis_home/postgis/postgis.sql $dest_db $dump_file -E UTF8
        -T template0"

  # PostGIS 1.3.x defines different names.
  elif [[ $REL_MAJOR_VERSION -eq 1 && $REL_MINOR_VERSION -eq 3 ]]; then

    CMD_RESTORE="\
      sh $postgis_home/utils/postgis_restore.pl
        $postgis_home/lwpostgis.sql $dest_db $dump_file -E=UTF8 -U postgres
        -T template0"

  else

    POSTGIS_VERSION="$REL_MAJOR_VERSION.$REL_MINOR_VERSION.$REL_MICRO_VERSION"
    echo "ERROR: Unknown postgis version:"
    echo "`cat $postgis_home/Version.config`"

    exit 1

  fi

  CMD_ANALYZE="psql -U postgres --no-psqlrc -d $dest_db -c \"VACUUM ANALYZE;\""
  CMD_CLEANUP="/bin/rm -f $dump_file.ascii $dump_file.list"

else

  echo "ERROR: Unknown option '$load_style'"
  exit 1

fi

# We don't care if dropdb fails, so we either need to prevent script 
# termination with 'set +e' or we can just use IF EXISTS. But if we send a SQL
# statement, we want to make sure postgres doesn't load our ~/.psqlrc file, 
# which might try to set search_path to minnesota, which will also cause psql 
# to output an ERROR.
# Either of these works:
#CMD_DROP="dropdb -U postgres -e $dest_db > /dev/null 2>&1"
CMD_DROP="\
  echo 'DROP DATABASE IF EXISTS ${dest_db};'
    | psql -U postgres --no-psqlrc |& grep '^ERROR:'"

# NOTE: dropdb returns an error if the database does not exist but also 
#       if it's in use. We can ignore the former error but not the latter.
#       So we can't call 'set +e' and then dropdb. Instead, eval the command 
#       and grep for error:
#   ERROR:  database "ccpv2_tmp" is being accessed by other users
#   DETAIL:  There are 1 other session(s) using the database.

echo
echo $CMD_DROP
echo
set +e
DROP_RESP=`eval $CMD_DROP`
set -e
if [[ -n "$DROP_RESP" ]]; then
  # Some possible errors:
  #  - "ERROR: There was an error. Aborting. (ERROR:  database "ccpv2_new"
  #     is being accessed by other users)"
  echo "ERROR: There was an error. Aborting. ($DROP_RESP)"
  exit 1
fi

if [[ -n "$CMD_CREATE" ]]; then
  echo 
  echo $CMD_CREATE
  echo
  eval $CMD_CREATE
fi

if [[ $POSTGIS_MAJOR_VERSION -eq 2 && $POSTGIS_MINOR_VERSION -eq 0 ]]; then

  # From: http://www.postgis.org/documentation/manual-svn/postgis_installation.html#create_new_db
  #  and: http://www.postgis.org/documentation/manual-svn/postgis_installation.html#create_new_db_extensions

  # $CMD_DROP ran, e.g.:
  #   dropdb -U postgres $dest_db

  # $CMD_CREATE was not run above for PostGIS 2.x.

  createdb -U postgres -e --template template0 $dest_db
  
  # 2014.01.17: In recent Postgreses, 9.x+, the plpgsql language is included by
  # default, and trying to create it again fails.
  if [[ $POSTGRES_MAJOR -lt 9 ]]; then
    createlang -U postgres plpgsql $dest_db
  fi

  # Now load PostGIS object and function definitions into the database by
  # running a bunch of postgis scripts.

  psql -U postgres -d $dest_db -f $postgis_home/postgis/postgis.sql
  # For a complete set of EPSG coordinate system definition identifiers, you
  # can also load the spatial_ref_sys.sql definitions file and populate the
  # spatial_ref_sys table. This will permit you to perform ST_Transform()
  # operations on geometries.
  psql -U postgres -d $dest_db -f $postgis_home/spatial_ref_sys.sql
  # If you wish to add comments to the PostGIS functions, the final step is
  # to load the postgis_comments.sql into your spatial database. The comments
  # can be viewed by simply typing \dd [function_name] from a psql terminal
  # window.
  psql -U postgres -d $dest_db -f $postgis_home/doc/postgis_comments.sql
  # Install raster support
  psql -U postgres -d $dest_db -f $postgis_home/raster/rt_pg/rtpostgis.sql
  # Install raster support comments. This will provide quick help info for
  # each raster function using psql or PgAdmin or any other PostgreSQL tool
  # that can show function comments
  psql -U postgres -d $dest_db -f $postgis_home/doc/raster_comments.sql
  # Install topology support
  psql -U postgres -d $dest_db -f $postgis_home/topology/topology.sql
  # Install topology support comments. This will provide quick help info for
  # each topology function / type using psql or PgAdmin or any other
  # PostgreSQL tool that can show function comments
  psql -U postgres -d $dest_db -f $postgis_home/doc/topology_comments.sql

  # [lb]: The instructions say Postgres < 9.1 but CREATE EXTENSION 
  #       is for sure a 9.1 function.
  #
  # The core postgis extension installs PostGIS geometry, geography, raster,
  # spatial_ref_sys and all the functions and comments with a simple:
  # BUG nnnn: Postgres 9.1 and PostGIS 2.1
  # Not yet: psql -U postgres -d $dest_db -c "CREATE EXTENSION postgis;"
  # Topology is packaged as a separate extension and installable with command
  # psql -U postgres -d $dest_db -c "CREATE EXTENSION postgis_topology;"

  # If you plan to restore an old backup from prior versions in this new db:
  #
  # NOTE: There's also: $postgis_home/regress/legacy.sql
  # -rw-rw---- 1 you cyclop  54K Oct 31 13:02 ./postgis/legacy.sql
  # -rw-r----- 1 you cyclop 4.8K Nov 25  2012 ./regress/legacy.sql
  #
  psql -U postgres -d $dest_db -f $postgis_home/postgis/legacy.sql

  # I didn't see this in the PostGIS instructions, but the new tables
  # are owned by postgres -- obviously because we ran the import script
  # under the postgres superuser. Do a \d in postgres to view all the
  # relations, and then look for relations owned by postgres and not cycling.
  # See: http://workshops.boundlessgeo.com/postgis-intro/security.html
  psql -U postgres -d $dest_db \
    -c "GRANT SELECT ON TABLE geography_columns TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT SELECT ON TABLE geometry_columns TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT SELECT ON TABLE spatial_ref_sys TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT SELECT ON TABLE raster_columns TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT SELECT ON TABLE raster_overviews TO cycling;"
  #
  psql -U postgres -d $dest_db \
    -c "GRANT ALL ON SCHEMA topology TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT ALL ON TABLE topology.layer TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT ALL ON TABLE topology.topology TO cycling;"
  psql -U postgres -d $dest_db \
    -c "GRANT ALL ON TABLE topology.topology_id_seq TO cycling;"

  # Test your new database!
  #  psql -U cycling -d $dest_db -c "SELECT postgis_full_version();"

  # BUG nnnn: Remove deprecated PostGIS 1.x cruft.
  # FIXME: Cyclopath has a constraint on legacy PostGIS:
  #        enforce_valid_loop in geofeature.
  # # You can later run uninstall_legacy.sql to get rid of the deprecated
  # # functions after you are done with restoring and cleanup.
  #psql -U postgres -d $dest_db -f $postgis_home/postgis/uninstall_legacy.sql

fi

echo
echo Restoring the database.
echo NOTE: This script does not verify success. You must do it.
echo 
echo $CMD_RESTORE
echo
eval $CMD_RESTORE

echo Restore: Success!

echo
echo Analyzing the database. 
echo Please be patient......
echo 
echo $CMD_ANALYZE
echo
eval $CMD_ANALYZE

if [[ -n "$CMD_CLEANUP" ]]; then
  echo
  echo Cleaning up.
  echo 
  echo $CMD_CLEANUP
  echo
  eval $CMD_CLEANUP
fi

exit 0

# ***

