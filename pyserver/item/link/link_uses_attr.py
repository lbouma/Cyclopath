# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import traceback

from gwis.query_overlord import Query_Overlord
from item import link_value
from item.attc import attribute
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type

log = g.log.getLogger('link_uses_attr')

class One(link_value.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'

   #child_item_types = None
   child_item_types = (
      Item_Type.LINK_VALUE,
      Item_Type.LINK_GEOFEATURE,
      Item_Type.LINK_POST,
      #Item_Type.LINK_ATTRIBUTE,
      )

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      link_value.One.__init__(self, qb, row, req, copy_from)

   # ***

# ***

class Many(link_value.Many):

   one_class = One

   __slots__ = (
      'attr_stack_id',
      'the_attr',
      )

   def __init__(self, attc_type=None, feat_type=None):
      link_value.Many.__init__(self, attc_type, feat_type)
      self.attr_stack_id = 0
      self.the_attr = None

   #
   def attribute_load(self, qb, attr_name):
      # DEPRECATED: See qb.item_mgr.cache_attrs/cache_attrnames.
      # 2012.08.14: This is still used by link_post... probably okay if it just
      #             happens once per checkout...
      # MAYBE: Can/Should we preload attributes for all pyserver instances?
      # Would only make sense if it runs before URL requests are received,
      # i.e., if Apache loads pyserver and then just forks it for each request.

      attr = None

      if (qb.item_mgr is not None) and (qb.item_mgr.loaded_cache):
         try:
            # Note that we're caching to the qb object so that this fcn. is
            # thread-, er, apache-thread-safe.
            attr = qb.item_mgr.cache_attrnames[attr_name]
         except KeyError:
            pass

      if attr is None:

         # CAVEAT: Callers should call qb.item_mgr.load_cache_attachments(qb)
         #         if they intend to load most of the attributes. If the caller
         #         is just intending to load a few attributes, this fcn. is
         #         fine, but if you want all the attributes, load the cache.

         qb_cur = qb.clone()
         qb_cur.revision = revision.Current()
         qb_cur.branch_hier[0] = (qb_cur.branch_hier[0][0],
                                  qb_cur.revision,
                                  qb_cur.branch_hier[0][2],)
         # Can call qb_cur.revision.setup_gids(qb_cur.db, qb_cur.username) or
         qb_cur.branch_hier_set(qb_cur.branch_hier)
         Query_Overlord.finalize_query(qb_cur)

         attrs = attribute.Many()
         attrs.search_by_internal_name(attr_name, qb_cur)
         log.verbose('attribute_load: %s (%d)' 
                     % (attr_name, len(attrs),))
         if len(attrs):
            g.assurt(len(attrs) == 1)
            attr = attrs[0]
            if qb.item_mgr.loaded_cache:
               qb.item_mgr.cache_attrnames[attr_name] = attr

      if attr is not None:
         self.attr_stack_id = attr.stack_id
         self.the_attr = attr
      else:
         # This happens on import... but import not longer uses this fcn.
         # This fcn. is just called for checking out a thread and posts,
         # e.g., to get the stack ID of '/post/revision', so this is probably a
         # problem.
         log.warning('attribute_load: Attribute not found: %s' % (attr_name,))
         self.attr_stack_id = 0
         self.the_attr = None

   # ***

# ***

