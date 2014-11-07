/* Convert fake users in the revision table into a single user called
   '_script' and add that user to the user table.*/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO user_ (username, email, login_permitted, dont_study)
   VALUES ('_script', 'info@cyclopath.org', 't', 't');

UPDATE revision
   SET comment = 
         CASE 
            WHEN comment is NULL
               OR comment = ''
            THEN username
            ELSE username || ' ' || comment
         END,
   username = '_script'
   WHERE
     position('_' in username) = 1
     AND username NOT IN (SELECT username FROM user_);

alter table revision
  add constraint revision_username_fk
  foreign key (username) references user_(username) deferrable;

COMMIT;
