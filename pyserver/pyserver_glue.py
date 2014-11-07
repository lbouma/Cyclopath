# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

# Pyserver's conf.py wants the pyserver directory to be the current directory.
# And for importing pyserver sub-modules to work, we need the pyserver 
# directory to be the current directory. We also need to add the dir to 
# sys.path.

# SYNC_ME: Search pyserver module name.
dirname_pyserver = 'pyserver'

# Check that INSTANCE is set.
# FIXME: Should INSTANCE (and other env vars) be commonly prefixed?
#        E.g., CCP_INSTANCE, CCP_PYSERVER_HOME, etc.? 
#        And just what are all the env vars that Cyclopath uses?

try:
   from mod_python import apache
   # This means we're running from apache. And under apache, INSTANCE isn't 
   # set. But we can tell what instance is specifed in httpd.conf by reading 
   # its PythonInterpreter value. Note that every Cyclopath installation on
   # the server has a unique name that goes [instance]___[my_ccp_dev_dir],
   # e.g., minnesota___ccpv3_trunk
   instance_raw = apache.interpreter
   # See /var/log/apache2/error.log, or maybe /ccp/var/log/apache2/error.log.
   error_log = apache.log_error
except ImportError:
   # We have yet to set up logging; log to, e.g., /var/log/apache2/error.log.
   error_log = sys.stderr.write
   try:
      instance_raw = os.environ['INSTANCE']
   except KeyError:
      instance_raw = ''
#
uniquely_starts = instance_raw.find('___')
if uniquely_starts != -1:
   instance_name = instance_raw[:uniquely_starts]
else:
   instance_name = instance_raw
# We used to set an env. var. but let's avoid a race condition with other
# Apache forks, since the env. seems to be shared among our processes.
# No: os.environ['INSTANCE'] = instance_name
#
if not instance_name:
   error_log('ERROR: Please set the INSTANCE environment variable (py_glue).')
   sys.exit(1)

# We hard-code the path separator, so make sure it's what we think 'tis.
assert(os.path.sep == '/') # We only run on Linux.

# If $PYSERVER_HOME is set, but to the wrong path, you'll get weird errors,
# e.g., ./ccp.py -i ==> ConfigParser.NoSectionError: No section: 'gwis'.
#                       because $PYSERVER_HOME set to a V1 path.
try:
   # See if the user or script supplied the directory as an environment var.
   # SYNC_ME: Search environment variable: PYSERVER_HOME.
   pyserver_home = os.environ['PYSERVER_HOME']
except KeyError:
   # Otherwise, if the user or script is running this script from somewhere
   # within the Cyclopath source directory, we can deduce pyserver's home.
   # NOTE: sys.path[0] is the absolute path to the script, which we need to
   #       use in case the calling script was invoked from a directory other
   #       than its own.
   # NOTE: If you run py interactively, sys.path[0] is '', and abspath('')
   #       resolves to the current directory...
   walk_path = os.path.abspath(sys.path[0])
   depth = 1
   pyserver_home = ''
   while not pyserver_home:
      # EXPLAIN: Why doesn't this use os.path.join?
      test_this_path = os.path.abspath('%s/%s' % (walk_path, 
                                                  dirname_pyserver,))
      #print 'test_this_path: %s' % (test_this_path,)
      # See if the test path is really a path.
      if os.path.isdir(test_this_path):
         # Ooh, this iss good news. See if we can find ourselves a VERSION.py.
         # Note that this will have required that flashclient has beed maked.
         if os.path.isfile('%s/VERSION.py' % (test_this_path)):
            # Whooptie-doo! We have ourselves a pyserver_home.
            pyserver_home = test_this_path
            break
      # If we didn't find pyserver_home, try the next directory in the
      # ancestry, and do some error checking.
      assert(not pyserver_home) # There's a 'break' above...
      new_walk_path = os.path.dirname(walk_path)
      assert(new_walk_path != walk_path)
      walk_path = new_walk_path
      # If we hit rock bottom...
      if walk_path == '/':
         sys.stderr.write('Got to root. Something is wrong. Buh-bye!\n')
         sys.exit(1)
      # Increse your loop confidence.
      # MAGIC NUMBER: Just guessing that 32 is very unlikely path depth.
      depth += 1
      if depth > 32:
         sys.stderr.write('Tired of looping. Giving up!\n')
         sys.exit(1)
   # Set the PYSERVER_HOME env var for the rest of the app.
   # NO: Race conidition with our Cyclopath server installations:
   #     The next URL request -- even on a different server install --
   #     will inherit the environment variables for this process. So
   #     don't set environment variables inside the app.
   # No: os.environ['PYSERVER_HOME'] = pyserver_home

# 2013.09.03: Let's add mapserver/ to the path, too, so we can always skin.
mapserver_home = '%s/mapserver' % (os.path.dirname(pyserver_home),)
sys.path.insert(0, mapserver_home)

# 2013.10.24: Let's add services/ to the path, too.
services_home = '%s/services' % (os.path.dirname(pyserver_home),)
sys.path.insert(0, services_home)

sys.path.insert(0, pyserver_home)

os.chdir(pyserver_home)

if __name__ == '__main__':
   import conf
   print 'Seems OK...'

