#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage
#
__usage_example__ = '''

cd $cp/scripts/dev
./flashclient_macros-make.py
/bin/cp -f macros_development.m4 ../../flashclient/macros.m4
/bin/mv -f macros_development.m4 ../../flashclient/macros_development.m4
/bin/mv -f macros_production.m4 ../../flashclient/macros_production.m4

'''

script_name = ('Generate macros_*.m4')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-05-22'

import datetime
import re

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
# Setup our paths before calling pyserver_glue, which calls os.chdir.
path_to_macros_dev = os.path.abspath(
   '%s/macros_development.m4' % (os.path.abspath(os.curdir),))
path_to_macros_prod = os.path.abspath(
   '%s/macros_production.m4' % (os.path.abspath(os.curdir),))
path_to_flashclient = os.path.abspath(
   '%s/../../flashclient' % (os.path.abspath(os.curdir),))
# Now load pyserver_glue.
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
log_level = logging2.VERBOSE2
log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('flsh_macs_mk')

from grax.access_level import Access_Level
from gwis.query_branch import Query_Branch
from item import item_base
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.grac import group
from item.link import link_attribute
from item.link import link_tag
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

# ***

macros_loggers = [
   #
   # These are the Logging.as loggers.
   ('m4_VERBOSE', 'log.verbose($*)',),
   ('m4_TALKY', 'log.talky($*)',),
   ('m4_DEBUG', 'log.debug($*)',),
   ('m4_INFO', 'log.info($*)',),
   # FIXME: These facilities should log to the server.
   ('m4_WARNING', 'log.warning($*)',),
   ('m4_ERROR', 'log.error($*)',),
   ('m4_CRITICAL', 'log.critical($*)',),
   # NOTE: No one uses EXCEPTION and it's log.error, not log.exception.
   ('m4_EXCEPTION', 'log.error($*)',),
   #
   # These are the speciality loggers.
   #
   #('m4_DEBUG_CLLL', 'G.log_clll.debug($*)',),
   ('m4_DEBUG_CLLL',
      'if (Conf_Instance.debug_loggers_enabled.is_member("call_later")) { '
      + 'G.log_clll.debug($*);'
      + '}',),
   #
   ('m4_DEBUG_TIME',
      'if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { '
      + 'G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);'
      + '}',),
   #
   ('m4_PPUSH',
      'if (Conf_Instance.debug_loggers_enabled.is_member("pixel_push")) { '
      + 'log.debug($*);'
      + '}',),
   #
   ]

macros_header = (
"""m4_dnl Copyright (c) 2006-%d Regents of the University of Minnesota.
m4_dnl For licensing terms, see the file LICENSE.
m4_dnl
m4_dnl There are two m4 files: one for production builds, and another for 
m4_dnl development builds. The latter contains all the Flash trace messages.
m4_dnl
m4_dnl WARNING: DO NOT EDIT macros.m4 - it's not checked into the repository 
m4_dnl                                  and it gets overwritten by make.
m4_dnl
m4_dnl == M4 Caveats ==
m4_dnl
m4_dnl Commas inside 'quoted' "things" are still seen by m4, so
m4_dnl    m4_DEBUG('My string, your string');
m4_dnl prints as
m4_dnl    My string  your string
m4_dnl (note the double space).
m4_dnl
""" % (datetime.date.today().year,))

macros_footer = (
"""m4_dnl
""")

# ***

class Macros_Development(object):

   #
   def __init__(self):
      pass

   path_to_file = path_to_macros_dev

   section_01_runtime_asserts = (
"""m4_dnl == Runtime Asserts ==
m4_dnl
m4_define(`m4_ASSERT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSURT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_EXISTS', `G.assert($1 !== null, "m4___file__:m4___line__")')m4_dnl
m4_dnl m4_define(`m4_ASSERT_FALSE', `G.assert(false, "m4___file__:m4___line__")')m4_dnl
m4_dnl
""")

   section_02_specialized_macros = (
"""m4_dnl == Specialized Macros ==
m4_dnl
m4_dnl FIXME: Following should be logged to the server!
m4_dnl FIXME: m4_ASSERT_ELSE shouldn't assert? should just log instead.
m4_define(`m4_ASSERT_ELSE', `else { G.assert(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_ASSERT_SOFT', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_ELSE_SOFT', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_SERVED', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ELSE_SERVED', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_DEBUG_CLLL', `G.log_clll.debug($*)')m4_dnl
m4_define(`m4_DEBUG_TIME', `if ((G.now() - tstart) >= Conf.debug_time_threshold_ms) { G.log_time.debug("Elapsed time:", (G.now() - tstart), "msec. /", $*);}')m4_dnl
m4_dnl
""")

   section_03_kludgy_trace_macros = (
"""m4_dnl == Kludgy Trace Macros ==
m4_dnl
m4_dnl The following is a big mess because... well, that's the way m4_IT_IS.
m4_dnl If your macro contains newlines, m4 removes them. Which means,
m4_dnl the flex compiler incorrectly reports line numbers, because the 
m4_dnl files in flashclient/build/ are shorter than the source files. 
m4_dnl (Is "shorter" a proper computer sciency term?) So herein, we 
m4_dnl deliberately add newlines to the macros. Use the suffix 2 through 9 on 
m4_dnl m4_ASSERT, m4_DEBUG, and everyone's favorite, m4_VERBOSE.
m4_dnl
m4_dnl Pre-2013.05.22: Is there a way to automate the following, or is this
m4_dnl                 file forever ugly?
m4_dnl Post-2013.05.22: See scripts/dev/flashclient_macros-make.py.
m4_dnl
m4_dnl NOTE: We don't need to kludge m4_ASSERT (e.g., m4_ASSERT2) because 
m4_dnl       assert statements do not contain commas, which is what causes 
m4_dnl       m4 to whack our newlines -- however, we do need to kludge at least
m4_dnl       one m4_ASSERT (e.g., m4_ASSERT2), for asserts that start with an  
m4_dnl       open parentheses followed by a newline, since m4 whacks the CR.
m4_define(`m4_ASSERT2', `G.assert($1, "m4___file__:m4___line__")'
)m4_dnl
m4_dnl 
""")

   #
   def write_section_loggers(self, new_f):
      for logger in macros_loggers:
         for ordinal in xrange(1, 10):
            numeric_postfix = '' if (ordinal == 1) else str(ordinal)
            newlines = "\n" * (ordinal - 1)
            new_f.write(
               "m4_define(`%s%s', `%s'%s)m4_dnl\n"
               % (logger[0], numeric_postfix, logger[1], newlines,))
         #new_f.write("m4_dnl\n")

# ***

class Macros_Production(object):

   def __init__(self):
      pass

   path_to_file = path_to_macros_prod

   section_01_runtime_asserts = (
"""m4_dnl == Runtime Asserts ==
m4_dnl
m4_dnl FIXME [aa] Removes ASSERTs for release builds? Or is that a Bad Idea?
m4_dnl            (We still need to stop control flow, i.e., if we assert that
m4_dnl            something is not null but it is, we have no choice but to
m4_dnl            assert. So maybe the answer is a global try/catch block?)
m4_dnl
m4_define(`m4_ASSERT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSURT', `G.assert($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_EXISTS', `G.assert($1 !== null, "m4___file__:m4___line__")')m4_dnl
m4_dnl m4_define(`m4_ASSERT_FALSE', `G.assert(false, "m4___file__:m4___line__")')m4_dnl
m4_dnl
""")

   section_02_specialized_macros = (
"""m4_dnl == Specialized Macros ==
m4_dnl
m4_define(`m4_ASSERT_ELSE', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_ASSERT_SOFT', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ASSERT_ELSE_SOFT', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_SERVED', `G.assert_soft($1, "m4___file__:m4___line__")')m4_dnl
m4_define(`m4_ELSE_SERVED', `else { G.assert_soft(false, "m4___file__:m4___line__") }')m4_dnl
m4_define(`m4_DEBUG_CLLL', `')m4_dnl
m4_define(`m4_DEBUG_TIME', `')m4_dnl
m4_dnl
""")

   section_03_kludgy_trace_macros = (
"""m4_dnl == Kludgy Trace Macros ==
m4_dnl
m4_dnl See macros_development.m4 for the reason why the following is such a big
m4_dnl mess.
m4_dnl
m4_define(`m4_ASSERT2', `G.assert($1, "m4___file__:m4___line__")'
)m4_dnl
m4_dnl
""")

   #
   def write_section_loggers(self, new_f):
      for logger in macros_loggers:
         for ordinal in xrange(1, 10):
            numeric_postfix = '' if (ordinal == 1) else str(ordinal)
            newlines = "\n" * (ordinal - 1)
            new_f.write(
               "m4_define(`%s%s', `'%s)m4_dnl\n"
               % (logger[0], numeric_postfix, newlines,))
         #new_f.write("m4_dnl\n")

# ***

class Flashclient_Macros__make(object):

   def __init__(self):
      pass

   #
   def go(self):
      self.make_file(Macros_Development())
      self.make_file(Macros_Production())

   #
   def make_file(self, macro_obj):

      new_f = open(macro_obj.path_to_file, 'w')

      new_f.write(macros_header)

      new_f.write(macro_obj.section_01_runtime_asserts)
      new_f.write(macro_obj.section_02_specialized_macros)
      new_f.write(macro_obj.section_03_kludgy_trace_macros)

      macro_obj.write_section_loggers(new_f)

      new_f.write(macros_footer)

      new_f.close()

# ***

if (__name__ == '__main__'):
   fmm = Flashclient_Macros__make()
   fmm.go()

# ***

