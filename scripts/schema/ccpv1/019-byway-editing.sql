/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script makes some data tweaks for nongeographic byway editing. */

begin transaction;
set constraints all deferred;

update byway_type set text='Expressway' where code = 41;
update byway_type set text='Bicycle Path' where code = 14;
update byway_type set text='Major Road' where code = 21;
update byway_type set text='Highway' where code = 31;

update byway_segment set z = z + 3;

commit;
