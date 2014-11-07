# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from grax.access_level import Access_Level
from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item.feat import branch
from item.util import revision
from util_ import misc

log = g.log.getLogger('cmd.grac_get')

# NOTE This module is similar to checkout. The client calls us to get at a
#      number of different tables dealing with access control, like group_,
#      group_membership, and new_item_access. These tables (and the objects we
#      create when we fetch from 'em), all share things in common, like how we 
#      determine if the user can view or edit them. Also, every object we
#      return to the client has both the group_id and group_name.

# GWAC: Geo Wiki Access Control
# Pronounced: "Geeeeeee-WHACK!"
# GrAC: Group Access Control
# Pronounced: Well, just "Grack"

# Instead of using 'gwac' (or 'grac') for object names, 'control' is an 
# acceptable synonym

class Op_Handler(command.Op_Handler):

   __slots__ = (
      # ** Client Request Values
      'control_type',      # Type of access control records client requested
      'control_context',   # Request context: 'user', 'branch', 'group', 'item'
                           # - See below for lots of blather about this...
      # ** Internal Variables
      'control_handler',   # An instantiated class of type control_type
      )

   # *** Constructor

   #
   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      # Tell the ancestor class, command_revision, to look for a revision ID. 
      # Not all of the control types this class uses will honor historical 
      # requests, however (currently, just group_membership does).
      self.filter_rev_enabled = True
      self.control_type = None
      self.control_context = None
      self.control_handler = None

   # ***

   #
   def __str__(self):
      selfie = (
         'grac_get: ctl_type: %s / ctl_ctxt: %s / ctl_hndlr: %s'
         % (self.control_type,
            self.control_context,
            self.control_handler,))
      return selfie

   # *** Base class overrides

   #
   def decode_request(self):
      'Validate and decode the incoming request.'
      #import rpdb2
      #rpdb2.start_embedded_debugger('password', fAllowRemote=True)
      command.Op_Handler.decode_request(self)
      # Get the type of access control records to fetch. This is required and 
      # the fcn. throws a GWIS_Error() if the access record type is bogus.
      self.decode_request_control_request()
      # The GrAC commands don't know anything about diffing.
      if isinstance(self.req.revision.rev, revision.Diff):
         raise GWIS_Error('GrAC does not support Diff requests.')
      # Hmmm. Maybe we don't support Updated, either. Just Current or Historic.
      if isinstance(self.req.revision.rev, revision.Updated):
         raise GWIS_Error('GrAC does not support Updated requests.')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      # If we're here, decode_request didn't raise, which means the requested
      # access type is valid.
      qb = self.req.as_iqb()
      # FIXME: Where should we check permissions? Here?:
      if self.control_context == 'branch':
         # As of 2011.08.19, only new_item_policy handles branch context, and
         # it only makes sense to return the nips for the whole branch if the
         # person asking is Very Special (i.e., branch owner or arbiter).
         # NOTE: qb.branch_hier[0][0] is the leafiest branch's stack ID.
         #branch.Many.branch_enforce_permissions(qb.db,
         #                                       qb.username,
         #                                       qb.branch_hier[0][0],
         #                                       qb.revision,
         #                                       Access_Level.arbiter)
         branch.Many.branch_enforce_permissions(qb, Access_Level.arbiter)

      # Create a new instance of the access module's Many class.
      self.control_handler = self.get_access_control_module().Many()
      # Fetch the items
      # NOTE: Unlike checkout and commit, grac_get and grac_put use just the
      #       branch_id, not branch_hier, since these items aren't stacked.
      self.control_handler.search_by_context(self.control_context, qb)

   def prepare_response(self):
      e = etree.Element('access_control')
      misc.xa_set(e, 'control_type', self.control_type)
      self.doc.append(e)
      # FIXME Does need_digest apply to control access records? Maybe just to
      #       group_membership, which is revisioned. (This is what checkout
      #       does)
      need_digest = isinstance(self.req.revision.rev, revision.Diff)
      # Add the results from the SQL query to our XML document.
      self.control_handler.append_gml(e, need_digest)

   ##
   ## Protected Interface
   ##

   # This is a lookup for to see if control_type is a valid access control 
   # type. In the future, if this lookup proves useful elsewhere, move it.
   # NOTE In checkout, we use the item_factory to dynamically find and load
   #      the desired item module. Here, since we only have three or four
   #      control types to choose from, we'll keep it simple and use a list.
   valid_control_types = [
      'group',
      'group_item_access',
      'group_membership',
      # B1976 'group_policy',
      # FIXME 'group_revision', see: group_revision.Many.sql_context_user()
      'new_item_policy',
      ]

   # Along with the type of record, the client must specify the context of the
   # results.
   #
   # ==============================================|
   # | TYPE--> | GRP | MEM | GIA | GPO | REV | NIP |
   # | ======= | === | === | === | === | === | === |
   # | CONTEXT |     |     |     |     |     |     |
   # | ------- | --- | --- | --- | --- | --- | --- |
   # |  user   | x-a |  d  |  g  |  j  |  m  |  p  |
   # |  branch |  b  |  e  |  h  | x-k | x-n |  q  |
   # |  group  |  c  |  f  |  i  |  l  |  o  | x-r |
   # |  item   | x-1 |  2  |  3  |  4  |  5  | x-6 |
   # |==============================================
   #
   # Table key, where x- means a feature is not supported, and [is a gui tip]:
   #
   #   a = get user's private group? user cannot edit it; let's not confuser
   #   b = gets all groups in branch hierarchy; for basemap owners; [??]
   #   c = gets/sets group_; for group owners; (name, deleted, description)
   #   1 = groups don't have items (they have group-item-access; see below)
   #   d = gets groups to which user belongs; for current user; [??]
   #   e = gets all groups with branch access; for branch owners; [Access Tab]
   #   f = gets/sets 
   #    [Manage Groups]
   #   2 = 
   #   g = gets user's most permissive access to an item; for current user
   #   h = gets list of all groups with access to a branch; for branch owners
   #   i = gets/sets group's or groups' access level on item; for item owners
   #   3 = gets all records for a particular item; for pyserver
   #   j = B1976 group policy list for all groups of current user
   #   k = B1976 group policy applies to all branches; this doesn't make sense
   #   l = B1976 group policy list for a particular group
   #   4 = 
   #   m = revision list for all groups of current user; shown in hist browser
   #         see: group_revision.Many.sql_context_user()
   #   n = revision list for current branch? seems like something just for root
   #   o = revision list for just one group -- makes sense for hist brow filter
   #   5 = 
   #   p = policy list for groups of user; for current user; not shown to user
   #   q = policy list for branch; only for branch owners; [Policy Tab]
   #   r = policy list for just one group? no need for this info (just use (q))
   #   6 = policy list for just one item type? just use (q) and manually search
   #   x = not supported

# FIXME Control Panel tabs: Options, Aerial (maybe?), Tags Filter
#       (should also be able to access Aerial from map dropdown)

   valid_control_contexts = [
      'user',
      'branch',
      'group',
      'item',
      ]

   #
   def decode_request_control_request(self):
      '''
      Checks that control_type references a valid access control class type.
      Raises on error; returns silently on success.
      '''
      self.control_type = self.decode_key('control_type')
      if (not self.control_type in Op_Handler.valid_control_types):
         raise GWIS_Error('Invalid access control type: ' + self.control_type)
      self.control_context = self.decode_key('control_context')
      if (not self.control_context in Op_Handler.valid_control_contexts):
         raise GWIS_Error('Invalid access control context: ' 
                          + self.control_context)
      # FIXME Rather than us checking 'context', we should call
      #       control_type.Many and ask it if it supports 'context'

   control_modules = dict()

   #
   def get_access_control_module(self):
      '''Import and return control_type module from item.grac package. '''
      if (self.control_type not in Op_Handler.control_modules):
         module = __import__('item.grac',          # Package name
                             globals(), locals(),  # Python things
                             [self.control_type,], # Module name
                             -1)                   # level: use abs and rel
         Op_Handler.control_modules[self.control_type] \
            = getattr(module, self.control_type)
      return Op_Handler.control_modules[self.control_type]

   # ***

# ***

