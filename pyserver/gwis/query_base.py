# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('gwis.query_base')

class Query_Base(object):

   # NOTE: Because of cPickle, do not define __slots__.
   __after_slots__ = (
      'req', # Cyclopath request object
   )

   # NOTE The Query_Base class is a little bit ackward. It's similar 
   #      to the command classes, but the command classes represent
   #      one class hierarchy, and the query classes are all independent
   #      descendants. If anything, I [landonb] feel that multiple, 
   #      independent objects makes more sense than a class hierarchy, but, 
   #      on the same hand, I understand that the class hierarchy forces a 
   #      dependency among the objects, i.e., the viewport filter relies
   #      upon the revision filter, which relies upon the branch, which 
   #      relies upon which user is logged in. In any case, the Query 
   #      classes are Good Enough for Now. ("Totes GEN.") One good reason
   #      why this design is still better than the old design: it helps 
   #      decouple the code, keeping different types of operations separate.

   def __init__(self, req):
      self.req = req

   # ***

   """
   #
   def __getstate__(self):
      return False

   #
   def __setstate__(self, state):
      g.assurt(False)
   """

   #
   def __eq__(self, other):
      # NOTE: Ignoring self.req
      return isinstance(other, Query_Base)

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   # *** Public interface

   #
   def decode_gwis(self):
      g.assurt(False) # Abstract

   # *** Private interface / static class methods

   # FIXME: This feels like it belongs in db_glue.
   @staticmethod
   def table_name_prefixed(table_name):
      if (table_name is None):
         return ''
      else:
         return table_name + '.'

