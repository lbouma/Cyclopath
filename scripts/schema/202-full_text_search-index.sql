/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates and indexes columns for full text search support. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script sets up full text search.
\qecho 
\qecho [EXEC. TIME: 2012.03.11/Huffy: ~ 2 mins. mn. / 2 mins. co. [novacu]]
\qecho [EXEC. TIME: 2013.04.23/runic:  01.92 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho 
\qecho Creating columns, indices, and triggers
\qecho 

/* MAYBE: Copy this to the constrainst script? */

/* */

\qecho  >> item_versioned
ALTER TABLE item_versioned ADD COLUMN tsvect_name tsvector;
UPDATE item_versioned SET tsvect_name =
     to_tsvector('english', coalesce(name, ''));
CREATE INDEX item_versioned_tsvect_name 
   ON item_versioned USING gin(tsvect_name);
CREATE TRIGGER item_versioned_tsvect_name_trig 
   BEFORE INSERT OR UPDATE ON item_versioned 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_name, 'pg_catalog.english', name);

/* */

\qecho  >> annotation
ALTER TABLE annotation ADD COLUMN tsvect_comments tsvector;
UPDATE annotation SET tsvect_comments =
     to_tsvector('english', coalesce(comments, ''));
CREATE INDEX annotation_tsvect_comments 
   ON annotation USING gin(tsvect_comments);
CREATE TRIGGER annotation_tsvect_comments_trig 
   BEFORE INSERT OR UPDATE ON annotation 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_comments, 'pg_catalog.english', comments);

/* */

\qecho  >> post
ALTER TABLE post ADD COLUMN tsvect_body tsvector;
UPDATE post SET tsvect_body =
     to_tsvector('english', coalesce(body, ''));
CREATE INDEX post_tsvect_body 
   ON post USING gin(tsvect_body);
CREATE TRIGGER post_tsvect_body_trig 
   BEFORE INSERT OR UPDATE ON post 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_body, 'pg_catalog.english', body);

/* */

\qecho  >> link_value
ALTER TABLE link_value ADD COLUMN tsvect_value_text tsvector;
UPDATE link_value SET tsvect_value_text =
     to_tsvector('english', coalesce(value_text, ''));
CREATE INDEX link_value_tsvect_value_text 
   ON link_value USING gin(tsvect_value_text);
CREATE TRIGGER link_value_tsvect_value_text_trig 
   BEFORE INSERT OR UPDATE ON link_value 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_value_text, 'pg_catalog.english', value_text);

/* */

\qecho  >> group_item_access
ALTER TABLE group_item_access ADD COLUMN tsvect_name tsvector;
\qecho "    2013.05.12: runic: UPDATE 911393 | sql: 127697.565 ms | py: 2m08s"
UPDATE group_item_access SET tsvect_name =
     to_tsvector('english', coalesce(name, ''));
CREATE INDEX group_item_access_tsvect_name 
   ON group_item_access USING gin(tsvect_name);
CREATE TRIGGER group_item_access_tsvect_name_trig 
   BEFORE INSERT OR UPDATE ON group_item_access 
   FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger(
      tsvect_name, 'pg_catalog.english', name);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

