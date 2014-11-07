#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# EXPLAIN: What does this script do?

import sys
from hotshot import stats

print 'Loading profile stats from %s ...' % (sys.argv[1])
s = stats.load(sys.argv[1])

s.strip_dirs()

s.sort_stats('time')
s.print_stats(60)

s.sort_stats('cumulative')
s.print_stats(60)

