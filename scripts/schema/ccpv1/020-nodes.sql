/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script removes some foreign key constraints which make it impossible
   to keep the byway_nodes cache current. */

begin transaction;
set constraints all deferred;

alter table byway_segment drop constraint end_node_id_fk;
alter table byway_segment drop constraint start_node_id_fk;

commit;
