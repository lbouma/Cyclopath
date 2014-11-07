/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.links {

   import mx.utils.UIDUtil;

   import items.Geofeature;
   import items.Link_Value;
   import items.Record_Base;
   import items.attcs.Attribute;
   import items.utils.Item_Type;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Link_Geofeature extends Link_Value {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Link_Gftr');

      // *** Mandatory attributes

      public static const class_item_type:String = 'link_geofeature';
      //public static const class_gwis_abbrev:String = 'lfeat';
      public static const class_item_type_id:int = Item_Type.LINK_GEOFEATURE;

      // *** Instance variables

      // Extra instance variables over the base class, Link_Value.
      // Link_Geofeature also contains location information about the
      // geofeature (or as a special case, a revision) referred to in the
      // object.
      public var gf_xs:Array = null;
      public var gf_ys:Array = null;
      public var gf_deleted:Boolean;

      // *** Constructor

      // A Link_Geofeature links an attachment as lhs_item to a geofeature or
      // attribute (/post/revision) as rhs_item.
      public function Link_Geofeature(xml:XML=null,
                                      rev:utils.rev_spec.Base=null,
                                      lhs_item:Object=null,
                                      rhs_item:Object=null)
      {
         if (rhs_item !== null) {
            var feat_or_attr:Geofeature = (rhs_item as Geofeature);
            if (feat_or_attr !== null) {
               this.gf_name = feat_or_attr.name_;
               this.gf_xs = Collection.array_copy(feat_or_attr.xs);
               this.gf_ys = Collection.array_copy(feat_or_attr.ys);
            }
            else {
               m4_ASSERT(rhs_item is Attribute);
               // So... nothing to do?
            }
         }
//         else {
//            // No?: this.gf_name = '';
//            this.gf_xs = new Array();
//            this.gf_ys = new Array();
//         }
         this.gf_deleted = false;

         super(xml, rev, lhs_item, rhs_item);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         m4_ASSERT_SOFT(false); // Not called, right?
         var other:Link_Geofeature = (to_other as Link_Geofeature);
         super.clone_once(other);
         other.gf_name = this.gf_name;
         other.gf_deleted = this.gf_deleted;
         if ((this.gf_xs !== null) && (this.gf_ys !== null)) {
            other.gf_xs = Collection.array_copy(this.gf_xs)
            other.gf_ys = Collection.array_copy(this.gf_ys)
         }
         else {
            m4_ASSERT((this.gf_xs === null) && (this.gf_ys === null));
         }
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         m4_ASSERT_SOFT(false); // Not called, right?
         var other:Link_Geofeature = (to_other as Link_Geofeature);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {

            this.gf_name = gml.@gf_name;

            m4_DEBUG3('gml_c: gf_name:', this.gf_name,
                      'lhs_type:', this.link_lhs_type_id,
                      'rhs_type:', this.link_rhs_type_id);

            var geo_text:String = '';
            if (this.link_rhs_type_id == Item_Type.str_to_id('byway')) {
               // Line geometry
               //geo_text = gml.external.text();
               geo_text = gml.text();
            }
            else if (
                  (this.link_rhs_type_id == Item_Type.str_to_id('waypoint'))
               || (this.link_rhs_type_id == Item_Type.str_to_id('region'))
               || (this.link_rhs_type_id == Item_Type.str_to_id('terrain'))) {
               // Point or Region geometry
               geo_text = gml.text();
            }
// FIXME: route reactions.
            else if (this.link_rhs_type_id == Item_Type.str_to_id('route')) {
// FIXME: see below. this is silly. I think we just set:
//             geo_text = gml.text();
//        because this fcn. just hacks around the chars that later osgeo builds
//        include in their geometry output... which the server should be
//        scrubbing... and wouldn't this be a problem for the other
//        link-types?
//        2013.03.25: [lb]: [mm] commented out this block but not the code
//                          inside. so now we're not calling
//                          link_route_compute_xys. or maybe we weren't before,
//                          anyway, since I've got the weird /post/route
//                          attribute...
//               this.link_route_compute_xys(gml.text());
            }
            else {
               // BUG nnnn: Clicking Link_Post-Revision widget should go to
               //           revision entry?
               // Revision.
               m4_ASSERT(this.link_rhs_type_id
                         == Item_Type.str_to_id('attribute'));
               m4_DEBUG('gml_consume: this.attc:', this.attc);
               m4_DEBUG('gml_consume: this.rhs_stack_id:', this.rhs_stack_id);

               // MAGIC_NUMBER: '/post/revision' is the name of the
               //               link_post-revision attribute.
//               var attr:Attribute = Attribute.all_named['/post/revision'];
               var attr:Attribute = Attribute.all[this.rhs_stack_id];
               m4_ASSURT(attr !== null);

               if (attr.value_internal_name == '/post/revision') {
                  // FIXME: Why is this under <external>?
                  //geo_text = gml.text();
                  geo_text = gml.external.text();
               }
               else if (attr.value_internal_name == '/post/route') {
//                  m4_ASSURT(false); // FIXME: Implement /post/route?
                  this.link_route_compute_xys(gml.text());
               }
               else {
                  m4_WARNING2('gml_consume: Unrecognized link-attr:',
                              attr.value_internal_name);
               }
            }

            m4_DEBUG(' >> geo_text:', geo_text);
            m4_DEBUG(' >> this:', this.toString());
            //m4_DEBUG(' >> uuid: this:', UIDUtil.getUID(this));
            if (geo_text != '') {
               m4_ASSERT((this.gf_xs === null) && (this.gf_ys === null));
               this.gf_xs = new Array();
               this.gf_ys = new Array();
               Geometry.coords_string_to_xys(geo_text, this.gf_xs, this.gf_ys);
            }
            this.gf_deleted = Boolean(int(gml.@gf_deleted));
         }
         else if (this.stack_id != 0) {
            m4_WARNING('gml_consume: no gml?!');
         }
         // else, the app is starting up (see init_GetDefinitionByName()).
      }

      // ***

      public function get gf_name() :String
      {
         return this.rhs_name;
      }

      public function set gf_name(gf_name_:String) :void
      {
         this.rhs_name = gf_name_;
      }

      //
      protected function link_route_compute_xys(xy_str:String) :void
      {
         // FIXME: Can we delete this? [lb] doesn't think the server does (or
         //        should) send the 'M '. Or maybe it should. Scope the network
         //        and find out what's currently happening, I suppose...
         var pattern:RegExp = /M\s([\d\.]+)\s([\d\.]+)\s/g;
         Geometry.coords_string_to_xys(xy_str.replace(pattern, ''),
                                       this.gf_xs, this.gf_ys);
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' | gf_name: ' + this.gf_name
                 + ' | gf_xs: ' + this.gf_xs
                 + ' | gf_ys: ' + this.gf_ys
                 + ' | gf_deleted: ' + this.gf_deleted
                 );
      }

   }
}

