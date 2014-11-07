/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** Adds a table to keep track of user account and ip address bans */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

CREATE TABLE ban (
  username TEXT,
  ip_address INET,
  public_ban BOOL NOT NULL,
  full_ban BOOL NOT NULL,
  activated BOOL NOT NULL,
  created TIMESTAMP NOT NULL,
  expires TIMESTAMP NOT NULL,
  CHECK (username IS NOT NULL OR ip_address IS NOT NULL),
  CHECK ((public_ban AND NOT full_ban) OR (full_ban AND NOT public_ban))
);
CREATE TRIGGER ban_i BEFORE INSERT ON ban
  FOR EACH ROW EXECUTE PROCEDURE set_created();

COMMIT;
