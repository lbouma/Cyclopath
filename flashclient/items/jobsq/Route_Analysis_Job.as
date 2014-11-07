/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // SYNC_ME: See pyserver/items/jobsq/route_analysis_job.py
   //              flashclient/item/jobsq/Route_Analysis_Job.as
   public class Route_Analysis_Job extends Work_Item {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Rt_Anlys_J');

      // *** Mandatory attributes

      public static const class_item_type:String = 'route_analysis_job';
      public static const class_gwis_abbrev:String = 'rjob';
      public static const class_item_type_id:int = (
                        Item_Type.ROUTE_ANALYSIS_JOB);

      // *** Instance variables

      public var n:int;
      public var revision_id:int;
      public var regions_ep_name_1:String;
      public var regions_ep_tag_1:String;
      public var regions_ep_name_2:String;
      public var regions_ep_tag_2:String;
      public var rider_profile:String;
      public var rt_source:int;
      public var cmp_job_name:String;

      // *** Constructor

      public function Route_Analysis_Job(xml:XML=null,
                                         rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Route_Analysis_Job = (to_other as Route_Analysis_Job);
         super.clone_once(other);
         other.n = this.n;
         other.revision_id = this.revision_id;
         other.regions_ep_name_1 = this.regions_ep_name_1;
         other.regions_ep_tag_1 = this.regions_ep_tag_1;
         other.regions_ep_name_2 = this.regions_ep_name_2;
         other.regions_ep_tag_2 = this.regions_ep_tag_2;
         other.rider_profile = this.rider_profile;
         other.rt_source = this.rt_source;
         other.cmp_job_name = this.cmp_job_name;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Route_Analysis_Job = (to_other as Route_Analysis_Job);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.n = int(gml.@n);
            this.revision_id = int(gml.@revision_id);
            this.regions_ep_name_1 = gml.@regions_ep_name_1;
            this.regions_ep_tag_1 = gml.@regions_ep_tag_1;
            this.regions_ep_name_2 = gml.@regions_ep_name_2;
            this.regions_ep_tag_2 = gml.@regions_ep_tag_2;
            this.rider_profile = gml.@rider_profile;
            this.rt_source = int(gml.@rt_source);
            this.cmp_job_name = gml.@cmp_job_name;
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(Route_Analysis_Job.class_item_type);
         gml.@n = this.n;
         gml.@revision_id = this.revision_id;
         gml.@regions_ep_name_1 = this.regions_ep_name_1;
         gml.@regions_ep_tag_1 = this.regions_ep_tag_1;
         gml.@regions_ep_name_2 = this.regions_ep_name_2;
         gml.@regions_ep_tag_2 = this.regions_ep_tag_2;
         gml.@rider_profile = this.rider_profile;
         gml.@rt_source = this.rt_source;
         gml.@cmp_job_name = this.cmp_job_name;
         return gml;
      }

   }
}

