/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP TABLE IF EXISTS route_feedback_stretch;
DROP TABLE IF EXISTS route_feedback_drag;

COMMIT;

