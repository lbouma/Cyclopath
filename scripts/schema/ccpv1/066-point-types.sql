/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;

SET CONSTRAINTS ALL DEFERRED;

/** One request in adding point types was the ability for different 
points to be shown with different text label sizes at different zooms 
while keeping the actual colored circle that represents the point at the 
same size - this is being done by adding a value that determines the 
size of the text label to the draw param table. **/

ALTER TABLE draw_param ADD label_size REAL;

/** Initially we just set this equal to the width of the feature being 
drawn, which is the same as the current behavior. **/

UPDATE draw_param SET label_size = width;

/** Because the server fetches draw params from the draw_param_joined 
view rather than the actual table, this view needs to be updated to 
include label size now. **/

DROP VIEW draw_param_joined;

CREATE VIEW draw_param_joined AS 
SELECT 
   draw_param.width, 
   draw_class.code AS draw_class_code, 
   draw_param.zoom, 
   draw_param.label, 
   draw_param.label_size, 
   draw_class.color 
FROM draw_class 
   LEFT JOIN draw_param ON draw_class.code = draw_param.draw_class_code;

COMMIT;
