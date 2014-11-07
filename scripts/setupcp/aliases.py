#!/usr/bin/python

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./aliases.py --help
#
# Also:
#
#  $ ./aliases.py |& tee 2012.09.29.aliases.txt
#

# This script generates first and last names randomly. Usage:
#
#   $ aliases.py OFFSET COUNT | psql
#
# where OFFSET is the number of aliases already in alias_source and COUNT is
# the number of additional aliases to add.
#
# The random seed is the same each run, so the list of names is predictable.
# Output is a SQL script.
#
# Names are filtered through the Caverphone II phonetic algorithm, so e.g.
# only one of Chris and Kris will appear.
#
# Names from US Census: http://www.census.gov/genealogy/names/names_files.html
#
# Circa 2008: Note that this script takes ~1 minute to run and requires ~1.2GB
#             memory. See notes below: this is because we make an array with
#             18 million elements.

# FIXME: We should just count the rows in aliases so offset doesn't have to be
#        an input...

script_name = ('Insert More Username Aliases')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-09-29'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('aliases')

# *** 

import string
import sys
import random
import re

from util_ import strutil
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

debug_skip_commit = False
#debug_skip_commit = True

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)
      #
      self.add_argument('-C', '--count', dest='row_count',
         action='store', default=0, type=int, required=True,
         help='the number of aliases to insert')

      self.add_argument('-O', '--offset', dest='row_offset',
         action='store', default=0, type=int, required=True,
         help='the row offset at which to start')

# *** Aliases

class Aliases(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def go_main(self):

      do_commit = False

      try:

         self.insert_aliases()

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   #
   def insert_aliases(self):

      # Seed the randomizer. We store the seed in CONFIG so that different
      # installations of Cyclopath don't use the same seed (which doesn't
      # matter unless you want to compare two Ccp datasets; see bug 1572).
      random.seed(conf.aliases_seed)

      log.info('Reading first names...')

      first_names_f = open('census/names.first.txt')
      first_names = first_names_f.readlines()
      firsts = strutil.phonetic_crush(first_names)
      first_names_f.close()

      log.info('Reading last names...')

      last_names_f = open('census/names.last.txt')
      last_names = last_names_f.readlines()
      lasts = strutil.phonetic_crush(last_names)
      last_names_f.close()

      log.info('Found: %d first names / %d last names'
                % (len(firsts), len(lasts),))
      
      log.info('Generating combined names...')
      names = list()
      for first_name in firsts:
         for last_name in lasts:
            alias_name = ('%s_%s' % (first_name, last_name,))
            names.append(alias_name)

      # MAYBE: This is memory intensive... dev machines watch out.
      # FIXME: We're timesing 1291 first names and 14384 last names,
      #        so we're getting an array that's 18,569,744 elements long!
      #        Since we shuffle and we use a seed on random, we've painted
      #        ourselves into a corner -- what we should do is make the alias
      #        name unique and then just try inserting, so we can make a
      #        smaller list of names (and make more names if they're coming up
      #        unique)... in other words, screw the seed and don't make such a
      #        big structure.
      #        FIXME: On my laptop, I'm getting corrupted memory using such a
      #        big array. The first_name keeps showing up as the license
      #        comment from the beginning of this script!??
      log.info('Created %d names pairs' % (len(names),))

      log.info('Shuffling names')
      random.shuffle(names)

      log.info('Locking database')

      revision.Revision.revision_lock_dance(
         self.qb.db, caller='aliases.py')

      log.debug('Generating names list...')

      values_list = []
      # Bug 2735: The range gots to offset plus count, not just count.
      g.assurt(len(names) > (offset + count))
      for i in xrange(offset, offset + count):
         # NOTE: We're adding one to i because i is 0-based but offset is 
         #       1-based.
         # NOTE: We using names[i] and not names[i - offset] so that we pick
         #       up in the names array where we left off the last time we used
         #       this script (we is why we used the same seed for random).
         value_sql = "(%d, %s)" % (i + 1, names[i],)
         log.debug('%s' % (value_sql,))
         values_list.append(value_sql)

      log.info('Inserting into the table...')

      insert_sql = ("INSERT INTO alias_source (id, text) VALUES %s"
                    % (','.join(values_list),))

      self.qb.db.sql(insert_sql)

      log.info('Done inserting.')

   # ***

# ***

if (__name__ == '__main__'):
   aliases = Aliases()
   aliases.go()

