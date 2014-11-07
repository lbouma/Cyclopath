/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* SQL to add the dont_study flag to the user_ table. This flag is true for
   those users which must be excluded from analysis because they are too
   closely affiliated with the Cyclopath team or for other reasons. */

begin transaction;
set constraints all deferred;

alter table user_ add column dont_study boolean not null default false;

update user_ set dont_study = true
where
      username like 'test%'          -- mostly from Dec 2007 study
   or username like E'\\_%'          -- system users
   or username in ('ajohnson',       -- Anthony Johnson
                   'joh03749',       -- Anthony Johnson
                   'jordan',         -- Jordan Focht
                   'm',              -- Mikhil Masli
                   'mekhyl',         -- Mikhil Masli
                   'mludwig',        -- Michael Ludwig
                   'reid',           -- Reid Priedhorsky
                   'reid2',          -- Reid Priedhorsky
                   'reid3',          -- Reid Priedhorsky
                   'reid4',          -- Reid Priedhorsky
                   'reid5',          -- Reid Priedhorsky
                   'sheppard',       -- Andrew Sheppard
                   'tatgeer',        -- Erin Tatge (Reid's wife)
                   'terveen',        -- Loren Terveen
                   'torre',          -- Fernando Torre
                   'zschloss');      -- Zach Schloss

commit;
