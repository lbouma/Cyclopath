# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import urllib
import uuid

import conf
import g

from grax.access_level import Access_Level
from gwis.query_base import Query_Base
from gwis.exception.gwis_error import GWIS_Error
from util_ import misc

log = g.log.getLogger('gwis.q_filter')

class Query_Filters(Query_Base):

   # Following is the list of filters that GWIS supports. These are mostly used
   # with the checkout command, but some of them are also used for other
   # commands.

   # NOTE: You cannot name this __slots__ unless you override __getstate__ for
   # cPickle. But overriding __getstate__ is tedious, and we don't really need 
   # __slots__. cPickle just uses self.__dict__, which we could also just
   # use, but this at least serves as some sort of documentation.
   #__slots__ = (
   #__sloots__ = (
   __after_slots__ = (

      # SYNC_ME: Search Query_Filters

      # *** These variables match those in flashclient and are set via GWIS.

      # The class definition version, for cPickle.
      'ver_pickled',

      # Pagination.
      'pagin_total',          # use the query filters to do a COUNT(*)
      'pagin_count',          # no. of records to fetch
      'pagin_offset',         # page no. of records to fetch (based on count)

      # Result ordering. Not supported. 
      # Needed to change search from server-side to client-side paginating.
      #'result_order',        # 'rord'

      # The search center, for map searches. Results are ordered by distance
      # from this point.
      'centerx',
      'centery',
      # NOTE: In flashclient, centerx and centery are represented by a point:
      #         centered_at

      # Search, Discussions, and Recent Changes filters.
      #
      # If more than one of these is set, the result is an ORing. At least for
      # now. From flashclient, you can only set one of these at a time.
      'filter_by_username',   # text search on username

      # The tricky triple: these filters are complex.
      # * Sometimes we need to perform a setup step that runs a normal
      #   Cyclopath query (in the user's context) to either:
      #   - Assemble a collection of region geometries; or
      #   - Assemble a collection of item stack IDs.
      # * The region geometries are assembled if filter_by_regions specifies
      #   one or more region names, or if filter_by_watch_geom is nonzero.
      #   - If filter_by_regions, we search the region table and find all
      #     the regions the user can view that match the specified names.
      #   - If filter_by_watch_geom, we search the region table for regions
      #     the user is watching.
      # * The item stack IDs are collected if filter_by_watched_item, but
      #   how they're used varies.
      #   - If fetching geofeatures, we just filter the geofeatures being
      #     fetched (which we do in the SQL, so there's no setup step);
      #   - If fetching attachments, we can filter the attachments being
      #     fetched (just like we'd do if fetching geofeatures);
      #   - If fetching attachments, we could instead filter attachments by
      #     the geofeatures to which they're attached. In the setup step, we
      #     find all the geofeatures the user is watching and then we use those
      #     stack IDs to filter the fetched attachments.
      # FIXME: Do previous for filter by viewport at raster zoom.
      #
      'filter_by_regions',    # text search on region names
      'filter_by_watch_geom', # only items in regions user is watching
      'filter_by_watch_item', # only items that user is watching
      'filter_by_watch_feat', # only items w/ attached items user is watching
      'filter_by_unread',     # only items user has not seen since changed
      'filter_by_names_exact', # comma-separated list of exact item names
      'filter_by_text_exact', # single-term text search (on all text columns)
      'filter_by_text_loose', # single-term text search (on all text columns)
      'filter_by_text_smart', # full-text search (multi-term); raw
      'filter_by_text_full',  # full-text search, but already to_tsquery()ed
      'filter_by_nearby_edits', # only nearby edited items
      'filter_by_thread_type', #
      # MAYBE: Replace filter_by_username with filter_by_creator_*.
      'filter_by_creator_include', #
      'filter_by_creator_exclude', #

      # Specific Stacks IDs that use temporary stack_id lookup table.
      'stack_id_table_ref',   # table name of temp. stack_id table
      'stack_id_table_lhs',   # link_value attachments, or lhs items
      'stack_id_table_rhs',   # link_value geofeatures, or rhs items

      # Specific Stack IDs -- All Items.
      'only_stack_ids',       # only items with the specified stack ids
      # 2014.05.09: About time =): specific sys ID so cli can req item history.
      'only_system_id',       # item with the specified system id
      # For "About items in visible area" filter for discussions.
      # 2013.03.27: [lb] notes that about_stack_ids is similar to
      #             only_rhs_stack_ids, but not really: about_stacks_ids
      #             applies to non-link_values, e.g., checkout threads
      #             but only with links to these geofeatures. The
      #             only_rhs_stack_ids filter only works on link_values.
      #             But they're implemented very similarly.
      'about_stack_ids',      # only threads about items with these stack_ids.

      # Specific Stack IDs -- Link_Values.
      # NOTE: These only work if the item.Many() is derived from link_value.
      'only_lhs_stack_ids',   # for link_values, only for these lhs items
      'only_rhs_stack_ids',   # for link_values, only for these rhs items
      # FIXME: EXPLAIN: What's the difference between the stack ID arrays and
      # the solo stack ID values here? Why aren't these in flashclient?
      'only_lhs_stack_id',
      'only_rhs_stack_id',

      # value_* filters.
      'filter_by_value_text',
      # FIXME: Implement for other value_* so flashclient search can search
      #        like this.

      # NOTE: Skipping flashclient's
      #         only_selected_items

      # Specific Stack IDs -- Nonwiki Items.
      'only_associate_ids',# for nonwiki items; get items about these stack ids
      'context_stack_id',  # solo alt. to previous, for getting thread's posts.
      # NOTE: only_item_type_ids is called only_item_type in pyserver.
      'only_item_type_ids',   # for watchers, only associated items of types
      'only_lhs_item_types',  # for routed and import/export, fetch just 
      'only_rhs_item_types',  #   links with these item type IDs
      # Skipping flashclient's only_selected_items

      # Stealth secret.
      'use_stealth_secret',   # gets one item if the stealth secret matches

      # Results style.
      'results_style',        # what kinds of data (i.e., cols) to return
      'include_item_stack',   # includes stealth_secret, access_style_id,
                              #  access_infer_id from item_stack, and
                              #  created_user and created_date from version=1,
                              #  and edited_date, etc., from item_revisionless.

      'include_lhs_name',     # name checkedout link_value using lhs name
      'include_rhs_name',     # name checkedout link_value using rhs name

      # History filters.
      'rev_ids',            # specific revision ids to return
      'include_geosummary', # include geosummary in results
      'rev_min',            # minimum revision id
      'rev_max',            # maximum revision id

      # Ratings filters.
      # FIXME: Implement in flashclient
      'rating_restrict',    # If true, only use user ratings for leafy branch
      'rating_special',

      # Route Sharing uses filters to displays routes the user owns/arbits
      # versus routes owned/arbited by other users. So this allow the client to
      # filter results by access level. Note that min_access_level was
      # originally intended for the local ccp.py script, but there's no problem
      # letting clients ask us to filter by access level. (In CcpV1, this is
      # filtering by "my routes" vs. by "others' routes".)
      'min_access_level',
      'max_access_level',

      # *** These are pyserver-only and only set by pyserver or local scripts

      # If filter_by_regions or filter_by_watch_geom is set, we have to figure
      # out the geometry in question. When we're querying for the geometry, we
      # set setting_multi_geometry. After we've calculated the geometry and are
      # fetching items for the user, we set only_in_multi_geometry to the geom.
      'setting_multi_geometry',
      'only_in_multi_geometry',

      # This is a hack for the geometry classes, which used to always fetch 
      # geometry as SVG but also always expected incoming geometry to be in WKT
      # format (see bug nnnn).
      'skip_geometry_raw', # 
      'skip_geometry_svg', # load geometry WKT rather than SVG (we send SVG to 
                           # client, but for interal ops, we need WKT instead).
      'skip_geometry_wkt', # 
      'make_geometry_ewkt',#
      #
      'gia_use_gids',      # If strlist, uses SQL IN (WHERE group_id IN (...)) 
                           #   rather than joining user_ and group_membership
                           #   to figure out user access to items. (Or
                           #   bypasses permissions altogether and gets all
                           #   items.)
      'gia_userless',      # If set, don't filter on permissions. Dangerous! =)
      'gia_use_sessid',    # 
      #
      # NOTE: Flashclient always sets False; load_cache_attc_tags sets True.
      # MAYBE: This is only used on Tag checkout, so, only one call per user
      # session, but really, the logic here should be the inverse: that is,
      # rename and reverse logic, skip_tag_counts -> include_tag_counts. It
      # should be the caller's responsibility to ask for byway-tag-counts.
      'skip_tag_counts',      # True to not waste time calculating tag counts.
      # dont_load_feat_attcs is always False. It applies on checkout and
      # internally, when bulk-loading geofeatures.
      'dont_load_feat_attcs', # True to not load feats' lvals (attrs and tags).
      # If the user is highlighting features with notes/posts, this is True.
      'do_load_lval_counts', # True to load feats' lval cts (notes and posts)

      'include_item_aux',  # Get, e.g., route steps and stops or track points

      # MEH: ya know findability is just like using a private attr, eh?
      #      But maybe using the one table (item_findability) is simpler
      #      than using multiple tables (attribute and link_value)... and
      #      maybe having our own table offers a little more flexibility
      #      for adding more options (i.e., it's easier than making a bunch
      #      of attributes, or trying to cram multiple options into a
      #      single integer bitfield)? Also, we left-outer-join the table,
      #      item_findability, because a lack of row also means something....
      'findability_ignore', # Affects, e.g., routes; ignores library_squelch.
      'findability_ignore_include_deleted',
      'findability_recent', # Fetch recently viewed items list...

      #
      # BUG nnnn: In flashclient, add user option, e.g., UI.byway_tooltips 
      #           (or settings_options.byway_tooltips_cbox?) and then tell 
      #           pyserver to load latest note for each byway.
      # FIXME: Implement this:
      'do_load_latest_note', # E.g., client's "Tooltips on streets".

      #
      # MAYBE: When fetching routes, restrict by geometry length.
      #        Bug nnnn: See last comment line. Also, for routes, the search
      #                  might have to be more intelligent, like, does the
      #                  route have to be circular? does the route have to pass
      #                  by or within a certain distance of a user-OD?
      #'geom_length_min',
      #'geom_length_max',
      # FIXME: Do we need these for route_search?:
      #self.min_length = self.decode_key('min_length', False)
      #self.max_length = self.decode_key('max_length', False)

      # The node_cache_maker script is the one the creates node_endpoints.
      # It relies on item_mgr to load the byways, but byway JOINs on
      # node_endpoints. So this tells it not to.
      'exclude_byway_elevations',

      # See item_user_access.search_item_type_id_sql.
      # MAYBE: Add these to the flashclient Query_Filters.as.
      'filter_by_value_boolean',
      'filter_by_value_integer',
      'filter_by_value_real',
      'filter_by_value_text',
      'filter_by_value_binary',
      'filter_by_value_date',

      'force_resolve_item_type',

      )

   # *** Constructor

   def __init__(self, req):
      # NOTE: req only needed if decoding GWIS.
      Query_Base.__init__(self, req)
      self.ver_pickled = 1
      # NOTE: All of these should default to a logically untrue value.
      self.pagin_total = False
      self.pagin_count = 0
      self.pagin_offset = 0
      self.centerx = 0.0
      self.centery = 0.0
      self.filter_by_username = ''
      self.filter_by_regions = ''
      self.filter_by_watch_geom = False
      self.filter_by_watch_item = 0
      self.filter_by_watch_feat = False
      self.filter_by_unread = False
      self.filter_by_names_exact = ''
      self.filter_by_text_exact = ''
      self.filter_by_text_loose = ''
      self.filter_by_text_smart = ''
      self.filter_by_text_full = ''
      self.filter_by_nearby_edits = False
      self.filter_by_thread_type = ''
      self.filter_by_creator_include = ''
      self.filter_by_creator_exclude = ''
      self.stack_id_table_ref = ''
      self.stack_id_table_lhs = ''
      self.stack_id_table_rhs = ''
      self.only_stack_ids = ''
      self.only_system_id = 0
      self.about_stack_ids = ''
      self.only_lhs_stack_ids = ''
      self.only_rhs_stack_ids = ''
      self.only_lhs_stack_id = 0
      self.only_rhs_stack_id = 0
      self.only_associate_ids = []
      self.context_stack_id = 0
      self.only_item_type_ids = ''
      self.only_lhs_item_types = ''
      self.only_rhs_item_types = ''
      self.use_stealth_secret = ''
      self.results_style = ''
      self.include_item_stack = False
      self.include_lhs_name = False
      self.include_rhs_name = False
      self.rev_ids = []
      self.include_geosummary = False
      self.rev_min = 0
      self.rev_max = 0
      self.rating_restrict = False
      self.rating_special = False
      self.min_access_level = None
      self.max_access_level = None
      self.setting_multi_geometry = False
      self.only_in_multi_geometry = None
      self.skip_geometry_raw = False
      self.skip_geometry_svg = False
      self.skip_geometry_wkt = False
      self.make_geometry_ewkt = False
      self.gia_use_gids = ''
      self.gia_userless = False
      self.gia_use_sessid = False
      self.skip_tag_counts = False
      self.dont_load_feat_attcs = False
      self.do_load_lval_counts = False
      self.include_item_aux = False
      self.findability_ignore = False
      self.findability_ignore_include_deleted = False
      self.findability_recent = False
      self.do_load_latest_note = False
      self.exclude_byway_elevations = False
      self.filter_by_value_boolean = None
      self.filter_by_value_integer = None
      self.filter_by_value_real = None
      self.filter_by_value_text = None
      self.filter_by_value_binary = None
      self.filter_by_value_date = None
      self.force_resolve_item_type = False

   """
   #
   def __getstate__(self):
      return False

   #
   def __setstate__(self, state):
      g.assurt(False)
   """

   # ***

   # 
   def __eq__(self, other):
      equals = (Query_Base.__eq__(self, other)
                and isinstance(other, Query_Filters))
      if equals:
         # NOTE: == Should work on: int, bool, str, []
         #          I'm [lb] not sure about geometry...
         #for mbr in Query_Filters.__slots__:
         for mbr in Query_Filters.__after_slots__:
            if getattr(self, mbr) != getattr(other, mbr):
               equals = False
               break
      return equals

   #
   def __ne__(self, other):
      return not (self == other)

   #
   def __str__(self):
      strs = []
      if self.pagin_total:
         strs.append('cnts %s' % self.pagin_total)
      if self.pagin_count:
         strs.append('rcnt %d' % self.pagin_count)
      if self.pagin_offset:
         strs.append('roff %d' % self.pagin_offset)
      # centerx and centery [pyserver] ==> centered_at [flashclient]
      if self.centerx:
         # E.g., 'ctrx %.6f'
         strs.append(('ctrx %%.%df' % conf.geom_precision) % self.centerx)
      if self.centery:
         strs.append(('ctry %%.%df' % conf.geom_precision) % self.centery)
      if self.filter_by_username:
         strs.append('busr %s' % self.filter_by_username)
      if self.filter_by_regions:
         strs.append('nrgn %s' % self.filter_by_regions)
      if self.filter_by_watch_geom:
         strs.append('wgeo %s' % self.filter_by_watch_geom)
      if self.filter_by_watch_item:
         strs.append('witm %s' % self.filter_by_watch_item)
      if self.filter_by_watch_feat:
         strs.append('woth %s' % self.filter_by_watch_feat)
      if self.filter_by_unread:
         strs.append('unrd %s' % self.filter_by_unread)
      if self.filter_by_names_exact:
         strs.append('nams %s' % self.filter_by_names_exact)
      if self.filter_by_text_exact:
         strs.append('mtxt %s' % self.filter_by_text_exact)
      if self.filter_by_text_loose:
         strs.append('ltxt %s' % self.filter_by_text_loose)
      if self.filter_by_text_smart:
         strs.append('ftxt %s' % self.filter_by_text_smart)
      if self.filter_by_text_full:
         strs.append('stxt %s' % self.filter_by_text_full)
      if self.filter_by_nearby_edits:
         strs.append('nrby %s' % self.filter_by_nearby_edits)
      if self.filter_by_thread_type:
         strs.append('tdtp %s' % self.filter_by_thread_type)
      if self.filter_by_creator_include:
         strs.append('fbci %s' % self.filter_by_creator_include)
      if self.filter_by_creator_exclude:
         strs.append('fbce %s' % self.filter_by_creator_exclude)
      if self.stack_id_table_ref:
         strs.append('sidr_ref %s' % self.stack_id_table_ref)
      if self.stack_id_table_lhs:
         strs.append('sidr_lhs %s' % self.stack_id_table_lhs)
      if self.stack_id_table_rhs:
         strs.append('sidr_rhs %s' % self.stack_id_table_rhs)
      if self.only_stack_ids:
         strs.append('sids_gia %s' % self.only_stack_ids)
      if self.only_system_id:
         strs.append('sysid %d' % self.only_system_id)
      if self.about_stack_ids:
         strs.append('sids_abt %s' % self.about_stack_ids)
      if self.only_lhs_stack_ids:
         strs.append('sids_lhs %s' % self.only_lhs_stack_ids)
      if self.only_rhs_stack_ids:
         strs.append('sids_rhs %s' % self.only_rhs_stack_ids)
      if self.only_lhs_stack_id:
         strs.append('lhsd %d' % self.only_lhs_stack_id)
      if self.only_rhs_stack_id:
         strs.append('rhsd %d' % self.only_rhs_stack_id)
      if self.only_associate_ids:
         strs.append('ids_assc %s' % self.only_associate_ids)
      if self.context_stack_id:
         strs.append('ctxt %d' % self.context_stack_id)
      if self.only_item_type_ids:
         strs.append('ids_itps %s' % self.only_item_type_ids)
      if self.only_lhs_item_types:
         strs.append('ids_ltps %s' % self.only_lhs_item_types)
      if self.only_rhs_item_types:
         strs.append('ids_rtps %s' % self.only_rhs_item_types)
      if self.use_stealth_secret:
         strs.append('stlh %s' % self.use_stealth_secret)
      if self.results_style:
         strs.append('rezs %s' % self.results_style)
      if self.include_item_stack:
         strs.append('istk %s' % self.include_item_stack)
      if self.include_lhs_name:
         strs.append('ilhn %s' % self.include_lhs_name)
      if self.include_rhs_name:
         strs.append('irhn %s' % self.include_rhs_name)
      if self.rev_ids:
         strs.append('rids %s' % self.rev_ids)
      if self.include_geosummary:
         strs.append('gsum %s' % self.include_geosummary)
      if self.rev_min:
         strs.append('rmin %d' % self.rev_min)
      if self.rev_max:
         strs.append('rmax %d' % self.rev_max)
      if self.rating_restrict:
         strs.append('ratr %s' % self.rating_restrict)
      if self.rating_special:
         strs.append('rats %s' % self.rating_special)
      if self.min_access_level:
         strs.append('mnac %s' % self.min_access_level)
      if self.max_access_level:
         strs.append('mxac %s' % self.max_access_level)
      if self.setting_multi_geometry:
         strs.append('smgo %s' % self.setting_multi_geometry)
      if self.only_in_multi_geometry:
         if len(self.only_in_multi_geometry) < 20:
            strs.append('mgeo %s' % self.only_in_multi_geometry)
         else:
            strs.append('mgeo %s...' % self.only_in_multi_geometry[:17])
      if self.skip_geometry_raw:
         strs.append('nraw %s' % self.skip_geometry_raw)
      if self.skip_geometry_svg:
         strs.append('nsvg %s' % self.skip_geometry_svg)
      if self.skip_geometry_wkt:
         strs.append('nwkt %s' % self.skip_geometry_wkt)
      if self.make_geometry_ewkt:
         strs.append('ewkt %s' % self.make_geometry_ewkt)
      if self.gia_use_gids:
         strs.append('fgid %s' % self.gia_use_gids)
      if self.gia_userless:
         strs.append('usrl %s' % self.gia_userless)
      if self.gia_use_sessid:
         strs.append('guss %s' % self.gia_use_sessid)
      if self.skip_tag_counts:
         strs.append('ntcs %s' % self.skip_tag_counts)
      if self.dont_load_feat_attcs:
         strs.append('dlfa %s' % self.dont_load_feat_attcs)
      if self.do_load_lval_counts:
         strs.append('dllc %s' % self.do_load_lval_counts)
      if self.include_item_aux:
         strs.append('iaux %s' % self.include_item_aux)
      if self.findability_ignore:
         strs.append('bilt %s' % self.findability_ignore)
      if self.findability_ignore_include_deleted:
         strs.append('bild %s' % self.findability_ignore_include_deleted)
      if self.findability_recent:
         strs.append('bilr %s' % self.findability_recent)
      if self.do_load_latest_note:
         strs.append('dlln %s' % self.do_load_latest_note)
      if self.exclude_byway_elevations:
         strs.append('xbel %s' % self.exclude_byway_elevations)
      if self.filter_by_value_boolean is not None:
         strs.append('fbvb %s' % self.filter_by_value_boolean)
      if self.filter_by_value_integer is not None:
         strs.append('fbvi %s' % self.filter_by_value_integer)
      if self.filter_by_value_real is not None:
         strs.append('fbvr %s' % self.filter_by_value_real)
      #if self.filter_by_value_text:
      #   strs.append('vtxt %s' % self.filter_by_value_text)
      if self.filter_by_value_text:
         strs.append('fbvt %s' % self.filter_by_value_text)
      if self.filter_by_value_binary is not None:
         strs.append('fbvx %s' % self.filter_by_value_binary)
      if self.filter_by_value_date:
         strs.append('fbvd %s' % self.filter_by_value_date)
      if self.force_resolve_item_type:
         strs.append('frit %s' % self.force_resolve_item_type)
      if strs:
         self_s = ', '.join(strs)
      else:
         self_s = '(empty)'
      return self_s

   # *** Base class overrides

   # 
   def decode_gwis(self):
      if self.req is not None:
         self.decode_gwis_url()
         self.decode_gwis_xml()
      log.verbose1('decode_gwis: %s' % (str(self),))

   # *** Decode GWIS

   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::url_append_filters
   def decode_gwis_url(self):

      # N/a: ver_pickled

      self.pagin_total = bool(int(self.req.decode_key('cnts', 0)))

      self.pagin_count = int(self.req.decode_key('rcnt', 0))

      # FIXME: This is page number offset, not individual record offset.
      self.pagin_offset = int(self.req.decode_key('roff', 0))
      self.pagin_offset = self.pagin_offset * self.pagin_count

      self.centerx = float(self.req.decode_key('ctrx', 0.0))
      self.centery = float(self.req.decode_key('ctry', 0.0))

      self.filter_by_username = self.req.decode_key('busr', None)

      self.filter_by_regions = self.req.decode_key('nrgn', '')
      self.filter_by_watch_geom = bool(int(self.req.decode_key('wgeo', 0)))
      self.filter_by_watch_item = int(self.req.decode_key('witm', 0))
      self.filter_by_watch_feat = bool(int(self.req.decode_key('woth', 0)))

      self.filter_by_unread = bool(int(self.req.decode_key('unrd', 0)))

      self.filter_by_names_exact = self.req.decode_key('nams', '')
      self.filter_by_text_exact = self.req.decode_key('mtxt', '')
      self.filter_by_text_loose = self.req.decode_key('ltxt', '')
      # Remove non-ascii characters from the full text query. Also,
      # urllib.unquote does not seem to work for all unicode characters,
      # so some are left quoted and are thus not removed.
      ftxt = self.req.decode_key('ftxt', '')
      if ftxt:
         ftxt = (unicode(urllib.unquote(ftxt), errors='ignore')
                         .encode('ascii', 'xmlcharrefreplace')).lower()
      self.filter_by_text_smart = ftxt
      # Skipping: self.filter_by_text_full (not allowed from client)

      self.filter_by_nearby_edits = bool(int(self.req.decode_key('nrby', 0)))
      self.filter_by_thread_type = self.req.decode_key('tdtp', '')
      self.filter_by_creator_include = self.req.decode_key('fbci', '')
      self.filter_by_creator_exclude = self.req.decode_key('fbce', '')

      # NOTE: Skipping:
      #self.stack_id_table_ref = self.req.decode_key('sidr_ref', '')
      #self.stack_id_table_lhs = self.req.decode_key('sidr_lhs', '')
      #self.stack_id_table_rhs = self.req.decode_key('sidr_rhs', '')

      # See next fcn. for
      #   only_stack_ids
      self.only_system_id = int(self.req.decode_key('sysid', 0))
      #   about_stack_ids
      #   only_lhs_stack_ids
      #   only_rhs_stack_ids

      # FIXME: Are these internal (pyserver-only) or GWIS? They are not used by
      # flashclient.
      self.only_lhs_stack_id = int(self.req.decode_key('lhsd', 0))
      self.only_rhs_stack_id = int(self.req.decode_key('rhsd', 0))

      # See next fcn. for 
      #   only_associate_ids

      self.context_stack_id = int(self.req.decode_key('ctxt', 0))

      # See next fcn. for 
      #   only_item_type_ids
      #   only_lhs_item_types
      #   only_rhs_item_types

      self.use_stealth_secret = self.req.decode_key('stlh', '')
      if self.use_stealth_secret:
         try:
            self.use_stealth_secret = uuid.UUID(self.use_stealth_secret)
         except ValueError:
            raise GWIS_Error('Stealth Secret is not a valid UUID: "%s".'
                             % (self.use_stealth_secret,))

      self.results_style = self.req.decode_key('rezs', '')
      self.include_item_stack = bool(int(self.req.decode_key('istk', False)))

      self.include_lhs_name = bool(int(self.req.decode_key('ilhn', False)))
      self.include_rhs_name = bool(int(self.req.decode_key('irhn', False)))

      self.rev_ids = []
      rids = self.req.decode_key('rids', None)
      if rids is not None:
         for rid in rids.split(','):
            self.rev_ids.append(str(int(rid)))

      self.include_geosummary = bool(int(self.req.decode_key('gsum', 0)))

      self.rev_min = int(self.req.decode_key('rmin', 0))

      self.rev_max = int(self.req.decode_key('rmax', 0))

      self.rating_restrict = bool(int(self.req.decode_key('ratr', 0)))
      self.rating_special = bool(int(self.req.decode_key('rats', 0)))

      self.min_access_level = int(self.req.decode_key('mnac', 0))
      self.max_access_level = int(self.req.decode_key('mxac', 0))
      # We'll check that the access levels are valid in verify_filters.

      # Skipping only_in_multi_geometry (gwis.command_client sets it 
      # from prepare_filters) and skipping setting_multi_geometry (set by local
      # scripts as necessary; not used by flashclient). 

      # Skipping:
      #   skip_geometry_raw
      #   skip_geometry_svg
      #   skip_geometry_wkt
      #   make_geometry_ewkt

      # We can't accept gia_use_gids: that's a security risk, too.
      # We can't accept gia_userless: that's a security risk, too.
      # There was a comment that gia_use_sessid was a security risk,
      # but really that's not true: it's a bool and we use the real,
      # verified session id in the SQL, so it's not a problem.
      # (Though maybe [lb] was concerned about the face that client's
      # can spoof session IDs, but what're they gonna get? Someone's
      # route? We just need to generate session IDs locally and time
      # them out eventually, and maybe check session ID against other
      # client characteristics (like we do for the user token).
      self.gia_use_sessid = bool(int(self.req.decode_key('guss', 0)))

      self.skip_tag_counts = bool(int(self.req.decode_key('ntcs', 0)))
      self.dont_load_feat_attcs = bool(int(self.req.decode_key('dlfa', 0)))
      self.do_load_lval_counts = bool(int(self.req.decode_key('dllc', 0)))
      self.include_item_aux = bool(int(self.req.decode_key('iaux', 0)))
      self.findability_ignore = bool(int(self.req.decode_key('bilt', 0)))
      self.findability_ignore_include_deleted = (
                                 bool(int(self.req.decode_key('bild', 0))))
      self.findability_recent = bool(int(self.req.decode_key('bilr', 0)))
      self.do_load_latest_note = bool(int(self.req.decode_key('dlln', 0)))
      self.exclude_byway_elevations = bool(int(self.req.decode_key('xbel', 0)))
      self.filter_by_value_boolean = self.req.decode_key('fbvb', None)
      if self.filter_by_value_boolean is not None:
         self.filter_by_value_boolean = bool(int(self.filter_by_value_boolean))
      self.filter_by_value_integer = self.req.decode_key('fbvi', None)
      if self.filter_by_value_integer is not None:
         self.filter_by_value_integer = int(self.filter_by_value_integer)
      self.filter_by_value_real = self.req.decode_key('fbvr', None)
      if self.filter_by_value_real is not None:
         self.filter_by_value_real = float(self.filter_by_value_real)
      #self.filter_by_value_text = self.req.decode_key('vtxt', '')
      self.filter_by_value_text = self.req.decode_key('fbvt', None)
      #if self.filter_by_value_text is not None:
      #   self.filter_by_value_text = str(self.filter_by_value_text)
      self.filter_by_value_binary = self.req.decode_key('fbvx', None)
      #? if self.filter_by_value_binary is not None:
      #?    self.filter_by_value_binary = bin(self.filter_by_value_binary)
      self.filter_by_value_date = self.req.decode_key('fbvd', None)
      #? if self.filter_by_value_date is not None:
      #?     self.filter_by_value_date = datetime(self.filter_by_value_date)
      self.force_resolve_item_type = bool(int(self.req.decode_key('frit', 0)))

   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::xml_append_filters
   def decode_gwis_xml(self):
      self.only_stack_ids = self.decode_ids_compact('sids_gia')
      #log.debug('decode_gwis_xml: only_stack_ids %s' % (self.only_stack_ids,))
      self.about_stack_ids = self.decode_ids_compact('sids_abt')
      #log.debug('decode_gwis_xml: about_sids: %s' % (self.about_stack_ids,))
      self.only_lhs_stack_ids = self.decode_ids_compact('sids_lhs')
      self.only_rhs_stack_ids = self.decode_ids_compact('sids_rhs')
      self.only_associate_ids = self.decode_ids_compact('ids_assc')
      self.only_item_type_ids = self.decode_ids_compact('ids_itps')
      # These are not implemented in flashclient:
      self.only_lhs_item_types = self.decode_ids_compact('ids_ltps')
      self.only_rhs_item_types = self.decode_ids_compact('ids_rtps')

   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::append_xml_verbose
   def decode_ids_compact(self, doc_name, doc_in=None):
      if doc_in is None:
         doc_in = self.req.doc_in
      stack_ids = ''
      if doc_in is not None:
         stack_ids_doc = doc_in.find(doc_name)
         if stack_ids_doc is not None:
            # .tag is the element name, and .text is it's value.
            stack_ids_s = stack_ids_doc.text
            if stack_ids_doc.text:
               try:
                  stack_ids_i = [ int(sid) for sid in stack_ids_s.split(',')
                                             if sid]
                  # NOTE: We don't accept client IDs, only actual IDs.
                  stack_ids_a = [ str(sid) for sid in stack_ids_i
                                             if sid > 0 ]
               except ValueError:
                  log.warning('decode_ids_compact: not ints: %s' 
                              % (stack_ids_doc.text,))
                  raise GWIS_Error('Stack ID list not integers.')
               stack_ids = ", ".join(stack_ids_a)
      log.verbose('decode_ids_compact: doc_name: %s / stack_ids: %s'
                  % (doc_name, stack_ids,))
      return stack_ids

   # *** Encode GWIS

   # NOTE: This fcn. is used by ccp.py to make a url to send to pyserver
   #       (pyserver itself doesn't need to make a URL; it needs to unpack a
   #        URL, which it does above, in decode_gwis())).
   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::url_append_filters
   def url_append_filters(self, url_str):
      g.assurt(url_str)
      if self.pagin_total:
         url_str += '&cnts=' + str(int(self.pagin_total))
      if self.pagin_count > 0:
         url_str += '&rcnt=' + str(self.pagin_count)
      if self.pagin_offset > 0:
         url_str += '&roff=' + str(self.pagin_offset)
      #if self.centered_at:
         #url_str += ('&centerx=' + self.centered_at.x
         #            + '&centery=' + self.centered_at.y)
      if self.centerx and self.centery:
         url_str += ('&ctrx=' + str(self.centerx)
                     + '&ctry=' + str(self.centery))
      else:
         g.assurt(not (self.centerx and self.centery))
      if self.filter_by_username:
         url_str += '&busr=' + urllib.quote(self.filter_by_username)
      if self.filter_by_regions:
         url_str += '&nrgn=' + urllib.quote(self.filter_by_regions)
      if self.filter_by_watch_geom:
         url_str += '&wgeo=' + str(int(self.filter_by_watch_geom))
      if self.filter_by_watch_item:
         url_str += '&witm=' + str(self.filter_by_watch_item)
      if self.filter_by_watch_feat:
         url_str += '&woth=' + str(int(self.filter_by_watch_feat))
      if self.filter_by_unread:
         url_str += '&unrd=' + str(int(self.filter_by_unread))
      if self.filter_by_names_exact:
         url_str += '&nams=' + urllib.quote(self.filter_by_names_exact)
      if self.filter_by_text_exact:
         url_str += '&mtxt=' + urllib.quote(self.filter_by_text_exact)
      if self.filter_by_text_loose:
         url_str += '&ltxt=' + urllib.quote(self.filter_by_text_loose)
      if self.filter_by_text_smart:
         url_str += '&ftxt=' + urllib.quote(self.filter_by_text_smart)
      if self.filter_by_text_full:
         url_str += '&stxt=' + urllib.quote(self.filter_by_text_full)
      if self.filter_by_nearby_edits:
         url_str += '&nrby=' + str(int(self.filter_by_nearby_edits))
      if self.filter_by_thread_type:
         url_str += '&tdtp=' + urllib.quote(self.filter_by_thread_type)
      if self.filter_by_creator_include:
         url_str += '&fbci=' + urllib.quote(self.filter_by_creator_include)
      if self.filter_by_creator_exclude:
         url_str += '&fbce=' + urllib.quote(self.filter_by_creator_exclude)
      # NOTE: Skipping:
      #if self.stack_id_table_ref:
      #   url_str += '&sidr_ref=' + urllib.quote(self.stack_id_table_ref)
      #if self.stack_id_table_lhs:
      #   url_str += '&sidr_lhs=' + urllib.quote(self.stack_id_table_lhs)
      #if self.stack_id_table_rhs:
      #   url_str += '&sidr_rhs=' + urllib.quote(self.stack_id_table_rhs)
      # See next fcn. for
      #    only_stack_ids
      if self.only_system_id > 0:
         url_str += '&sysid=' + str(self.only_system_id)
      #    about_stack_ids
      #    only_lhs_stack_ids
      #    only_rhs_stack_ids
      if self.only_lhs_stack_id > 0:
         url_str += '&lhsd=' + str(self.only_lhs_stack_id)
      if self.only_rhs_stack_id > 0:
         url_str += '&rhsd=' + str(self.only_rhs_stack_id)
      # See next fcn. for
      #    only_associate_ids
      if self.context_stack_id > 0:
         url_str += '&ctxt=' + str(self.context_stack_id)
      # See next fcn. for
      #    only_item_type_ids
      #    only_lhs_item_types
      #    only_rhs_item_types
      if self.use_stealth_secret:
         url_str += '&stlh=' + urllib.quote(self.use_stealth_secret)
      if self.results_style:
         url_str += '&rezs=' + urllib.quote(self.results_style)
      if self.include_item_stack:
         url_str += '&istk=' + str(int(self.include_item_stack))
      if self.include_lhs_name:
         url_str += '&ilhn=' + str(int(self.include_lhs_name))
      if self.include_rhs_name:
         url_str += '&irhn=' + str(int(self.include_rhs_name))
      if self.rev_ids:
         url_str += '&rids=' + ','.join(str(x) for x in self.rev_ids)
      if self.include_geosummary:
         url_str += '&gsum=' + str(int(self.include_geosummary))
      if self.rev_min > 0:
         url_str += '&rmin=' + self.rev_min
      if self.rev_max > 0:
         url_str += '&rmax=' + self.rev_max
      if self.rating_restrict:
         url_str += '&ratr=' + str(int(self.rating_restrict))
      if self.rating_special:
         url_str += '&rats=' + str(int(self.rating_special))
      if self.min_access_level > 0:
         url_str += '&mnac=' + str(self.min_access_level)
      if self.max_access_level > 0:
         url_str += '&mxac=' + str(self.max_access_level)
      # Skipping:
      #    setting_multi_geometry
      #    only_in_multi_geometry
      # Skipping:
      #    skip_geometry_raw
      #    skip_geometry_svg
      #    skip_geometry_wkt
      #    make_geometry_ewkt
      #    gia_use_gids
      #    gia_userless
      #    gia_use_sessid
      if self.gia_use_sessid:
         url_str += '&guss=' + str(int(self.gia_use_sessid))
      if self.skip_tag_counts:
         url_str += '&ntcs=' + str(int(self.skip_tag_counts))
      if self.dont_load_feat_attcs:
         url_str += '&dlfa=' + str(int(self.dont_load_feat_attcs))
      if self.do_load_lval_counts:
         url_str += '&dllc=' + str(int(self.do_load_lval_counts))
      if self.include_item_aux:
         url_str += '&iaux=' + str(int(self.include_item_aux))
      if self.findability_ignore:
         url_str += '&bilt=' + str(int(self.findability_ignore))
      if self.findability_ignore_include_deleted:
         url_str += '&bild=' + (
            str(int(self.findability_ignore_include_deleted)))
      if self.findability_recent:
         url_str += '&bilr=' + str(int(self.findability_recent))
      if self.do_load_latest_note:
         url_str += '&dlln=' + str(int(self.do_load_latest_note))
      if self.exclude_byway_elevations:
         url_str += '&xbel=' + str(int(self.exclude_byway_elevations))
      if self.filter_by_value_boolean is not None:
         url_str += '&fbvb=' + str(int(self.filter_by_value_boolean))
      if self.filter_by_value_integer is not None:
         url_str += '&fbvi=' + str(int(self.filter_by_value_integer))
      if self.filter_by_value_real is not None:
         # FIXME/MEH/BUG nnnn: Implement filter_by_value_real.
         #                     And what about precision?
         url_str += '&fbvr=' + str(self.filter_by_value_real)
      #if self.filter_by_value_text:
      #   url_str += '&vtxt=' + urllib.quote(self.filter_by_value_text)
      if self.filter_by_value_text:
         url_str += '&fbvt=' + urllib.quote(self.filter_by_value_text)
      if self.filter_by_value_binary is not None:
         url_str += '&fbvx=' + str(self.filter_by_value_binary)
      if self.filter_by_value_date:
         url_str += '&fbvd=' + str(self.filter_by_value_date)
      if self.force_resolve_item_type:
         url_str += '&frit=' + str(int(self.force_resolve_item_type))
      return url_str

   #
   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::xml_append_filters
   def xml_append_filters(self, xml_doc):
      self.append_ids_compact(xml_doc, 'sids_gia', self.only_stack_ids)
      self.append_ids_compact(xml_doc, 'sids_abt', self.about_stack_ids)
      self.append_ids_compact(xml_doc, 'sids_lhs', self.only_lhs_stack_ids)
      self.append_ids_compact(xml_doc, 'sids_rhs', self.only_rhs_stack_ids)
      self.append_ids_compact(xml_doc, 'ids_assc', self.only_associate_ids)
      self.append_ids_compact(xml_doc, 'ids_itps', self.only_item_type_ids)
      # FIXME: Not used by flashclient: only_lhs_item_types/only_rhs_item_types
      self.append_ids_compact(xml_doc, 'ids_ltps', self.only_lhs_item_types)
      self.append_ids_compact(xml_doc, 'ids_rtps', self.only_rhs_item_types)

   #
   # SYNC_ME: GWIS. See gwis/utils/Query_Filters.as::append_ids_compact
   def append_ids_compact(self, xml_doc, doc_name, stack_ids_s):
      if stack_ids_s:
         # stack_ids_docs.tag == doc_name
         stack_ids_docs = etree.Element(doc_name)
         stack_ids_docs.text = stack_ids_s
         xml_doc.append(stack_ids_docs)

   # *** 

   # 
   def limit_clause(self):
      limit_clause = ""
      if self.pagin_count > 0:
         limit_clause = ("LIMIT %d" % (self.pagin_count,))
      return limit_clause

   # 
   def offset_clause(self):
      offset_clause = ""
      if self.pagin_offset > 0:
         offset_clause = ("OFFSET %d" % (self.pagin_offset,))
      return offset_clause

   # ***

   #
   def fix_missing(self):
      # If you add members to this class after pickling an object of this
      # class, when you unpickle it, any members you've since added to the
      # class definition will be unset.
      reference = Query_Filters(None)
      #
      for mbr in Query_Filters.__after_slots__:
         try:
            getattr(self, mbr)
         except AttributeError:
            setattr(self, mbr, getattr(reference, mbr))
      log.verbose('fix_missing: %s' % (self,))
      # If you change attribute changes, though, you'll want to increment the
      # "version pickled" and do any version translating here.
      g.assurt(self.ver_pickled == 1)

   #
   def get_fetch_size_adj(self):
      # This is just a debug fcn. Don't worry too much about it.
      # It gives the DEV a general idea how big of a query to expect.
      adj = ''
      if (   self.only_in_multi_geometry
          or self.filter_by_username
          or self.filter_by_regions
          or self.filter_by_watch_geom
          or self.filter_by_watch_item
          or self.filter_by_watch_feat
          or self.filter_by_unread
          or self.filter_by_names_exact
          or self.filter_by_text_exact
          or self.filter_by_text_loose
          or self.filter_by_text_smart
          or self.filter_by_text_full
          or self.filter_by_nearby_edits
          or self.filter_by_thread_type
          or self.filter_by_creator_include
          or self.filter_by_creator_exclude
          or self.only_lhs_stack_ids
          or self.only_rhs_stack_ids
          or self.only_lhs_stack_id
          or self.only_rhs_stack_id
          or self.filter_by_value_text
          ):
         adj = 'some'
      elif self.pagin_count:
         adj = '%d (pcnt)' % self.pagin_count
      elif self.only_stack_ids:
         adj = '%d (ostk)' % (self.only_stack_ids.count(',') + 1,)
      elif self.only_system_id:
         adj = '1 (osys)'
      elif self.about_stack_ids:
         adj = '%d (astk)' % (self.about_stack_ids.count(',') + 1,)
      elif self.only_associate_ids:
         adj = '%d (asss)' % (self.only_associate_ids.count(',') + 1,)
      elif self.context_stack_id:
         adj = 'one'
      #elif self.only_item_type_ids:
      #   adj = '%d' % self.only_item_type_ids
      #elif (self.only_lhs_item_types
      #    or self.only_rhs_item_types):
      #   adj = 'a lot of'
      else:
         adj = 'all'
      return adj

   #
   def get_id_count(self, item_type, gwis_errs):
      # This fcn. is used to count the number of stack IDs in the request, so
      # we can deny really large requests.
      id_count = 1
      if ((item_type == 'link_value')
          or (item_type == 'link_geofeature')):
         # NOTE: We don't consider the count of LHS IDs because they are 
         #       the ones that are applied liberally. We only care about
         #       the RHS IDs, which has more impact on the number of
         #       results.
         # NOTE: We'll pass if the string is non-empty. If it doesn't
         #       actually contain integers, we'll except on it later.
         if self.only_rhs_stack_ids:
            id_count += self.only_rhs_stack_ids.count(',')
         # BUG nnnn: 2013.03.27: [lb] needs to relax this for
         #           /item/alert_email. We used to not honor client
         #           requests for link_values with just lhs_stack_id
         #           without a bbox because, e.g., speed_limit could
         #           return tens of thousands of results. But for
         #           alert_email we need to search on lhs stack ID.
         # MAYBE: Make a lookup of lhs IDs that are okay for this type
         #        of checkout, and then redo gwis_errs for the others.
         #        Or could we impose, say, LIMIT 10000?
         elif self.only_lhs_stack_ids:
            id_count += self.only_lhs_stack_ids.count(',')
         else:
            id_count = 0
         if ((self.only_stack_ids) 
             or (self.only_associate_ids)):
            gwis_errs.append('Mixing disassociated StackId queries/1 (%s).'
                             % (item_type,))
            id_count = -1
      else:
         if (self.only_stack_ids 
             or self.only_associate_ids):
            # FIXME: Add 1 for only_associate_ids if set?
            id_count += (self.only_stack_ids.count(',')
                        + self.only_associate_ids.count(','))
         else:
            id_count = 0
         if ((self.only_stack_ids 
              and self.only_associate_ids)
             or self.only_lhs_stack_ids
             or self.only_rhs_stack_ids):
            gwis_errs.append('Mixing disassociated StackId requests/2 (%s)'
                             % (item_type,))
            id_count = -1
         # 2014.05.09: We can mix system_ids and stack_ids, right?
         if self.only_system_id:
            id_count += 1
      # 2013.04.30: The stealth_secret should count as a single ID.
      if self.use_stealth_secret:
         id_count += 1
         if id_count != 1:
            gwis_errs.append('Mixing disassociated StackId requests/3 (%s)'
                             % (item_type,))
      return id_count

   #
   def verify_filters(self, req):
      if not (    req.client.request_is_local
              and req.client.request_is_script
              and req.client.request_is_secret):
         # This is a remote user, so make sure they don't game the system.
         if self.min_access_level:
            self.verify_access_level(self.min_access_level, 'mnac')
         if self.max_access_level:
            self.verify_access_level(self.max_access_level, 'mxac')

   #
   def verify_access_level(self, access_level_id, filter_abbrev):
      # The access level should be valid and not less than client, which is
      # what we normal use as the min access level when searching.
      if ((not Access_Level.is_valid(access_level_id))
            or (access_level_id > Access_Level.client)):
         raise GWIS_Error('Illegal value for "%s": %s.'
                          % (filter_abbrev, access_level_id,))

   # ***

# ***

#
if (__name__ == '__main__'):
   pass

