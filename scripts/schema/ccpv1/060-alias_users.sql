/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script modifies the user_ table to give each user a unique alias so
   that we can refer to them without comprimising their privacy. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

alter table user_ add column id serial not null unique;
alter table user_ add column alias text unique;

-- keep in sync with below
update user_ set alias = (select text from alias_source
                          where alias_source.id = user_.id);

alter table user_ alter column alias set not null;

\d user_;

select username, email, id, alias from user_ limit 10;

create function user_alias_set() returns trigger as
$$
begin
  NEW.alias = (select text from alias_source where alias_source.id = NEW.id);
  return NEW;
end
$$ language plpgsql;

create trigger user_alias_i before insert on user_
  for each row execute procedure user_alias_set();

insert into user_ (username, email, login_permitted)
  values ('_TEST1', 'x', true);
insert into user_ (username, email, login_permitted)
  values ('_TEST2', 'x', true);
select * from user_ order by created desc limit 2;
delete from user_ where username in ('_TEST1', '_TEST2');
select * from user_ order by created desc limit 2;

commit;
