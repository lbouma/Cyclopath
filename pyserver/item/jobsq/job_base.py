# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import copy
import os
import sys

from item.util.item_type import Item_Type

__all__ = ['Job_Base',]

log = g.log.getLogger('job_base')

class Job_Base(object):

   # NOTE: Skipping __slots__, other cPickle will complain,
   # TypeError: a class that defines __slots__ without defining 
   #            __getstate__ cannot be pickled.
   # But if you define __getstate__, you have to do the pickling yourself,
   # which seems like it defeats the purpose of using cPickle.

   # Base class overrides

   item_type_id = Item_Type.JOB_BASE
   item_type_table = 'job_base'
   #item_gwis_abbrev = 'jbas'
   child_item_types = None

   #
   def __init__(self, viewport, filters):
      log.debug('job_base: __init__')

      # We want to pickle the viewport and filters, but we cannot pickle a
      # class that defines __slots__ (that is, unless we also define
      # __getstate__, but I haven't got that to work). Neither viewport nor
      # filters define slots, but they do maintain a reference to the request
      # object, which does define slots, and also which we don't need to ref.
      #
      # FIXME: 2012.03.23: I don't think we should attach viewport and filters
      # to job, but should just make what we care about attributes of the job.
      self.viewport = copy.copy(viewport)
      self.viewport.req = None
      self.filters = copy.copy(filters)
      self.filters.req = None

   #
   def re_init(self):
      # NOTE: Nothing to do currently. If the job def changes, this fcn. should
      # make sure that what is stored in the database gets hydrated correctly
      # into the new job def.
      # NOTE: See Query_Filters.fix_missing() for an example.
      self.filters.fix_missing()
      pass

   #
   def __eq__(self, other):
      log.verbose('job_base: checking __eq__...')
      log.verbose('  id(self): %d' % (id(self),))
      log.verbose('  id(other): %d' % (id(other),))
      log.verbose('  self.viewport: %s' % (self.viewport,))
      log.verbose('  other.viewport: %s' % (other.viewport,))
      log.verbose('  self.filters: %s' % (self.filters,))
      log.verbose('  other.filters: %s' % (other.filters,))
      return (   (self.viewport == other.viewport)
              and (self.filters == other.filters))

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   # ***

# ***

class Callback_Def_Base(object):

   # NOTE: Skipping __slots__, other cPickle will complain,
   # TypeError: a class that defines __slots__ without defining 
   #            __getstate__ cannot be pickled.
   # But if you define __getstate__, you have to do the pickling yourself,
   # which seems like it defeats the purpose of using cPickle.

   #
   def __init__(self):
      log.debug('callback_def_base: __init__')

   #
   def re_init(self):
      # NOTE: Nothing to do currently. If the callback def changes, this fcn.
      # should make sure that what is stored in the database gets hydrated
      # correctly into the new callback def.
      # NOTE: See Query_Filters.fix_missing() for an example.
      pass

   #
   def __eq__(self, other):
      log.verbose('callback_def_base: checking __eq__...')
      log.verbose('  id(self): %d' % (id(self),))
      log.verbose('  id(other): %d' % (id(other),))
      return (id(self) == id(other))

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   # ***

# ***

