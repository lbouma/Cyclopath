/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script fixes Bug nnnn.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* If you want to see the problem, search for abnormal emails: */

SELECT
   email,
   enable_email,
   enable_email_research
FROM user_ WHERE email LIKE '%,%';

SELECT
   email,
   enable_email,
   enable_email_research
FROM user_ WHERE email LIKE '% %';

/* For emails with commas, set the bouncing flag. */

UPDATE user_ SET email_bouncing = TRUE WHERE email LIKE '%,%';

/* For emails with whitespace, trim 'em. */

UPDATE user_ SET email = TRIM(both ' ' FROM email) WHERE email LIKE '% %';

/* There's still two records with a space in the middle of the email. */

UPDATE user_ SET email_bouncing = TRUE WHERE email LIKE '% %';

/* All done! */

--ROLLBACK;
COMMIT;

