# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis.query_base import Query_Base
from gwis.exception.gwis_error import GWIS_Error
from item.util import revision

log = g.log.getLogger('gwis.q_viewport')

class Query_Revision(Query_Base):
   '''This is a lightweight wrapper around item.util.revision.'''

   __after_slots__ = (
      'rev',
      )

   def __init__(self, req):
      Query_Base.__init__(self, req)
      self.rev = revision.Current()

   # *** Public interface

   def __str__(self):
      return 'query_revision: %s' % (str(self.rev),)

   # *** Base class overrides

   def decode_gwis(self):
      # Consume the revision, if supplied; else assume 'Current' revision.
      if self.req.cmd.filter_rev_enabled:
         # Revision filter (optional)
         rev = self.req.decode_key('rev', '')
         # Decode the revision or raise trying, or use Current() if '' or None.
         self.rev = revision.Revision.revision_object_get(rev)
         # Check for another reality.
         if self.req.filters.only_system_id:
            if not isinstance(self.rev, revision.Current):
               raise GWIS_Error('Please separate revisions and system IDs.')
            self.rev = revision.Comprehensive()
      else:
         # This happens for commit: always assume Current. Even though
         # flashclient sends us the rev, we still ignore it....
         g.assurt(isinstance(self.rev, revision.Current))

   # ***

   def as_sql_where(self, table_name=None):
      g.assurt(False) # I don't think this fcn. is called
      return self.rev.as_sql_where(table_name)

# *** Unit test code

if (__name__ == '__main__'):
   pass

