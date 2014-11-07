/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* For the Colorado instance, make the 'closed' tag avoided by default.
   NOTE: This script assumes someone has already created the 'closed' tag,
   which is the case for the Colorado instance. */

\set tagid '(SELECT id FROM tag WHERE label=''closed'')'
\set avoid 3

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;
SET search_path TO colorado, public;

INSERT INTO tag_preference (username, tag_id, type_code, enabled)
  VALUES ('_r_generic', :tagid, :avoid, TRUE);

--ROLLBACK;
COMMIT;
