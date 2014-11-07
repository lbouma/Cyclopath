# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import attachment
from item import item_base
from item import item_versioned
from item.util.item_type import Item_Type
from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('annotation')

class One(attachment.One):

   item_type_id = Item_Type.ANNOTATION
   item_type_table = 'annotation'
   item_gwis_abbrev = 'anno'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('comments',            None,   True,  False,    str,     2),
      ]
   attr_defns = attachment.One.attr_defns + local_defns
   psql_defns = attachment.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      attachment.One.__init__(self, qb, row, req, copy_from)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      attachment.One.save_core(self, qb)
      # Save to the 'annotation' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # ***

class Many(attachment.Many):

   one_class = One

   __slots__ = ()

   sql_clauses_cols_all = attachment.Many.sql_clauses_cols_all.clone()

   # FIXME: Maybe call a fcn. instead, like opt/argparse? Or does that 
   #        just complicate things more?
   #sqlc_all.inner.select_list("annot.comments")
   sql_clauses_cols_all.inner.shared += (
      """
      , annot.comments
      """
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN annotation AS annot
         ON (gia.item_id = annot.system_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.comments
      """
      )

   # *** Constructor

   def __init__(self):
      attachment.Many.__init__(self)

   # *** Query Builder routines

# FIXME [aa] Only get gf's whose username = '' or = [current_user]
# FIXME [aa] Security leak -- private annotations being sent to client
#            2012.04.02: Is this really still true??
#    FIXME Send where feat_type != and append feat_type == region_watched
# FIXME [aa] Bug: Deleted and old version attachments being sent for no-diff
#            Is this a regression, or have annots always been fetches this way?
#            SELECT DISTINCT 
#                   lhs_stack_id AS id,
#                   version,
#                   comments
#            FROM annotation_geo AS ag
#            WHERE (ST_Intersects(ag.geometry, 
#                  ST_SetSRID('BOX(479932.800000 4978592.800000, 
#                                  482124.800000 4981408.800000)'::box2d, 
#                             26915)))

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):
      g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))
      where_clause = attachment.Many.sql_apply_query_filters(
                              self, qb, where_clause, conjunction)
      return where_clause

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      table_cols.insert(0, 'annot.comments')
      stop_words = ccp_stop_words.Addy_Stop_Words__Annotation
      return attachment.Many.sql_apply_query_filter_by_text(
                  self, qb, table_cols, stop_words, use_outer)

   # ***

# ***

