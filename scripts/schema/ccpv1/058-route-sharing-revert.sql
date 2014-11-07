/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Revert 055-route-sharing.sql */
BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE route DROP COLUMN version;
ALTER TABLE route DROP COLUMN type_code;
ALTER TABLE route DROP COLUMN valid_starting_rid;
ALTER TABLE route DROP COLUMN valid_before_rid;
ALTER TABLE route DROP COLUMN z;
ALTER TABLE route DROP COLUMN deleted;

DROP TABLE route_type;

DELETE FROM draw_param WHERE draw_class_code = 8;
DELETE FROM draw_class WHERE code = 8;

COMMIT;
