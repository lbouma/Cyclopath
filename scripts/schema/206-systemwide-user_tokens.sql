/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the user token table. */

\qecho 
\qecho This script creates the jobs queuer.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho 
\qecho Creating user token table.
\qecho 

/* */

DROP TABLE IF EXISTS public.user__token;
CREATE TABLE public.user__token (
   user_token UUID NOT NULL,
   username TEXT NOT NULL,
   user_id INTEGER NOT NULL,
   date_created TIMESTAMP WITH TIME ZONE NOT NULL,
   date_expired TIMESTAMP WITH TIME ZONE,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
   usage_count INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.user__token 
   ADD CONSTRAINT user__token_pkey 
   PRIMARY KEY (user_token);

CREATE TRIGGER user__token_date_created_i
   BEFORE INSERT ON public.user__token
   FOR EACH ROW EXECUTE PROCEDURE public.set_date_created();

CREATE TRIGGER user__token_last_modified_i
   BEFORE INSERT ON public.user__token
   FOR EACH ROW EXECUTE PROCEDURE public.set_last_modified();
CREATE TRIGGER user__token_last_modified_u
   BEFORE UPDATE ON public.user__token
   FOR EACH ROW EXECUTE PROCEDURE public.set_last_modified();

/*

Just a little testing sandbox...

INSERT INTO user__token 
(user_token, username, user_id)
VALUES
('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'lando', 123);


update user__token set usage_count = usage_count + 1
WHERE user_token = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

*/

/* Obsolete trigger code... */

/* 1 ... */

/* NOTE: I wanted to write a trigger that takes the column name as a parameter
 *       but apparently plpgsql does not support it, even using execute, e.g., 
 *          EXECUTE 'NEW.' || TG_ARGV[0] || ' = now();';
CREATE TRIGGER user__token_date_created_i
   BEFORE INSERT ON public.user__token
   FOR EACH ROW EXECUTE PROCEDURE public.set_date_column('date_created');
 */

/* 2 ... */

/* This is such a cute fcn. but it's so not necessary. And by cute, I mean it's
 * a good example of how to write a more complicated trigger... then again, we
 * should really be using triggers except for the most basic of tasks like
 * maintaining time stamps.... */

/* In this fcn., we cannot assign NULL to NEW.usage_count or we get a
 * constraint error, so we need to use an intermediate variable. */
/*
CREATE OR REPLACE FUNCTION set_usage_count() 
   RETURNS TRIGGER AS '
   DECLARE
      next_count_num INTEGER;
   BEGIN 
      next_count_num = MAX(usage_count) + 1
                       FROM user__token 
                       WHERE user_token = NEW.user_token;
      IF next_count_num IS NULL THEN
         NEW.usage_count := 1;
      ELSE
         NEW.usage_count := next_count_num;
      END IF;
      RETURN NEW;
   END
' LANGUAGE 'plpgsql';
*/

/* NOTE: You cannot set step_number on the initial insert. I.e., 
 *       INSERT INTO user__token (work_item_id, step_number) VALUES (1,10); 
 *       You have to instead run UPDATE after the INSERT. */
--CREATE TRIGGER user__token_usage_count_i
--   BEFORE INSERT ON public.user__token
--   FOR EACH ROW EXECUTE PROCEDURE set_usage_count();
/* Another reason these triggers are not that useful is that they don't fire on
 * select. So you'd have to spoof an update, e.g., 
 *    UPDATE user__token SET user_token = 'abc' WHERE user_token = 'abc';
 * just to get this trigger to fire to update the usage_cound, which seems
 * silly: you might as well just call SET usage_count = usage_count + 1. */
--CREATE TRIGGER user__token_usage_count_u
--   BEFORE UPDATE ON public.user__token
--   FOR EACH ROW EXECUTE PROCEDURE set_usage_count();

/* */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;

