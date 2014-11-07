/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds password salting and hashing and some functions to
   manipulate passwords. */

begin transaction;
set constraints all deferred;

/* Return a random string for use as salt. Note that this method of producing
   a hex salt string is not particularly well thought out, but
   cryptographically robust randomness is not needed here. */

/* 20111229: [lb] notes: The salt is used so we don't store plaintext 
 * passwords. Also, md5() is a oneway street, so even with the salt and a
 * hashed password, a hacker would still have to use a brute force attack
 * vector, I'm sure. Really, I just wanted to say "attack vector". */
-- FIXME: Need stronger hashes.
--        See: https://en.wikipedia.org/wiki/Key_strengthening
--        and https://www.tarsnap.com/scrypt.html
create function salt_new() returns text as $$
begin
   return substr(to_hex((random() * (1<<30))::int), 0, 7);
end
$$ language plpgsql;

/* Fix up user_ table. */

alter table user_ add column salt text default salt_new();
update user_ set salt = salt_new();
alter table user_ alter column salt set not null;

\d user_

/* Return the hash of the given cleartext password. */
create function pw_hash(uname text, cleartext text) returns text as $$
begin
   return md5((select salt from user_ where username = uname) || cleartext);
end
$$ language plpgsql;

select pw_hash('reid', 'foobar');

/* Set the given user's password to pw. */
create function password_set(uname text, pw text) returns void as $$
begin
   update user_ set password = pw_hash(uname, pw) where username = uname;
end
$$ language plpgsql;

select password_set('reid', 'foobar');

/* Return true if the given user/pass pair (cleartext) is sufficient for
   authentication, false otherwise. */
create function login_ok(uname text, pw text) returns boolean as $$
declare
   pw_stored text;
   can_login boolean;
begin
   select password, login_permitted
     from user_
     into pw_stored, can_login
     where username = uname;
   if not found then
      return 'false';
   end if;
   return (pw_hash(uname, pw) = pw_stored AND can_login = 'true');
end
$$ language plpgsql;

select * from user_ where login_permitted order by username;

select login_ok('reid', 'foobar');
select login_ok('reid', 'hello');
select login_ok('nobody', 'foobar');

--rollback;
commit;

