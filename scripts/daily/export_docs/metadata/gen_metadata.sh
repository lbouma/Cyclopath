#!/bin/bash

# Copyright (c) 2012-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# *** Prerequisites

#OGR2OGR=/ccp/opt/gdal-1.9.0/bin/ogr2ogr
OGR2OGR=/ccp/opt/gdal-1.10.1/bin/ogr2ogr

if [[ -z "${INSTANCE}" ]]; then
  echo "Please specify the INSTANCE environment variable."
  exit
fi

if [[ -z "${PYSERVER_HOME}" ]]; then
  #CCP_WORKING=${script_relbase}/../../../..
  #PYSERVER_HOME=${CCP_WORKING}/pyserver
  echo "Please specify the PYSERVER_HOME environment variable."
  exit
fi

# *** Optional definitions

if [[ -z "${CCP_DB_NAME}" ]]; then
  echo "WARNING: No CCP_DB_NAME: loading ccp_base.sh."
  . ${PYSERVER_HOME}/../scripts/util/ccp_base.sh
fi

if [[ -z "${CCP_LAST_UPDATE}" ]]; then
  CCP_LAST_UPDATE=`date +%D`
fi

if [[ -z "${CCP_UPDATE_FREQUENCY}" ]]; then
  CCP_UPDATE_FREQUENCY="Irregular"
fi

if [[ -z "${CCP_EXPORT_DATE}" ]]; then
  CCP_EXPORT_DATE=`date +%Y.%m.%d`
fi

# *** Figure out the latest revision date.

PSQL_REPLY=`psql -U cycling ${CCP_DB_NAME} -q -c \
  "SELECT MAX(id) FROM ${INSTANCE}.revision WHERE id != cp_rid_inf();"`
# This gives, e.g., "max ------- 19160 (1 row)"
#
# Split the line into an array.
IFS=" ()" read -a PSQL_LINES -d "" <<< "${PSQL_REPLY}"
#
# The 3rd element is the revision ID.
CCP_LATEST_REV_ID=${PSQL_LINES[2]}
#
# Get the date of the revision.
# FIXME: The database name is hard-coded.
PSQL_REPLY=`psql -U cycling ${CCP_DB_NAME} -q -c \
  "SELECT timestamp FROM minnesota.revision WHERE id = ${CCP_LATEST_REV_ID};"`
# This gives, e.g., "timestamp -------- 2012-10-19 12:48:00.497855-05 (1 row)"
IFS=" ()" read -a PSQL_LINES -d "" <<< "${PSQL_REPLY}"
# The date is the 3rd element, e.g., "2012-10-19". Convert to MM/DD/YYYY.
CCP_LATEST_REV_DATE=`echo "${PSQL_LINES[2]}" \
  | /bin/sed -r 's#([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})#\2/\3/\1#g'`

# *** Shared definitions

ACCESS_RESTRICTED="
Licensed through GroupLens Research and Regents of the University of Minnesota. Access to this data product is granted to Licensees only.
"
CCP_LICENSE='
Copyright (c) 2008-2012 GroupLens Research and Regents of the University of Minnesota. All rights reserved. This data product may not be used for commercial applications. No part of this data product is allowed to be reproduced without permission and is exclusively distributed by GroupLens Research and the University of Minnesota. <br><br>
GroupLens Research, Regents of the University of Minnesota, and its researchers and staff cannot guarantee the correctness of the data, its suitability for any particular purpose, or the validity of results based on the use of this data product. <br><br>
This data product may be used for any research purposes under the following conditions: <br><br>
* The user may not state or imply any endorsement from GroupLens Research or the University of Minnesota. <br><br>
* The user must acknowledge the use of the data product in publications resulting from the use of the data. The user must also send GroupLens Research an electronic or paper copy of those publications: please email info@cyclopath.org or use <a href="http://www.grouplens.org/contact" target="_blank"> http://www.grouplens.org/contact</a> <br><br>
* The user may not redistribute the data product or any derivative thereof without separate permission. <br><br>
* The user may not use this information for any commercial or revenue-bearing purposes without first obtaining permission from a faculty member of GroupLens Research. <br><br>
Warranties and Disclaimers: This data product is licensed ''as is'' and without any warranty of any kind, either express, implied, or arising by statute, custom, course of dealing, or trade usage. The user, or licensor, specifically disclaims any and all implied warranties or conditions of title, non-infringement, accuracy or completeness, the presence or absence of errors, fitness for a particular purpose, merchantability, or otherwise. <br><br>
Limitation of liability: In no event shall GroupLens Research, Regents of the University of Minnesota, its affiliates or employees be liable to you for any damages arising out of the use or inability to use this data product (including but not limited to loss of data or inaccurate data).
'

# *** METADATA: rt_collected: Unobfuscated Computed-Routes Network

m4 \
 --define=CCP_LAYER_NAME=rt_collected \
 --define=CCP_TITLE="
Cyclopath Unobfuscated Computed-Routes Network
" \
 --define=CCP_ABSTRACT="
A dataset of route requests. Each line segment collection represents a computed route.
" \
 --define=CCP_LAST_UPDATE="${CCP_LAST_UPDATE}" \
 --define=CCP_UPDATE_FREQUENCY="${CCP_UPDATE_FREQUENCY}" \
 --define=CCP_TIME_PERIOD_OF_CONTENT_DATE="" \
 --define=CCP_CURRENTNESS_REFERENCE="
Beginning_Date: 10/03/2007 <br>
Ending_Date: ${CCP_LAST_UPDATE} <br>
The route endpoints represent endpoints of routes requested between Beginning_Date and Ending_Date.
" \
 --define=CCP_ATTRIBUTE_ACCURACY="" \
 --define=CCP_ENTITY_OVERVIEW="
cnt_routes <br>
cnt_ipadys
" \
 --define=CCP_DETAILED_CITATION="
cnt_routes <br>
* The number of unique route requests from users for this route. <br> <br>
cnt_ipadys <br>
* The number of route requests from unique computer hosts for this route (to help distinguish from multiple requests from the same user).
" \
 --define=CCP_DOWNLOAD_LINK="http://runic.cyclopath.org/exports/daily/${CCP_EXPORT_DATE}/ccp_rt_collected.zip" \
 --define=CCP_ACCESS_CONSTRAINTS="${ACCESS_RESTRICTED}" \
 --define=USE_CONSTRAINTS="${CCP_LICENSE}" \
 ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/ccp_metadata.htm.m4 \
  > ccp_rt_collected.htm

# *** METADATA: rt_endpoints: Cyclopath Requested-Route Endpoints

m4 \
 --define=CCP_LAYER_NAME=rt_endpoints \
 --define=CCP_TITLE="
Cyclopath Requested-Route Endpoints
" \
 --define=CCP_ABSTRACT="
A dataset of points. Each point represents an endpoint -- an origin or destination -- of a route request made by an actual user at Cyclopath.org.
" \
 --define=CCP_LAST_UPDATE="${CCP_LAST_UPDATE}" \
 --define=CCP_UPDATE_FREQUENCY="${CCP_UPDATE_FREQUENCY}" \
 --define=CCP_TIME_PERIOD_OF_CONTENT_DATE="" \
 --define=CCP_CURRENTNESS_REFERENCE="
Beginning_Date: 10/03/2007 <br>
Ending_Date: ${CCP_LAST_UPDATE} <br>
The route endpoints represent endpoints of routes requested between Beginning_Date and Ending_Date.
" \
 --define=CCP_ATTRIBUTE_ACCURACY="
Each point represents the endpoint of a route request from a user, snapped to a 1-cm grid.
" \
 --define=CCP_ENTITY_OVERVIEW="
beg_routes <br>
beg_ipadys <br>
fin_routes <br>
fin_ipadys
" \
 --define=CCP_DETAILED_CITATION="
beg_routes <br>
* The number of route requests for which this is the beginning endpoint (i.e., the origin). (Value: Positive integer.) <br> <br>
beg_ipadys <br>
* The number of unique user IP addresses that used this point as an origin in a route request. (Value: Positive integer.) <br> <br>
fin_routes <br>
* The number of route requests for which this is the finishing endpoint (i.e., the destination). (Value: Positive integer.) <br> <br>
fin_ipadys <br>
* The number of unique user IP addresses that used this point as a destination in a route request. (Value: Positive integer.)
" \
 --define=CCP_DOWNLOAD_LINK="http://runic.cyclopath.org/exports/daily/${CCP_EXPORT_DATE}/ccp_rt_endpoints.zip" \
 --define=CCP_ACCESS_CONSTRAINTS="None." \
 --define=USE_CONSTRAINTS="${CCP_LICENSE}" \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/ccp_metadata.htm.m4 \
  > ccp_rt_endpoints.htm

# *** METADATA: rt_line_segs: Cyclopath Road Network with Route Statistics

m4 \
 --define=CCP_LAYER_NAME=rt_line_segs \
 --define=CCP_TITLE="
Cyclopath Road Network with Route Statistics
" \
 --define=CCP_ABSTRACT="
A dataset of line segments. Each line segment represents a line segment that was included in one or more route requests.
" \
 --define=CCP_LAST_UPDATE="${CCP_LAST_UPDATE}" \
 --define=CCP_UPDATE_FREQUENCY="${CCP_UPDATE_FREQUENCY}" \
 --define=CCP_TIME_PERIOD_OF_CONTENT_DATE="" \
 --define=CCP_CURRENTNESS_REFERENCE="
Beginning_Date: 10/03/2007 <br>
Ending_Date: ${CCP_LAST_UPDATE} <br>
The route endpoints represent endpoints of routes requested between Beginning_Date and Ending_Date.
" \
 --define=CCP_ATTRIBUTE_ACCURACY="
Each point represents the endpoint of a route request from a user, snapped to a 1-cm grid.
" \
 --define=CCP_ENTITY_OVERVIEW="
name <br>
stack_id <br>
versions <br>
cnt_routes <br>
cnt_ipadys
" \
 --define=CCP_DETAILED_CITATION="
name <br>
* The name of the line segment in the Cyclopath dataset (which may be multiple names, comma-separated, i.e., if the line segment was edited between route requests). Each line segment represents a street used as a step in one or more route requests. Because streets can be edited by users (and therefore change over time), the same line segment may be named differently for different route requests. Note that, if two routes use the same street but the street's geometry was edited between route requests, you'll see two line segments in this dataset for that street (but you'll see just one line segment if only, i.e., the name changed). <br> <br>
stack_id <br>
* The internal Cyclopath ID(s) of this (these) line segments. <br> <br>
versions <br>
* The internal Cyclopath version(s) of this (these) line segments. <br> <br>
cnt_routes <br>
* The number of unique route requests that include this line segment. <br> <br>
cnt_ipadys <br>
* The number of route requests from unique computers (IP addresses) that include this line segment.
" \
 --define=CCP_DOWNLOAD_LINK="http://runic.cyclopath.org/exports/daily/${CCP_EXPORT_DATE}/ccp_rt_line_segs.zip" \
 --define=CCP_ACCESS_CONSTRAINTS="None." \
 --define=USE_CONSTRAINTS="${CCP_LICENSE}" \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/ccp_metadata.htm.m4 \
  > ccp_rt_line_segs.htm

# *** METADATA: ccp_road_network: Cyclopath Road Network

m4 \
 --define=CCP_LAYER_NAME=ccp_road_network \
 --define=CCP_TITLE="
Cyclopath Road Network
" \
 --define=CCP_ABSTRACT="
A dataset of line segments.
" \
 --define=CCP_LAST_UPDATE="${CCP_LAST_UPDATE}" \
 --define=CCP_UPDATE_FREQUENCY="${CCP_UPDATE_FREQUENCY}" \
 --define=CCP_TIME_PERIOD_OF_CONTENT_DATE="${CCP_LATEST_REV_DATE}" \
 --define=CCP_CURRENTNESS_REFERENCE="" \
 --define=CCP_ATTRIBUTE_ACCURACY="
The vertices of each line segment are accurate to 1 decimeter.
" \
 --define=CCP_ENTITY_OVERVIEW="
_ACTION <br>
_CONTEXT <br>
_DELETE <br>
_REVERT <br>
_CONFLATED <br>
_PCT_SURE <br>
_NEW_GEOM <br>
<!-- _REVERSED -->
_CCP_FROMS <br>
EDIT_DATE <br>
CCP_ID <br>
CCP_NAME <br>
z_level <br>
gf_lyr_id <br>
gf_lyr_nom <br>
one_way <br>
rtng_cbf7 <br>
rtng_yours <br>
rtng_mean <br>
rtng_count <br>
item_tags <br>
speedlimit <br>
lane_count <br>
out_ln_wid <br>
shld_width <br>
ndl_nodeid <br>
ndl_elev <br>
ndl_ref_no <br>
ndl_dngl_k <br>
ndl_duex_k <br>
ndr_nodeid <br>
ndr_elev <br>
ndr_ref_no <br>
ndr_dngl_k <br>
ndr_duex_k
" \
 --define=CCP_DETAILED_CITATION="
_ACTION <br>* Instructs Cyclopath how to handle this line segment during import. One of: CCP_, Import, Ignore, FIXME. <br> <br>
_CONTEXT <br>* May be used by the user to help prepare a data before importing. <br> <br>
_DELETE <br>* If True, instructs Cyclopath to mark this road 'deleted' on import. <br> <br>
_REVERT <br>* If True, instructs Cyclopath to 'branch-revert' this road on import. <br> <br>
_CONFLATED <br>* If True, the line segment has been manually conflated, and no matching Cyclopath road was found. <br> <br>
_PCT_SURE <br>* If set, indicates that a road was automatically conflated, and this is the confidence rating. <br> <br>
_NEW_GEOM <br>* If True, use the geometry of the conflated line segment and not the geometry of the existing Cyclopath feature. <br> <br>
<!-- _REVERSED -->
_CCP_FROMS <br>* For split-from or split-into byways, the IDs of the reference byways. <br> <br>
EDIT_DATE <br>* If set, indicates that a feature has been edited and should be imported. FIXME: See the xxx ArcGIS plugin. FIXME: Include README like http://cyclopath.org/wiki/Cycloplan/User_Guide#Editing_an_Exported_Shapefile <br> <br>
CCP_ID <br>* The Cyclopath ID of the feature. This value should not be edited. If -1, signifies a Control Feature -- this feature has no geometry but is used for import. Some Control Features can be edited to influence the import. For real line segments, this value is positive if it represents a line segment in Cyclopath, otherwise it's unset order negative to indicate it's a new feature. <br> <br>
CCP_NAME <br>* The name of the feature. <br> <br>
z_level <br>* The feature's z-level, or underpass/overpass indicator. <br> <br>
gf_lyr_id <br>* The database ID of the feature type. <br> <br>
gf_lyr_nom <br>* The friendly name of the feature type. <br> <br>
one_way <br>* If 0, the road represented by the line segment is two-way. If 1, the road is one-way in the direction of the line segment; if -1, the road is one-way in the opposite direction of the line segment. <br> <br>
rtng_cbf7 <br>* The road rating as determined by the Chicago Bikeland Federation Algorithm #7. <br> <br>
rtng_yours <br>* If the export was produced in the context of a particular user, this is that user's road rating. <br> <br>
rtng_mean <br>* The average of all user ratings for this road segment. <br> <br>
rtng_count <br>* The number of users who have rated this road segment. <br> <br>
item_tags <br>* The collection of tags that users have applied to this road segment. <br> <br>
speedlimit <br>* The speed limit of the road. <br> <br>
lane_count <br>* The number of lanes, including both directions. <br> <br>
out_ln_wid <br>* The width of the outside (generally, right-most) lane. <br> <br>
shld_width <br>* The width of the road shoulder. <br> <br>
ndl_nodeid <br>* The Cyclopath ID of the beginning vertex of the line segment. <br> <br>
ndl_elev <br>* The elevation of the beginning vertex of the line segment. <br> <br>
ndl_ref_no <br>* The number of non-deleted line segments that share this vertex. <br> <br>
ndl_dngl_k <br>* If this is the only line segment that uses this vertex, indicates if the dangle is okay or if the line segment is missing network connectivity. <br> <br>
ndl_duex_k <br>*  &quot;A duex rues&quot; means &quot;Has two streets.&quot; It's an endpoint that connects just two byways. (And we might be able to join the two byways.) The ndl_duex_k field applies to the line segment's beginning vertex. <br> <br>
ndr_nodeid <br>* The Cyclopath ID of the finishing vertex of the line segment. <br> <br>
ndr_elev <br>* The elevation of the finishing vertex of the line segment. <br> <br>
ndr_ref_no <br>* The number of non-deleted line segments that share this vertex. <br> <br>
ndr_dngl_k <br>* If this is the only line segment that uses this vertex, indicates if the dangle is okay or if the line segment is missing network connectivity. <br> <br>
ndr_duex_k <br>* &quot;A duex rues&quot; means &quot;Has two streets.&quot; It's an endpoint that connects just two byways. (And we might be able to join the two byways.) The ndr_duex_k field applies to the line segment's finishing vertex.
" \
 --define=CCP_DOWNLOAD_LINK="http://runic.cyclopath.org/exports/daily/${CCP_EXPORT_DATE}/ccp_road_network.zip" \
 --define=CCP_ACCESS_CONSTRAINTS="None." \
 --define=USE_CONSTRAINTS="${CCP_LICENSE}" \
  ${PYSERVER_HOME}/../scripts/daily/export_docs/metadata/ccp_metadata.htm.m4 \
  > ccp_road_network.htm

# ***

