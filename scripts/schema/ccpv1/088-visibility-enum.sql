/* Remove concept of transient and replace with a 3-value enum representing
   who can search for a route: all, owner, noone. */

/* Create a visibility table that holds 3 enum values:
    1. - all (anyone can discover the route via client sharing features)
    2. - owner (only owner can discover the route via client sharing features)
    3. - noone (no one can rediscover route via client sharing features)
   Note that this excludes viewing a route via deep-link, this determines
   only things that are searchable or discoverable by the client.

   As an example, a "private" route that has a deep-link is actually 
   a shared route that is searchable only by the owner. */

/* NOTE: In a future script, the revision table will need to be updated to
   reflect the addition of a visibility. */

BEGIN TRANSACTION;

CREATE TABLE visibility (
   code INT PRIMARY KEY,
   text TEXT NOT NULL
);

INSERT INTO visibility VALUES (1, 'all');
INSERT INTO visibility VALUES (2, 'owner');
INSERT INTO visibility VALUES (3, 'noone');

COMMIT;

