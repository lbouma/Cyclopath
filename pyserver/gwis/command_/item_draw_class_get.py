# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from gwis import command

log = g.log.getLogger('cmd.itm_drw_c_get')

class Op_Handler(command.Op_Handler):

   __slots__ = ()

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)

   # ***

   #
   def __str__(self):
      selfie = 'item_draw_class_get'
      return selfie

   # *** Public Interface

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      self.doc.append(self.config_load_dom())
      # NOTE This class cheats and doesn't use prepare_response

   #
   def config_load_dom(self):
      'Load the config info from the database and return it as a DOM node.'
      config = etree.Element('config')
      # BUG nnnn: Replace draw_class/draw_param_joined with
      # tiles_mapserver_zoom...
# BUG nnnn: Full conversion to skins
# FIXME: DEPRECATED: Nix this code once flashclient and android both use the skins data
#                    instead... which reminds me, talk to [ft] about using the skins...
# FIXME: DEPRECATED: flashclient should no longer use draw_param_joined.
      config.append(self.req.db.table_to_dom('draw_param_joined'))
      # FIXME del:
      # FIXME What about the other layers, silly! Incl. route?
      #sql = Op_Handler.sql_draw_class_layers_for_feat('byway')
      #config.append(self.req.db.table_to_dom('gfl_byway', sql))
      #sql = Op_Handler.sql_draw_class_layers_for_feat('waypoint')
      #config.append(self.req.db.table_to_dom('gfl_waypoint', sql))
      # NOTE We could skip recreating the sql and just grab the whole 
      #      table -- the only column we're ignoring is geometry_type.
      # FIXME: Mobile should specify feat list to get smaller packet.
# FIXME: DEPRECATED: flashclient should no longer use geofeature_layer.
      sql = Op_Handler.sql_draw_class_layers_for_feat()
# FIXME: DEPRECATED: flashclient should no longer use draw_class_owner, etc.
      config.append(self.req.db.table_to_dom('geofeature_layer', sql))
      # Add the skins config.
      # BUG nnnn: Flashclient should specify the mapserv_layer_name, 
      #           e.g., 'standard', 'classic', 'new coke'.
      config.append(self.req.db.table_to_dom('tiles_mapserver_zoom'))
      return config

   #
   @staticmethod
   def sql_draw_class_layers_for_feat(feat_type=None):
      where_clause = ""
      if (feat_type):
         where_clause = "WHERE gfl.feat_type = '%s'" % (feat_type,)
      sql = (
         """
         SELECT 
            gfl.id AS gfl_id, 
            gfl.feat_type, 
            gfl.layer_name, 
            gfl.draw_class_viewer, 
            gfl.draw_class_editor, 
            gfl.draw_class_arbiter,
            gfl.draw_class_owner,
            gfl.restrict_usage
         FROM 
            geofeature_layer AS gfl
         %s
         ORDER BY gfl.id
         """ % (where_clause,))
      return sql

