/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Make sure event tables (at least those in the public/shared schema) record
   which instance the event happened under. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

-- Set default when creating column to avoid dealing with update triggers
ALTER TABLE user_preference_event ADD COLUMN instance TEXT NOT NULL DEFAULT 'minnesota';
-- Remove to ensure column is explicitly set in the future
ALTER TABLE user_preference_event ALTER COLUMN instance DROP DEFAULT;

ALTER TABLE auth_fail_event ADD COLUMN instance TEXT NOT NULL DEFAULT 'minnesota';
ALTER TABLE auth_fail_event ALTER COLUMN instance DROP DEFAULT;

COMMIT;
