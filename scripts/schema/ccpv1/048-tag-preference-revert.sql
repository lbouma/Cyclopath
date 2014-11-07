/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Revert everything done in 047-tag-preference.sql */

BEGIN TRANSACTION;

ALTER TABLE user_ DROP rf_priority;
ALTER TABLE route DROP from_addr;
ALTER TABLE route DROP to_addr;
ALTER TABLE route_digest DROP route_id;

DROP TABLE user_preference_event;
DROP TABLE route_tag_preference;
DROP TABLE route_priority;
DROP TABLE tag_preference;
DROP TABLE tag_preference_event;
DROP TABLE tag_preference_type;

COMMIT;
