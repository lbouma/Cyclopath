# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys

from item import item_base
from item.jobsq import work_item
from item.util.item_type import Item_Type

__all__ = ['One', 'Many',]

log = g.log.getLogger('work_item_dl')

class One(work_item.One):

   # Base class overrides

   local_defns = [
      ]
   attr_defns = work_item.One.attr_defns + local_defns
   psql_defns = work_item.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      work_item.One.__init__(self, qb, row, req, copy_from)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      g.assurt(False) # Not supported

   # ***

   #
   def get_zipname(self):
      g.assurt(False)

class Many(work_item.Many):

   one_class = One

   # This is deliberately the same type as the base class.
   # job_class = 'merge_job'

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      work_item.Many.__init__(self)

   # ***

   #
   def search_for_items(self, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      work_item.Many.search_for_items(self, qb)
      self.search_enforce_download_rules(qb)

   #
   def get_download_filename(self):
      zpath = None
      if len(self) != 1:
         # This shouldn't happen unless the client has been hacked, right?
         log.error('get_download_filename: too many or too few many: %d'
                   % (len(self),))
      else:
         wtem = self[0]
         fbase = '%s.fin' % (wtem.local_file_guid,)
         fpath = os.path.join(conf.shapefile_directory, fbase)
         zbase = '%s.zip' % (wtem.get_zipname(),)
         zpath = os.path.join(fpath, zbase)
         # FIXME: I want to rename the zip so it's not a weird name that the
         # user downloads.
         log.debug('get_download_filename: %s' % (zpath,))
      return zpath

