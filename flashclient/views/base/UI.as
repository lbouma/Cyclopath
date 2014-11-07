/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class holds various UI utility stuff.

package views.base {

   import flash.display.DisplayObjectContainer;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.filters.GlowFilter;
   import flash.geom.Rectangle;
   import flash.net.navigateToURL;
   import flash.net.URLRequest;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.containers.TitleWindow;
   import mx.controls.Alert;
   import mx.events.ListEvent;
   import mx.managers.PopUpManager;

   import items.Geofeature;
   import items.Link_Value;
   import items.attcs.Attribute;
   import items.attcs.Tag;
   import items.feats.Byway;
   import items.feats.Waypoint;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_components.instance_messages.*;
   import views.map_widgets.tools.Map_Tool;
   import views.map_widgets.tools.Tool_Pan_Select;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_util.Alert_Dialog;
   import views.panel_util.Image_Popup;
   import views.panel_util.Pointing_Widget;
   import views.section_toolbar.Map_Layer_Toggler;

   public class UI {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('UI');

      // Icons used in various places
      // FIXME: Should this go with the other Embed code?
      // NOTE: Use static not const because of the Embed.
      [Embed(source='/assets/img/lock.png')]
      // EXPLAIN: Why is this static here but not other places Embed is used?
      //          2013.03.04: [lb] wonders maybe because UI is a singleton.
      public static var locked_icon:Class;

      // How many data requests have been created since the last idle?
      protected static var requests_created:int = 0;

      // How many data requests have been completed since the last idle?
      protected static var requests_completed:int = 0;

      protected static var throbberers_timer:Timer = null;
      protected static var throbberer_clients:Set_UUID = new Set_UUID();

      // BUG 2715: Better errors: We keep track of which error messages
      // we show during the same throb-session so that we don't show the
      // same error message multilpe times. E.g., if there was
      // a network interruption, we'd show the same error message for
      // each request that didn't complete, but we really only
      // need to tell the user once (i.e., since some actions, like loading
      // the map, generate dozens of requests... meaning the simplest
      // recovery was a complete Web page refresh).
      protected static var throb_session_alerts:Set_UUID = new Set_UUID();
      protected static var throb_sessionless_timer:Timer = null;

      // Pointing widget to encourage compact saves.
      protected static var save_pointer:Pointing_Widget = null;
      // 2012.08.16: Users are annoyed when they see this a lot. Show once.
      protected static var compact_save_reminded:Boolean = false;

      // Current threshold distance for a save-reminder.
      public static var curr_sv_remind_dist:int = Conf.save_reminder_distance;

      // Filter to make things over the map look good.
      public static var mapglow:GlowFilter
         = new GlowFilter(
               Conf.background_color,  // color:uint
               1.0,                    // alpha:Number
               5.0,                    // blurX:Number
               5.0,                    // blurY:Number
               16                      // strength:Number
                                       // quality:int
                                       // inner:Boolean
                                       // knockout:Boolean
            );
      public static var mapglow2:GlowFilter
         = new GlowFilter(// 0xeaf1fc
               Conf.background_color,  // color:uint
               0.6,                    // alpha:Number
               5.5,                    // blurX:Number
               5.5,                    // blurY:Number
                8                      // strength:Number
                                       // quality:int
                                       // inner:Boolean
                                       // knockout:Boolean
            );

      // *** Constructor

      public function UI() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Init method

      //
      public static function init() :void
      {
         m4_DEBUG('init: Conf.welcome_popup:', Conf.welcome_popup);
         if (Conf.welcome_popup !== null) {

            // The notice_bar is somewhat deprecated, or at least there's a
            // cleaner version of it: Pyserver_Message, which shows a banner
            // message spanning the top of the app above the panels and map,
            // that the user can close. And note that the notice_bar gets its
            // message from Conf_Instance, so flashclient needs to be
            // recompiled whenever the message changes. Pyserver_Message gets
            // its message from the server.
            m4_WARNING('Consider using Pyserver_Message instead.');
            G.app.notice_bar.show();

            if (!G.deep_link.pending) {
               // No deep link; just show splash.
               UI.popup(new Conf.welcome_popup());
            }
         }

         UI.throbberers_timer = new Timer(/*delay=*/2500, /*repeatCount=*/0);
         UI.throbberers_timer.addEventListener(
            TimerEvent.TIMER, UI.on_throbberers_timer_timeout);

         UI.throb_sessionless_timer = new Timer(/*delay=*/1250,
                                                /*repeatCount=*/1);
         UI.throb_sessionless_timer.addEventListener(
            TimerEvent.TIMER, UI.on_throb_sessionless_timer_timeout);
      }

      // *** Class getters/setters

      // Return true if one or more popup windows are on-screen.
      //
      // WARNING: I'm not sure how reliable this is. It works for the splash
      //          screen, but I haven't tested it for other popups.
      public static function get popup_present() :Boolean
      {
         return (G.app.systemManager.numModalWindows > 0);
      }

      // *** Static class methods

      // Updates the highlights based on the active or highlighted attachment.
      //
      // FIXME: If there isn't an active attachment, the highlighted
      //        attachment might be a tag or attribute instead... is that
      //        okay? So we just fix the name of this fcn? Or are we missing
      //        code?
      //
      // MAYBE: This class is called from all over. It could use an Event.
      //
      // FIXME: This should ideally handle all attachment-related highlights,
      //        and hence, should be named attachment_highlights_update().
      //
      public static function attachment_highlights_update() :void
      {
         if (G.map === null) {
            // The app is starting up (see main.mxml).
            m4_DEBUG('attachment_highlights_update: Map not ready!');
            return;
         }

         var tstart:int = G.now();

         m4_TALKY('attachment_highlights_update');

         // Start by clearing attachment highlights.
         G.map.highlights_clear(Conf.attachment_highlight);
         G.map.highlights_clear(Conf.attachment_hover_highlight);

         // MAYBE: Should we also call Widget_Tag_Widget.clear_selected()?
         //        And what about Attribute highlights, too? Or don't those
         //        exist (yet)?

         // We used to have G.item_mgr.active_attachment but really the active
         // attachment is set if the user is looking at the attachment details
         // panel, and it's set to the attachment the panel is showing, so we
         // might as well just consult the panel manager.
         m4_ASSERT(G.item_mgr !== null); // Not necessary, but should pass.
         m4_ASSERT(G.panel_mgr !== null); // Is necessary; also should pass.

         // Get the active panel, which isn't necessarily an item panel.
         var active_panel:Detail_Panel_Base;
         active_panel = G.panel_mgr.effectively_active_panel;
         // Not true on startup: m4_ASSERT(active_panel !== null);
         if (active_panel !== null) {
            // See if the user is looking at a note or thread details panel and
            // highlight all the items on the map to which the note or thread
            // applies.
            // Early CcpV2: We used to just highlight byways...
            //    to_h = Link_Value.items_for_attachment(
            //       attachment_panel.attachment, Byway);
            // but now we highlight any item type, since notes and threads
            // can apply to...      any item type.
            var to_h:Array = active_panel.attachment_highlights_update();
            // Go through the linked geofeatures and set the highlight.
            if (to_h !== null) {
               // 2014.07.16: Since when did casting to an incorrect raise
               // an exception rather than rambling on until a null pointer
               // exception? Some this causes as error:
               //
               //   for each (var gf:Geofeature in to_h) { ... }
               //
               // TypeError: Error #1034: Type Coercion failed: cannot convert
               //          items.attcs::Attribute@eb0bd581 to items.Geofeature.
               //
               // So do this the long way, using an intermediate Object.
               for each (var rhs_obj:Object in to_h) {
                  var gf:Geofeature = (rhs_obj as Geofeature);
                  if (gf !== null) {
                     gf.set_highlighted(true, Conf.attachment_highlight);
                  }
                  else {
                     // Threads can link to non-geofeatures, like revision,
                     // which are represented by the /post/revision attribute.
                     m4_ASSERT_SOFT(rhs_obj is Attribute);
                  }
               }
            }
         }

         m4_DEBUG_TIME('attachment_highlights_update');
      }

      //
      public static function cursor_set_native_arrow() :void
      {
         G.map.buttonMode = false;
         //G.map.useHandCursor = false;
      }

      //
      public static function cursor_set_native_finger() :void
      {
         G.map.buttonMode = true;
         //G.map.useHandCursor = true;
      }

      // Enable and disable the editing buttons as appropriate.
      public static function editing_tools_update(access_changed:Boolean=false)
         :void
      {
         // Enable the Undo button if there's stuff on the undo stack.
         G.app.tool_palette.undo.enabled = G.map.cm.undoable();
         // For the toolTip, either indicate that nothing is undoable, or
         // indicate the action that would be undone (e.g., 'Undo create new
         // attribute').
         // 2013.05.13: [lb] sees this toolTip on boot, even though tool
         //             palette is hidden....
         if (G.app.tool_palette.visible) {
            G.app.tool_palette.undo.toolTip = G.map.cm.undo_descriptor;
         }
         else {
            G.app.tool_palette.undo.toolTip = '';
         }

         // Setup the Redo button like we did the Undo button.
         G.app.tool_palette.redo.enabled = G.map.cm.redoable();
         if (G.app.tool_palette.visible) {
            G.app.tool_palette.redo.toolTip = G.map.cm.redo_descriptor;
         }
         else {
            G.app.tool_palette.redo.toolTip = '';
         }
         // Enable/Disable the tool buttons. What happens depends on the zoom
         // level (the user cannot edit at raster level), the revision (the
         // user cannot edit unless revision is Working), and the user's access
         // permissions (Access Level must be 'editor' or better).
         for (var i:int = 0; i < G.app.tool_palette.length; i++) {
            var tool_id:String = G.app.tool_palette.get_tool_id(i);
            var tool:Map_Tool = G.map.tool_dict[tool_id];
            G.app.tool_palette.update_by_index(i, tool.useable);
         }

         // Lastly, if the access level changed, dirty all the panels that
         // care, telling 'em to enable/disable controls as appropriate.
         if (access_changed) {
            //m4_DEBUG_CLLL('>callLater: Side_Pnl.edit_panels_toggle');
            //G.map.callLater(G.panel_mgr.edit_panels_toggle);
            G.panel_mgr.update_access();
         }

         // We track the number of unsaved changes so we can prompt the user to
         // save when appropriate. Note that, if there's nothing on the undo
         // stack, unsaved_change_ct is 0; it doesn't matter what (if anything)
         // is on the redo stack.
         // See also: contains_dirty_revisioned. But the map's command mgr.
         // should only contain dirty map items (it the past, it might have
         // contained revisionless changes).
         if (G.map.cm.unsaved_change_ct <= 0) {
            m4_TALKY('editing_tools_update: save_enabled: disabling');
            // Because clicking Start new discussion can trigger this, do not:
            //m4_ASSERT(!G.item_mgr.contains_dirty_revisioned);
            G.app.tool_palette.save_enabled = false;
         }
         else {
            m4_TALKY('editing_tools_update: save_enabled: enabling');
            m4_DEBUG2('editing_tools_update: G.item_mgr.dirtyset.length:',
                      G.item_mgr.dirtyset.length);
            G.app.tool_palette.save_enabled = true;
         }
      }

      // Complain to the user about something.
      // FIXME: The text should be selectable, so user can cut-n-paste.
      public static function gripe(s:String) :void
      {
         Alert.show(s)
      }

      // Show a remote image in an alert box.
      public static function image_alert(title:String, url:String,
                                         on_close:Function=null) :void
      {
         var p:Image_Popup = new Image_Popup();
         UI.popup(p, 'ok');
         p.init(title, G.url_base + '/' + url, on_close);
      }

      //
      public static function map_mode_label(item:Object) :String
      {
         return "yesyes";
      }

      // Show the mediawiki on a specified page. If already have a MW window
      // open, use it; otherwise open a new one.
      public static function mediawiki(topic:String) :void
      {
         UI.url_popup(Conf.help_url + topic, 'cp_mw');
      }

      // Return a closure which filters mouseout and mouseover events, passing
      // only "real" mouseout/over events to h(). This is necessary due to a
      // quirk in the Flex mouse event model: moving the mouse into or out of
      // a child of a DisplayObjectContainer generates mouseout/over events in
      // the parent even if the mouse hasn't had any transition WRT the
      // parent. Such "fake" events are filtered out by the closure. (Stopping
      // event propagation in the child isn't a general solution, lest direct
      // transitions between fully outside and inside a child be lost.)
      public static function mouseoutover_wrap(d:DisplayObjectContainer,
                                               h:Function) :Function
      {
         return function(ev:MouseEvent) :void
         {
            // In mouseout events, ev.relatedObject is the object
            // _subsequently_ under the cursor; in mouseover events, it's the
            // object _previously_ under the cursor. Therefore, if this object
            // is a (sub)child of d, the event is "fake".
            if (ev.relatedObject === null || !(d.contains(ev.relatedObject))) {
               h(ev);
            }
         }
      }

      //
      public static function on_timeout() :void
      {
         m4_DEBUG('on_timeout');
         Alert_Dialog.hide();
         G.user.reauthenticate();
      }

      // CAVEAT: What about an edited/dirty map? If the user lets
      //         a dirty map idle, we log them out and toss their work!
      // FIXME/BUG nnnn: Make an obvious option for user to disable
      //                 automatic log-off.
      //
      public static function on_timeout_warn() :void
      {
         m4_DEBUG('on_timeout_warn');
         Alert_Dialog.show(
            'Timeout Warning',
            'You seem to be idle. Have you gone away? '
            + 'Please click the button '
            + 'or you will be automatically logged out.',
            /*html?=*/false,
            /*on_ok?=*/G.app.timeout.reset,
            /*ok_label?=*/"I'm still here");
      }

      //
      public static function popup(w:TitleWindow, focus_attr:String=null) :void
      {
         m4_DEBUG('popup: w:', w, '/ focus_attr:', focus_attr);
         PopUpManager.addPopUp(w, G.app, true);
         PopUpManager.centerPopUp(w);
         if (focus_attr !== null) {
            w[focus_attr].setFocus();
         }
      }

      // Update the data request progress bar
      public static function request_progressbar_update() :void
      {
         if (UI.requests_created == 0) {
            //G.app.throb_label.text = 'No outstanding requests';
            //G.app.throb_label.visible = false;
            m4_TALKY('==++== THROBBERS / Stop');
            G.throbber.stop();
         }
         else {
            //G.app.throb_label.text = (requests_completed + ' of '
            //                          + UI.requests_created
            //                          + ' requests complete');
            //G.app.throb_label.visible = true;
            m4_TALKY('==++== THROBBERS / Play');
            G.throbber.play();
         }
      }

      // Possibly show a pointing widget by the Save button; rules:
      //   1. Don't show reminder in raster mode
      //   2. Only show reminder when something is selected or
      //      a tool other than pan_select is active
      //   3. The nearest distance from viewport center to dirty_rect
      //      is more than Conf.save_reminder_distance
      // NOTE: Map_Canvas and Geofeature must call this for #2 to work
      public static function save_remind_maybe() :void
      {
         if (!UI.compact_save_reminded) {
            UI.save_remind_maybe_();
         }
      }

      //
      public static function save_remind_maybe_() :void
      {
         var rect:Rectangle = G.map.cm.dirty_rect;
         var map_x:int = G.map.view_rect.map_center_x;
         var map_y:int = G.map.view_rect.map_center_y;
         var show_reminder:Boolean = false;

         if ((rect !== null)
             && (G.map.zoom_is_vector())
             && ((G.map.selectedset.length > 0)
                 || (!(G.map.tool_cur is Tool_Pan_Select)))) {
            // valid dirty_rect, in vector mode, and have something selected
            if ((map_x < rect.x)
                && ((rect.x - map_x) > UI.curr_sv_remind_dist)) {
               show_reminder = true;
            }
            else if ((map_x > rect.right)
                       && ((map_x - rect.right) > UI.curr_sv_remind_dist)) {
               show_reminder = true;
            }
            else if ((map_y < rect.y)
                       && ((rect.y - map_y) > UI.curr_sv_remind_dist)) {
               show_reminder = true;
            }
            else if ((map_y > rect.bottom
                       && ((map_y - rect.bottom) > UI.curr_sv_remind_dist))) {
               show_reminder = true;
            }
         }

         if (show_reminder
             && ((UI.save_pointer === null)
                 || (UI.save_pointer.is_closed))) {
            // Show a pop-up suggesting that the user save, because they're
            // panning the map far from where they started editing.
            // FIXME: This could be annoying. One mile isn't that much. And
            //        maybe they're just panning for the sake of panning and
            //        aren't really about to edit... oh, well, for now, we'll
            //        just show this dialog once, rather than every time they
            //        pan...
            UI.compact_save_reminded = true;
            UI.save_pointer = Pointing_Widget.show_pointer(
               'Save changes now?',
               'You have moved over a mile from your unsaved changes. '
               + 'Please consider saving now, to keep your changes compact.',
               // NOTE: The 'save' button calls items_save_start.
               G.app.tool_palette.save);
            // grow the threshold so they won't get nagged right away again
            // FIXME: See compact_save_reminded: We only nag once per save
            //        session. (2012.08.16).
            UI.curr_sv_remind_dist = (Conf.save_reminder_distance / 3.0
                                      + Math.max(map_x - rect.right,
                                                 rect.x - map_x,
                                                 rect.y - map_y,
                                                 map_y - rect.bottom));
         }
      }

      // Remove the save reminder pointing widget, if it's up.
      public static function save_reminder_hide() :void
      {
         if (UI.save_pointer !== null) {
            UI.save_pointer.on_close();
            UI.save_pointer = null;
         }
         // 2012.08.16: This fcn. only called just before sending GWIS_Commit
         //             or after discarding all map changes.
         UI.compact_save_reminded = false;
      }

      // Updates the highlights for byways with a tag
      public static function tag_highlights_update(tg:Tag) :void
      {
         var to_h:Array;
         var by:Byway;
         var wp:Waypoint;
         m4_ASSERT(G.map !== null);
         if (G.map === null) {
            return;
         }
         G.map.highlights_clear(Conf.attachment_highlight);
         /* Deprecated: link_values are lazy-loaded for selected items,
                        so not all items will have 'em.
         //to_h = Tag_BS.all_byways(tg);
         to_h = Link_Value.items_for_attachment(tg, Byway);
         if (to_h !== null) {
            for each (by in to_h) {
               by.set_highlighted(true, Conf.attachment_highlight);
            }
         }
         //to_h = Tag_Point.all_geopoints(tg);
         to_h = Link_Value.items_for_attachment(tg, Waypoint);
         if (to_h !== null) {
            for each (wp in to_h) {
               wp.set_highlighted(true, Conf.attachment_highlight);
            }
         }
         */
         for each (var bway:Byway in Byway.all) {
            if (bway.tags.contains(tg.name_)) {
               bway.set_highlighted(true, Conf.attachment_highlight);
            }
         }
         for each (var wayp:Waypoint in Waypoint.all) {
            if (wayp.tags.contains(tg.name_)) {
               wayp.set_highlighted(true, Conf.attachment_highlight);
            }
         }
      }

      //
      public static function url_open_exports() :void
      {
         UI.url_popup(G.url_base + '/exports', 'Cyclopath Exports');
      }

      //
      public static function url_open_reports() :void
      {
         UI.url_popup(G.url_base + '/reports', 'Cyclopath Reports');
      }

      //
      public static function url_popup(url:String, window_tag:String) :void
      {
// FIXME/BUG nnnn/MAYBE: Ask before changing tabs and loading external URL?
//                 [lb] finds it annoying.
//        Make a modal widget. See Splash_Colorado
// this works, but you need a callback before navigating away
//   UI.popup(new Splash_Colorado());

         navigateToURL(new URLRequest(url), window_tag);
      }

      // Decrements the outstanding HTTP request count; stops Throbber when 0
      public static function throbberers_decrement(throb_client:Object) :void
      {
         UI.requests_completed++;
         m4_TALKY2('==++== THROBBERS / Dec / Completed:',
                   UI.requests_completed);
         m4_ASSERT(UI.requests_completed <= UI.requests_created);

         m4_ASSERT_SOFT(UI.throbberer_clients.is_member(throb_client));
         UI.throbberer_clients.remove(throb_client);

         if (UI.requests_created == UI.requests_completed) {
            // Finished everything we started; return to idle state
            m4_TALKY('==++== THROBBERS / Idle!');
            UI.requests_created = 0;
            UI.requests_completed = 0;
            // BUG 2715: Better errors: We kept track of which error messages
            // we've shown so far this throb-session so that we don't show the
            // same error message twice. Reset those trackers.
            UI.throb_session_alerts = new Set_UUID();

            UI.throbberers_timer.reset();
         }

         UI.request_progressbar_update();
      }

      // Increments the count of outstanding HTTP requests that the user should
      // know are outstanding; when nonzero, causes the Throbber to throb
      public static function throbberers_increment(throb_client:Object) :void
      {
         UI.requests_created++;
         m4_TALKY('==++== THROBBERS / Inc / Created:', UI.requests_created);

         m4_ASSERT_SOFT(!(UI.throbberer_clients.is_member(throb_client)));
         var uuid:String = UI.throbberer_clients.add(throb_client);
         m4_TALKY(' .. uuid:', uuid, '/ throb_client:', throb_client);
         //UI.throbberers_timer.reset();
         if (!UI.throbberers_timer.running) {
            UI.throbberers_timer.start();
         }

         UI.request_progressbar_update();
      }

      //
      protected static function on_throbberers_timer_timeout(
         event:TimerEvent) :void
      {
         m4_TALKY2('==++== THROBBERS / waiting on:',
                   UI.throbberer_clients.length);
         for (var uuid:String in UI.throbberer_clients) {
            var throb_client:Object = UI.throbberer_clients[uuid];
            m4_TALKY(' .. uuid:', uuid, '/ throb_client:', throb_client);
         }
      }

      //
      protected static function on_throb_sessionless_timer_timeout(
         event:TimerEvent) :void
      {
         m4_TALKY('on_throb_sessionless_timer_timeout');
         if (!UI.throbberers_timer.running) {
            UI.throb_session_alerts = new Set_UUID();
         }
         m4_ASSERT_ELSE_SOFT; // This actually might happen, and it's
                              // totally fine if it happens because
                              // when the throbberer stops, it'll
                              // cleanup, but [lb] is curious nonetheless.
      }

      //
      public static function throbber_error_register(alert_name:String)
         :Boolean
      {
         //m4_DEBUG3('throbber_error_register: alert_name:', alert_name,
         //          '/ requests_created:', UI.requests_created,
         //          '/ requests_completed:', UI.requests_completed);

         var do_show_error:Boolean = false;

         // Check if the throbberer is running: if it is, don't show the same
         // error message more than once, other the user might have to OK
         // dozens of modal dialogs. If the throbberer is not running, we can
         // just not show the same message is, say, some time period.
         if ((UI.requests_created == 0) && (UI.requests_completed == 0)) {
            // BUG 2715: Better errors: We kept track of which error messages
            // we've shown so far this throb-session so that we don't show the
            // same error message twice. Reset those trackers.
            UI.throb_session_alerts = new Set_UUID();
            m4_ASSERT_SOFT(!UI.throbberers_timer.running);
            UI.throb_sessionless_timer.reset();
            UI.throb_sessionless_timer.start();
         }
         if (!UI.throb_session_alerts.is_member(alert_name)) {
            UI.throb_session_alerts.add(alert_name);
            do_show_error = true;
         }
         return do_show_error;
      }

      // ***

      //
      // FIXME: This fcn. is just used for some errors right now (especially
      //        the wordy, long-winded error messages). But maybe we want to
      //        use this elsewhere, too?
      public static function alert_show_roomy(alert_text:String,
                                              alert_title:String) :void
      {
         // End Alert dialog messages with two newlines (one doesn't help), so
         // that the OK button is lower (separated from the text), and start
         // with one newline to separate from the header.
         //
         // Note also that in Cyclopath, at least circa 2012 and earlier, the
         // border of the alert dialog is almost the same color as a lot of
         // Cyclopath elements in the UI, so it's hard to distinguish the alert
         // dialog. Using these newlines helps make the message for readable.
         Alert.show('\n' + alert_text + '\n\n', alert_title);
      }

   }
}

