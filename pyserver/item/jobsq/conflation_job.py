# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys

from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import nonwiki_item
from item.feat import route
from item.feat import route_step
from item.jobsq import work_item
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('conflat_jb')

# Standard deviation for distance between a location and a block. (in meters)
STD_DEFAULT = 10
# The maximum distance to consider a block near a location. The smaller this
# distance, the stricter the algorithm will be when matching locations to
# blocks. (in meters)
CUTOFF_DEFAULT = STD_DEFAULT * 4

# SYNC_ME: See pyserver/items/jobsq/conflation_job.py
#              flashclient/item/jobsq/Conflation_Job.as???
class One(work_item.One):

   # Base class overrides

   item_type_id = Item_Type.CONFLATION_JOB
   item_type_table = 'conflation_job'
   item_gwis_abbrev = 'cjob'
   child_item_types = None

   local_defns = [
      # py/psql name,               deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('track_id',                  None,  True,   False,    int,     0),
      ('revision_id',               None,  True,   False,    int,     0),
      ('cutoff_distance', CUTOFF_DEFAULT,  True,   False,    float,   0),
      ('distance_error',     STD_DEFAULT,  True,   False,    float,   0),
      ]
   attr_defns = work_item.One.attr_defns + local_defns
   psql_defns = work_item.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      'ride',
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      self.ride = None
      work_item.One.__init__(self, qb, row, req, copy_from)
      self.job_class = 'conflation_job'
      self.job_fcn = (
         'conflation.conflation:Conflation:process_request')

   #
   def __str__(self):
      return ((work_item.One.__str__(self))
              + (', Cj: tid: %s rev: %s'
                 % (self.track_id, self.revision_id,)))

   #
   def append_gml(self, elem, need_digest):

      job_elem = work_item.One.append_gml(self, elem, need_digest)
      if (self.ride is not None):
         self.ride.append_gml(job_elem, need_digest)
      return job_elem

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
         # Save to the 'conflation_job' table.
         self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_core_save_file_maybe(self, qb):
      # The client shouldn't be trying to upload a file.
      g.assurt((not self.download_fake) and (not self.resident_download))
      # Call the base class; should be a no-op.
      work_item.One.save_core_save_file_maybe(self, qb)

   # ***

# ***

class Many(work_item.Many):

   one_class = One

   job_class = 'conflation_job'

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = work_item.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , cj.track_id
      , cj.revision_id
      , cj.cutoff_distance
      , cj.distance_error
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN conflation_job AS cj
         ON (gia.item_id = cj.system_id)
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

   #
   def search_get_items(self, qb):
      work_item.Many.search_get_items(self, qb)
      if (qb.filters.include_item_aux):
         self.conflation_load_aux(qb)

   #
   def conflation_load_aux(self, qb):
      job = self[0]
      job.ride = route.One()
      rows = qb.db.sql(
         """
         SELECT
            step_number,
            byway_stack_id,
            byway_geofeature_layer_id,
            step_name,
            split_from_stack_id,
            beg_node_id,
            fin_node_id,
            forward,
            beg_time,
            fin_time,
            ST_AsText(geometry) AS geometry_wkt,
            ST_AsSVG(ST_Scale(geometry, 1, -1, 1), 0, %d)
                     AS geometry
         FROM
            conflation_job_ride_steps
         WHERE
            job_id = %d
         ORDER BY
            step_number ASC
         """ % (conf.db_fetch_precision, job.system_id,))
      for row in rows:
         job.ride.rsteps.append(route_step.One(qb, row=row))

   # ***

# ***

