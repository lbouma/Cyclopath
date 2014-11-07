/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: ~ 160 mins. */


-- FIXME: This script takes too long. Offload to not the production server.
-- 2014.09.19: Moved to scripts/daily/usage_weekly until either moved to
--             non-production server; for now we might want to want it
--             weekly.


begin read only;

-- User accounts created per day
\o accounts-new.daily.out
select to_char(dates.day_, 'YYYYMMDD'), COALESCE(ct, 0)
from date_since_live as dates
     LEFT OUTER JOIN
     (select
        date_trunc('day', created) as day_,
        count(*) as ct
      from user_
      group by day_) as user_
     ON (dates.day_ = user_.day_)
order by dates.day_;

-- Unique IP's per day which were not used by logged-in users the same day
\o users.daily_anon.out
select day_, count(*) from
   (select
       to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
       client_host
    from apache_event
    group by client_host, day_
    having max(username) is null) as foo
group by day_
order by day_;

-- Unique IP's per week which were not used by logged-in users the same week
\o users.weekly_anon.out
select week, count(*) from
   (select
       to_char(date_trunc('week', timestamp_tz), 'YYYYMMDD') as week,
       client_host
    from apache_event
    group by client_host, week
    having max(username) is null) as foo
group by week
order by week;

-- Unique logged-in usernames per day
\o users.daily_li.out
select day_, count(*) from
   (select
       to_char(date_trunc('day', timestamp_tz), 'YYYYMMDD') as day_,
       username
    from apache_event
    where
       username is not null
       and username not in (select username from user_ where dont_study)
    group by username, day_) as foo
group by day_
order by day_;

-- Unique logged-in usernames per week
\o users.weekly_li.out
select week, count(*) from
   (select
       to_char(date_trunc('week', timestamp_tz), 'YYYYMMDD') as week,
       username
    from apache_event
    where
       username is not null
       and username not in (select username from user_ where dont_study)
    group by username, week) as foo
group by week
order by week;

/* Reset \o */
\o

commit;

