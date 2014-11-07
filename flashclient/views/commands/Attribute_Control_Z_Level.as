/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import items.Geofeature;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.base.Map_Layer;

   public class Attribute_Control_Z_Level extends Command_Scalar_Edit {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Attr_Z');

      // *** Constructor

      public function Attribute_Control_Z_Level(
         targets:Set_UUID,
         value_new:int)
            :void
      {
         super(targets, 'z_user', value_new);
      }

      // *** Instance methods

      // We override the base class implementation so we can call
      // feature_relayer.
      override protected function alter(i:int, from:*, to:*) :void
      {
         // NOTE: Ignoring variable 'from'
         var gf:Geofeature = this.edit_items[i] as Geofeature;
         var zplus_from:Number = gf.zplus;
         //gf.z_level = to;
         gf.z_user = to;
         // Remove the geofeature from the old layer and add to the new layer.
         Map_Layer.feature_relayer(gf, zplus_from);
         // NOTE: Base class normally calls draw_all, but not us.
      }

   }
}

