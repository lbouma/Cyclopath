/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** Remove the ban table from the database */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP TABLE ban;

COMMIT;
