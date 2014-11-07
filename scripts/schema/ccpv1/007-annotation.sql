/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Annotation and Annot_BS tables. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;


/** Annotation and Annot_BS tables **/

DROP TABLE annot_bs;
DROP TABLE annotation;

CREATE TABLE annotation (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  comments TEXT,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE TABLE annot_bs (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  annot_id INT NOT NULL,  --REFERENCES annotation (id) DEFERRABLE,
  byway_id INT NOT NULL,  --REFERENCES byway_segment (id) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

\d annotation
\d annot_bs

--ROLLBACK;
COMMIT;
