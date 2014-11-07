# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from util_ import misc

log = g.log.getLogger('gwis.nothing_found')

class GWIS_Nothing_Found(Exception):
   '''Used to short-circuit checkout when we know no items will be found.'''

   __slots__ = (
      )

   def __init__(self, message='', tag=None, logger=log.debug):
      Exception.__init__(self, message)
      self.gerrs = []
      logger('GWIS_Nothing_Found caught: %s.' % (message,))

   # *** Public interface

   #
   def as_xml(self, elem_name='gwis_nothing_found'):
      g.assurt(False) # Not used.

# *** Unit test code

if __name__ == '__main__':
   pass

