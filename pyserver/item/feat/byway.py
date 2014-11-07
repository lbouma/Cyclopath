# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import time

import conf
import g

from grax.access_level import Access_Level

from item import geofeature
from item import item_base
from item import item_revisionless
from item import item_stack
from item import item_versioned
from item import link_value
from item.feat import branch
from item.feat import node_endpoint
from item.feat import node_byway
from item.feat import node_traverse
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('byway')

# ***

class Geofeature_Layer(object):
   '''These are row IDs from the geofeature_layer table'''

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   # SYNC_ME: Search: Skin GFL IDs. All of these byway.Geofeature_Layer
   #          attributes should also be part of mapserver/skins/*.py.
   Unknown = 1
   Other = 2
   Local_Road = 11
   _4WD_Road = 12
   Bike_Trail = 14
   Sidewalk = 15
   Doubletrack = 16
   Singletrack = 17
   Byway_Alley = 18
   Major_Road = 21
   Major_Trail = 22
   Highway = 31
   Expressway = 41
   Expressway_Ramp = 42
   Railway = 43
   Private_Road = 44
   Other_Ramp = 51
   Parking_Lot = 52

   Z_DEFAULT = 134

   all_gfids = set([
      Unknown,
      Other,
      Byway_Alley,
      Local_Road,
      _4WD_Road,
      Bike_Trail,
      Sidewalk,
      Doubletrack,
      Singletrack,
      Major_Road,
      Major_Trail,
      Highway,
      Expressway,
      Expressway_Ramp,
      Railway,
      Private_Road,
      Other_Ramp,
      Parking_Lot,
      ])

   motorized_uncontrolled_gfids = set([
      #Unknown,
      #Other,
      #Byway_Alley,
      Local_Road,
      #_4WD_Road,
      ##Bike_Trail,
      ##Sidewalk,
      ##Doubletrack,
      ##Singletrack,
      Major_Road,
      ##Major_Trail,
      Highway,
      #Expressway,
      #Expressway_Ramp,
      #Railway,
      #Private_Road,
      Other_Ramp,
      Parking_Lot,
      ])

   non_motorized_gfids = set([
      Bike_Trail,
      # Exclude this?: Sidewalk,
      Doubletrack,
      Singletrack,
      Major_Trail,
      ])

   # This lookup is for non-motorized facilities that are good for routes
   # (that is, doubletrack and singletrack should not be preferred like
   # bike trails when looking for a route that favors lanes and trails).
   non_motorized_facils = set([
      Bike_Trail,
      Major_Trail,
      # Skipping: Sidewalk, Doubletrack, Singletrack,
      ])

   controlled_access_gfids = set([
      Expressway,
      # Not true: MnDOT uses the ramp layer on free-rights.
      # BUG nnnn: We should convert all fake xway ramps to Other Ramp
      #  For now, we might suggest starting/ending a route at the
      #   start of an expressway ramp? They're marked closed, anyway, right?
      #  Expressway_Ramp,
      Railway,
      Private_Road,
      ])

   controlled_access_tags = set([
      'prohibited',
      'closed',
      # 2014.04.06: 'impassable' has been missing, hasn't it!
      'impassable',
      # 2014.08.18: What about 'avoid'? a user asked about it... [lb] doesn't
      #             remember it ever being used...
      # 2014.04.06: These tags would be similar except they don't exist (yet?):
      #  'restricted',
      #  'private',
      #  'controlled',
      # 2014.08.18: Let the route finder handle this:
      #  'is_disconnected',
      ])

   # ***

   # 2014.03.17: For Shapefile import, we finally need a sane gfl lookup.

   # HINT: To help make this table, try:
   #  SELECT
   #     '''' || LOWER(layer_name) || ''': '
   #     || REPLACE(layer_name, ' ', '_') || ','
   #     FROM geofeature_layer WHERE feat_type = 'byway'
   #     ORDER BY feat_type, layer_name;

   gfid_lookup = {
      #'alley': Alley,
      'alley': Byway_Alley,
      #'bicycle path': Bicycle_Path,
      'bicycle path': Bike_Trail,
      'bike trail': Bike_Trail,
      'bicycle trail': Bike_Trail,
      'doubletrack': Doubletrack,
      'expressway': Expressway,
      'expressway ramp': Expressway_Ramp,
      'highway': Highway,
      'local road': Local_Road,
      'major road': Major_Road,
      'major trail': Major_Trail,
      'other': Other,
      'railway': Railway,
      'private road': Private_Road,
      'other ramp': Other_Ramp,
      'parking lot': Parking_Lot,
      'sidewalk': Sidewalk,
      'singletrack': Singletrack,
      'unknown': Unknown,
      }

# ***

class One(geofeature.One):

   item_type_id = Item_Type.BYWAY
   item_type_table = 'geofeature'
   item_gwis_abbrev = 'ft'
   child_item_types = None
   gfl_types = Geofeature_Layer

# BUG nnnn: Enforce min/max on z_level.
   z_level_min = 130
   z_level_max = 138
   z_level_med = 134

   attr_bike_facil_base = '/byway/cycle_facil'
   attr_bike_facil_metc = '/metc_bikeways/bike_facil'

# FIXME Either use aliases instead of long names,
#              or serialize this stuff so you don't waste chars, 
#              or send multiple byway response packets?
   local_defns = [
      # py/psql name,            deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('one_way',                None,   True,  False,    int,     1, 'onew'),
      # EXPLAIN: split_from_stack_id is not needed to be persisted? We just
      #          need it to clone the split-into byways and their link_values
      #          from the split-from byway, right? But, whatever, it's stored
      #          in the table nonetheless.
      ('split_from_stack_id',    None,   True,  False,    int,     0, 'splt'),
      # NOTE: We used to send geometry_len to the client, but none use it.
      # NOTE: The next three are generated values not stored in the database.
      ('geometry_len',           None,  False,   None,    int,  None, 'glen'),
      #('generic_rating',         None,   True,   None,    int,  None, 'grat'),
      ('generic_rating',         None,   True,   None,  float,  None, 'grat'),
      ('user_rating',            None,   True,   None,    int,  None, 'urat'),
      ('bsir_rating',            None,  False,   None,  float,  None, 'bsir'),
      ('cbf7_rating',            None,  False,   None,  float,  None, 'cbf7'),
      ('ccpx_rating',            None,  False,   None,  float,  None, 'ccpx'),
      # For the route finder's network graph.
      # MAYBE: Instead of extracting points from byway's geometry, should we 
      #        rather just get node_lhs_endpoint_xy node_endpoint?
      ('beg_point',              None,  False),
      # Beg2 is the second vertex from the start of the line.
      # It's used to determine the direction one might be traveling near the
      # end of the line, i.e., at an intersection.
      ('beg2_point',             None,  False),
      ('fin_point',              None,  False),
      # ... the second vertex from the end of the line.
      ('fin2_point',             None,  False),
      # For multimodal route finder
      # MAYBE: Revisit these two; I'm [lb] not convinced they operate correct.
      ('xcoord',                 None,  False),
      ('ycoord',                 None,  False),

      #
      ('beg_node_id',               0,   True,  False,    int,  None, 'nid1'),
      ('fin_node_id',               0,   True,  False,    int,  None, 'nid2'),
      # 
      # MAYBE: We don't always need the node details, but it's not a big deal 
      #        unless it degrades performance or memory usage... but I don't 
      #        think it does... and, anyway, we'd have to remove all __slots__
      #        to fix memory usage issues (whether or not an attribute is set, 
      #        using __slots__ always creates extra object overhead... but it 
      #        also make code more sane and less Old-West-like than not being
      #        clear about the object interface by using __slots__...).
      # See above; maybe replace start(2)_point.
      #('node_lhs_endpoint_xy',   None,  False,   None,    set,  None, 'nxy1'),
      # FIXME: Elevation seems like it could apply to other geofeature types.
      # FIXME: Elevation is being converted to int? should be float, I think.
      ('node_lhs_reference_n',   None,  False,   None,    int,  None, 'nrn1'),
      ('node_lhs_referencers',   None,  False,   None,    str,  None, 'nid1'),
      # MAYBE: Historically, elev is int... now float...
      ('node_lhs_elevation_m',   None,   True,   None,  float,  None, 'nel1'),
      ('node_lhs_dangle_okay',   None,  False,   None,   bool,  None, 'ndo1'),
      ('node_lhs_a_duex_rues',   None,  False,   None,   bool,  None, 'ndr1'),
      #
      #('node_rhs_endpoint_xy',   None,  False,   None,    set,  None, 'nxy2'),
      ('node_rhs_reference_n',   None,  False,   None,    int,  None, 'nrn2'),
      ('node_rhs_referencers',   None,  False,   None,    str,  None, 'nid2'),
      ('node_rhs_elevation_m',   None,   True,   None,  float,  None, 'nel2'),
      ('node_rhs_dangle_okay',   None,  False,   None,   bool,  None, 'ndo2'),
      ('node_rhs_a_duex_rues',   None,  False,   None,   bool,  None, 'ndr2'),
      # This is necessary for mapserver/tilecache_update.py
      ('bike_facility_or_caution', None, False,  None,    str,  None, 'bkfy'),
      ]
   attr_defns = geofeature.One.attr_defns + local_defns
   # NOTE: Using parent's private_defns, since we use their table.
   psql_defns = geofeature.One.private_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   cols_copy_nok = geofeature.One.cols_copy_nok + (
      [
       # NO: 'one_way' # The only member we copy
       'split_from_stack_id',
       'geometry_len',
       'generic_rating',
       'user_rating',
       'bsir_rating',
       'cbf7_rating',
       'ccpx_rating',
       'beg_point',
       'beg2_point',
       'fin_point',
       'fin2_point',
       'xcoord',
       'ycoord',
       'beg_node_id',
       'fin_node_id',
       'is_disconnected',
       'node_lhs_reference_n',
       'node_lhs_referencers',
       'node_lhs_elevation_m',
       'node_lhs_dangle_okay',
       'node_lhs_a_duex_rues',
       'node_rhs_reference_n',
       'node_rhs_referencers',
       'node_rhs_elevation_m',
       'node_rhs_dangle_okay',
       'node_rhs_a_duex_rues',
       'bike_facility_or_caution',
       ])

   __slots__ = [
      'byway_split_from',
      'splitting_in_progress',
      'newly_split_',
      # For import/export jobs.
      'rating_avg',
      'rating_cnt',
      # Used on commit.
      'ref_beg_node_id',
      'ref_fin_node_id',
      #
      #'bsir_rating',
      #'cbf7_rating',
      #'ccpx_rating',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      #self.geofeature_layer_id = Geofeature_Layer.Unknown
      geofeature.One.__init__(self, qb, row, req, copy_from)
      # generic_rating is fetched from the database rather than being
      # recalculated after fetch (which might be faster) in order to guarantee
      # that the ratings in the database are up-to-date.
      log.verbose1('new byway: %s' % (self,))
      #
      self.rating_avg = None
      self.rating_cnt = None
      #
      if self.fresh and self.split_from_stack_id:
         log.verbose('ctor: newly_split_: %s' % (self,))
         self.newly_split_ = True

   # *** Built-in Function definitions

   #
   def __str__(self):
      return (
         ('%s%s')
         % (geofeature.One.__str__(self),
            ' | newly_split' if self.newly_split() else '',
            ))

   # *** ...

   @staticmethod
   def ensure_instance(byway_or_id, qb):
      '''If b is an instance of byway.One, return it unchanged. If b is an int
         or long, fetch the latest version of the byway with that id and return
         it, or None if none exists with that ID. Otherwise, barf.'''
      if (isinstance(byway_or_id, One)):
         return byway_or_id
      elif (isinstance(byway_or_id, int) 
            or isinstance(byway_or_id, long)):
         stack_id = byway_or_id
         byway_many = Many()
         byway_many.search_by_stack_id(stack_id, qb)
         if (len(byway_many) == 0):
            # nothing in the database
            return None
         return byway_many[0]
      g.assurt(False)

   # *** GML/XML Processing

   #
   def append_gml_geometry(self, new):
      gml.append_LineString(new, self.geometry_svg)

   #
   def from_gml(self, qb, elem):
      # So, are we to assume if from_gml is called this is a fresh item that
      # hasn't been populated?
      # FIXME: Remove this code
      # Mikhil: According to the FIXME above, the code below (try-except) is
      # commented out. Uncomment if needed, but then deal with the assurt
      # firing.
      # 
      #try:
      #   getattr(self, 'split_from_stack_id')
      #   g.assurt(False)
      #except AttributeError:
      #   pass # expected
      #
      geofeature.One.from_gml(self, qb, elem)
      # FIXME: Bug 2508: Are these two lines bad?
      geom_wkt = gml.wkt_linestring_get(elem.text)
      # If the geometry deloved to a point (the xys are too close),
      # then geom_wkt is None.
      # BUG nnnn: 2014.09.17: [lb] edited S Lake Blvd NE at 117th La NE to
      # removed dangling connector and to connect bike path and two oneway
      # couplets to neighborhood street. The client sent a new 0-length byway
      # for S Lake Blvd NE. Looking at stack IDs in the client, it looks like
      # the create-intersection tool split one of the couplet segments into
      # two segments, even though the new segment is really just a point,
      # and both its endpoint share the same node stack ID as one of the
      # other, longer segment's endpoints.
      if geom_wkt is not None:
         self.set_geometry_wkt(geom_wkt)
         # FIXME: What's this talk about 6 decimal places of precision?
         # HACK: If a byway has all of vertices in the same location (to 6
         # decimal places of precision), it degenerates to a point. Such byways
         # are effectively deleted and cannot be saved due to IsValid(geometry)
         # constraint. gml.wkt_linestring_get returns None when the the
         # linestring is degenerate, therefore we explicitly set deleted to
         # True.
         # See Bug 1442.
         #
         # FIXME If this happens to a fresh byway, it's saved such that the
         #       only version is deleted, which seems wrong.
         if not self.geometry_wkt:
            # This is unexpected, though we might want to let clients
            # mark items deleted without needing them to send geometry.
            # Note that we'll return False, anyway, so commit will ignore
            # this item...
            g.assurt_soft(self.deleted)
      # See if this is a newly split byway.
# BUG nnnn: If client splits same byway many times, each should use same
#           split_from_stack_id.
# BUG nnnn: Split byway into four, then delete one segment.
      #attr_value = One.from_gml_required(elem, attr_name, required)
      if self.fresh and self.split_from_stack_id:
         log.debug('from_gml: newly_split_: %s' % (self,))
         self.newly_split_ = True
      return bool(self.geometry_wkt)

   #
   def newly_split(self):
      try:
         self.newly_split_
      except AttributeError:
         self.newly_split_ = False
      return self.newly_split_

   #
   def set_geometry_wkt(self, geometry_wkt, is_changed=None):
      # Call base class to set self.geometry_wkt.
      geofeature.One.set_geometry_wkt(self, geometry_wkt, is_changed)
      # Calculate the length, need when we recalculate the base rating.
      # MAYBE: Wait to calculate this value.... would need to profile 
      #        import/export, e.g., and see if it's really a bottleneck.
      # FIXME: 2012.09.27: Do we even need/use this value?
      self.geometry_len = gml.geomstr_length(geometry_wkt)

   # *** Saving to the Database

   # 
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      geofeature.One.validize(self, qb, is_new_item, dirty_reason, ref_item)
      # The base class makes sure geometry_changed is set to True or False.
      g.assurt(self.geometry_changed is not None)
      self.ref_beg_node_id = None
      self.ref_fin_node_id = None
      if is_new_item:
         # If not split-from, we'll get node_endpoints and update node_byway in
         # save_related_maybe. If split-from, we may already have set the 
         # nodes; zero or one may match one of ref_item's nodes, and one or two
         # may be different nodes.
         if ref_item is not None:
            self.byway_split_from = ref_item
      else:
         g.assurt(ref_item is not None)
         # Copy the ref_item's node_endpoint IDs so we know if they change.
         self.ref_beg_node_id = ref_item.beg_node_id
         self.ref_fin_node_id = ref_item.fin_node_id
         # save_or_update_node_endpoints does not expect node IDs.
         self.beg_node_id = None
         self.fin_node_id = None
      # Do we ever delete or revert an item previously deleted or reverted?
      g.assurt((ref_item is None)
               or ((not ref_item.deleted) and (not ref_item.reverted)))

   # This is used by commit.py to figure out what group_revisions to create.
   def group_ids_add_to(self, group_ids, rid):
      geofeature.One.group_ids_add_to(self, group_ids, rid)

   #
   def save_core(self, qb):
      geofeature.One.save_core(self, qb)

   #
   def mark_deleted_(self, qb, f_process_item_hydrated):
      geofeature.One.mark_deleted_(self, qb, f_process_item_hydrated)
      # Clean up node ids. Make sure reset_rows_for_byway gets called.
      if self.deleted:
         self.save_or_update_node_endpoints(qb)

   #
   def save_insert(self, qb, table, psql_defns, do_update=False):
      # HACK: We piggyback on the geofeature table. That is, the geofeature
      # class defines a bunch of attrs that only this class uses. So here we
      # cheat and replace the psql_defns if we're saving to the geofeature
      # table (which is conceptually the non-existant byway table).
      if table == geofeature.One.item_type_table:
         geofeature.One.save_insert(self, qb, table, One.psql_defns, do_update)
      else:
         # Otherwise, this is just the item_stack's or item_versioned's table
         # we're updating.
         g.assurt((table == item_revisionless.One.item_type_table)
                  or (table == item_versioned.One.item_type_table)
                  or (table == item_stack.One.item_type_table))
         geofeature.One.save_insert(self, qb, table, psql_defns, do_update)

   #
   def save_related_maybe(self, qb, rid):
      geofeature.One.save_related_maybe(self, qb, rid)

      # It's not *technically* time to make the rating -- we haven't made
      # link_values for attrs or tags yet -- but there's an explicit 
      # JOIN byway_rating in the Many sql_clauses below. So we have to make a
      # row.
      # BUG nnnn: Multiple rating algorithms. See some comments below, in the
      # sql_clauses (search: JOIN byway_rating AS brg). Make an
      # "algorithm_type" column in byway_rating that indicates how the value 
      # was calculated (e.g., "user", "generic", "metc_test"), and maybe supply
      # a default value if one is not available.
      # For now, just fake a generic rating. Commit or Import will fix this
      # later, once lvals are saved (and self.link_values is hydrated).
      # Haha, start out as unrideable, since we have no clue yet.
      self.generic_rating = 0.0
      self.bsir_rating = None
      self.cbf7_rating = None
      self.ccpx_rating = None
      #log.verbose('save_related_maybe: generic_rating_save: value: %s / %s'
      #            % (self.generic_rating, self,))
      self.generic_rating_save(qb.db)

      # FIXME: This means you can't load from db and save, because split from
      # is set......
      # if self.fresh and self.split_from_stack_id:
      if self.newly_split():
         g.assurt(self.version == 1)
         self.links_split_into(qb)
         self.ratings_split_into(qb)

      # FIXME: BUG nnnn: Update AADT table.

      # FIXME: BUG nnnn: Update Watchers, too!

# BUG_FALL_2013: Revision revert: revert_related_maybe...
      # FIXME: BUG nnnn: Do the reverse of these for reverts!

         # Skipping: route_step table.
         # NOTE: The caller -- either commit.py, or merge_job_import.py, or
         # whatever -- is responsible for dealing with the split-from byway
         # (marking it deleted, maybe after making a new copy in the branch);
         # same for the split-from link_values.
         # Don't reset newly_split_: After saving, this info is still valuable.
         # NO: self.newly_split_ = False
         del self.byway_split_from # Unlink our reference.
         # BUG nnnn: Missing Nonwiki Items, like watchers.

      # Update the node_* tables.
      self.save_or_update_node_endpoints(qb)

   # ***

   #
   def save_or_update_node_endpoints(self, qb):

      # Clone the qb.
      qb = qb.clone(skip_clauses=True, skip_filtport=True)

      # When called for new or edited byways, we're called after validize but
      # before the save, and validize resets the endpoint node IDs. But if we
      # are called after a delete -- which doesn't validize but just overwrites
      # the deleted columns in existing rows in the database -- the item will
      # not be marked valid and its node IDs should be set.
      if self.beg_node_id or self.fin_node_id:
         g.assurt(((not self.valid) and (self.deleted))
                  or (qb.cp_maint_lock_owner)) # Bulk import.
         self.ref_beg_node_id = self.beg_node_id
         self.ref_fin_node_id = self.fin_node_id
         self.beg_node_id = None
         self.fin_node_id = None
      else:
         g.assurt(self.valid and (not self.deleted))

      # Find (or create) the endpt nodes.
      (beg_node_endpoint, fin_node_endpoint,
         ) = node_endpoint.Many.node_endpoints_get(qb, self,
               self.ref_beg_node_id, self.ref_fin_node_id, skip_cache=False)

      #g.assurt(beg_node_endpoint is not None)
      #g.assurt(fin_node_endpoint is not None)
      g.assurt(beg_node_endpoint)
      g.assurt(fin_node_endpoint)
      # See Stack ID 1474850: A very unimaginably short line segment,
      # whose node IDs match because they're within a decimeter...
      #g.assurt(beg_node_endpoint.stack_id != fin_node_endpoint.stack_id)

      # We don't trust the client to tell us the node IDs, so they shouldn't be
      # set yet. (See also validize(), which resets these, so, e.g., you can
      # load an item from the database, but once you call validize(), the node
      # IDs need to be recomputed.)
      g.assurt((not self.beg_node_id) and (not self.fin_node_id))

      g.assurt(self.geometry_changed is not None)

      # If we're a new version of an existing item and our geometry hasn't
      # changed, we expect our node IDs to be the same, too.

      if self.ref_beg_node_id and self.ref_fin_node_id:
         if not self.geometry_changed:
            # 2012.07.29: If you are importing to a new branch and this fires,
            # see that you've called node_cache_maker on the new branch,
            # otherwise split-from byways being copied to the new branch will
            # be assigned new node IDs, since node_byway and node_endpoint are
            # branch-flattened -- so you have to populate the caches first.
            # FIXME: When you create a new branch using ccp.py, how do you make
            # sure node caches are populated? Do you leave it up to user, or
            # can you make a work item for it? For now, see the CcpV2 upgrade
            # script, upgrade_ccpv1-v2.sh, which first makes a new branch and
            # then second populates the node cache tables.
            #


# BUG_FALL_2013: BUG nnnn: Apply bike blvd in Hackensack fails on node endpt
# FIXME: I just selected 1st St in Hackensack and applied bike boulevard
#        and saved, and this fires.
#
#        > v beg_node_endpoint.stack_id
#         6421952L
#        > v self.ref_beg_node_id
#        4193003
#
#        And last stack ID is 6421953... so, why are new endpoints being
#        created? This assurt has every right to fire!
#
#        node_endpoint.Many.node_endpoints_get is broke!!!!!!!!
#
#        maybe try block-by-block to find the errant one,
#        or is the problem multiple blocks?
#
#        i'm guessing it's a rounding issue with the node x,y...
#
#        also, why is this fcn. being called when i didn't touch the geometry?
#        TEST: Make sure new byway version is not being created!
#

            # 2014.02.x: This happened on the server....
            g.assurt_soft(beg_node_endpoint.stack_id == self.ref_beg_node_id)
            g.assurt_soft(fin_node_endpoint.stack_id == self.ref_fin_node_id)
      else:
         g.assurt((not self.ref_beg_node_id) and (not self.ref_fin_node_id))

      # MAYBE: Is this okay: raw SQL here? Seems like the simplest approach...
      # 2013.08.14: Update the byway's row before updating the endpoints,
      #             otherwise the query the endpoint runs will not get
      #             the correct reference_n count.

      # BUG_JUL_2014/MEH: Should byway share responsibility keeping
      #                   is_disconnected up to date? [lb] no longer
      #                   thinks so: the route finder is the one that
      #                   builds the network graph, so let it manage
      #                   geofeature.is_disconnected.
      update_node_ids_sql = (
         """
         UPDATE
            %s
         SET
              beg_node_id = %d
            , fin_node_id = %d
         WHERE system_id = %d
         """ % (One.item_type_table,
                beg_node_endpoint.stack_id,
                fin_node_endpoint.stack_id,
                self.system_id,))
      qb.db.sql(update_node_ids_sql)

      log.verbose('save_or_update_node_endpoints: %s' % (self,))

      if self.geometry_changed or self.deleted or self.reverted:
         # Update the node_byway table.
         node_byway.Many.reset_rows_for_byway(
            qb, self,
            beg_node_endpoint.stack_id,
            fin_node_endpoint.stack_id)
         # Update the node_endpoint and node_endpt_xy tables.
         valid_start_rid = self.valid_start_rid
         if beg_node_endpoint.stack_id != self.ref_beg_node_id:
            g.assurt(beg_node_endpoint.stack_id != self.beg_node_id)
            beg_node_endpoint.save_new_connection(
               qb, self, valid_start_rid, old_node_id=self.ref_beg_node_id)
         if fin_node_endpoint.stack_id != self.ref_fin_node_id:
            g.assurt(fin_node_endpoint.stack_id != self.fin_node_id)
            fin_node_endpoint.save_new_connection(
               qb, self, valid_start_rid, old_node_id=self.ref_fin_node_id)

      # We've just saved the byway, but maybe with the wrong or empty node IDs,
      # so update the byway now.
      self.beg_node_id = beg_node_endpoint.stack_id
      self.fin_node_id = fin_node_endpoint.stack_id

      # bug nnnn: fixme: need to check if endpoint attrs changed and save those
      # BUG nnnn: Let users set elevation, dangle_okay, a_duex_rues, etc.

# BUG nnnn: Check beg_node_endpoint and fin_node_endpoint
#           If byway x,y differs from node x,y by more than 1 meter?, complain
#           otherwise, if differs > 0, fix one them (probably the byway? by
#           adding a new vertex either at beginning or end of line segment)

      # CHECK: Unset the ref nodes, right?
      del self.ref_beg_node_id
      del self.ref_fin_node_id

   # *** Client ID Resolution

   #
   def stack_id_correct(self, qb):
      # Translate our own stack ID.
      geofeature.One.stack_id_correct(self, qb)
      # The client should not send split-from IDs for temporary byways (e.g.,
      # if the user makes a new byway in the client and splits it, the client
      # should not send the original byway that got split).
      g.assurt((not self.split_from_stack_id) 
               or (self.split_from_stack_id > 0))
      # NOTE: Historically, this class managed the node_endpoints stack IDs.
      # I.e., here we used to call, 
      #   self.beg_node_id = qb.item_mgr.stack_id_translate(
      #                                qb, self.beg_node_id)
      #   self.fin_node_id = qb.item_mgr.stack_id_translate(
      #                                qb, self.fin_node_id)
      # but this is wrong: we don't want to trust the client's node IDs. Nodes 
      # are sacred, in the sense that each node ID is mapped to a specific
      # xy value, so we don't need the client to tell us the ID, but rather
      # we want to use the xy value to retrieve the correct node ID from the
      # database.

   # *** Rating routines


# BUG_FALL_2013: Bikeability bug: E.g., route from Two Harbors to Duluth.
# 2014.05.08: This is maybe fixed by the new route finder?
#
# FIXME: Bikeabiliest route from Two Harbors to Duluth
#        wrongfully takes MNTH 61. The line seg. w/ stack ID
#        3786178 is the less-traveled CSAH 61.
#        Where are the other ratings? no aadt????
#
# select * from byway_rating where byway_stack_id in ( 3786178 , 3831394)
#   and branch_id = 2500677 order by byway_stack_id, last_modified desc;
#
# select * from aadt where byway_stack_id in ( 3786178 , 3831394);
#
# PROBLEM is no aadt for less-traveled highway, so make that an
#         automatic aadt of something under the threshold!!!
#
#  bwy_stk_id | val |         last_modified         |   username   | branch_id 
# ------------+-----+-------------------------------+--------------+-----------
#     3786178 |   1 | 2013-12-07 13:44:56.137179-06 | _r_generic   |   2500677
#     3831394 |2.25 | 2013-12-07 13:44:56.137179-06 | _r_generic   |   2500677
#     3831394 |   0 | 2013-12-07 13:44:56.137179-06 | _rating_cbf7 |   2500677
#     3831394 |   3 | 2013-12-07 13:44:56.137179-06 | _rating_bsir |   2500677
#

   #
   def generic_rating_calc(self, qb):
      '''Return my generic rating based on my attributes and fetching my AADT
         from the database.

         If enough users have rated the block in question, return the mean of
         those ratings.

         For roads, the objective calculation has two paths. If enough
         attributes are available, then we use the Chicago Bicycle Federation
         Map Criteria 7 (see http://bikelib.org/roads/roadnet.htm) with a few
         heuristic tweaks; otherwise we use a simple heuristic based on the
         byway type. The CBF7 color ratings Not Recommended, Red, Yellow,
         Green are numericized as 0.0 (Unrideable), 1.0 (Poor), 2.0 (Fair),
         and 3.0 (Good) respectively, i.e., no roads are rated Excellent in
         the initial pass.

         FIXME: See also BLOS:

           http://www.bikelib.org/bike-planning/bicycle-level-of-service

         (Note that the CBF7 method was not chosen because it has been
         definitely shown to be more correct or effective than other methods,
         but because it seemed reasonable and the amount of work required to
         gather its input data was feasible.)

         For bike paths, we use a simple heuristic based on the segment
         length, on the reasoning that frequent intersections make for
         trickier riding.

         FIXME: This method has a heavy dependence on magic numbers from the
         database view gfl_byway.'''

      # The generic rating is either one of our three calculated values or it's
      # the average user rating.
      self.generic_rating = None
      self.bsir_rating = None
      self.cbf7_rating = None
      self.ccpx_rating = None

      # Expressways and expressway ramps: always lowest bikeability.
      # If the user checked 'prohibited' in their tag prefs, these edges will 
      # also always return the greatest cost in the cost fcn.
      if (self.geofeature_layer_id in (Geofeature_Layer.Expressway,
                                       # MnDOT uses ramps for free rights.
                                       #Geofeature_Layer.Expressway_Ramp,
                                       Geofeature_Layer.Railway,
                                       Geofeature_Layer.Private_Road,)):
         self.ccpx_rating = 0.0
      for controlled_tag in Geofeature_Layer.controlled_access_tags:
         if self.has_tag(controlled_tag):
            self.ccpx_rating = 0.0
            break

      if self.ccpx_rating is None:
         # Use average user rating if available.
         useravg = self.rating_useravg(qb.db)
         # But only if enough users have rated the item.
         if ((useravg is not None)
             and (self.rating_cnt >= conf.rating_ct_mean_threshold)):
            self.generic_rating = useravg

      # Bicycle paths.
      # BUG nnnn: This doesn't account for paths like the greenway, which have
      # on/off ramps that don't really influence its bikeability!
      if (self.geofeature_layer_id in (Geofeature_Layer.Bike_Trail,
                                       Geofeature_Layer.Major_Trail,)):
         reseg = self.resegmentize()
         if (reseg.geometry_len > 500):
            self.ccpx_rating = 4.0
         elif (reseg.geometry_len > 100):
            self.ccpx_rating = 3.5
         else:
            self.ccpx_rating = 2.5
      # Sidewalks.
      if (self.geofeature_layer_id == Geofeature_Layer.Sidewalk):
         reseg = self.resegmentize()
         if (reseg.geometry_len > 500):
            self.ccpx_rating = 3.0
         elif (reseg.geometry_len > 100):
            self.ccpx_rating = 2.5
         else:
            self.ccpx_rating = 1.5

      # Attribute Values

# BUG 2662: This fcn. should be called when attrs change, too! Currently, the
# generic rating is only recalculated when the byway is saved, but not when the
# attributes or tags are edited. [2012.05.03: commit actually does call this
# fcn. when an attribute is changed, but it wouldn't hurt to test and verify.]
# 2012.07.25: BUG 2662 is probably fixed now. 

      # When Commit or Import calls this fcns., the item's lvals are setup.
      # Meaning, we don't want to have to slow-load attrs and tags here.
      g.assurt(self.lvals_wired())
      # This also means the item_mgr loaded its cache... fyi...
      g.assurt(qb.item_mgr.loaded_cache)
      # And commit can call item_mgr and get just lightweight links, so:
      #  Not necessary: g.assurt(self.link_values is not None)

      #attr_one_way = self.attr_integer('/byway/one_way')
      #g.assurt(attr_one_way == self.one_way)

      # For new byways, and some existing byways, these attributes are not set,
      # so some or all of these values may be None.
      attr_speed_limit = self.attr_integer(
                           '/byway/speed_limit')
      attr_lane_count = self.attr_integer(
                           '/byway/lane_count')
      attr_outside_lane_width = self.attr_integer(
                           '/byway/outside_lane_width')
      attr_shoulder_width = self.attr_integer(
                           '/byway/shoulder_width')
      attr_bike_facil = self.attr_val(One.attr_bike_facil_base)
      if attr_bike_facil is None:
         attr_bike_facil = self.attr_val(One.attr_bike_facil_metc)

      log.verbose(
         '%s spd_lmt %s / ln_ct %s / out_ln_w %s / sh_w %s / bk_f %s'
         % ('generic_rating_calc:', attr_speed_limit, attr_lane_count,
            attr_outside_lane_width, attr_shoulder_width, attr_bike_facil,))

      # If no shoulder width given, guess.
      # MAGIC NUMBER: Checking for specific tags, hard-coded.
      if attr_shoulder_width is None:
         if ((self.has_tag('bikelane'))
             or (self.has_tag('bike lane'))
             or (attr_bike_facil == 'bike_lane')):
            attr_shoulder_width = 4
         else:
            attr_shoulder_width = 0

      # Main road rating logic -- calulate either CBF7 or simple heuristic,
      # then correct for shoulders and bike lanes.

# FIXME: Our aadt data is very out-of-date! From 2007, and attached to
# stack_ids, meaning, split byways and new byways are not aadt'd.
      # BUG 2660: When you split byways, you lose the aadt data.
      # BUG 2661: AADT data is stale (from 2007).
      (vol_aadt, vol_hcdt,) = self.aadt_fetch(qb.db)

      # The auto cutoff is, e.g., 2500 aadt and the heavy commercial is 300.
      if ((vol_aadt >= conf.vol_addt_high_volume_threshold)
          and (vol_hcdt >= conf.vol_addt_heavy_commercial_threshold)):
         high_volume = True
      else:
         high_volume = False

      # FIXME: [lb] thinks Highways should not be automatically rated so
      # low: what about in the countryside? This means dirt roads will be
      # better rated.
      # BUG nnnn: For Statewide, rating Highways so low seems silly.
      if self.geofeature_layer_id == Geofeature_Layer.Highway:
         naive_rating = 1.0 if high_volume else 2.0
      elif self.geofeature_layer_id == Geofeature_Layer.Major_Road:
         naive_rating = 2.0 if high_volume else 2.5
      elif self.geofeature_layer_id in (Geofeature_Layer.Unknown,
                                        Geofeature_Layer.Other,):
         naive_rating = 2.0 if high_volume else 3.0
      else:
         # FIXME: Includes double track and single track.
         naive_rating = 3.0

      guessed_lane_count = None
      if not attr_lane_count:
         if self.geofeature_layer_id == Geofeature_Layer.Highway:
            guessed_lane_count = 4 # Error on side of caution? Or just try 2?
         elif self.geofeature_layer_id == Geofeature_Layer.Major_Road:
            guessed_lane_count = 4 # Error on side of caution?  Or just try 2?
         elif self.geofeature_layer_id == Geofeature_Layer.Local_Road:
            guessed_lane_count = 2
         elif (self.geofeature_layer_id
               in Geofeature_Layer.controlled_access_gfids):
            guessed_lane_count = 4
         else:
            guessed_lane_count = 2
         attr_lane_count = guessed_lane_count
      elif self.one_way:
         # The algorithms use the total number of lanes, so guesssume
         # the other couplet's count.
         attr_lane_count *= 2

      # 2013.11.20: For Statewide, we don't have speed limit data...
      #             but that's not to say we can't guess.
      guessed_speed_limit = None
      if not attr_speed_limit:
         if self.geofeature_layer_id == Geofeature_Layer.Highway:
            if attr_lane_count <= 3:
               guessed_speed_limit = 55 # I.e., 55 mph
            else:
               guessed_speed_limit = 65 # I.e., 65 mph
            # 
         elif self.geofeature_layer_id == Geofeature_Layer.Major_Road:
            # Use 45 just to weight this road lower...
            guessed_speed_limit = 45 # I.e., 45 mph
         elif self.geofeature_layer_id == Geofeature_Layer.Local_Road:
            # This is probably just 30 but since we don't know, err on side of
            # lesser rating.
            guessed_speed_limit = 35 # I.e., 35 mph
         elif (self.geofeature_layer_id
               in Geofeature_Layer.controlled_access_gfids):
            guessed_speed_limit = 65 # I.e., 65 mph
         else:
            guessed_speed_limit = 25 # I.e., 25 mph
         attr_speed_limit = guessed_speed_limit

      # 2013.12.07: I [lb] got a horrible route from Two Harbors to Duluth
      # on the most Bikeable rating. Without AADT, the less traveled CSAH 61
      # is generic-rated 1, and MNTH 61 gets generic 2.25, CBF7 0, and BSIR 3!

# FIXME: Guess AADT: If not applied, assume half of threshold?

# FIXME/BUG nnnn: Byway Cluster Cache: Speed up from 1.3 days for State of MN
# to less by sub-dividing problem, like, make clusters of 1/4s of the state,
# and then cluster again to see if any edge clusters connect... and at the
# edges you'll have overlapping segments that we included in the previous
# operation, so you'd just combine the line segmens, no biggee.


      # If no valid lane width, guess 12 feet because it's the state design
      # standard. http://www.dot.state.mn.us/tecsup/rdm/, sec 4-3.01.01.
      # (Note: we did not bulk-load any lane widths.)
      guessed_outside_lane_width = None
      if not attr_outside_lane_width:
         guessed_outside_lane_width = 12
         attr_outside_lane_width = guessed_outside_lane_width

      # NOTE: Sometimes the aadt is stored as -1.
      if (vol_aadt <= 0) and (conf.aadt_guess_when_missing):
         # Hrmm... assume 1/2 of the threshold?
         vol_aadt = conf.vol_addt_high_volume_threshold / 2.0
      if (vol_hcdt <= 0) and (conf.aadt_guess_when_missing):
         vol_hcdt = conf.vol_addt_heavy_commercial_threshold / 2.0

      # Pump the Chicagoland Bicycle Federation Algorithm #7.
      if vol_aadt > 0:
         self.cbf7_rating = self.rating_calc_chicago_bf7(
            vol_aadt, attr_speed_limit, attr_lane_count,
            attr_outside_lane_width, attr_shoulder_width)
         # 2013.11.20: Try the Bicycle safety index rating.
         self.bsir_rating = self.rating_calc_bike_safety_idx(
            vol_aadt, attr_speed_limit, attr_lane_count,
            attr_outside_lane_width, attr_shoulder_width)

      if vol_aadt <= 0:
         # Not enough info for CBF7 -- use naive heuristic.
         chosen_rating = naive_rating
      else:
         # 2013.11.20: Use average of CBF7 and safety index rating? Hmm.
         # [lb] doesn't really dig CBF7 because highways get a zero rating!
         #chosen_rating = self.cbf7_rating
         chosen_rating = float(self.cbf7_rating + self.bsir_rating) / 2.0
         # Just look in the byway_rating table now...
         #if self.cbf7_rating != self.bsir_rating:
         #   logf = log.debug
         #else:
         #   logf = log.verbose
         #logf('%s: %s: %.2f (%.2f | naive: %.2f / cbf7: %.2f / bsir: %.2f)'
         #     % ('generic_rating_calc',
         #        self.stack_id, adjusted_rating, chosen_rating,
         #        naive_rating, self.cbf7_rating, self.bsir_rating,))
         # gen_r_c: 1112485: 2.25 (1.0 | naive: 1.0 / cbf7: 0.0 / bsir: 2.0)
         #  2-lane 50 mph highway w/ a bike lane and 4 foot shldr... so +1.25
         #  aadt is 14800. Chi rating is 0 b/c of the 45:5000:12:nr=0.0 calc.
         #  (0 chi + 2 bsir / 2 to avg.) + 0.75 nice shldr + 0.5 bike lane

# FIXME: Use attr_bike_facil and check
#  protect_ln, bike_lane, rdway_shrrws, bike_blvd, bk_rte_u_s, bkway_state
#  paved_trail, loose_trail

      if self.ccpx_rating is None:
         # Corrections for shoulders and bike lanes (slightly different than
         # CBF7). CBF7 says that shoulders over 7 feet upgrade all ratings to
         # Green, but I [rp] don't believe that.
         # FIXME Document Magic Tags
         adjusted_rating = chosen_rating
# FIXME: See also '/metc_bikeways/bike_facil' shldr_loval and shldr_hival...
# Also, the bsi_rating and chibf_rating already take the shoulder into
# account...
#         if (attr_shoulder_width >= 4):
#            #adjusted_rating += 1.5
#            adjusted_rating += 0.75
#         if (self.has_tag('bikelane')):
##            # Assume that bike lane implies shoulder >= 4.
#            adjusted_rating += 0.5
         # Correct for unpavedness.
         # FIXME: unpaved should not be a rating but should be a cost fcn. value:
         # i.e., unpaved streets take longer to bike, so increase cost.
         # FIXME: Bikeability: Some riders prefer unpaved!
# Argh, If you get a route from Two Harbors to Duluth, there are three
# parallel roads: a busy, split 65-mph highway, a lesser travelled highway,
# and the old, old dirt road.
# BUG nnnn: Demote unpaved but what about when people thumbs-up unpaved in the
# tag filters? Give them a +2 rather than a +1 to compensate for this?
         if (self.has_tag('unpaved')):
            adjusted_rating -= 1.0
         # Clamp at limits.
         rating = max(min(adjusted_rating, 4.0), 0.0)
         self.ccpx_rating = rating

      if self.generic_rating is None:
         self.generic_rating = self.ccpx_rating

   # ***

   # CBF7. This is the CBF7 table.
   #       Nesting: max speed, max ADT per lane, max lane width.
   nr =  0.0
   red = 1.0
   yel = 2.0
   gre = 3.0
   dt = {  0: {    0: {  0: gre, 12: gre, 13: gre, 14: gre }, 
                 500: {  0: gre, 12: gre, 13: gre, 14: gre }, 
                1250: {  0: yel, 12: gre, 13: gre, 14: gre }, 
                5000: {  0: red, 12: yel, 13: yel, 14: yel } },
          35: {    0: {  0: gre, 12: gre, 13: gre, 14: gre }, 
                 500: {  0: yel, 12: gre, 13: gre, 14: gre }, 
                1250: {  0: red, 12: yel, 13: yel, 14: yel }, 
                5000: {  0:  nr, 12: red, 13: red, 14: red } },
          45: {    0: {  0: yel, 12: gre, 13: gre, 14: gre }, 
                 500: {  0: red, 12: yel, 13: yel, 14: gre }, 
                1250: {  0:  nr, 12:  nr, 13: red, 14: yel }, 
                5000: {  0:  nr, 12:  nr, 13:  nr, 14: red } },
          55: {    0: {  0: yel, 12: gre, 13: gre, 14: gre }, 
                 500: {  0: red, 12: yel, 13: yel, 14: gre }, 
                # FIXME: [lb] This seems wrong. A zero rating means
                # highways will always be avoided, right? but in the
                # countryside, this is going to be very wrong, since
                # there may not be alternative streets.
                1250: {  0:  nr, 12:  nr, 13:  nr, 14: red }, 
                5000: {  0:  nr, 12:  nr, 13:  nr, 14:  nr } } }

   # helper function for rounding
   @staticmethod
   def cbf7_smush(x, iter):
      'Return x rounded down to the nearest item in iter.'
      for i in sorted(iter, reverse=True):
         if (i <= x):
            return i
      return None

   #
   def rating_calc_chicago_bf7(self, aadt, attr_speed_limit,
         attr_lane_count, attr_outside_lane_width, attr_shoulder_width):

      lanew = attr_outside_lane_width
      # modest shoulder is added to outside lane width
      if attr_shoulder_width < 4:
         lanew += attr_shoulder_width
      # calculate candidate rating
      rating = (
         One.dt[One.cbf7_smush(attr_speed_limit, One.dt.keys())] \
               [One.cbf7_smush(aadt / attr_lane_count, One.dt[0].keys())] \
               [One.cbf7_smush(lanew, One.dt[0][0].keys())])

      return rating

   # Bicycle Safety Index Rating
   #
   # http://ntl.bts.gov/DOCS/98072/appa/appa_01.html
   # same at:
   #  http://www.hsrc.unc.edu/research/pedbike/98072/appa/appa_01.html
   #
   # BSIR = AADT / (2500 * No. lanes)
   #        + Speed limit / 35
   #        + (14 - Outside lane width) / 2
   #        + PF + LF
   # except we don't use PF (pavement factor) or LF (location factor),
   # which account for e.g., potholes, or rough pavement, and grade,
   # parking facilities, driveways, etc. There's also an intersection
   # safety index rating that we don't use.
   #
   # Index Range | Classification | Description
   #
   #      0 to 4 |      Excellent | Denotes a roadway extremely favorable for
   #                              | safe bicycle operation.
   #      4 to 5 |           Good | Refers to roadway conditions still
   #                              | conducive to safe bicycle operation, but
   #                              | not quite as unrestricted as in the
   #                              | excellent case.
   #      5 to 6 |           Fair | Pertains to roadway conditions of marginal
   #                              | desirability for safe bicycle operation.
   #  6 or above |           Poor | Indicates roadway conditions of
   #                              | questionable desirability for bicycle
   #                              | operation. 
   #
   def rating_calc_bike_safety_idx(self, aadt, attr_speed_limit, 
         attr_lane_count, attr_outside_lane_width, attr_shoulder_width):

      #bsir = float(aadt) / float(2500 * attr_lane_count)
      # [lb] thinks 2500 is quite high.
      #bsir = float(aadt) / float(1250 * attr_lane_count)
      # and it's lane count multiplied...
      bsir = float(aadt) / float(625 * attr_lane_count)
      bsir += float(attr_speed_limit) / 35.0
      bsir += float(14 - attr_outside_lane_width) / 2.0

      # MAYBE: Why not return a float? Because user
      #        ratings are also whole numbers?

      if bsir < 4.0:
         rating = 4.0

      elif bsir < 5.0:
         rating = 3.0

      elif bsir < 6.0:
         rating = 2.0

      else:
         rating = 1.0

      return rating

   # ***

   #
   def generic_rating_save(self, db):
      # The byway rating gets saved only in the leaf branch
      # FIXME: 2011.08.26: Double-check this is right...
      # BUG nnnn: byway_rating: Add num_raters column.
      db.insert_clobber('byway_rating',
                        { 'username': conf.generic_rater_username,
                          'branch_id': self.branch_id,
                          'byway_stack_id': self.stack_id, },
                        { 'value': self.generic_rating, })
      #
      if self.bsir_rating is not None:
         db.insert_clobber('byway_rating',
                           { 'username': conf.bsir_rater_username,
                             'branch_id': self.branch_id,
                             'byway_stack_id': self.stack_id, },
                           { 'value': self.bsir_rating, })
      if self.cbf7_rating is not None:
         db.insert_clobber('byway_rating',
                           { 'username': conf.cbf7_rater_username,
                             'branch_id': self.branch_id,
                             'byway_stack_id': self.stack_id, },
                           { 'value': self.cbf7_rating, })
      if self.ccpx_rating is not None:
         db.insert_clobber('byway_rating',
                           { 'username': conf.ccpx_rater_username,
                             'branch_id': self.branch_id,
                             'byway_stack_id': self.stack_id, },
                           { 'value': self.ccpx_rating, })

   #
   @staticmethod
   def generic_rating_update(qb, byway_or_id, bulk_list=None):
      '''Update the generic rating of byway b in the database, if b exists.'''
      log.warning(': This fcn. is deprecated.')
      g.assurt(False) # Deprecate. FIXME: Delete this fcn.
      # NOTE: The generic rating is only saved to the base map branch's byway.
      # FIXME: I'm not sure that's right... the item was just saved, so it
      # should exist in the leafiest branch
      # MAYBE: This gets the byway in the context of qb, which is usually
      # anonymous. So this won't work on private byways... which don't exist.
      #
      # BUG nnnn: FIXME: PERFORMANCE: commit calls this one-by-one with stack
      # IDs. What does import do?
      bway = One.ensure_instance(byway_or_id, qb)
      if bway is None:
         log.warning('generic_rating_update: None?: %s' % (byway_or_id,))
         return
      bway.generic_rating_calc(qb)
      log.debug('generic_rating_update: generic_rating_save: value: %s / %s'
                % (bway.generic_rating, bway,))
      if bulk_list is not None:
         # i.e., "(branch_id, byway_stack_id, username, value)"
         insert_vals = ("(%d, %d, '%s', %s)" 
                        % (qb.branch_hier[0][0],
                           bway.stack_id,
                           conf.generic_rater_username,
                           # FIXME/MAYBE: Do we care about precision?
                           bway.generic_rating,))
         bulk_list.append(insert_vals)
         #
         if bway.bsir_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              bway.stack_id,
                              conf.bsir_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              bway.bsir_rating,))
            bulk_list.append(insert_vals)
         if bway.cbf7_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              bway.stack_id,
                              conf.cbf7_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              bway.cbf7_rating,))
            bulk_list.append(insert_vals)
         if bway.ccpx_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              bway.stack_id,
                              conf.ccpx_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              bway.ccpx_rating,))
            bulk_list.append(insert_vals)
      else:
         bway.generic_rating_save(qb.db)

   #
   def refresh_generic_rating(self, qb, bulk_list=None):
      self.generic_rating_calc(qb)
      if bulk_list is not None:
         # i.e., "(branch_id, byway_stack_id, username, value)"
         insert_vals = ("(%d, %d, '%s', %s)" 
                        % (qb.branch_hier[0][0],
                           self.stack_id,
                           conf.generic_rater_username,
                           # FIXME/MAYBE: Do we care about precision?
                           self.generic_rating,))
         bulk_list.append(insert_vals)
         #
         if self.bsir_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              self.stack_id,
                              conf.bsir_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              self.bsir_rating,))
            bulk_list.append(insert_vals)
         if self.cbf7_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              self.stack_id,
                              conf.cbf7_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              self.cbf7_rating,))
            bulk_list.append(insert_vals)
         if self.ccpx_rating is not None:
            insert_vals = ("(%d, %d, '%s', %s)" 
                           % (qb.branch_hier[0][0],
                              self.stack_id,
                              conf.ccpx_rater_username,
                              # FIXME/MAYBE: Do we care about precision?
                              self.ccpx_rating,))
            bulk_list.append(insert_vals)
      else:
         log.verbose(
            'refresh_generic_rating: generic_rating_save: val: %s / %s'
            % (self.generic_rating, self,))
         self.generic_rating_save(qb.db)

   #
   def ratings_split_into(self, qb):
      '''Copy ratings from the byway this was split from to this new byway.
         Copy only other users' ratings, as the saving user's ratings were
         copied by the flashclient.'''

      self_ex = ""
      if (qb.username != conf.anonymous_username):
         self_ex = "AND username != %s" % str(qb.db.quoted(qb.username))

      # MAGIC STRING: Special usernames start with underscore, hence !~ '^_'.
      # NOTE: Per branch_id, the split-from byway is guaranteed to exist in the
      # same branch as the newly split byways (since the split-from is copied
      # to the branch if it hasn't already been copied). But users' ratings
      # haven't been copied from the parent branch(es); just this user's
      # ratings are guaranteed to be set (since flashclient sent the ratings
      # with the byway). And since we've changed the stack_id, our route finder
      # won't be able to find users' ratings for split byways. So we have to 
      # FIXME: Assert that qb.revision is Current()?
      qb.db.sql(
         """
         INSERT INTO byway_rating
            (branch_id, byway_stack_id, value, username)
         SELECT 
            %d, %d, value, username
         FROM 
            byway_rating
         WHERE
            branch_id = %d
            AND byway_stack_id = %d
            %s
            AND username !~ '^_'
         """ % (self.branch_id,
                self.stack_id, 
                self.branch_id,
                self.split_from_stack_id, 
                self_ex,))

   #
   def rating_useravg(self, db, force_reload=False):
      if (self.rating_cnt is None) or force_reload:
         self.rating_avg, self.rating_cnt = self.rating_useravg_and_count(db)
      return self.rating_avg

   #
   def rating_usercnt(self, db, force_reload=False):
      if (self.rating_cnt is None) or force_reload:
         self.rating_avg, self.rating_cnt = self.rating_useravg_and_count(db)
      return self.rating_cnt

   #
   def rating_user_sql(self):
      rating_user_sql = (
         """
         SELECT username, value, last_modified
         FROM %s.byway_rating
         WHERE branch_id = %d
           AND byway_stack_id = %d
           AND username NOT IN ('%s')
         """ % (conf.instance_name,
                self.branch_id,
                self.stack_id,
                "','".join(conf.rater_usernames),))
      return rating_user_sql

   #
   def rating_useravg_and_count(self, db):

# BUG nnnn: This should be calculated en masse when getting byways -- it's
# really slow on export to do this once per byway...

      # BUG nnnn: Option to historic ratings (or maybe that's a separate field
      # in the export). (Search: sql_historic.)

      # NOTE: username !~ '^_' skips 'special' user accounts.
      rows = db.sql(
         """
         SELECT
            AVG(value) AS rating_avg
            , COUNT(*) AS rating_cnt
         FROM 
            byway_rating
         WHERE
            branch_id = %d
            AND byway_stack_id = %d
            AND value >= 0
            AND username !~ '^_'
         """ % (self.branch_id, 
                self.stack_id,))
      g.assurt(len(rows) == 1)
      rating_avg = rows[0]['rating_avg']
      rating_cnt = rows[0]['rating_cnt']
      g.assurt(((rating_avg is None) and (rating_cnt == 0))
               ^ ((rating_avg >= 0) and (rating_cnt > 0)))
      return rating_avg, rating_cnt

   # *** Support routines

   #
   def aadt_fetch(self, db):
      
      vol_aadt = None
      vol_hcdt = None

      if self.stack_id is None:
         log.warning('aadt_fetch: no stack_id?: %s' % (self,))
      else:
         vol_aadt = self.aadt_fetch_for_type(db, 'auto')
         vol_hcdt = self.aadt_fetch_for_type(db, 'heavy')

      return vol_aadt, vol_hcdt

   # aadt_type is 'heavy' or 'auto'.
   def aadt_fetch_for_type(self, db, aadt_type):
      aadt_sql = self.aadt_fetch_sql(aadt_type)
      result = db.sql(aadt_sql)
      if len(result) == 1:
         vol_aadt = result[0]['aadt']
      else:
         g.assurt(len(result) == 0)
         vol_aadt = None
      return vol_aadt

   # aadt_type is 'heavy' or 'auto'.
   def aadt_fetch_sql(self, aadt_type='', all_records=False):
      sql_aadt_type = ""
      if aadt_type:
         sql_aadt_type = "AND aadt_type = '%s'" % (aadt_type,)
      sql_distinct = ""
      if not all_records:
         sql_distinct = "DISTINCT ON (byway_stack_id)"
      aadt_fetch_sql = (
         """
         SELECT %s byway_stack_id, aadt_year, aadt_type, last_modified, aadt
         FROM aadt
         WHERE branch_id = %d
           AND byway_stack_id = %d
           %s
         GROUP BY byway_stack_id
                  , aadt_year
                  , aadt_type
                  , last_modified
                  , aadt
         ORDER BY byway_stack_id DESC
                  , aadt_year DESC
                  , aadt_type DESC
                  , last_modified DESC
         """ % (sql_distinct,
                self.branch_id,
                self.stack_id,
                sql_aadt_type,))
      return aadt_fetch_sql

   # *** Byway-splitting

   #
   def links_split_into(self, qb):

      split_from = self.byway_split_from

      log.verbose('links_split_into: 1. self: %s' % (self,))
      log.verbose('links_split_into: 1. split_from: %s' % (split_from,))
      try:
         log.verbose('links_split_into: 1. link_values: %s'
                     % (self.link_values,))
      except AttributeError, e:
         pass

      # Commit or Import got the split_from from the database already.
      g.assurt(split_from is not None)

      # MAYBE: We copy all split-from link_values to each split-into.
      #        This includes item watchers and post-links. So we might
      #        want to indicate, e.g., in the post, or in the next item
      #        watcher email, that the original byway was split/edited.

      g.assurt(split_from.stack_id == self.split_from_stack_id)

      # The callers may or may not have loaded heavyweight link_values.
      # We make sure to do a user-agnostic load of all of the link_values.
      # Don't care: g.assurt(split_from.link_values is not None)

      # Commit and Import usually do a bulk load of split-froms in the context
      # of the user, but we want a userless checkout of all links, so we can
      # copy, e.g., private links between users and item watchers.
      #
      # Note that this fcn. is called multiple times for the same split_from,
      # so we only load its link_values the first time we see it.
      try:
         # See if we've started processing this split-into group yet.
         g.assurt(split_from.splitting_in_progress)
         # If that didn't throw an AttributeError, all link_values were
         # previously loaded.
         try:
            g.assurt(split_from.lvals_inclusive)
         except AttributeError:
            g.assurt(False)
      except AttributeError:
         # Split-intos are processed in groups. This is the first split-into of
         # the group to be processed.
         split_from.splitting_in_progress = True
         # Out of curiousity, remember how many user link_values there are.
         if split_from.link_values is not None:
            orig_lval_cnt = len(split_from.link_values)
         else:
            orig_lval_cnt = 0
         # Now fetch all links for this item. The existing split_from's
         # link_values were fetched in user context, but we need all of
         # the link_values for the byway, so we can copy them all.
         split_from.load_all_link_values(qb)
         log.verbose(
            'links_split_into: overwrote %d user-lvals with %d userless: %s'
            % (orig_lval_cnt, len(split_from.link_values), split_from,))
         # We may have picked up link_values the user could not see.
         g.assurt(orig_lval_cnt <= len(split_from.link_values))
      # end: try/except to make sure split_from.link_values is loaded.
      g.assurt(split_from.link_values is not None)

      # It doesn't matter if self.attrs or self.tagged or self.link_values is
      # already set: we ignore them -- and reset them -- here. If a caller
      # sent new link_values for the new split-into byways, the caller has to
      # update the new split-into byways' link_values after calling this fcn.

      userless_qb = qb.get_userless_qb()
      userless_qb.filters.include_item_stack = True

      self.link_values_reset(qb)

      #for lhs_stack_id, linkv in self.link_values.iteritems():
      for linkv in split_from.link_values.itervalues():

         log.verbose('links_split_into: linkv.groups_access: %s / %s'
                     % (linkv.groups_access, str(self),))

         g.assurt(linkv.rhs_stack_id == self.split_from_stack_id)

         # For the first split_into, i.e., we just set splitting_in_progress,
         # we just called links.search_by_stack_id_rhs, so our links are not
         # fully hydrated yet.
         if linkv.groups_access is None:
            linkv.groups_access_load_from_db(qb)

         # FIXME: Should link_values have a split_from col, too, like byway/gf?

         new_link = link_value.One(qb=userless_qb, copy_from=linkv)
         g.assurt(not new_link.system_id)
         g.assurt(not new_link.stack_id)
         g.assurt(new_link.version == 0)
         g.assurt(not new_link.system_id)
         g.assurt(not new_link.branch_id)
         # copy_from set branch & None'ified system_id, valid_start/until_rid
         # WRONG: new_link.stack_id_set(qb.item_mgr.get_next_client_id())
         new_link.client_id = qb.item_mgr.get_next_client_id()
         new_link.stack_id = new_link.client_id
         # prepare_and_save_item will correct the stack ID.
         g.assurt(new_link.lhs_stack_id > 0)
         g.assurt(new_link.rhs_stack_id != self.stack_id)
         new_link.rhs_stack_id = self.stack_id
         #
         new_link.split_from_stack_id = linkv.stack_id

         g.assurt(userless_qb.grac_mgr is not None)

         log.verbose('links_split_into: new_link: %s' % (new_link,))
         log.verbose('links_split_into: ref_item (linkv): %s' % (linkv,))

         # Use this split-into byway's valid_start_rid for the link.

         new_link.prepare_and_save_item(
            userless_qb, 
            target_groups=None,
            rid_new=self.valid_start_rid,
            ref_item=linkv)

         # [lb] asks, should we make group_revision records for so-called
         # private, multiple_allowed link_values? E.g.,
         #  self.group_ids_add_to(commit?.rev_groups, qb.item_mgr.rid_new)

         # Add the new link to the link lookups.
         self.wire_lval(qb, new_link, heavywt=True)

         log.verbose('links_split_into: saved+wired: %s' % (new_link,))

      # NOTE: Not closing userless_qb.db because it's the same as the commit
      #       one we're using.

      self.lvals_wired_ = True
      self.lvals_inclusive_ = True

   # *** Linear referencing

   #
   def nearest_node_id(self):
      if self.st_line_locate_point < 0.5:
         nearest_node_id = self.beg_node_id
      else:
         nearest_node_id = self.fin_node_id
      return nearest_node_id

   # *** Resegmentization helpers

   #
   def resegmentize(self):
      # BUG nnnn: implement
      # find all neighbors that are same street (same name, same geof type,
      # similar attrs, etc.)
      reseg = self
      return reseg

   # *** Search feature helpers

   #
   @staticmethod
   def search_center_sql(geom=None, table_name=None):

      g.assurt((geom is not None) or (table_name is not None))

      if table_name:
         geom_col_or_text = '%s.geometry' % (table_name,)
      else:
         try:
            # Raw geom, e.g.: '010100002023690000AE47E1FA4E3B1D4184EB516056041'
            int(geom, 16) # Test that it's hex, else raise ValueError.
            geom_col_or_text = "'%s'" % (geom,)
         except ValueError:
            # It could be "text", SVG, WKT, or nothing...
            if geom.contains('('):
               if geom.startswith('SRID='):
                  geom_col_or_text = "ST_GeomFromEWKT('%s')" % (geom,)
               else:
                  geom_col_or_text = ("ST_GeomFromText('%s', %d)"
                                      % (geom, conf.default_srid,))
            else:
               # Assume SVG, e.g.: 'M 481562.06 4980048.25 L 481697 4980046'
               g.assurt(False) # Not supported

      as_center_sql = (
         """ CASE
               WHEN ST_NumPoints(%s) > 2 THEN
                  ST_AsText(ST_PointN(%s, ST_NumPoints(%s)/2 + 1))
               ELSE
                  ST_AsText(ST_Centroid(%s))
               END """ % (geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,))

      return as_center_sql

   # ***

   #
   def get_branch_bbox(self, qb):
      return Many.get_branch_bbox(qb, self.branch_id)

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      g.assurt(item.geometry_wkt)
      g.assurt(item.geometry_wkt.startswith('SRID='))

      try:
         insert_expr = (
            #"(%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s, '%s'::GEOMETRY)"
            "(%d, %d, %d, %d, %d, %d, %d, %s, %d, %d, %s, '%s'::GEOMETRY)"
            % (item.system_id,
               #? qb.branch_hier[0][0],
               # or:
               item.branch_id,
               item.stack_id,
               item.version,
               item.geofeature_layer_id or Geofeature_Layer.Unknown,
               #item.control_of_access,
               item.z or One.z_level_med,
               item.one_way or 0,
               item.split_from_stack_id or "NULL",
               item.beg_node_id or 0,
               item.fin_node_id or 0,
               "TRUE" if item.is_disconnected else "FALSE",
               #item.geometry,
               item.geometry_wkt,
               ))
      except Exception, e:
         log.error('as_insert_expression: missing param(s): %s' % (item,))
         raise

      return insert_expr

   #
   @staticmethod
   def add_insert_expressions_ratings_generic(qb, item, rat_rows, rat_sids):

      # See bulk_insert_ratings for the corresponding insert.

      insert_expr = (
         "(%d, %d, %s, %s)"
         % (#? qb.branch_hier[0][0], # or:
            item.branch_id,
            item.stack_id,
            qb.db.quoted(conf.generic_rater_username),
            item.generic_rating,
            #last_modified,
            ))
      rat_rows.append(insert_expr)

      try:
         insert_expr = (
            "(%d, %d, %s, %s)"
            % (#? qb.branch_hier[0][0], # or:
               item.branch_id,
               item.stack_id,
               qb.db.quoted(conf.bsir_rater_username),
               item.bsir_rating,
               #last_modified,
               ))
         rat_rows.append(insert_expr)
      except AttributeError, e:
         pass

      try:
         insert_expr = (
            "(%d, %d, %s, %s)"
            % (#? qb.branch_hier[0][0], # or:
               item.branch_id,
               item.stack_id,
               qb.db.quoted(conf.cbf7_rater_username),
               item.cbf7_rating,
               #last_modified,
               ))
         rat_rows.append(insert_expr)
      except AttributeError, e:
         pass

      try:
         insert_expr = (
            "(%d, %d, %s, %s)"
            % (#? qb.branch_hier[0][0], # or:
               item.branch_id,
               item.stack_id,
               qb.db.quoted(conf.ccpx_rater_username),
               item.ccpx_rating,
               #last_modified,
               ))
         rat_rows.append(insert_expr)
      except AttributeError, e:
         pass

      rat_sids.append(item.stack_id)

   #
   @staticmethod
   def as_insert_expression_volume_aadt(qb, item, aadt, aadt_year, aadt_type):

      g.assurt(False) # Not used.

      insert_expr = (
         "(%d, %d, %d, %d, '%s')"
         % (item.stack_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            aadt,
            aadt_year,
            aadt_type,
            #last_modified,
            ))

      return insert_expr

   # ***

# ***

class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   sql_clauses_cols_all = geofeature.Many.sql_clauses_cols_all.clone()

   # SPEED Should the length be cached in a table?
   # FIXME: Add exists_annotations and exists_posts to group_item_access?
   # FIXME: ST_Length, not Length?
   # FIXME: length2d(geometry) same as ST_Length(geometry)
   #        Is there a difference? Which one do ppl use by convention?
   #        (I [lb] like SQL fcns having common prefixes, since SQL fcns 
   #         are just names and don't have package qualifiers.)
   # FIXME: We don't always need to get all the node columns.
   sql_clauses_cols_all.inner.select += (
      """
      , gf.one_way
      , gf.beg_node_id
      , gf.fin_node_id
      , gf.is_disconnected
      , gf.split_from_stack_id
      """)

   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   sql_clauses_cols_all.inner.group_by += (
      """
      , gf.one_way
      , gf.beg_node_id
      , gf.fin_node_id
      , gf.is_disconnected
      , gf.split_from_stack_id
      """)

   # FIXME: Is this okay: JOIN byway_rating and not LEFT OUTER JOIN?
   #        Put something in auditor to check for missing byway_ratings.
   # BUG nnnn: Using other default ratings, other than the generic_rater's 
   #           generic rating in byway_rating.
   #           Note: Only the route-finder needs the generic rating, and maybe
   #                 import/export? We could build one or more joins here for 
   #                 the one or more rating algorithms. We either use a unique
   #                 system username for each, or we add a column to
   #                 byway_rating or make a table separate from the one used by
   #                 users and add a column to indicate what algorithm was
   #                 used... or maybe just use the byway_rating table but for
   #                 real users the algorithm is "user-alg" and for the system
   #                 algorithm we use, i.e., "/metc/alg-my_test_1"


# FIXME: What about "average" rating? We're just getting byway_rating's generic
#        rating, which isn't really that great! We really want average user
#        rating...
#        See: rating_useravg
#        oh, wait, we're supposed to update the rating if enough user's have
#        rated... but i doubt the code works... maybe we need a 'cache'-like
#        script to populate the rating...
#        oh, dur, we use CBF7 at first, and then we overwrite with the average
#          user rating, so the FIXME is really to make new attributes for CBF7
#          and average user rating and then the route finder picks the average
#          if it's set, otherwise it uses CBF7.


   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.one_way
      , group_item.beg_node_id
      , group_item.fin_node_id
      , group_item.is_disconnected
      , group_item.split_from_stack_id
      """)

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   # *** Query Builder routines

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      stop_words = ccp_stop_words.Addy_Stop_Words__Byway
      return geofeature.Many.sql_apply_query_filter_by_text(
                  self, qb, table_cols, stop_words, use_outer)

   # 
   def sql_outer_select_extra(self, qb):
      extra_select = geofeature.Many.sql_outer_select_extra(self, qb)
      if qb.sql_clauses.outer.enabled and qb.sql_clauses.outer.geometry_needed:
         extra_select += (
            """
            , Length(group_item.geometry) AS geometry_len
            """)
      return extra_select

   # NOTE: Sometimes, code calls search_get_sql directly, bypassing this fcn.
   #       But none of those callers care about byway ratings or node
   #       endpoints; those callers that do care will be sure to call this
   #       fcn., search_get_items.
   #
   def search_get_items(self, qb):

      # The node_cache_maker is called while a new branch is being created,
      # so the node endpoints aren't loaded.
      # MAYBE: Should we be more discriminating, or is loading node_endpoints
      #        only on a heavyweight load okay?
      self.update_clauses_rating_generic(qb)
      if qb.filters.rating_special:
         self.update_clauses_rating_special(qb)
      self.update_clauses_rating_real_user(qb)
      if not qb.filters.exclude_byway_elevations:
         self.update_clauses_node_endpoints(qb)

      # Perform the SQL query.
      geofeature.Many.search_get_items(self, qb)

   #
   def update_clauses_rating_generic(self, qb):

      qb.sql_clauses.inner.select += (
         """
         , brg.value AS generic_rating
         """)
      g.assurt(not qb.sql_clauses.inner.group_by_enable)
      qb.sql_clauses.inner.group_by += (
         """
         , brg.value
         """)
      # NOTE: byway_rating is populated for every byway for every branch.
      # BUG nnnn: How does this affect branch merge/update?
      qb.sql_clauses.inner.join += (
         """
         LEFT OUTER JOIN byway_rating AS brg
            ON (    (gia.stack_id = brg.byway_stack_id)
              --AND (gia.branch_id = brg.branch_id)
                AND (brg.branch_id = %d)
                AND (brg.username = %s))
         """ % (qb.branch_hier[0][0],
                qb.db.quoted(conf.generic_rater_username),))
      g.assurt(not qb.sql_clauses.inner.group_by_enable)
      qb.sql_clauses.outer.shared += (
         """
         , group_item.generic_rating
         """)

   #
   def update_clauses_rating_special(self, qb):

      qb.sql_clauses.inner.select += (
         """
         , bsir_brg.value AS bsir_rating
         , cbf7_brg.value AS cbf7_rating
         , ccpx_brg.value AS ccpx_rating
         """)
      g.assurt(not qb.sql_clauses.inner.group_by_enable)
      qb.sql_clauses.inner.group_by += (
         """
         , bsir_brg.value
         , cbf7_brg.value
         , ccpx_brg.value
         """)
      qb.sql_clauses.inner.join += (
         """
         LEFT OUTER JOIN byway_rating AS bsir_brg
            ON (    (gia.stack_id = bsir_brg.byway_stack_id)
              --AND (gia.branch_id = bsir_brg.branch_id)
                AND (bsir_brg.branch_id = %d)
                AND (bsir_brg.username = %s))
         LEFT OUTER JOIN byway_rating AS cbf7_brg
            ON (    (gia.stack_id = cbf7_brg.byway_stack_id)
              --AND (gia.branch_id = cbf7_brg.branch_id)
                AND (cbf7_brg.branch_id = %d)
                AND (cbf7_brg.username = %s))
         LEFT OUTER JOIN byway_rating AS ccpx_brg
            ON (    (gia.stack_id = ccpx_brg.byway_stack_id)
              --AND (gia.branch_id = ccpx_brg.branch_id)
                AND (ccpx_brg.branch_id = %d)
                AND (ccpx_brg.username = %s))
         """ % (qb.branch_hier[0][0],
                qb.db.quoted(conf.bsir_rater_username),
                qb.branch_hier[0][0],
                qb.db.quoted(conf.cbf7_rater_username),
                qb.branch_hier[0][0],
                qb.db.quoted(conf.ccpx_rater_username),))
      g.assurt(not qb.sql_clauses.inner.group_by_enable)
      qb.sql_clauses.outer.shared += (
         """
         , group_item.bsir_rating
         , group_item.cbf7_rating
         , group_item.ccpx_rating
         """)

   #
   def update_clauses_rating_real_user(self, qb):

      # If the user is logged in, grab their byway ratings. This is used by
      # flashclient to show the user's ratings and to let the user edit them.
      if (qb.username and (qb.username != conf.anonymous_username)):
         qb.sql_clauses.inner.select += (
            """
            , bgr_user.value AS user_rating
            """)
         g.assurt(not qb.sql_clauses.inner.group_by_enable)
         qb.sql_clauses.inner.group_by += (
            """
            , bgr_user.value
            """)

         # NOTE: rating_restrict is just for flashclient and does not affect
         # route finder.
         g.assurt(not qb.filters.rating_restrict) # Not used?
         # Not using branch_ids.
         # branch_ids = ','.join([str(x[0]) for x in qb.branch_hier])
         qb.sql_clauses.inner.join += (
            """
            LEFT OUTER JOIN byway_rating AS bgr_user
               ON (    (gia.stack_id = bgr_user.byway_stack_id)
                 --AND (gia.branch_id = bgr_user.branch_id)
                   AND (bgr_user.branch_id = %d)
                   AND (bgr_user.username = %s))
            """ % (qb.branch_hier[0][0],
                   qb.db.quoted(qb.username),))
         g.assurt(not qb.sql_clauses.inner.group_by_enable)
         qb.sql_clauses.outer.shared += (
            """
            , group_item.user_rating
            """)

   #
   def update_clauses_node_endpoints(self, qb):

      qb.sql_clauses.inner.select += (
         """
         --
         , lne.reference_n AS node_lhs_reference_n
         --, lne.referencers AS node_lhs_referencers
         , lne.elevation_m AS node_lhs_elevation_m
         , lne.a_duex_rues AS node_lhs_dangle_okay
         , lne.dangle_okay AS node_lhs_a_duex_rues
         --
         , rne.reference_n AS node_rhs_reference_n
         --, rne.referencers AS node_rhs_referencers
         , rne.elevation_m AS node_rhs_elevation_m
         , rne.a_duex_rues AS node_rhs_dangle_okay
         , rne.dangle_okay AS node_rhs_a_duex_rues
         """)
      g.assurt(not qb.sql_clauses.inner.group_by_enable)
      qb.sql_clauses.inner.group_by += (
         """
         --
         , lne.reference_n
         --, lne.referencers
         , lne.dangle_okay
         , lne.a_duex_rues
         , lne.elevation_m
         --
         , rne.reference_n
         --, rne.referencers
         , rne.dangle_okay
         , rne.a_duex_rues
         , rne.elevation_m
         """)

      #
      qb.sql_clauses.inner.join += (
         """
         LEFT OUTER JOIN node_endpoint AS lne
            ON ((lne.stack_id = gf.beg_node_id)
                AND (lne.branch_id = %d))
         LEFT OUTER JOIN item_versioned AS lne_iv
            ON ((lne.system_id = lne_iv.system_id)
                AND %s)
         --
         LEFT OUTER JOIN node_endpoint AS rne
            ON ((rne.stack_id = gf.fin_node_id)
                AND (rne.branch_id = %d))
         LEFT OUTER JOIN item_versioned AS rne_iv
            ON ((rne.system_id = rne_iv.system_id)
                AND %s)
         """ % (# Not using: qb.branch_hier_where('lne_iv'),
                qb.branch_hier[0][0],
                qb.revision.as_sql_where('lne_iv'),
                qb.branch_hier[0][0],
                qb.revision.as_sql_where('rne_iv'),
                ))
      # BUG nnnn/MAYBE: When we make a new branch, we make a node_endpoint for
      # every node in the parent branch and clone it to the new branch. But
      # since node_endpoint is revisioned, and (as of 2013.08.15) since the SQL
      # here is fixed to use as_sql_where, do we still need to make
      # branchy node_endpoint entries for all byways in the parent? It seems
      # like we could treat node_endpoints as stackable, too. But, whatever:
      # if managing node_endpoint is extra work, so be it; at least things
      # work.

      g.assurt(not qb.sql_clauses.inner.group_by_enable)

      qb.sql_clauses.outer.shared += (
         """
         --
         , group_item.node_lhs_reference_n
         --, group_item.node_lhs_referencers
         , group_item.node_lhs_elevation_m
         , group_item.node_lhs_dangle_okay
         , group_item.node_lhs_a_duex_rues
         --
         , group_item.node_rhs_reference_n
         --, group_item.node_rhs_referencers
         , group_item.node_rhs_elevation_m
         , group_item.node_rhs_dangle_okay
         , group_item.node_rhs_a_duex_rues
         """)

   # Used by some calls to item_mgr.load_feats_and_attcs.
   # See also: search_for_items, which just calls search_get_items.
   # So we're just adding the node endpoint geometry.
   def search_by_network(self, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      # FIXME: Test joining against links and one_way attribute to 
      #        get one_ways? Or just keep the one_way column in geofeature?
      #attrs = attribute.Many()
      #attrs.search_by_internal_name('/byway/one_way', qb_links)
      g.assurt(not qb.sql_clauses)
      self.sql_clauses_cols_setup(qb)
      # NOTE: Not using node_endpoint or node_byway or node_endpt_xy
      #       because we need the line string to calculate PointN.
      qb.sql_clauses.outer.select += (
         """
         , ST_AsText(ST_StartPoint(group_item.geometry))      AS beg_point
         , ST_AsText(ST_EndPoint  (group_item.geometry))      AS fin_point
         , ST_AsText(ST_PointN    (group_item.geometry, 2))   AS beg2_point
         , ST_AsText(ST_PointN    (group_item.geometry, 
                        NumPoints (group_item.geometry) - 1)) AS fin2_point
         """)
      #qb.sql_clauses.inner.join += (
      #   """
      #   LEFT OUTER JOIN link_value AS link
      #      ON (gia.stack_id = link.rhs_stack_id)
      #   LEFT OUTER JOIN item_versioned AS link_iv
      #      ON (link.system_id = link_iv.system_id)
      #   LEFT OUTER JOIN attribute AS attr
      #      ON (link.lhs_stack_id = attr.stack_id)
      #   """)
      #sqlc.inner.where += (
      #   """
      #   AND link_iv.valid_start_rid < gia.valid_until_rid
      #   AND gia.valid_start_rid < link_iv.valid_until_rid
      #   """)
      self.search_get_items(qb)

   #
   @staticmethod
   def get_branch_bbox(qb, branch_sid):

      if isinstance(qb.revision, revision.Updated):
         g.assurt(qb.filters.stack_id_table_ref)
      else:
         g.assurt((isinstance(qb.revision, revision.Current))
                  or (isinstance(qb.revision, revision.Historic)))

      g.assurt(not qb.sql_clauses)
      qb.sql_clauses = Many.sql_clauses_cols_all.clone()
      sql_byways = Many().search_get_sql(qb)

      qb.sql_clauses = None
      sql_extent = (
         """
         SELECT
              ST_XMin(ST_Extent(geometry)) AS xmin
            , ST_YMin(ST_Extent(geometry)) AS ymin
            , ST_XMax(ST_Extent(geometry)) AS xmax
            , ST_YMax(ST_Extent(geometry)) AS ymax
         FROM (%s) AS foo_bwy_1
         """ % (sql_byways,))
      time_0 = time.time()
      rows = qb.db.sql(sql_extent)
      misc.time_complain('get_branch_bbox', time_0, 2.0)
      if rows:
         g.assurt(len(rows) == 1)
         xmin = rows[0]['xmin']
         ymin = rows[0]['ymin']
         xmax = rows[0]['xmax']
         ymax = rows[0]['ymax']
         if xmin is None:
            log.warning('get_branch_bbox: nothing found?: rev: %s'
                        % (str(qb.revision,)))
            g.assurt((xmin is None) and (ymin is None)
                     and (xmax is None) and (ymax is None))
         else:
            g.assurt((xmin is not None) and (ymin is not None)
                     and (xmax is not None) and (ymax is not None))
      else:
         g.assurt(False) # SQL always returns one row.
      return (xmin, ymin, xmax, ymax,)

   # ***

   #
   @staticmethod
   def branch_coverage_area_update(db, branch_, rid):

      # An example of recalculating coverage_area using ccp.py:
      #    from grax.item_manager import Item_Manager
      #    from item.feat import branch
      #    from item.feat import byway
      #    from item.util import revision
      #    rev = revision.Historic(rid=19169)
      #    branch_hier = branch.Many.branch_hier_build(
      #       self.qb.db, branch_id=2421567, mainline_rev=rev)
      #    byway.Many.branch_coverage_area_update(self.qb.db, rid, branch_hier)
      #    self.qb.db.transaction_commit()

      username = '' # Using gia_userless, so not really needed.
      rev = revision.Historic(rid)
      branch_hier = branch.Many.branch_hier_build(db, branch_.stack_id, rev)
      userless_qb = Item_Query_Builder(db, username, branch_hier, rev)
      userless_qb.request_is_local = True
      userless_qb.request_is_script = True
      userless_qb.filters.gia_userless = True
      # Skipping: Query_Overlord.finalize_query(userless_qb)
      # Skipping: userless_qb.finalize()

      g.assurt(not userless_qb.sql_clauses)
      # MEH: branch.Many.sql_clauses joins on ratings and node_endpoints, which
      #      we don't need, but there doesn't seem to be a performance hit.
      #  userless_qb.sql_clauses = geofeature.Many.sql_clauses_cols_all.clone()
      userless_qb.sql_clauses = Many.sql_clauses_cols_all.clone()

      sql_byways = Many().search_get_sql(userless_qb)

      userless_qb.sql_clauses = None

      sql_hull = (
         """
         UPDATE branch SET coverage_area = (
            SELECT ST_ConvexHull(ST_Collect(geometry)) AS coverage_area
               FROM (%s) AS foo_bwy_2)
         WHERE
            system_id = %d
         """ % (sql_byways,
                branch_.system_id,))

      time_0 = time.time()

      rows = userless_qb.db.sql(sql_hull)
      g.assurt(not rows)

      # MAYBE: If this is slow move to Mr. Do! bg process or put in
      # tilecache_update or check_cache_now or gen_tilecache_cfg.
      misc.time_complain('branch_coverage_area_update', time_0, 2.0)

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, by_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if by_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               , geofeature_layer_id
               --, control_of_access
               , z
               , one_way
               , split_from_stack_id
               , beg_node_id
               , fin_node_id
               , is_disconnected
               , geometry
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(by_rows_to_insert),))

         qb.db.sql(insert_sql)

   #
   @staticmethod
   def bulk_delete_ratings_generic(qb, brat_sids_to_delete):

      if brat_sids_to_delete:

         delete_sql = (
            """
            DELETE FROM %s.byway_rating
            WHERE (byway_stack_id IN (%s))
              AND (branch_id = %d)
              AND (username IN (%s, %s, %s, %s))
            """ % (conf.instance_name,
                   ','.join([str(x) for x in brat_sids_to_delete]),
                   qb.branch_hier[0][0],
                   qb.db.quoted(conf.generic_rater_username),
                   qb.db.quoted(conf.bsir_rater_username),
                   qb.db.quoted(conf.cbf7_rater_username),
                   qb.db.quoted(conf.ccpx_rater_username),
                   ))

         qb.db.sql(delete_sql)

   #
   @staticmethod
   def bulk_insert_ratings(qb, brat_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)

      # Skipping table: byway_rating_event

      if brat_rows_to_insert:

         # Skipping column: last_modified
         insert_sql = (
            """
            INSERT INTO %s.byway_rating (
               branch_id
               , byway_stack_id
               , username
               , value
               --, last_modified
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   ','.join(brat_rows_to_insert),))

         qb.db.sql(insert_sql)

   #
   @staticmethod
   def bulk_insert_volume_aadt(qb, aadt_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner)

      insert_sql = (
         """
         INSERT INTO %s.aadt (
            branch_id
            , byway_stack_id
            , aadt
            , aadt_year
            , aadt_type
            --, last_modified
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(aadt_rows_to_insert),))

      qb.db.sql(insert_sql)

   # ***

# ***

if (__name__ == '__main__'):
   pass

