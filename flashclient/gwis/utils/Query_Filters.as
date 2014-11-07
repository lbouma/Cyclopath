/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.utils {

   import flash.geom.Point;

   import items.Geofeature;
   import items.Item_Revisioned;
   import items.utils.Stack_Id_Array;
   import utils.geom.Dual_Rect;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;

   public class Query_Filters {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Q_Filts');

      // *** Instance attributes

      // SYNC_ME: Search Query_Filters

      // *** These variables match those in pyserver.

      // NOTE: Skipping pyserver's
      //         ver_pickled

      // Pagination.
      public var pagin_total:Boolean = false;
      public var pagin_count:int = 0;
      public var pagin_offset:int = 0;

      // Result ordering. Not supported.
      //public var result_order:String = '';

      // The search center, for map searches. Results are ordered by distance
      // from this point.
      public var centered_at:Point = new Point();
      // NOTE: In pyserver, centered_at is represented by the two ints:
      //         centerx
      //         centery

      // Search, Discussions, and Recent Changes filters.
      public var filter_by_username:String = '';
      public var filter_by_regions:String = '';
      public var filter_by_watch_geom:Boolean = false;
      public var filter_by_watch_item:int = 0;
      public var filter_by_watch_feat:Boolean = false;
      public var filter_by_unread:Boolean = false;
      public var filter_by_names_exact:String = '';
      public var filter_by_text_exact:String = '';
      public var filter_by_text_loose:String = '';
      public var filter_by_text_smart:String = '';
      // Skipping filter_by_text_full
      public var filter_by_nearby_edits:Boolean = false;

// FIXME: route reactions. this is really just only_rhs_stack_ids ==
//        the /post/revision attribute, isn't it?
      public var filter_by_thread_type:String = '';

      // MAYBE: Replace filter_by_username with these two:
      public var filter_by_creator_include:String = '';
      public var filter_by_creator_exclude:String = '';

      // Skipping pyserver's stack_id_table_ref/_lhs/_rhs

      // Specific Stack IDs -- All Items.
      public var only_stack_ids:Stack_Id_Array = new Stack_Id_Array();
      // Fetch a specific item version from some unknown revision.
      public var only_system_id:int = 0;

      // For "About items in visible area" filter for discussions.
      // MAYBE: Allow other items to use similar, e.g., recent changes
      //        panel has similar filter.
      //        Search: 'Filter by what is visible in the map'
      //                 in get_filter_by_data_provider().
      public var about_stack_ids:Stack_Id_Array = new Stack_Id_Array();

      // Specific Stack IDs -- Link_Values.
      public var only_lhs_stack_ids:Stack_Id_Array = new Stack_Id_Array();
      public var only_rhs_stack_ids:Stack_Id_Array = new Stack_Id_Array();
      // NOTE: Missing pyserver's
      //         only_lhs_stack_id
      //         only_rhs_stack_id

      // Not supported in flashclient: value_* filters
      //   e.g., 'filter_by_value_text'

      // Specific Stack IDs -- Nonwiki Items.
      public var only_associate_ids:Stack_Id_Array = new Stack_Id_Array();
      public var context_stack_id:int = 0;
      // NOTE: This is called only_item_type_ids in pyserver.
      public var only_item_types:Array = new Array();
      // NOTE: Skipping pyserver
      //         only_lhs_item_types
      //         only_rhs_item_types

      // Stealth secret.
      public var use_stealth_secret:String = '';

      public var results_style:String = '';
      public var include_item_stack:Boolean = false;

      public var include_lhs_name:Boolean = false;
      public var include_rhs_name:Boolean = false;

      // History filters.
      public var rev_ids:Array = new Array();
      public var include_geosummary:Boolean = false;
      // FIXME: These might get deleted soon.
      public var rev_min:int = 0;
      public var rev_max:int = 0;

      // FIXME: Implement herein:
      public var rating_restrict:Boolean = false; // Use leafy branch user rats

      public var min_access_level:int = 0;
      public var max_access_level:int = 0;

      // NOTE: Skipping pyserver's
      //         only_in_multi_geometry
      //         setting_multi_geometry
      //         skip_geometry_raw
      //         skip_geometry_svg
      //         skip_geometry_wkt
      //         gia_use_gids
      public var gia_use_sessid:Boolean = false; // Find items w/ Session ID

      // FIXME: skip_tag_counts should be do_load_tag_counts
      public var skip_tag_counts:Boolean = false; // Don't add up tag cnts
      // FIXME: dont_load_feat_attcs should be do_load_feat_attcs
      public var dont_load_feat_attcs:Boolean = false; // Don't load attrs/tags
      public var do_load_lval_counts:Boolean = false; // Fetch lval cnts
      public var include_item_aux:Boolean = false; //

      public var findability_ignore:Boolean = false; //
      public var findability_ignore_include_deleted:Boolean = false; //
      public var findability_recent:Boolean = false; //

      public var do_load_latest_note:Boolean = false; // Not implemented/used.

      // *** These variables are flashclient-only.

      // Adding flashclient-specific:
      // Flashclient- and GWIS_Checkout_Base-specific
      // FIXME: Get_Rev uses this. Also, are these redundant? We calculate the
      //        same rects when we do a viewport update, but they are stored
      //        locally in the update class and are not stored here (and to
      //        keep things consistent and simple, I [lb] think the update
      //        class should just use the slots here).
      //        Note also that pyserver uses query_viewport, and doesn't have
      //        these in query_filters.
      public var include_rect:Dual_Rect = null;
      public var exclude_rect:Dual_Rect = null;

      // FIXME:
      // public var rev:utils.rev_spec.Base = null;

      // *** Constructor

      public function Query_Filters() :void
      {
         this.centered_at = new Point();
         m4_ASSERT(this.centered_at.x == 0);
         m4_ASSERT(this.centered_at.y == 0);
      }

      // Makes a new copy of this Link_Value. The ID and version are not
      // copied, nor is the new item inserted into the map.
      public function clone() :Query_Filters
      {
         var cl:Query_Filters = new Query_Filters();
         cl.pagin_total = this.pagin_total;
         cl.pagin_count = this.pagin_count;
         cl.pagin_offset = this.pagin_offset;
         cl.centered_at = this.centered_at.clone();
         cl.filter_by_username = this.filter_by_username;
         cl.filter_by_regions = this.filter_by_regions;
         cl.filter_by_watch_geom = this.filter_by_watch_geom;
         cl.filter_by_watch_item = this.filter_by_watch_item;
         cl.filter_by_watch_feat = this.filter_by_watch_feat;
         cl.filter_by_unread = this.filter_by_unread;
         cl.filter_by_names_exact = this.filter_by_names_exact;
         cl.filter_by_text_exact = this.filter_by_text_exact;
         cl.filter_by_text_loose = this.filter_by_text_loose;
         cl.filter_by_text_smart = this.filter_by_text_smart;
         cl.filter_by_nearby_edits = this.filter_by_nearby_edits;
         cl.filter_by_thread_type = this.filter_by_thread_type;
         cl.filter_by_creator_include = this.filter_by_creator_include;
         cl.filter_by_creator_exclude = this.filter_by_creator_exclude;
         cl.only_stack_ids = this.only_stack_ids.array_copy();
         cl.only_system_id = this.only_system_id;
         cl.about_stack_ids = this.about_stack_ids.array_copy();
         cl.only_lhs_stack_ids = this.only_lhs_stack_ids.array_copy();
         cl.only_rhs_stack_ids = this.only_rhs_stack_ids.array_copy();
         cl.only_associate_ids = this.only_associate_ids.array_copy();
         cl.context_stack_id = this.context_stack_id;
         cl.only_item_types = Collection.array_copy(this.only_item_types);
         cl.use_stealth_secret = this.use_stealth_secret;
         cl.results_style = this.results_style;
         cl.include_item_stack = this.include_item_stack;
         cl.include_lhs_name = this.include_lhs_name;
         cl.include_rhs_name = this.include_rhs_name;
         cl.rev_ids = Collection.array_copy(this.rev_ids);
         cl.include_geosummary = this.include_geosummary;
         cl.rev_min = this.rev_min;
         cl.rev_max = this.rev_max;
         cl.rating_restrict = this.rating_restrict;
         cl.min_access_level = this.min_access_level;
         cl.max_access_level = this.max_access_level;

         cl.gia_use_sessid = this.gia_use_sessid;
         cl.skip_tag_counts = this.skip_tag_counts;
         cl.dont_load_feat_attcs = this.dont_load_feat_attcs;
         cl.do_load_lval_counts = this.do_load_lval_counts;
         cl.include_item_aux = this.include_item_aux;
         cl.findability_ignore = this.findability_ignore;
         cl.findability_ignore_include_deleted
            = this.findability_ignore_include_deleted;
         cl.findability_recent = this.findability_recent;
         cl.do_load_latest_note = this.do_load_latest_note;

         //m4_DEBUG3('clone: this.include_rect:',
         //          (this.include_rect !== null)
         //          ? this.include_rect.toString() : 'null');
         cl.include_rect = this.include_rect;
         cl.exclude_rect = this.exclude_rect;

         return cl;
      }

      //
      public function equals(other:Query_Filters) :Boolean
      {
         var equals:Boolean = (true
            && (this.pagin_total == other.pagin_total)
            && (this.pagin_count == other.pagin_count)
            && (this.pagin_offset == other.pagin_offset)
            && (((this.centered_at === null)
                 && (other.centered_at === null))
                || ((this.centered_at !== null)
                    && (other.centered_at !== null)
                    && (this.centered_at.equals(other.centered_at))))
            && (this.filter_by_username == other.filter_by_username)
            && (this.filter_by_regions == other.filter_by_regions)
            && (this.filter_by_watch_geom == other.filter_by_watch_geom)
            && (this.filter_by_watch_item == other.filter_by_watch_item)
            && (this.filter_by_watch_feat == other.filter_by_watch_feat)
            && (this.filter_by_unread == other.filter_by_unread)
            && (this.filter_by_names_exact == other.filter_by_names_exact)
            && (this.filter_by_text_exact == other.filter_by_text_exact)
            && (this.filter_by_text_loose == other.filter_by_text_loose)
            && (this.filter_by_text_smart == other.filter_by_text_smart)
            && (this.filter_by_nearby_edits == other.filter_by_nearby_edits)
            && (this.filter_by_thread_type == other.filter_by_thread_type)
            && (this.filter_by_creator_include
                == other.filter_by_creator_include)
            && (this.filter_by_creator_exclude
                == other.filter_by_creator_exclude)
            && (Stack_Id_Array.array_eq(this.only_stack_ids,
                                        other.only_stack_ids))
            && (this.only_system_id == other.only_system_id)
            && (Stack_Id_Array.array_eq(this.about_stack_ids,
                                        other.about_stack_ids))
            && (Stack_Id_Array.array_eq(this.only_lhs_stack_ids,
                                        other.only_lhs_stack_ids))
            && (Stack_Id_Array.array_eq(this.only_rhs_stack_ids,
                                        other.only_rhs_stack_ids))
            && (Stack_Id_Array.array_eq(this.only_associate_ids,
                                        other.only_associate_ids))
            && (this.context_stack_id == other.context_stack_id)
            && (Collection.array_eq(this.only_item_types,
                                    other.only_item_types))
            && (this.use_stealth_secret == other.use_stealth_secret)
            && (this.results_style == other.results_style)
            && (this.include_item_stack == other.include_item_stack)
            && (this.include_lhs_name == other.include_lhs_name)
            && (this.include_rhs_name == other.include_rhs_name)
            && (Collection.array_eq(this.rev_ids, other.rev_ids))
            && (this.include_geosummary == other.include_geosummary)
            && (this.rev_min == other.rev_min)
            && (this.rev_max == other.rev_max)
            && (this.rating_restrict == other.rating_restrict)
            && (this.min_access_level == other.min_access_level)
            && (this.max_access_level == other.max_access_level)
            && (this.gia_use_sessid == other.gia_use_sessid)
            && (this.skip_tag_counts == other.skip_tag_counts)
            && (this.dont_load_feat_attcs == other.dont_load_feat_attcs)
            && (this.do_load_lval_counts == other.do_load_lval_counts)
            && (this.include_item_aux == other.include_item_aux)
            && (this.findability_ignore == other.findability_ignore)
            && (this.findability_ignore_include_deleted
                == other.findability_ignore_include_deleted)
            && (this.findability_recent == other.findability_recent)
            && (this.do_load_latest_note == other.do_load_latest_note)
            && (((this.include_rect === null)
                 && (other.include_rect === null))
                || ((this.include_rect !== null)
                    && (other.include_rect !== null)
                    && (this.include_rect.eq(other.include_rect))))
            && (((this.exclude_rect === null)
                 && (other.exclude_rect === null))
                || ((this.exclude_rect !== null)
                    && (other.exclude_rect !== null)
                    && (this.exclude_rect.eq(other.exclude_rect))))
            );
         return equals;
      }

      //
      // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_url
      // SYNC_ME: GWIS. See gwis/query_filters.py::url_append_filters
      public function url_append_filters(url_str:String) :String
      {
         if (this.pagin_total) {
            url_str += '&cnts=' + int(this.pagin_total);
            // Cannot mix pageination and counts... but that's just for
            // GWIS_Checkout. Other commands, like GWIS_Revision_History_Get,
            // let you mix getting a page of results and also getting a total
            // could of results.
            //  m4_ASSERT(this.pagin_count == 0);
         }
         if (this.pagin_count > 0) {
            if (this.pagin_count > 0) {
               // This if-block is just for looks, er, parallelism with the
               // next if-block.
               url_str += '&rcnt=' + this.pagin_count;
            }
            if (this.pagin_offset > 0) {
               url_str += '&roff=' + this.pagin_offset;
            }
            // Cannot mix pageination and counts.
            // See comments above re: mixing pagin_total and pagin_count.
            //  m4_ASSERT(this.pagin_total == 0);
         }
         // NOTE: I [lb] don't think x,y = 0,0 is valid, so this is okay.
         // 20111004: this.centered_at is null on startup: race condition.
         //      i think i fixed this; make bug
         if ((this.centered_at.x != 0) && (this.centered_at.y != 0)) {
            url_str += '&ctrx=' + this.centered_at.x
                     + '&ctry=' + this.centered_at.y;
         }
         if (this.filter_by_username != '') {
            url_str += '&busr=' + encodeURIComponent(this.filter_by_username);
         }
         if (this.filter_by_regions != '') {
            url_str += '&nrgn=' + encodeURIComponent(this.filter_by_regions);
         }
         if (this.filter_by_watch_geom) {
            url_str += '&wgeo=' + int(this.filter_by_watch_geom);
         }
         if (this.filter_by_watch_item) {
            url_str += '&witm=' + this.filter_by_watch_item;
         }
         if (this.filter_by_watch_feat) {
            url_str += '&woth=' + int(this.filter_by_watch_feat);
         }
         if (this.filter_by_unread) {
            url_str += '&unrd=' + int(this.filter_by_unread);
         }
         if (this.filter_by_names_exact != '') {
            url_str += '&nams='
                       + encodeURIComponent(this.filter_by_names_exact);
         }
         if (this.filter_by_text_exact != '') {
            url_str += '&mtxt='
                       + encodeURIComponent(this.filter_by_text_exact);
         }
         if (this.filter_by_text_loose != '') {
            url_str += '&ltxt='
                       + encodeURIComponent(this.filter_by_text_loose);
         }
         if (this.filter_by_text_smart != '') {
            url_str += '&ftxt='
                       + encodeURIComponent(this.filter_by_text_smart);
         }
         if (this.filter_by_nearby_edits) {
            url_str += '&nrby=' + int(this.filter_by_nearby_edits);
         }
         if (this.filter_by_thread_type != '') {
            url_str += '&tdtp=' + this.filter_by_thread_type;
         }
         if (this.filter_by_creator_include != '') {
            url_str += '&fbci=' + this.filter_by_creator_include;
         }
         if (this.filter_by_creator_exclude != '') {
            url_str += '&fbce=' + this.filter_by_creator_exclude;
         }
         // See next fcn. for
         //    only_stack_ids
         if (this.only_system_id) {
            url_str += '&sysid=' + int(this.only_system_id);
         }
         //    about_stack_ids
         //    only_lhs_stack_ids
         //    only_rhs_stack_ids
         //    only_associate_ids
         if (this.context_stack_id > 0) {
            url_str += '&ctxt=' + this.context_stack_id;
         }
         // See next fcn. for
         //    only_item_types
         if (this.use_stealth_secret != '') {
            url_str += '&stlh=' + this.use_stealth_secret;
         }
         if (this.results_style != '') {
            url_str += '&rezs=' + this.results_style;
         }
         if (this.include_item_stack) {
            url_str += '&istk=' + int(this.include_item_stack);
         }
         if (this.include_lhs_name) {
            url_str += '&ilhn=' + int(this.include_lhs_name);
         }
         if (this.include_rhs_name) {
            url_str += '&irhn=' + int(this.include_rhs_name);
         }
         if (this.rev_ids.length > 0) {
            url_str += '&rids=' + this.rev_ids.join(',');
         }
         if (this.include_geosummary) {
            url_str += '&gsum=' + int(this.include_geosummary);
         }
         if (this.rev_min > 0) {
            url_str += '&rmin=' + this.rev_min;
         }
         if (this.rev_max > 0) {
            url_str += '&rmax=' + this.rev_max;
         }
         if (this.rating_restrict) {
            url_str += '&ratr=' + int(this.rating_restrict);
         }
         if (this.min_access_level) {
            url_str += '&mnac=' + int(this.min_access_level);
         }
         if (this.max_access_level) {
            url_str += '&mxac=' + int(this.max_access_level);
         }
         if (this.gia_use_sessid) {
            url_str += '&guss=' + int(this.gia_use_sessid);
         }
         if (this.skip_tag_counts) {
            url_str += '&ntcs=' + int(this.skip_tag_counts);
         }
         if (this.dont_load_feat_attcs) {
            url_str += '&dlfa=' + int(this.dont_load_feat_attcs);
         }
         if (this.do_load_lval_counts) {
            url_str += '&dllc=' + int(this.do_load_lval_counts);
         }
         if (this.include_item_aux) {
            url_str += '&iaux=' + int(this.include_item_aux);
         }
         if (this.findability_ignore) {
            url_str += '&bilt=' + int(this.findability_ignore);
         }
         if (this.findability_ignore_include_deleted) {
            url_str += '&bild=' + int(this.findability_ignore_include_deleted);
         }
         if (this.findability_recent) {
            url_str += '&bilr=' + int(this.findability_recent);
         }
         if (this.do_load_latest_note) {
            url_str += '&dlln=' + int(this.do_load_latest_note);
         }
         if (this.include_rect !== null) {
            if (this.include_rect.valid) {
               url_str += '&bbxi=' + this.include_rect.gwis_bbox_str;
            }
            else {
               m4_ERROR2('Unexpected: invalid include_rect:',
                         this.include_rect.toString());
               m4_DEBUG(Introspect.stack_trace());
            }
         }
         // FIXME: BBox_exclude is a Hack: when the user pans, the exclude
         //        region is an L-shaped object, not just a simple rectangle.
         if (this.exclude_rect !== null) {
            if (this.exclude_rect.valid) {
               url_str += '&bbxe=' + this.exclude_rect.gwis_bbox_str;
            }
            else {
               m4_ERROR2('Unexpected: invalid exclude_rect:',
                         this.exclude_rect.toString());
               m4_DEBUG(Introspect.stack_trace());
            }
         }
         return url_str;
      }

      //
      // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_xml
      // SYNC_ME: GWIS. See gwis/query_filters.py::xml_append_filters
      public function xml_append_filters(xml_doc:XML) :void
      {
         var gf:Geofeature;
         //
         if (this.only_stack_ids.length > 0) {
            this.append_ids_compact(xml_doc, 'sids_gia',
                                    this.only_stack_ids);
         }
         //
         if (this.about_stack_ids.length > 0) {
            this.append_ids_compact(xml_doc, 'sids_abt',
                                    this.about_stack_ids);
         }
         //
         if (this.only_lhs_stack_ids.length > 0) {
            this.append_ids_compact(xml_doc, 'sids_lhs',
                                    this.only_lhs_stack_ids);
         }
         //
         if (this.only_rhs_stack_ids.length > 0) {
            this.append_ids_compact(xml_doc, 'sids_rhs',
                                    this.only_rhs_stack_ids);
         }
         //
         if (this.only_associate_ids.length > 0) {
            m4_DEBUG('... find this.only_associate_ids');
            this.append_ids_compact(xml_doc, 'ids_assc',
                                    this.only_associate_ids);
         }
         // only_item_types is only_item_type_ids in pyserver.
         if (this.only_item_types.length > 0) {
            m4_DEBUG('... find this.only_item_types');
            this.append_ids_compact(xml_doc, 'ids_itps',
                                    this.only_item_types);
         }
      }

      //
      // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_xml
      // SYNC_ME: GWIS. See gwis/query_filters.py::append_ids_compact
      public function append_ids_compact(
         xml_doc:XML,
         doc_name:String,
         the_ids:Array)
            :void
      {
         Query_Filters.append_ids_compact(xml_doc, doc_name, the_ids);
      }

      //
      public static function append_ids_compact(
         xml_doc:XML,
         doc_name:String,
         the_ids:Array)
            :void
      {
         m4_DEBUG('append_ids_compact: doc_name:', doc_name);
         // CAVEAT: Flex doesn't like this:
         //            var sids_doc:XML = new XML();
         //         If you setName, nothing; If you appendChild(), it's empty.
         //         But var sids_doc:XML = <foo/>; works just fine... ug....
         var sids_doc:XML = <foo/>; // Avoid new XML() so setName() works.
         sids_doc.setName(doc_name);
         m4_ASSERT(the_ids.length > 0);
         // In Flex, appendChild works on both XMLs and strings (to set
         // attrs (former) or to set the text (latter)). In Python, there
         // are two separate fcns., .append and .text.
         sids_doc.appendChild(the_ids.join(","));
         xml_doc.appendChild(sids_doc);
      }

      // ***

      //
      public function toString() :String
      {
         var stringified:String = this.url_append_filters('');
         if (this.only_stack_ids.length > 0) {
            stringified += '&sids_gia=' + this.only_stack_ids.join(",");
         }
         //
         if (this.about_stack_ids.length > 0) {
            stringified += '&sids_abt=' + this.about_stack_ids.join(",");
         }
         //
         if (this.only_lhs_stack_ids.length > 0) {
            stringified += '&sids_lhs=' + this.only_lhs_stack_ids.join(",");
         }
         //
         if (this.only_rhs_stack_ids.length > 0) {
            stringified += '&sids_rhs=' + this.only_rhs_stack_ids.join(",");
         }
         //
         if (this.only_associate_ids.length > 0) {
            stringified += '&ids_assc=' + this.only_associate_ids.join(",");
         }
         // only_item_types is only_item_type_ids in pyserver.
         if (this.only_item_types.length > 0) {
            stringified += '&ids_itps=' + this.only_item_types.join(",");
         }
         return stringified;
      }

   }
}

