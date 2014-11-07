/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** Create a table to store schema upgrade information and enable semi-smart
    schema upgrades with schema-upgrade.py. */

begin;
set constraints all deferred;

create table upgrade_event (
  id serial primary key,
  script_name text not null,
  created timestamp with time zone not null
);

create trigger upgrade_event_ic before insert on upgrade_event
  for each row execute procedure set_created();
-- make table insert-only
create trigger upgrade_event_u before update on upgrade_event
  for each statement execute procedure fail();
/* NOTE: upgrade_event is a special case, since it might need row deletion
   to clean up a bad schema upgrade. */
--create trigger upgrade_event_d before delete on upgrade_event
--  for each statement execute procedure fail();

\d upgrade_event

/* Initialize upgrade history. */
COPY upgrade_event (script_name) FROM STDIN;
001-byways.sql
002-users.sql
003-nodes.sql
004-reproject-utm.sql
005-bmpolygon.sql
006-point.sql
007-annotation.sql
008-routes.sql
009-cleanup.sql
010-z-order.sql
011-salt.sql
012-labeling.sql
013-login_ok.sql
014-annotations.sql
015-indexes.sql
016-revision-geosummary.sql
017-tilecache-state.sql
018-indexes.sql
019-byway-editing.sql
020-nodes.sql
021-watch_region.sql
022-name2.sql
023-byway-closed.sql
024-bbox_text.sql
025-sidewalks.sql
026-wr_draw_params.sql
027-revert-log.sql
028-byway-null-cleanup.sql
029-wr_notification.sql
030-byway-node-drop.sql
031-revision-geometry.sql
032-byway-node-repair.sql
033-annot_bs_geo.sql
034-revision-geometry.sql
035-ratings.sql
036-revision-feedback.sql
037-bmpolygon-cleanup.sql
038-byway-degenerate.sql
039-byway_current.sql
040-byway-split-from.sql
041-ban-hammer.sql
042-rating-log.sql
043-email-flags.sql
045-tag-history.sql
045-tag.sql
047-tag-remove-flags.sql
048-tag-preference.sql
049-route-feedback.sql
050-cleanup.sql
051-apache-logs.sql
052-researcher-list.sql
053-route-host.sql
054-route-logging.sql
055-enable-wr-digest.sql
056-link-cleanup.sql
057-viz-prefs.sql
058-route-sharing.sql
059-alias_source.sql
060-alias_users.sql
061-auth-fail-limit.sql
062-apache_event_sessions.sql
064-regions.sql
065-orphan-tags.sql
066-point-types.sql
067-routes-created-restore.sql
068-prohibited-tag.sql
069-valid-version.sql
070-wr_pending_username.sql
071-log-event.sql
072-remove-tag-bs-duplicates.sql
073-log-event_session-ids.sql
074-rename-visualization.sql
075-script-user.sql
076-tile-db-changes.sql
077-colors.sql
078-fix-tag-region-orphan.sql
079-route-deeplinking.sql
080-discussions.sql
081-fix-discussions-search.sql
082-geofeature-fix.sql
083-upgrade_event.sql
\.

commit;
