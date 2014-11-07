#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script is used after merges to "surrender" all conflicts, i.e. accept
# the other guy's version of everything. Obviously, use with caution.

import glob
import os
import re

print '*** Surrendering:'

filenames = os.popen("svn status | grep '^C' | cut -c8-").read().split()

for filename in filenames:
   revs = [int(re.search(r'(\d+)$', x).group(1))
           for x in glob.glob('%s.merge-right*' % (filename))]
   revs.sort()
   victor = '%s.merge-right.r%d' % (filename, revs[-1])
   os.system('mv -v %s %s' % (victor, filename))
   #os.system('rm -v %s.merge-* %s.working' % (filename, filename))
   os.system('svn resolved %s' % (filename))

print '*** Done. After you commit, say:'

me = re.search(r'^URL: (.+)$',
               os.popen('svn info').read(),
               re.MULTILINE).group(1)
other = re.search(r'^svnmerge: source is "(.+)"$',
                  os.popen('svnmerge avail --verbose').read(),
                  re.MULTILINE).group(1)
print '      svn diff %s %s' % (other, me)
print '*** There should be no output.'

