/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script updates colors per Zach's suggestions. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

UPDATE draw_class SET color = X'ffffff'::INT WHERE text = 'shadow';

UPDATE draw_class SET color = X'd6c5b4'::INT WHERE text = 'background';
UPDATE draw_class SET color = X'799931'::INT WHERE text = 'openspace';
UPDATE draw_class SET color = X'86b4ce'::INT WHERE text = 'water';

UPDATE draw_class SET color = X'8243dd'::INT WHERE text = 'point';
--UPDATE draw_class SET color = X'799931'::INT WHERE text = 'watch_region';
UPDATE draw_class SET color = X'86d0c7'::INT WHERE text = 'route';
UPDATE draw_class SET color = X'666666'::INT WHERE text = 'region';

-- don't label points at zoom level 14 (outest vector level)
UPDATE draw_param SET label = 'f' WHERE zoom = 14 AND draw_class_code = 5;


UPDATE draw_param SET width = 0 WHERE zoom = 10 AND draw_class_code = 7;
UPDATE draw_param SET width = 0 WHERE zoom = 10 AND draw_class_code = 21;

-- bike trails
DELETE FROM draw_param
WHERE
   zoom IN (9, 10, 11, 12, 13)
   AND draw_class_code = 12;

COPY draw_param (draw_class_code, zoom, width, label, label_size) FROM STDIN;
12	9	0	f	0
12	10	0	f	0
12	11	2	t	0
12	12	3	t	0
12	13	3	t	0
\.

SELECT * FROM draw_class ORDER BY code;
COMMIT;
