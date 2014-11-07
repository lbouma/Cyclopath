/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

ALTER TABLE public.alias_source 
   ADD CONSTRAINT alias_source_unique_text
      UNIQUE (text);

COMMIT;

