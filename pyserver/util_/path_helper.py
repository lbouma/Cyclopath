# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys
import time
import uuid

import conf
import g

log = g.log.getLogger('path_helper')

from util_ import portalocker

# *** 

class Path_Helper(object):

   path_helper_flock = '.path_helper_lock'

   # *** Constructor.

   #
   def __init__(self):
      g.assurt(False) # Not called.

   # *** 

   # This fcn. is thread-safe: the fpath it finds it keeps.
   @staticmethod
   def path_reserve(basedir, extension='', is_dir=False):

      # NOTE: We don't do recursive, or sub-directories. And not all file 
      # managers can handle lots of files or folders as siblings in the same 
      # directory -- at least now Windows, but Cyclopath runs on Linux, so this
      # may not be a problem.

      # Get the directory's new-file lock. This raises if anything is fishy.
      Path_Helper.lock_acquire(basedir)

      # Got the lock. Time to get a uniquely named file or directory.
      tries = 0
      while True:
         rand_path = '%s%s' % (str(uuid.uuid4()), extension,)
         fpath = os.path.join(basedir, rand_path)
         if not os.path.exists(fpath):
            # Found a unique path. Make a file or directory for the callee.
            if not is_dir:
               fileh = open(fpath, 'w')
               # Just by opening the file we've effectively 'touch'ed it -- 
               # so now os.path.exists will say true on it.
            else:
               os.mkdir(fpath)
               # 2013.05.06: Need to chmod?
               os.chmod(fpath, 02775)
            break
         else:
            tries += 1
         # MAGIC_NUMBER: Mostly just testing. UUID is so unique this
         # shouldn't happen (unless your folder is super full?).
         if tries > 100:
            g.assurt('filename_reserve: too many tries!')

      if tries > 1:
         log.warning('filename_reserve: tried a lot to get unique: %d tries' 
                     % (tries,))

      return fpath, rand_path

   @staticmethod
   def lock_acquire(basedir):
      # Make the path to the directory's new-file lock.
      flock_path = os.path.join(basedir, Path_Helper.path_helper_flock)
      # Get a grip on the new-file lock.
      try:
         base_flock = open(flock_path, 'r+')
      except IOError, e:
         # The developer hasn't fulfilled the setup prerequisites.
         raise Exception(
               'path_reserve: Dev error: Please create missing flock: %s'
               % (Path_Helper.path_helper_flock,))
      # Get a handle on the file lock we expect to find in the directory. But
      # don't hang forever.
      tries = 0
      while True:
         tries += 1
         try:
            portalocker.lock(base_flock, portalocker.LOCK_EX 
                                         | portalocker.LOCK_NB)
            # Got it!
            if tries > 1:
               log.warning('path_reserve: tried a lot to get lock: %d tryz'
                           % (tries,))
            break
         except LockException, e:
            # Another process has the flock. Wait a sec.
            # FIXME: Logging warning for now, just to see how often this haps.
            log.warning('path_reserve: lock not avail, sleeping a sec...')
            # MAGIC_NUMBER: 1 is one second.
            time.sleep(1)
         # MAGIC_NUMBER: Don't wait more then 10 seconds.
         if tries > 10:
            raise Exception('path_reserve: giving up on lock!')
      # If we're here, we've got the lock.
      return

   # ***

# ***

if (__name__ == '__main__'):
   pass

