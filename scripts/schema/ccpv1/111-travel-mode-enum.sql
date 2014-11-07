/* Add a travel_mode enum to match the enums defined in pyserver 
   and flashclient.
*/

BEGIN TRANSACTION;

CREATE TABLE travel_mode (
   id INT PRIMARY KEY,
   descr TEXT NOT NULL
);

-- SYNC_ME: Search: Travel Mode IDs
INSERT INTO travel_mode (id, descr) VALUES (0, 'undefined');
INSERT INTO travel_mode (id, descr) VALUES (1, 'bicycle');
INSERT INTO travel_mode (id, descr) VALUES (2, 'transit');
INSERT INTO travel_mode (id, descr) VALUES (3, 'walking');
INSERT INTO travel_mode (id, descr) VALUES (4, 'autocar');

COMMIT;

