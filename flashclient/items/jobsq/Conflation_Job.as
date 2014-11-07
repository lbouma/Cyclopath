/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // SYNC_ME: See pyserver/items/jobsq/conflation_job.py
   //              flashclient/item/jobsq/Conflation_Job.as
   public class Conflation_Job extends Work_Item {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Cfltn_Job');

      // *** Mandatory attributes

      public static const class_item_type:String = 'conflation_job';
      public static const class_gwis_abbrev:String = 'cjob';
      public static const class_item_type_id:int = (
                        Item_Type.CONFLATION_JOB);

      // *** Instance variables

      // *** Constructor

      public function Conflation_Job(xml:XML=null,
                                     rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Conflation_Job = (to_other as Conflation_Job);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Conflation_Job = (to_other as Conflation_Job);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         return gml;
      }

   }
}

