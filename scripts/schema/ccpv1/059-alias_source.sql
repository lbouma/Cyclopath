/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script updates the database to create a table to hold a pool of
   aliases. Use the script aliases.py to populate it. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

create table alias_source (
   id int not null primary key,
   text text not null
);

COMMIT;
