/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds some indexes to make accessing annot_bs given byway or
   annotation ID faster. */

begin transaction;
set constraints all deferred;

create index annot_bs_annot_id on annot_bs (annot_id);
create index annot_bs_byway_id on annot_bs (byway_id);

commit;
