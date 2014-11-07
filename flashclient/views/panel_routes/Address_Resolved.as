/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.geom.Point;

   import utils.misc.Logging;
   import views.panel_search.Panel_Search_Result;

   public class Address_Resolved {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('AddyResolved');

      // *** Instance attributes

      // The string that started it all.

      public var raw_address:String;

      // The list of geocoded results.

      public var results_xml:XMLList = null;
      public var results_none:Boolean = false;
      public var results_error:Boolean = false;
      public var error_message:String = null;

      // The selection index into the list of geocoded results. Not that we
      // really care about the position; we really just care if it's -1 or not.

      public var geocoded_index:int = -1;

      public var proper_address:String;

      public var geocoded_ptx:Number = NaN;
      public var geocoded_pty:Number = NaN;

      // The width and height of the context of the result, used to determine
      // the zoom level at which to lookat... hopefully.

      public var geocoded_w:String;
      public var geocoded_h:String;

      // The gc_fulfiller indicates what process geocoded this point. It's
      // either an external geocoder, e.g., Bing, MapPoint, MapQuest, etc.,
      // or the internal Cyclopath geocoder.
      // gc_fulfiller values: 'bing', 'mapq', 'mgis', 'mapp',
      //                      'ccp_gf', 'ccp_pt'
      public var gc_fulfiller:String;

      // The confidence is a value from 0 to 100. 100 means 100% confidence
      // that the address is what the user is looking for (although you can
      // have multiple such addresses for the same query, meaning, it's not so
      // much 100% that the result is what the user wants, but 100% confidence
      // that the result matches our well-defined rules with 100% success,
      // e.g., the names exactly match (as in the case of a named point), or
      // the user searched for a specific street address, or the user searched
      // for a "city, state").  The confidence is not meaningful between two
      // results with different gc_fulfiller origins except when both have a
      // 100% confidence, especially between internal results and external
      // results because the confidence value is computed differently.
      public var gc_confidence:Number;

      // *** Constructor

      public function Address_Resolved() :void
      {
         ; // No-op.
      }

      // ***

      //
//      override
      public function toString() :String
      {
         return ('Addr Reslvd:'
                 + ' raw_addr: ' + this.raw_address
                 + ' / xml.len: '
                    + ((this.results_xml !== null)
                       ? this.results_xml.length() : 'null')
                 + ' / none?: ' + this.results_none
                 + ' / err?: ' + this.results_error
                 + ' / emsg: ' + this.error_message
                 + ' / gc_idx: ' + this.geocoded_index
                 + ' / propr_addr: ' + this.proper_address
                 + ' / gc_x: ' + this.geocoded_ptx
                 + ' / gc_y: ' + this.geocoded_pty
                 + ' / gc_w: ' + this.geocoded_w
                 + ' / gc_h: ' + this.geocoded_h
                 + ' / fulfllr: ' + this.gc_fulfiller
                 + ' / cnfdnce: ' + this.gc_confidence
                 );
      }

      // ***

      //
      public function address_from_search(result:Panel_Search_Result) :void
      {
         var place:Point = result.label_coords;

         var addresses:XML = <addrs/>;
         var address:XML = <addr/>;
         address.@text = result.gf_name;
         address.@x = (place.x).toString();
         address.@y = (place.y).toString();
         address.@width = '0';
         address.@height = '0';
         address.@gc_id = '';
         address.@gc_ego = NaN;
         address.@results_index = 0;
         addresses.appendChild(address);
         m4_DEBUG('address_from_search: results:', addresses.toXMLString());

         this.raw_address = result.gf_name;
         this.results_xml = addresses.addr;
         this.results_none = false;
         this.results_error = false;
         this.error_message = null;
         this.choose_addy(/*results_index=*/0);
      }

      //
      public function address_from_rstop(rstop_endpt:Route_Stop) :void
      {
         m4_DEBUG('address_from_rstop: this:', this);

         this.geocoded_ptx = rstop_endpt.x_map;
         this.geocoded_pty = rstop_endpt.y_map;
         m4_DEBUG2('address_from_rstop: ptx:', this.geocoded_ptx,
                                     '/ pty:', this.geocoded_pty);

         if (this.is_geocoded(/*skip_checks=*/true)) {

            var stop_name:String;
            stop_name = rstop_endpt.name_or_street_name;
            m4_DEBUG('address_from_rstop: rstop_endpt:', rstop_endpt);
            m4_DEBUG('address_from_rstop: stop_name:', stop_name);

            var addresses:XML = <addrs/>;
            var address:XML = <addr/>;
            address.@text = stop_name;
            address.@x = (this.geocoded_ptx).toString();
            address.@y = (this.geocoded_pty).toString();
            address.@width = '0';
            address.@height = '0';
            address.@gc_id = 'ccp_fc'; // "Cyclopath_Flashclient"
            address.@gc_ego = 100;
            address.@results_index = 0;
            addresses.appendChild(address);
            m4_DEBUG('address_from_rstop: results:', addresses.toXMLString());

            this.raw_address = stop_name;
            this.results_xml = addresses.addr;
            this.results_none = false;
            this.results_error = false;
            this.error_message = null;
            this.choose_addy(/*results_index=*/0);
         }
         else {
            this.clear_addy(/*keep_results=*/false);
            m4_ASSERT_SOFT(false); // Does this happen?
         }
      }

      //
      public function choose_addy(results_index:int) :void
      {
         m4_DEBUG('choose_addy: results_index:', results_index);

         m4_ASSERT(this.results_xml !== null);
         this.results_none = false;
         this.results_error = false;
         this.error_message = null;

         m4_ASSERT_SOFT(results_index
                        == this.results_xml[results_index].@results_index);
         this.geocoded_index = results_index;
         this.proper_address = this.results_xml[results_index].@text;
         if (!this.raw_address) {
            this.raw_address = this.proper_address;
         }

         // For whatever reason, ptx,pty are Strings, not Numbers.
         this.geocoded_ptx = Number(this.results_xml[results_index].@x);
         this.geocoded_pty = Number(this.results_xml[results_index].@y);
         this.geocoded_w = this.results_xml[results_index].@width;
         this.geocoded_h = this.results_xml[results_index].@height;
         this.gc_fulfiller = this.results_xml[results_index].@gc_id;
         this.gc_confidence = this.results_xml[results_index].@gc_ego;
      }

      //
      public function clear_addy(keep_results:Boolean=false) :void
      {
         m4_DEBUG('clear_addy: keep_results:', keep_results, '/', this);

         if (!keep_results) {
            this.raw_address = null;
            this.results_xml = null;
            this.results_none = false;
            this.results_error = false;
            this.error_message = null;
         }
         this.geocoded_index = -1;
         this.proper_address = null;

         this.geocoded_ptx = NaN;
         this.geocoded_pty = NaN;
         this.geocoded_w = null;
         this.geocoded_h = null;

         this.gc_fulfiller = '';
         this.gc_confidence = NaN;
      }

      //
      public function copy_from_addy(other:Address_Resolved) :void
      {
         m4_DEBUG('copy_from_addy: this:', this.toString());
         m4_DEBUG('copy_from_addy: other:', other.toString());

         this.raw_address = other.raw_address;
         this.results_xml = other.results_xml;
         this.results_none = other.results_none;
         this.results_error = other.results_error;
         this.error_message = other.error_message;
         this.geocoded_index = other.geocoded_index;
         this.proper_address = other.proper_address;

         this.geocoded_ptx = other.geocoded_ptx;
         this.geocoded_pty = other.geocoded_pty;
         this.geocoded_w = other.geocoded_w;
         this.geocoded_h = other.geocoded_h;

         this.gc_fulfiller = other.gc_fulfiller;
         this.gc_confidence = other.gc_confidence;
      }

      //
      public function has_results() :Boolean
      {
         return ((this.results_xml !== null)
                 || (this.results_none)
                 || (this.results_error));
      }

      //
      public function is_geocoded(skip_checks:Boolean=false) :Boolean
      {
         m4_DEBUG('is_geocoded: this:', this);

         var is_geocoded:Boolean =
            (   (!isNaN(this.geocoded_ptx))
             && (!isNaN(this.geocoded_pty)));

         if (!skip_checks) {

            m4_ASSERT_SOFT((is_geocoded) || (this.geocoded_index == -1));
            m4_ASSERT_SOFT((!is_geocoded) || (this.geocoded_index != -1));

            // 2014.09.09: This is firing (via log_event_check.sh):
            m4_ASSERT_SOFT((is_geocoded) || (!this.proper_address));
            // Just to make sure the line number is correct:
            if (!((is_geocoded) || (!this.proper_address))) {
               m4_ASSERT_SOFT(false);
               G.sl.event('error/address_resolved/is_geocoded',
                          {raw_address: this.raw_address,
                           is_geocoded: is_geocoded,
                           proper_address: this.proper_address});
            }

            m4_ASSERT_SOFT((!is_geocoded) || (this.proper_address));
         }
         return is_geocoded;
      }

      // ***

   }
}

