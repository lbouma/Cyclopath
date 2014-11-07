/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.events.Event;
   import flash.utils.getDefinitionByName;

   import gwis.update.Update_Base;
   import gwis.update.Update_Supplemental;
   import gwis.utils.Query_Filters;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Post;
   import items.attcs.Tag;
   import items.attcs.Thread;
   import items.feats.Branch;
   import items.feats.Byway;
   import items.feats.Region;
   import items.feats.Route;
   import items.feats.Terrain;
   import items.feats.Track;
   import items.feats.Waypoint;
   import items.gracs.New_Item_Policy;
   import items.links.Link_Geofeature;
   import utils.misc.Counter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;

   public class GWIS_Checkout_Versioned_Items extends GWIS_Checkout_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~Chkout_VerI');

      // *** Class attributes

      // FIXME: You can probably get rid of these lookups soon.
      // The list of item types we only care about at vector zoom level (since
      // we don't render this at raster zoom)
      protected static const item_types_vector_only:Set_UUID
         = new Set_UUID([
            Annotation.class_item_type,
            Byway.class_item_type,
            Terrain.class_item_type,
            Waypoint.class_item_type,
            ]);
      // The list of items types we always care about, i.e., at either vector
      // or raster zoom levels.
      // NOTE: This array is deprecated. It's only used for debugging.
      // PROBABLY: Delete this array and the associated debug code.
      protected static const item_types_vector_or_raster:Set_UUID
         = new Set_UUID([
            //
            Item_User_Access.class_item_type,
            //
            Geofeature.class_item_type,
            Link_Value.class_item_type,
            //
            Attribute.class_item_type,
            Thread.class_item_type,
            Post.class_item_type,
            Tag.class_item_type,
            //
            Branch.class_item_type,
            Region.class_item_type,
            Route.class_item_type,
            Track.class_item_type,
            //
            Link_Geofeature.class_item_type,
            //
            New_Item_Policy.class_item_type,
            //
            ]);

      // *** Instance attributes

      // For Diff requests, we wait for all three requests before processing
      // any items (old rev, new rev, and unchanged).
      protected var buddy_ct:Counter;

      // For item version history, sometimes we get a specific item.
      // This value is just for callers -- it's not part of the command.
      public var item_version:int;

      // *** Constructor

      // Constructor

      public function GWIS_Checkout_Versioned_Items(
         item_type:String,
         rev:utils.rev_spec.Base=null,
         buddy_ct:Counter=null,
         query_filters:Query_Filters=null,
         update_req:Update_Base=null,
         resp_items:Array=null,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         m4_VERBOSE('GWIS_Checkout_Versioned_Items: rev:', rev);
         if (resp_items === null) {
            m4_ASSERT(buddy_ct === null);
            buddy_ct = new Counter(1);
         }
         this.buddy_ct = buddy_ct;
         super(item_type, resp_items, rev, query_filters,
               update_req, callback_load, callback_fail);
      }

      // *** Instance methods

      // Returns true if all done; false if it's been running too long and
      // selectively preempting itself so other threads may run
      override public function gwis_complete_callback() :Boolean
      {
         var all_done:Boolean = true;
         // If this GWIS request is attached to a Update_Base object, we add
         // the items to the map here. Otherwise, it's expected that a callback
         // will process this.resp_items.
         m4_ASSURT((this.update_req !== null)
                   || (this.callback_load !== null));
         if (     (this.update_req !== null)
               // Note that OOB sets itself as the update_req, so check
               // callback_load.
               // FIXME: This is so ugly. There's only one place that needs
               //        this code, so we should move it there
               //        (to Update_Base.gwis_fetch_rev_create_qf).
               && (this.callback_load === null)
               && (this.buddy_ct.value == 0)
               && (this.resp_items !== null)
               && (this.resp_items.length > 0)) {
            m4_DEBUG('gwis_complete_callback: update_req:', this.update_req);
            // Tell items_add not to call items_add_finish; Update Mgr. will.
            var complete_now:Boolean = false;
            all_done = this.update_req.map.items_add(
                        this.resp_items, complete_now);
            if (all_done) {
               m4_DEBUG('gwis_complete_callback: all done!');
               m4_ASSERT(this.resp_items.length == 0);
               this.resp_items = null;
               // FIXME: This seems... weird. don't do this.
               //        If the is an OOB request (Update_Supplemental), we're
               //        getting the selected geofeature's(s') panel and
               //        calling on_panel_show... but the data we consume
               //        should fire specific Events, instead. Here, we're just
               //        blindly updating the active item details panel...
               m4_DEBUG('HACK: Checking for OOB request.');
               if (this.update_req is Update_Supplemental) {
                  var itms:Array = new Array();
                  var dpanel:Detail_Panel_Base;
                  m4_DEBUG('HACK: is Update_Supplemental');
                  for each (var an_item:Item_Versioned in this.resp_items) {
m4_ASSERT(false); // FIXME: We just reset resp_items, so how could this run?
                  //        Do we need to fix this code?
                     if (an_item is Geofeature) {
                        m4_DEBUG('HACK: an_item:', an_item);
                        itms.push(an_item);
                     }
                     else {
                        // Not a collection of Geofeatures.
                        break;
                     }
                  }
                  if (itms.length > 0) {
                     m4_DEBUG('gwis_complete_callb: panels_mark_dirty: itms');
                     G.panel_mgr.item_panels_mark_dirty(itms);
                  }
               } // end: if (this.update_req is Update_Supplemental)
            }
         }
         else {
            // This happens for out of band item checkouts. E.g., Route_List
            // checksout the list of routes and uses its own callback to
            // process the results.
            m4_ASSERT(this.buddy_ct.value == 0);
         }

         if (all_done) {
            all_done = super.gwis_complete_callback();
            m4_ASSERT(all_done);
         }

         return all_done;
      }

      // Process the XML data from the server.
      override protected function resultset_process(rset:XML) :void
      {
         // Call the parent, which parses the incoming items and adds them to
         // this.resp_items. In this fcn., all do is some sanity checking. The
         // resp_items will be processed by the caller, via callback_load.
         super.resultset_process(rset);
         // This is only enabled for debug builds.
         if (Conf_Instance.debug_goodies) {
            // This is just a test to make sure we solved a problem in the
            // old code. You used to be able to switch zoom levels while
            // checking out items, and the items you got back were no longer
            // revelant. This shouldn't happen in CcpV2.
            if (this.resp_items.length > 0) {
               var aitem:Item_Versioned = this.resp_items[0];
               var item_type_name:String;
               item_type_name
                  = Introspect.get_constructor(aitem).class_item_type;
               if (GWIS_Checkout_Versioned_Items
                     .item_types_vector_only.is_member(item_type_name)) {
                  if (!G.map.zoom_is_vector()) {
                     // The way CcpV2 works this shouldn't happen.
                     m4_ASSERT(false);
                  }
               }
               else {
                  m4_ASSERT(GWIS_Checkout_Versioned_Items
                     .item_types_vector_or_raster.is_member(item_type_name));
               }
            }
         }
         // If not Diffing, we'll add groups of items as we get 'em; for Diffs,
         // though, we need to wait for all three responses before loading 'em
         this.buddy_ct.dec();
     }

      // ***

      //
      override public function toString() :String
      {
         return super.toString()
             + ' / vers. ' + this.item_version;
      }

   }
}

