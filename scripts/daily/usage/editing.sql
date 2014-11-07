/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: < 1 min. */

/* FIXME: The queries in this file rely on rather nasty outer joins against a
   generated table in order to produce zeroes on days with no activity. */

begin read only;

\set start_date '\'2008-05-01\''

-- Revisions per day
\o revisions.daily.out
select to_char(dates.day_, 'YYYYMMDD'), COALESCE(ct, 0)
from date_since_live as dates
     LEFT OUTER JOIN
     (select
        date_trunc('day', timestamp) as day_,
        count(*) as ct
      from revision
      where (   (username is null)
             or (username not in
                  (select username from user_ where dont_study)))
      group by day_) as revision
     ON (dates.day_ = revision.day_)
order by dates.day_;

-- Reverts per day
\o reverts.daily.out
select to_char(dates.day_, 'YYYYMMDD'), COALESCE(ct, 0)
from date_since_live as dates
     LEFT OUTER JOIN
     (select
        date_trunc('day', created) as day_,
        count(*) as ct
      from revert_event
      group by day_) as revert
     ON (dates.day_ = revert.day_)
order by dates.day_;

/* Reset \o */
\o

commit;

