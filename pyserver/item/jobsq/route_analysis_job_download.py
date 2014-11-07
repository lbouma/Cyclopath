# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys

from item.jobsq import route_analysis_job
from item.jobsq import work_item_download
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('route_analysis_job_dl')

class One(work_item_download.One):

   # Base class overrides

   # This is deliberately the same type as the class whose download we want.
   # FIXME: I think this really just has to be WORK_ITEM.
   item_type_id = Item_Type.ROUTE_ANALYSIS_JOB
   item_type_table = 'route_analysis_job'
   item_gwis_abbrev = 'rjob'
   child_item_types = None

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      work_item_download.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def get_zipname(self):
      # E.g., 'Route_Analysis'
      return route_analysis_job.One.route_analysis_job_zipname

class Many(work_item_download.Many):

   one_class = One

   job_class = 'route_analysis_job'
   #job_class = 'work_item'

   # *** Constructor

   def __init__(self):
      work_item_download.Many.__init__(self)

