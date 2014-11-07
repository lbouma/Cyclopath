# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys

from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import nonwiki_item
#from item.jobsq import job_base
from item.jobsq import work_item
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('rt_anlyss_jb')

class Route_Source:
   USER = 1
   SYNTHETIC = 2
   JOB = 3
   RADIAL = 4

# SYNC_ME: See pyserver/items/jobsq/route_analysis_job.py
#              flashclient/item/jobsq/Route_Analysis_Job.as
class One(work_item.One):

   # Base class overrides

   item_type_id = Item_Type.ROUTE_ANALYSIS_JOB
   item_type_table = 'route_analysis_job'
   item_gwis_abbrev = 'rjob'
   child_item_types = None

   route_analysis_job_zipname = 'Route_Analysis'

   local_defns = [
      # py/psql name,             deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      # FIXME: Make this name longer...
      ('n' ,                      None,  True,   False,    int,     1,    'n'),
      ('revision_id' ,            None,  True,   False,    int,     0),
      ('rt_source' , Route_Source.USER,  True,   False,    int,     0),
      ('cmp_job_name',              '',  True,   False,    str,     0),
      ('regions_ep_name_1' ,        '',  True,   False,    str,     0),
      ('regions_ep_tag_1' ,         '',  True,   False,    str,     0),
      ('regions_ep_name_2' ,        '',  True,   False,    str,     0),
      ('regions_ep_tag_2' ,         '',  True,   False,    str,     0),
      ('rider_profile' ,     'default',  True,   False,    str,     0),
      ]
   attr_defns = work_item.One.attr_defns + local_defns
   psql_defns = work_item.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      work_item.One.__init__(self, qb, row, req, copy_from)
      self.job_class = 'route_analysis_job'
      self.job_fcn = (
         'route_analysis.route_analysis:Route_Analysis:process_request')
      # If the user passed just one region's name and tag, we need it to be
      # the first one.
      if ((not self.regions_ep_name_1 and not self.regions_ep_tag_1)
          and (self.regions_ep_name_2 or self.regions_ep_tag_2)):
         self.regions_ep_name_1 = self.regions_ep_name_2
         self.regions_ep_name_2 = ''
         self.regions_ep_tag_1 = self.regions_ep_tag_2
         self.regions_ep_tag_2 = ''

   # 
   def __str__(self):
      return ((work_item.One.__str__(self))
              + (', Raj: n: %s rev: %s'
                 % (self.n, self.revision_id,)))

   #
   def from_gml(self, qb, elem):
      work_item.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      work_item.One.save_core(self, qb)
      if self.fresh:
         g.assurt(self.version == 1)
         g.assurt(not self.deleted)
         # Save to the 'route_analysis_job' table.
         self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_core_remove_files_maybe(self):
      work_item.One.save_core_remove_files_maybe(self)

   #
   def save_core_save_file_maybe(self, qb):
      # The client shouldn't be trying to upload a file.
      g.assurt((not self.download_fake) and (not self.resident_download))
      # Call the base class; should be a no-op.
      work_item.One.save_core_save_file_maybe(self, qb)

   # ***

   #
   def get_zipname(self):
      # E.g., 'Route_Analysis'.
      return One.route_analysis_job_zipname

class Many(work_item.Many):

   one_class = One

   job_class = 'route_analysis_job'

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = work_item.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , raj.n
      , raj.revision_id
      , raj.rt_source
      , raj.cmp_job_name
      , raj.regions_ep_name_1
      , raj.regions_ep_tag_1
      , raj.regions_ep_name_2
      , raj.regions_ep_tag_2
      , raj.rider_profile
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN route_analysis_job AS raj
         ON (gia.item_id = raj.system_id)
      """
      )

   # FIXME: Don't know what to do with this.
   #
   #sql_clauses_cols_all.outer.shared += (
   #   """
   #   , group_item.for_group_id
   #   , group_item.for_revision
   #   """
   #   )

   # *** Constructor

   def __init__(self):
      work_item.Many.__init__(self)

