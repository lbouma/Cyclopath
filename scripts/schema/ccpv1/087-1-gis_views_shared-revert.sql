
/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP AGGREGATE group_concat(text);
DROP FUNCTION _group_concat(text, text);

COMMIT;
