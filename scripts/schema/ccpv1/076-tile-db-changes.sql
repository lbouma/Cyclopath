/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Remove tilecache_lock table; add primary key by byway_name_cache. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP TABLE tilecache_lock;

alter table byway_name_cache add column id serial;

COMMIT;


