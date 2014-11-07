/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script deletes orphaned features and dangling links.

   About terminology: Features in the database either exist or they don't
   (i.e., there's rows for them in the database or there aren't), and features
   that exist may or may not be Wiki-deleted (i.e., have their "deleted" bit
   set or not). This script deals with nonexistence only and not with 
   Wiki-deletion.

   Definitions:
   
   A dangling link is a reference to a feature that does not exist. For 
   instance, a link from annot_bs to a byway_segment that doesn't exist (i.e.,
   has no rows).

   An orphaned feature is a feature that is not referenced from any link
   tables, like an annotation which is not linked from any annot_bs, or a tag 
   that has no links from tag_bs, tag_point, or tag_region. Neither orphaned
   tags nor orphaned annotations are a problem for the system, but orphaned
   annotations are completely useless and will forever be undiscoverable by
   users, so they just take up space in the database. Not that space isn't
   cheap, but if removing a dangling link creates an orphaned feature, we
   might as well scrub the orphaned feature, since it was created erroneously
   along with the dangling link.

     WARNING: This definition of "orphan" is different from used other places
     in the software, e.g. wfs_PutFeature.py.

   Both of these issues are failures, since features are never deleted from the
   database, but instead have their deleted flag set. So dangling links and
   orphaned features are created erroneously becasue of a failure in the
   software, and for that reason we choose to DELETE these rows from the
   database rather than "Wiki-delete" them by setting their 'deleted' column. 

   The bug:

   See Bug 1862: orphaned/dangling features on new-deleted geometries

   If you create a geometry, add a note or tag, delete that geometry, then save
   the map, you'll get new rows in the link and annotation or tag tables, but 
   not in the geometry table. This means that the link table references a 
   geometry that doesn't exist (called a dangling link).
   
   This happens not just because flashclient sends incomplete data, but because
   pyserver doesn't validate feature links when saving data. 
   
   See also Bug 1863 (pyserver), Bug 1864 (flashclient) and Bug 1882 (auditor)
   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO minnesota, public;

/* NOTE Rather than use a smart SQL statement to do the deleting, i.e., 

      DELETE FROM annot_bs WHERE id IN (SELECT ...)

   we explicitly specify the IDs. This is (a) more deliberate, so we're less 
   likely to make mistakes, and (b), more importantly, it this leaves a paper
   trail or a record of the IDs we deleted, so if we grep the source on
   particular IDs, we'll find this file. */

/* ================================================ */
/* DANGLING LINKS / annot_bs ==> non-existent byway */
/* ================================================ */

/* == Dangling links == */

CREATE TEMPORARY VIEW annot_bs_invalid_byway_count AS 
   SELECT 'annot_bs rows which reference non-existent byways'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM annot_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      WHERE geo.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   annot_bs with byway_ids of phantom byways. */
CREATE TEMPORARY VIEW annot_bs_invalid_byway_rows AS 
   SELECT lnk.id, lnk.version, lnk.annot_id, lnk.byway_id 
      FROM annot_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      JOIN annotation AS ann
         ON lnk.annot_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.annot_id, lnk.byway_id 
      ORDER BY lnk.byway_id;

/* == Newly orphaned features == */

/* This is the list of referenced annotations, grouped by ID (so we're
   ignoring the version). */
CREATE TEMPORARY VIEW annotations_linked AS
   SELECT ann.id
      FROM annot_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      JOIN annotation AS ann
         ON lnk.annot_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY ann.id;

/* This is the list of referenced annotations that are also linked to real
   byways in addition to the phantom byways, so we should not delete these 
   annotations. */
CREATE TEMPORARY VIEW annotations_in_use AS 
   SELECT ann.id
      FROM annotations_linked AS ann
      JOIN annot_bs AS lnk
         ON lnk.annot_id = ann.id
      WHERE lnk.id NOT IN (SELECT id FROM annot_bs_invalid_byway_rows) 
      GROUP BY ann.id;

/* This is the list of referenced annotations only used for phantom byways, so 
   we can delete these. */
CREATE TEMPORARY VIEW annotations_deletable AS 
   SELECT ann.id
      FROM annotations_linked AS ann
      WHERE ann.id NOT IN (SELECT id FROM annotations_in_use);

/* == Do the DELETE! == */

\qecho 
\qecho Number of annot_bs rows that reference non-existent byways:

SELECT * FROM annot_bs_invalid_byway_count;

\qecho 
\qecho Specifically, these annot_bs rows reference phantom byways:

SELECT id FROM annot_bs_invalid_byway_rows;

\qecho 
\qecho Deleting 60 rows from annot_bs:

DELETE FROM annot_bs WHERE id IN
   (1356292
   ,1356442
   ,1356461
   ,1371432
   ,1374679
   ,1378900
   ,1378923
   ,1378924
   ,1378957
   ,1378983
   ,1380622
   ,1387910
   ,1387911
   ,1387930
   ,1387934
   ,1387948
   ,1387955
   ,1387964
   ,1388020
   ,1388030
   ,1388035
   ,1388036
   ,1388037
   ,1388048
   ,1388054
   ,1388055
   ,1388064
   ,1388066
   ,1395410
   ,1397806
   ,1398225
   ,1398853
   ,1398903
   ,1401319
   ,1402886
   ,1403518
   ,1404668
   ,1405207
   ,1410868
   ,1410867
   ,1411636
   ,1412588
   ,1412589
   ,1414012
   ,1414019
   ,1415876
   ,1421117
   ,1434213
   ,1435704
   ,1435709
   ,1435713
   ,1445222
   ,1449507
   ,1470598
   ,1470606
   ,1474591
   ,1474599
   ,1477529
   ,1477695
   ,1491165);

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM annot_bs_invalid_byway_count;

\qecho 
\qecho After DELETEing, these annotations are now orphaned and may be deleted
\qecho (NOTE As of the writing of this script, this value should be 0!)

SELECT * FROM annotations_deletable;

/* ===================================================== */
/* DANGLING LINKS / annot_bs ==> non-existent annotation */
/* ===================================================== */

/* == Dangling links == */

CREATE TEMPORARY VIEW annot_bs_invalid_annot_count AS 
   SELECT 'annot_bs rows which reference non-existent annots'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM annot_bs AS lnk 
      LEFT OUTER JOIN annotation AS ann
         ON lnk.annot_id = ann.id
      WHERE ann.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   annot_bs with annot_ids of phantom annotations. */
CREATE TEMPORARY VIEW annot_bs_invalid_annot_rows AS 
   SELECT lnk.id, lnk.version, lnk.annot_id, lnk.byway_id 
      FROM annot_bs AS lnk 
      LEFT OUTER JOIN annotation AS ann
         ON lnk.annot_id = ann.id
      WHERE ann.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.annot_id, lnk.byway_id 
      ORDER BY lnk.byway_id;

/* == Newly orphaned features == */

/* Skipping: It doesn't make sense to check for newly orphaned byway_segments, 
             as byways are valid regardless of whether or not something links 
             to them. */

/* == Do the DELETE! == */

\qecho 
\qecho Number of annot_bs rows that reference non-existent annotations:

SELECT * FROM annot_bs_invalid_annot_count;

\qecho 
\qecho Specifically, these annot_bs rows reference phantom annotations:

SELECT id FROM annot_bs_invalid_annot_rows;

\qecho 
\qecho Deleting 187 rows from annot_bs:

DELETE FROM annot_bs WHERE id IN
   (1366163
   ,1361869
   ,1361831
   ,1361620
   ,1361826
   ,1361820
   ,1361878
   ,1369244
   ,1400190
   ,1361935
   ,1357441
   ,1361870
   ,1416198
   ,1416201
   ,1486441
   ,1400185
   ,1400189
   ,1486447
   ,1450503
   ,1357464
   ,1361940
   ,1361840
   ,1361823
   ,1361825
   ,1361828
   ,1361834
   ,1369268
   ,1369264
   ,1357465
   ,1450499
   ,1450511
   ,1450526
   ,1486450
   ,1361866
   ,1486439
   ,1361824
   ,1365934
   ,1361930
   ,1357446
   ,1450519
   ,1400184
   ,1361874
   ,1357437
   ,1366176
   ,1361821
   ,1361883
   ,1361832
   ,1486456
   ,1450504
   ,1361865
   ,1366169
   ,1357466
   ,1357468
   ,1361881
   ,1369266
   ,1357457
   ,1357453
   ,1486459
   ,1486457
   ,1403040
   ,1403038
   ,1486460
   ,1357448
   ,1486448
   ,1357458
   ,1357456
   ,1357461
   ,1354327
   ,1354327
   ,1357445
   ,1357443
   ,1357460
   ,1357442
   ,1361837
   ,1357462
   ,1357438
   ,1357467
   ,1369262
   ,1357450
   ,1357449
   ,1357452
   ,1358027
   ,1369263
   ,1369269
   ,1361872
   ,1369253
   ,1369254
   ,1369246
   ,1369251
   ,1361929
   ,1361946
   ,1358031
   ,1369249
   ,1369265
   ,1357469
   ,1486442
   ,1486445
   ,1361830
   ,1357440
   ,1357444
   ,1357435
   ,1357439
   ,1354325
   ,1354325
   ,1357451
   ,1361875
   ,1361876
   ,1361877
   ,1361880
   ,1369257
   ,1369259
   ,1361882
   ,1361868
   ,1357463
   ,1357454
   ,1357436
   ,1450505
   ,1450515
   ,1361873
   ,1366157
   ,1367513
   ,1484272
   ,1361879
   ,1369241
   ,1369248
   ,1361939
   ,1403039
   ,1400188
   ,1400187
   ,1361932
   ,1366158
   ,1482812
   ,1357455
   ,1366164
   ,1366166
   ,1361938
   ,1362114
   ,1362109
   ,1357447
   ,1361934
   ,1403036
   ,1354328
   ,1354328
   ,1369247
   ,1369250
   ,1354323
   ,1354323
   ,1362112
   ,1361943
   ,1361836
   ,1361835
   ,1361945
   ,1366160
   ,1361833
   ,1361822
   ,1434366
   ,1361838
   ,1418580
   ,1369256
   ,1361829
   ,1361942
   ,1397457
   ,1366165
   ,1366172
   ,1361827
   ,1434373
   ,1361839
   ,1357691
   ,1403364
   ,1387858
   ,1387865
   ,1362362
   ,1373675
   ,1449656
   ,1354392
   ,1354392
   ,1396491
   ,1366161
   ,1359571
   ,1369267
   ,1482650
   ,1377569
   ,1492908
   ,1399797
   ,1482652
   ,1428220
   ,1483191);

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM annot_bs_invalid_annot_count;

/* ============================================================ */
/* ORPHANED FEATURES / annotation ==> not linked from annot_bs  */
/* ============================================================ */

/* == Orphaned annotations == */

CREATE TEMPORARY VIEW annotation_invalid_annot_bs_count AS 
   SELECT 'annotation rows not referenced by any byways'::TEXT AS Comment,
         COUNT(*) AS Count
      FROM annotation AS ann
      LEFT OUTER JOIN annot_bs AS lnk 
         ON ann.id = lnk.annot_id
      WHERE lnk.id IS NULL;

/* Set of the orphaned rows. (Each ID listed just once.) These are the rows in
   annotation not associated with any rows in annot_bs. */
CREATE TEMPORARY VIEW annotation_invalid_annot_bs_rows AS 
   SELECT ann.id, ann.version 
      FROM annotation AS ann 
      LEFT OUTER JOIN annot_bs AS lnk 
         ON ann.id = lnk.annot_id
      WHERE lnk.id IS NULL
      GROUP BY ann.id, ann.version
      ORDER BY ann.id, ann.version;

/* == Do the DELETE! == */

\qecho 
\qecho Number of orphaned annotations (those not referenced from annot_bs):

SELECT * FROM annotation_invalid_annot_bs_count;

\qecho 
\qecho Specifically, these annotation rows are orphaned:

SELECT id FROM annotation_invalid_annot_bs_rows;

\qecho 
\qecho Deleting 42 rows from annotation:

DELETE FROM annotation WHERE id=1354290 AND version=1;
DELETE FROM annotation WHERE id=1354290 AND version=2;
DELETE FROM annotation WHERE id=1354411 AND version=1;
DELETE FROM annotation WHERE id=1354411 AND version=2;
DELETE FROM annotation WHERE id=1354469 AND version=1;
DELETE FROM annotation WHERE id=1354469 AND version=2;
DELETE FROM annotation WHERE id=1354637 AND version=1;
DELETE FROM annotation WHERE id=1354637 AND version=2;
DELETE FROM annotation WHERE id=1354863 AND version=1;
DELETE FROM annotation WHERE id=1354908 AND version=1;
DELETE FROM annotation WHERE id=1354926 AND version=1;
DELETE FROM annotation WHERE id=1355386 AND version=1;
DELETE FROM annotation WHERE id=1355470 AND version=1;
DELETE FROM annotation WHERE id=1355521 AND version=1;
DELETE FROM annotation WHERE id=1355978 AND version=1;
DELETE FROM annotation WHERE id=1355979 AND version=1;
DELETE FROM annotation WHERE id=1355980 AND version=1;
DELETE FROM annotation WHERE id=1355990 AND version=1;
DELETE FROM annotation WHERE id=1355994 AND version=1;
DELETE FROM annotation WHERE id=1356014 AND version=1;
DELETE FROM annotation WHERE id=1356076 AND version=1;
DELETE FROM annotation WHERE id=1356077 AND version=1;
DELETE FROM annotation WHERE id=1356085 AND version=1;
DELETE FROM annotation WHERE id=1356248 AND version=1;
DELETE FROM annotation WHERE id=1356287 AND version=1;
DELETE FROM annotation WHERE id=1356289 AND version=1;
DELETE FROM annotation WHERE id=1356291 AND version=1;
DELETE FROM annotation WHERE id=1356675 AND version=1;
DELETE FROM annotation WHERE id=1357272 AND version=1;
DELETE FROM annotation WHERE id=1357459 AND version=1;
DELETE FROM annotation WHERE id=1357542 AND version=1;
DELETE FROM annotation WHERE id=1358035 AND version=1;
DELETE FROM annotation WHERE id=1359731 AND version=1;
DELETE FROM annotation WHERE id=1359986 AND version=1;
DELETE FROM annotation WHERE id=1360044 AND version=1;
DELETE FROM annotation WHERE id=1360628 AND version=1;
DELETE FROM annotation WHERE id=1361302 AND version=1;
DELETE FROM annotation WHERE id=1361619 AND version=1;
DELETE FROM annotation WHERE id=1362521 AND version=1;
DELETE FROM annotation WHERE id=1362529 AND version=1;
DELETE FROM annotation WHERE id=1362614 AND version=1;
DELETE FROM annotation WHERE id=1362790 AND version=1;

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM annotation_invalid_annot_bs_count;

/* ============================================== */
/* DANGLING LINKS / tag_bs ==> non-existent byway */
/* ============================================== */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_bs_invalid_byway_count AS 
   SELECT 'tag_bs rows which reference non-existent byway_segments'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      WHERE geo.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   tag_bs with byway_ids of phantom byways. */
CREATE TEMPORARY VIEW tag_bs_invalid_byway_rows AS 
   SELECT lnk.id, lnk.version, lnk.tag_id, lnk.byway_id 
      FROM tag_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.tag_id, lnk.byway_id 
      ORDER BY lnk.byway_id;

/* == Newly orphaned features == */

/* This is the list of referenced tags, grouped by ID (so we're
   ignoring the version). */
CREATE TEMPORARY VIEW tag_bs_invalid_byway_linked AS
   SELECT ann.id
      FROM tag_bs AS lnk 
      LEFT OUTER JOIN byway_segment AS geo
         ON lnk.byway_id = geo.id
      JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY ann.id;

/* This is the list of referenced tags that are also linked to real
   byways in addition to the phantom byways, so we should not delete these 
   tags. */
CREATE TEMPORARY VIEW tag_bs_invalid_byway_tags_in_use AS 
   SELECT ann.id
      FROM tag_bs_invalid_byway_linked AS ann
      JOIN tag_bs AS lnk
         ON lnk.tag_id = ann.id
      WHERE lnk.id NOT IN (SELECT id FROM tag_bs_invalid_byway_rows) 
      GROUP BY ann.id;

/* This is the list of referenced tags only used for phantom byways, so 
   we can delete these. */
CREATE TEMPORARY VIEW tag_bs_invalid_byway_tags_deletable AS 
   SELECT ann.id
      FROM tag_bs_invalid_byway_linked AS ann
      WHERE ann.id NOT IN (SELECT id FROM tag_bs_invalid_byway_tags_in_use);

/* == Do the DELETE! == */

\qecho 
\qecho Number of tag_bs rows that reference non-existent byways:

SELECT * FROM tag_bs_invalid_byway_count;

\qecho 
\qecho Specifically, these tag_bs rows reference phantom byways:

SELECT id FROM tag_bs_invalid_byway_rows;

\qecho 
\qecho Deleting 22 rows from tag_bs:

DELETE FROM tag_bs WHERE id IN
   (1410877
   ,1410877
   ,1410878
   ,1410878
   ,1449508
   ,1470700
   ,1470816
   ,1470836
   ,1471326
   ,1471368
   ,1472787
   ,1472844
   ,1473455
   ,1473459
   ,1473546
   ,1474598
   ,1477255
   ,1480151
   ,1481810
   ,1491149
   ,1491159
   ,1496211);

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM tag_bs_invalid_byway_count;

\qecho 
\qecho After DELETEing, these tags are now orphaned and may be deleted
\qecho (NOTE As of the writing of this script, this value should be 0!)

SELECT * FROM tag_bs_invalid_byway_tags_deletable;

/* ============================================ */
/* DANGLING LINKS / tag_bs ==> non-existent tag */
/* ============================================ */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_bs_invalid_tag_count AS 
   SELECT 'tag_bs rows which reference non-existent tags'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_bs AS lnk 
      LEFT OUTER JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE ann.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   tag_bs with tag_ids of phantom tags. */
CREATE TEMPORARY VIEW tag_bs_invalid_tag_rows AS 
   SELECT lnk.id, lnk.version, lnk.tag_id, lnk.byway_id 
      FROM tag_bs AS lnk 
      LEFT OUTER JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE ann.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.tag_id, lnk.byway_id 
      ORDER BY lnk.byway_id;

/* == Newly orphaned features == */

/* Skipping: It doesn't make sense to check for newly orphaned byway_segments, 
             as byways are valid regardless of whether or not something links 
             to them. */

/* == Do the DELETE! == */

\qecho 
\qecho Number of tag_bs rows that reference non-existent tags:

SELECT * FROM tag_bs_invalid_tag_count;

\qecho 
\qecho Specifically, these tag_bs rows reference phantom tags:

SELECT id FROM tag_bs_invalid_tag_rows;

\qecho 
\qecho Deleting 4 rows from tag_bs:

DELETE FROM tag_bs WHERE id IN
   (1428859
   ,1428859
   ,1428858
   ,1428858);

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM tag_bs_invalid_tag_count;

/* ================================================= */
/* DANGLING LINKS / tag_point ==> non-existent point */
/* ================================================= */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_point_invalid_point_count AS 
   SELECT 'tag_point rows which reference non-existent points'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_point AS lnk 
      LEFT OUTER JOIN point AS geo
         ON lnk.point_id = geo.id
      WHERE geo.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   tag_point with point_ids of phantom points. */
CREATE TEMPORARY VIEW tag_point_invalid_point_rows AS 
   SELECT lnk.id, lnk.version, lnk.tag_id, lnk.point_id 
      FROM tag_point AS lnk 
      LEFT OUTER JOIN point AS geo
         ON lnk.point_id = geo.id
      JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.tag_id, lnk.point_id 
      ORDER BY lnk.point_id;

/* == Newly orphaned features == */

/* This is the list of referenced tags, grouped by ID (so we're
   ignoring the version). */
CREATE TEMPORARY VIEW tag_point_invalid_point_rows_linked AS
   SELECT ann.id
      FROM tag_point AS lnk 
      LEFT OUTER JOIN point AS geo
         ON lnk.point_id = geo.id
      JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE geo.id IS NULL
      GROUP BY ann.id;

/* This is the list of referenced tags that are also linked to real
   points in addition to the phantom points, so we should not delete these 
   tags. */
CREATE TEMPORARY VIEW tag_point_invalid_point_tags_in_use AS 
   SELECT ann.id
      FROM tag_point_invalid_point_rows_linked AS ann
      JOIN tag_point AS lnk
         ON lnk.tag_id = ann.id
      WHERE lnk.id NOT IN (SELECT id FROM tag_point_invalid_point_rows) 
      GROUP BY ann.id;

/* This is the list of referenced tags only used for phantom points, so 
   we can delete these. */
CREATE TEMPORARY VIEW tag_point_invalid_point_tags_deletable AS 
   SELECT ann.id
      FROM tag_point_invalid_point_rows_linked AS ann
      WHERE ann.id NOT IN (SELECT id FROM tag_point_invalid_point_tags_in_use);

/* Do the DELETE! */

/* == Do the DELETE! == */

\qecho 
\qecho Number of tag_bs rows that reference non-existent points:

SELECT * FROM tag_point_invalid_point_count;

\qecho 
\qecho Specifically, these tag_point rows reference phantom points:

SELECT id FROM tag_point_invalid_point_rows;

\qecho 
\qecho Deleting 3 rows from tag_point:

DELETE FROM tag_point WHERE id IN
   (1487135
   ,1435239
   ,1435239);

\qecho 
\qecho After DELETEing, the row count should now be 0:

\qecho 
SELECT * FROM tag_point_invalid_point_count;

\qecho 
\qecho After DELETEing, these tags are now orphaned and may be deleted
\qecho (NOTE As of the writing of this script, this value should be 0!)

SELECT * FROM tag_point_invalid_point_tags_deletable;

/* =============================================== */
/* DANGLING LINKS / tag_point ==> non-existent tag */
/* =============================================== */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_point_invalid_tag_count AS 
   SELECT 'tag_point rows which reference non-existent tags'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_point AS lnk 
      LEFT OUTER JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE ann.id IS NULL;

/* Set of the bad rows. (Each ID listed just once.) These are the rows in 
   tag_point with tag_ids of phantom tags. */
CREATE TEMPORARY VIEW tag_point_invalid_tag_rows AS 
   SELECT lnk.id, lnk.version, lnk.tag_id, lnk.point_id 
      FROM tag_point AS lnk 
      LEFT OUTER JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE ann.id IS NULL
      GROUP BY lnk.id, lnk.version, lnk.tag_id, lnk.point_id 
      ORDER BY lnk.point_id;

/* == Newly orphaned features == */

/* Skipping: It doesn't make sense to check for newly orphaned points, as 
             points are valid regardless of whether or not something links to 
             them. */

/* Do the DELETE! */

\qecho 
\qecho Number of tag_point rows that reference non-existent tags:

SELECT * FROM tag_point_invalid_tag_count;

\qecho 
\qecho These tag_point rows reference phantom tags:

SELECT id FROM tag_point_invalid_tag_rows;

\qecho 
\qecho Deleting 2 rows from tag_point:

DELETE FROM tag_point WHERE id IN
   (1416932
   ,1416932);

\qecho 
\qecho After DELETEing, the row count should now be 0:

SELECT * FROM tag_point_invalid_tag_count;

/* =================================================== */
/* DANGLING LINKS / tag_region ==> non-existent region */
/* =================================================== */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_region_invalid_region_count AS 
   SELECT 'tag_region rows which reference non-existent regions'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_region AS lnk 
      LEFT OUTER JOIN region AS geo
         ON lnk.region_id = geo.id
      WHERE geo.id IS NULL;

/* == Do the DELETE! == */

/* Nothing to do! */

\qecho 
\qecho Number of tag_region rows that reference non-existent regions
\qecho (NOTE As of the writing of this script, this value should be 0!)

SELECT * FROM tag_region_invalid_region_count;

/* ================================================ */
/* DANGLING LINKS / tag_region ==> non-existent tag */
/* ================================================ */

/* == Dangling links == */

CREATE TEMPORARY VIEW tag_region_invalid_tag_count AS 
   SELECT 'tag_region rows which reference non-existent tags'::TEXT 
         AS Comment, COUNT(*) AS Count
      FROM tag_region AS lnk 
      LEFT OUTER JOIN tag AS ann
         ON lnk.tag_id = ann.id
      WHERE ann.id IS NULL;

/* == Do the DELETE! == */

/* Nothing to do! */

\qecho 
\qecho Number of tag_region rows that reference non-existent tags
\qecho (NOTE As of the writing of this script, this value should be 0!)

SELECT * FROM tag_region_invalid_tag_count;

/* ==== */
/* DONE */
/* ==== */

\qecho 
\qecho All done!
\qecho 

COMMIT;

