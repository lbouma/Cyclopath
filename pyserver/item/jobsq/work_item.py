# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import cPickle
import os
import psycopg2
import shutil
import sys
import traceback

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import nonwiki_item
from item.jobsq import work_item_step
from item.jobsq.job_action import Job_Action
from item.jobsq.job_base import Job_Base
from item.jobsq.job_status import Job_Status
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc
from util_.path_helper import Path_Helper

__all__ = ['One', 'Many',]

log = g.log.getLogger('work_item')

#re ; ./ccp.py -U landonb --no-password -c -t work_item -m "Ignore me" -e name '' -e job_class 'merge'

# re ; ./ccp.py -U landonb --no-password -c -t merge_job -m "No note" -e name "" -e job_act create -e for_group_id 0 -e for_revision 0
# re ; ./ccp.py -U landonb --no-password -c -t merge_job -m "No note" -e name "" -e job_act create -e for_group_id 0 -e for_revision 0 -f branch_id 2401776



# FIXME: This is a single job, not a queue of 'em, so maybe rename...
# branch_job? job_record? job_job?

# SYNC_ME: See pyserver/items/jobsq/work_item.py
#              flashclient/item/jobsq/Work_Item.as
class One(nonwiki_item.One):

   # ***

   local_file_exts = ('.zip', '.usr', '.out', '.fin',)

   # ***

   PICKLE_PROTOCOL_ASCII = 0
   PICKLE_PROTOCOL_BINARY = cPickle.HIGHEST_PROTOCOL
   # FIXME: Maybe use binary eventually? Using ASCII for now for debugging.
   #PICKLE_PROTOCOL = PICKLE_PROTOCOL_ASCII

   # Base class overrides

   item_type_id = Item_Type.WORK_ITEM
   item_type_table = 'work_item'
   item_gwis_abbrev = None
   # 2013.04.07: This is new. We used to not filter by item type.
   child_item_types = (
      Item_Type.WORK_ITEM,
      Item_Type.MERGE_JOB,
      Item_Type.MERGE_EXPORT_JOB,
      Item_Type.MERGE_IMPORT_JOB,
      #Item_Type.MERGE_JOB_DOWNLOAD,
      Item_Type.ROUTE_ANALYSIS_JOB,
      #Item_Type.ROUTE_ANALYSIS_JOB_DOWNLOAD,
      #Item_Type.WORK_ITEM_DOWNLOAD,
      Item_Type.CONFLATION_JOB,
      )

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('job_class',           None,   True,  False,    str,  None),
      # MAYBE: We could start using item_revisionless.edited_user
      #        rather than maintaining our own created_by.
      ('created_by',          None,   True,  False),
      ('job_priority',        None,   True,  False,    int,     0),
      ('job_finished',       False,   True,  False),
      ('num_stages',          None,   True,  False),
      # e.g., job_fcn = merge.merge_job_import:Merge_Job_Import:process_request
      ('job_fcn',             None,  False,  False),
      ('job_dat',             None,  False,  False),
      ('job_raw',             None,  False,  False),
      # The user sends this to specify an action.
      ('job_act',             None,  False,   None,    str,     2),
      # The user can ask for immediate ownership of the new job.
      ('job_local_run',      False,  False,   None,   bool, False),
      ('publish_result',     False,  False,   None,    str, False),
      # Attributes stored in job_dat/job_raw.
      ('job_stage_msg',       None,   True,   None),
      ('job_time_all',        None,   True,   None),
      # There's a hack in ccp.py to let a cron job make a nightly Cyclopath
      # export, but the hack needs to know where the results are stored...
      # so we have to send the guid to the client.
      # MAYBE: Only do this for ccp.py but not for flashclient/android.
      #('local_file_guid',     None,  False,   None),
      ('local_file_guid',     None,   True,   None),
      # FIXME: Should email option be job_dev attr or a watcher item?
      ('email_on_finish',     None,   True,   None,   bool,     0),
      #
      ('download_fake',       None,  False,   None,    str,     0),
      ]
   attr_defns = nonwiki_item.One.attr_defns + local_defns
   psql_defns = nonwiki_item.One.psql_defns # No: + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = nonwiki_item.One.psql_defns + local_defns

   # These defaults are just like those in local_defns... violates DRY! =P
   _job_def_cols = [
      # job_def.[name],       deft,
      ('job_stage_msg',       None,),
      ('job_time_all',        None,),
      ('local_file_guid',     None,),
      ('email_on_finish',     None,),
      # FIXME: Is this really stored?
      ('download_fake',       None,),
      ]
   job_def_cols = _job_def_cols

   __slots__ = [
      'job_def',
      'steps',
      'latest_step',
      'next_step',
      'resident_download',
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   # 2011.12.19: I [lb] added qb to the init for items, mostly for this class
   # (and other nonwiki items) to load support table. Right now, the qb is just
   # used for its db, but I wonder if the full-fledged qb object will
   # eventually be needed by some object.
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      nonwiki_item.One.__init__(self, qb, row, req, copy_from)
      self.setup_job(qb, row)
      self.resident_download = None

   #
   def setup_job(self, qb, row):
      self.job_def = None
      self.steps = []
      self.latest_step = None
      self.next_step = None
      if row is not None:
         log.verbose('setup_job')
         g.assurt(qb is not None)
         # ccp.py sets up work_items that don't exist yet, so don't assume the
         # job_step exists.
         if self.system_id is not None:
            # This work item already exists in the database.
            g.assurt(self.stack_id > 0)
            self.job_data_unpack()
            self.job_step_get_latest(qb)

   # 
   def __str__(self):
      return ((nonwiki_item.One.__str__(self))
         + (', W Item: fini: %s, n_stages: %s, latest: %s, base: %s, email: %s'
                 % (self.job_finished, 
                    self.num_stages,
                    str(self.latest_step), 
                    self.local_file_guid,
                    self.email_on_finish,)))

   ##
   #def append_gml(self, elem, need_digest, new=None):
   #   g.assurt(new is None)
   #   new = nonwiki_item.One.append_gml(self, elem, need_digest, new)
   #   #self.latest_step.append_gml(elem, need_digest, new)
   #   extra_attrs = None
   #   self.latest_step.attrs_to_xml(new, need_digest, extra_attrs)
   #   return new

   #
   def attrs_to_xml(self, elem, need_digest, extra_attrs=None,
                          include_input_only_attrs=False):
      nonwiki_item.One.attrs_to_xml(self, elem, need_digest, extra_attrs, 
                                    include_input_only_attrs)
      if self.latest_step is not None:
         self.latest_step.attrs_to_xml(elem, need_digest, extra_attrs,
                                       include_input_only_attrs)

   #
   # Derived classes should override this and set job_class='job_type'.
   def from_gml(self, qb, elem):
      nonwiki_item.One.from_gml(self, qb, elem)

   # 
   # Intercept validize. This happens on commit. The existing database item
   # gets loaded and we get to take a look at it.
# FIXME: For derived classes, do they overload this to check the job_act?
# like, what if user is canceling an uncancellable thing? do we record the 
# attempt, or ignore it? actually, i don't think job_act will be that
# serious... 'create', 'status', 'cancel', 'delete' (or is that inherent in the
# item commit?), and what about 'download'?
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      nonwiki_item.One.validize(self, qb, is_new_item, dirty_reason, ref_item)
      g.assurt(self.valid)
      # EXPLAIN: We know the user has editor-access-or-better right now, right?
      if is_new_item:
         g.assurt(self.version == 0)
         # Prepare the job data, which is a packed Python object.
         self.job_data_prepare()
         self.job_data_packit()
         # Create a new work item is simple and doesn't involve error checking.
         # We let the jobs processor figure that out. We just expect the user
         # to be requesting a 'create' action.
         if self.job_act != 'create':
            log.warning('Client error: job_act: "%s" (expected "create"): %s'
                        % (self.job_act, self,))
            raise GWIS_Error('For new work items, job_act must be "create".')
         g.assurt(not self.system_id)
         # If we're called via ccp.py, the user might want to immediately
         # assume ownership of the work_item, which prevents the jobs queue
         # thread from grabbing it.
         if not self.job_local_run:
            status_code = Job_Status.lookup_val['queued']
            status_text = 'queued'
         else:
            g.assurt(qb.request_is_local)
            # Nope, since we're pyserver, not ccp.py:
            #   g.assurt(qb.request_is_script)
            status_code = Job_Status.lookup_val['starting']
            status_text = 'starting'
         log.verbose1('validize: creating work item step')
         # FIXME: Let the caller specify a derived work_item_step class?
         self.next_step = work_item_step.One(
            qb=qb, 
            wtem=self,
            row={
               'work_item_id': self.system_id,
               'step_number': 1,
               'status_code': status_code,
               'status_text': status_text,
               'cancellable': True,
               }
            )
         self.next_step.work_item = self
         # Don't forget to set created_by.
         self.created_by = qb.username
      else:
         # We can steal the job data from the database.
         self.job_raw = ref_item.job_raw
         self.job_dat = ref_item.job_dat

         log.verbose('self.job_raw: %s' % (self.job_raw,))
         log.verbose('self.job_dat: %s' % (self.job_dat,))

         self.job_data_unpack()
         self.job_step_get_latest(qb)
         g.assurt(self.latest_step.step_number >= 1)
         # See what action the user is requesting.
         #
         if self.job_finished:
            raise GWIS_Error('Cannot act on work item: job already finished.')
         #
         if self.job_act == 'cancel':
            self.job_interrupt(qb, cancel=True)
         elif self.job_act == 'suspend':
            self.job_interrupt(qb, suspend=True)
         elif self.job_act == 'delist':
            g.assurt(not self.deleted) # client error?
            # NOTE: Skipping mark_deleted(), since save_core will be called.
            self.deleted = True
         else:
            raise GWIS_Error('Unknown job action: "%s".' % (self.job_act,))

   #
   def job_interrupt(self, qb, cancel=False, suspend=False):

      g.assurt(cancel ^ suspend)

      log.debug('job_interrupt: %s' % ('cancel' if cancel else 'suspend',))

      if cancel:
         action_request = 'canceling'
         action_statement = 'canceled'
         if not self.latest_step.cancellable:
            raise GWIS_Error(
               'Cannot cancel work item: it is marked uncancellable.')
      else:
         g.assurt(suspend)
         action_request = 'suspending'
         action_statement = 'suspended'
         if not self.latest_step.suspendable:
            raise GWIS_Error(
               'Cannot suspend work item: it is marked unsuspendable.')

      # We could probably remove these raises, but [lb] is curious if they ever
      # happen.
      if self.latest_step.status_text == 'canceling':
         raise GWIS_Error(
            'Cannot cancel work item: it is being canceled.')
      if self.latest_step.status_text == 'suspending':
         raise GWIS_Error(
            'Cannot suspend work item: it is being suspended.')

      if ((self.latest_step.status_text == 'queued')
         or (self.latest_step.status_text == 'starting')):
         new_status = action_statement
         # Can skip setting job_finished because of how save_core works.
      else:
         g.assurt(self.latest_step.status_text == 'working')
         new_status = action_request

      self.next_step = work_item_step.One(
         qb=qb, 
         wtem=self,
         row={
            'work_item_id': self.system_id,
            'step_number': self.latest_step.step_number + 1,
            # Skipping: last_modified, epoch_modified
            'stage_num': self.latest_step.stage_num,
            'stage_name': self.latest_step.stage_name,
            'stage_progress': self.latest_step.stage_progress,
            'status_code': Job_Status.lookup_val[new_status],
            'status_text': new_status,
            'cancellable': False,
            'callback_def': self.latest_step.callback_def,
            # Skipping: callback_dat, callback_raw
            }
         )

   # *** Saving to the Database

   #
   def save_core(self, qb):
      g.assurt((self.valid_start_rid is None) or (self.valid_start_rid == 1))
      log.verbose1('save_core: self: %s' % (self,))
      nonwiki_item.One.save_core(self, qb)
      if self.fresh:
         g.assurt(self.version == 1)
         g.assurt(self.valid_start_rid == 1)
         # Check that the callback is set by the derived class.
         g.assurt(self.job_fcn)
         # Save to the 'work_item' table
         # No: self.save_insert(qb, One.item_type_table, One.psql_defns)
         self.save_insert(qb, One.item_type_table, One.private_defns)
      else:
         g.assurt(self.version in (1, 2,))
         g.assurt((self.valid_start_rid is None) 
                  or (self.valid_start_rid == 1))
         # Is this cheating?
         if self.version == 2:
            log.verbose1('save_core: resetting version to 1')
            self.version = 1
      # Check out status: if it's one of the finished statues, mark our
      # finished bool as finished.
      if self.next_step is not None:
         log.verbose1('save_core: next_step: %s' % (self.next_step,))
         if self.next_step.status_text in Job_Status.finished_statuses:
            self.job_finished = True
            job_finished_sql = (
               """
               UPDATE work_item 
               SET job_finished = TRUE
               WHERE system_id = %d
               """ % (self.system_id,))
            rows = qb.db.sql(job_finished_sql)
            g.assurt(rows is None) # sql throws on error or returns naught onok
      # 
      if self.fresh:
         g.assurt(self.job_act == 'create')
         # Save the uploaded file, maybe (only merge_import_job uses this).
         self.save_core_save_file_maybe(qb)
      else:
         # See if the item is deleted and remove files (most or job types have
         # local files; this applies to both merge_job types and
         # route_analysis_job).
         self.save_core_remove_files_maybe()

   #
   def save_core_remove_files_maybe(self):
      g.assurt(self.version in (1, 2,))
      # If we're being wiki-deleted, do a real-delete on associated files.
      if self.deleted:
         g.assurt(self.job_act == 'delist')
         #if self.latest_step.callback_def['fbase']:
         if self.local_file_guid:
            log.debug('save_core: removings files')
            # E.g., for ext in ('.zip', '.out', '.usr', '.fin',):
            for ext in One.local_file_exts:
               #fbase = ('%s.%s' 
               #         % (self.latest_step.callback_def['fbase'], ext,))
               fbase = ('%s.%s' % (self.local_file_guid, ext,))
               fpath = os.path.join(conf.shapefile_directory, fbase)
               log.debug('save_core: removing file or dir: %s' % (fbase,))
               try:
                  os.unlink(fpath)
               except OSError, e:
                  # Not all work item types use all the exts we've defined.
                  # NOTE: If a work item uses an ext not in local_file_exts, 
                  #       we won't delete it.
                  log.debug('save_core: file missing?: %s / %s' % 
                            (fbase, str(e),))
            # FIXME: NULLify self.local_file_guid?
         else:
            log.debug('save_core: no files to remove?')

   #
   def save_core_save_file_maybe(self, qb):

      g.assurt(self.local_file_guid is None)

      if (self.download_fake or (self.resident_download is not None)):

         log.debug('len(self.resident_download): %d' 
                   % (0 if self.resident_download is None 
                      else len(self.resident_download)),)
         log.debug('self.download_fake: %s' % (self.download_fake,))

         g.assurt(self.job_act == 'create')

         try:

            fpath, rand_path = Path_Helper.path_reserve(
                                 basedir=conf.shapefile_directory,
                                 extension='', is_dir=False)

            # NOTE: This fcn. assumes all files uploaded to us are zips.
            # Add the file extension.
            fpath += '.zip'

            if self.resident_download is not None:
               log.debug('writing POSTed file to: %s' % (fpath,))
               local_f = open(fpath, 'w')
               local_f.write(self.resident_download)
               local_f.close()
            else:
               log.debug('copying FAKEed file from/to: %s / %s' 
                         % (self.download_fake, fpath,))
               shutil.copyfile(self.download_fake, fpath)

            self.local_file_guid = rand_path
            # We'll save this to the database when we call 
            # self.job_data_update_with_lock from save_related_maybe.

         except IOError, e:

            log.warning('Unable to save upload file: %s' % (str(e),))
            raise GWIS_Error('Unable to save upload file!')

   # 
   def save_related_maybe(self, qb, rid, kick_mr_do=True):
      nonwiki_item.One.save_related_maybe(self, qb, rid)
      if self.next_step is not None:
         log.verbose1('save_related_maybe: next_step: %s' % (self.next_step,))
         if not self.next_step.work_item_id:
            g.assurt(self.system_id)
            self.next_step.work_item_id = self.system_id
         if self.job_local_run:
            kick_mr_do = False
         self.next_step.save_core(qb, kick_mr_do)
         self.latest_step = self.next_step
         #self.latest_step.work_item = self
         g.assurt(self.latest_step.work_item == self)
         self.next_step = None
      # We may have changed job_def, so resave it.
      self.job_data_update_with_lock(qb.db)

   # *** Stage helpers

   #
   def update_num_stages(self, num_stages):
      g.assurt(not self.fresh)
      g.assurt(self.version == 1)
      g.assurt((self.valid_start_rid is None) # Not loaded from db...
               or (self.valid_start_rid == 1)) # or loaded from db.
      g.assurt(num_stages > 0)

      self.num_stages = num_stages

      # BUG 2688: Use transaction_retryable?

      log.verbose4('update_num_stages: Getting exclusive database lock...')
      db = db_glue.new()

      found_row = None
      locked_table = False
      try:
         log.debug('update_num_stages: locking work_item...')
         # NOTE: Not wrapping with transaction_retryable, but using a timeout
         #       should cause transaction_lock_row to behave similarly.
         (found_row, locked_table,
            ) = db.transaction_lock_row(
               'work_item', 'system_id', self.system_id)
         # FIXME/MAYBE: If not locked_table, should we really raise in the
         #              middle of a job?
      except Exception, e:
         # This is a programmer error, probably...
         log.error('update_num_stages: exception: %s' % (str(e),))
         # This is a programmer error, probably...
         stack_trace = traceback.format_exc()
         log.warning('update_num_stages: stack_trace: %s' % (stack_trace,))
         # WRONG: format_stack shows Mr. Do!'s main thread, but format_exc
         # shows the stack trace of the thread that dumped.
         #   stack_trace = traceback.format_stack()
         #   log.warning('Warning: Unexpected exception: %s'
         #               % (''.join(stack_trace),))
      if not locked_table:
         log.error('update_num_stages: cannot get row lock...')
         raise GWIS_Error('%s %s'
            % ('Unable to update work_item status!',
               'Please try again soon.',))

      rows = db.sql(
         """
         UPDATE 
            work_item 
         SET 
            num_stages = %d
         WHERE 
            system_id = %d
         """ % (self.num_stages, 
                self.system_id,))
      g.assurt(rows is None) # sql throws on error and returns naught else

      db.transaction_commit()
      db.close()
      log.verbose4('update_num_stages: release database lock.')

   #
   def stage_create_next(self, qb, new_status, 
                               stage_num=None, stage_name=None, 
                               cancellable=True, callback_def=None):

      log.verbose1('stage_create_next: "%s" / %s' % (new_status, str(self),))
      g.assurt(self.next_step is None)

      log.verbose1('stage_create_next: creating work item step')
      self.next_step = work_item_step.One(
         qb=qb, 
         wtem=self,
         row={
            'work_item_id': self.system_id,
            'step_number': self.latest_step.step_number + 1,
            # Skipping: last_modified, epoch_modified
            'stage_num': stage_num,
            'stage_name': stage_name,
            'stage_progress': None,
            'status_code': Job_Status.lookup_val[new_status],
            'status_text': new_status,
            'cancellable': cancellable,
            }
         )

      self.next_step.work_item = self

      g.assurt((self.valid_start_rid is None) # Not loaded from db...
               or (self.valid_start_rid == 1)) # or loaded from db.
      g.assurt(self.version == 1)

      if callback_def:
         g.assurt(False) # FIXME: Get rid of callback_def as a param.
                         #        Just set the obj attr.
         self.latest_step.reset_callback_def(callback_def)

      self.save_core(qb)
      self.save_related_maybe(qb, conf.rid_inf, kick_mr_do=False)

      g.assurt(self.next_step is None)

   #
   def stage_update_current(self, qb, stage_num, stage_progress):
      g.assurt(not self.fresh)
      g.assurt(self.version == 1)
      g.assurt((self.valid_start_rid is None) # Not loaded from db...
               or (self.valid_start_rid == 1)) # or loaded from db.
      self.latest_step.stage_update_current(qb, stage_num, stage_progress)

   # BUG nnnn: Implement suspendable. I.e., 
   # def stage_set_suspendable(self):
   #    self.latest_step.suspendable = True
   #    # something

   # ***

   #
   def job_step_get_latest(self, qb):
      log.verbose('job_step_get_latest')
      g.assurt(not self.steps)
      self.steps = work_item_step.Many()
      latest_only = True
      self.steps.search_by_work_item_id(qb, self, self.system_id, latest_only)
      g.assurt(len(self.steps) == 1)
      self.latest_step = self.steps[0]
      self.latest_step.work_item = self

   # *** Job data helpers

   #
   def job_data_prepare(self):
      if self.job_def is None:
         g.assurt(self.version == 0)
         # This is a little cheat. We use the viewport and filters for the
         # request and apply them to the item...
         # NOTE: Once set, viewport and filters are never updated.
         # Commit makes its own qb, so use the original one from the request.
         # FIXME: 2012.03.23: We should stop using viewport and filters...
         #                    it's too messy to get flashclient to pack 'em.
         self.job_def = Job_Base(self.req.viewport, self.req.filters)
      # The One object duplicates the job_def attributes. Programmers should
      # use the ones in the One object. Now, copy the One's attrs to job_def.
      for defn in self.job_def_cols:
         attr_val = getattr(self, defn[0], defn[1])
         setattr(self.job_def, defn[0], attr_val)

   #
   def job_data_packit(self):
      if self.job_def is not None:
         # FIXME: Settle on one of these.
         ## FIXME: ProgrammingError: ERROR:  
         ##  invalid byte sequence for encoding "UTF8": 0x80
         self.job_dat = cPickle.dumps(self.job_def, One.PICKLE_PROTOCOL_ASCII)
         self.job_raw = cPickle.dumps(self.job_def, One.PICKLE_PROTOCOL_BINARY)
         #log.debug('self.job_dat: %s' % (self.job_dat,))
         #log.debug('self.job_raw: %s' % (self.job_raw,))
         ##self.job_dat = qb.db.quoted(psycopg2.Binary(self.job_dat))
         ##self.job_dat = qb.db.quoted(self.job_dat)
         ##self.job_dat = return psycopg2.extensions.QuotedString(str(s)
         ##                                                       ).getquoted()
         ##self.job_raw = qb.db.quoted(psycopg2.Binary(self.job_raw))
         self.job_raw = psycopg2.Binary(self.job_raw)
         #log.debug('self.job_dat: %s' % (self.job_dat,))
         #log.debug('self.job_raw: %s' % (self.job_raw,))
         ##self.job_dat = None

   #
   def job_data_unpack(self):
      if self.job_raw is not None:
         g.assurt(self.job_dat is not None)
         # FIXME: Settle on one of these.
         g.assurt(self.job_dat)
         g.assurt(self.job_raw)
         #log.debug('self.job_dat: %s' % (self.job_dat,))
         #log.debug('cPickle.loads: self.job_dat')
         job_def_dat = cPickle.loads(self.job_dat)
         # If the job def changes, what's in the database may reflect the old
         # job def definition, so update it.
         job_def_dat.re_init()
         #log.debug('id(job_def_dat): %d' % (id(job_def_dat),))
         g.assurt(isinstance(job_def_dat, Job_Base))
         #log.debug('self.job_raw: %s' % (self.job_raw,))
         job_def_raw = cPickle.loads(str(self.job_raw))
         g.assurt(isinstance(job_def_raw, Job_Base))
         # If the job def changes, what's in the database may reflect the old
         # job def definition, so update it.
         job_def_raw.re_init()
         #log.debug('id(job_def_raw): %d' % (id(job_def_raw),))
         g.assurt(job_def_dat == job_def_raw)
         self.job_def = job_def_raw
         # Rehydrate our locals that are stored in job_def.
         for defn in self.job_def_cols:
            attr_val = getattr(self.job_def, defn[0], defn[1])
            setattr(self, defn[0], attr_val)
      else:
         log.warning('No job data? self: %s' % self)

   #
   def job_data_update(self):

      log.verbose4('job_data_update: Getting table row lock...')

      # BUG 2688: Use transaction_retryable?

      # Since we're going to commit a transaction, let's not clone(), so as 
      # not to confuse the current connection. Also, db_glue will complain if 
      # we try to commit a cursor that was cloned, if there are still other 
      # cursors active.
      # MAYBE: Postgres would actually let us save, so maybe we should ease the
      #        restriction. By doing it this way, we force the caller to get a 
      #        new db handle to see our update. But we're just saving job data,
      #        which is already part of the work_item, so it's probably not 
      #        important.
      db = db_glue.new()
      g.assurt(not db.dont_fetchall)

      # FIXME: Do we really need the revision lock? What about getting the
      # 'work_item' table lock instead? Isn't the work_item already row-locked
      # by its system_id in item_versioned? Or are we competing with commit?
      found_row = None
      locked_table = False
      try:
         log.debug('update_num_stages: locking work_item...')
         # NOTE: Not wrapping with transaction_retryable, but using a timeout
         #       should cause transaction_lock_row to behave similarly.
         (found_row, locked_table,
            ) = db.transaction_lock_row(
               'work_item', 'system_id', self.system_id)
         # FIXME/MAYBE: If not locked_table, should we really raise in the
         #              middle of a job?
      except Exception, e:
         # This is a programmer error, probably...
         log.error('job_data_update: exception: %s' % (str(e),))
      if not locked_table:
         log.error('job_data_update: cannot get row lock...')
         raise GWIS_Error('%s %s'
            % ('Unable to update work_item job_data!',
               'Please try again soon.',))

      self.job_data_update_with_lock(db)

      db.transaction_commit()
      log.verbose4('job_data_update: release database lock.')

      db.close()

   #
   def job_data_update_with_lock(self, db):

      # Prepare the job data.
      self.job_data_prepare()
      self.job_data_packit()

      # NOTE: Let Postgres do the interpolation, since job_raw is binary.
      rows = db.sql(
         """
         UPDATE 
            work_item 
         SET 
            job_dat = %s, 
            job_raw = %s
         WHERE 
            system_id = %s
         """, (self.job_dat, 
               self.job_raw, 
               self.system_id,))
      g.assurt(rows is None) # sql throws on error and returns naught else

   # ***

   #
   def get_zipname(self):
      g.assurt(False)

class Many(nonwiki_item.Many):

   one_class = One

   job_class = None

   # *** SQL clauseses

   sql_clauses_cols_all = nonwiki_item.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , wkit.job_class
      , wkit.created_by
      , wkit.job_priority
      , wkit.job_finished
      , wkit.num_stages
      , wkit.job_fcn
      , wkit.job_dat
      , wkit.job_raw
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN work_item AS wkit
         ON (gia.item_id = wkit.system_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.job_class
      , group_item.created_by
      , group_item.job_priority
      , group_item.job_finished
      , group_item.num_stages
      , group_item.job_fcn
      , group_item.job_dat
      , group_item.job_raw
      """
      )

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      nonwiki_item.Many.__init__(self)

   # *** Public interface

#FIXME: How do you return counts for the paginator?
#and should you return counts? i.e., not for geofeatures, esp.
# make a new command, since you shouldn't piggyback the total on 
# every checkout. item_count_get. or maybe put in the filter obj?

   #
   def search_get_sql(self, qb):
      g.assurt(not qb.confirm_leafiness)
      # Work Items apply to one branch and one branch only.
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1

# BUG nnnn: If branch arbiter, get all users' jobs.
#           You may need to add branch access to branch_hier?

      log.verbose('self.job_class: %s' % (self.job_class,))
      sql = nonwiki_item.Many.search_get_sql(self, qb)
      qb.branch_hier_limit = branch_hier_limit
      return sql

   #
   def search_item_type_id_sql(self, qb, item_type_ids=None):
      if (item_type_ids is None) or (len(item_type_ids) == 1):
         # Just use the leaf class's item type ID.
         g.assurt((item_type_ids is None) 
                  or (item_type_ids[0] == self.one_class.item_type_id))
         where_clause = nonwiki_item.Many.search_item_type_id_sql(self, qb)
      else:
         # This is an intermediate class, so use multiple item type IDs.
         where_clause = (" (gia.item_type_id IN (%s)) " 
                         % (', '.join([('%d' % x) for x in item_type_ids]),))
      log.verbose('search_item_type_id_sql: where: %s' % (where_clause,))
      return where_clause

   #
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id, job_classes=None):
      where_extra = nonwiki_item.Many.sql_inner_where_extra(self, qb, 
                           branch_hier, br_allow_deleted, min_acl_id)
      if job_classes is None:
         job_classes = []
         if self.job_class:
            job_classes = [self.job_class,]
         # else, e.g., ./ccp.py -r -t work_item
      if job_classes:
         if len(job_classes) == 1:
            where_extra += (" AND wkit.job_class = '%s' " % (self.job_class,))
         else:
            where_extra += (" AND wkit.job_class IN (%s) " 
                            % (', '.join(
                               [("'%s'" % x) for x in job_classes]),))
      return where_extra

   # *** Download associated file interface

   #
   def search_enforce_download_rules(self, qb):
      log.verbose('search_enforce_download_rules')
      # This check is now part of checkout.py, too.
      try:
         stack_id = int(qb.filters.only_stack_ids)
      except ValueError:
         # This is only caused by a miscoded client.
         raise GWIS_Error('Expected one stack ID of work item to download.')
      g.assurt(len(self) <= 1)
      # Check that the state of the item is complete.
      if len(self) == 1:
         wtem = self[0]
         if ((not wtem.job_finished) 
             or (wtem.latest_step.status_text != 'complete')):
            # Another miscoded client situation.
            raise GWIS_Error('Job not complete! Nothing to download.')
         # Let request.py's fetch_n_save() command complete. When the request 
         # uses the command class to build the response XML, we'll get 
         # our chance to sneak in the download file.
      else:
         # This, too, should be a miscoded client problem.
         raise GWIS_Error('Item with stack ID "%d" not found!' % (stack_id,))

   #
   def postpare_response(self, doc, elem, extras):
      log.verbose('postpare_response')
      nonwiki_item.Many.postpare_response(self, doc, elem, extras)
      # This fcn. is called by checkout.py after it's built its self.doc, which
      # is the XML response it thinks it's going to send back to the client.
      # But we want to send back a file instead. In extras, you'll find that
      # the first element is the request's self.sendfile_out.
      sendfile_out_i = 0
      extras[sendfile_out_i] = self.get_download_filename()

   #
   def get_download_filename(self):
      # By default, return the item details XML.
      return None

   # *** Mr Do! interface

   #
   def search_by_latest_branch_job(self, qb):

      # User clients are not allowed access to this list.
      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)

      # Don't get jobs that are the finished. This fcn. is only interested in
      # hot jobs.

      # This search gets one hot job of each job_class for each branch, or None
      # for those branch or job_classes without hot jobs.
      #
      # Make sure you order by ID ASC, otherwise if new jobs get added you
      # might accidentally start extra ones for the branch, since the rows
      # returned will change (that is, make sure your query returns the same
      # results as new jobs are added).

      # 2012.05.11: Changing so this processes one job per user per job type
      # per branch.

      sql = (
         """
         SELECT 

            DISTINCT ON (item.branch_id, wkit.job_class, wkit.created_by) 
              wkit.branch_id
            , item.stack_id
            --, item.branch_id
            , item.system_id
            , item.version

            , item.deleted
            , item.name
            , item.valid_start_rid
            , item.valid_until_rid

            , wkit.job_class
            , wkit.created_by
            , wkit.job_priority
            , wkit.job_finished
            , wkit.num_stages
            , wkit.job_fcn
            , wkit.job_dat
            , wkit.job_raw

            FROM 

               work_item AS wkit

            JOIN 

               item_versioned AS item
               ON (item.system_id = wkit.system_id)

            WHERE

               /* NOTE: Item only has one version in db, so this is cool. */
               item.deleted = FALSE
               AND wkit.job_finished = FALSE

            ORDER BY

               item.branch_id ASC
               , wkit.job_class ASC
               , wkit.created_by ASC
               , item.stack_id ASC

         """)

      # This fcn. is meant to run outside the GrAC subsystem.
      g.assurt(qb.username == '')
      g.assurt(len(qb.branch_hier) == 0)
      #g.assurt(qb.revision is None)
      g.assurt(isinstance(qb.revision, revision.Current))

      # Do the search.
      res = qb.db.sql(sql)
      # FIXME: Maybe just send db to One.__init__ and not the whole qb?
      for row in res:
         item = self.get_one(qb, row)
         self.append(item)

