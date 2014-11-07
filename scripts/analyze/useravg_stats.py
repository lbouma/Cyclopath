#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script prints some statistics about how well user ratings are predicted
# by the average rating of other users.
#
# Usage:
#
#   $ export PYSERVER_HOME=/whatever
#   $ ./useravg_stats.py

from __future__ import division

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue

class Rating(object):

   __slots__ = ('user',
                'bid',
                'rating',
                'pred')

   def __init__(self, row):
      self.user = row['username']
      self.bid = row['byway_id']
      self.rating = row['value']

   def predict(self, b_ratings):
      pool = [r.rating for r in b_ratings[self.bid] if r.user != self.user]
      self.pred = sum(pool) / len(pool)

   def error(self):
      return abs(self.rating - self.pred)

b_ratings = dict()  # rating objects by byway_id
ratings = list()    # list of all rating objects
b_ae = dict()       # average error for each byway

db = db_glue.new()
rows = db.sql("""SELECT username, byway_id, value
                 FROM byway_rating
                 WHERE username ~ '^test.*' """)
print 'Fetched %d rows' % (len(rows))
db.close()

for row in rows:
   r = Rating(row)
   b_ratings.setdefault(r.bid, list())
   b_ratings[r.bid].append(r)

# remove byways with only one user rating, also build ratings list
for bid in b_ratings.keys():
   if (len(b_ratings[bid]) <= 1):
      del b_ratings[bid]
   else:
      ratings += b_ratings[bid]

# predict ratings
for rat in ratings:
   rat.predict(b_ratings)

# figure per-byway stats -- aren't list comprehensions grand?
b_ae.update([(bid, sum([r.error() for r in rs]) / len(rs))
             for (bid, rs) in b_ratings.iteritems()])

print 'Total user ratings:', len(ratings)

print 'MAE:', sum([r.error() for r in ratings]) / len(ratings)

err1_ct = len([r for r in ratings if r.error() >= 1])
print 'Ratings in error by >= 1 star:', err1_ct, err1_ct / len(ratings)

err2_ct = len([r for r in ratings if r.error() >= 2])
print 'Ratings in error by >= 2 stars:', err2_ct, err2_ct / len(ratings)

print 'Blocks w/ at least two user ratings:', len(b_ratings)

err1_ct = len([bid for (bid, ae) in b_ae.iteritems() if ae >= 1])
print 'Blocks w/ average error >= 1 star:', err1_ct, err1_ct / len(b_ratings)

err2_ct = len([bid for (bid, ae) in b_ae.iteritems() if ae >= 2])
print 'Blocks w/ average error >= 2 stars:', err2_ct, err2_ct / len(b_ratings)

