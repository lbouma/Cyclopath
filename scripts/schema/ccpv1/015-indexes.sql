/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds some indexes. */

begin transaction;
set constraints all deferred;

create index byway_rating_last_modified on byway_rating (last_modified);
create index user__username_unique_caseinsensitive on user_ (lower(username));

commit;
