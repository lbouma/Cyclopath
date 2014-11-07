/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script drops obsolete views and makes views for each of the 
   geofeature_layer feat_types. */

\qecho 
\qecho This script drops obsolete views and makes views for each of the 
\qecho geofeature_layer feat_types.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- DROP GEOFEATURE LAYER CONVENIENCE VIEWS                  */
/* ==================================================================== */

CREATE FUNCTION iv_gf_layer_view_drop_all()
   RETURNS VOID AS $$
   DECLARE
      feat_type_layer RECORD;
   BEGIN
      /* Drop view for each geofeature type */
      /* NOTE We removed two rows previously so we UNION 'em back in */
      FOR feat_type_layer IN 
            SELECT DISTINCT feat_type FROM geofeature_layer 
            UNION (SELECT 'region_watched' AS feat_type) 
            UNION (SELECT 'region_work_hint' AS feat_type) LOOP
         EXECUTE 'DROP VIEW gfl_' || feat_type_layer.feat_type || ';';
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT iv_gf_layer_view_drop_all();

DROP FUNCTION iv_gf_layer_view_drop_all();

/* ==================================================================== */
/* Step (2) -- Cleanup geofeature_layer table                           */
/* ==================================================================== */

\qecho 
\qecho Cleaning up geofeature_layer table
\qecho 

-- FIXME All dependent tables were dropped in the last script?
ALTER TABLE geofeature_layer DROP COLUMN draw_class_id;

/* ==================================================================== */
/* Step (3) -- REBUILD GEOFEATURE LAYER CONVENIENCE VIEWS               */
/* ==================================================================== */

/* C.f. 102-apb-21-aattrs-shared__.sql */

\qecho 
\qecho Creating geofeature layer convenience views
\qecho 

/* FIXME Is gfl_ a good prefixxing convention? */

CREATE FUNCTION gfl_feat_type_view_create(IN feat_type TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'CREATE VIEW gfl_' || feat_type || ' AS 
            SELECT * 
               FROM geofeature_layer AS gfl
               WHERE gfl.feat_type = ''' || feat_type || ''';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION gfl_feat_type_view_create_all()
   RETURNS VOID AS $$
   DECLARE
      layer RECORD;
   BEGIN
      -- Create view for each geofeature type
      FOR layer IN SELECT DISTINCT feat_type FROM geofeature_layer LOOP
         PERFORM gfl_feat_type_view_create(layer.feat_type);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT gfl_feat_type_view_create_all();

DROP FUNCTION gfl_feat_type_view_create_all();
DROP FUNCTION gfl_feat_type_view_create(IN feat_type TEXT);

/* ==================================================================== */
/* Step (4) --                                                          */
/* ==================================================================== */

/* FIXME: This view is used by CcpC1 MapServer and Flashclient to render 
 *        map items. In CcpV2, there are more sophisticated draw param 
 *        settings. 
 *
 *        So... delete this view eventually. */

DROP VIEW draw_param_joined;

CREATE VIEW draw_param_joined AS 
   SELECT 
      draw_class.id AS draw_class_id, 
      draw_class.text, 
      draw_class.color,
      draw_param.zoom, 
      draw_param.width, 
      draw_param.label, 
      draw_param.label_size
   FROM 
      draw_class 
   LEFT OUTER JOIN 
      draw_param 
      ON draw_class.id = draw_param.draw_class_id
   ORDER BY
      draw_param.zoom ASC
      ,draw_class.id ASC
   ;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;

