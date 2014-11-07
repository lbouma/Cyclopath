/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: ~ 12 min. */

begin read only;

-- Tiles served per day
\o tiles.daily.out
select
   to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
   count(*)
from apache_event
where (   (request ~ E'^/tilec\\?')
       or (request ~ E'^/tiles/'))
group by day_
order by day_;

/* Reset \o */
\o

commit;

