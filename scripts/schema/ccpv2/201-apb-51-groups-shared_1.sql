/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds public support tables used by the new access control 
   system. */

\qecho 
\qecho This script adds public support tables used by the new access ctrl sys
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Make the access level and scope lookups                  */
/* ==================================================================== */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

\qecho 
\qecho Creating the public access_infer lookup table
\qecho 

CREATE TABLE public.access_infer (
   id INTEGER NOT NULL,
   infer_name TEXT
);

ALTER TABLE public.access_infer 
   ADD CONSTRAINT access_infer_pkey 
   PRIMARY KEY (id);

CREATE INDEX access_infer_infer_name
   ON public.access_infer (infer_name);

\qecho 
\qecho Creating the public access_level lookup table
\qecho 

CREATE TABLE public.access_level (
   id INTEGER NOT NULL,
   description TEXT
);

ALTER TABLE public.access_level 
   ADD CONSTRAINT access_level_pkey 
   PRIMARY KEY (id);

CREATE INDEX access_level_description
   ON public.access_level (description);

\qecho 
\qecho Creating the public access_scope lookup table
\qecho 

CREATE TABLE public.access_scope (
   id INTEGER NOT NULL,
   scope_name TEXT
);

ALTER TABLE public.access_scope 
   ADD CONSTRAINT access_scope_pkey 
   PRIMARY KEY (id);

CREATE INDEX access_scope_scope_name
   ON public.access_scope (scope_name);

\qecho 
\qecho Creating the public access_style lookup table
\qecho 

CREATE TABLE public.access_style (
   id INTEGER NOT NULL,
   style_name TEXT
);

ALTER TABLE public.access_style 
   ADD CONSTRAINT access_style_pkey 
   PRIMARY KEY (id);

CREATE INDEX access_style_style_name
   ON public.access_style (style_name);

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* ==================================================================== */
/* Step (2) -- Define the access levels and scopes                      */
/* ==================================================================== */

\qecho 
\qecho Populating access_infer
\qecho 

/* SYNC_ME: Search: Access Infer IDs. */

INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000000'::INTEGER, 'not_determined');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000001'::INTEGER, 'usr_arbiter');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000002'::INTEGER, 'usr_editor');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000004'::INTEGER, 'usr_viewer');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000008'::INTEGER, 'usr_denied');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000010'::INTEGER, 'pub_arbiter');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000020'::INTEGER, 'pub_editor');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000040'::INTEGER, 'pub_viewer');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000080'::INTEGER, 'pub_denied');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000100'::INTEGER, 'stealth_arbiter');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000200'::INTEGER, 'stealth_editor');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000400'::INTEGER, 'stealth_viewer');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00000800'::INTEGER, 'stealth_denied');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00001000'::INTEGER, 'others_arbiter');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00002000'::INTEGER, 'others_editor');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00004000'::INTEGER, 'others_viewer');
INSERT INTO access_infer (id, infer_name)
   VALUES (x'00008000'::INTEGER, 'others_denied');

\qecho 
\qecho Populating access_level
\qecho 

/* SYNC_ME: Search: Access Level IDs. */

INSERT INTO access_level (id, description) VALUES (-1, 'invalid');

INSERT INTO access_level (id, description) VALUES (1, 'owner');
INSERT INTO access_level (id, description) VALUES (2, 'arbiter');
INSERT INTO access_level (id, description) VALUES (3, 'editor');
INSERT INTO access_level (id, description) VALUES (4, 'viewer');
INSERT INTO access_level (id, description) VALUES (5, 'client');
INSERT INTO access_level (id, description) VALUES (6, 'stealth');
INSERT INTO access_level (id, description) VALUES (7, 'denied');

\qecho 
\qecho Populating access_scope
\qecho 

/* SYNC_ME: Search: Access Scope IDs. */

INSERT INTO access_scope (id, scope_name) VALUES (0, 'undefined');

INSERT INTO access_scope (id, scope_name) VALUES (1, 'private');
INSERT INTO access_scope (id, scope_name) VALUES (2, 'shared');
INSERT INTO access_scope (id, scope_name) VALUES (3, 'public');

\qecho 
\qecho Populating access_scope
\qecho 

/* SYNC_ME: Search: Access Style IDs. */

INSERT INTO access_style (id, style_name) VALUES (0, 'nothingset');
INSERT INTO access_style (id, style_name) VALUES (1, 'all_access');
INSERT INTO access_style (id, style_name) VALUES (2, 'permissive');
INSERT INTO access_style (id, style_name) VALUES (3, 'restricted');
INSERT INTO access_style (id, style_name) VALUES (4, '_reserved1');
INSERT INTO access_style (id, style_name) VALUES (5, 'pub_choice');
INSERT INTO access_style (id, style_name) VALUES (6, 'usr_choice');
INSERT INTO access_style (id, style_name) VALUES (7, 'usr_editor');
INSERT INTO access_style (id, style_name) VALUES (8, 'pub_editor');
INSERT INTO access_style (id, style_name) VALUES (9, 'all_denied');

/* ==================================================================== */
/* Step (3) -- And now for something completely different               */
/* ==================================================================== */

\qecho 
\qecho Renaming WFS to GWIS
\qecho 

ALTER TABLE ban RENAME COLUMN ban_all_wfs TO ban_all_gwis;

/* ==================================================================== */
/* Step (4) -- Make useful trigger fcn(s).                              */
/* ==================================================================== */

\qecho 
\qecho Creating useful trigger functions
\qecho 

/* C.f. set_last_modified() and set_created() and set_last_viewed(). */
CREATE OR REPLACE FUNCTION public.set_date_created() 
   RETURNS TRIGGER AS $set_date_created$
     BEGIN 
       NEW.date_created = now();
       RETURN NEW;
     END
   $set_date_created$ LANGUAGE 'plpgsql';

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

