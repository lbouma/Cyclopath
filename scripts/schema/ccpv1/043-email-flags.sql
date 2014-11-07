/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** add email columns to the database **/

begin;
set constraints all deferred;

ALTER TABLE user_
   ADD COLUMN enable_email BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_
   ADD COLUMN enable_email_research BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_
   ADD COLUMN email_bouncing BOOLEAN NOT NULL DEFAULT false;

commit;
