# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import re
import traceback

# This is the global namespace.

# 2011.04.19: g.log is the only member of the global namespace. I think there
#             were bigger plans for g.py, but it's only ever housed the logger.
#             See: conf.py, which sets g.log = logging.

# 2011.08.19: Import pyserver_glue so we get os.environ['PYSERVER_HOME'].
# 2013.04.20: pyserver_glue no longer sets os.environ['PYSERVER_HOME'], but
#             we no longer use it. Also, it should still be the first element
#             of sys.path[].
import pyserver_glue

# 2011.01.23: Adding g.assurt so we can show a proper stack trace
ignore_stack_re = re.compile(r'^\s*raise Ccp_Assert\(message\)$')
class Ccp_Assert(AssertionError):
   def __init__(self, message):
      if not message:
         # NO! prints to stderr or something: message = traceback.print_stack()
         #message = traceback.format_exc()
         strip_stack = False
         stack_lines_ = traceback.format_stack()
         stack_lines = []
         for lines in stack_lines_:
            for line in lines.split('\n'):
               if line:
                  #log.debug('Ccp_Assert: line: %s' % (line,))
                  if ignore_stack_re.match(line) is not None:
                     #import pdb; pdb.set_trace()
                     # "raise Ccp_Assert(message)" is actually secondtolast ln
                     # The line before is, e.g., 
                     #  File "/ccp/dev/cp_1051/pyserver/g.py", ln 36, in assurt
                     try:
                        stack_lines.pop()
                     except IndexError:
                        log.error('Ccp_Assert: empty list?')
                     strip_stack = True
                     break
                  stack_lines.append(line)
            if strip_stack:
               break
         message = '\n'.join(stack_lines)
      #Exception.__init__(self, message)
      AssertionError.__init__(self, message)
      #log.error('Ccp_Assert: %s' % (message,))

#traceback.print_exception(*sys.exc_info())

debug_me = False
#debug_me = True

# FIXME: Should we check either of these, i.e., for cron jobs?
#Apr-20 20:40:20  DEBG         schema-up  #  os.getenv("LOGNAME"): landonb
#Apr-20 20:40:20  DEBG         schema-up  #  os.environ.get("TERM"): xterm
# From pyserver, Fedora:
#   os.getenv('LOGNAME') is None
#   os.getenv('TERM') is 'xterm'
# {'LANG': 'C', 
#  'TERM': 'xterm', 
#  'SHLVL': '2', 
#  'INSTANCE': 'minnesota', 
#  'PWD': '/', 
#  'PYSERVER_HOME': '/ccp/dev/cp_nnnn/pyserver', 
#  'PATH': '/sbin:/usr/sbin:/bin:/usr/bin', 
#  '_': '/usr/sbin/httpd'}
iamwhoiam = True
# NOTE: os.getenv same as os.environ.get. Type os.environ to see all.
if ((os.getenv('APACHE_RUN_USER') == 'www-data')  # Ubuntu apache service
    or (os.getenv('_') == '/usr/sbin/httpd')      # Fedora apache service
    or (os.getenv('LOGNAME') == 'www-data')       # Ubuntu routed/mr_do service
    or (os.getenv('LOGNAME') == 'apache')):       # Fedora routed/mr_do service
    # FIXME: What are the mr_do/routed services under Ubuntu?
   iamwhoiam = False

# NOTE: If starting as a service, cannot import rpdb2 here.
#       'cause the cwd is '.'. After pyserver_glue runs, it'll 
#       be corrected, so the import is in the assurt fcn.

# The 'assert' keyword is reserved, so we call it, uh, 'syrt!
def assurt(condit, message=None, soft=False):
   if not bool(condit):
      # FIXME: This doesn't work if being run as a service. Can you figure out
      #        if we're a daemon and throw a normal assert instead?
      if debug_me:
         log.warning('DEBUGGING!!')
         print 'DEBUGGING!!'
         if iamwhoiam:
            import pdb; pdb.set_trace()
         else:
            log.warning('Waiting for remote debug client...')
            print 'Waiting for remote debug client...'
            import rpdb2
            rpdb2.start_embedded_debugger('password', fAllowRemote=True)
      assrt = Ccp_Assert(message)
      if not soft:
         raise assrt
      else:
         log.error('Soft Assert: %s' % (str(assrt),))

#
def assurt_soft(condit, message=None):
   assurt(condit, message, soft=True)

#
# Some debugging hints:
#
#  Start the remote debugger
#  -------------------------
#
#    In one terminal window,
#
#      $ cd /ccp/dev/cp/pyserver/bin/winpdb ; py rpdb2.py
#      > password password
#
#    In your code, start a debug session where you want to break,
#
#      import rpdb2
#      rpdb2.start_embedded_debugger('password', fAllowRemote=True)
#
#    And then back in your terminal window, find the list of
#    waiting sessions,
#
#      > attach
#      Connecting to 'localhost'...
#      Scripts to debug on 'localhost':
#      
#         pid    name
#      --------------------------
#         28969  /ccp/dev/cp/pyserver/g.py
#
#      > attach 28969
#      ...
#
#  Start a local debugger
#  ----------------------
#
#    If you're just running a script (and not pyserver via apache),
#    insert a simple pdb break into your code,
#
#      import pdb;pdb.set_trace()
#
#    You can also use a safer, user-specific mechanism, e.g.,
#
#      conf.break_here('ccpv3')
#

# ***

class Ccp_Shutdown(Exception):
   '''An error telling the code to cleanup as quickly as possible.'''
   def __init__(self, message=''):
      Exception.__init__(self, message)

#
def check_keep_running(keep_running):
   if (keep_running is not None) and (not keep_running.isSet()):
      raise Ccp_Shutdown()

# ***

if (__name__ == '__main__'):
   pass

