# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Ack.:
#
#   StackOverflow was 2d google response to "python show memory usage"
#   http://stackoverflow.com/questions/938733/python-total-memory-used
#
#   It references
#
#   the Python Cookbook
#   http://code.activestate.com/recipes/286222/
#
#   Windows WMI documentation
#   http://timgolden.me.uk/python/wmi.html
#   http://pypi.python.org/pypi/WMI/1.3.2

import os
import sys
import traceback

# *** Windows

class Mem_Usage_Windows(object):

   #
   def __init__(self):
      pass

   #
   def get_usage(self):
       from wmi import WMI
       w = WMI('.')
       result = w.query(
          """
          SELECT 
            WorkingSet 
          FROM 
            Win32_PerfRawData_PerfProc_Process 
          WHERE 
            IDProcess=%d
          """ % (os.getpid(),))
       return int(result[0]['WorkingSet'])

# *** Linux

class Mem_Usage_Linux(object):

   # NOTE: Because we're threaded, don't call os.getpid() yet. The Python
   # Cookbook does this, but the PID we see on load is not the PID we see 
   # when we're called later.

   _scale = {'kB': 1024.0, 'mB': 1024.0 * 1024.0,
             'KB': 1024.0, 'MB': 1024.0 * 1024.0}

   #
   def __init__(self):
      pass

   #
   def _VmB(self, VmKey):
      # get pseudo file /proc/<pid>/status
      try:
         try:
            proc_status_f = '/proc/%d/status' % (os.getpid(),)
            t = open(proc_status_f)
            v = t.read()
            t.close()
         except IOError, e:
            #  IOError: [Errno 2] No such file or directory: '/proc/442/status'
            if e[0] == 2:
               sys.stderr.write('_VmB: NO FILE')
            raise # this gets intercepted by the outer 'except'
      except Exception, e:
         sys.stderr.write('_VmB: Unexpected Exception!: "%s" / %s' 
                          % (str(e), traceback.format_exc(),))
# FIXME: delete
#         import rpdb2
#         rpdb2.start_embedded_debugger('password', fAllowRemote=True)
#         import time
#         time.sleep(100)
         return 0.0 # non-Linux?
      # get VmKey line e.g. 'VmRSS:  9999  kB\n ...'
      i = v.index(VmKey)
      v = v[i:].split(None, 3)  # whitespace
      if len(v) < 3:
         sys.stderr.write('_VmB: Unexpected format: %s' % (v,))
         return 0.0 # invalid format?
      # convert Vm value to bytes
      return float(v[1]) * Mem_Usage_Linux._scale[v[2]]

   #
   def mem_virtual(self, since=0.0):
       'Return memory usage in bytes.'
       return (self._VmB('VmSize:') - since)

   #
   def mem_resident(self, since=0.0):
       'Return resident memory usage in bytes.'
       return (self._VmB('VmRSS:') - since)

   #
   def mem_stacksize(self, since=0.0):
       'Return stack size in bytes.'
       return (self._VmB('VmStk:') - since)

# *** Generic method

#
def get_usage():
   if sys.platform == 'linux2':
      mem_usage = Mem_Usage_Linux().mem_resident()
   elif sys.platform in ('win32', 'cygwin',):
      mem_usage = Mem_Usage_Windows().get_usage()
   else:
      # E.g., 'darwin' (Mac OS X), 'os2', 'os2emx', 'riscos', 'atheos'
      sys.stderr.write('get_mem_usage: unknown os: %s' % (sys.platform,))
      mem_usage = None
   return mem_usage

#
def get_usage_mb():
   return get_usage() / 1024.0 / 1024.0

# ***

if (__name__ == '__main__'):
   print get_usage()

