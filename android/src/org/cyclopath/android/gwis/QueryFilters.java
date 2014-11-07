/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.gwis;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;

import org.cyclopath.android.util.Dual_Rect;

import android.graphics.Point;

/**
 * This class specifies the general filters to be used in GWIS queries.
 * It is based in part on Query_Filters.as
 * FIXME: This class should be reviewed once changes to the FlashClient are
 * finished
 * @author Fernando Torre
 *
 */
public class QueryFilters {

   // *** These variables match those in pyserver
   
   // Pagination
   public boolean pagin_total = false;
   public int pagin_count = 0;
   public int pagin_offset = 0;
   
   // The search center, for map searches. Results are ordered by distance
   // from this point.
   public Point centered_at = null;
   // NOTE: In pyserver, centered_at is represented by the two ints:
   //         centerx
   //         centery

   // Search, Discussions, and Recent Changes filters.
   public String filter_by_username = "";
   public String filter_by_regions = "";
   public boolean filter_by_unread = false;
   public boolean filter_by_watched = false;
   public String filter_by_text_exact = "";
   public String filter_by_text_loose = "";
   public String filter_by_text_smart = "";
   public boolean filter_by_nearby_edits = false;

   public String filter_by_creator_include = "";
   public String filter_by_creator_exclude = "";

   // Specific Stack IDs -- All Items.
   public int[] only_stack_ids = new int[0];

   // Specific Stack IDs -- Link_Values.
   public int[] only_lhs_stack_ids = new int[0];
   public int[] only_rhs_stack_ids = new int[0];
   // NOTE: Missing pyserver's 
   //         only_lhs_stack_id
   //         only_rhs_stack_id

   // Specific Stack IDs -- Selected Items.
   // This parameter is flashclient-only.
   public boolean only_selected_items = false;

   // Specific Stack IDs -- Nonwiki Items.
   public int[]  only_associate_ids = new int[0];
   public int context_stack_id = 0;
   // NOTE: This is called only_item_type_ids in pyserver.
   public int[] only_item_types = new int[0];
   // NOTE: Skipping pyserver
   //         only_lhs_item_types
   //         only_rhs_item_types

   public String results_style = "";
   public boolean include_item_stack = false;

   public int min_access_level = 0;
   public int max_access_level = 0;

   // FIXME: skip_tag_counts should be do_load_tag_counts
   public boolean skip_tag_counts = false; // Don't add up tag cnts
   // FIXME: dont_load_feat_attcs should be do_load_feat_attcs
   public boolean dont_load_feat_attcs = false; // Don't load attrs/tags
   public boolean do_load_lval_counts = false; // Fetch lval cnts
   public boolean include_item_aux = false; // 
   public boolean do_load_latest_note = false; // 


   public Dual_Rect include_rect = null;
   public Dual_Rect exclude_rect = null;

   /**
    * Constructor
    */
   public QueryFilters() {
   }

   @Override
   /**
    * Makes a new copy of this QueryFilters object.
    */
   public QueryFilters clone() {
      QueryFilters cl = new QueryFilters();
      cl.pagin_total = this.pagin_total;
      cl.pagin_count = this.pagin_count;
      cl.pagin_offset = this.pagin_offset;
      cl.centered_at = new Point(this.centered_at.x, this.centered_at.y);
      cl.filter_by_username = this.filter_by_username;
      cl.filter_by_regions = this.filter_by_regions;
      cl.filter_by_unread = this.filter_by_unread;
      cl.filter_by_watched = this.filter_by_watched;
      cl.filter_by_text_exact = this.filter_by_text_exact;
      cl.filter_by_text_loose = this.filter_by_text_loose;
      cl.filter_by_text_smart = this.filter_by_text_smart;
      cl.filter_by_nearby_edits = this.filter_by_nearby_edits;
      cl.filter_by_creator_include = this.filter_by_creator_include;
      cl.filter_by_creator_exclude = this.filter_by_creator_exclude;
      cl.only_stack_ids = this.only_stack_ids.clone();
      cl.only_lhs_stack_ids = this.only_lhs_stack_ids.clone();
      cl.only_rhs_stack_ids = this.only_rhs_stack_ids.clone();
      cl.only_selected_items = this.only_selected_items;
      cl.only_associate_ids = this.only_associate_ids.clone();
      cl.context_stack_id = this.context_stack_id;
      cl.only_item_types = this.only_item_types.clone();
      cl.results_style = this.results_style;
      cl.include_item_stack = this.include_item_stack;
      cl.min_access_level = this.min_access_level;
      cl.max_access_level = this.max_access_level;

      cl.skip_tag_counts = this.skip_tag_counts;
      cl.dont_load_feat_attcs = this.dont_load_feat_attcs;
      cl.do_load_lval_counts = this.do_load_lval_counts;
      cl.include_item_aux = this.include_item_aux;
      cl.do_load_latest_note = this.do_load_latest_note;

      cl.include_rect = this.include_rect;
      cl.exclude_rect = this.exclude_rect;

      return cl;
   }

   /**
    * Compares two QueryFilters objects
    * @param other
    * @return
    */
   public boolean equals(QueryFilters other) {
      boolean equals = (true
         && (this.pagin_total == other.pagin_total)
         && (this.pagin_count == other.pagin_count)
         && (this.pagin_offset == other.pagin_offset)
         && (this.centered_at == other.centered_at)
         && (this.filter_by_username == other.filter_by_username)
         && (this.filter_by_regions == other.filter_by_regions)
         && (this.filter_by_unread == other.filter_by_unread)
         && (this.filter_by_watched == other.filter_by_watched)
         && (this.filter_by_text_exact == other.filter_by_text_exact)
         && (this.filter_by_text_loose == other.filter_by_text_loose)
         && (this.filter_by_text_smart == other.filter_by_text_smart)
         && (this.filter_by_nearby_edits == other.filter_by_nearby_edits)
         && (this.filter_by_creator_include
             == other.filter_by_creator_include)
         && (this.filter_by_creator_exclude
             == other.filter_by_creator_exclude)
         && (this.only_stack_ids == other.only_stack_ids)
         && (this.only_lhs_stack_ids == other.only_lhs_stack_ids)
         && (this.only_rhs_stack_ids == other.only_rhs_stack_ids)
         && (this.only_selected_items == other.only_selected_items)
         && (this.only_associate_ids == other.only_associate_ids)
         && (this.context_stack_id == other.context_stack_id)
         && (this.only_item_types == other.only_item_types)
         && (this.results_style == other.results_style)
         && (this.include_item_stack == other.include_item_stack)
         // FIXME: Does == work on Array?
         //&& (this.rev_ids == other.rev_ids)\
         && (this.min_access_level == other.min_access_level)
         && (this.max_access_level == other.max_access_level)
         && (this.skip_tag_counts == other.skip_tag_counts)
         && (this.dont_load_feat_attcs == other.dont_load_feat_attcs)
         && (this.do_load_lval_counts == other.do_load_lval_counts)
         && (this.include_item_aux == other.include_item_aux)
         && (this.do_load_latest_note == other.do_load_latest_note)
         && (this.include_rect == other.include_rect)
         && (this.exclude_rect == other.exclude_rect));
      return equals;
   }

   // 
   // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_url
   // SYNC_ME: GWIS. See gwis/query_filters.py::url_append_filters
   public String url_append_filters(String url_str) {
      if (this.pagin_total) {
         url_str += "&cnts=" + (this.pagin_total? 1 : 0);
      }
      if (this.pagin_count > 0) {
         url_str += "&rcnt=" + this.pagin_count;
         if (this.pagin_offset > 0) {
            url_str += "&roff=" + this.pagin_offset;
         }
      }
      // NOTE: I [lb] don't think x,y = 0,0 is valid, so this is okay.
      // 20111004: this.centered_at is null on startup: race condition.
      //      i think i fixed this; make bug
      if (this.centered_at != null) {
         url_str += "&ctrx=" + this.centered_at.x
                  + "&ctry=" + this.centered_at.y;
      }

      try {
         if (!this.filter_by_username.equals("")
               && this.filter_by_username != null) {
            url_str += "&busr="
                        + URLEncoder.encode(this.filter_by_username,"UTF-8");
         }
         if (!this.filter_by_regions.equals("")
               && this.filter_by_regions != null) {
            url_str += "&nrgn=" 
                        + URLEncoder.encode(this.filter_by_regions,"UTF-8");
         }
         if (this.filter_by_unread) {
            url_str += "&unrd=" + (this.filter_by_unread? 1 : 0);
         }
         if (this.filter_by_watched) {
            url_str += "&wchd=" + (this.filter_by_watched? 1 : 0);
         }
         if (!this.filter_by_text_exact.equals("")
               && this.filter_by_text_exact != null) {
            url_str += "&mtxt=" 
                       + URLEncoder.encode(this.filter_by_text_exact,"UTF-8");
         }
         if (!this.filter_by_text_loose.equals("")
               && this.filter_by_text_loose != null) {
            url_str += "&ltxt=" 
                       + URLEncoder.encode(this.filter_by_text_loose,"UTF-8");
         }
         if (!this.filter_by_text_smart.equals("")
               && this.filter_by_text_smart != null) {
            url_str += "&ftxt=" 
                       + URLEncoder.encode(this.filter_by_text_smart,"UTF-8");
         }
         if (this.filter_by_nearby_edits) {
            url_str += "&nrby=" + (this.filter_by_nearby_edits? 1 : 0);
         }
         if (!this.filter_by_creator_include.equals("")
               && this.filter_by_creator_include != null) {
            url_str += "&fbci=" + this.filter_by_creator_include;
         }
         if (!this.filter_by_creator_exclude.equals("")
               && this.filter_by_creator_exclude != null) {
            url_str += "&fbce=" + this.filter_by_creator_exclude;
         }
         // See next fcn. for 
         //    only_stack_ids
         //    only_lhs_stack_ids
         //    only_rhs_stack_ids
         //    only_selected_items
         //    only_associate_ids
         if (this.context_stack_id > 0) {
            url_str += "&ctxt=" + this.context_stack_id;
         }
         // See next fcn. for 
         //    only_item_types
         if (!this.results_style.equals("")
               && this.results_style != null) {
            url_str += "&rezs=" + this.results_style;
         }
         if (this.include_item_stack) {
            url_str += "&istk=" + (this.include_item_stack? 1 : 0);
         }
         if (this.min_access_level > 0) {
            url_str += "&mnac=" + this.min_access_level;
         }
         if (this.max_access_level > 0) {
            url_str += "&mxac=" + this.max_access_level;
         }
         if (this.skip_tag_counts) {
            url_str += "&ntcs=" + (this.skip_tag_counts? 1 : 0);
         }
         if (this.dont_load_feat_attcs) {
            url_str += "&dlfa=" + (this.dont_load_feat_attcs? 1 : 0);
         }
         if (this.do_load_lval_counts) {
            url_str += "&dllc=" + (this.do_load_lval_counts? 1 : 0);
         }
         if (this.include_item_aux) {
            url_str += "&iaux=" + (this.include_item_aux? 1 : 0);
         }
         if (this.do_load_latest_note) {
            url_str += "&dlln=" + (this.do_load_latest_note? 1 : 0);
         }
         if (this.include_rect != null) {
            url_str += "&bbxi=" + this.include_rect.get_gwis_bbox_str();
         }
         // FIXME: BBox_exclude is a Hack: when the user pans, the exclude
         //        region is an L-shaped object, not just a simple rectangle.
         if (this.exclude_rect != null) {
            url_str += "&bbxe=" + this.exclude_rect.get_gwis_bbox_str();
         }
      } catch (UnsupportedEncodingException e) {
         // FIXME: better error handling
         e.printStackTrace();
      }
      return url_str;
   }

   // 
   // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_xml
   // SYNC_ME: GWIS. See gwis/query_filters.py::xml_append_filters
   public String getFiltersXML() {
      StringBuilder xml_string = new StringBuilder("");
      //
      if (this.only_stack_ids.length > 0) {
         xml_string.append(this.append_ids_compact("sids_gia", 
                                                   this.only_stack_ids));
      }
      //
      if (this.only_lhs_stack_ids.length > 0) {
         xml_string.append(this.append_ids_compact("sids_lhs", 
                                                   this.only_lhs_stack_ids));
      }
      //
      // this.only_rhs_stack_ids is combined with this.only_selected_items,
      // since the latter only matters for discussions (at least for now),
      // so that means what's selected is geofeatures.
      /*var linked_ids:Array;
      if (this.only_rhs_stack_ids.length == 0) {
         linked_ids = new Array();
      }
      else {
         linked_ids = Collection.array_copy(this.only_rhs_stack_ids);
      }
      if (this.only_selected_items) {
         // Get the stack_ids of the geofeatures selected on the map.
         for each (gf in G.map.selectedset) {
            linked_ids.push(gf.stack_id);
         }
      }*/
      if (this.only_rhs_stack_ids.length > 0) {
         // only_rhs_stack_ids
         xml_string.append(this.append_ids_compact("sids_rhs", 
                                                   this.only_rhs_stack_ids));
      }
      //
      if (this.only_associate_ids.length > 0) {
         xml_string.append(this.append_ids_compact("ids_assc", 
                                                   this.only_associate_ids));
      }
      // only_item_types is only_item_type_ids in pyserver.
      if (this.only_item_types.length > 0) {
         xml_string.append(this.append_ids_compact("ids_itps", 
                                                   this.only_item_types));
      }
      return xml_string.toString();
   }

   //
   // SYNC_ME: GWIS. See gwis/query_filters.py::decode_gwis_xml
   // SYNC_ME: GWIS. See gwis/query_filters.py::append_ids_compact
   public String append_ids_compact(String doc_name,
                                    int[] stack_ids) {
      StringBuilder stack_id_str = new StringBuilder();
      for (int i = 0; i < stack_ids.length; i++) {
         if (i > 0) {
            stack_id_str.append(",");
         }
         stack_id_str.append(stack_ids[i]);
      }
      return "<" + doc_name + ">" + stack_id_str + "</" + doc_name + ">";
   }
}
