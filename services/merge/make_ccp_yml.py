# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item.feat import branch

__all__ = ('Make_Ccp_Yml',)

log = g.log.getLogger('make_ccp_yml')

# ***

class Make_Ccp_Yml(object):

   # *** Constructor

   def __init__(self):
      # This class is not meant to be instantiated.
      g.assurt(False)

   #
   @staticmethod
   def produce(qb, mjob):

      branches = branch.Many()
      branches.search_by_stack_id(mjob.branch_id, qb)
      g.assurt(len(branches) == 1)
      src_branch = branches[0]

      # Item Type layers
      layers_yml = ''
      # FIXME: Support export of different item types.
      item_types = ['item',]
      for item_type in item_types:
         layers_yml += (
     #import_type: cyclop
            """
   - !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim
     shpf_name: cyclopath_%s.shp
     shpf_layr: cyclopath_%s
     item_type: %s
     do_conflate: False

"""
      # MAGIC_NUMBER: There are 3 %ses above.
      % (3 * [item_type,],))

      as_yml = (
"""
# Cyclopath Import Config.

# SYNC_ME: We use a shim class to object-ify this Yaml. Without the object, we
# access attributes using nested dictionaries. But I am not a big fan of 
# dicts within dicts. E.g., would you rather write, 
#   conf['source_def']['roadmatcher']['shpf_name']
# or,
#   conf.source_def.roadmatcher.shpf_name
# ?
!!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Base

# NOTE: WGS84 is similar to NAD83 (that is, within a meter around Mpls) so if 
# your projection looks good in Arc but is not quite right, check the project.
# And maybe some day we'll support different projections. For now this _must_
# be NAD83.
source_srs: NAD83

# *** Cyclopath context.

ccp_src:

  !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim

   # The revision ID of the original Cyclopath data.
   revision_id: %(revision_id)d

   # Original export context.
   #branch: %(branch_name)s
   branch: %(branch_id)d

   # FIXME: Add the regions filter list
   #filter_by_regions: 

ccp_dst:

   !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim

   # 
   commit_message_prefix: Cyclopath Export Import

   # The branch (name or id) or branch_id (id) of the destination branch.
   #branch: %(branch_name)s
   branch: %(branch_id)d

   # The group (name or id) or group_id (id) of the target group.
   # FIXME: I am not convinced about this. We could let the user choose whose
   # permissions to set for imported items, but that seems unnecessarily 
   # complicated. For now, imports and exports are all based on
   # Public-accessible items. (Though you could always fiddle with this section
   # and try something different. But we won't be exposing this option from
   # flashclient.)
   permissions:
      - !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim
        group       : Public
        access_level: editor

# *** Shapefile details.

# The target Shapefile.
export_name: bikeways_target.shp

# The source Shapefiles.
shapefiles:

   %(layers_yml)s

   # If you want to conflate a custom Shapefile, make entries like the
   # following.
   #- !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim
   #  shpf_name: Agency_Source.shp
   #  shpf_layr: Agency_Source
   #  # Item types are: byway, point, region, terrain
   #  item_type: byway
   #  do_conflate: True

   # If you are conflating from RoadMatcher, you might find that some split 
   # segments are missing.
   #- !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim
   #  shpf_name: Agency_Source.shp
   #  shpf_layr: Agency_Source
   #  item_type: byway
   #  do_conflate: False
   #  assume_missing_geometry: True

"""
   #  import_type: conflate
      % ({'revision_id': mjob.for_revision,
          'branch_name': src_branch.name,
          'branch_id': mjob.branch_id,
          'layers_yml': layers_yml,
         }))

      return as_yml

