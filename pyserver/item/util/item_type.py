# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('item_type')

# NOTE: Callers should "from item.util.item_type import Item_Type",
#       and callers should not import Item_Type_Lookup.

class Item_Type_Lookup(object):

   the_lookup = None

   ## Singleton method

   #
   @staticmethod
   def get_lookup():
      if (not Item_Type_Lookup.the_lookup):
         Item_Type_Lookup.the_lookup = Item_Type_Lookup()
      return Item_Type_Lookup.the_lookup

   ## Constructor

   # FIXME Bug nnnn -- Auto-load lookup tables

   def __init__(self):
      self.lookup_id_by_str = {}
      self.lookup_str_by_id = {}
      self.all_attachments_ = []
      self.all_geofeatures_ = []
      # SYNC_ME: Search: Item_Type table.
      self._lookup_add( 1, 'attachment')
      self._lookup_add( 2, 'geofeature')
      self._lookup_add( 3, 'link_value')
      self._lookup_add( 4, 'annotation')
      self._lookup_add( 5, 'attribute')
      self._lookup_add( 6, 'branch')
      self._lookup_add( 7, 'byway')
      self._lookup_add( 8, 'post')
      self._lookup_add( 9, 'region')
      self._lookup_add(10, 'route')
      self._lookup_add(11, 'tag')
      self._lookup_add(12, 'terrain')
      self._lookup_add(13, 'thread')
      self._lookup_add(14, 'waypoint')
      self._lookup_add(15, 'workhint')
      self._lookup_add(16, 'group_membership')
      self._lookup_add(17, 'new_item_policy')
      self._lookup_add(18, 'group')
      self._lookup_add(19, 'route_step')
      self._lookup_add(20, 'group_revision')
      self._lookup_add(21, 'track')
      self._lookup_add(22, 'track_point')
      self._lookup_add(23, 'addy_coordinate')
      self._lookup_add(24, 'addy_geocode')
      self._lookup_add(25, 'item_name')
      self._lookup_add(26, 'grac_error')
      self._lookup_add(27, 'work_item')
      self._lookup_add(28, 'nonwiki_item')
      self._lookup_add(29, 'merge_job')
      self._lookup_add(30, 'route_analysis_job')
      self._lookup_add(31, 'job_base')
      self._lookup_add(32, 'work_item_step')
      self._lookup_add(33, 'merge_job_download')
      self._lookup_add(34, 'group_item_access')
      # DEPRECATED: item_watcher (replaced by private link_attributes)
      #  self._lookup_add(35, 'item_watcher')
      #  self._lookup_add(36, 'item_watcher_change')
      self._lookup_add(37, 'item_event_alert')
      # DEPRECATED: byway_node (replaced by node_endpoint).
      #  self._lookup_add(38, 'byway_node')
      # DEPRECATED: route_waypoint (renamed to route_stop).
      #  self._lookup_add(39, 'route_waypoint')
      self._lookup_add(40, 'route_analysis_job_download')
      self._lookup_add(41, 'branch_conflict')
      self._lookup_add(42, 'merge_export_job')
      self._lookup_add(43, 'merge_import_job')
      self._lookup_add(44, 'node_endpoint')
      self._lookup_add(45, 'node_byway')
      self._lookup_add(46, 'node_traverse')
      self._lookup_add(47, 'route_stop')
      # 2013.04.04: For fetching basic item info (like access_style_id).
      # No?: self._lookup_add(48, 'item_stack')
      # No?: self._lookup_add(49, 'item_versioned')
      self._lookup_add(50, 'item_user_access')
      # No?: self._lookup_add(51, 'item_user_watching')
      # Reserve space for the new link_geofeature type though it's not used.
      self._lookup_add(52, 'link_geofeature')
      self._lookup_add(53, 'conflation_job')
      self._lookup_add(54, 'link_post')
      self._lookup_add(55, 'link_attribute')
      self._lookup_add(56, 'landmark')
      self._lookup_add(57, 'landmark_t')
      self._lookup_add(58, 'landmark_other')
      self._lookup_add(59, 'item_revisionless')

   #
   def _lookup_add(self, id, type_name):
      # Add to both lookups
      self.lookup_id_by_str[type_name] = int(id)
      self.lookup_str_by_id[id] = type_name
      # Also add to the object itself, as an uppercased version
      # (just like we do for constants, i.e., Item_Type.BYWAY)
      setattr(self, type_name.upper(), id)

   #
   def id_to_str(self, id):
      #log.debug('id_to_str: id: %s' % (id,))
      g.assurt(id in self.lookup_str_by_id)
      return self.lookup_str_by_id[id]

   #
   def is_id_valid(self, item_type_id):
      return (item_type_id in self.lookup_str_by_id)

   #
   def id_validate(self, item_type_id):
      id = int(item_type_id)
      g.assurt(id in self.lookup_str_by_id)
      return id

   #
   def str_to_id(self, type_name):
      return self.lookup_id_by_str[type_name]

   #
   def all_attachments(self):
      if not self.all_attachments_:
         self.all_attachments_.extend([
            self.ANNOTATION,
            self.ATTRIBUTE,
            self.POST,
            self.TAG,
            self.THREAD,
            ])
      return self.all_attachments_

   #
   def all_geofeatures(self):
      if not self.all_geofeatures_:
         self.all_geofeatures_.extend([
            #self.BRANCH,
            self.BYWAY,
            self.REGION,
            #self.ROUTE,
            self.TERRAIN,
            self.WAYPOINT,
            ])
      return self.all_geofeatures_

   #
   def item_type_id_get(self, item_type_name_or_id):
      try:
         item_type_id = int(item_type_name_or_id)
      except ValueError:
         try:
            g.assurt(isinstance(item_type_name_or_id, basestring))
            item_type_id = self.str_to_id(item_type_name_or_id)
         except KeyError:
            # This is a programmer's problem.
            g.assurt(False)
      return item_type_id

   # end: class Item_Type_Lookup

# Global singleton reference
Item_Type = Item_Type_Lookup.get_lookup()

