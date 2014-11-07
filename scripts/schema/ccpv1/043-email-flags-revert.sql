/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** remove email columns to the database **/

ALTER TABLE user_ DROP COLUMN enable_email;
ALTER TABLE user_ DROP COLUMN enable_email_research;
ALTER TABLE user_ DROP COLUMN email_bouncing;
