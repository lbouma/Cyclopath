/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

begin transaction;
set constraints all deferred;

alter table user_ drop column enable_wr_digest;
drop table wr_email_pending;

commit;
