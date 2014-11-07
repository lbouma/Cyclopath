# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import datetime
import os
import sys

import conf
import g

from item import geofeature
from item import item_base
from item import item_helper
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc

log = g.log.getLogger('track_point')

# ***

class One(item_helper.One):
   '''One point along a track. Note that unlike other geofeatures, this
      doesn't have an ID.'''

   item_type = Item_Type.TRACK_POINT
   item_type_table = 'track_point'
   item_gwis_abbrev = 'tp'
   child_item_types = None

   local_defns = [
      # py/psql name,          deft,  send?,  pkey?,  pytyp,  reqv
      ('track_id',             None,   True,   True),
      # FIXME: Need track_stack_id and track_version? What should reqv be?
      ('track_stack_id',       None,   True,  False,    int,     0),
      ('track_version',        None,   True,  False,    int,     0),
      #
      ('step_number',          None,  False,   True),
      #
      # MAYBE: Are these XML item types right wrong? They're mostly str.
      # 2013.05.11: EXPLAIN: Why are these str and not all float?
      ('x',                    None,   True,  False,    str,     0),
      ('y',                    None,   True,  False,    str,     0),
      # 2013.05.11: EXPLAIN: Isn't timestamp value usually a str?
      ('timestamp',            None,   True,  False,  float,     0),
      ('altitude',             None,   True,  False,    str,     0),
      ('bearing',              None,   True,  False,    str,     0),
      ('speed',                None,   True,  False,    str,     0),
      ('orientation',          None,   True,  False,    str,     0),
      ('temperature',          None,   True,  False,    str,     0),
      ]
   attr_defns = item_helper.One.attr_defns + local_defns
   psql_defns = item_helper.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(psql_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      item_helper.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def append_gml(self, elem):
      new = etree.Element('tpoint')
      item_helper.One.append_gml(self, elem, need_digest=False, new=new)
      return new

   #
   def from_gml(self, qb, elem):
      item_helper.One.from_gml(self, qb, elem)
      t = float(self.timestamp) / 1000.0
      self.timestamp = str(datetime.datetime.fromtimestamp(t))

   # *** Saving to the Database

   #
   def save_tpoint(self, qb, track, step_number):

      self.track_id = track.system_id
      # FIXME: Do we need these? They're in the table...
      self.track_stack_id = track.stack_id
      self.track_version = track.version

      self.step_number = step_number

      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # ***

class Many(item_helper.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   # This class is old-skule V1 and not a true Nonwiki item, so we don't use
   # the clauses; we don't have group_item_access records for these types of 
   # items.

   # *** Constructor

   def __init__(self):
      item_helper.Many.__init__(self)

   # ***

# ***

