/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets.tools {

   import flash.events.MouseEvent;

   import items.feats.Byway;
   import items.verts.Byway_Vertex;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;

   public class Tool_Byway_Split extends Tool_Vertex_Add {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Bwy_Spl');

      // *** Constructor

      public function Tool_Byway_Split(map:Map_Canvas_Base) :void
      {
         super(map);
      }

      // *** Instance methods

      //
      override public function mouse_event_applies_to(target_:Object) :Boolean
      {
         var applies_to:Boolean = false;
         // Check that the byway is editable.
         // FIXME: There should be multiple byways that intersect that need to
         //        be checked.
         //applies_to = (item is Byway);
         // 2013.04.08: Is this right?: In get useable, we called
         //             useable_check_type, so... this is a given, right?
         var bway:Byway = (target_ as Byway);
         // 2013.07.03: To split existing vertices, need also to check for
         //             Vertex type.
         if (bway === null) {
            var bvtx:Byway_Vertex = (target_ as Byway_Vertex);
            if (bvtx !== null) {
               bway = (bvtx.parent_ as Byway);
            }
         }
         applies_to = ((bway !== null) && (bway.can_edit));
         m4_DEBUG2('mouse_event_applies_to: target_:', target_,
                   '/ applies:', applies_to);
         return applies_to;
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_TALKY2('on_mouse_up: processed:', processed,
                   '/ target:', ev.target);
         if (!processed) {
            var bvtx:Byway_Vertex;
            bvtx = (this.map.get_item_vertex(ev) as Byway_Vertex);
            if (bvtx !== null) {
               processed = bvtx.on_mouse_up(ev, processed);
            }
            // else, if a Byway, Tool_Vertex_Add will add a vertex first and
            //       then call the new Byway_Vertex's on_mouse_up.
         }
         return super.on_mouse_up(ev, processed);
      }

      //
      override public function get tool_is_advanced() :Boolean
      {
         return true;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_byway_split';
      }

      // Check that the user has appropriate priveleges to edit the items
      // that are selected
      override public function get useable() :Boolean
      {
         // The user has to be able to edit the selected byways and to create
         // new byways.
         return ((super.useable)
                 //&& (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length > 0)
                 && (this.useable_check_type(Byway))
                 // This is redundant; see user_has_permissions:
                 && (G.item_mgr.create_allowed_get(Byway)));
      }

   }
}

