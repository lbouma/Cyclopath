# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import os
import re
import shutil
import sys
import time
import zipfile

import conf
import g

from merge.ccp_import import Ccp_Import
from merge.ccp_merge_conf import Ccp_Merge_Conf
from merge.import_cyclop import Import_Cyclop
from merge.merge_job_base import Merge_Job_Base

# We don't mention these modules in this package but yaml requires them to load
# our config file, which references them.
from merge.ccp_merge_conf import Ccp_Merge_Conf_Base
from merge.ccp_merge_conf import Ccp_Merge_Conf_Shim

__all__ = ('Merge_Job_Import',)

log = g.log.getLogger('merg_job_imp')

# ***

class Merge_Job_Import(Merge_Job_Base):

   __slots__ = (
      'shpf_fnames',
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      Merge_Job_Base.__init__(self, wtem, mr_do)

   # ***

   #
   def job_cleanup(self):
      Merge_Job_Base.job_cleanup(self)

   # ***

   #
   @staticmethod
   def process_request(wtem, mr_do):
      mi = Merge_Job_Import(wtem, mr_do)
      mi.process_request_()

   # *** The stage function lookup.

   #
   def make_stage_lookup(self):
      self.stage_lookup = []
      self.stage_lookup += [
         self.do_extract_archive,            # Stages 1-2.
         self.do_prepare_import,
         ]
      # We'll fill in the import substages and cleanup stages when we know the 
      # shapefile count.

   #
   def add_substage_lookups(self, shpf_count):
      # Make a fake handler just to see how many substages are in a series.
      handler = Ccp_Import(self, None)
      g.assurt(self.handler is not None)
      n_sub_stages = len(handler.substage_lookup)
      # Make a substage list.
      do_do_imports = n_sub_stages * [self.do_do_import,]
      # Tell the handler its start offset.
      Import_Cyclop.stage_num_base = len(self.stage_lookup) + 1
      # Add as many substage lists as there are shapefiles.
      for i in xrange(shpf_count):
         self.stage_lookup += do_do_imports  # A bunch more stages.
      # Finally add the cleanup routines.
      self.stage_lookup += [
         self.do_create_archive,             # The cleanup stages.
         self.do_notify_users,
         self.job_mark_complete,
         ]

      self.handler = None
      handler = None

   # *** STAGE 1: VERIFY ZIP.

   errmsg_please_notricks = (
     'Please flatten the archive and keep your paths relative and descendant.'
      )

   errmsg_please_flatten = (
     'Please flatten the archive (put all files in one folder before zipping).'
      )

   errmsg_please_badzip = (
     'Please rebuild the archive. The zipfile tool spit it back (BadZipfile).'
      )

   errmsg_please_bigzip = (
     'Please rebuild the archive. Make it smaller next time (LargeZipFile).'
      )

   zipname_regex = re.compile(r'^\w')

   #
   def do_extract_archive(self):

      okay = False

      log.debug('do_extract_archive: wtem: %s' % (self.wtem,))

      self.stage_initialize('Extracting ZIP')

      self.shpf_fnames = []

      # Verify and extract the supposed archive.

      # Make the path, e.g., /ccp/var/cpdumps/ + {GUID} + .zip
      zname = '%s.zip' % (self.wtem.local_file_guid,)
      zpath = os.path.join(conf.shapefile_directory, zname)

      failure_reason = None
      zip_valid = zipfile.is_zipfile(zpath)
      if not zip_valid:
         failure_reason = 'zipfile says not a zip file.'
      else:
         zfile = None
         try:
            zfile = zipfile.ZipFile(zpath, 'r')
            # Verify that the zipfile is flat. And not sneaky.
            zfiles_list = zfile.infolist()
            log.debug('do_extract_archive: examining %d files in zip.'
                      % (len(zfiles_list),))
            contains_dirs = False
            unzipped_files = []
            small_head = None
            total_head = None
            total_size = 0
            for zfo in zfiles_list:
               log.debug(' >> zip filename: %s (size: %s)' 
                         % (zfo.filename, zfo.file_size,))
               head, tail = os.path.split(zfo.filename)
               log.debug('    head: %s / tail: %s' % (head, tail,))
               # Directories get their own entries.
               if not tail:
                  g.assurt(zfo.file_size == 0)
                  contains_dirs = True
               else:
                  total_size += zfo.file_size
                  unzipped_files.append(tail)
                  if tail.endswith('.shp'):
                     self.shpf_fnames.append(tail)
               if total_head is None:
                  # Check that the file path is relative and sticks to its
                  # lineage (doesn't use ..s to sneak outside our container).
                  # The regex check is probably overkill. Same with the relpath
                  # check. But I like to be thorough. And I like being able to
                  # do things more than one way.
                  if (head
                      and (head.startswith(os.path.sep) # Not an absolute path.
                           or (head.find('.') != -1) # Contains relative path.
                           or (Merge_Job_Import.zipname_regex.search(head)
                               is None)
                           # trailing / stripd:
                           # or (head != os.path.relpath(head))
                      )):
                     log.warning('do_extract_archive: tricky zip: %s' 
                                 % (zpath,))
                     log.debug('  head.startswith(os.path.sep): %s' 
                               % (head.startswith(os.path.sep),))
                     log.debug('  head.find(".") != -1: %s' 
                               % ((head.find('.') != -1),))
                     log.debug('  zipname_regex.search(head) is None: %s'
                               % ((Merge_Job_Import.zipname_regex.search(head) 
                                   is None),))
                     # We can't use the relpath unless we know what we're
                     # relative to. pyserver/? services/merge/?
                     #   head: testzip / os.path.relpath(head): ../testzip
                     log.debug('  head != os.path.relpath(head): %s' 
                               % ((head != os.path.relpath(head)),))
                     log.debug('  head: %s / os.path.relpath(head): %s' 
                               % (head, os.path.relpath(head),))
                     failure_reason = Merge_Job_Import.errmsg_please_notricks
                     break
                  total_head = head
                  # This is a lazy way to get the top-level subdir name, which
                  # assumes it'll be the first directory we find in the
                  # archive. I'm not sure the zipfile library guarantees this!
                  g.assurt(small_head is None)
                  small_head = head
               elif total_head != head:
                  # This checks that, if the archive is one or more directories
                  # deep, there's only one directory of Shapefiles and not two
                  # or more directories of files.
                  if head.startswith(total_head):
                     total_head = head
                  else:
                     log.warning('do_extract_archive: unflat zip: %s' 
                                 % (zpath,))
                     failure_reason = Merge_Job_Import.errmsg_please_flatten
                     break
            if failure_reason is None:
               # FIXME: Check size of the extracted archive isn't too large?
               log.debug('do_extract_archive: zip okay: size: %d' 
                         % (total_size,))
               # Extract the archive. The archive is named {GUID}.zip (see 
               # merge_job.py). Make the destination something similar.

               xname = '%s.usr' % (self.wtem.local_file_guid,)
               xpath = os.path.join(conf.shapefile_directory, xname)

               # I love the Python documentation: 
               #  Warning: Never extract archives from untrusted sources
               #  without prior inspection. It is possible that files are
               #  created outside of path, e.g. members that have absolute
               #  filenames starting with "/" or filenames with two dots "..".
               g.assurt(not os.path.exists(xpath))
               log.debug('do_extract_archive: extracting inspected zip...')
               zfile.extractall(xpath)
               # MAYBE: Can we extract just the subdir so we don't have to 
               #        cleanup like this?
               if contains_dirs:
                  g.assurt(total_head)
                  try:
                     for fname in unzipped_files:
                        src_path = os.path.join(xpath, total_head, fname)
                        log.debug('Moving subdirred zip file file: %s / %s'
                                  % (src_path, xpath,))
                        shutil.move(src_path, xpath)
                     subdir = os.path.join(xpath, small_head)
                     log.debug('Removing zip file subdir(s): %s' % (subdir,))
                     shutil.rmtree(subdir)
                  except Exception, e:
                     failure_reason = ('Problem moving zip files: %s' 
                                       % (str(e),))
               # Yeppers.
               if failure_reason is None:
                  log.debug('do_extract_archive: Success.')
         except zipfile.BadZipfile, e:
            log.warning('do_extract_archive: BadZipfile: %s' % (zpath,))
            failure_reason = Merge_Job_Import.errmsg_please_badzip
         except zipfile.LargeZipFile, e:
            log.warning('do_extract_archive: LargeZipFile: %s' % (zpath,))
            failure_reason = Merge_Job_Import.errmsg_please_bigzip
         finally:
            zfile.close()
      if failure_reason is not None:
         log.warning('do_extract_archive: not a zip file: %s' % (zpath,))
         self.job_mark_failed(failure_reason)
      else:
         okay = True
      return okay

   # *** STAGE 2: RECHECK PERMISSIONS; PREPARE CONFIG.

   #
   def do_prepare_import(self):

      log.debug('do_prepare_import: wtem: %s' % (self.wtem,))

      self.stage_initialize('Preparing Import')

      all_errs = []

      # We call a series of substage handlers for each one of the shapefiles.
      shpf_count = len(self.shpf_fnames)
      self.add_substage_lookups(shpf_count)

      if not shpf_count:
         all_errs.append(
            'verify_import_job: did not find any Shapefiles to import')

      # If using ccp.yml, check its contents.
      if Merge_Job_Base.use_yaml_conf:
         self.do_read_import_config_load()
         if self.cfg is not None:
            if not all_errs:
               if self.cfg.ccp_dst.branch != self.wtem.branch_id:
                  all_errs.append(
                     'verify_import_config: %s: %s'
                     % ('branch in ccp.yml differs from job',
                        'yml: %s / job: %s' 
                        % (self.cfg.ccp_dst.branch,
                           self.wtem.branch_id,),))

      if all_errs:
         failure_reason = ('do_prepare_import: problems encountered: %s' 
                           % (all_errs,))
         self.job_mark_failed(failure_reason)

   # *** Load permissions

   # *** STAGE 3: IMPORT CCP.

   #
   def do_do_import(self):

      # NOTE: This fcn. gets called multiple times, once for each substage.
      # Skipping: self.stage_initialize

      log.verbose('do_do_import: wtem: %s' % (self.wtem,))

      self.do_import_or_export('import_callback')

   # *** STAGE 4: CREATE ZIP.

   #
   def do_create_archive(self):

      Merge_Job_Base.do_create_archive(self)

   # *** STAGE 5: NOTIFY PPL.

   #
   def do_notify_users(self):

      Merge_Job_Base.do_notify_users(self)

   # ***

   #
   def do_poach_ccp_yml_as_shp_conf(self):
      g.assurt(False) # Deprecated.
      g.assurt(not Merge_Job_Base.use_yaml_conf)
      spf_conf = Ccp_Merge_Conf()
      spf_conf.revision_id = self.cfg.ccp_src.revision_id
      # MAYBE: If we ever use_yaml_conf, you'll want to note that 
      # self.cfg.ccp_src.branch is either the stack ID or the name.
      spf_conf.branch_id = self.cfg.ccp_src.branch
      spf_conf.branch_name = ''
      spf_conf.commit_msg = self.cfg.ccp_dst.commit_message_prefix
      # self.cfg.n/a
      spf_conf.find_missing = ''
      # self.cfg.shapefiles[].assume_missing_geometry
      spf_conf.use__new_geom = False
      #
      shp_conf.add_perms('Public', 'editor')
      #
      return shp_conf

# ***

if (__name__ == '__main__'):
   pass

