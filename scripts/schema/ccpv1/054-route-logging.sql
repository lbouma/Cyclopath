/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

-- Extra logging fields
BEGIN TRANSACTION;

ALTER TABLE route ADD source TEXT;
-- was it a deep link?

ALTER TABLE route ADD use_defaults BOOLEAN;
-- no prefs were sent so defaults were used

COMMIT;
