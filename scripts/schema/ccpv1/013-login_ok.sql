/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds password salting and hashing and some functions to
   manipulate passwords. */

begin transaction;
set constraints all deferred;

/* Return true if the given user/pass pair (cleartext) is sufficient for
   authentication, false otherwise. (Updated to disallow login if password is
   too short.) */
create or replace function login_ok(uname text, pw text) returns boolean as $$
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
   return (pw IS NOT NULL
           AND length(pw) >= 6
           AND pw_hash(uname, pw) = pw_stored
           AND can_login = 'true');
end
$$ language plpgsql;

commit;
--rollback;
