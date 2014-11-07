# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import os
import sys
import traceback
import yaml

import conf
import g

from gwis.query_overlord import Query_Overlord
from item.feat import branch
from item.jobsq.job_status import Job_Status
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_.mod_loader import Mod_Loader

from utils.work_item_job import Work_Item_Job

__all__ = ('Merge_Job_Base',)

log = g.log.getLogger('merge_job_base')

# ***

class Merge_Job_Base(Work_Item_Job):

   # When merge was first implemented, we used a file, ccp.yml, archived with
   # the shapefile(s) to specify, i.e., the branch, revision ID, and a few
   # other things. But months later we added the _ACTION and other _-prefixed
   # fields in the Shapefile, and we simplified permissions, so it no longer 
   # makes sense to maintain a yaml file. It also simplifies things for the 
   # user, and we won't have to worry about them forget to zip the conf.
   use_yaml_conf = False

   __slots__ = (
      'the_def',
      'handler',
      'cfg',
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      self.the_def = None
      self.handler = None
      self.cfg = None
      #
      Work_Item_Job.__init__(self, wtem, mr_do)

   #
   def get_import_config_path(self, dir_ext):
      # 
      xname = '%s.%s' % (self.wtem.local_file_guid, dir_ext,)
      xpath = os.path.join(conf.shapefile_directory, xname)
      # MAGIC NUMBER: make the filename configurable?
      cfg_name = 'ccp.yml'
      cfg_path = os.path.join(xpath, cfg_name)
      #
      return cfg_path

   #
   def process_request_(self):

      log.debug(' >> wtem.local_file_guid: %s' % (self.wtem.local_file_guid,))

      Work_Item_Job.process_request_(self)

   #
   def job_cleanup(self):
      # handler is Ccp_Export or Ccp_Import
      if self.handler is not None:
         self.handler.job_cleanup()
         self.handler = None
      Work_Item_Job.job_cleanup(self)

   # ***

   #
   def do_read_import_config_load(self):
      g.assurt(Merge_Job_Base.use_yaml_conf)
      # Try 'n load the yaml config file.
      cfg_path = self.get_import_config_path('usr')
      self.cfg = None
      try:
         yaml_stream = file(cfg_path, 'r')
         # See above. We imported Ccp_Merge_Conf_Shim so our config is a
         # Python object (with dotted referencing) rather than a dictionary
         # (with [] referencing).
         self.cfg = yaml.load(yaml_stream)
      except Exception, e:
         #log.warning('do_read_import_config_load: failed: %s' % (str(e),))
         # This is yaml.constructor.ConstructorError sometimes.
         failure_reason = ('yaml.load says bad yaml: %s / %s' 
                           % (cfg_path, str(e),))
         self.job_mark_failed(failure_reason)
      g.assurt(self.cfg is not None)
      self.do_read_import_config_verify()

   #
   def do_read_import_config_verify(self):

      g.assurt(Merge_Job_Base.use_yaml_conf)

      all_errs = []

      # Check for yaml attrs. Those without a default are required.
      errs = []
      #
      self.import_config_check(errs, 'source_srs', default='NAD83')
      #
      self.import_config_check(errs, 'revision_id', 'ccp_src')
      self.import_config_check(errs, 'branch', 'ccp_src')
      #
      self.import_config_check(errs, 'commit_message_prefix', 'ccp_dst')
      self.import_config_check(errs, 'branch', 'ccp_dst')
      self.import_config_check(errs, 'assume_missing_geometry', 'ccp_dst', 
                               default=False)
      #
      self.import_config_check(errs, 'shapefiles', default=list())
      #
      all_errs.extend(errs)

      # Check the optional args. Prints to log file, for debugging.
      errs = []
      req = False
      g.assurt(not errs)

      # Check the shapefiles.
      for shpf_def in self.cfg.shapefiles:
         self.import_config_check(errs, 'shpf_name', shpf_def)
         #self.import_config_check(errs, 'shpf_layr', shpf_def)
         self.import_config_check(errs, 'item_type', shpf_def)
         self.import_config_check(errs, 'do_conflate', shpf_def,
                                  default=False)
         self.import_config_check(errs, 'check_missing_only', shpf_def,
                                  default=False)

      if all_errs:
         self.cfg = None
         failure_reason = (
            'do_read_import_config_verify: please check config: %s' 
            % (all_errs,))
         self.job_mark_failed(failure_reason)

   # *** Yaml verification

   # If default is not None, the yaml attr is not required. Otherwise errs is
   # appended if the attr is missing from the yaml.
   def import_config_check(self, errs, attr_name, source=None, default=None):
      g.assurt(Merge_Job_Base.use_yaml_conf)
      try:
         if not source:
            container = self.cfg
         elif isinstance(source, basestring):
            container = getattr(self.cfg, source)
         else:
            container = source
         cfg_value = getattr(container, attr_name)
         # NOTE: A defined attr but with a None or '' value is considered not
         #       exists, or a list attr that's empty.
         if ((cfg_value is None) 
             or ((isinstance(cfg_value, basestring)) and (cfg_value == ''))
             or ((isinstance(cfg_value, list)) and (len(cfg_value) == 0))):
            err_s = 'import_config: attr value is empty: %s' % (attr_name,)
         log.debug('input_config: yml says: %s / %s' % (attr_name, cfg_value,))
      except AttributeError:
         err_s = 'import_config: missing attr: %s' % (attr_name,)
         if default is None:
            errs.append(err_s)
         else:
            log.debug(err_s)
            container = None
            if not source:
               container = self.cfg
            elif isinstance(source, basestring):
               try:
                  container = getattr(self.cfg, source)
               except AttributeError:
                  pass
            else:
               container = source
            if container is not None:
               setattr(container, attr_name, default)

   # *** Stage fcns.

   #
   def do_import_or_export(self, callback_handler_name):

      log.verbose('do_import_or_export: fbase: %s' 
                  % (self.wtem.local_file_guid,))
      log.verbose('do_import_or_export: wtem: %s' % (self.wtem,))

      # Figure out the branch-specific import or export handler.

      failure_reason = None

      the_branch = None

      qb_cur = self.get_qb_cur()
      if qb_cur is not None:
         branches = branch.Many()
         branches.search_by_stack_id(self.wtem.branch_id, qb_cur)
         if branches:
            g.assurt(len(branches) == 1)
            the_branch = branches[0]
         qb_cur.db.close()
         qb_cur.db = None
         qb_cur = None

      callback_fcn = None
      if the_branch is not None:
         callback_handler = getattr(the_branch, callback_handler_name)
         callback_fcn = Mod_Loader.get_callback_from_path(callback_handler)
         if callback_fcn is None:
            failure_reason = (
               'do_import_or_export: No handler for branch: %s (%d)'
               % (the_branch.name, the_branch.stack_id,))
      else:
         failure_reason = ('do_import_or_export: not a branch: %s'
                           % (self.wtem.branch_id,))

      if callback_fcn is not None:
         log.verbose('do_import_or_export: calling handler')
         try:
            # This callback is allowed to take a Very Long Time. But we also
            # trust that it checks periodically for state change, e.g.,
            # should the user want to cancel the operation, or if Mr. Do! is
            # shutting down.
            okay = callback_fcn(self)
            g.assurt(okay is not None)
            # Check that the handler updated the status appropriately.
            self.wtem, qb = self.mr_do.wtem_refresh(self.wtem)
            #if (self.wtem.latest_step.status_text 
            #    not in Job_Status.statuses_complete):
            if okay:
               if self.wtem.latest_step.status_text != 'working':
                  failure_reason = (
                     'do_import_or_export: done but not still working: %s'
                     % (self.wtem.latest_step.status_text,))
            else:
               if (self.wtem.latest_step.status_text 
                   not in Job_Status.finished_statuses):
                  failure_reason = (
                     'do_import_or_export: not done and unexpected status: %s'
                     % (self.wtem.latest_step.status_text,))
            qb.db.transaction_rollback()
            qb.db.close()
         except Work_Item_Job.Ccp_Preempted, e:
            raise # Keep going; job is already marked failed.
         except Exception, e:
            # This is unexpected: the callback has its own try/expect block.
            log.error('do_import_or_export: unexpected error: %s' 
                      % (traceback.format_exc(),))
            failure_reason = ('do_import_or_export: handler failed: %s\n%s' 
                              % (str(e), traceback.format_exc(),))

      if failure_reason:
         self.job_mark_failed(failure_reason)

   # ***

   #
   def get_qb_cur(self):

      qb_cur = None

      username = self.wtem.created_by

      db = db_glue.new()
      rev = revision.Current(allow_deleted=False)
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db, 
                           self.wtem.branch_id, branch_hier_rev=rev)
      if branch_id is not None:
         g.assurt(branch_hier)
         qb_cur = Item_Query_Builder(db, username, branch_hier, rev)
         Query_Overlord.finalize_query(qb_cur)

      return qb_cur

   # ***

# ***

if (__name__ == '__main__'):
   pass

