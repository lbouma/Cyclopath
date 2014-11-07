/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Command_Text_Edit extends Command_Scalar_Edit {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Text_E');

      // ***

      protected var new_text_value:String;
      protected var old_text_value:String;
      protected var text_input:Text_Field_Editable;

      // *** Constructor

      public function Command_Text_Edit(
         targets:Set_UUID,
         attr_name:String,
         text_new:String,
         text_old:String,
         dirty_reason:int,
         text_input:Text_Field_Editable)
            :void
      {
         this.new_text_value = text_new;
         this.old_text_value = text_old;
         this.text_input = text_input;

         m4_DEBUG2('Command_Text_Edit: new:', this.new_text_value,
                   '/ old:', this.old_text_value);

         super(targets, attr_name, text_new, dirty_reason);
      }

      // ***

      //
      override public function do_() :void
      {
         super.do_();

         this.text_input.text = this.new_text_value;
      }

      //
      override public function undo() :void
      {
         super.undo();

         this.text_input.text = this.old_text_value;
      }

      // ***

   }
}

