# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis.query_filters import Query_Filters
from item import item_base
from item import item_user_watching
from item.util.item_type import Item_Type

log = g.log.getLogger('nonwiki_item')

# A nonwiki_item is just a conceptual wrap around an item. The class acts as
# a sibling to the other item wrappers: geofeature, attachment, and link_value.
# A nonwiki_item lives independently of these other items. Obviously, a
# nonwiki_item has no geometry, so it's not a geofeature. It also isn't
# related to an geofeature -- you can't link it to a geofeature -- so it's not 
# an attachment. And obviously it's not a link_value. So it's its own thing.
# It's an item in the system that's managed like the other items -- group
# access control and all -- but it's not directly related to any map features.
# My guess is that most uses of this class will be to make branch-attachments,
# which is what work_items kind of are.

class One(item_user_watching.One):

   item_type_id = Item_Type.NONWIKI_ITEM
   item_type_table = None # There is no 'nonwiki_item' table; we're abstract.
   item_gwis_abbrev = None
   child_item_types = None

   item_save_order = 1

   __slots__ = ()

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_user_watching.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def verify_revision_id(self, rid):
      g.assurt(self.valid_start_rid == 1)

   # 
   def version_finalize_and_increment(self, qb, rid, same_version=False,
                                                     same_revision=False):
      # Skipping:
      #    item_user_watching.One.version_finalize_and_increment(self, qb, rid,
      #                                                          same_version)

      g.assurt((rid == 1) or (rid == qb.item_mgr.rid_new))
      # but we ignore rid, anyway...

      self.valid_start_rid = 1 # MAGIC_NUMBER: conf.rid_first?
      self.valid_until_rid = conf.rid_inf

      if not self.version:
         g.assurt(self.system_id is None)
      else:
         g.assurt(self.system_id)

      # Unlike item_versioned's version of this fcn., we can assume the
      # branch_id isn't set or stays the same, since nonwiki_item objects
      # only live in one branch.
      new_branch_id = self.save_core_get_branch_id(qb)
      g.assurt((not self.branch_id) or (new_branch_id == self.branch_id))
      self.branch_id = new_branch_id

      # MAYBE: The remaining code 
      #        is C.f. item_versioned.version_finalize_and_increment
      #        so maybe make a new fcn. for code in item_versioned that's
      #        special and override in this class to be a no-op...
      # Bump the vers.
      # COUPLING: acl_grouping is an item_user_access dealie.
      # Nonwiki items are either new (version 0) or existing (version 1).
      g.assurt(self.version in (0, 1,))
      # commit.py sets same_version=True when it sees not needs_new_revision:
      g.assurt(same_version)
      # NOTE: It is up to derived classes not to accidentally save a new 
      # row when version == 2 (see save_core()), since nonwiki items are always
      # version 1 but they may have a "steps" tables with timestamped thingies.
      self.version += 1
      #
      self.dirty_reason_add(item_base.One.dirty_reason_item_auto)
      #
      self.acl_grouping = 1

   #
   def save_core_shim(self, qb):
      if self.version == 1:
         self.save_core(qb)
      else:
         log.verbose1('Skipping save_core on saved nonwiki item: %s' % (self,))
         g.assurt(self.version == 2)

   #
   def save_core(self, qb):
      #item_user_watching.One.save_core(self, qb)
      #if self.version == 1:
      if self.fresh:
         g.assurt(self.version == 1)
         item_user_watching.One.save_core(self, qb)
      else:
         log.verbose1('Skipping super.save_core on saved nonwiki item: %s' 
                      % (self,))
         g.assurt(self.version in (1, 2,))
         # If deleted, mark deleted.
         if self.deleted:
            g.assurt(self.version == 2)
            # FIXME: del this. I think mark_deleted does exact the same.
            #set_deleted_sql = (
            #   """
            #   UPDATE item_versioned 
            #   SET deleted = TRUE
            #   WHERE system_id = %d
            #   """ % (self.system_id,))
            #rows = qb.db.sql(set_deleted_sql)
            #g.assurt(rows is None) # sql throws on error or returns None
            #set_deleted_sql = (
            #   """
            #   UPDATE group_item_access 
            #   SET deleted = TRUE
            #   WHERE item_id = %d
            #   """ % (self.system_id,))
            #rows = qb.db.sql(set_deleted_sql)
            #g.assurt(rows is None) # sql throws on error or returns None
            ## This is a little hokey usage of mark_deleted.
            #self.mark_deleted(qb.db)
            # This is a little hokey usage of mark_deleted_update_sql.
            self.mark_deleted_update_sql(qb.db)

   #
   def save_related_maybe(self, qb, rid):
      #if self.version == 1:
      if self.fresh:
         g.assurt(self.version == 1)
         item_user_watching.One.save_related_maybe(self, qb, rid)
      else:
         # Don't call the base class, which makes group_item_access records,
         # since we didn't actually create a new item version, so we don't need
         # new group item access records.
         # FIXME: Can you have item watchers on jobs? Maybe....... so this
         # avoids setting them after initial item creation. but you don't want
         # watchers in the hierarchy anyway: i'm kind of guessing that watchers
         # are really nonwiki items, too!
         log.verbose1('No save_relatd_mayb on alrdy svd nonwiki it: %s' 
                      % (self,))
         #g.assurt(self.version == 2)
         g.assurt(self.version in (1, 2,))

   #
   def save_update(self, qb):
      g.assurt(False) # Not impl. for nonwiki_item.
      item_user_watching.One.save_update(self, qb)
      self.save_insert(qb, One.item_type_table, One.psql_defns, 
                       do_update=True)

class Many(item_user_watching.Many):

   one_class = One

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      item_user_watching.Many.__init__(self)

   # ***

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      g.assurt(qb.viewport.include is None)
      return ''

   #
   def search_get_sql(self, qb):
      g.assurt(not qb.confirm_leafiness)
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1
      sql = item_user_watching.Many.search_get_sql(self, qb)
      qb.branch_hier_limit = branch_hier_limit
      return sql

