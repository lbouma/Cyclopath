# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item.attc import attribute
from item.link import link_uses_attr
from item.util.item_type import Item_Type

log = g.log.getLogger('link_attribute')

class One(link_uses_attr.One):

   #item_type_id = Item_Type.LINK_ATTRIBUTE
   #item_type_table = 'link_attribute'
   #item_gwis_abbrev = 'la'
   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      link_uses_attr.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      g.assurt(False) # Invalid request.
      link_uses_attr.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      g.assurt(False) # Invalid request.
      link_uses_attr.One.save_core(self, qb)

   # ***

# ***

class Many(link_uses_attr.Many):

   one_class = One

   # ***

   sql_clauses_cols_all = link_uses_attr.Many.sql_clauses_cols_all.clone()

   #sql_clauses_cols_all.inner.shared += (
   #   """
   #   , link.value_boolean
   #   , link.value_integer
   #   , link.value_real
   #   , link.value_text
   #   , link.value_binary
   #   , link.value_date
   #   """)

   #sql_clauses_cols_all.outer.shared += (
   #   """
   #   , group_item.value_boolean
   #   , group_item.value_integer
   #   , group_item.value_real
   #   , group_item.value_text
   #   , group_item.value_binary
   #   , group_item.value_date
   #   """)

   # *** Constructor

   __slots__ = (
      'internal_name',
      )

   def __init__(self, internal_name=None, feat_type=None):
      # FIXME: What about feat_type? Is it always None, a/k/a, any gf type?
      link_uses_attr.Many.__init__(self, Item_Type.ATTRIBUTE, feat_type)
      self.internal_name = internal_name
      # FIXME: Unlike link_tag, caller has to explicitly init class
      #        (attribute_load) to get the lhs_stack_id.

   #
   def attribute_load(self, qb):
      g.assurt(self.internal_name)
      link_uses_attr.Many.attribute_load(self, qb, self.internal_name)

   #
   def search_by_stack_id_rhs(self, rhs_stack_id, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      self.attribute_load(qb)
      link_uses_attr.Many.search_by_stack_id_both(
         self, self.attr_stack_id, rhs_stack_id, *args, **kwargs)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not where_clause) and (not conjunction)) # Topmost impl.
      g.assurt((not conjunction) or (conjunction == "AND"))

      where_ands = []

      if qb.filters.filter_by_value_boolean is not None:
         where_ands.append("(link.value_boolean IS %s)"
            % ("TRUE" if qb.filters.filter_by_value_boolean else "FALSE",))
      if qb.filters.filter_by_value_integer is not None:
         where_ands.append("(link.value_integer = %d)"
                           % (qb.filters.filter_by_value_integer,))
      # FIXME: Finish implementing what's commented out here:
      # if qb.filters.filter_by_value_real is not None:
      #    # FIXME: This probably won't work unless we truncate decimal places
      #    #        to some amount of precision. Can you easily compare two
      #    #        reals to within some toleration of one another?
      #    where_ands.append("(link.value_real = %s)"
      #                      % (qb.filters.filter_by_value_real,))
      if qb.filters.filter_by_value_text:
         where_ands.append("(link.value_text = %s)"
                           % (qb.db.quoted(qb.filters.filter_by_value_text),))
      # if qb.filters.filter_by_value_binary is not None:
      #    where_ands.append("(link.value_binary = %s)"
      #                      % (qb.filters.filter_by_value_binary,))
      # if qb.filters.filter_by_value_date is not None:
      #    where_ands.append("(link.value_date = %s)"
      #                      % (qb.filters.filter_by_value_date,))

      addit_where = " AND ".join(where_ands)
      if addit_where:
         where_clause = "%s %s" % (conjunction, addit_where,)
         conjunction = "AND"
      else:
         conjunction = ""

      return link_uses_attr.Many.sql_apply_query_filters(
                           self, qb, where_clause, conjunction)

   # ***

   #
   def link_multiple_allowed_sql(self, qb, rhs_stack_id):

      self.attribute_load(qb)

      g.assurt(self.the_attr.multiple_allowed)

      all_attribute_lvals_sql = (
         """
         SELECT
              gia.group_id
            , gia.item_id
            , gia.branch_id
            , gia.stack_id
            , gia.version
            , gia.acl_grouping
            --, gia.deleted
            --, gia.reverted
            --, gia.session_id
            , gia.access_level_id
            --, gia.name
            --, gia.valid_start_rid
            --, gia.valid_until_rid
            , gia.item_type_id
            , gia.link_lhs_type_id
            , gia.link_rhs_type_id
            --
            --, ik.stack_id
            --, ik.stealth_secret
            , ik.cloned_from_id
            , ik.access_style_id
            , ik.access_infer_id
            --
            --, iv.branch_id
            --, iv.system_id
            --, iv.stack_id
            --, iv.version
            --, iv.deleted
            --, iv.reverted
            --, iv.name
            --, iv.valid_start_rid
            --, iv.valid_until_rid
            --
            , ir.edited_date
            , ir.edited_user
            , ir.edited_addr
            , ir.edited_host
            , ir.edited_note
            , ir.edited_what
            --
            --, lv.branch_id
            --, lv.system_id
            --, lv.stack_id
            --, lv.version
            , lv.lhs_stack_id
            , lv.rhs_stack_id
            , lv.direction_id
            , lv.value_boolean
            , lv.value_integer
            , lv.value_real
            , lv.value_text
            , lv.value_binary
            , lv.value_date
            , lv.line_evt_mval_a
            , lv.line_evt_mval_b
            , lv.line_evt_dir_id
            , lv.split_from_stack_id
         FROM group_item_access AS gia
         --LEFT OUTER JOIN item_versioned AS iv
         --   ON (gia.item_id = iv.system_id)
         JOIN link_value AS lv
            ON (gia.item_id = lv.system_id)
         LEFT OUTER JOIN item_stack AS ik
            ON (gia.stack_id = ik.stack_id)
         LEFT OUTER JOIN item_revisionless AS ir
            ON (gia.item_id = ir.system_id
                AND gia.acl_grouping = ir.acl_grouping)
         WHERE lv.lhs_stack_id = %d
           AND lv.rhs_stack_id = %d
           AND gia.branch_id = %d
           AND gia.valid_until_rid = %d
           AND NOT gia.deleted
         """ % (
                #self.attr_stack_id,
                self.the_attr.stack_id,
                rhs_stack_id,
                #self.the_attr.branch_id,
                qb.branch_hier[0][0],
                conf.rid_inf,
                ))

      return all_attribute_lvals_sql

   # ***

# ***

