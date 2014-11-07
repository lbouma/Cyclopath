/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds a "sidewalk" byway type. */

begin transaction;
set constraints all deferred;

insert into byway_type
  (code, draw_class_code, text) values (15, 12, 'Sidewalk');

commit;
