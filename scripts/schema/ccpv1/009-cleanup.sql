/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

alter table annot_bs drop constraint annot_bs_byway_id_fkey;
alter table aadt drop constraint aadt_byway_id_fkey;
alter table byway_rating drop constraint byway_id_fk;

alter table byway_segment drop constraint temp;

/* not allowed according to SQL spec
alter table annot_bs add constraint annot_bs_byway_id_fkey
  foreign key (byway_id) references byway_segment (id) deferrable;
alter table aadt add constraint aadt_byway_id_fkey
  foreign key (byway_id) references byway_segment (id) deferrable;
alter table byway_rating add constraint byway_id_fk
  foreign key (byway_id) references byway_segment (id) deferrable;
*/

\d annot_bs
\d aadt
\d byway_rating
\d byway_segment

COMMIT;
-- ROLLBACK;
