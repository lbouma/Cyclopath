/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*
Removes duplicate tag bs's added to the Cyclopath database in January 2010.
*/

BEGIN TRANSACTION;

DELETE
   FROM tag_bs
   WHERE id IN (1470684, 1470686, 1470694, 1470697, 1470699, 1470741,
                1470721, 1470724, 1470742, 1470737, 1470831, 1470834);

COMMIT;
