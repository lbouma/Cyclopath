/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Add "4WD Road" byway type to support importing Colorado data. This is not
   quite right, I think; see bug 1805. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

insert into byway_type (code, draw_class_code, text)
                values (12,   11,              '4WD Road');

COMMIT;
