/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

begin transaction;
set constraints all deferred;

alter table wr_email_pending add column 
   username text references user_(username) deferrable;

alter table wr_email_pending drop constraint wr_email_pending_pkey;
alter table wr_email_pending add constraint
   wr_email_pending_pkey primary key (rid, wrid, username);

commit;
