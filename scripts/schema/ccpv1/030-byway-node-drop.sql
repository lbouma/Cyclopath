/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script drops the no-longer-needed byway_node table. */

begin transaction;
set constraints all deferred;

drop table byway_node;

-- rollback;
commit;
