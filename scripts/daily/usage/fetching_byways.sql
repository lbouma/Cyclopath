/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: ~ 12 min. */

begin read only;

-- Vector mode pans and zooms per day
\o getfeature.daily.out
select
   to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
   count(*)
from apache_event
where
       (   request ~ E'^/gwis\\?re?qu?e?st=checkout&ityp=byway'
        or request ~ E'^/wfs\\?request=GetFeature&typename=byway')
   and (   (username is null)
        or (username not in (select username from user_ where dont_study)))
group by day_
order by day_;

/* Reset \o */
\o

commit;

