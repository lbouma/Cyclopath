/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** This script updates the default watch region color **/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

UPDATE draw_class SET color = X'ff0000'::INT WHERE code = 6;

SELECT * FROM draw_param_joined WHERE draw_class_code = 6;
COMMIT;
