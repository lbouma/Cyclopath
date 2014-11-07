/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

-- SQL to add the enable digest flag to the user_ table and the batching table
-- to store pending email notifications.

begin transaction;
set constraints all deferred;

alter table user_ add column enable_wr_digest boolean not null default false;

create table wr_email_pending (
   rid  integer references revision (id) deferrable,
   wrid integer references watch_region (id) deferrable,
   primary key (rid, wrid)
);
 
commit;
