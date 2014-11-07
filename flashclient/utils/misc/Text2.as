/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import mx.controls.Text;
   import mx.core.IUITextField;

   public class Text2 extends Text {

      // *** Class attributes.

      protected static var log:Logging = Logging.get_logger('Text2');

      // ***

      public function Text2()
      {
         super();
      }

      // ***

      [Bindable] public function get get_textField() :IUITextField
      {
         return this.textField;
      }

      //
      public function set get_textField(text_field:IUITextField) :void
      {
         m4_ASSERT_SOFT(false);
      }

   }
}

