# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import conf
import g

import os
import stat
import sys
import time
import traceback
import zipfile

from item.jobsq.job_status import Job_Status

__all__ = ('Work_Item_Job',)

log = g.log.getLogger('work_item_job')

# ***

class Work_Item_Job(object):

   __slots__ = (
      'wtem',
      'mr_do',
      'stage_lookup',
      # For derived classes
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      self.wtem = wtem
      self.mr_do = mr_do
      self.stage_lookup = None
      self.make_stage_lookup()

   #
   def make_stage_lookup(self):
      g.assurt(False) # Abstract

# ***

   class Ccp_Preempted(Exception):
      '''This exception lets us easily stop a job before it's finished.'''
      def __init__(self, message=''):
         Exception.__init__(self, message)

   # *** Stage processing framework.

   #
   def process_request_(self):

      # To support pause/resume, our stage fcns. are not always called (i.e.,
      # if they were called and completed during a previous operation, before
      # the pause), so put common callouts here... or in derived classes.

      log.debug('process_request called: wtem: %s' % (self.wtem,))
      log.debug(' >> wtem.latest_step: %s' % (self.wtem.latest_step,))
      log.debug(' >> wtem.latest_step.stage_num: %s' 
                % (self.wtem.latest_step.stage_num,))

      time_0 = time.time()

      # Pick up where we left off.
      g.assurt(self.wtem.latest_step.status_text == 'working')
      last_stage_num = self.wtem.latest_step.stage_num or 0
      if not last_stage_num:
         self.process_stage_0()
         last_stage_num = 1

      try:
         # Process the job, stage by stage. The processing fcns. are listed
         # in self.stage_lookup. If a job is suspended or cancelled or if
         # Mr. Do! is shutting down, an exception is raised to escape the
         # processing loop; otherwise, the loop continues until the job is
         # completely processed.

         go_again = True
         while go_again:
            go_again = False
            stage_1 = last_stage_num - 1
            stage_n = self.get_num_stages()
            for lookup_num in xrange(stage_1, stage_n):
               log.debug('process_request_: on stage %d' % ((lookup_num + 1),))
               stage_fcn = self.stage_lookup[lookup_num]
               stage_fcn()
               # Indicate that this stage is complete. This also checks if the
               # user cancelled us or if Mr. Do! is stopping (and raises if so)
               self.stage_finalize()
               g.assurt(self.wtem.latest_step.stage_num == (lookup_num + 1))
               last_stage_num += 1
               # Substages are allowed to change the stage count.
               cur_stage_n = self.get_num_stages()
               if cur_stage_n != stage_n:
                  stage_n = cur_stage_n
                  log.debug('process_request_: new get_num_stages: %d' 
                            % (stage_n,))
                  self.wtem.update_num_stages(stage_n)
                  go_again = True

      except Work_Item_Job.Ccp_Preempted, e:
         # This error means an outside force intervened and we should preempt
         # the job and shutdown. This could mean the job was canceled or
         # suspended, or that Mr. Do! is shutting down.
         log.debug('process_request_: Ccp_Preempted detected.')
         pass

      finally:
         self.job_cleanup()

      # Update the cumulative timer keeper.
      past_time = self.wtem.job_def.job_time_all or 0.0
      self.wtem.job_def.job_time_all = past_time + (time.time() - time_0)

   # *** Built-in Stage 0 fcn.

   # 
   # Stage 0 simply records how many stages we expect to run, so the user has
   # some idea what to expect (though some stages complete almost immediately
   # and other stages could take hours to complete).
   #
   # Derived classes should implement process_stage_1 through process_stage_n.
   def process_stage_0(self):

      # Provide the name of the current stage.
      self.stage_initialize(stage_name='Starting up')

      # Perform the current stage.
      num_stages = self.get_num_stages()
      log.debug('process_stage_0: wtem.update_num_stages: %s' % (num_stages,))
      self.wtem.update_num_stages(num_stages)

      # Derived classes' stage fcn. do not call stage_finalize, just 
      # stage_initialize. We call it here because process_stage_0 is special.
      self.stage_finalize()

   #
   def get_num_stages(self):
      n_stages = len(self.stage_lookup)
      g.assurt(n_stages > 0)
      return n_stages

   #
   def job_cleanup(self):
      # If the job failed, it's marked as such, otherwise, it's still marked
      # 'working'.
      if (self.wtem.latest_step.status_text in Job_Status.finished_statuses):
         # If we caught an error, we marked the job failed. If Mr. Do! is being
         # shutdown, we marked 'aborted'. If the user clicked Cancel in the 
         # client, we mark 'canceled' (or 'suspended' for Suspend). So we only 
         # won't have marked 'complete' if we're here
         g.assurt(self.wtem.latest_step.status_text != 'complete')
         pass # Already in a final state.
      else:
         log.debug('job_cleanup: marking complete.')
         g.assurt(self.wtem.latest_step.status_text == 'working')
         qb = None
         self.mr_do.stage_create_next(qb, self.wtem, 'complete')

   # *** Job-level status change.

   #
   def job_mark_complete(self):
      self.stage_initialize(stage_name='Finishing')
      # Raise an error so our cleanup fcn. is called. We'll mark complete
      # after we've cleaned up.
      raise Work_Item_Job.Ccp_Preempted()

   #
   # We can mark jobs failed for reasons that are the user's fault, or reasons
   # that are our own. Use warn to control the log file level.
   def job_mark_failed(self, failure_reason, warn=True):
      self.mr_do.process_failure(qb=None, wtem=self.wtem, 
                  failure_reason=failure_reason, warn=warn)
      raise Work_Item_Job.Ccp_Preempted()

   # *** Stage-level status change.

   #
   def stage_initialize(self, stage_name):
      self.stage_work_item_update(stage_name=stage_name)

   #
   def stage_finalize(self):
      self.stage_work_item_update(stage_progress=100)

   #
   def stage_update(self, stage_progress):
      self.stage_work_item_update(stage_progress=stage_progress)

   #
   def stage_work_item_update(self, stage_name=None, stage_progress=None):

      # BUG 2688: Use transaction_retryable?

      # Refresh the step, in case the user canceled or suspended the job.
      # But keep a copy of callback_def, which a stage fcn. may have updated.
      self.wtem.latest_step.callback_data_prepare()
      callback_def = self.wtem.latest_step.callback_def
      log.verbose('stage_work_item_update: getting row lock: stack_id: %d'
                  % (self.wtem.stack_id,))
      self.wtem, qb = self.mr_do.wtem_refresh(self.wtem)
      # We've now got a lock on the item.

      # Restore the callback_def. The one in the database is older than the one
      # in Python.
      self.wtem.latest_step.reset_callback_def(callback_def)

      # If the caller passed in a stage_name, create a new stage.
      start_new_stage = (stage_name is not None)
      if start_new_stage:
         g.assurt(stage_name)
         g.assurt(not stage_progress)
      else:
         g.assurt(stage_progress >= 0)
         stage_name = self.wtem.latest_step.stage_name

      # Set the stage number. Either preserve the current number, increment it,
      # or -- for the very first stage (process_stage_0) -- set it to 0.
      stage_num = self.wtem.latest_step.stage_num
      if start_new_stage:
         if stage_num is not None:
            stage_num += 1
         else:
            stage_num = 0
      g.assurt(stage_num >= 0)

      # The new progress is passed in or inferred.
      if start_new_stage:
         stage_progress = 0
      else:
         stage_progress >= self.wtem.latest_step.stage_progress 

      g.assurt((stage_progress >= 0) and (stage_progress <= 100))

      # The status_text is whatever it says in the database. Generally, this is
      # 'working', unless the user or a system event intervened (and set it to,
      # e.g., 'suspending' or 'canceling').
      status_text = self.wtem.latest_step.status_text
      g.assurt(status_text in ('working', 'canceling', 'suspending',))

      # Update the work item step's row in the database before checking for
      # shutdown conditions.
      if not start_new_stage:
         self.wtem.stage_update_current(qb, stage_num, stage_progress)
         # No need to lock here: we're just updating the stage progress.
         qb.db.transaction_begin_rw()
         log.verbose1('stage_work_item_update: updated stage: %s' 
                      % (self.wtem.latest_step,))
      else:
         # The previous stage should be set to 100%.
         g.assurt((self.wtem.latest_step.stage_progress == 100)
                  or (stage_num == 0))

      # Check if we need to quit early.
      new_status_text = None
      if not self.mr_do.jobs_thread.keep_running.isSet():
         log.debug(
            'stage_work_item_update: suspending job (jobs thread is exiting')
         new_status_text = 'aborted'
      if status_text == 'suspending':
         log.debug('stage_work_item_update: suspending job...')
         new_status_text = 'suspended'
      elif status_text == 'canceling':
         log.debug('stage_work_item_update: canceling job...')
         new_status_text = 'canceled'
      elif status_text != 'working':
         g.assurt(self.wtem.latest_step.status_text 
                  in Job_Status.finished_statuses)
         g.assurt(False) # This shouldn't happen, right?
      else:
         g.assurt(status_text == 'working')

      if new_status_text:
         # The last status message was either a stage update, or a
         # canceling/suspending request. Write the final status, either
         # aborted, suspended, or canceled.
         self.wtem.stage_create_next(qb, new_status_text, cancellable=False)
      elif start_new_stage:
         # Make a new row for the next stage.
         log.debug('============ Starting stage %d / %s ===' 
                   % (stage_num, stage_name,))
         self.wtem.stage_create_next(qb, 'working', stage_num, stage_name,
                                     cancellable=True)

      # Record update and release the row lock on the work item.
      qb.db.transaction_commit()
      qb.db.close()
      qb.db = None

      if new_status_text:
         raise Work_Item_Job.Ccp_Preempted()

   # ***

   #
   def prog_update(self, prog_log):

      # This is called periodically by the prog logger. Update the status.

      if prog_log.loop_max:
         new_progress = int(100.0 * float(prog_log.progress) 
                                  / float(prog_log.loop_max))
      else:
         log.warning('prog_update: no loop_max')
         new_progress = 0

      # Let process_request_ finalize the work item: don't show 100, show at
      # most 99% instead.
      if new_progress > 99:
         new_progress = 99

      # Don't bother updating unless the progress is different.
      if self.wtem.latest_step.stage_progress != new_progress:
         self.stage_work_item_update(stage_progress=new_progress)

   # ***

   #
   def make_working_directories(self):

      # We need a unique target directory. The work item already has dibs on a
      # unique UUID in the /ccp/var/cpdumps directory, so we'll just use that 
      # as our base.

      # We use two directories, a '.out' and a '.fin'. The out-dir is populated
      # with files that the job creates, and the fin-dir just contains a zip 
      # of the out-dir.

      # Make the directories.
      opath = self.make_working_directory('.out')
      ppath = self.make_working_directory('.fin')

      return opath

   #
   def make_working_directory(self, dir_suffix):

      # Make a name for the new directory.
      new_name = '%s%s' % (self.wtem.local_file_guid, dir_suffix,)
      new_path = os.path.join(conf.shapefile_directory, new_name)
      # Make the new directory.
      g.assurt(not os.path.exists(new_path))
      try:
         # MAGIC_NUMBER: Setup the directory permissions.
         os.mkdir(new_path, 02775)
         # 2013.05.06: Need to chmod?
         os.chmod(new_path, 02775)
      except OSError, e:
         log.error('do_reserve_directory: OSError: %s' % (str(e),))
         raise Exception(
            'route_analysis: Unable to reserve shaepfile directory.')

      return new_path

   #
   def do_create_archive(self):

      self.stage_initialize('Archiving output files')

      # Make the path, e.g., /ccp/var/cpdumps/{GUID}.out/Cyclopath_Export.zip

      oname = '%s.out' % self.wtem.local_file_guid
      opath = os.path.join(conf.shapefile_directory, oname)

      pname = '%s.fin' % self.wtem.local_file_guid
      ppath = os.path.join(conf.shapefile_directory, pname)

      zipfile_name = self.wtem.get_zipname()
      zname = '%s.zip' % (zipfile_name,)
      zpath = os.path.join(ppath, zname)

      log.verbose('do_create_archive: opath: %s / zpath: %s / wtem: %s' 
                  % (opath, zpath, self.wtem,))

      # Make the zipfile.
      #
      # It might be easiest to use subprocess to call *nix's zip. But we do it
      # the hard way, in Python, using os.walk.

      zfile = zipfile.ZipFile(zpath, 'w')

      for dirpath, dirnames, filenames in os.walk(opath, topdown=True):
         log.verbose(' >> dirpath: %s' % dirpath)
         log.verbose(' >> dirnames: %s' % dirnames)
         log.verbose(' >> filenames: %s' % filenames)
         for fname in filenames:
            is_source = False
            log.verbose('dirpath: %s / fname: %s' % (dirpath, fname,))
            srcpath = os.path.join(opath, dirpath, fname)
            # The zip path should be relative, not absolute.
            zippath = srcpath.replace(opath, '').lstrip(os.path.sep)
            zfile.write(srcpath, arcname=zippath)

      zfile.close()

      try:
         # E.g., chmod 664
         os.chmod(zpath,   stat.S_IRUSR | stat.S_IWUSR 
                         | stat.S_IRGRP | stat.S_IWGRP 
                         | stat.S_IROTH)
      except OSError, e:
         # Not all work item types use all the exts we've defined.
         # NOTE: If a work item uses an ext not in local_file_exts, 
         #       we won't delete it.
         log.error('do_create_archive: cannot chmod: %s' % (str(e),))

# FIXME: This should run after cleanup, eh??
   #
   def do_notify_users(self):

      self.stage_initialize('Notifying users')

      log.debug('do_notify_users: email_on_finish: %s' 
                % (self.wtem.email_on_finish,))

      # FIXME: Implement this.

# ***

if (__name__ == '__main__'):
   pass

