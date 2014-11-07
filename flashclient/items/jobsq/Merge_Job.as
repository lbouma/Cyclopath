/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // SYNC_ME: See pyserver/items/jobsq/merge_job.py
   //              flashclient/item/jobsq/Merge_Job.as
   public class Merge_Job extends Work_Item {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Merge_Job');

      // *** Mandatory attributes

      public static const class_item_type:String = 'merge_job';
      public static const class_gwis_abbrev:String = 'mjob';
      public static const class_item_type_id:int = Item_Type.MERGE_JOB;

      // *** Instance variables

      // FIXME: for_group_id is restricted to the public group for the branch,
      //        since the following scenerio would otherwise be possible but
      //        doesn't make sense: as a branch arbiter, you create a private
      //        export of the map, which includes your private items; but any
      //        other branch arbiter can now download this package. This isn't
      //        too hard to fix, but it's not implemented in pyserver.
      public var for_group_id:int;
      public var for_revision:int;

      // FIXME: rather than use query_filters this should just be here?
      public var filter_by_region:String;

      // *** Constructor

      public function Merge_Job(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Merge_Job = (to_other as Merge_Job);
         super.clone_once(other);
         other.for_group_id = this.for_group_id;
         other.for_revision = this.for_revision;
         other.filter_by_region = this.filter_by_region;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Merge_Job = (to_other as Merge_Job);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.for_group_id = int(gml.@for_group_id);
            this.for_revision = int(gml.@for_revision);
            this.filter_by_region = gml.@filter_by_region;
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         // This is a tad hacky: If the user creates a new import or export
         // job, we'll make, i.e., Merge_Import_Job or Merge_Export_Job. But
         // when we just populate the Map Package Jobs list, we're just dealing
         // with the intermediate class, Merge_Job.
         //
         // So we set the XML tag to 'merge_job' here, but if the class hier.
         // includes a derived class, it'll overwrite it with something more
         // specific.

         // Derived classes should call setName... unless we're dealing with a
         // partial-hierarchy.
         gml.setName(Merge_Job.class_item_type); // 'merge_job'

         gml.@for_group_id = int(this.for_group_id);
         gml.@for_revision = int(this.for_revision);
         gml.@filter_by_region = this.filter_by_region;

         return gml;
      }

      // ***

      //
      public function get for_group_id_s() :String
      {
         var id_s:String;
         if (this.for_group_id == 0) {
            id_s = 'Public';
         }
         else {
            id_s = String(this.for_group_id);
         }
         return id_s;
      }

      //
      public function set for_group_id_s(group_id_s:String) :void
      {
         m4_ASSERT(false); // Not supported.
         //this.for_group_id = ??;
      }

      //
      public function get for_revision_s() :String
      {
         var rev_s:String;
         if (this.for_revision == 0) {
            rev_s = 'Current';
         }
         else {
            rev_s = String(this.for_revision);
         }
         return rev_s;
      }

      //
      public function set for_revision_s(revision_s:String) :void
      {
         m4_ASSERT(false); // Not supported.
         //this.revision_s = ??;
      }

   }
}

