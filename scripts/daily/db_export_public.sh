#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script exports non-permissioned SQL seed data for community developers.

# For permissioned SQL seed data, we export an anonymized Shapefile that
# community developers can load (see ccp_export_branches.sh).

# FIXME/BUG nnnn: APRIL2014: This script is incomplete/missing steps.
#        E.g., we need to create an anonymous user and group and
#        make rows in key_value_pair for them, and we need to make
#        a new branch and populate the new_item_policy table, and
#        the geofeature table, etc. See the bottom of the file for
#        a list of steps we need to make easier for a community
#        developer setting up a new installation of Cyclopath.

# *** Check inputs

DBNAME=$1
OUTDIR=$2

__for_testing__='

For copy-pasting:

 DBNAME=ccpv3_demo
 DBNAME=ccpv3_lite
 OUTDIR=/ccp/dev/cycloplan_live/htdocs/exports/devs

For running this script:

 /ccp/dev/cp_cron/scripts/daily/db_export_public.sh \
  ccpv3_demo \
  /ccp/dev/cp_cron/htdocs/exports/devs

'

if [[ -z "$INSTANCE" ]]; then
  echo "ERROR: Please set the INSTANCE env. variable to the db instance"
  exit 1
fi

if [[ -z "$DBNAME" || -z "$OUTDIR" ]]; then
  echo "Usage: $0 DBNAME OUTDIR [arguments to psql]"
  exit
fi
shift 2

# Exit on error
set -e

# *** Make destination directory.

/bin/mkdir -p ${OUTDIR}
/bin/chmod 2775 ${OUTDIR}

# *** Export the schema.

pg_dump -U cycling ${DBNAME} \
  --schema-only \
  --schema=public \
  --schema=${INSTANCE} \
  > ${OUTDIR}/schema.sql

# *** Export non-permissioned (core) data.

# Note that instance data doesn't make sense to export
# because of stack IDs. So any table whose data references
# a stack ID (like key_value_pair, e.g., cp_group_public_id),
# cannot be exported; these tables and data will be recreated
# the hard way.

public_tables="
  -t public.access_infer \
  -t public.access_level \
  -t public.access_scope \
  -t public.access_style \
  -t public.draw_class \
  -t public.draw_param \
  -t public.enum_definition \
  -t public.geofeature_layer \
  -t public.item_type \
  -t public.spatial_ref_sys \
  -t public.tag_preference_type \
  -t public.tiles_mapserver_zoom \
  -t public.travel_mode \
  -t public.upgrade_event \
  -t public.viz \
"

pg_dump -U cycling ${DBNAME} \
  \
  --data-only \
  --disable-triggers \
  --schema=public \
  --schema=${INSTANCE} \
  \
  ${public_tables} \
  \
  > ${OUTDIR}/data.sql

/bin/chmod 664 ${OUTDIR}/*.sql

# ***

# Copy the elevation file(s).

elev_path=/ccp/var/elevation/${INSTANCE}.tif
if [[ -e ${elev_path} ]]; then
  # We don't need to really make a copy, do we? A link should suffice.
  #   /usr/bin/rsync -a ${elev_path} ${OUTDIR}/
  #   /bin/chmod 664 ${OUTDIR}/*.tif
  /bin/rm -f ${OUTDIR}/${INSTANCE}.tif
  /bin/ln -s ${elev_path} ${OUTDIR}/${INSTANCE}.tif
else
  echo "WARNING: No elevation file found: ${elev_path}"
fi

# ***

__fixme_db_export_public_sh__="

# FIXME/BUG nnnn: APRIL2014: Finish implementing a new db setup tool.

Make a script to setup a new Cyclopath database that does the following:

Import the public tables (the ones this script exports)
FIXME: Why is schema.sql empty?
       (2014.04.21: Is this still true? Is this script broken?)

Rebuild constraints (db_load_add_constraints.sql)
  psql -U cycling ccp_anew \
    < scripts/setupcp/db_load_add_constraints.sql

Rebuild views (convenience_views.sql)
  psql -U cycling ccp_anew \
    < scripts/dev/convenience_views.sql

Create the special users and groups,
  and insert appropriate key_value_pair rows

Make a new user for the developer
  psql -U cycling ccp_anew -c \
    \"SELECT cp_user_new('bikes', 'bikesrockpound@cyclopath.org', 'rock!');\"

Setup item policies (new_item_policy_init.py)

Create attributes. See: The minnesota.attribute table

Create tags. MAYBE: Create just the explicit tags we use,
  "city", "county", "township", "closed", "restricted", "disconnected",
  and other tags we use all the time?

Create key_value_pair rows.
  minnesota.key_value_pair
   cp_instance_uuid                                        | 12345678-1234-1234-1234-123456789012
   cp_branch_baseline_id                                   | 2500677
   cp_group_basemap_owners_id_minnesota                    | 2500678
   cp_group_public_id                                      | 2500679
   cp_group_stealth_id                                     | 2506583
   cp_group_session_id                                     | 2506584

MAYBE: Are we missing any other special data?

MAYBE: Do we need to populate upgrade_event with each ID so the
       old schema scripts are ignored?

Make new branch, make the developer an arbiter, and
  add the key_value_pair for the baseline ID (make_new_branch.py)
FIXME: The make-new-branch-and-assign-branch-permissions script
       (make_new_branch.py) should be able to make the branch the baseline
       branch by making a key_val row.

Populate data from a Shapefile (hausdorff_import.py)

"

# ***

