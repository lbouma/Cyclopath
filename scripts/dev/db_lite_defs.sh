#!/bin/bash

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script.
# CAVEAT: Really, only db_lite.sh should use this script.
#

# ***

# SYNC_ME: This same list is C.f. other cron scripts and bash scripts.
# NOTE: Order matters here, i.e., log_event_kvp depends on log_event.
# NOTE: Not dropping VIEW: log_event_joined, but it'll be dropped because of
#       CASCADE. And it doesn't get recreated. But no one uses it, just devs.
CCP_LITE_IGNORE_TABLES_SCHEMA="
  """apache_event_session"""
  """apache_event"""
  """log_event_kvp"""
  """log_event"""
  "
CCP_LITE_IGNORE_TABLES_PUBLIC="
  """auth_fail_event"""
  """ban"""
  "
CCP_LITE_IGNORE_TABLES="
  ${CCP_LITE_IGNORE_TABLES_SCHEMA}
  ${CCP_LITE_IGNORE_TABLES_PUBLIC}
  "
# Additional possibilities:
# --exclude-table '''*.user_preference_event''' \
# --exclude-table '''*.byway_rating_event''' \
# --exclude-table '''*.tag_preference_event''' \
# --exclude-table '''*.route''' \
# --exclude-table '''*.route_step''' \
# --exclude-table '''*.route_waypoint''' \
# etc.
#
CCP_LITE_INCLUDE_TABLES=""
for table in ${CCP_LITE_IGNORE_TABLES}; do
  # NOTE: Single quotes don't work here: bash doesn't interpolate singlie-'s.
  CCP_LITE_INCLUDE_TABLES="$CCP_LITE_INCLUDE_TABLES --table *.$table "
done
#
CCP_LITE_EXCLUDE_TABLES=""
for table in ${CCP_LITE_IGNORE_TABLES}; do
  # NOTE: Single quotes don't work here: bash doesn't interpolate singlie-'s.
  CCP_LITE_EXCLUDE_TABLES="$CCP_LITE_EXCLUDE_TABLES --exclude-table *.$table "
done
#
# NOTE: log_event_id_seq is not part of the schema created by pg_dump if we
#       just specify the table names, but for some reason the other sequences
#       are included. So be explicit about including the sequences in the
#       schema and also about making sure they're dropped before recreating
#       them.
CCP_LITE_IGNORE_SEQS_SCHEMA="
  """apache_event_session_id_seq"""
  """apache_event_id_seq"""
  """log_event_id_seq"""
  "
CCP_LITE_IGNORE_SEQS_PUBLIC="
  """auth_fail_event_id_seq"""
  "
CCP_LITE_IGNORE_SEQS="
  ${CCP_LITE_IGNORE_SEQS_SCHEMA}
  ${CCP_LITE_IGNORE_SEQS_PUBLIC}
  "
#
CCP_LITE_INCLUDE_SEQS=""
for seq in ${CCP_LITE_IGNORE_SEQS}; do
  # NOTE: Single quotes don't work here: bash doesn't interpolate singlie-'s.
  CCP_LITE_INCLUDE_SEQS="$CCP_LITE_INCLUDE_SEQS --table *.$seq "
done

# NOTE: Do not call exit. The calling script sourced us, so if we exit, we'll
# take the caller with us.
#exit 0

