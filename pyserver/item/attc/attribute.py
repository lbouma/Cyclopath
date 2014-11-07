# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item import attachment
from item import item_base
from item import item_versioned
#from item.util import revision
from item.util.item_type import Item_Type

log = g.log.getLogger('attribute')

class One(attachment.One):

   item_type_id = Item_Type.ATTRIBUTE
   item_type_table = 'attribute'
   item_gwis_abbrev = 'attr'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('value_internal_name', None,   True,  False,    str,  None),
      ('spf_field_name',      None,   True,  False,    str,     0),
      ('value_type',          None,   True,  False,    str,     0),
      ('value_hints',         None,   True,  False,    str,     0),
      ('value_units',         None,   True,  False,    str,     0),
      ('value_minimum',       None,   True,  False,    int,     0),
      ('value_maximum',       None,   True,  False,    int,     0),
      ('value_stepsize',      None,   True,  False,    int,     0),
      ('gui_sortrank',        None,   True,  False,    int,     0),
      ('applies_to_type_id',  None,   True,  False,    int,     0),
      ('uses_custom_control', None,   True,  False,   None,  None),
      ('value_restraints',    None,   True,  False,    str,     0),
      ('multiple_allowed',    None,   True,  False,   bool,     0),
      # BUG nnnn: Add value_callback (custom callback fcn. to calculate
      # attribute link_value).
      # BUG nnnn: Add value_cache_me and make a geofeature_linked cache
      # table that has geofeatures and important attribute link_values.
      ]
   attr_defns = attachment.One.attr_defns + local_defns
   psql_defns = attachment.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      attachment.One.__init__(self, qb, row, req, copy_from)

   # *** Built-in Function definitions

   #
   def __str__(self):
      return ('"%s" [%s]'
              % (self.friendly_name(),
                 self.__str_deets__(),))

   #
   def friendly_name(self):
      try:
         fname = self.value_internal_name
      except AttributeError:
         try:
            fname = self.name
         except AttributeError:
            fname = 'Unnamed'
      return fname

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      attachment.One.from_gml(self, qb, elem)
      # The user is allowed to create a branch that was last merged before
      # Current(), because that's how we roll.
      # FIXME: Validate value_type in xxx
      if self.fresh and (not self.value_type):
         # C.f. item_base.One.from_gml_required
         raise GWIS_Error('Missing mandatory attr: "value_type".')
      elif (self.value_type is not None) and (not self.fresh):
         # C.f. item_base.One.from_gml_required
         raise GWIS_Error('Cannot set "value_type" except on create.')

   # *** Saving to the Database

   #
   def save(self, qb, rid):
      attachment.One.save(self, qb, rid)
      # Tell item_mgr we've changed. This might mean we're a new version of 
      # an existing item, so the old version is in the lookup, or this might
      # mean we're a new item altogether that doesn't exist in the lookups.
      if qb.item_mgr.loaded_cache:
         g.assurt(qb.item_mgr.cache_attrs is not None)
         qb.item_mgr.cache_attrs[self.stack_id] = self
         qb.item_mgr.cache_attrnames[self.value_internal_name] = self
         qb.item_mgr.attr_and_tag_ids.add(self.stack_id)
      else:
         # 2012.08.14: Remove this warning, maybe; [lb] doesn't think this is
         # an error but he's curious if/when this path happens.
         log.warning(
            'What code path is this? Save but not item_mgr.loaded_cache.')

   #
   def save_core(self, qb):
      attachment.One.save_core(self, qb)
      # Save to the 'attribute' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # ***

# ***

class Many(attachment.Many):

   one_class = One

   __slots__ = ()

   sql_clauses_cols_all = attachment.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.shared += (
      """
      , attr.value_internal_name
      , attr.spf_field_name
      , attr.value_type
      , attr.value_hints
      , attr.value_units
      , attr.value_minimum
      , attr.value_maximum
      , attr.value_stepsize
      , attr.gui_sortrank
      , attr.applies_to_type_id
      , attr.uses_custom_control
      , attr.value_restraints
      , attr.multiple_allowed
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN attribute AS attr
         ON (gia.item_id = attr.system_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.value_internal_name
      , group_item.spf_field_name
      , group_item.value_type
      , group_item.value_hints
      , group_item.value_units
      , group_item.value_minimum
      , group_item.value_maximum
      , group_item.value_stepsize
      , group_item.gui_sortrank
      , group_item.applies_to_type_id
      , group_item.uses_custom_control
      , group_item.value_restraints
      , group_item.multiple_allowed
      """
      )

   # *** Constructor

   def __init__(self):
      attachment.Many.__init__(self)

   # *** Query Builder routines

   #
   def search_by_internal_name(self, internal_name, *args, **kwargs):
      '''
      Searches for the item specified by stack_id at the specified revision.
      Appends the item, if found, to the Many instance (which derives from 
      list).
      '''
      qb = self.query_builderer(*args, **kwargs)
      self.sql_clauses_cols_setup(qb)
      qb.sql_clauses.inner.where += (
         " AND attr.value_internal_name = '%s' " % (internal_name,))
      self.search_get_items(qb)

   #def search_for_items(self, *args, **kwargs):
   #   # This can only be fetched as Current or as the new part of a Diff
   #   # FIXME Do we care that this crashes for malformed GML requests?
   #   #if (isinstance(rev, revision.Diff)):
   #   #   g.assurt(rev.group == 'new')
   #   #else:
   #   #   log.debug('type(rev)', type(rev))
   #   #   g.assurt(isinstance(rev, revision.Current))
   #   # FIXME Should viewport always be null? Should we always do this?
   #   viewport = None
   #   # FIXME Do we need to do something list this?:
   #   ## For Diff (new), a hack to include deleted attributes (so client knows
   #   ## they were deleted)
   #   #if (isinstance(req.revision, revision.Diff)):
   #   #   # The SQL so far doesn't consider revision IDs, so we need to filter
   #   #   # rows based on revision IDs of the three joins -- geofeature, 
   #   #   # link_value, and attachment
   #   #   where += (
   #   #      """
   #   #      OR (gia.deleted 
   #   #          AND gia.valid_start_rid > %d 
   #   #          AND gia.valid_start_rid <= %d)
   #   #      """ % (rev.rid_old, 
   #   #             rev.rid_new))
   #   attachment.Many.search_for_items(self, *args, **kwargs)

   # ***

   #
   def sql_where_filter_linked(self, qb, join_on_to_self,
                                         where_on_other,
                                         join_on_temp=""):

      linked_items_where = attachment.Many.sql_where_filter_linked(
         qb, join_on_to_self, where_on_other, join_on_temp)

      qb.sql_clauses.inner.join += (
         """
         JOIN attribute AS attr
            ON (flv.lhs_stack_id = attr.stack_id)
         """)

      return linked_items_where

   #
   def sql_where_filter_linked_join_on_to_self(self, qb):
      join_on_to_self = "attr.stack_id = flv.lhs_stack_id"
      return join_on_to_self

   # ***

   #
   @staticmethod
   def get_system_attr(qb, internal_name):
      the_attr = None
      attrs = Many()
      attrs.search_by_internal_name(internal_name, qb)
      if (len(attrs) == 1):
         log.debug('get_sys_attr: %s' % (attrs[0].friendly_name(),))
         log.debug('              %s' % (attrs[0].__str_deets__(),))
         #log.debug('get_system_attr: found attribute: %s' % (attrs[0].name,))
         the_attr = attrs[0]
         g.assurt(Item_Type.ATTRIBUTE == the_attr.item_type_id)
      else:
         g.assurt(len(attrs) == 0)
         # It is expected that callers can handle the attribute not existing.
      return the_attr

   # ***

# ***

