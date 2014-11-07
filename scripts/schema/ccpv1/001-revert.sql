/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

SELECT DropGeometryTable('byway_segment');
drop table revision;
drop table byway_type;
drop table draw_param;
drop table draw_class;
drop sequence feature_id_seq;
