/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getQualifiedSuperclassName;
   import mx.core.Container;
   import mx.core.UIComponent;

   public class Introspect {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__Introspect');

      // *** Constructor

      public function Introspect() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class methods

      //
      public static function ctor(obj:Object) :Class
      {
         return Introspect.get_constructor(obj);
      }

      //
      public static function get_constructor(obj:Object) :Class
      {
         var cls:Class = (obj as Class) || (obj.constructor as Class);

         if (cls === null) {
            // Fall back to using more expensive string operations to
            // find the class for obj
            cls = (getDefinitionByName(getQualifiedClassName(obj)) as Class);
         }
         return cls;
      }

      // Return the text name of the given class object. If simple is true
      // the qualifying package is stripped off the beginning of the string.
      //   Ex. [class Byway] returns "item.feat::Byway", but with simple=true,
      //   it returns "Byway"
      public static function class_name(cls:Class, simple:Boolean=false)
         :String
      {
         var qualified:String = getQualifiedClassName(cls);
         if (simple) {
            var colon:int = qualified.lastIndexOf(':');
            if (colon >= 0) {
               // qualified type, so strip of package
               return qualified.substring(colon + 1);
            }
            else {
               // class w/o package?
               return qualified;
            }
         }
         else {
            // no string manipulation required
            return qualified;
         }
      }

      // I'm [lb] not normally one to kvetch, but why doesn't Flex provide this
      // functionality? This compares an Object at runtime against a Class to
      // see if the former is or derives from the latter. I tested all the
      // other angles and nothing seems to work at runtime. And using 'this is
      // that' only works if 'that' is known at compile-time. Bah! =)
      public static function derives_from(obj:Object, cls:Class) :Boolean
      {
         var is_derived:Boolean = false;
         var target:String = getQualifiedClassName(cls);
         var walker:Class = Introspect.get_constructor(obj);
         var visitor:String = getQualifiedClassName(walker);
         while (walker !== null) {
            //m4_VERBOSE('derives_from:', walker, '/', target, '/', visitor);
            // Is our journey over?
            if (target == visitor) {
               is_derived = true;
               break;
            }
            // Keep walking the ancestry until we find a match or null.
            visitor = getQualifiedSuperclassName(walker);
            if (visitor !== null) {
               walker = getDefinitionByName(visitor) as Class;
               visitor = getQualifiedClassName(walker);
            }
            else {
               walker = null;
            }
         }
         return is_derived;
      }

      // There's some Flex weirdness going on with .constructor:  When we
      // reference the static class and look at its static member, if that
      // member isn't set (is null), we instead see the void data type, which
      // has only one value, "underfined".  That is,
      //
      //    my_obj:My_Class = new My_Class();
      //    My_Class.my_static_var === null; // true
      //    my_obj.constructor.my_static_var === null; // false
      //
      // Instead, look for a void return, which can be detected one of three
      // ways:
      //
      //    !my_obj.constructor.my_static_var
      //    typeof(my_obj.constructor.my_static_var) == "undefined"
      //    my_obj.constructor.my_static_var == (undefined as My_Class)
      //
      // Note that the first form, using bang!, gives false-positives for
      // "false", "0", and other values. There are no differences between the
      // second and third form other than stylistic.
      //
      // DEPRECATION WARNING: Both typeof and instanceof are deprecated in
      // favor of the "is" operator, but you cannot "is void" since void is not
      // a class. Illegal: "my_obj.constructor.my_static_var is void".
      public static function is_undefined_or_null(thingy:*) :Boolean
      {
         // DEPRECATED: We have no choice but to use typeof!
         return ((typeof(thingy) == "undefined") || (thingy === null));
      }

      // Return the current stack trace, as reported by Error,
      // the returned String includes the call to this function.
      public static function stack_trace() :String
      {
         var stack:String = '';
         try {
            throw new Error('StackTrace');
         }
         catch (e:Error) {
            stack = e.getStackTrace();
         }
         return stack;
      }

      // Returns the name of the fcn. that called the fcn. we're in
      public static function stack_trace_caller() :String
      {
         // The stack trace looks like the following. We want the fourth fcn.
         // listed.
         //   at G$/stack_trace_caller()[/ccp/dev/cp_1051/flashclient/build...]
         //   at G$/stack_trace()[/ccp/dev/cp_1051/flashclient/build/G.as:1033]
         //   at views::Update_Base/work_queue_add_unit()[/ccp/dev/cp/...]
         //   at views::Update_Base/update_step_geofeatures_and_tiles(...]
         // NOTE We can search for either 'at ' or a newline.
         var stack_trace:String = Introspect.stack_trace();
         var index_first:int = -3; // Starting at -3 cause we add 3 in the loop
         var index_last:int = -1;
         for (var i:int = 0; i < 4; i++) {
            // MAGIC_NUMBER: Add three to go past the 'at '
            index_first = stack_trace.indexOf('at ', index_first + 3);
         }
         index_last = stack_trace.indexOf('()', index_first + 3);
         return stack_trace.substring(index_first + 3, index_last);
      }

      //
      public static function trace_display_list(
         container:DisplayObjectContainer, indent_spaces:String = '') :void
      {
         var child:DisplayObject;
         for (var i:uint=0; i < container.numChildren; i++)
         {
            child = container.getChildAt(i);
            //m4_DEBUG('display_list:', indent_spaces, child, '/', child.name);
            m4_DEBUG('display_list:', indent_spaces, child.name);
            m4_DEBUG2(indent_spaces, ' >> width:', child.width,
                      '/ vis:', child.visible);
            if (child is UIComponent) {
               m4_DEBUG3(indent_spaces, ' >> width:', child.width,
                         '/ vis:', child.visible, '/ iil:',
                         (child as UIComponent).includeInLayout);
            }
            else {
               m4_DEBUG2(indent_spaces, ' >> width:', child.width,
                         '/ vis:', child.visible);
            }
            if (container.getChildAt(i) is DisplayObjectContainer)
            {
               Introspect.trace_display_list(DisplayObjectContainer(child),
                                             indent_spaces + '  ');
            }
         }
      }

   }
}

