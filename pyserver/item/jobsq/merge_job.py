# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import nonwiki_item
#from item.jobsq import job_base
from item.jobsq import work_item
from item.util import revision
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('merge_job')

# SYNC_ME: See pyserver/items/jobsq/merge_job.py
#              flashclient/item/jobsq/Merge_Job.as
class One(work_item.One):

   # Base class overrides

   item_type_id = Item_Type.MERGE_JOB
   item_type_table = 'merge_job'
   item_gwis_abbrev = 'mjob'
   # 2013.04.07: This is new. We used to not filter by item type.
   child_item_types = (
      Item_Type.MERGE_JOB,
      Item_Type.MERGE_EXPORT_JOB,
      Item_Type.MERGE_IMPORT_JOB,
      )

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      # FIXME: Need to verify this from the user.
      ('for_group_id',        None,   True,   False,    int,     1),
      # FIXME: Specifying historic revs. means users added to groups 
      # later can see data from earlier.
      ('for_revision',        None,   True,   False,    int,     1),
      # Attributes stored in job_dat/job_raw.
      ('filter_by_region',    None,   True,    None,    str,     0),
      #
      ('enable_conflation',   None,  False,    None,   bool,     0),
      ]
   attr_defns = work_item.One.attr_defns + local_defns
   psql_defns = work_item.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   _job_def_cols = [
      # job_def.[name],       deft
      ('filter_by_region',    None,),
      # BUG nnnn: Implement conflation
      ('enable_conflation',   None,),
      ]
   job_def_cols = work_item.One.job_def_cols + _job_def_cols

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      work_item.One.__init__(self, qb, row, req, copy_from)
      self.resident_download = None
      # If row is not None, it usually means the item is being loaded from the
      # database, but ccp.py also creates temporary items using row, so check
      # system_id to see if the item really exists or not.
      if (row is not None) and (self.system_id is not None):
         # The item exists in the database, so we expect a few things to
         # already be set.
         g.assurt(self.job_fcn)
         #g.assurt(self.for_group_id)

   # 
   def __str__(self):
      return ((work_item.One.__str__(self))
              + (', Merj: grp: %s, rev: %s, reg: %s'
                 % (self.for_group_id, 
                    self.for_revision,
                    self.filter_by_region,)))

   #
   def from_gml(self, qb, elem):
      # This fcn., from_gml, called from commit.
      work_item.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      work_item.One.save_core(self, qb)
      if self.fresh:
         g.assurt(self.version == 1)
         g.assurt(not self.deleted)
         # Save to the 'merge_job' table.
         self.save_insert(qb, One.item_type_table, One.psql_defns)

class Many(work_item.Many):

   one_class = One

   job_class = 'merge_job'

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = work_item.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , merj.for_group_id
      , merj.for_revision
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN merge_job AS merj
         ON (gia.item_id = merj.system_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.for_group_id
      , group_item.for_revision
      """
      )

   # *** Constructor

   def __init__(self):
      work_item.Many.__init__(self)

   # ***

   #
   def search_item_type_id_sql(self, qb, item_type_ids=None):
      # Derived classes send their item type IDs, but if the user is just
      # interacting with this intermediate class, then let's use all derived
      # classes' IDs.
      if item_type_ids is None:
         # HACKy: This class -- the parent class -- has to know about its
         #        children.
         item_type_ids = [Item_Type.MERGE_EXPORT_JOB,
                          Item_Type.MERGE_IMPORT_JOB,]
      where_clause = work_item.Many.search_item_type_id_sql(self, qb, 
                                                            item_type_ids)
      return where_clause

   # Merge_Jobs are... special. Sometimes, we want to distinguish between
   # import and export job types, and other times we don't. When the client 
   # asks for a list of merge_jobs: then we don't care; we want both import 
   # and export jobs.
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id, job_classes=None):
      g.assurt(self.job_class) # self.job_class is always set?
      if job_classes is None:
         # HACK: These are the names of our sub-job classes, or whatever
         # they're called (they're classes in the code but they don't have
         # their own tables...).
         job_classes = ['merge_export_job', 'merge_import_job',]
      where_extra = work_item.Many.sql_inner_where_extra(self, qb, 
            branch_hier, br_allow_deleted, min_acl_id, job_classes)
      return where_extra

