/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_util {

   // NO: import com.adobe.images.JPGEncoder;
   // We want the faster third-party utility:
   //  utils.misc.JPEGEncoder
   import flash.display.BitmapData;
   import flash.errors.IllegalOperationError;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.net.FileReference;
   import flash.utils.ByteArray;
   import mx.containers.Canvas;
   import mx.containers.VBox;
   import mx.controls.Alert;
   import mx.controls.Image;
   import mx.controls.Label;
   import mx.core.FlexBitmap;
   import mx.events.ItemClickEvent;
   import mx.printing.*;

   /*/ DEVS: Uncomment this if you want to experiment with SWFExplorer.
   import org.bytearray.explorer.SWFExplorer;
   import org.bytearray.explorer.events.SWFExplorerErrorEvent;
   import org.bytearray.explorer.events.SWFExplorerEvent;
   /*/

   // BUG nnnn: Figure out how to dynamically load these to avoid adding
   //           1 Mb to swf size. For now, statically linking in
   //           mxmlc-config.xml.
   // NOTE: We don't instantiate these. But we need them for Bug 2783: that
   //       is, to dynamically load *.swf at our will... using Class_Loader.
   import org.purepdf.elements.images.ImageElement;
   import org.purepdf.pdf.PageSize;
   import org.purepdf.pdf.PdfDocument;
   import org.purepdf.pdf.PdfViewPreferences;
   import org.purepdf.pdf.PdfWriter;

   import utils.misc.Class_Loader;
   import utils.misc.JPEGEncoder;
   import utils.misc.Logging;

   public class Print_And_Save_Map {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('PrntNSav_Map');

      // *** Instance attributes

      // protected var classldr_as3corelib:Class_Loader = null;
      // protected var classldr_purePDFont:Class_Loader = null;
      // protected var classldr_purePDF:Class_Loader = null;
      protected var classldr_print:Class_Loader = null;
      protected var classes_loaded:uint = 0;
      // SYNC_ME: The number of Class_Loader.load()s
      //          below must equal this.classes_count.
      protected static const classes_count:uint = 1;

      // protected var swfexplorer_print:SWFExplorer = null;

      // ***

      //
      public function Print_And_Save_Map() :void
      {
      }

      // ***

      /*/ 2013.03.19: The old CcpV2 code that was never tested...
      protected function on_print_click() :void
      {
         var print_job:FlexPrintJob = new FlexPrintJob();
         print_job.start();
         print_job.addObject(G.map, FlexPrintJobScaleType.MATCH_WIDTH);
         print_job.send();
      }
      /*/
      // FIXME: Not fully tested. Works best with Chrome. Not recommended.
      public function print_map() :void
      {
         var printJob:FlexPrintJob = new FlexPrintJob();
         if (printJob.start()) {
            // Add map.
            printJob.addObject(G.app.map_canvas_print, 
                               FlexPrintJobScaleType.SHOW_ALL);
            // Send the job to the printer.
            printJob.send();
         }
      }

      // ***

      // FIXME: This doesn't work when aerial photos are on because of 
      //        cross-domain security violation.
      public function save_pdf() :void
      {
         m4_DEBUG('on_save_pdf');
         if (this.classes_loaded != Print_And_Save_Map.classes_count) {
            m4_DEBUG('dynamic swc: on_save_pdf: not inited');
            this.load_pdf_packages();
            // We cannot call FileReference after the library loads, since we
            // can only call FileReference in response to user interaction.
            //  Error: Error #2176: Certain actions, such as those that display
            //  a pop-up window, may only be invoked upon user interaction, for
            //  example by a mouse click or button press.
            m4_WARNING2(
               'Unexpected: Cannot load library and call FileReference');
            // Nope: this.on_save_pdf_dynamic();
            // Nope: G.map.callLater(this.on_save_pdf_dynamic);
         }
         else {
            m4_DEBUG('dynamic swc: on_save_pdf: already ready');
            //this.on_save_pdf_static(G.app.map_canvas_print);
            this.on_save_pdf_dynamic();
         }
      }

      //
      // SYNC_ME: pdf_printer.mxml:: and Main_Toolbar.mxml::on_save_pdf_*.
      protected function on_save_pdf_dynamic() :void
      {
         // Set up the PDF document.

         // m4_DEBUG2('on_save_pdf_dynamic: list_classes:',
         //           this.classldr_print.list_classes());

         var buffer:ByteArray = new ByteArray();

         var ImageElementCls:Class;
         var PageSizeCls:Class;
         var PdfDocumentCls:Class;
         var PdfViewPreferencesCls:Class;
         var PdfWriterCls:Class;
         try {
            ImageElementCls = this.classldr_print.get_class(
                              'org.purepdf.elements.images.ImageElement');
            m4_DEBUG('get_class: org.purepdf.elements.images.ImageElement');
         } catch (ev:IllegalOperationError) { }
         try {
            PageSizeCls = this.classldr_print.get_class(
                              'org.purepdf.pdf.PageSize');
            m4_DEBUG('get_class: org.purepdf.pdf.PageSize');
         } catch (ev:IllegalOperationError) { }
         try {
            PdfDocumentCls = this.classldr_print.get_class(
                              'org.purepdf.pdf.PdfDocument');
            m4_DEBUG('get_class: org.purepdf.pdf.PdfDocument');
         } catch (ev:IllegalOperationError) { }
         try {
            PdfViewPreferencesCls = this.classldr_print.get_class(
                              'org.purepdf.pdf.PdfViewPreferences');
            m4_DEBUG('get_class: org.purepdf.pdf.PdfViewPreferences');
         } catch (ev:IllegalOperationError) { }
         try {
            PdfWriterCls = this.classldr_print.get_class(
                              'org.purepdf.pdf.PdfWriter');
            m4_DEBUG('get_class: org.purepdf.pdf.PdfWriter');
         } catch (ev:IllegalOperationError) { }

         // Oddly, this fails if you comment out the org.purepdf.*
         // imports above, otherwise, it works.
         /*/
         try {
            var PrintCls:Class;
            PrintCls = this.classldr_print.get_class('pdf_printer');
            m4_DEBUG('get_class: pdf_printer');
            var map_print:Object = new PrintCls();
            map_print.on_save_pdf_impl(G.app.map_canvas_print);
         } catch (ev:IllegalOperationError) { }
         /*/

         m4_ASSERT(
            (ImageElementCls !== null)
            && (PageSizeCls !== null)
            && (PdfDocumentCls !== null)
            && (PdfViewPreferencesCls !== null)
            && (PdfWriterCls !== null)
            );

         PageSizeCls = this.classldr_print.get_class(
                           'org.purepdf.pdf.PageSize');

         // var writer:PdfWriter = PdfWriter.create(
         //                         buffer, PageSizeCls.LETTER.rotate());
         var writer:Object = PdfWriterCls['create'](
                                 buffer, PageSizeCls['LETTER']['rotate']());

         // var document:PdfDocument = writer.pdfDocument;
         var document:Object = writer.pdfDocument;

         document.addAuthor("Cyclopath");
         document.addTitle("Cyclopath Map");
         document.addCreator("Cyclopath");
         // document.setViewerPreferences(PdfViewPreferences.FitWindow);
         document.setViewerPreferences(PdfViewPreferencesCls['FitWindow']);

         // Open the document.
         document.open();

         // Shorthand.
         var w:Number = G.app.map_canvas_print.width;
         var h:Number = G.app.map_canvas_print.height;

         // Get the screen-shot.
         var map_bmd:BitmapData = new BitmapData(w, h, false);
         map_bmd.draw(G.app.map_canvas_print);

         // Encode it to JPEG.
         // NO: var encoder:JPGEncoder = new JPGEncoder();
         var encoder:JPEGEncoder = new JPEGEncoder();
         var map_ba:ByteArray = encoder.encode(map_bmd);
         // var image:ImageElement = ImageElement.getInstance(map_ba);
         var image:Object = ImageElementCls['getInstance'](map_ba);

         // Scale and add to document.
         // FIXME: MAGIC NUMBERS: 700 and 500 are approximately what results in
         // a full-page display. Explicitly setting margins may be better.
         image.scaleToFit(700, 500);
         document.add(image);

         // Close the document.
         document.close();

         // Offer the PDF for download.
         var f:FileReference = new FileReference();
         // MAYBE: Is there a better filename? Maybe the name of the closest
         //        region describing the map?
         // MAYBE: Increment the number for each PDF saved, so the user doesn't
         //        have to manually edit the name every time.
         f.save(buffer, "Cyclopath Map.pdf");
      }

      //
      // SYNC_ME: pdf_printer.mxml:: and Main_Toolbar.mxml::on_save_pdf_*.
      /*/ 
      public function on_save_pdf_static(map_canvas:Canvas) :void
      {
         // Set up the PDF document.

         m4_DEBUG('dynamic swc: on_save_pdf_static');

         var buffer:ByteArray = new ByteArray();

         var writer:PdfWriter = PdfWriter.create(
                                 buffer, PageSize.LETTER.rotate());
         // var PdfWriterCls:Class;
         // var PageSizeCls:Class;
         // -- or:
         // PdfWriterCls = this.classldr_purePDF.get_class('PdfWriter');
         // PageSizeCls = this.classldr_purePDF.get_class('PageSize');
         // var writer:Object = PdfWriterCls['create'](
         //                        buffer, PageSizeCls['LETTER']['rotate']());

         var document:PdfDocument = writer.pdfDocument;
         // -- or:
         // var document:Object = writer.pdfDocument;

         document.addAuthor("Cyclopath");
         document.addTitle("Cyclopath Map");
         document.addCreator("Cyclopath");

         document.setViewerPreferences(PdfViewPreferences.FitWindow);
         // -- or:
         // var PdfViewPreferencesCls:Class = this.classldr_purePDF.get_class(
         //                                              'PdfViewPreferences');
         // document.setViewerPreferences(PdfViewPreferencesCls['FitWindow']);

         // Open the document.
         document.open();

         // Shorthand.
         var w:Number = map_canvas.width;
         var h:Number = map_canvas.height;

         // Get the screen-shot.
         var map_bmd:BitmapData = new BitmapData(w, h, false);
         map_bmd.draw(map_canvas);

         // Encode it to JPEG.
         // NO: var encoder:JPGEncoder = new JPGEncoder();
         var encoder:JPEGEncoder = new JPEGEncoder();
         var map_ba:ByteArray = encoder.encode(map_bmd);

         var image:ImageElement = ImageElement.getInstance(map_ba);
         // -- or:
         // var ImageElementCls:Class = this.classldr_purePDF.get_class(
         //                                              'ImageElement');
         // var image:Object = ImageElementCls['getInstance'](map_ba);

         // Scale and add to document.
         // FIXME: MAGIC NUMBERS: 700 and 500 are approximately what results in
         // a full-page display. Explicitly setting margins may be better.
         image.scaleToFit(700, 500);
         document.add(image);

         // Close the document.
         document.close();

         // Offer the PDF for download.
         var f:FileReference = new FileReference();
         // MAYBE: Is there a better filename? Maybe the name of the closest
         //        region describing the map?
         // MAYBE: Increment the number for each PDF saved, so the user doesn't
         //        have to manually edit the name every time.
         f.save(buffer, "Cyclopath Map.pdf");
      }
      /*/ 

      // ***

      //
      protected function on_load_lib() :void
      {
         m4_DEBUG('on_load_lib');
         if (this.classes_loaded != Print_And_Save_Map.classes_count) {
            m4_DEBUG('dynamic swc: on_load_lib: not inited');
            this.load_pdf_packages();
         }
      }

      //
      public function load_pdf_packages() :void
      {
         if (this.classes_loaded != Print_And_Save_Map.classes_count) {
            this.load_pdf_packages_();
         }
      }

      //
      protected function load_pdf_packages_() :void
      {
         m4_DEBUG('dynamic swc: load_pdf_packages');
         // SYNC_ME: The number of Class_Loader.load()s
         //          herein must equal this.classes_count.
         /*/
         // Trying to load the third-party modules:
         if (this.classldr_as3corelib === null) {
            this.classldr_as3corelib = new Class_Loader();
            this.classldr_as3corelib.addEventListener(
               Class_Loader.LOAD_ERROR, this.loadErrorHandler_as3corelib);
            this.classldr_as3corelib.addEventListener(
               Class_Loader.CLASS_LOADED, this.class_loaded_handler);
            this.classldr_as3corelib.load(
               G.url_base + "/flex_util/as3corelib.swf");
         }
         if (this.classldr_purePDFont === null) {
            this.classldr_purePDFont = new Class_Loader();
            this.classldr_purePDFont.addEventListener(
               Class_Loader.LOAD_ERROR, this.loadErrorHandler_purePDFont);
            this.classldr_purePDFont.addEventListener(
               Class_Loader.CLASS_LOADED, this.class_loaded_handler);
            this.classldr_purePDFont.load(
               G.url_base + "/flex_util/purePDFont.swf");
         }
         if (this.classldr_purePDF === null) {
            this.classldr_purePDF = new Class_Loader();
            this.classldr_purePDF.addEventListener(
               Class_Loader.LOAD_ERROR, this.loadErrorHandler_purePDF);
            this.classldr_purePDF.addEventListener(
               Class_Loader.CLASS_LOADED, this.class_loaded_handler);
            this.classldr_purePDF.load(
               G.url_base + "/flex_util/purePDF.swf");
         }
         /*/
         //
         // Trying to load our own compiled module:
         if (this.classldr_print === null) {
            this.classldr_print = new Class_Loader();
            this.classldr_print.addEventListener(
               Class_Loader.LOAD_ERROR, this.loadErrorHandler_print);
            this.classldr_print.addEventListener(
               Class_Loader.CLASS_LOADED, this.class_loaded_handler);
            if (Conf.external_interface_okay) {
               // This is what normally happens.
               m4_ASSERT(G.file_base === null);
               this.classldr_print.load(
                  G.url_base + '/flex_util/pdf_printer.swf');
            }
            else {
               // This is for DEVs debugging on Windows.
               m4_ASSERT(G.file_base !== null);
               this.classldr_print.load(
                  G.file_base + 'pdf_printer.swf');
            }
         }
         //
         // Attempt to use SWFExplorer to print out classes in a loaded swf:
         /*/
         if (this.swfexplorer_print === null) {
            this.swfexplorer_print = new SWFExplorer();
            this.swfexplorer_print.load(new URLRequest(
                  G.url_base + '/flex_util/pdf_printer.swf'));
            this.swfexplorer_print.addEventListener(
               SWFExplorerEvent.COMPLETE, this.swfexplorer_ready);
         }
         /*/
      }

      //
      // protected function swfexplorer_ready(ev:SWFExplorerEvent) :void
      /*/
      protected function swfexplorer_ready(ev:Object) :void
      {
         // SWFExplorer doesn't seem to work, or [lb] isn't using it right.
         // The pdf_printer.pdf indicates just one Class:
         //    defns: _pdf_printer_mx_managers_SystemManager
         //    getDefs: _pdf_printer_mx_managers_SystemManager
         //    totl: 1
         m4_DEBUG2('swfexplorer_ready: defns:',
                   (ev as SWFExplorerEvent).definitions);
         m4_DEBUG2('swfexplorer_ready: getDefs:',
                   (ev as SWFExplorerEvent).target.getDefinitions());
         m4_DEBUG2('swfexplorer_ready: totl:',
                   (ev as SWFExplorerEvent).target.getTotalDefinitions());
         this.classes_loaded++;
         // Cannot, because of FileReferece: this.on_save_pdf_dynamic();
      }
      /*/

      /*/
      //
      protected function loadErrorHandler_as3corelib(ev:Event) :void
      {
         m4_WARNING('loadErrorHandler: ev:', ev);
         m4_WARNING('loadErrorHandler: ev.target:', ev.target);
         m4_WARNING('loadErrorHandler: ev.toString():', ev.toString());
         this.classldr_as3corelib = null;
      }

      //
      protected function loadErrorHandler_purePDFont(ev:Event) :void
      {
         m4_WARNING('loadErrorHandler: ev:', ev);
         m4_WARNING('loadErrorHandler: ev.target:', ev.target);
         m4_WARNING('loadErrorHandler: ev.toString():', ev.toString());
         this.classldr_purePDFont = null;
      }

      //
      protected function loadErrorHandler_purePDF(ev:Event) :void
      {
         m4_WARNING('loadErrorHandler_purePDF: ev:', ev);
         m4_WARNING('loadErrorHandler_purePDF: ev.target:', ev.target);
         m4_WARNING('loadErrorHandler_purePDF: ev.toString():', ev.toString());
         this.classldr_purePDF = null;
      }
      /*/

      //
      protected function loadErrorHandler_print(ev:Event) :void
      {
         m4_WARNING('loadErrorHandler_print: ev:', ev);
         m4_WARNING('loadErrorHandler_print: ev.target:', ev.target);
         m4_WARNING('loadErrorHandler_print: ev.toString():', ev.toString());
         this.classldr_print = null;
      }

      //
      protected function class_loaded_handler(ev:Event) :void
      {
         m4_DEBUG('dynamic swc: class_loaded_handler: ev:', ev);
         this.classes_loaded++;
         // Cannot, because of FileReferece: this.on_save_pdf_dynamic();
      }

      // ***

   }
}

