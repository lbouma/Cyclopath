# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy

import conf
import g

from item.feat import branch
from grax.access_level import Access_Level
from gwis.query_base import Query_Base
from gwis.query_overlord import Query_Overlord
from gwis.exception.gwis_error import GWIS_Error
#from item import item_user_access
from item.feat import branch
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import misc

log = g.log.getLogger('gwis.q_branch')

class Query_Branch(Query_Base):

   __after_slots__ = (
      'branch_id',         # The branch ID, or None for public base map
      'access_level_id',   # The user's access to the branch for a certain rev
      'branch_hier',       # List of branch IDs: cur. branch, then parent, etc.
      )

   # *** Constructor

   def __init__(self, req):
      Query_Base.__init__(self, req)

   # *** Base class overrides

   #
   def decode_gwis(self):
      #log.debug('decode_gwis')
      # NOTE: If client doesn't specify branch, assuming public basemap.
      #       However, for some Grac commands, like getting a user's group
      #       memberships, the branch ID is meaningless.
      self.branch_id = int(self.req.decode_key('brid', 0))
      if not self.branch_id:
         self.branch_id = branch.Many.baseline_id(self.req.db)
         log.verbose1(' >> baseline_id: %d' % (self.branch_id,))
      else:
         log.verbose1(' >> branch_id: %d' % (self.branch_id,))
      # Build the branch hierarchy.
      self.branch_hier = branch.Many.branch_hier_build(self.req.db, 
                                                       self.branch_id,
                                                       self.req.revision.rev)
      log.verbose1(' >> branch_hier: %s' % (self.branch_hier,))

   ## Private interface

   # Check that the user has rights to access the branch at the revision or
   # revisions specified. If committing, the user needs editor access to the
   # leaf branch; if checking out, the user just needs viewer access. In either
   # case, the user needs viewer access to any parent branches.
   # NOTE: If the user does not have access, this raises an exception.
   def branch_hier_enforce(self):
      branch_update_enabled = self.req.cmd.branch_update_enabled
      # Process the branch from the leafiest to the parentiest. Only on the
      # leaf branch does the user need editor access; s/he just needs viewer
      # access otherwise.
      # NOTE: This copies references. E.g., it copies a list of sets, so each
      #       list is unique but each set therein has the same id(). But sets
      #       are immutable, so, ha.
      branch_tups = copy.copy(self.branch_hier)
      # Use reversed() instead of .reverse() because more collection types
      # support reversed() than .reverse() (i.e., get in the habit...).
      # NO: branch_tups.reverse()
      for branch_tup in reversed(branch_tups):
         self.branch_hier_enforce_branch(branch_tup, branch_update_enabled)
         # Only the leaf branch requires the user to have editor access on
         # commit
         branch_update_enabled = False

   # 
   def branch_hier_enforce_branch(self, branch_tup, branch_update_enabled):
      '''
      Checks the user's access to a branch at the requested revision, or 
      revisions, in the case of a Diff.

      We always check the user's access at the latest revision, to understand 
      what their access to the current branch really is.
      '''
      log.verbose1('self.req.revision.rev: %s' % (self.req.revision.rev,))
      if isinstance(self.req.revision.rev, revision.Current):
         if branch_update_enabled:
            min_access = Access_Level.editor
         else:
            min_access = Access_Level.viewer
         self.access_level_id = self.branch_hier_enforce_revision(
            branch_tup, self.req.revision.rev, min_access)
      elif isinstance(self.req.revision.rev, revision.Historic):
         g.assurt(not branch_update_enabled)
         self.branch_hier_enforce_revision(
            branch_tup, self.req.revision.rev, Access_Level.viewer)
         # In historic mode, access is always viewer
         self.access_level_id = Access_Level.viewer
      elif isinstance(self.req.revision.rev, revision.Diff):
         # The user needs view access or better to both revisions.
         acl_viewer = Access_Level.viewer
         g.assurt(not branch_update_enabled)
         rev = revision.Historic(self.req.revision.rev.rid_old)
         self.branch_hier_enforce_revision(branch_tup, rev, acl_viewer)
         rev = revision.Historic(self.req.revision.rev.rid_new)
         self.branch_hier_enforce_revision(branch_tup, rev, acl_viewer)
         # In historic mode, access is always viewer
         self.access_level_id = Access_Level.viewer
      elif isinstance(self.req.revision.rev, revision.Updated):
         log.error(
            'Updated revision requested. This is only secure for scripts.')
         raise GWIS_Error('GWIS does not support revision.Updated.')
      elif isinstance(self.req.revision.rev, revision.Comprehensive):
         self.access_level_id = self.branch_hier_enforce_revision(
            branch_tup, revision.Current(), Access_Level.viewer)
      else:
         g.assurt(False)

   #
   def branch_hier_enforce_revision(self, branch_tup, rev, min_access=None):
      #branch.Many.branch_enforce_permissions(self.req.db, 
      #                                       self.req.client.username, 
      #                                       branch_id, 
      #                                       rev, 
      #                                       min_access)
      branch_hier = [(branch_tup[0], rev, branch_tup[2],),]
      qb = Item_Query_Builder(self.req.db,
                              self.req.client.username,
                              branch_hier,
                              rev,
                              viewport=None, 
                              filters=None, 
                              user_id=None)
      Query_Overlord.finalize_query(qb)
      branch.Many.branch_enforce_permissions(qb, min_access)

   # ***

# ***

