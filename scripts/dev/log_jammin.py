#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script counts lines of code over time.

# Usage:
#
#FIXME: these parms.
#  ./log_jammin.py --svnpath $svnroot/public/ccpv2 --svnrels $svnroot/releases
#
#  or
#
#  $ nohup ./log_jammin.py --svnpath $svnroot/public/ccpv2 \
#                          --svnrels $svnroot/releases | tee loj.txt 2>&1 &

"""

FIXME: landonb_pre-route-sharing_nnnn isn't returning anything, so
       graph jumps from CcpV1 to CcpV3...

I added $svnroot/public/ccpv2_trunk but have not tested:
./log_jammin.py \
 --svnhier \
      $svnroot/br/landonb_ccpv2_route_manip_nnnn \
      $svnroot/br/landonb_pre-route-sharing_nnnn \
      $svnroot/public/ccpv2_trunk \
      $svnroot/public/trunk \
 --svnrels $svnroot/releases \
 --svnlogf /ccp/dev/ccpv3_trunk/log.txt

# --svnpath $svnroot/br/landonb_ccpv2_route_manip_nnnn \

nohup ./log_jammin.py \
  --svnpath $svnroot/br/landonb_ccpv2_route_manip_nnnn \
  --svnrels $svnroot/releases | tee loj.txt 2>&1 &
"""

# This script requires PyYAML:
#    cd /export/scratch/ccp/opt/.downloads
#    wget -N http://pyyaml.org/download/pyyaml/PyYAML-3.10.tar.gz
#    tar xvf PyYAML-3.10.tar.gz
#    cd PyYAML-3.10
#    python setup.py install --user
#

# FIXME: Script should be able to pick up where it left off. Check out the last
# revision or release and any since then and append to the gnuplot file. Maybe
# just write a file called log_jammin.place with
# last_revision: 26658
# last_release: 51.1
# cloc_path:
# first_day:
# today_day:
# compare_scale:
# maybe just Pickle a dictionary?

# FIXME: --exclude-list-file does not seem to exclude the cloc script, which is
# 8K lines long. --exclude-dir doesn't work, either.
# Here's what it adds to misc:
# Language  files      blank        comment           code
#    Perl   4             58             69            203
#    Perl   5            674            988           6932
# For now you could just use the same 'misc' count since it rarely changes...
# or after 2011-12-x start subtracting it......
#
# Messing around on the command line suggests that using a relative path to the
# source code fixes the problem, at least with
# ok: ./cloc-1.55/cloc-1.55.pl --exclude-dir=cloc-1.55 ../../scripts
# not ok:
# ./cloc-1.55/cloc-1.55.pl --exclude-dir=cloc-1.55 /ccp/dev/cp_trunk_v2/scripts

# FIXME: Add this script to a nightly cron job.

script_name = ('')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-12-10'

import datetime
from decimal import Decimal
import glob
import re
import shutil
import subprocess
import time
import traceback
import yaml

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
# Make our path before pyserver_glue calls os.chdir.
script_root = os.path.abspath(os.curdir)
# Now load pyserver_glue.
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# NOTE: Not using Ccp_Script_Args.
try:
   import argparse
except ImportError, e:
   from util_ import argparse

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.INFO
log_level = logging.DEBUG
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

from util_ import misc

# ***

#cloc_path = os.path.join(script_root, 'cloc-1.55', 'cloc-1.55.pl')
cloc_path = os.path.join(script_root, 'cloc-1.60', 'cloc-1.60.pl')

# Start at the beginning of 2006.
#first_day = datetime.date(2006, 01, 01)
# $ svn info .../project/Grouplens/svn/cyclingproject/releases/1
# Last Changed Rev: 6708
# Last Changed Date: 2008-05-08 13:20:52 -0500 (Thu, 08 May 2008)
first_day = datetime.date(2008, 05, 01)
#first_day = datetime.date(2011, 12, 01)

today_day = datetime.date.today()
#today_day = datetime.date(2011, 12, 31)

#compare_scale = datetime.timedelta(weeks=1)
#compare_scale = datetime.timedelta(weeks=4)
compare_scale = datetime.timedelta(weeks=2)

releases_pre_ccpv2 = Decimal('49.1')
releases_pre_1051 = Decimal('43')

# FIXME: I'm not sure this works. I've noticed different results running CLOC
# on the command line with relative paths versus running this script which uses
# absolute paths (doing the latter seems to break the exclude rules).
cloc_exclude_dirs = 'cloc-1.55,pychart,rpdb,rpy2,winpdb,.svn'

# ***

log = g.log.getLogger('_log_jammin_')

debug_depth = None
#debug_depth = 5
#debug_depth = 2
#debug_depth = 3

debug_skip_trunk = False
#debug_skip_trunk = True
debug_skip_relss = False
#debug_skip_relss = True

debug_skip_fetchlog = False
#debug_skip_fetchlog = True

debug_skip_checkout = False
#debug_skip_checkout = True

debug_skip_checkout_remove = False
#debug_skip_checkout_remove = True

debug_skip_cloc_solo = False
#debug_skip_cloc_solo = True

debug_skip_cloc_diff = False
#debug_skip_cloc_diff = True

debug_skip_exports = False
#debug_skip_exports = True

#debug_skip_to_time_unit = None
#debug_skip_to_time_unit = 94
debug_skip_to_revision = None
#debug_skip_to_revision = 26523

# ***

class Log_Jammin_ArgParser(argparse.ArgumentParser):

   #
   def __init__(self):
      argparse.ArgumentParser.__init__(self)
      self.cli_opts = None
      self.handled = False

   #
   def get_opts(self):
      self.prepare();
      self.parse();
      #self.verify();
      g.assurt(self.cli_opts is not None)
      return self.cli_opts

   #
   def prepare(self):
      '''Defines the CLI options for this script'''

      # Script version.

      self.add_argument('-v', '--version', action='version',
         version='%s version %2s' % (script_name, script_version,))

      # ***

      # SVN path to the trunk.
      # SVN branch hierarchy -- since branches reference revisions in their
      # parents, we need to try the whole tree when looking for a revision.
      self.add_argument('-p', '--svnhier', dest='svnhier',
                        action='store', type=str, required=True,
                        default=[], nargs='+',
                        help='a list of svn paths to search for revisions')

      # When the trunk was made public, we scrubbed older revisions. I think
      # they're in SVN somewhere, but I can't find 'em. Don't waste your time
      # looking for revisions that don't exist.
      #  r16396 | reid | 2010-03-12 16:39:14 -0600 (Fri, 12 Mar 2010) | 2 lines
      #  Move the trunk into the public zone.
      self.add_argument('-r', '--first_revision', dest='first_revision',
                        action='store', type=int, required=False,
                        default=16396)

      # SVN path to the releases.
      self.add_argument('-R', '--svnrels', dest='svnrels',
                        action='store', type=str, required=True)

      # Optional: SVN path to the leafy branch SVN log.
      # DEVS: Use this switch to save time testing; otherwise, i.e., from cron,
      #       you don't want to specify this switch unless you know your log is
      #       up to date.
      self.add_argument('--svnlogf', dest='svnlogf',
                        action='store', type=str, required=False,
                        default='')

      self.add_argument('-t', '--tmppath', dest='tmppath',
                        action='store', type=str, required=False,
                        default='/tmp/log_jammin')

      self.add_argument('-i', '--interactive', dest='interactive',
                        action='store', type=str, required=False,
# FIXME: make default False
                        default=True)

   #
   def parse(self):
      '''Parse the command line arguments.'''
      self.cli_opts = self.parse_args()
      # NOTE: parse_args halts execution if user specifies:
      #       (a) '-h', (b) '-v', or (c) unknown option.

   # ***

# ***

class Log_Jammin(object):

   def __init__(self):
      # Source code by release.
      self.releases = []
      # Source code by trunk revision.
      self.revisions = []
      self.checked_out = []
      self.no_checkout = []
      # Create the output lookups.
      self.croc_solo = {}
      self.croc_diff = {}
      self.rels_diff = {}
      # Create the stats lookup.
      self.stats = {}

   # ***

   #
   def assert_(self, condition):
      if not condition:
         if self.cli_opts.interactive:
            # Dump to a python shell and make the user investigate.
            log.warning('Fatal error. Please debug!')
            log.warning(traceback.format_exc())
            import pdb; pdb.set_trace()
         g.assurt(condition)

   # ***

   #
   def go(self):
      time_0 = time.time()
      parser = Log_Jammin_ArgParser()
      self.cli_opts = parser.get_opts()
      if not parser.handled:
         try:
            self.go_go()
         except AssertionError:
            if self.cli_opts.interactive:
               # Dump to a python shell and make the user investigate.
               log.warning('Fatal error. Please debug!')
               # FIXME: I don't think the traceback prints useful info.
               log.warning(traceback.format_exc())
               import pdb; pdb.set_trace()
            raise
         finally:
            log.info('Script complete! Ran in %s'
                     % (misc.time_format_elapsed(time_0),))
         self.print_stats()

   # ***

   #
   def go_go(self):
      try:
         # Make sure the tmp directory exists.
         cmd_and_args = ['/bin/mkdir', '-p', self.cli_opts.tmppath,]
         the_resp = misc.process_check_output(cmd_and_args)
         self.assert_(not the_resp)
         # Init. the stats
         for svn_path in self.cli_opts.svnhier:
            self.stats[svn_path] = 0
         # Get the SVN log of the leafiest branch. Look for revisions from any
         # of the branches in the hierarchy (starting at the leaf).
         # MAYBE: In SVN, each revision no. corresponds to a checkin of files,
         #        but is there anyway to find out the base directory path of
         #        each revision, given just a revision no., without having to
         #        do trial and error?
         if not debug_skip_trunk:
            self.process_trunk()
         # Our SVN history only extends back to March, 2010, when the code was
         # made public -- and I can't find the original SVN trunk. So get
         # releases from the releases folder to fill in the long ago history.
         if not debug_skip_relss:
            self.process_releases()
         # Print out the results.
         self.print_results()
         # Generate the images.
         self.generate_pngs()
         # Copy the images to the htdocs exports/ directory. [lb] supposes
         # clients won't care about these... but it's as good a place as any.
         # Though maybe we can make some subdirectories.
         self.install_exports()
      except subprocess.CalledProcessError, e:
         log.warning('CalledProcessError: %s' % (str(e),))

   # ***

   #
   def process_trunk(self):
      leafy_log_branch = self.cli_opts.svnhier[0]
      log_cache = os.path.join(self.cli_opts.tmppath, 'log_jammin_svn.log')
      if self.cli_opts.svnlogf:
         # DEVS: This is for testing, if you want to use a log file you've
         #       generated.
         log.info('Reading existing user-generated log: %s'
                  % (self.cli_opts.svnlogf,))
         log_f = open(self.cli_opts.svnlogf, 'r')
         the_log = log_f.read()
         log_f.close()
      elif not debug_skip_fetchlog:
         # NORMALS: Normally, this script makes a fresh log file, which takes a
         #          few seconds.
         log.info('Fetching fresh log for: %s' % (leafy_log_branch,))
         cmd_and_args = ['svn', 'log', leafy_log_branch,]
         ## no? This hangs if the svn command resets the SSH connection and
         ## doesn't actually run. I.e., if you see
         ##  Identity added: /home/misc00/landonb/.ssh/id_rsa (/home/misc00/..)
         the_log = misc.process_check_output(cmd_and_args)
         # DEVS: This script doesn't really keep to cache the log except unless
         #       you're debugging this script, but we cache it always anyway.
         log_f = open(log_cache, 'w')
         log_f.write(the_log)
         log_f.close()
      else:
         # DEVS: This is for testing, if you want to use this script's log file
         #       that it generated the last time it ran.
         log.info('Reading existing script-generated log: %s' % (log_cache,))
         log_f = open(log_cache, 'r')
         the_log = log_f.read()
         log_f.close()
      # Parse the log.
      self.consume_log(the_log)
      log.info('Found %d revisions for branch "%s".'
         % (len(self.revisions), os.path.basename(leafy_log_branch),))
      # Check out pairs of revisions and analyze the code.
      self.checkout_and_analyze_revisions()

   #
   def process_releases(self):
      cmd_and_args = ['svn', 'list', self.cli_opts.svnrels,]
      rel_list = misc.process_check_output(cmd_and_args)
      list_lines = rel_list.split('\n')
      # Each line is a number followed by a slash, e.g., '51.1/'.
      self.releases = [Decimal(x.rstrip('/')) for x in list_lines if x]
      self.releases.sort()
      log.info('Found %d releases under "%s".'
         % (len(self.releases), os.path.basename(self.cli_opts.svnrels),))
      self.checkout_and_analyze_releases()

   # ***

   #re_rev_delim = r'^-+$'
   re_rev_delim = re.compile(r'------------------------------------------------------------------------$')

# FIXME: Check this: new: compile
   re_rev_data = re.compile(
      r'^r([0-9]+) \| '
      + r'(\w+) \| '
      + r'([0-9]{4}-[0-9]{2}-[0-9]{2} '
      + r'[0-9]{2}:[0-9]{2}:[0-9]{2} '
      + r'-?[0-9]{4} '
      + r'\([a-zA-Z]{3}, [0-9]{2} [a-zA-Z]{3} [0-9]{4}\))'
      + r' \| ([0-9]+) lines?$')

   # Sandbox testing:
   #ln1 = 'r26656 | landonb | 2011-12-10 15:17:34 -0600 (Sat, 10 Dec 2011) | 1 line'
   #m = re_rev_data.match(ln1)

   #
   def consume_log(self, the_log):
      # E.g., this is what svn log returns:
      '''
      ------------------------------------------------------------------------
      r26656 | landonb | 2011-12-10 15:17:34 -0600 (Sat, 10 Dec 2011) | 1 line

      Script to auto-generate Config_Logging.as. Also added job_action and
      job_status enum classes to pyserver.
      ------------------------------------------------------------------------
      r26655 | landonb | 2011-12-10 02:26:40 -0600 (Sat, 10 Dec 2011) | 1 line
      ...
      '''
      log_lines = the_log.split('\n')
      revision_id = None
      committed_by = ''
      commit_date = ''
      comment_lines = list()
      state = 'reset'
      for line in log_lines:
         if state == 'rev_data':
            m = Log_Jammin.re_rev_data.match(line)
            if m is not None:
               # Record the last revision.
               if revision_id is not None:
                  self.record_rev(revision_id, committed_by, commit_date,
                                  comment_lines)
               # Remember the new revision.
               revision_id = int(m.group(1))
               committed_by = m.group(2)
               commit_date = m.group(3)
               svn_lines = int(m.group(4)) # Not sure what this value means...
               comment_lines = list()
               state = 'blank_line'
            else:
               # As of 2011.12.12/r26657, there are 3 checkins with comments
               # with lines that are solely dashed.
               log.debug('False delimiter detected.')
               comment_lines += line
               state = 'comment_lines'
         elif state == 'blank_line':
            self.assert_(line == '')
            state = 'comment_lines'
         else:
            m = Log_Jammin.re_rev_delim.match(line)
            if state == 'reset':
               self.assert_(m is not None)
               state = 'rev_data'
            elif state == 'comment_lines':
               if m is None:
                  comment_lines += line
                  state = 'comment_lines'
               else:
                  state = 'rev_data'
            else:
               self.assert_(False)
      # Record the final revision.
      self.record_rev(revision_id, committed_by, commit_date, comment_lines)

   # ***

   p_rname = 0
   p_revid = 1
   p_cmmtr = 2
   p_cdate = 3
   p_cmmts = 4

   #
   def record_rev(self, revision_id, committed_by, commit_date, comment_lines):
      log.verbose('revision_id: %s [%s]' % (revision_id, type(revision_id),))
      # The svn log is order latest revision to first revision, but we build
      # our lookup from first to last.
      self.revisions.insert(0, (None, int(revision_id), committed_by,
                                commit_date, comment_lines,))

   # ***

   #
   def checkout_and_analyze_revisions(self):

      # This script only works on two or revisions.
      if len(self.revisions) < 2:
         log.warning('Cannot run script on first revision, sorry!')
         self.assert_(False)

      last_rdat = None
      last_path = ''
      revs_visited = 0
      last_day = None

      # self.revisions is sorted by first to last revision.
      #if debug_depth:
      #   log.warning(
      #      'Truncating revisions list to last %d entries per debug_depth.'
      #      % (debug_depth,))
      #   self.revisions = self.revisions[-debug_depth:]

      for rdat in self.revisions:
         revision_id = rdat[Log_Jammin.p_revid]
         log.debug('checkout_and_analyze_revs: on rev: %06d' % (revision_id,))
         self.assert_(revision_id > 0)
         global debug_skip_to_revision
         if debug_skip_to_revision is not None:
            if revision_id < debug_skip_to_revision:
               continue
            elif revision_id == debug_skip_to_revision:
               debug_skip_to_revision = None
         this_day = self.rdat_get_date(rdat)
         if ((last_day is not None)
             and ((len(self.revisions) - 1) != revs_visited)
             and ((last_day + compare_scale) > this_day)):
            continue # Wait until checkin at least a time unit later.
         # Make the local file path.
         co_path = os.path.join(self.cli_opts.tmppath, ('r%d' % revision_id))
         if not debug_skip_checkout:
            # When the trunk was made public, earlier revisions were omitted,
            # but they still appear in the log.
            if ((self.cli_opts.first_revision is not None)
                and (self.cli_opts.first_revision > revision_id)):
               log.debug('Skipping lost revision: %d' % revision_id)
               self.no_checkout.append(revision_id)
               continue
            log.info('Checking out revision: %d' % (revision_id,))
            # Try getting the source, starting with the leaf and working our
            # way up the branch hierarchy until we find the revision.
            for svn_path in self.cli_opts.svnhier:
               co_rev = '%s@%d' % (svn_path, revision_id,)
               co_okay = self.try_checkout(co_rev, co_path, revision_id)
               if co_okay:
                  self.stats[svn_path] += 1
                  break
               else:
                  log.debug('Rev not found: %s' % (co_rev,))
               # else, keep looping
            if not co_okay:
               log.debug('Rev. not found in any branch: %d' % (revision_id,))
               self.no_checkout.append(revision_id)
               continue
            else:
               self.checked_out.append(revision_id)
         if not debug_skip_cloc_solo:
            self.something_Croc_one(rdat, co_path)
         if last_path:
            if not debug_skip_cloc_diff:
               self.something_Croc_two(rdat, co_path, last_rdat, last_path)
            self.cleanup_co(last_path)
         last_rdat = rdat
         last_path = co_path
         revs_visited += 1
         last_day = this_day
         if debug_depth and (debug_depth == revs_visited):
            log.warning('Bailing early per debug_depth!')
            break
      self.cleanup_co(last_path)

   #
   def checkout_and_analyze_releases(self):
      if len(self.releases) < 2:
         log.warning('Cannot run script on any less than two releases, sorry!')
         self.assert_(False)
      last_rdat = None
      last_path = ''
      rels_visited = 0
      last_rel_date = None
      #
      for rel_num in self.releases:
         relname = str(rel_num)
         svn_path = '%s/%s' % (self.cli_opts.svnrels, relname,)
         rdat = self.release_get_rdat(relname, svn_path)
         #
         if rel_num > releases_pre_ccpv2:
            # This is when Ccpv2 was made, so don't mix the releases anymore,
            # since the V1 trunk lines don't change much from here.
            break
         # With the 1051 branch, the cutoff is rel 44.
         if rel_num > releases_pre_1051:
            # This is when Ccpv2 was made, so don't mix the releases anymore,
            # since the V1 trunk lines don't change much from here.
            break
         #
         rel_date = self.rdat_get_date(rdat)
         if ((last_rel_date is not None)
             and ((len(self.releases) - 1) != rels_visited)
             and ((last_rel_date + compare_scale) > rel_date)):
            continue # Wait until checkin at least a time unit later.
         last_rel_date = rel_date
         #
         log.info('Checking out release: %s' % (relname,))
         # Make the local file path.
         local_path = os.path.join(self.cli_opts.tmppath, ('REL-%s' % relname))
         if not debug_skip_checkout:
            suc = self.try_checkout(svn_path, local_path)
            self.assert_(suc)
         if not debug_skip_cloc_solo:
            self.something_Croc_one(rdat, local_path)
         if last_path:
            if not debug_skip_cloc_diff:
               self.something_Croc_two(rdat, local_path, last_rdat, last_path)
            self.cleanup_co(last_path)
         last_rdat = rdat
         last_path = local_path
         rels_visited += 1
         if debug_depth and (debug_depth == rels_visited):
            log.warning('Bailing early per debug_depth!')
            break
      self.cleanup_co(last_path)



   # ***

   re_checkout_rev = 'Checked out revision ([0-9]+).\n$'

   # Sandbox.
   #the_resp = 'A    /tmp/log_jammin/REL-3/pyserver\nU   /tmp/log_jammin/REL-3\nChecked out revision 26667.\n'
   #m = re.search(re_checkout_rev, the_resp)

   # Returns True if co_path@co_rev exists and is checked out okay.
   def try_checkout(self, co_rev, co_path, revision_id=None):
      try:
         cmd_and_args = ['svn', 'co', co_rev, co_path,]
         the_resp = misc.process_check_output(cmd_and_args)
         # The response is, e.g.,
         #    A    /tmp/log_jammin/r26657/pyserver
         #    ...
         #    Checked out revision 26657.
         log.verbose('the_resp: %s' % (the_resp,))
         log.debug('the_resp: %s' % (the_resp[-28:],))
         success = not the_resp.endswith("' doesn't exist\n")
         if success:
            if revision_id is not None:
               # This is for the branch hierarchy, --svnhier.
               self.assert_(the_resp.endswith('Checked out revision %d.\n'
                                              % revision_id))
            else:
               # This is for the release branches, --svnrels.
               m = re.search(Log_Jammin.re_checkout_rev, the_resp)
               self.assert_(m is not None)
      except subprocess.CalledProcessError:
         success = False
      return success

   # ***

   # E.g., this is what svn info returns:
   '''
   $ svn info svn+ssh://${USER}@${CS_PRODUCTION}/project/Grouplens/svn/cyclingproject/releases/20
   Path: 20
   URL: svn+ssh://${USER}@${CS_PRODUCTION}/project/Grouplens/svn/cyclingproject/releases/20
   Repository Root: svn+ssh://${USER}@${CS_PRODUCTION}/project/Grouplens/svn
   Repository UUID: e6cc3703-4d0c-0410-8df7-e55f7143975b
   Revision: 26665
   Node Kind: directory
   Last Changed Author: reid
   Last Changed Rev: 8569
   Last Changed Date: 2008-09-20 17:54:18 -0500 (Sat, 20 Sep 2008)

   Killed by signal 15.
   '''

   re_sinfo_author = re.compile(r'^Last Changed Author: (.*)$', re.MULTILINE)
   re_sinfo_rev = re.compile(r'^Last Changed Rev: ([0-9]+)$', re.MULTILINE)
   # C.f. re_rev_data (above)
   #re_sinfo_date = (
   #     r'^Last Changed Date: ([0-9]{4})-([0-9]{2})-([0-9]{2}) '
   #   + r'[0-9]{2}:[0-9]{2}:[0-9]{2} '
   #   + r'-?[0-9]{4} '
   #   + r'\([a-zA-Z]{3}, [0-9]{2} [a-zA-Z]{3} [0-9]{4}\)')
   re_sinfo_date = re.compile(
      r'^Last Changed Date: ([0-9]{4}-[0-9]{2}-[0-9]{2} '
         + r'[0-9]{2}:[0-9]{2}:[0-9]{2} '
         + r'-?[0-9]{4} '
         + r'\([a-zA-Z]{3}, [0-9]{2} [a-zA-Z]{3} [0-9]{4}\))',
      re.MULTILINE)

   # regex sandbax
   # re.match doesn't work because it looks from start of line?
   #import re
   #rel_info = 'Path: 1\nURL: svn+ssh://user@server.tld/project/Grouplens/svn/cyclingproject/releases/1\nRepository Root: svn+ssh://user@server.tld/project/Grouplens/svn\nRepository UUID: e6cc3703-4d0c-0410-8df7-e55f7143975b\nRevision: 26665\nNode Kind: directory\nLast Changed Author: reid\nLast Changed Rev: 6708\nLast Changed Date: 2008-05-08 13:20:52 -0500 (Thu, 08 May 2008)\n\n'
   #rel_info = 'a\nLast Changed Author: reid\n'
   #m = re_sinfo_author.search(rel_info) ; print m

   #
   def release_get_rdat(self, relname, svn_path):
      #
      cmd_and_args = ['svn', 'info', svn_path,]
      rel_info = misc.process_check_output(cmd_and_args)
      #info_lines = rel_list.split('\n')
      # Why do I default to using re.match, which matches at the start of the
      # string. Use re.search if you want MULTILINE to work.
      m = Log_Jammin.re_sinfo_author.search(rel_info)
      committed_by = m.group(1)
      #
      m = Log_Jammin.re_sinfo_rev.search(rel_info)
      rev_id = int(m.group(1))
      #
      m = Log_Jammin.re_sinfo_date.search(rel_info)
      #rev_year = int(m.group(1))
      #rev_month = int(m.group(2))
      #rev_day = int(m.group(3))
      #rev_date = datetime.date(rev_year, rev_month, rev_day)
      #commit_date = rev_date
      commit_date = m.group(1)
      #
      comment_lines = ''
      #
      rdat = (relname, rev_id, committed_by, commit_date, comment_lines,)
      #
      return rdat

   # ***

   # E.g., this is what CLOC returns:
   '''
   $ ./cloc-1.55.pl /ccp/dev/cp_trunk_v2 --quiet --progress-rate=0

   http://cloc.sourceforge.net v 1.55  T=6.0 s (161.7 files/s, 32800.3 lines/s)
   ------------------------------------------------------------------------
   Language              files          blank        comment           code
   ------------------------------------------------------------------------
   Python                  300          14618          17981          44288
   ActionScript            235           7520          11763          29522
   MXML                    107           3388           1128          20185
   SQL                     204           4889           7270          15693
   Java                     59           1172           3129           6357
   Javascript                6            241            259           1407
   HTML                      7            288             28           1278
   XML                      20             51             65           1087
   CSS                       7            149             75            749
   Bourne Shell             16            197            235            571
   m4                        2            172              0            226
   Perl                      4             58             69            203
   Bourne Again Shell        1             32             46            153
   PHP                       1             33             35             79
   make                      1             16             27             70
   ------------------------------------------------------------------------
   SUM:                    970          32824          42110         121868
   ------------------------------------------------------------------------
   '''

   # We use this for startswith. The whole line of output is, e.g.,
# http://cloc.sourceforge.net v 1.60  T=2.15 s (199.7 files/s, 25901.0 lines/s)
   #cloc_outp_intro = 'http://cloc.sourceforge.net v 1.55'
   cloc_outp_intro = 'http://cloc.sourceforge.net v 1.60'

   re_cloc_delim = re.compile(r'^-+$')

   re_cloc_header = re.compile(
     r'^([a-zA-Z]+)  +([a-zA-Z]+)  +([a-zA-Z]+)  +([a-zA-Z]+)  +([a-zA-Z]+)$')

   # The +? makes the plus operator not greedy, so one space can be
   # differentiated from two or more spaces.
   re_cloc_data = re.compile(
      r'^([a-zA-Z0-9 ]+?)  +([0-9]+)  +([0-9]+)  +([0-9]+)  +([0-9]+)$')

   re_cloc_footer = re.compile(
     r'^SUM:  +([0-9]+)  +([0-9]+)  +([0-9]+)  +([0-9]+)$')

   # Sandbox testing:
   #ln1 = 'http://cloc.sourceforge.net v 1.55  T=6.0 s (161.7 files/s, 32800.3 lines/s)'
   #ln1.startswith(cloc_outp_intro)
   #ln2 = '------------------------------------------------------------------------'
   #m = re_cloc_delim.match(ln2) ; print m
   #ln3 = 'Language              files          blank        comment           code'
   #m = re_cloc_header.match(ln3) ; print m
   #ln4 = 'Bourne Again Shell        1             32             46            153'
   #m = re_cloc_data.match(ln4) ; print m
   #ln5 = 'm4 c3 p0                  2            172              0            226'
   #m = re_cloc_data.match(ln5) ; print m
   #ln6 = 'SUM:                    970          32824          42110         121868'
   #m = re_cloc_footer.match(ln6) ; print m

   #
   def something_Croc_one(self, rdat, co_path):
      # FIXME: Neither exclude seems to work...
      cmd_and_args = [cloc_path,
                      co_path,
                      '--quiet',
                      '--progress-rate=0',
                      ]
      #
      exclude_switch = self.cloc_get_exclude_switch()
      if exclude_switch:
         cmd_and_args.append(exclude_switch)
      if cloc_exclude_dirs:
         cmd_and_args.append('--exclude-dir=%s' % (cloc_exclude_dirs,))
      #
      log.info('CLOCing revn: %d' % (rdat[Log_Jammin.p_revid],))
      log.debug('CLOCing checkout: %s' % (cmd_and_args,))
      cloc = misc.process_check_output(cmd_and_args)
      log.verbose('CLOC results: %s' % (cloc,))
      cloc_lines = cloc.split('\n')
      counts = {}
      state = 'reset1'
      next_state = ''
      for line in cloc_lines:
         if state == 'reset1':
            if line != '':
               # E.g., <<CLOC line: Use of qw(...) as parentheses is deprecated
               # at /export/scratch/ccp/dev/cp_2628/scripts/dev/cloc-1.55/
               #     cloc-1.55.pl line 1841.>>
               log.error('CLOC line: %s' % (line,))
            self.assert_(line == '')
            state = 'reset2'
         elif state == 'reset2':
            if not line.startswith(Log_Jammin.cloc_outp_intro):
               log.error('Unexpected cloc version: %s / %s'
                         % (line, Log_Jammin.cloc_outp_intro,))
               self.assert_(False)
            state = 'delim'
            next_state = 'header'
         elif state == 'delim':
            m = Log_Jammin.re_cloc_delim.match(line)
            self.assert_(m is not None)
            state = next_state
            next_state = ''
         elif state == 'header':
            m = Log_Jammin.re_cloc_header.match(line)
            self.assert_(m is not None)
            state = 'delim'
            next_state = 'data'
         elif state == 'data':
            m = Log_Jammin.re_cloc_delim.match(line)
            if m is not None:
               state = 'footer'
            else:
               m = Log_Jammin.re_cloc_data.match(line)
               self.assert_(m is not None)
               self.proc_croc_data(m, counts)
            # No state change.
         elif state == 'footer':
            m = Log_Jammin.re_cloc_footer.match(line)
            self.proc_croc_footer(m, counts, rdat)
            self.assert_(m is not None)
            state = 'delim'
            next_state = 'end'
         elif state == 'end':
            self.assert_(line == '')
            state = 'eof'
         elif state == 'eof':
            self.assert_(False)
         else:
            self.assert_(False)

   # ***

   p_cnt_files = 0
   p_cnt_blank = 1
   p_cnt_comments = 2
   p_cnt_code = 3

   #
   # CLOC has a --yaml switch but this is just as easy to parse the text output
   def proc_croc_data(self, m, counts):
      lang = m.group(1)
      cnt_files = int(m.group(2))
      cnt_blank = int(m.group(3))
      cnt_comments = int(m.group(4))
      cnt_code = int(m.group(5))
      cnts = [cnt_files, cnt_blank, cnt_comments, cnt_code,]
      if lang == 'Python':
         self.assert_('py' not in counts)
         counts['py'] = cnts
      elif lang in ('ActionScript', 'MXML',):
         try:
            some_cnts = counts['as']
            for i in xrange(4):
               some_cnts[i] += cnts[i]
         except KeyError:
            counts['as'] = cnts
      elif lang == 'SQL':
         self.assert_('sql' not in counts)
         counts['sql'] = cnts
      elif lang == 'Java':
         self.assert_('java' not in counts)
         counts['java'] = cnts
      else:
         try:
            some_cnts = counts['misc']
            for i in xrange(4):
               some_cnts[i] += cnts[i]
         except KeyError:
            counts['misc'] = cnts

   #
   def proc_croc_footer(self, m, counts, rdat):
      tot_filts = int(m.group(1))
      tot_blank = int(m.group(2))
      tot_comments = int(m.group(3))
      tot_code = int(m.group(4))
      cnts = [tot_filts, tot_blank, tot_comments, tot_code,]
      counts['total'] = cnts
      log.debug('CROC: counts: %s' % (counts,))
      # If there's already a record for this time unit, remove the old one
      # (this causes release info to replace simple revision info).
      rdat_date = self.rdat_get_date(rdat)
      days_since_2006 = rdat_date - first_day
      this_unit = days_since_2006.days / compare_scale.days
      for old_rev_id, (old_rdat, old_cnts,) in self.croc_solo.iteritems():
         old_date = self.rdat_get_date(old_rdat)
         days_since_2006 = old_date - first_day
         old_unit = days_since_2006.days / compare_scale.days
         if old_unit == this_unit:
            self.croc_solo.pop(old_rev_id)
            break
      # FIXME: Whatever revs are time units 71 and 72 are anomalies (very large
      # misc). Check them out and investiage.
      # _log_jammin_  #  Adding rec for rev 21391 / timeunit 71.
      # _log_jammin_  #  Adding rec for rev 21654 / timeunit 72.
      log.debug('Adding rec for rev %d / timeunit %d.'
                % (rdat[Log_Jammin.p_revid], this_unit,))
      self.croc_solo[rdat[Log_Jammin.p_revid]] = (rdat, counts,)

   # ***

   #
   def something_Croc_two(self, lhs_rdat, lhs_path, rhs_rdat, rhs_path):
      # CLOC's yaml is, e.g.,
      #
      # same :
      #   - language : Bourne Again Shell
      #     files_count : 1
      #     blank : 0
      #     comment : 46
      #     code : 153
      # same_total :
      #     sum_files : 963
      #     blank : 0
      #     comment : 41987
      #     code : 121671
      # modified :
      #   - language : ...
      # modified_total :
      #     sum_files : ...
      # added :
      #   - language : ...
      # added_total :
      #     sum_files : ...
      # removed :
      #   - language : ...
      # removed_total :
      #     sum_files : ...

      cmd_and_args = [cloc_path,
                      '--diff',
                      '--yaml',
                      '--quiet',
                      '--progress-rate=0',
                      # FIXME: Why not use cloc_exclude_dirs?
                      '--exclude-dir=cloc-1.55',
                      ]
      #
      exclude_switch = self.cloc_get_exclude_switch()
      if exclude_switch:
         cmd_and_args.append(exclude_switch)
      #
      cmd_and_args += [lhs_path, rhs_path,]

      log.info('CLOCing diff: %d:%d' % (lhs_rdat[Log_Jammin.p_revid],
                                        rhs_rdat[Log_Jammin.p_revid],))
      log.debug('DIFFCLOCing: %s' % (cmd_and_args,))
      cloc_yaml = misc.process_check_output(cmd_and_args)
      log.verbose('CLOC cloc_yaml: %s' % (cloc_yaml,))
      caml = yaml.load(cloc_yaml)
      if not lhs_rdat[Log_Jammin.p_rname]:
         self.croc_diff[lhs_rdat[Log_Jammin.p_revid]] = (lhs_rdat, caml,)
      else:
         self.rels_diff[lhs_rdat[Log_Jammin.p_revid]] = (lhs_rdat, caml,)

   # ***

   #
   def cloc_get_exclude_switch(self):
      exclude_switch = ''
      exclude_fname = os.path.abspath(
         os.path.join(script_root, 'log_jammin_exclude.txt'))
      if os.path.exists(exclude_fname):
         exclude_switch = '--exclude-list-file=%s' % (exclude_fname,)
      return exclude_switch

   # ***

   #
   def cleanup_co(self, co_path):
      # Cleanup
      self.assert_(co_path and (co_path != '/'))
      self.assert_(len(co_path.split(os.path.sep)) > 2)
      self.assert_(co_path.startswith(self.cli_opts.tmppath))
      self.assert_(os.path.isdir(co_path))
      if not debug_skip_checkout_remove:
         cmd_and_args = ['/bin/rm', '-rf', co_path,]
         log.debug('Removing checkout folder: %s' % (cmd_and_args,))
         the_resp = misc.process_check_output(cmd_and_args)

   # ***

   #
   def dat_file_write_solo(self):
      log.info('Creating solo gnuplot data file.')
      #
      csolo_path = os.path.join(script_root, 'croc_solo.dat')
      #os.path.join(self.cli_opts.tmppath, 'croc_solo.dat')
      log.debug('Creating dat file: %s' % (csolo_path,))
      csolo_f = open(csolo_path, 'w')
      #
      n_cols = 5
      csolo_f.write('Epochdays misc *.java *.sql *.py *.as rid\n')
      #
      last_day = first_day
      # The lookup is ordered by rev id ascending when we go through the
      # revisions, but we add the releases to it later. So sort the two sorted
      # sublists together.
      rev_ids = self.croc_solo.keys()
      rev_ids.sort()
      for rev_id in rev_ids:
         (rdat, cnts,) = self.croc_solo[rev_id]
         this_day = self.rdat_get_date(rdat)
         self.gnuplop_fillin_histo_blanks(csolo_f, n_cols, this_day, last_day,
                                          compare_scale)
         days_since_2006 = this_day - first_day
         cnt_misc = self.cnts_get(cnts, 'misc')
         cnt_java = self.cnts_get(cnts, 'java')
         cnt_sql = self.cnts_get(cnts, 'sql')
         cnt_py = self.cnts_get(cnts, 'py')
         cnt_as = self.cnts_get(cnts, 'as')
         xtick = '%d' % ((days_since_2006.days / compare_scale.days),)
         if rdat[Log_Jammin.p_rname]:
            xtick += '-REL-%s' % rdat[Log_Jammin.p_rname]
         csolo_f.write('%s %d %d %d %d %d %d\n'
                       % (xtick,
                          cnt_misc, cnt_java, cnt_sql, cnt_py, cnt_as, rev_id))
         # FIXME: Care about lines of comments?
         last_day = this_day
      # Fill in zeros from the last checkin until today.
      log.debug('solo: today_day: %s / last_day: %s / first_day: %s'
                % (today_day, last_day, first_day,))
      self.gnuplop_fillin_histo_blanks(csolo_f, n_cols, today_day, last_day,
                                       compare_scale)
      #
      csolo_f.close()

   #
   def cnts_get(self, cnts, key):
      try:
         cnt = cnts[key][Log_Jammin.p_cnt_code]
      except KeyError:
         cnt = 0
      return cnt

   #
   def dat_file_write_diff(self):
      self.dat_file_write_diff_for(self.croc_diff, 'croc_diff.dat')
      self.dat_file_write_diff_for(self.rels_diff, 'rels_diff.dat')

   #
   def dat_file_write_diff_for(self, lkup_diff, dat_path):
      log.info('Creating diff gnuplot data at %s.' % (dat_path,))
      #
      cdiff_path = os.path.join(script_root, dat_path)
      #os.path.join(self.cli_opts.tmppath, dat_path)
      log.debug('Creating dat file: %s' % (cdiff_path,))
      cdiff_f = open(cdiff_path, 'w')
      #
      n_cols = 4
      cdiff_f.write('Epochdays removed added modified same rid\n')
      #
      last_day = first_day
      #
      rev_ids = lkup_diff.keys()
      rev_ids.sort()
      for rev_id in rev_ids:
         (rdat, caml,) = lkup_diff[rev_id]
         this_day = self.rdat_get_date(rdat)
         self.gnuplop_fillin_histo_blanks(cdiff_f, n_cols, this_day, last_day,
                                          compare_scale)
         days_since_2006 = this_day - first_day
         #xtick = '%d' % days_since_2006.days
         xtick = '%d' % ((days_since_2006.days / compare_scale.days),)
         if rdat[Log_Jammin.p_rname]:
            xtick += '-REL-%s' % rdat[Log_Jammin.p_rname]
         cdiff_f.write('%s %d %d %d %d %d\n'
                       % (xtick,
                          caml['removed_total']['code'],
                          caml['added_total']['code'],
                          caml['modified_total']['code'],
                          caml['same_total']['code'],
                          rev_id,))
         last_day = this_day
      # Fill in zeros from the last checkin until today.
      log.debug('diff: today_day: %s / last_day: %s / first_day: %s'
                % (today_day, last_day, first_day,))
      self.gnuplop_fillin_histo_blanks(cdiff_f, n_cols, today_day, last_day,
                                       compare_scale)
      #
      cdiff_f.close()

   # ***

   #
   def png_file_write_solo(self):
      self.png_file_write_for('croc_solo.gnuplot')

   #
   def png_file_write_diff(self):
      self.png_file_write_for('croc_diff.gnuplot')
      # There's a rels_diff.dat but no corresponding gnuplot.
      #self.png_file_write_for('rels_diff.gnuplot')

   #
   def png_file_write_for(self, dat_path):
      log.info('Creating gnuplot image for %s.' % (dat_path,))
      #
      cdiff_path = os.path.join(script_root, dat_path)
      log.debug('Creating png file: %s' % (cdiff_path,))

      # pyserver_glue chdired us, but our gnuplot uses paths relative to our
      # dir, so chdir back.
      was_dir = os.path.abspath(os.curdir)
      os.chdir(script_root)

      # process_check_output: resp:
      # "/export/scratch/ccp/dev/cp_2628/scripts/dev/croc_diff.gnuplot",
      #  line 36: warning: Skipping unreadable file "croc_diff.dat"
      #
      # plot 'croc_diff.dat' using 2:xtic(1), for [i=3:4] '' using i
      #                                             ^
      # "/export/scratch/ccp/dev/cp_2628/scripts/dev/croc_diff.gnuplot",
      #  line 36: ':' expected
      cmd_and_args = ['gnuplot', cdiff_path,]
      # process_check_output: resp: Could not find/open font when opening
      #     font arial, trying default
      # "/export/scratch/ccp/dev/cp_2628/scripts/dev/croc_solo.gnuplot",
      #  line 69: warning: Skipping unreadable file "croc_solo.dat"

      # process_check_output: resp: Cannot open load file 'croc_diff.gnuplot'
      #cmd_and_args = ['gnuplot', dat_path,]

      the_resp = misc.process_check_output(cmd_and_args)
      log.verbose('the_resp: %s' % (the_resp,))

      os.chdir(was_dir)

   # ***

   re_rev_data_date = re.compile(
        r'([0-9]{4})-([0-9]{2})-([0-9]{2}) '
      + r'[0-9]{2}:[0-9]{2}:[0-9]{2} '
      + r'-?[0-9]{4} '
      + r'\([a-zA-Z]{3}, [0-9]{2} [a-zA-Z]{3} [0-9]{4}\)')

   #
   def rdat_get_date(self, rdat):#, last_day):
      m = Log_Jammin.re_rev_data_date.match(rdat[Log_Jammin.p_cdate])
      g.assurt(m is not None)
      rev_year = int(m.group(1))
      rev_month = int(m.group(2))
      rev_day = int(m.group(3))
      this_day = datetime.date(rev_year, rev_month, rev_day)
      return this_day

   #
   def gnuplop_fillin_histo_blanks(self, out_f, num_num_cols, this_day,
                                         last_day, compare_scale):
      log.verbose('histo_blanks: this_day: %s / last_day: %s'
                  % (this_day, last_day,))
      # Fill in the missing days, since gnuplot's rowstacked histogram can't
      # handle dates on the axis, so we have to force the axis to scale.
      zeros = ' '.join(['0',] * num_num_cols)
      rev_id = 0
      self.assert_(this_day >= last_day)
      last_unit = (last_day - first_day).days / compare_scale.days
      final_unit = (this_day - first_day).days / compare_scale.days
      for date_unit in xrange(last_unit + 1, final_unit):
         out_f.write('%s %s %d\n' % (date_unit, zeros, rev_id,))

   # ***

   #
   def print_results(self):
      if not debug_skip_cloc_solo:
         self.dat_file_write_solo()
      if not debug_skip_cloc_diff:
         self.dat_file_write_diff()

   # ***

   #
   def generate_pngs(self):
      if not debug_skip_cloc_solo:
         self.png_file_write_solo()
      if not debug_skip_cloc_diff:
         self.png_file_write_diff()

   # ***

   #
   def install_exports(self):

      if not debug_skip_exports:

         # Make the output directory if it doesn't exist.
         export_path = os.path.join(script_root, '../../htdocs/statistics')
         if not os.path.exists(export_path):
            try:
               os.mkdir(export_path)
               os.chmod(export_path, 02775)
            except OSError, e:
               log.error('install_exports: cannot mkdir: %s' % (export_path,))
               raise

         # FIXME: Wire these from the Wiki page.
         # FIXME: Also fix the stats images generated by another script.
         self.install_exports_for('croc_solo.png')
         self.install_exports_for('croc_diff.png')
         #self.install_exports_for('rels_diff.png')

   #
   def install_exports_for(self, image_file):
      source_path = os.path.join(script_root, image_file)
      exports_path = os.path.join(script_root, '../../htdocs/statistics',
                                  image_file)
      log.debug('copying image file from/to: %s / %s'
                % (source_path, exports_path,))
      shutil.copyfile(source_path, exports_path)

   # ***

   #
   def print_stats(self):
      log.info('Script stats:')
      log.info(' >> revisions checked-out: %d' % (len(self.checked_out),))
      log.info(' >> revs without checkout: %d' % (len(self.no_checkout),))
      for svn_path in self.cli_opts.svnhier:
         log.info('%20s: %d' % (svn_path, self.stats[svn_path],))
      try:
         log.info(' >> first rev checked-out: %d' % (self.checked_out[0],))
      except IndexError:
         pass
      log.info('Finished log jammin.')

# ***

if (__name__ == '__main__'):
   lj = Log_Jammin()
   lj.go()

