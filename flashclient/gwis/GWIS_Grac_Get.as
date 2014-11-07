/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.utils.getDefinitionByName;

   import grax.Grac_Manager;
   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Item_Base;
   import utils.misc.Counter;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;

   public class GWIS_Grac_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Get_Grac');

      // *** Object attributes

      protected var rev:utils.rev_spec.Base;

      // These attributes are used to synchronize grouped requests which
      // should be processed in a certain order. Such requests use a shared
      // features array; when each request completes, buddy_ct is decremented.
      // When it reaches 0, the features are processed.
      // DEFER This class is similar to GWIS_Checkout_Base and
      //       GWIS_Checkout_Versioned_Items. It might benefit from
      //       consolidation.
      protected var resp_items:Array;
      protected var buddy_ct:Counter;

      // Where to store the results
      protected var grac:Grac_Manager;

      protected var callers_callback_okay:Function = null;
      protected var callers_callback_fail:Function = null;

      // *** Constructor

      public function GWIS_Grac_Get(
         update_req:Update_Base,
         control_type:String,
         control_context:String,
         rev:utils.rev_spec.Base,
         grac:Grac_Manager,
         resp_items:Array=null,
         buddy_ct:Counter=null,
         qfs:Query_Filters=null,
         callback_okay:Function=null,
         callback_fail:Function=null)
            :void
      {
         var url:String = (this.url_base('grac_get')
                           + '&control_type=' + control_type
                           + '&control_context=' + control_context
                           + '&rev=' + rev);

         m4_DEBUG('GWIS_Grac_Get: url:', url);
         m4_DEBUG('GWIS_Grac_Get: rev:', rev);
         m4_ASSERT(rev is utils.rev_spec.Follow);

         // The branch ID is required for branch-context requests, but not
         // necessarily for user-context. E.g., getting a user's group
         // memberships doesn't require a branch ID, but getting a user's
         // new item policy for a branch does require a branch ID.
         m4_ASSERT(G.item_mgr.branch_id_to_load == 0);

         if (resp_items === null) {
            m4_ASSERT(buddy_ct === null);
            resp_items = new Array();
            buddy_ct = new Counter(1);
         }

         this.resp_items = resp_items;
         this.rev = rev;
         this.grac = grac;
         this.buddy_ct = buddy_ct;

         var throb:Boolean = true;
         // The GWIS_Base calls the callbacks before gwis_complete_callback,
         // so the items haven't been added to the map yet.
         //   super(url, this.doc_empty(), throb, qfs, update_req,
         //         callback_okay, callback_fail, caller_data);
         super(url, this.doc_empty(), throb, qfs, update_req);

         this.callers_callback_okay = callback_okay;
         this.callers_callback_fail = callback_fail;
      }

      // *** Instance methods

      //
      override public function cancel() :void
      {
         if (G.item_mgr.branch_id_to_load != 0) {
            m4_DEBUG2('Canceling load of GrAC records for',
                      G.item_mgr.branch_id_to_load);
            G.item_mgr.branch_id_to_load = 0;
         }
         super.cancel();
      }

      // Returns true if all done; false if it's been running too long and
      // selectively preempting itself so other threads may run
      override public function gwis_complete_callback() :Boolean
      {
         var all_done:Boolean = true;
         super.gwis_complete_callback();
         if ((this.buddy_ct.value == 0)
             && (this.resp_items !== null)
             && (this.resp_items.length > 0)) {
            m4_DEBUG('gwis_complete_callback: adding items');
            // Add the new items to the Grac_Record object, which is
            // either the global one which applies to the user, or one for a
            // group, if the user is looking at a group's details panel.
            all_done = this.grac.items_add(this.resp_items);
            if (all_done) {
               if (this.callers_callback_okay !== null) {
                  this.callers_callback_okay(this);
               }
               m4_DEBUG('gwis_complete_callback: all done!');
               m4_ASSERT(this.resp_items.length == 0);
               this.resp_items = null;
            }
         }
         else {
            m4_DEBUG('gwis_complete_callback: nothing to add?!');
            m4_ASSERT(this.buddy_ct.value == 0);

            if (this.callers_callback_fail !== null) {
               this.callers_callback_fail(this);
            }
         }
         return all_done;
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);

         GWIS_Grac_Get.grac_resultset_process(rset, this.resp_items, this.rev);

         // If not Diffing, we'll add groups of items as we get 'em; for Diffs,
         // though, we need to wait for all three responses before loading 'em.
         this.buddy_ct.dec();
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user;
      }

      // ***

      //
      public static function grac_resultset_process(
         rset:XML,
         resp_items:Array,
         rev:utils.rev_spec.Base)
            :void
      {
         var grac_container:XML;
         var grac_type:String;
         var grac_class:Class;
         var grac_detail:XML;

         m4_DEBUG2('grac_resultset_process: rset:',
                     rset.toXMLString());

         //for each (grac_container in rset.*) { ... }
         for each (grac_container in rset.access_control) {

            m4_DEBUG2('grac_resultset_process: grac_container:',
                        grac_container.toXMLString());

            // <access_control control_type="new_item_policy">
            //    <new_item_policy .../></access_control>
            grac_type = grac_container.@control_type;
            m4_DEBUG('grac_resultset_process: grac_type:', grac_type);
            grac_class = Item_Base.item_get_class(grac_type);
            m4_DEBUG('grac_resultset_process: grac_class:', grac_class);
            // Start by iterating through each of the new object details.
            for each (grac_detail in grac_container.*) {
               //m4_DEBUG2('grac_class.class_item_type:',
               //          grac_class.class_item_type);
               //m4_DEBUG2('grac_class.class_gwis_abbrev:',
               //          grac_class.class_gwis_abbrev);
               // Make sure the object type is actually what we expect.
               //if (grac_type == String(grac_detail.name())) {
               if ((grac_type == grac_class.class_item_type)
                   || (grac_type == grac_class.class_gwis_abbrev)) {
                  // Create a new GrAC record and store in our temporary list
                  // WATCH This'll kill Flash plugin if you're processing a
                  //       large XML document, like ~ 1 Mb; you'll want to
                  //       use callLater in this instance, and to process
                  //       the XML in chunks (perhaps by asking for the
                  //       results in chunks, or perhaps by processing the
                  //       results in chunks).
                  //m4_DEBUG('resultset_process: Adding', grac_detail);
                  // Note that Record_Base's ctor calls gml_consume.
                  grac_detail.@cli_id = rset.@cli_id;
                  grac_detail.@new_id = rset.@new_id;
                  m4_DEBUG2('grac_resultset_process: grac_detail',
                            grac_detail.toXMLString());
                  resp_items.push(new grac_class(grac_detail, rev));
               }
               else {
                  var estr:String = 'Unknown item type: ' + grac_detail.name();
                  throw new Error(estr);
               }
            } // for each (grac_detail in grac_container.*)
         } // for each (grac_container in rset.*)
      }

      // ***

   }
}

