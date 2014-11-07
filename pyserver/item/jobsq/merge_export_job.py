# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os

import conf
import g

from item import item_base
from item.jobsq import merge_job
from item.util import revision
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('merge_export')

# SYNC_ME: See pyserver/items/jobsq/merge_export_job.py
#              flashclient/item/jobsq/Merge_Export_Job.as
class One(merge_job.One):

   # Base class overrides

   item_type_id = Item_Type.MERGE_EXPORT_JOB
   item_type_table = 'merge_job' # Import uses the merge_job table.
   item_gwis_abbrev = 'imjb'
   child_item_types = None

   merge_job_zipname = 'Cyclopath-Export'

   local_defns = [
      #('enable_conflation',   None,  False,    None,   bool,     0),
      ]
   attr_defns = merge_job.One.attr_defns + local_defns
   psql_defns = merge_job.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   _job_def_cols = [
      # job_def.[name],       deft
      ## BUG nnnn: Implement conflation
      #('enable_conflation',   None,),
      ]
   job_def_cols = merge_job.One.job_def_cols + _job_def_cols

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      merge_job.One.__init__(self, qb, row, req, copy_from)
      self.job_class = 'merge_export_job'
      self.job_fcn = (
         'merge.merge_job_export:Merge_Job_Export:process_request')
      # The client shouldn't be trying to upload a file.
      g.assurt((req is None) or (req.file_data_in is None))
      # See if the item is being loaded from the database.
      if (row is not None) and (self.system_id is not None):
         # The item exists in the database, so we expect a few things to
         # already be set.
         g.assurt(self.for_revision)

   # 
   def __str__(self):
      return ((merge_job.One.__str__(self))
              + (', Export'))

   #
   def from_gml(self, qb, elem):
      # This fcn., from_gml, called from commit.
      merge_job.One.from_gml(self, qb, elem)
      # FIXME: Why don't we set self.job_class in the Constructor?
      #self.job_class = 'merge_export_job'
      if self.job_act == 'create':
         pass
#         g.assurt(not self.job_fcn)
         #if self.is_import_job():
         #   self.job_fcn = (
         #      'merge.merge_job_import:Merge_Job_Import:process_request')
         #else:
         #   self.job_fcn = (
         #      'merge.merge_job_export:Merge_Job_Export:process_request')
#         self.job_fcn = (
#            'merge.merge_job_export:Merge_Job_Export:process_request')

   # *** Saving to the Database

   #
   def save_core(self, qb):

      if self.fresh:
         g.assurt(self.version == 1)
         g.assurt(not self.deleted)
         # If the user specified no revision, rather than using Current, still
         # use a revision number, in case users save to the map while we're
         # working.
         # NOTE: This feels like a weird place to set revision -- on save
         # rather than on load. But we have to do it after from_gml....
         # FIXME: Is the rev ID stored where it really belongs? Could it
         # instead be apart of the work item step's callback_def?
         if not self.for_revision:
            self.for_revision = revision.Revision.revision_max(qb.db)
            log.debug('from_gml: set default for_revision: %d'
                      % (self.for_revision,))

      merge_job.One.save_core(self, qb)

   #
   def save_core_remove_files_maybe(self):
      merge_job.One.save_core_remove_files_maybe(self)

   #
   def save_core_save_file_maybe(self, qb):
      # The client shouldn't be trying to upload a file.
      g.assurt((not self.download_fake) and (not self.resident_download))
      # Call the base class; should be a no-op.
      merge_job.One.save_core_save_file_maybe(self, qb)

   # ***

   #
   def get_zipname(self):
      # E.g., 'Cyclopath-Export'.
      return One.merge_job_zipname

class Many(merge_job.Many):

   one_class = One

   job_class = 'merge_export_job'

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      merge_job.Many.__init__(self)

   #
   def search_item_type_id_sql(self, qb, item_type_ids=None):
      g.assurt(item_type_ids is None)
      item_type_ids = [self.one_class.item_type_id,]
      where_clause = merge_job.Many.search_item_type_id_sql(self, qb, 
                                                            item_type_ids)
      return where_clause

   #
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id, job_classes=None):
      g.assurt(job_classes is None)
      job_classes = [One.job_class,]
      where_extra = merge_job.Many.sql_inner_where_extra(self, qb, 
            branch_hier, br_allow_deleted, min_acl_id, job_classes)
      return where_extra

