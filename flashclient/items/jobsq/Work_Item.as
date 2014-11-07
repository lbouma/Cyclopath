/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import mx.utils.StringUtil;

   import items.Nonwiki_Item;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.misc.Strutil;
   import utils.misc.Timeutil;
   import utils.rev_spec.*;

   // SYNC_ME: See pyserver/items/jobsq/work_item.py
   //              flashclient/item/jobsq/Work_Item.as
   public class Work_Item extends Nonwiki_Item {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Work_Item');

      // *** Mandatory attributes

      public static const class_item_type:String = 'work_item';
      public static const class_gwis_abbrev:String = 'wtem';
      public static const class_item_type_id:int = Item_Type.WORK_ITEM;

      // *** Instance variables

      // Work Item
      public var job_act:String;
      public var job_class:String;
      public var created_by:String;
      public var job_priority:int;
      public var job_finished:Boolean;
      public var num_stages:int;
      //
      // MAYBE: email_on_finish should be replaced with watchers framework
      public var email_on_finish:Boolean;
      public var job_stage_msg:String;
      public var job_time_all:Number;
      // Work Item Step (the Latest Step)
      // work_item_id
      // step_number
      //public var last_modified:String;
      public var epoch_modified:int;
      public var stage_num:int;
      public var stage_name:String;
      public var stage_progress:int;
      public var status_code:int;
      protected var status_text_:String;
      public var cancellable:Boolean;
      public var suspendable:Boolean;
      //
      public var recency_modified:String;

      // FIXME: Using this just to test...
      public var status_tip:String;

      // *** Constructor

      public function Work_Item(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      public function get status_text() :String
      {
         var sttus:String;
         var overall_progress:Number = 0;
         if ((this.status_text_ == 'working')
             && (this.stage_progress >= 0)
             && (this.num_stages > 0)) {
            if (this.stage_num > 0) {
               overall_progress = 100.0 * ((Number(this.stage_num) - 1.0)
                                           / Number(this.num_stages));
            }
            overall_progress += (Number(this.stage_progress)
                                 / Number(this.num_stages));
            sttus = StringUtil.substitute('{0}%', int(overall_progress));
         }
         else {
            sttus = Strutil.capitalize_underscore_delimited(this.status_text_);
         }
         return sttus;
      }

      //
      public function set status_text(status_text:String) :void
      {
         this.status_text_ = status_text;
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Work_Item = (to_other as Work_Item);
         super.clone_once(other);
         m4_ASSERT(false); // Not called.
         other.job_class = this.job_class;
         other.created_by = this.created_by;
         other.job_priority = this.job_priority;
         other.job_finished = this.job_finished;
         other.num_stages = this.num_stages;
         other.email_on_finish = this.email_on_finish;
         other.job_stage_msg = this.job_stage_msg;
         other.job_time_all = this.job_time_all;
         //other.date_modified = this.date_modified;
         other.epoch_modified = this.epoch_modified;
         other.stage_num = this.stage_num;
         other.stage_name = this.stage_name;
         other.stage_progress = this.stage_progress;
         other.status_code = this.status_code;
         other.status_text = this.status_text;
         other.cancellable = this.cancellable;
         other.suspendable = this.suspendable;
         //other.err_s = this.err_s;
         other.recency_modified = this.recency_modified;
         other.job_stage_msg = this.job_stage_msg;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Work_Item = (to_other as Work_Item);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         // This fcn. process one row:
         //
         // <data major="not_a_working_copy" gwis_version="2" semiprotect="0">
         //    <jobs_queue>
         //       <row
         //          id="2"
         //          username="landonb" branch_id="2401776" group_id="2401777"
         //          revision_id="12345" epoch_created="[secs. since epoch]"
         //          date_created="Fri Dec 09 00:29:13 CST 2011"
         //          stage_name="" stage_progress="0" num_stages="1"
         //          status_code="1" status_text="Queued" cancellable="1"
         //          job_class="shapeio" job_priority="1" />
         //    </jobs_queue>
         // </data>
         //
         super.gml_consume(gml);
         if (gml !== null) {
            // Skipping: job_act
            //
            this.job_class = gml.@job_class;
            this.created_by = gml.@created_by;
            this.job_priority = int(gml.@job_priority);
            this.job_finished = Boolean(int(gml.@job_finished));
            this.num_stages = int(gml.@num_stages);
            //
            this.email_on_finish = Boolean(int(gml.@email_on_finish));
            this.job_stage_msg = gml.@job_stage_msg;
            this.job_time_all = Number(gml.@job_time_all);
            //
            //this.date_modified = gml.@date_modified;
            this.epoch_modified = int(gml.@epoch_modified);
            this.stage_num = int(gml.@stage_num);
            this.stage_name = gml.@stage_name;
            this.stage_progress = int(gml.@stage_progress);
            this.status_code = int(gml.@status_code);
            this.status_text = gml.@status_text;
            this.cancellable = Boolean(int(gml.@cancellable));
            this.suspendable = Boolean(int(gml.@suspendable));
            //this.err_s = Boolean(int(gml.@err_s));
            // Calculated values.
            this.recency_modified =
               Timeutil.datetime_to_recency(this.epoch_modified);
            // The job_stage_msg is a toolTip, er, dataTip, but it obscures the
            // column data, which is the status, so include both.
            var sttus:String;
            sttus = Strutil.capitalize_underscore_delimited(this.status_text_);
            if (this.job_stage_msg != '') {
               this.job_stage_msg = sttus + ': ' + this.job_stage_msg;
            }
            else if (this.stage_name != '') {
               this.job_stage_msg = sttus + ': ' + this.stage_name;
            }
            else {
               this.job_stage_msg = sttus;
            }
            if ((this.status_text_ == 'working')
                && (this.stage_progress >= 0)) {
               this.job_stage_msg += StringUtil.substitute(
                  ' ({0}% of stage {1} of {2}])',
                  String(this.stage_progress),
                  String(this.stage_num),
                  String(this.num_stages));
            }
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         //gml.setName(Work_Item.class_item_type); // 'work_item'
         gml.@job_act = this.job_act;
         //gml.@job_class = this.job_class; // redundant?
         // Skipping: created_by
         gml.@job_priority = this.job_priority;
         // Skipping: job_finished, num_stages
         // FIXME: Make settable. And don't email if user cancels from
         //        flashclient.
         gml.@email_on_finish = int(this.email_on_finish);
         // Skipping: job_stage_msg, job_time_all
         // Skipping: last_modified, epoch_modified
         // Skipping: stage_num, stage_name, stage_progress
         // Skipping: status_code, status_text, cancellable, suspendable
         // Skipping: recency_modified
         return gml;
      }

   }
}

