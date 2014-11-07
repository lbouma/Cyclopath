/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// SYNC_ME: flashclient/GWIS_Route_Feedback_Dragged.as
//          pyserver/route_put_feedback_dragged.py
//

// Data packet format:
//
// <gwis>
//    <old id=X version=X>
//       old_reason
//    </old>
//    <new id=X version=X>
//       new_reason
//    </new>
//    <byways>
//       <byway id=X />
//       <byway id=X />
//       ...
//    </byways>
// </gwis>

// FIXME: route reactions. this whole file is new.
//    and untested, since route feedback is not enable in Cycloplan/Statewide.

// FIXME: route manip. Reimplement route feedback.

package gwis {

   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import utils.misc.Logging;

   public class GWIS_Route_Feedback_Dragged extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rte_PDrg');

      // *** Instance variables

// FIXME: See GWIS_Base.callback_load...
      protected var callback:Function = null;

      // *** Constructor

      // Assumes that the new, dragged route has been successfully saved and
      // has an ID and version.
      public function GWIS_Route_Feedback_Dragged(
         route_old_stack_id:int,
         route_old_version:int,
         route_new_stack_id:int,
         route_new_version:int,
         old_reason:String,
         new_reason:String,
         byway_sids:Array,
         change:int,
         callback_:Function=null) :void
      {
         var byway_id:int;
         var byway_ids_node:XML = <byways/>;
         var doc:XML = this.doc_empty();
         var url:String = this.url_base('route_feedback_dragged');

         // Append change info.
         url += ('&change=' + change);

         // Append old route info.
         doc.appendChild(
            <old
               id={route_old_stack_id}
               version={route_old_version}>
                  {old_reason}
            </old>);

         // Append new route info. Must be a saved route.
         doc.appendChild(
            <new
               id={route_new_stack_id}
               version={route_new_version}>
                  {new_reason}
            </new>);

         // Append stretches info.
         if (byway_sids !== null) {
            for each (byway_id in byway_sids) {
               byway_ids_node.appendChild(<byway id={byway_id}/>);
            }
         }
         doc.appendChild(byway_ids_node);

         // Record callback function.
         this.callback = callback_;

         super(url, doc);
      }

      //
      override protected function error_present(text:String) :void
      {
         // FIXME: For the first time, say "try again", on the second time,
         // just silently thank the user.
         Alert.show(text, 'Feedback failed');
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         // MAYBE: Should the alert dialog be saved after the callback is
         //        called?
         Alert.show(
            'Feedback saved successfully. Thank you for helping Cyclopath!',
            'Feedback successful');
         if (this.callback !== null) {
            this.callback();
         }
      }

   }
}

