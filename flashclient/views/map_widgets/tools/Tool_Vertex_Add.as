/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets.tools {

   import flash.events.MouseEvent;

   import items.Geofeature;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;

   public class Tool_Vertex_Add extends Tool_Pan_Select {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Vtx_Add');

      // *** Constructor

      public function Tool_Vertex_Add(map:Map_Canvas_Base) :void
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
         //applies_to = (item is Geofeature);
         // 2013.04.08: Is this right?: In get useable, we called
         //             useable_check_type, so... this is a given, right?
         var feat:Geofeature = (target_ as Geofeature);
         applies_to = ((feat !== null) && (feat.can_edit));
         m4_DEBUG2('mouse_event_applies_to: target_:', target_,
                   '/ applies:', applies_to);
         return applies_to;
      }

      //
      override public function on_mouse_move(x:Number, y:Number) :void
      {
         // We don't care if the user drags while clicked or whenever.
         // Skipping: super.on_mouse_mode(x, y);
      }

      //
      override public function get tool_is_advanced() :Boolean
      {
         return true;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_vertex_add';
      }

      //
      override public function get useable() :Boolean
      {
         var is_useable:Boolean = false;
         var feat:Geofeature;

         // NOTE: You can have multiple geofeatures selected, and this tool
         // just adds the vertex to one of them. However, we don't know which
         // geofeature the user clicks until it happens, so we don't know if
         // the user has permissions to edit the supposed geofeature when we're
         // deciding to enable this tool or not. For now, we do the easiest
         // thing, which is to only enable this tool if the user can edit every
         // single geofeature in the selection.
         if ((super.useable)
             //&& (this.map.zoom_is_vector())
             && (this.map.selectedset.length > 0)
             && (this.useable_check_type(Geofeature))) {
            feat = this.map.selectedset.item_get_random() as Geofeature;
            m4_DEBUG('useable?: feat:', feat);
            m4_ASSERT(feat !== null); // Else useable_check_type falsed us
            // Check that the item type actually supports vertices
            is_useable = feat.vertex_add_enabled;
         }
         return is_useable;
      }

      // *** Double click detector mouse handlers

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_VERBOSE2('on_mouse_up: target:', ev.target,
                     '/ processed:', processed);
         if (!processed) {
            var item:Geofeature = this.map.get_geofeature(ev);
            if (item !== null) {
               processed = item.on_mouse_up_vertex_add(ev);
            }
            // else, user didn't click a Geofeature.
         }
         // else, processed earlier by Vertex or Tool_Byway_Split.
         return super.on_mouse_up(ev, processed);
      }

   }
}

