/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Add "Singletrack" and "Doubletrack" byway types per bug 1805. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO byway_type (code, draw_class_code, text) VALUES
  (16, 12, 'Doubletrack'), 
  (17, 12, 'Singletrack');

COMMIT;
