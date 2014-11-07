/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script (which does nothing; it's just a readme) is the first in a 
   series of many scripts to convert the entire database schema, adding support
   for arbitrary attributes, permissions and branching. See Bug 1089 and 1977.

   == Notes on Running the Scripts ==

   Running all of the scripts takes a long time, on the order of eight hours. 

      2011.02.xx    Huffy: 3 or 4 hours
      2011.05.20    Huffy: 7h 53m (but there were errors, so this is low.)
      2011.05.23    Huffy: 8h 43m (no errors; excl. anonymizer scripts.)

   To make your life easier, you can run the scripts in the background.

      First, load a fresh copy of the database in use by the trunk

      cd $cp/scripts
      ./dbload

      Next, run the scripts in the background, telling our update script to 
      assume each script succeeds.

         nohup ./schema-upgrade.py cycling4 yesall | tee yesall.txt 2>&1 &

      - nohup:        tells the OS not to kill the script if you log off
      - yesall:       tells schema-upgrade.py to assume each script succeeds
      - pipe to tee:  tee prints to standard out while also filling a file
      - 2>&1 &:       redirects stderr to stdout and runs script in background

      After the scripts run, open yesall.txt and search for ERROR: and make 
      sure there are none. If you found an error and want to debug it without 
      having to run all of the scripts each time you want to test changes to 
      a script, you can run the update to a certain point and tell it to 
      stop when it reaches a certain script.

      For example, suppose I have ten scripts, 01.sql to 10.sql. If the first
      5 scripts work well, but I'm editing the last five, I can update through
      the fifth script and tell update to stop when it gets to the sixth. Then,
      I can copy the database, so I can easily restore to that point.

         cd $cp/scripts
         ./dbload
         nohup ./schema-upgrade.py cycling4 yesall 06.sql \
            | tee yesall.txt 2>&1 &
         pg_dump -U cycling cycling -Fc --exclude-table '''*.apache_event''' \
            > lite.dump

      - 06.sql:       tells schema-update to stop when it reaches 06.sql

      To reload the database, run db_load from the scripts directory.

          ./db_load.sh lite.dump cycling

      The following is from development, 2011.01.25, and can be deleted after 
      the group scripts stop getting tweaked.

         cd $cp/scripts
         ./dbload 4
         nohup ./schema-upgrade.py cycling4 yesall \
            102-apb-23-aattrs-views___.sql | tee yesall-23.txt 2>&1 &
         pg_dump -U cycling cycling4 -Fc --exclude-table '''*.apache_event''' \
            > upgrade-apb-22.dump
         nohup ./schema-upgrade.py cycling4 yesall \
            102-apb-51-groups-shared_1.sql | tee yesall-51.txt 2>&1 &
         pg_dump -U cycling cycling4 -Fc --exclude-table '''*.apache_event''' \
            > upgrade-apb-43.dump
         nohup ./schema-upgrade.py cycling4 yesall \
            102-apb-57-groups-pvt_ins1.sql | tee e-table '''*.apache_event''' \
            > upgrade-apb-56.dump
         nohup ./schema-upgrade.py cycling4 yesall \
            999-anonymize-1-schema-inst.sql | tee yesall-999.txt 2>&1 &
         pg_dump -U cycling cycling4 -Fc --exclude-table '''*.apache_event''' \
            > upgrade-apb-73.dump
         or
            nohup ./schema-upgrade.py cycling4 yesall \
               102-apb-83-cleanp-archives.sql | tee yesall-999.txt 2>&1 &
            pg_dump -U cycling cycling4 -Fc --exclude-table '''*.apache_event''' \
               > upgrade-apb-83.dump
         nohup ./schema-upgrade.py cycling4 yesall | tee yesall-999+.txt 2>&1 &
         pg_dump -U cycling cycling4 -Fc --exclude-table '''*.apache_event''' \
            > upgrade-apb-999.dump

         restore:
         ./db_load.sh upgrade-apb-43.dump cycling4

   == Possibly Outdated Overview of the Scripts ==

   There are about 20 scripts total used to convert the database, grouped 
   into logically applications:

      * The first set of scripts (this one and the next one) create archival 
        schemas for the existing tables, so we can move the old tables out 
        of the schema, create new tables, and then copy data from the 
        archived tables into the new tables.

      * The second set of scripts adds arbitrary attributes to the database. 
        These scripts are quite complicated, since we're shuffling a ton of 
        data around and also making some drastic changes to existing tables.

      * The third set of scripts adds System IDs and Branch IDs to the tables.

      * The fourth set of scripts adds the Branching tables to the database, 
        and it creates the Public Base Map branch.

      * The fifth set of scripts add the Access Control tables to the 
        database. It creates the Public User Group, as well as Private 
        user groups for each user, and creates permissions on all existing 
        items.

      * The sixth set of scripts adds the user watcher tables.

      * The seventh set of scripts cleans up the new schema, since some 
        Postgres activity has to be committed before additional activities 
        can occur.

      * The eighth (and final) set of scripts re-creates the views used to 
        make GIS exports.

   */

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

\qecho 
\qecho This script does nothing; it''s just a README
\qecho 

