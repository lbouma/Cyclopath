/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // SYNC_ME: See pyserver/items/jobsq/merge_export_job.py
   //              flashclient/item/jobsq/Merge_Export_Job.as
   public class Merge_Export_Job extends Merge_Job {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Mrg_Export');

      // *** Mandatory attributes

      public static const class_item_type:String = 'merge_export_job';
      public static const class_gwis_abbrev:String = 'exjb';
      public static const class_item_type_id:int = Item_Type.MERGE_EXPORT_JOB;

      // *** Instance variables

      // *** Constructor

      public function Merge_Export_Job(xml:XML=null,
                                       rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Merge_Export_Job = (to_other as Merge_Export_Job);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Merge_Export_Job = (to_other as Merge_Export_Job);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         // Merge_Import_Job is only created internally; when we checkout the
         // list of jobs, they're all Merge_Job (though job_class specifies if
         // it's an import or an export). So gml should be empty.
         m4_ASSURT(gml === null);
         super.gml_consume(gml);
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(Merge_Export_Job.class_item_type); // 'merge_export_job'

         return gml;
      }

   }
}

