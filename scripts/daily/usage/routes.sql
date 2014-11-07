/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: < 1 min. */

begin read only;

-- New Routes computed per day
\o routes_new.daily.out
select
   to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
   count(*)
from apache_event
where
   (   (    (wfs_request = 'route_get')
        and (request ~ E'^/gwis\\?re?qu?e?st=route_get&beg_addr='))
    or (    (wfs_request = 'GetRoute')
        and (request ~ E'^/wfs\\?request=GetRoute&fromaddr=')))
   and (   (username is null)
        or (username not in (select username from user_ where dont_study)))
group by day_
order by day_;

-- Existing Routes checked out per day
\o routes_old.daily.out
select
   to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
   count(*)
from apache_event
where
   (   (    (wfs_request = 'route_get')
        and (request ~ E'^/gwis\\?re?qu?e?st=route_get&rt_sid='))
    or (    (wfs_request = 'GetRoute')
        and (request ~ E'^/wfs\\?request=GetRoute&routeid=')))
   and (   (username is null)
        or (username not in (select username from user_ where dont_study)))
group by day_
order by day_;

/* Reset \o */
\o

commit;

