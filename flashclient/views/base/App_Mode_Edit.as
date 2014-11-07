/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   //import flash.filters.GlowFilter;
   import flash.utils.Timer;
   //import mx.formatters.DateFormatter;

   import gwis.GWIS_Kval_Get;
   import utils.misc.Logging;
   import utils.misc.Timeutil;
   import views.panel_util.Alert_Dialog;

   public class App_Mode_Edit extends App_Mode_Base {

      // Class attributes.

      protected static var log:Logging = Logging.get_logger('App_Mde_Edit');

      // How often to check the cp_maint_beg/_fin values on the server.
      // This is in lieu of just always including the values in every
      // GWIS packet.
      //protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 1;  // 1 sec
      //protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 2;  // 2 secs
      //protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 5;  // 5 secs
      //protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 10; // 10 secs
      protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 15; // 15 secs
      //protected static const CP_MAINT_INTERVAL:Number = 1000.0 * 30; // 30 secs

      protected static const date_fmt_s:String = 'EEE, MMM DD at L:NN A';

      // *** Instance variables

      // When activated, we check with the server that Editing is okay.
      protected var do_activate:Boolean = false;

      // Millisecs until (or since) start of maintenance (no commits allowed).
      protected var cp_maint_beg:Number = 0;
      // Millisecs until (or since) (estimated) end of maintenance
      //   ("please come back later, at x o'clock").
      protected var cp_maint_fin:Number = 0;
      // While in Edit mode, periodically ping server for maintenance state.
      protected var cp_maint_timer:Timer = null;
      // Remember the state the last time we pinged, so we can alert the user.
      protected var cp_maint_last_state:int = 0;

      // *** Constructor

      //
      public function App_Mode_Edit()
      {
         this.name_ = 'Edit';

         this.glow_filters =
         // 2013.05.07: [mm]'s original color:
         //   [new GlowFilter(0x336699, 0.8, 32, 32, 2, 1, true),];
         // but [lb] thinks it's distracting and detracts from the beauty of
         // the map. I tried a different color (more silvery) but it still
         // doesn't look good.
         //   [new GlowFilter(0xc1c1c1, 0.8, 32, 32, 2, 1, true),];
         // We really don't need to glow, though: The "Editing" button is
         // toggled ON and the tool palette is showing, so [lb] hopes the
         // user knows they're editing.
            [];

         // See App_Action for the complete list of App_Actions.
         // The Edit Mode uses all of them.

         this.allowed = [

            // Map Operations
            App_Action.map_pan_zoom,
            App_Action.item_edit,
            App_Action.item_tag,
            App_Action.item_annotate,
            App_Action.byway_rate,

            // Discussions
            App_Action.post_create,

            // Route Planning
            App_Action.route_request,
            App_Action.route_lib_view,
            App_Action.route_hist_view,
            App_Action.route_modify_new,
            App_Action.route_modify_own,
            App_Action.route_modify_all,
            App_Action.route_print,
            App_Action.route_edit,

            // Search
            App_Action.search_anything,

            // Item Watching and Subscriptions
            App_Action.item_watcher_edit,

            // Settings
            App_Action.settings_edit,
         ];
      }

      // ***

      //
      override public function activate() :void
      {
         m4_DEBUG('activate');
         m4_ASSERT(G.initialized);
         super.activate();
         // Update the View|Edit buttons.
         G.app.main_toolbar.setup_viewing_or_editing(
            /*editing_okay=*/!G.app.edit_restriction,
            /*hide_options=*/null);
         // Double-check the cp_maintenance state.
         this.do_activate = true;
         this.cp_maint_check_mode();

         G.app.addEventListener('modeChange', this.on_mode_change);
      }

      //
      protected function activate_finish() :void
      {
         // Start the cp_maintenance timer.
         if (G.app.mode === this) {
            this.cp_maint_timer = new Timer(CP_MAINT_INTERVAL);
            this.cp_maint_timer.addEventListener(TimerEvent.TIMER,
                                                 this.on_cp_maint_timer);
            this.cp_maint_timer.start();
         }

         this.do_activate = false;
      }

      //
      override public function get uses_editing_tool_palette() :Boolean
      {
         return true;
      }

      // ***

      //
      protected function cp_maint_check_mode() :void
      {
         // We might be called on boot, before the app is ready to send
         // arbitrary requests (though there's really nothing wrong with
         // sending this request; it's just that the update stack is setup
         // to complain if OOBs are sent before the hellos and whatnot).
         m4_DEBUG('cp_maint_check_mode: G.initialized:', G.initialized);
         var kval_keys:Array = null;
         var gwis_req:GWIS_Kval_Get =
            new GWIS_Kval_Get(
               kval_keys,
               this.on_gwis_kval_get_okay,
               this.on_gwis_kval_get_fail);
         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_req);
         // If you set the timer to run fast, since these requests are OOB,
         // if the map is being updated, the OOB commands might start
         // stacking (being sent out faster than we're getting responses).
         // Not true: m4_ASSERT_SOFT(!found_duplicate);
      }

      //
      protected function on_gwis_kval_get_okay(
         gwis_req:GWIS_Kval_Get, xml:XML) :void
      {
         // Some trace helpers... since [lb]'s FleXMLing is a little rusty.
         if (false) {
            m4_DEBUG('on_gwis_kval_get_okay: xml:', xml.toString());
            m4_DEBUG('on_gwis_kval_get_okay: xml..kvals:', xml..kvals);
            // This returns the .text part:
            m4_DEBUG2('on_gwis_kval_get_okay: xml..kvals.cp_maint_beg_age:',
                      xml..kvals.cp_maint_beg_age);
            // That is, this returns null:
            m4_DEBUG2('on_gwis_kval_get_ok: xml..kvals.cp_maint_beg_age.text:',
                      xml..kvals.cp_maint_beg_age.text);
         }

         // The server could send a date, e.g., 2014-02-18 19:52:57.989045-06,
         // but instead it sends num. of milliseconds. A positive value is the
         // number of milliseconds until the event happens; 0 means the event
         // is not scheduled; a negative value is the number of milliseconds
         // since the event occurred.
         var prev_maint_beg:Number = this.cp_maint_beg;
         var prev_maint_fin:Number = this.cp_maint_fin;
         this.cp_maint_beg = Number(xml..kvals.cp_maint_beg_age);
         this.cp_maint_fin = Number(xml..kvals.cp_maint_fin_age);
         this.cp_maint_beg *= 1000.0; // The server sends seconds.
         this.cp_maint_fin *= 1000.0;
         m4_DEBUG('_kval_get_ok: cp_maint_beg:', this.cp_maint_beg);
         m4_DEBUG('_kval_get_ok: cp_maint_fin:', this.cp_maint_fin);

       // help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/Date.html
         var now:Date = new Date();
         // If you're curious...
         //  m4_DEBUG('now.toDateString:', now.toDateString());
         //  m4_DEBUG('now.toLocaleDateString:', now.toLocaleDateString());
         //  m4_DEBUG('now.toLocaleString:', now.toLocaleString());
         //  m4_DEBUG('now.toLocaleTimeString:', now.toLocaleTimeString());
         //  m4_DEBUG('now.toString:', now.toString());
         //  m4_DEBUG('now.toTimeString:', now.toTimeString());
         //  m4_DEBUG('now.toUTCString:', now.toUTCString());
         // Milliseconds since epoch:
         //  m4_DEBUG('now.toTimeString:', now.getTime());

         var current_state:int = this.current_state();
         m4_DEBUG2('on_gwis_kval_get_okay: cur_state:',
                   current_state, '/ last_state:', this.cp_maint_last_state);
         if (current_state != this.cp_maint_last_state) {
            if (G.map.tool_cur.dragging) {
               // Wait for user to complete what they're doing.
               // 2014.04.21: [lb] tested this by hand using litemaint.sh
               //             and a long mouse press.
               m4_DEBUG('on_gwis_kval_get_okay: action: wait for mouse up');
               G.map.addEventListener(MouseEvent.MOUSE_UP,
                                      this.on_map_mouse_up);
               // We'll call alert_user on mouse up.
            }
            else {
               m4_DEBUG('on_gwis_kval_get_okay: action: alerting user');
               this.alert_user(current_state);
               // Note that alert_user calls update_maintenance_message.
            }
         }
         else {
            // The state didn't change... but maybe the server's time
            // estimate(s) changed, so at least update the display.
            m4_DEBUG('on_gwis_kval_get_okay: action: no state change');
            if ((current_state != 0)
                && (   (prev_maint_beg != this.cp_maint_beg)
                    || (prev_maint_fin != this.cp_maint_fin))) {
               this.update_maintenance_message(current_state);
            }
            else {
               // else, maintenance disabled and not scheduled,
               //       and state did not change.
               if (this.do_activate) {
                  this.activate_finish();
                  this.do_activate = false;
               }
            }
         }
      }

      //
      protected function on_gwis_kval_get_fail(
         gwis_req:GWIS_Kval_Get, rset:XML) :void
      {
         // Ha, this fires when, e.g., the database is shutting down...
         // 2014.09.09: Happened twice to anon users in last ten days.
         //             Is this a problem or not? The GWIS command is
         //             trying to get the cp_maint_beg and cp_maint_fin,
         //             since kval_keys:Array = null. So why would that
         //             fail? Perhaps it was I, [lb], debugging... I
         //             could dig deeper into the logs and find out,
         //             but we'll save that exercise for another day
         //             (that day being when this assert fires again
         //             and I don't think it's my fault).
         m4_ASSERT_SOFT(false);
         // EXPLAIN: The user should see a generic network error... right?
      }

      // ***

      // MAYBE: The following is view code, but App_Mode_Edit is definately
      //        model code. Should we move this code and wire it differently?
      //        Maybe Message_Maintenance.mxml should listen on a change-mode
      //        event...

      //
      protected function alert_user(current_state:int) :void
      {
         var force_show_message:Boolean = false;

         var edited:Boolean = ((G.map.cm.redo_length > 0)
                               || (G.map.cm.undo_length > 0));

         m4_DEBUG5('alert_user: current_state:', current_state,
                   '/ last_state:', this.cp_maint_last_state,
                   '/ cp_maint_beg:', this.cp_maint_beg,
                   '/ cp_maint_fin:', this.cp_maint_fin,
                   '/ edited:', edited);

         // Alert user of state change. With a nasty modal dialog.
         if (this.cp_maint_last_state == 0) {
            if (this.cp_maint_beg != 0) {
               var now:Date = new Date();
               // Always show a dialog when user is editing
               // and server is going into maintenance mode.
               var alert_title:String = '';
               var alert_text:String = '';
               if (this.cp_maint_beg > 0) {
                  alert_title = "Scheduled maintenance";
                  alert_text +=
                     'We will be updating the database soon.\n\n'
                  if (edited) {
                     alert_text +=
                        'Please finish your work now and save changes. '
                        + 'You will not be able to save changes once '
                        + 'we start the update process.\n\n';
                  }
                  else {
                     alert_text +=
                        'You can edit and save the map before we start '
                        + 'updating, but we\n'
                        + 'suggest waiting until after we have updated '
                        + 'the database.\n\n';
                  }
                  alert_text +=
                     'The update will begin on '
                     + Timeutil.datetime_to_friendlier(
                        new Date(now.getTime() + this.cp_maint_beg),
                        App_Mode_Edit.date_fmt_s)
                     + '.\nWe should be done by '
                     + Timeutil.datetime_to_friendlier(
                        new Date(now.getTime() + this.cp_maint_fin),
                        App_Mode_Edit.date_fmt_s)
                     + '.';
               }
               else {
                  // cp_maint_beg is negative, so server is under maintenance.
                  alert_title = "Undergoing maintenance";
                  alert_text =
                     'We are updating the database on the server.\n\n';
                  if (edited) {
                     alert_text +=
                        'If you have unsaved changes, you may be able '
                        + 'to save them later... if you are not automatically '
                        + 'logged off before then, and if the database update '
                        + 'does not change things too drastically.\n\n';
                  }
                  else {
                     alert_text +=
                        'You can edit the map in your browser while we '
                        + 'upgrade the database, but we cannot guarantee '
                        + 'that you will be able to save the changes after '
                        + 'the update is complete.\n\n';
                  }
                  if (this.cp_maint_fin > 0) {
                     alert_text +=
                        'We should be done by '
                        + Timeutil.datetime_to_friendlier(
                           new Date(now.getTime() + this.cp_maint_fin),
                           App_Mode_Edit.date_fmt_s)
                        + '.';
                  }
                  else {
                     alert_text +=
                        'We are not sure how long the update will run. '
                        + 'Please check back soon!';
                  }
               }
               if ((this.do_activate) || (G.app.mode === this)) {
                  m4_DEBUG('alert_user: alert_text:', alert_text);
                  Alert_Dialog.show(
                     alert_title,
                     alert_text,
                     /*html?=*/false,
                     /*on_ok?=*/null,//this.on_alert_message_got_it,
                     /*ok_label?=*/'Got it!',
                     /*on_cancel?=*/null,
                     /*cancel_label=*/null,
                     /*on_third_option=*/null,
                     /*third_option_label=*/null,
                     /*callback_data=*/null);
               }
               
               // Unhide the maintenance message if it was previously hidden.
               force_show_message = true;

            } // end: if (this.cp_maint_beg != 0)
            // else, both states 0, so nothing to do.

         } // end: if (this.cp_maint_last_state == 0)
         // else, the last state was not 0, so we've alerted the user already
         // about the scheduled maintenance. We might force-show the message
         // if we need to tell the user that the update is done, but we won't
         // do a modal alert.

         this.update_maintenance_message(current_state, force_show_message);
      }

      //
      protected function update_maintenance_message(
         current_state:int,
         force_show_message:Boolean=false) :void
      {
         m4_DEBUG2('update_maintenance_message: current_state:', current_state,
                   '/ force_show_message:', force_show_message);

         var msg:String;

         var now:Date = new Date();
         // SYNC_ME: The text herein is very much like the fcn. above us.
         if (this.cp_maint_beg > 0) {
            msg =
                 'We will be updating the database soon. You can <br/>'
               + 'save map changes up until we start the update.<br/><br/>'
               + 'The update will begin on '
               + Timeutil.datetime_to_friendlier(
                  new Date(now.getTime() + this.cp_maint_beg),
                  App_Mode_Edit.date_fmt_s)
               + '.<br/>We should be done by '
               + Timeutil.datetime_to_friendlier(
                  new Date(now.getTime() + this.cp_maint_fin),
                  App_Mode_Edit.date_fmt_s)
               + '.';
         }
         else if (this.cp_maint_beg < 0) {
            msg =
               'We are updating the database, and users cannot save <br/>'
               + 'map changes until the update is complete.<br/><br/>';
            if (this.cp_maint_fin > 0) {
               msg +=
                  'We should be done by '
                  + Timeutil.datetime_to_friendlier(
                     new Date(now.getTime() + this.cp_maint_fin),
                     App_Mode_Edit.date_fmt_s)
                  + '.';
            }
            else {
               msg +=
                  'We are not sure how long the update will run. <br/>'
                  + 'Please check back soon!';
            }
         }
         else {
            // So, this.cp_maint_beg == 0, and this.current_state() == 0.
            msg =
               'We are finished updating the database.<br/><br/> '
               + 'Thanks for your patience! And thank you for editing!!';
            force_show_message = true;
         }

         m4_DEBUG('update_maintenance_message: msg:', msg);
         G.app.maintenance_msg_fake.pyserver_message_text.htmlText = msg;
         G.app.maintenance_msg_real.pyserver_message_text.htmlText = msg;
         
         if ((G.app.mode === this)
             && (force_show_message
                 || (this.cp_maint_last_state == 0))) {

            var is_later:Boolean = false;
            G.app.maintenance_msg_fake.component_fade_into(
                              is_later, force_show_message);
         }

         this.cp_maint_last_state = this.current_state();

         if (this.do_activate) {
            this.activate_finish();
            this.do_activate = false;
         }
      }

      // ***

      //
      public function current_state() :int
      {
         var current_state:int = 0;
         if (this.cp_maint_beg < 0) {
            // The server is undergoing maintenance. No commits allowed.
            current_state = -1;
         }
         else if (this.cp_maint_beg > 0) {
            // The server will be upgraded soon. "Save your work now!"
            current_state = 1;
         }
         else {
            // There is no maintenance happening and none planned.
            current_state = 0;
         }
         return current_state;
      }

      //
      public function on_map_mouse_up(ev:MouseEvent) :void
      {
         m4_DEBUG('on_map_mouse_up: target:', ev.target);
         G.map.removeEventListener(MouseEvent.MOUSE_DOWN,
                                   this.on_map_mouse_up);
         var current_state:int = this.current_state();
         this.alert_user(current_state);
      }

      // ***

      //
      protected function on_cp_maint_timer(ev:TimerEvent) :void
      {
         m4_DEBUG('on_cp_maint_timer');
         this.cp_maint_check_mode();
      }

      //
      protected function on_mode_change(event:Event=null) :void
      {
         m4_DEBUG('on_mode_change');

         if (G.app.mode !== this) {

            if (this.cp_maint_timer !== null) {
               this.cp_maint_timer.stop();
               this.cp_maint_timer = null;
            }

            G.app.maintenance_msg_fake.pyserver_message_text.htmlText = '';
            G.app.maintenance_msg_real.pyserver_message_text.htmlText = '';
            G.app.maintenance_msg_real.component_fade_away();

            // Reset the last state, so that we'll alert again next edit mode.
            this.cp_maint_last_state = 0;

            G.app.removeEventListener('modeChange', this.on_mode_change);
         }
      }

   }
}

