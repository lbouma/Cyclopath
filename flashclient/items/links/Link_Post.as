/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.links {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

// Screwy. We can link to attribute, too...
// EXPLAIN: Why derive from Link_Geofeature?
   public class Link_Post extends Link_Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Link_Post');

      // *** Mandatory attributes

      public static const class_item_type:String = 'link_post';
      //public static const class_gwis_abbrev:String = 'lpost';
      public static const class_item_type_id:int = Item_Type.LINK_POST;

      // *** Instance variables

      // *** Constructor

      // EXPLAIN: Why Link_Post and not just Link_Geofeature -- is it just so
      //          pyserver checkout joins thread and/or post tables?
      public function Link_Post(xml:XML=null,
                                rev:utils.rev_spec.Base=null,
                                lhs_item:Object=null,
                                rhs_item:Object=null)
      {
         super(xml, rev, lhs_item, rhs_item);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Link_Post = (to_other as Link_Post);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Link_Post = (to_other as Link_Post);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            m4_ASSERT(this.link_lhs_type_id == Item_Type.str_to_id('post'));
         }
         else if (this.stack_id != 0) {
            m4_WARNING('gml_consume: no gml?!');
         }
         // else, the app is starting up (see init_GetDefinitionByName()).
      }

   }
}

