#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Log event check: check the Cyclopath log_event table for flashclient errors.

# Usage: INSTANCE=minnesota /ccp/dev/cp/scripts/daily/log_event_check.sh

# ===========================================================================
# *** Debug options

DEBUG_TRACE=false
# DEVS: Uncomment this if you want a cron email.
#DEBUG_TRACE=true

# ===========================================================================
# Utility fcns. and vars.

# This script expects to be run from its directory.
# E.g., /dev/ccp/cp/scripts/daily/landmarks_experiment_cron.sh.
script_relbase=$(dirname $0)
source ${script_relbase}/../util/ccp_base.sh

if [[ -z "${CCP_WORKING}"
      || -z "${PYSERVER_HOME}"
      || -z "${CCP_INSTANCE}"
      || -z "${CCP_DB_NAME}"
      ]]; then
  echo "ERROR: Missing CCP_WORKING (${CCP_WORKING})
               and/or PYSERVER_HOME (${PYSERVER_HOME})
               and/or CCP_INSTANCE (${CCP_INSTANCE})
               and/or CCP_DB_NAME (${CCP_DB_NAME}).
               "
  exit 1
fi

# A lot of the CcpV2 scripts get looped on, once per INSTANCE, but this
# script doesn't have a wrapper. It's currently called via cron, so the
# cron script should call this script once per db instance.
if [[ -z "$INSTANCE" ]]; then
  echo "ERROR: Please set the INSTANCE env. variable to the db instance"
  exit 1
fi

# ===========================================================================
# Asynchronous lockdown.

LOG_EVENT_CHECK_LOCKDIR="${CCP_WORKING}/scripts/daily/${script_name}-lock"

# Get the script lock or die trying.

DONT_FLOCKING_CARE=0
FLOCKING_REQUIRED=1
NUM_FLOCKING_TRIES=1
FLOCKING_TIMELIMIT=30
flock_dir \
  "${LOG_EVENT_CHECK_LOCKDIR}" \
  ${DONT_FLOCKING_CARE} \
  ${FLOCKING_REQUIRED} \
  ${NUM_FLOCKING_TRIES} \
  ${FLOCKING_TIMELIMIT}

# If we're here, it means the lock succeeded; otherwise, flock_dir exits.

# ===========================================================================
# LOG EVENT CHECK
#

# Find log_event events since last time, using touch file for timestamp.
#
# The stat command returns, e.g., "2013-09-30 11:20:03.649212 -0500"
# A Postgres timestamp is, e.g., "2013-09-30 11:20:03.649212-05", but the stat
# output also works.
# And date --rfc-3339=ns returns, e.g., "2013-10-01 14:10:53.523346782-05:00"

# SELECT COUNT(*) FROM log_event WHERE facility LIKE 'error/%' AND created > '2013-09-30 11:20:03.649212 -0500' GROUP BY id ORDER BY id ASC;

TOUCH_FILE="${CCP_WORKING}/scripts/daily/${script_name}-touch"
if [[ -f ${TOUCH_FILE} ]]; then
  #caldat=`stat -c %y ${TOUCH_FILE} | /bin/sed -r 's/^([-0-9]+).*$/\1/'`
  time_stamp=`stat -c %y ${TOUCH_FILE}`
else
  # We could check errors from the beginning of time but that's
  # a lot of errors.
  time_stamp=`date --rfc-3339=ns`
fi
touch ${TOUCH_FILE}
# Try this for debugging:
#  touch --date=`date --rfc-3339=ns --date='-10 days'` \
#   /ccp/dev/cycloplan_work/scripts/daily/log_event_check.sh-touch
#   #/ccp/dev/cycloplan_test/scripts/daily/log_event_check.sh-touch
#   #/ccp/dev/cycloplan_live/scripts/daily/log_event_check.sh-touch
#  ./log_event_check.sh > 2014.09.09.log_event_check.sh.log

#PSQL_REPLY=`psql -U cycling ${CCP_DB_NAME} -q -tA -c \
#  "SELECT * FROM ${INSTANCE}.log_event_joined
#   WHERE facility LIKE 'error/%' AND created > '${time_stamp}'
#   ORDER BY id ASC;"`
#if [[ $PSQL_REPLY != '' ]]; then
#  # Echo to stdout so cron sends an email.
#  echo $PSQL_REPLY
#fi
#
# See error/assert_soft in flashclient/G.as assert_soft().
#
# The -q and -t options cause psql not to return anything unless 1+ rows.
# Also, we're not checking for 'warning/%', though we could...
psql -U cycling ${CCP_DB_NAME} -q -tA -c \
  "
   SELECT id
        , event_id AS eid
        , facility AS facil
        , CASE WHEN username LIKE '_user_anon_%'
               THEN '_anon' ELSE username END
            AS uname
        , client_host AS host
        , TO_CHAR(timestamp_client, 'YYYY.MM.DD|HH24:MI')
          AS ts_client
        --, TO_CHAR(created, 'YYYY.MM.DD|HH24:MI')
        --  AS created_date
        --, browid
        --, sessid
        , key_ AS key
        , value AS val
     FROM ${INSTANCE}.log_event_joined
    WHERE facility LIKE 'error/%'
      AND created > '${time_stamp}'
    ORDER BY id ASC;
  "

# ===========================================================================
# Unlock async lock.

/bin/rmdir "${LOG_EVENT_CHECK_LOCKDIR}" &> /dev/null
/bin/rmdir "${LOG_EVENT_CHECK_LOCKDIR}-${script_name}" &> /dev/null

# ===========================================================================
# Print elapsed time

# bash_base.sh initialized $script_time_0. Say how long we've run.
script_finished_print_time

# ===========================================================================
# All done.

exit 0

# ***

_2014_09_09_debug_scratch_ignore_="

# ***

How to work with log_event_check.

# ***

First, make a dump file from the database.

Choose the time frame you want to examine, and make a log file.

{BLAH}


touch --date=`date --rfc-3339=ns --date='-2 days'` \
  /ccp/dev/cycloplan_live/scripts/daily/log_event_check.sh-touch
  /ccp/dev/cycloplan_work/scripts/daily/log_event_check.sh-touch
  /ccp/dev/cycloplan_test/scripts/daily/log_event_check.sh-touch

./log_event_check.sh > 2014.09.11-14.log_event_check.sh.log


# ***

Next, find each unique error indicated and build an egrep chain
until you've found all errors.

E.g., here's all the errors [lb] found between Aug 31 and Sep 10, 2014:

LOGEVENTCHECK=/ccp/dev/cp/scripts/daily/2014.09.09.log_event_check.log
cat $LOGEVENTCHECK \
| egrep -niv '\|stack\|$' \
| egrep -niv '\|stack\|Error: StackTrace$' \
| egrep -niv '\|fail_count\|[^d]+$' \
| egrep -niv '\|msg\|Error #2032$' \
| egrep -niv '\|msg\|Error #2035$' \
| egrep -niv '\|msg\|Error #2036$' \
| egrep -niv '\|tile\|ccpwms,minnesota-2500677-bikeways' \
| egrep -niv '\|url\|/tilec\?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915' \
| egrep -niv '\|url\|http:\/\/cycloplan.cyclopath.org\/gwis\?rqst=kval_get&vkey=' \
| egrep -niv '\|message\|grax/Access_Level.as:124$' \
| egrep -niv '\|message\|grax/Item_Manager.as:1243$' \
| egrep -niv '\|message\|grax/Item_Manager.as:1245$' \
| egrep -niv '\|message\|grax/Item_Manager.as:1248$' \
| egrep -niv '\|message\|grax/Item_Manager.as:1251$' \
| egrep -niv '\|message\|gwis/Update_Manager.as:237$' \
| egrep -niv '\|message\|items/Item_User_Access.as:425$' \
| egrep -niv '\|message\|items/Link_Value.as:1367$' \
| egrep -niv '\|message\|items/feats/Direction_Step.as:87$' \
| egrep -niv '\|message\|views/map_widgets/tools/Tool_Route_Destination.as:102$' \
| egrep -niv '\|message\|views/base/App_Mode_Edit.as:255$' \
| egrep -niv '\|message\|views/panel_items/Widget_Gia_Sharing.mxml:344$' \
| egrep -niv '\|message\|views/panel_items/Widget_Gia_Sharing.mxml:652$' \
| egrep -niv '\|message\|views/panel_routes/Address_Resolved.as:262$' \
| egrep -niv '\|message\|views/panel_routes/Address_Resolver.mxml:272$' \
| egrep -niv '\|message\|views/panel_routes/Address_Resolver.mxml:441$' \
| egrep -niv '\|message\|views/panel_routes/Panel_Item_Route_Details.mxml:164$' \
| egrep -niv '\|message\|views/panel_routes/Panel_Routes_Looked_At.mxml:222$' \
| egrep -niv '\|message\|views/panel_routes/Panel_Routes_New.mxml:1211$' \
| egrep -niv '\|message\|views/panel_routes/Route_Editor_UI.as:532$' \
| egrep -niv '\|message\|views/panel_routes/Route_List_Entry.mxml:480$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:430$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:451$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:758$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:760$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:762$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:764$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:794$' \
| egrep -niv '\|message\|views/panel_routes/Route_Save_Footer.mxml:1073$' \
| egrep -niv '\|message\|views/panel_routes/Route_Stop.as:540$' \
| egrep -niv '\|message\|views/panel_routes/Widget_Feedback.mxml:41$' \
| egrep -niv '\|message\|views/panel_watchers/Panel_Watchers.mxml:297$' \
| egrep -niv '^ \+at ' \
| less
# Whatever: cannot get tab exclusion to work... and tried all the tricks, too.

# ***

Next, copy the egreps from above, trim 'em, and investigate each file:line.
Mark your findings here.

# ***

This is from Aug 31 through Sep 10, 2014:

# ***

'\|stack\|$'
The emply stack key/value is because prod. SWFs cannot create stack traces.

'\|stack\|Error: StackTrace$'
The non-empty stack key/value pair is landonb's debug flashclient traces.

# *** Hard asserts (Very Bad!)

'\|fail_count\|[^d]+$'
See: flashclient/G.as::assert().
#
This only happens with hard asserts.
21350775|50.82.224.54|_user_anon_minnesota|2014-09-07 21:30:40.666574-05|2014-09-07 21:30:39-05|error/assert_hard|19F192F1-6ACA-5E5F-762F-52DD8BB26B3E|541926f7-7e70-26ce-9f1d-52dd84fa623c|21350775|message|views/map_widgets/tools/Tool_Route_Destination.as:102
21163028|24.118.246.48|_user_anon_minnesota|2014-09-01 12:29:44.710211-05|2014-09-01 12:29:40-05|error/assert_hard|60D7B41C-9184-FA85-976E-C2EE3186BCA5|1b498aaa-c8be-0e9d-a4cf-32341433e586|21163028|message|views/panel_routes/Widget_Feedback.mxml:41
05|error/assert_hard||d766b5d0-3c71-af07-4541-31c787ed1e29|21159630|message|gwis/Update_Manager.as:237
21133256|107.2.97.205|_user_anon_minnesota|2014-08-31 02:10:51.836749-05|2014-08-31 02:10:48-05|error/assert_hard|54F82CA7-89FB-E440-3527-2AE554E37C96|728ad712-a710-e7af-8387-2ae54d5173e9|21133256|message|grax/Access_Level.as:124
21249546|146.217.200.214|fredecker|2014-09-04 12:54:29.718914-05|2014-09-04 12:54:26-05|error/assert_hard|B4AD986C-5543-3978-C5F6-5E42D4B62536|0a10a889-63f2-693b-27d7-41c41a9090a4|21249546|message|views/panel_items/Widget_Gia_Sharing.mxml:344
#
'\|message\|grax/Access_Level.as:124$'
I added more event info; still need to figure this one out:
it's the least_of fcn., which Panel_Item_Versioned uses to
determine an item selection set's permissions. No need to fail, yo!
#
'\|message\|gwis/Update_Manager.as:237$'
This one indicates that schedule_oo_band is being called when
!G.initialized. It's only in the last ten days twice, so maybe
[lb] triggered this when testing flashclient.
I added a new G.sl.event so we can see the request if this happens again.
#
'\|message\|views/map_widgets/tools/Tool_Route_Destination.as:102$'
Something to do with dragged_object not being reset?
I added G.sl.event... investigate further.
#
'\|message\|views/panel_items/Widget_Gia_Sharing.mxml:344$'
New G.sl.event should make it obvious next time it fires.
#
'\|message\|views/panel_routes/Widget_Feedback.mxml:41$'
New G.sl.event blah fix blah.

FIXME/BUG nnnn: When panning, sometimes edge tiles do not load.
                Is that because flashclient does not request them,
                or perhaps one of these Error #203[256] phenomenom
                is happening.
#
error/tiles/io ... '\|msg\|Error #2035$'
See: flashclient/items/utils/Tile.as::handler_ioerror()
Flex IOErrorEvent Error #2035: URL Not Found
There are just a few of these, and I checked the tile URLs and got tiles...
#
error/tiles/io ... '\|msg\|Error #2036$'
See: flashclient/items/utils/Tile.as::handler_ioerror()
Flex IOErrorEvent Error #2036: Load Never Completed
There's just one of these.
I imagine this had to do with restarting services, rebuilding
binaries, or something along those lines.

# Soft asserts

'\|url\|http:\/\/cycloplan.cyclopath.org\/gwis\?rqst=kval_get&vkey='
Happened twice in ten days (8/31 - 9/10).
See: flashclient/gwis/GWIS_Base.as::on_io_error()
Coincides with:
  error/gwis/io ... '\|msg\|Error #2032$'
Flex IOErrorEvent Error #2032: Stream Error
See if this keeps happening; probably caused by pyserver crash?

'\|message\|items/Item_User_Access.as:425$'
Added G.sl.event.

'\|message\|items/Link_Value.as:1367$'
Added G.sl.event.

'\|message\|views/panel_items/Widget_Gia_Sharing.mxml:652$'
TEST: making/viewing notes. TEST GIA WIDGET

'\|message\|views/base/App_Mode_Edit.as:255$'
Happened twice. Database is shutting down? Hrmmmmm...
Added comment.

'\|message\|views/panel_watchers/Panel_Watchers.mxml:297$'
Happened once. Added an sl event.

'\|message\|items/feats/Direction_Step.as:87$'
Added G.sl.event. Guessing a problem with p2/multimodal finder?

'\|message\|views/panel_routes/Address_Resolved.as:262$'
Problem with is_geocoded. Added G.sl.event.

'\|message\|views/panel_routes/Address_Resolver.mxml:272$'
Happened once.
Removed asssert:
 The geocode_picker.addy_picker_box cab be showing if the addy
 is also chosen, because user can expand it after being geocoded.

'\|message\|views/panel_routes/Address_Resolver.mxml:441$'
Happened five times in last ten days; anon users.
Re-geocoding request same as previous.
Does this mean we don't geocode this request but silently fail?
Add G.sl.event but not sure it'll help...

'\|message\|views/panel_routes/Panel_Item_Route_Details.mxml:164$'
Probably a false positive. Investigate further (wait for a bump).

'\|message\|views/panel_routes/Panel_Routes_Looked_At.mxml:222$'
16 x in past 10 days.
Looks like logged-in users. Makes sense for item findability.
Probably a non-issue.

'\|message\|views/panel_routes/Panel_Routes_New.mxml:1211$'
3 x in past 10 days. Care? Add event, aight.

'\|message\|views/panel_routes/Route_List_Entry.mxml:480$'
14 x in past 10 days.
Not sure, seems like it should work; added sl.event.

'\|message\|views/panel_routes/Route_Stop.as:540$'
Happened a lot. Added more events info too much diagnose fix.

'\|message\|grax/Item_Manager.as:1243$'
'\|message\|grax/Item_Manager.as:1245$'
'\|message\|grax/Item_Manager.as:1248$'
'\|message\|grax/Item_Manager.as:1251$'
Dozen-some times in past week-half.
Added G.sl.event; not sure if it'll help.

'\|message\|views/panel_routes/Route_Save_Footer.mxml:430$'
'\|message\|views/panel_routes/Route_Save_Footer.mxml:451$'
Happened once. Added G.sl.event.

'\|message\|views/panel_routes/Route_Save_Footer.mxml:758$'
'\|message\|views/panel_routes/Route_Save_Footer.mxml:760$'
'\|message\|views/panel_routes/Route_Save_Footer.mxml:762$'
'\|message\|views/panel_routes/Route_Save_Footer.mxml:764$'
'\|message\|views/panel_routes/Route_Save_Footer.mxml:794$'
A block of asserts. Rarely happened. Added sl.event.

'\|message\|views/panel_routes/Route_Editor_UI.as:532$'
14 x in past 10 days, boooo.
Indicates route_stops changed?
Maybe route was edited while request was outstanding?

"

