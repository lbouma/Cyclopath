#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.
#
# This script submits the GWIS request found in the dump file passed on the
# command line to the pyserver listening on localhost.
#
# Note that the replay isn't 100% identical to the original request; we don't
# try to match headers, HTTP version, etc.

import os
import sys
sys.path.insert(0, os.path.abspath('%s/util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import re
import sys
import urllib2

from util_ import misc

verbose = True

filename = sys.argv[1]

print 'Replaying request %s ...' % (filename)

m = re.match(r'.+\n.+\s(/gwis.+)\s.+\n\n.+\n\n(.*)',
             open(filename).read(), re.DOTALL)
if (m is None):
   print 'file does not seem to be a request dump'
   sys.exit(1)
# url is, e.g., 'http://localhost' + m.group(1)
url = 'http://%s%s' % (conf.server_names[0], m.group(1),)

body = m.group(2)

if (verbose):
   print
   print 'URL: %s' % (url)
   print
   print 'Body: --\n'
   sys.stdout.write(body)
   print

req = urllib2.Request(url=url, data=body)

print 'Result: --\n'
print misc.urllib2_urlopen_readall(req)
print

__example_wget__ = (
"""
wget --post-data '<data><metadata><user name="landonb" token="asdasdasdasdasd"/></metadata></data>' "http://ccpv3/gwis?rqst=revision_get&rcnt=20&wgeo=1&brid=2500677&rcnt=20&wgeo=1&gwv=3&browid=asdasdasdasdasd&sessid=asdasdasdasd&body=yes"
"""
)

