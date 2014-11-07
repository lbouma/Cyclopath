#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script sends email reminders for the landmarks experiment.

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from gwis import user_email

from util_ import db_glue


if (__name__ == '__main__'):
   db = db_glue.new()

   res = db.sql(
      """
      SELECT username, trial_num
      FROM landmark_trial
      WHERE condition='later'
            AND track_id > 0
            AND NOT email_sent
            AND (trial_time + interval '1 hour') < now()
      """
   )

   subject = 'Cyclopath notice: Please help us by adding landmarks along your ride'

   for row in res:

      body = ('''\
Hi,

Earlier today we asked you to look out for useful navigation landmarks while
you recorded your bike ride. To add the landmarks, please visit the following
link:

http://magic.cyclopath.org#landmarks?trial=%s

You can open the link in either the web browser or the mobile app. In order to
make the process easier for you, we will show you your ride and the locations
where we prompted you to look for landmarks.

Thank you for helping us test this feature!
      ''' % (row['trial_num']))

      user_email.send(db, row['username'], None, subject, body)

      # After sending summary email, delete the entries from the pending table.
      db.sql(
         """
         UPDATE landmark_trial
         SET email_sent = 't'
         WHERE username = '%s'
            AND trial_num = %s
         """ % (row['username'], row['trial_num']))

