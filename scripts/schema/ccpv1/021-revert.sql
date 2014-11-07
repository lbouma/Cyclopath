/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* revert everything done in 021-watch_region.sql */

BEGIN TRANSACTION;

SELECT DropGeometryTable('watch_region');
DROP TABLE watch_region_type;

DELETE FROM draw_param WHERE draw_class_code = 6;
DELETE FROM draw_class WHERE code = 6;

SELECT * FROM draw_class;
SELECT * FROM draw_param_joined WHERE draw_class_code = 6;
SELECT * FROM draw_param WHERE draw_class_code = 6;

COMMIT;
