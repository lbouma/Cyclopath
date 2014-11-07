# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import traceback

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_style import Access_Style
from item import item_base
from item import item_versioned
from item.util.item_type import Item_Type
from util_ import misc

# MAYBE: Use __all__over.
__all__ = ['One', 'Many',]

log = g.log.getLogger('grac_record')

# This class is similar to item_user_access. item_user_access gaits requests
# for attachments, geofeatures, and link_values. This class gaits requests for
# group access control items.
# NOTE Each of the map item classes (attc, geof, link) derive from 
#      item_user_watching, which in turn derives from item_user_access. The
#      group access control classes do not derive from item_user_watching, at
#      least for now.  But that's not to say they can't, because someday we
#      might want user's to track changes to a group's membership or changes
#      to a branch's new_item_policy. But deriving from item_user_watching
#      might still be overkill: it might make more sense to fetch this info.
#      separately, on-demand, when the user is on an appropriate details panel
#      (that is, when the user is on the panel that shows the "Watch this item"
#      checkbox -- see the Update_Supplemental class in flashclient).

class One(item_versioned.One):

   item_type_id = None # Abstract
   item_type_table = None
   item_gwis_abbrev = None
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ]
   # MAYBE: The group tables duplicate rows from item_versiond 
   #        (deleted, reverted, name, valid_start_rid and valid_until_rid; see
   #        item_versioned.One.private_defns). We could (if we wanted) delete
   #        these columns and just join on item_versioned instead, like the
   #        normal item classes do.
   attr_defns = item_versioned.One.attr_defns + local_defns
   # NOTE: The group tables include the a few columns from item_versioned that
   #       the item tables do not include.
   psql_defns = (item_versioned.One.psql_defns + local_defns
                 + item_versioned.One.local_defns)
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      'acl_grouping',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      item_versioned.One.__init__(self, qb, row, req, copy_from)

   # *** Saving to the Database

   #
   def finalize_last_version_at_revision(self, qb, rid, same_version):

      item_versioned.One.finalize_last_version_at_revision(
         self, qb, rid, same_version)

      # 2013.10.16: Add check on branch_id since items that are checked out
      #             reflect branch_hier[0][0] and not the actual branch.
      qb.db.sql(
         """
         UPDATE %s SET valid_until_rid = %s
         WHERE (item_id = %s) AND (branch_id = %d)
         """ % (self.item_type_table, rid,
                self.system_id, qb.branch_hier[0][0],))

   #
   def get_access_infer(self, qb):
      # The group records don't use item_stack.access_infer_id.
      return Access_Infer.not_determined

   #
   def save_core(self, qb):
      # Avoid not-null constraints in item_stack by setting unused attrs.
      self.access_infer_id = Access_Infer.not_determined
      item_versioned.One.save_core(self, qb)

   #
   def save_update(self, qb):
      g.assurt(False) # Not impl. for grac_record.

   # 
   def version_finalize_and_increment(self, qb, rid, same_version=False,
                                                     same_revision=False):

      self.acl_grouping = 1

      item_versioned.One.version_finalize_and_increment(self, qb, rid, 
                                                        same_version,
                                                        same_revision)

   # ***

# ***

class Many(item_versioned.Many):

   context_types = ('branch', 'group', 'item', 'user',)

   one_class = One

   # *** SQL snippets

   sql_shared_basic_iv_raw = (
      """
        %s.system_id
      , %s.branch_id
      , %s.stack_id
      , %s.version
      , %s.deleted
      , %s.reverted
      , %s.name
      """)
   sql_shared_basic_iv_pfx_cnt = sql_shared_basic_iv_raw.count('%s')

   # 
   @staticmethod
   def sql_shared_basic_iv(tbl):
      return (
            Many.sql_shared_basic_iv_raw 
              % tuple([tbl] * Many.sql_shared_basic_iv_pfx_cnt))

   # *** Constructor

   def __init__(self):
      item_versioned.Many.__init__(self)

   # *** Query Builder routines

   #
   def search_by_context(self, context, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      # All of the parameters are required
      g.assurt(context 
             and qb.db and qb.username and qb.branch_hier and qb.revision)
      # Thunk to the actual function
      sql = self.search_get_sql_grac(qb, context)
      # Get the results from the database and hydrate them.
      self.sql_search(qb, sql)

   #
   def search_get_sql_grac(self, qb, context):
      # Get the SQL based on the context
      # Make the fcn name and use getattr to call the string as a function
      fcn = 'sql_context_' + context
      log.verbose2('search_get_sql_grac calling fcn %s' % (fcn,))
      try:
         qb.use_filters_and_viewport = True
         qb.use_limit_and_offset = True
         sql = getattr(self, fcn)(qb)
      except Exception, e:
         # This callee verified context is correct, so this shouldn't happen 
         # unless the code is wrong
         log.warning('search_get_sql_grac failed: "%s" / %s' 
                     % (str(e), traceback.format_exc(),))
         # NOTE: We're here if one of the abstract fcns. below fires its
         # asserts, since not all grac types implement each of the context
         # fcns.
         g.assurt(False)
      return sql

   # *** Abstract methods

   #
   def sql_context_branch(self, qb, *args, **kwargs):
      g.assurt(False) # Abstract

   #
   def sql_context_group(self, qb, *args, **kwargs):
      g.assurt(False) # Abstract

   #
   def sql_context_item(self, qb, *args, **kwargs):
      g.assurt(False) # Abstract

   #
   def sql_context_user(self, qb, *args, **kwargs):
      g.assurt(False) # Abstract

   # ***

# ***

