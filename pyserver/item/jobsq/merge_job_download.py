# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys

from item.jobsq import merge_job
from item.jobsq import merge_import_job
from item.jobsq import merge_export_job
from item.jobsq import work_item_download
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('merge_job_dl')

# FIXME: This used to derive from merge_job, not work_item_download (which
# derives from work_item). Make sure you don't rely on the merge_job
# intermediate class!

class One(work_item_download.One):

   # Base class overrides

   # This is deliberately the same type as the class whose download we want.
   # NOTE: I [lb] think this really just has to be WORK_ITEM.
   item_type_id = Item_Type.MERGE_JOB
   item_type_table = 'merge_job'
   item_gwis_abbrev = 'mjob'
   child_item_types = None

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      work_item_download.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def get_zipname(self):
      # This is really hacky. This class, merge_job_download, ultimately 
      # derives from work_item... so this class is kind of a work_item type but
      # it's incomplete: it doesn't know anything about merge_job, or
      # merge_import_job, or merge_export_job...
      zipname = ''
      if self.job_class == 'merge_import_job':
         # E.g., = 'Cyclopath-Import'.
         zipname = merge_import_job.One.merge_job_zipname
      else:
         g.assurt(self.job_class == 'merge_export_job')
         # E.g., = 'Cyclopath-Export'.
         zipname = merge_export_job.One.merge_job_zipname
      return zipname

class Many(work_item_download.Many):

   one_class = One

   job_class = 'merge_job'
   #job_class = 'work_item'

   # *** Constructor

   def __init__(self):
      work_item_download.Many.__init__(self)

   #
   def search_item_type_id_sql(self, qb, item_type_ids=None):
      g.assurt(item_type_ids is None)
      if item_type_ids is None:
         # HACKy: The class -- the parent class -- has to know about its
         #        children.
         item_type_ids = [Item_Type.MERGE_EXPORT_JOB,
                          Item_Type.MERGE_IMPORT_JOB,]
      where_clause = work_item_download.Many.search_item_type_id_sql(self, qb, 
                                                            item_type_ids)
      return where_clause

   # 
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id, job_classes=None):
      g.assurt(job_classes is None)
      if job_classes is None:
         # HACK: These are the names of our sub-job classes, or whatever
         # they're called (they're classes in the code but they don't have
         # their own tables...).
         job_classes = ['merge_export_job', 'merge_import_job',]
      where_extra = work_item_download.Many.sql_inner_where_extra(self, qb, 
            branch_hier, br_allow_deleted, min_acl_id, job_classes)
      return where_extra

