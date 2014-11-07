/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// C.f. http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/system/ApplicationDomain.html#includeExamplesSummary

package utils.misc {

   import flash.display.Loader;
   import flash.errors.IllegalOperationError;
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.Capabilities;
   import flash.system.LoaderContext;

   public class Class_Loader extends EventDispatcher {

      // *** Class attributes.

      protected static var log:Logging = Logging.get_logger('Class_Loader');

      public static var CLASS_LOADED:String = "classLoaded";
      public static var LOAD_ERROR:String = "loadError";

      // *** Instance attributes

      private var cloader:Loader;
      private var swf_lib:String;
      private var request:URLRequest;

      // *** Constructor

      public function Class_Loader()
      {
         this.cloader = new Loader();
         this.cloader.contentLoaderInfo.addEventListener(
            Event.COMPLETE, this.completeHandler);
         this.cloader.contentLoaderInfo.addEventListener(
            IOErrorEvent.IO_ERROR, this.ioErrorHandler);
         this.cloader.contentLoaderInfo.addEventListener(
            SecurityErrorEvent.SECURITY_ERROR, this.securityErrorHandler);
      }

      // *** Instance methods

      //
      public function load(lib:String) :void
      {
         m4_DEBUG('load: lib:', lib);
         this.swf_lib = lib;
         this.request = new URLRequest(this.swf_lib);
         var context:LoaderContext = new LoaderContext();
         // Use currentDomain unless you're loading modules that have
         // overlapping interfaces.
         context.applicationDomain = ApplicationDomain.currentDomain;
         //context.applicationDomain = new ApplicationDomain();
         this.cloader.load(this.request, context);
      }

      //
      public function get_class(class_name:String) :Class
      {
         try {
            return this.cloader.contentLoaderInfo.applicationDomain
                     .getDefinition(class_name) as Class;
         }
         catch (e:Error) {
            m4_WARNING2('get_class: failed for:', class_name,
                        '/ in:', this.swf_lib);
            throw new IllegalOperationError(
               class_name + ' definition not found in ' + this.swf_lib);
         }
         return null;
      }

      //
      private function completeHandler(ev:Event) :void
      {
         m4_DEBUG('completeHandler: ev:', ev);
         this.dispatchEvent(new Event(Class_Loader.CLASS_LOADED));
      }

      //
      private function ioErrorHandler(ev:Event) :void
      {
         m4_DEBUG('ioErrorHandler: ev:', ev);
         this.dispatchEvent(new Event(Class_Loader.LOAD_ERROR));
      }

      //
      private function securityErrorHandler(ev:Event) :void
      {
         m4_DEBUG('securityErrorHandler: ev:', ev);
         this.dispatchEvent(new Event(Class_Loader.LOAD_ERROR));
      }

      //
      public function list_classes() :void
      {
         m4_DEBUG('list_classes: this:', this);
         var definitions:*;
         // Vector.<String> = this.loaderInfo.applicationDomain
         //                      .getQualifiedDefinitionNames();
         if (this.cloader.contentLoaderInfo.applicationDomain.hasOwnProperty(
                                             'getQualifiedDefinitionNames')) {
            definitions = this.cloader.contentLoaderInfo.applicationDomain[
                                             'getQualifiedDefinitionNames']();
            for (var i:int = 0; i < definitions.length; i++) {
               m4_DEBUG('list_classes: i:', i, '/ defn:', definitions[i]);
            }
         }
         else {
            // This happens in pre-Flash 11.3.
            m4_WARNING2('list_classes: not supported by your Flash version:',
                        Capabilities.version);
         }
      }

   }
}

