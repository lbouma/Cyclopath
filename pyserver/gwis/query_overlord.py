# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

# Cannot: from grax.item_manager import Item_Manager
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from item.feat import branch
from item.feat import region
from item.util.item_query_builder import Item_Query_Builder
from item.util import revision

log = g.log.getLogger('query_overlord')

class Query_Overlord(object):

   __slots__ = ()

   def __init__(self):
      g.assurt(False)

   # *** 

   # This class is sorta weird. The query_builder filters need to be
   # initialized before being used, and one step is to compute the region
   # geometry. Well, all the item classes import the query_filters module, so
   # query_filters cannot import them back. Which is where this class comes in.
   # Once a query_builder object is setup, the seteruper must use this class to
   # configure the qb object.

   #
   @staticmethod
   def finalize_query(qb):
      if qb.filters is not None:
         if (qb.filters.filter_by_regions 
             or qb.filters.filter_by_watch_geom):
            Query_Overlord.regions_coalesce_geometry(from_qb=qb)
      # Make the couterpart hierarchy for diff.
      if (isinstance(qb.revision, revision.Diff)):
         qb.diff_hier = branch.Many.branch_hier_build(
            qb.db, qb.branch_hier[0][0], qb.revision, 
            diff_group='former', latter_group=qb.branch_hier)
         # EXPLAIN: Where's diff_group='latter'? Is that us?
      # NOTE: We'll call setup_gids in qb.finalize()
      #        qb.revision.setup_gids(qb.db, qb.username)
      qb.finalize()
      # Mark finalized so we can check for violators.
      qb.finalized = True

   # This fcn. is static so ccp.py can call it and not fetch.
   @staticmethod
   def prepare_filters(req):
# 2013.03.30: Can we just call this from finalize_query?
#      #
#      if (req.filters.filter_by_regions
#          or req.filters.filter_by_watch_geom):
#            Query_Overlord.regions_coalesce_geometry(req=req)
#         #log.debug('prepare_filters: multi_geom: %s' 
#         #          % (req.filters.only_in_multi_geometry,))
      # This seems like a weird place to do this... oh, well.
      if req.client.username:
         req.revision.rev.setup_gids(req.db, req.client.username)
         if not req.revision.rev.gids:
            log.warning('prepare_filters: no group IDs for user: %s'
                        % (req.client.username,))
            # 2013.03.31: EXPLAIN: Does this ever happen?
            g.assurt(False)

   # 
   # NOTE: Coupling alert: This fcn. really doesn't belong here?
   #       It's supposed to help things access the database and items, not do
   #       it itself?
   @staticmethod
   def regions_coalesce_geometry(req=None, from_qb=None):

      # Calculate the region-filter geometry. Do it now so we can cache the
      # value and use an explicit value in the SQL where clause. (This is 
      # bug nnnn, don't use SQL fcns. in WHERE clauses).
      #
      # Note that the region-filter is either the geometry of one or more
      # regions the client specifically indicate, or the geometry is the
      # geometry of regions that the user is watching.
      #
      # Note also that we use the Current revision of the regions and ignore
      # whatever revision the client might really be requesting. This is by
      # design, so users can make new regions and use them on historical
      # queries. It also makes working with the autocomplete edit box in
      # the client easier, since it only has to get the list of current
      # regions.

      g.assurt((req is not None) ^ (from_qb is not None))

      if from_qb is None:
         g.assurt(False) # Deprecated.
         db = req.db
         username = req.client.username
         branch_hier = req.branch.branch_hier
         the_rev = req.revision.rev
         filters = req.filters
         # NOTE: Cannot call as_iqb(addons=False), because that fcn. calls
         #       finalize_query(). So we make our own qb, below.
      else:
         db = from_qb.db
         username = from_qb.username
         branch_hier = from_qb.branch_hier
         the_rev = from_qb.revision
         filters = from_qb.filters

      if not isinstance(the_rev, revision.Current):
         the_rev = revision.Current()
         branch_hier = branch.Many.branch_hier_build(
                        db, branch_hier[0][0], the_rev)
         g.assurt(id(the_rev) == id(branch_hier[0][1]))
      else:
         # [lb] is not sure this is always true. Just curious...
         g.assurt(id(the_rev) == id(branch_hier[0][1]))
         g.assurt(not isinstance(the_rev, revision.Comprehensive))

      qb = Item_Query_Builder(db, username, branch_hier, the_rev)

      g.assurt(qb.revision == the_rev)

      # Use from_qb.item_mgr?
      # Cannot import Item_Manager:
      # Nope: qb.item_mgr = Item_Manager()
      g.assurt(from_qb is not None)
      g.assurt(from_qb.item_mgr is not None)
      qb.item_mgr = from_qb.item_mgr

      # Create a Many() object to perform the search
      # 2013.03.29: MAYBE: We're really fetching regions...
      region_geoms = region.Many()
      # Tell the sql builder not to double-check the multi geom
      region_geoms.search_for_geom(qb, filters.filter_by_regions,
                                       filters.filter_by_watch_geom)

      g.assurt(len(region_geoms) == 1) # Because of the aggregrate, ST_Union.
      # Normally geometry_svg gets set but only for an outer select.
      # Our select had nothing nested, so geometry is raw only.
      geom = region_geoms[0].geometry
      if geom is None:
         # If there's no geometry, we won't find anything, so short-circuit.
         # MAYBE: Alert user that region name was not found, or no watched
         #        regions were found? Except we're called from a filter...
         #        so the lack of results should be clue enough.
         log.debug('fetch_n_save: GWIS_Nothing_Found: nothing found')
         raise GWIS_Nothing_Found()
      log.debug('fetch_n_save: len(geom): %s' % (len(geom),))

      # Set the geometry we calculated in the source qb.
      filters.only_in_multi_geometry = geom

   # ***

# ***

