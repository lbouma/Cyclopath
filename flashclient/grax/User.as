/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import flash.utils.getQualifiedClassName;
   import mx.controls.Alert;
   import mx.core.IUID;
   import mx.events.CloseEvent;
   import mx.managers.PopUpManager;
   import mx.utils.UIDUtil;

   import gwis.GWIS_Handshake;
   import gwis.GWIS_User_Preference_Put;
   import items.attcs.Tag;
   import items.feats.Byway;
   import items.gracs.Group_Membership;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.base.UI;
   import views.map_components.Ban_Warning_Popup;
   import views.map_components.Login_Popup;
   import views.panel_routes.Route_Viz;
   import views.panel_util.Alert_Dialog;
   import views.section_header.Account_Control;

   public class User {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('User');

      // *** Instance variables

      public var login_window:Login_Popup;
      public var username:String;
      public var token:String;
      public var email:String;

      [Bindable] public var logged_in:Boolean = false;

      // *** User-settable Persistable Options.

      public var enable_watchers_email:Boolean;
      public var enable_watchers_digest:Boolean;

      // Which planner to use by default.

      public var rf_planner_default:int = Conf.rf_planner_default_default;
      protected var rf_planner_default_old:int;

      // The classic route finder's priority parameter.

      public var rf_p1_priority:Number = Conf.rf_p1_priority_default;
      protected var rf_p1_priority_old:Number;

      // The multimodal route finder's on/off switch and adjustment value.

      public var rf_p2_transit_pref:int = Conf.rf_p2_transit_pref_default;
      protected var rf_p2_transit_pref_old:int;

      // The static planner's various parameters.

      public var rf_p3_weight_type:String = Conf.rf_p3_weight_type_default;
      protected var rf_p3_weight_type_old:String;
      public var rf_p3_rating_pump:int = Conf.rf_p3_rating_pump_default;
      protected var rf_p3_rating_pump_old:int;
      public var rf_p3_burden_pump:int = Conf.rf_p3_burden_pump_default;
      protected var rf_p3_burden_pump_old:int;
      public var rf_p3_spalgorithm:String = Conf.rf_p3_spalgorithm_default;
      protected var rf_p3_spalgorithm_old:String;

      // New, easily expandable generic user settings "pickle".
      // ("Easily expandable" == no changes to database or pyserver.)

      public var flashclient_settings:String =
         Conf.flashclient_settings_default;
      protected var flashclient_settings_old:String;

      public var routefinder_settings:String =
         Conf.routefinder_settings_default;
      protected var routefinder_settings_old:String;

      // EXPLAIN: Why do we init to random?
      //protected var _route_viz:Route_Viz = Route_Viz.random();
      // UG: Be consistent. Default to generic flat color.
      // BUG nnnn: How does user set default route viz?
      //           Currently, the user's cookie stores the route viz they last
      //           selected for any route, but maybe we should put the same
      //           dropdown on the Map Settings panel.
      // Use the 'Normal' route viz... which is a solic lame line.
      protected var route_viz_:Route_Viz = Conf.route_vizs[0];

      // ***

      // Not a user pref; if user's emails have come back undeliverable,
      // we'll notify them and ask them to update their email address, or
      // to re-confirm existing email address.
      public var email_bouncing_griped:Boolean = false;

      // Read-only, a flag to say whether or not user preferences should
      // be saved in a cookie, too since we won't need to make a hello request
      public var rememberme:Boolean;

      // This is set to true if the server has informed us that previously
      // valid credentials are no longer valid.
      public var reauthenticating:Boolean = false;

      // Strings storing the expiration date of the different types of bans
      // If null, then there is no ban for that type.
      public var public_user_ban:String = null;
      public var full_user_ban:String = null;
      public var public_ip_ban:String = null;
      public var full_ip_ban:String = null;

      public var private_group_id:int = 0;

      // *** Constructor

      public function User()
      {
         // no-op
      }

      // ***

      //
      public function toString() :String
      {
         return (getQualifiedClassName(this)
                 + '/ username ' + this.username
                 + '/ token ' + this.token
                 + '/ email ' + this.email
                 + '/ logged_in ' + this.logged_in
                 );
      }

      // *** Startup methods

      //
      public function startup() :void
      {
         // NOTE: G.fcookies_user.get returns null if the cookie isn't there.
         var cookie_username:String = G.fcookies_user.get('username');
         var cookie_token:String = G.fcookies_user.get('token');

         var prefs:XML = <preferences/>

         // Argh... we're faking preferences so other fcns. can just use the
         // same XML the server returns, but we're also duplicating setting
         // defaults, for the fourth time! E.g., search this file for
         // Conf.rf_p2_transit_pref_default.

         if (G.fcookies_user.get('route_viz') === null) {
            // MAGIC_NUMBER: The route_viz ranges from 1 to 6, 1 being normal.
            G.fcookies_user.set('route_viz', Conf.route_vizs[0].id_);
         }
         prefs.@route_viz = G.fcookies_user.get('route_viz');

         if (G.fcookies_user.get('enable_watchers_email') === null) {
            G.fcookies_user.set('enable_watchers_email', false);
         }
         prefs.@enable_watchers_email
            = G.fcookies_user.get('enable_watchers_email');

         if (G.fcookies_user.get('enable_watchers_digest') === null) {
            G.fcookies_user.set('enable_watchers_digest', false);
         }
         prefs.@enable_watchers_digest
            = G.fcookies_user.get('enable_watchers_digest');

         if (G.fcookies_user.get('rf_planner_default') === null) {
            G.fcookies_user.set('rf_planner_default',
                                Conf.rf_planner_default_default);
         }
         prefs.@rf_planner = G.fcookies_user.get('rf_planner_default');

         if (G.fcookies_user.get('rf_p1_priority') === null) {
            G.fcookies_user.set('rf_p1_priority',
                                Conf.rf_p1_priority_default);
         }
         prefs.@rf_p1_priority = G.fcookies_user.get('rf_p1_priority');

         if (G.fcookies_user.get('rf_p2_transit_pref') === null) {
            G.fcookies_user.set('rf_p2_transit_pref',
                                Conf.rf_p2_transit_pref_default);
         }
         prefs.@rf_p2_transit_pref = G.fcookies_user.get('rf_p2_transit_pref');

         if (G.fcookies_user.get('rf_p3_weight_type') === null) {
            G.fcookies_user.set('rf_p3_weight_type',
                                Conf.rf_p3_weight_type_default);
         }
         prefs.@p3_wgt = G.fcookies_user.get('rf_p3_weight_type');

         if (G.fcookies_user.get('rf_p3_rating_pump') === null) {
            G.fcookies_user.set('rf_p3_rating_pump',
                                Conf.rf_p3_rating_pump_default);
         }
         prefs.@p3_rgi = G.fcookies_user.get('rf_p3_rating_pump');

         if (G.fcookies_user.get('rf_p3_burden_pump') === null) {
            G.fcookies_user.set('rf_p3_burden_pump',
                                Conf.rf_p3_burden_pump_default);
         }
         prefs.@p3_bdn = G.fcookies_user.get('rf_p3_burden_pump');

         if (G.fcookies_user.get('rf_p3_spalgorithm') === null) {
            G.fcookies_user.set('rf_p3_spalgorithm',
                                Conf.rf_p3_spalgorithm_default);
         }
         prefs.@p3_alg = G.fcookies_user.get('rf_p3_spalgorithm');

         //if (G.fcookies_user.get('flashclient_settings') === null) {
         //   G.fcookies_user.set('flashclient_settings',
         //                       Conf.flashclient_settings_default);
         //}
         //prefs.@fc_opts = G.fcookies_user.get('flashclient_settings');

         if (G.fcookies_user.get('routefinder_settings') === null) {
            G.fcookies_user.set('routefinder_settings',
                                Conf.routefinder_settings_default);
         }
         prefs.@rf_opts = G.fcookies_user.get('routefinder_settings');

         // Create an anonymous tracking cookie if one does not already exist;
         // this cookie should not ever be cleared.
         // NOTE: The session ID is generated by the server, but the browser ID
         //       is generated by the client. This is because the session ID is
         //       much more secure than the browser ID. I.e., the session ID is
         //       used to provide personalized service throughout a session.
         //       The browser ID, on the other hand, merely helps us track data
         //       general usage, but not to provide personalized service --
         //       whether the computer is at the library or at a family home,
         //       we have no idea which user is operating the current session.
         //       I.e., during a single session, we can assume the same user,
         //       but across sessions, we can't. So the browid is just for
         //       research, so its UUID -- while almost more probably unique --
         //       can be generated by the client (whereas the session ID should
         //       be generated by the server so it can ensure uniqueness).
         if (G.fcookies_anon.get('browid') === null) {
            G.fcookies_anon.set('browid', UIDUtil.createUID(), true);
         }
         G.browid = G.fcookies_anon.get('browid');

         if ((cookie_username !== null) && (cookie_token !== null)) {
            // found a cookie; use those creds
            this.login_finish(cookie_username, cookie_token, prefs, true);
            // NOTE: Since we're not sending GWIS_Handshake, we're not
            //       receiving the user's preferences stored in the
            //       database. So hopefully the ones in the Flash
            //       cookies are up-to-date.
            //       BUG nnnn: If user logs on from another machine/browser
            //       and changes their preferences and then returns to a
            //       machine/browser they've used previously, they'll be
            //       using whatever preferences were in that browser's
            //       cookies.
         }
         else {
            this.logout();
            this.force_login_maybe();
         }
      }

      //
      protected function startup_complete() :void
      {
         G.deep_link.load_deep_link(Deep_Link.STARTUP_COMPLETE);
         // FIXME: For now, marking all panels dirty. But maybe firing the
         //        event is enough.
         m4_DEBUG('startup_complete: panels_mark_dirty');
         G.panel_mgr.panels_mark_dirty();
         // 2013.02.14: The user change event used to fire from login_finish
         //             but force_login_maybe takes a shortcut, so we need it
         //             here. The event also fires from logout.
         // NOTE: In CcpV1, this class used to toggle the UI, but we should
         //       make sure everything is event-based now, so maintaining code
         //       is easier.
         // Alert listeners that the loggedin user changed. Most listeners name
         // their callback: on_user_change.
         m4_DEBUG('startup_complete: dispatchEvent: user_event_change');
         G.app.dispatchEvent(new Event('user_event_change'));
      }

      // *** Logging in and logging out

      //
      // FIXME: This fcn. doesn't really belong here. Not sure where it r. does
      public static function alert_unsaved(action_desc:String,
                                           alert_handler:Function) :void
      {
         // NOTE: The two callers check G.item_mgr.contains_dirty_any, which
         //       applies to both changed map items and also edited routes.
         //
         // HACK: 'tis this holiday season 2013. Let's just do this...
         var what_edits:String;
         if ((G.item_mgr.contains_dirty_revisioned)
             && (G.item_mgr.contains_dirty_revisionless)) {
            what_edits = 'map edits and route changes';
         }
         else if (G.item_mgr.contains_dirty_revisioned) {
            what_edits = 'map edits';
         }
         else if (G.item_mgr.contains_dirty_revisionless) {
            what_edits = 'route changes';
         }
         else if (G.item_mgr.contains_dirty_changeless) {
            what_edits = 'ratings and watchers';
         }
         else {
            m4_ASSERT_SOFT(false); // Shouldn't happen.
         }

         // action_desc is, e.g., 'change maps', or 'log out'.

         if (what_edits) {

            // E.g., 'You have unsaved map edits and route changes.
            //        Discard them and log out?'
            var body:String = 
               'You have unsaved ' + what_edits + '. '
               + 'Discard them and ' + action_desc + '?';

            Alert.show(
               body,
               'Discard changes?',
               Alert.CANCEL | Alert.OK,
               null,
               alert_handler,
               null,
               Alert.OK);
         }
      }

      //
      public function get anonymous() :Boolean
      {
         // 2013.04.08: [lb] knows we don't really need this fcn., since code
         //             just checks G.user.logged_in, but this is for DEVs who
         //             search flashclient for anonymous and would get nil hits
         //             otherwise.
         return (!this.logged_in);
      }

      //
      protected function force_login_maybe() :void
      {
         if (Conf.force_login || G.deep_link.wants_login) {
            this.login_popup_open();
         }
         else {
            this.startup_complete();
         }
      }

      //
      public static function is_anonymous(username:String) :Boolean
      {
         var is_anon:Boolean = false;
         // If we don't have the user ID, e.g., when route fetches and
         // returns item_stack.created_user, than we have to check for
         // special prefixes.
         //   2013.05.21: This fcn. is only called by Widget_Gia_Sharing
         //               so it can pretty-print anonymous user name.
         const anon_prefix:String = "_user_anon_";
         if (username.substr(0, anon_prefix.length) == anon_prefix) {
            // E.g., _user_anon_minnesota.
            is_anon = true;
         }
         return is_anon;
      }

      //
      public function get is_banned() :Boolean
      {
         return (this.public_user_ban !== null
                 || this.public_ip_ban !== null
                 || this.is_full_banned);
      }

      //
      public function get is_full_banned() :Boolean
      {
         return (this.full_user_ban !== null
                 || this.full_ip_ban !== null);
      }

      //
      public function is_rememberingme() :Boolean
      {
         return G.fcookies_user.has('username');
      }

      // Complete the login process.
      public function login_finish(username:String,
                                   token:String,
                                   preferences:XML,
                                   rememberme:Boolean) :void
      {
         var viz_index:int;

         this.username = username;
         this.token = token;
         m4_DEBUG('login_finish: new token:', token);
         this.logged_in = true;

         this.email = preferences.@email;

         this.enable_watchers_email
            = Boolean(int(preferences.@enable_watchers_email));
         this.enable_watchers_digest
            = Boolean(int(preferences.@enable_watchers_digest));

         m4_ASSERT(preferences.@route_viz.length() > 0);
         viz_index = int(preferences.@route_viz) - 1;
         // Old cookies may be missing route_viz - so only try to
         // look up in the table if viz_index smells good. Also, we assign
         // directly to the real variable (bypassing the setter) because this
         // shouldn't generate a PutPreference request.
         if (viz_index >= 0) {
            this.route_viz_ = Conf.route_vizs[viz_index];
         }

         if (preferences.@rf_planner.length() > 0) {
            this.rf_planner_default = int(preferences.@rf_planner);
         }
         else {
            this.rf_planner_default = Conf.rf_planner_default_default;
         }

         // When the user adjusts the bikeability slider on the get new route
         // panel, we'll update their route finder priority preference, whose
         // value we'll send to the server when the user hits Find Route...
         // if the user has enabled the classic route finder.
         if (preferences.@rf_p1_priority.length() > 0) {
            this.rf_p1_priority = Number(preferences.@rf_p1_priority);
            // Old cookies may cause rf_p1_priority to be NaN
            if (isNaN(this.rf_p1_priority)) {
               this.rf_p1_priority = Conf.rf_p1_priority_default;
            }
         }
         else {
            this.rf_p1_priority = Conf.rf_p1_priority_default;
         }

         // Get the transit slider value (more biking / more busing).
         if (preferences.@rf_p2_transit_pref.length() > 0) {
            this.rf_p2_transit_pref = int(preferences.@rf_p2_transit_pref);
         }
         else {
            this.rf_p2_transit_pref = Conf.rf_p2_transit_pref_default;
         }

         if (preferences.@p3_wgt.length() > 0) {
            this.rf_p3_weight_type = preferences.@p3_wgt;
         }
         else {
            this.rf_p3_weight_type = Conf.rf_p3_weight_type_default;
         }

         if (preferences.@p3_rgi.length() > 0) {
            this.rf_p3_rating_pump = int(preferences.@p3_rgi);
         }
         else {
            this.rf_p3_rating_pump = Conf.rf_p3_rating_pump_default;
         }

         if (preferences.@p3_bdn.length() > 0) {
            this.rf_p3_burden_pump = int(preferences.@p3_bdn);
         }
         else {
            this.rf_p3_burden_pump = Conf.rf_p3_burden_pump_default;
         }

         if (preferences.@p3_alg.length() > 0) {
            this.rf_p3_spalgorithm = preferences.@p3_alg;
         }
         else {
            this.rf_p3_spalgorithm = Conf.rf_p3_spalgorithm_default;
         }

         if (preferences.@fc_opts.length() > 0) {
            this.flashclient_settings = preferences.@fc_opts;
            m4_DEBUG2('login_finish: flashclient_settings:',
                      this.flashclient_settings);
         }
         else {
            this.flashclient_settings = Conf.flashclient_settings_default;
         }

         if (preferences.@rf_opts.length() > 0) {
            this.routefinder_settings = preferences.@rf_opts;
            m4_DEBUG2('login_finish: routefinder_settings:',
                      this.routefinder_settings);
         }
         else {
            this.routefinder_settings = Conf.routefinder_settings_default;
         }

         // If the user has a stale token, we'll ask them to login again, and
         // we'll retry all the GWIS requests that got the resp 'badtoken'.
         /* 2013.05.12: Because of how Update sets up commands, it doesn't make
                        sense to retry failed commands, but to just start over.
                        For whatever reason, CcpV1 does it (maybe it's just
                        easier to recycle failed GWIS commands?) but in CcpV2,
                        nuh-uh.
         if (this.reauthenticating) {
            // 2013.02.14: [lb] is not convinced that this works as expected.
            // But maybe it does. If a GWIS reply is 'badtoken', the GWIS
            // request puts itself on the retry list. But how does this work
            // with the Update class? And how exactly do we test this path?
            // 2013.05.12: Well, in CcpV2, we at least have to go through the
            // GWIS commands we're retrying and rewrite the credentials so they
            // use the new token. It still seems weird to be reusing/resending
            // GWIS commands...
            GWIS_Base.retry_all();
         }
         else {
         */
            // This is the normal path: dump all items and reload from scratch.
            G.map.rev_loadnext = new utils.rev_spec.Current();
            var user_loggingin:Boolean = true;
            var user_loggedout:Boolean = false;
            var branch_changed:Boolean = false;
            G.map.discard_and_update(user_loggingin, user_loggedout,
                                     branch_changed);
         /*
         }
         */

         this.reauthenticating = false;
         this.rememberme = rememberme;

         /*/ MAYBE: The is [lb]'s tooltip from CcpV3. Use w/ Statewide UI?
         G.app.hello.text = 'Welcome, ' + this.username; // + '!';
         G.app.hello.toolTip = 'Thanks for making Cyclopath awesome, '
                               + this.username + '!';
         /*/
         // FIXME: This component should listen on user_event_change.
         var account_control:Account_Control
            = G.app.ccp_header.account_control;
         account_control.banner_button_user_login.label = 'Log Out';
         G.app.ccp_header.account_control.help_link_sign_up.visible = false;

         if (rememberme) {
            G.fcookies_user.set('username', this.username);
            G.fcookies_user.set('enable_watchers_email',
                                int(this.enable_watchers_email));
            G.fcookies_user.set('enable_watchers_digest',
                                int(this.enable_watchers_digest));
            G.fcookies_user.set('route_viz', int(this.route_viz.id_));
            G.fcookies_user.set('rf_planner_default',
                                int(this.rf_planner_default));
            G.fcookies_user.set('rf_p1_priority', this.rf_p1_priority);
            G.fcookies_user.set('rf_p2_transit_pref', this.rf_p2_transit_pref);
            G.fcookies_user.set('rf_p3_weight_type', this.rf_p3_weight_type);
            G.fcookies_user.set('rf_p3_rating_pump',
                                int(this.rf_p3_rating_pump));
            G.fcookies_user.set('rf_p3_burden_pump',
                                int(this.rf_p3_burden_pump));
            G.fcookies_user.set('rf_p3_spalgorithm', this.rf_p3_spalgorithm);
            //G.fcookies_user.set('flashclient_settings',
            //                    this.flashclient_settings);
            G.fcookies_user.set('routefinder_settings',
                                this.routefinder_settings);
            G.fcookies_user.set('token', this.token, true);
         }
         else {
            G.fcookies_user.clear();
            G.app.timeout.start();
         }
         if ((this.login_window !== null)
             && !(this.login_window.enabled)) {
            m4_DEBUG('login_finish: setting login_window.enabled');
            this.login_window.enabled = true;
            m4_DEBUG('login_finish: removePopUp login_window');
            PopUpManager.removePopUp(this.login_window);
         }

         // FIXME: This component should listen on user_event_change.
         // FIXME: Statewide UI: Reimplement historic browsing.
         //        G.tabs.changes.history_browser_update();

         // We can't do this here: we're about to trigger Update_User, which
         // will dump any outstanding out-of-band requests.
         //  See elsewhere: G.deep_link.load_deep_link(Deep_Link.LOGGED_IN);

         this.startup_complete();
      }

      // Toggle the login state: if logged in, log out; otherwise (logged
      // out), pop up the login box.
      public function login_or_logout() :void
      {
         // reset the ban record for a new user (anonymous or actual).
         this.public_user_ban = null;
         this.full_user_ban = null;
         this.public_ip_ban = null;
         this.full_ip_ban = null;

         if (this.logged_in) {
            if (G.item_mgr.contains_dirty_any) {
               User.alert_unsaved('log out', this.logout_alert_handler);
            }
            else {
               this.logout();
            }
            if (!(this.logged_in)) {
               this.force_login_maybe();
            }
         }
         else {
            this.login_popup_open();
         }
      }

      // Pop up the login window
      public function login_popup_open() :void
      {
         if (this.login_window === null) {
            this.login_window = new Login_Popup();
         }
         m4_DEBUG('login_popup_open: addPopUp login_window');
         PopUpManager.addPopUp(this.login_window, G.app, true);
         PopUpManager.centerPopUp(this.login_window);
         this.login_window.password.text = '';
         this.login_window.username.text = this.username;
         if (!(this.reauthenticating)) {
            this.login_window.username.editable = true;
            this.login_window.username.setStyle('borderStyle', 'inset');
            this.login_window.username.setFocus();
         }
         else {
            this.login_window.username.editable = false;
            this.login_window.username.setStyle('borderStyle', 'none');
            this.login_window.password.setFocus();
         }
      }

      // Begin the login process. (Callbacks in GWIS_Handshake deal with its
      // completion.) Note: This is for sending a password. If we've stored
      // a token, this fcn. isn't called (and GWIS_Handshake not sent).
      public function login_start() :void
      {
         m4_DEBUG('login_start: dispatchEvent: user_event_changing');
         G.app.dispatchEvent(new Event('user_event_changing'));

         this.token = null;
         this.email = null;
         this.logged_in = false;
         this.enable_watchers_email = false;
         this.enable_watchers_digest = false;

         this.username = this.login_window.username.text;
         var password:String = this.login_window.password.text;

         var gwis_req:GWIS_Handshake;
         gwis_req = new GWIS_Handshake(
            this.username,
            password,
            this.login_window.rememberme.selected);
         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_req);
         m4_ASSERT_SOFT(!found_duplicate);

         m4_DEBUG('login_start: setting login_window.enabled');
         this.login_window.enabled = false;
      }

      // User clicked cancel in the login popup.
      public function login_popup_cancel() :void
      {
         if (this.reauthenticating) {
            this.logout();
         }
         G.deep_link.login_canceled();

         // Remove the login window
         m4_DEBUG('login_popup_cancel: removePopUp login_window');
         PopUpManager.removePopUp(this.login_window);
         if (!(this.logged_in)) {
            this.force_login_maybe();
         }
      }

      // Log out
      public function logout() :void
      {
         this.reauthenticating = false;
         this.logged_in = false;
         this.username = null;
         this.token = null;
         this.rememberme = false;
         this.enable_watchers_email = true;
         this.enable_watchers_digest = false;

         // FIXME: Save queued non wiki items.

         G.fcookies_user.clear();

         /*/ MAYBE: The is [lb]'s tooltip from CcpV3. Use w/ Statewide UI?
         //G.app.hello.text = 'Welcome!';
         // FIXME: Random welcome text, just like we do for the logging facil?
         const welcome_text:Array = [
            'Welcome!'
            ,'Welcome to Cyclopath Minneapolis!'
            ,'Rubber Side Down!'
            ,'What\'s Your Route?'
            ]
         var random_n:int = Math.floor(Math.random() * welcome_text.length);
         m4_DEBUG('random_n:', random_n);
         G.app.hello.text = welcome_text[random_n];
         /*/
         // FIXME: This component should listen on user_event_change.
         var account_control:Account_Control
            = G.app.ccp_header.account_control;
         account_control.banner_button_user_login.label = 'Log In';
         // MAYBE: Why not: "Log In | Signup" instead? Like, two buttons?
         // account_control.banner_button_user_login.toolTip =
         //    'Click here to login or to sign up for a free account.';
         account_control.banner_button_user_login.toolTip =
            'Welcome to Cyclopath! '
            + 'Click "Log In" to sign up for a free account.';
         account_control.help_link_sign_up.visible = true;

         G.app.timeout.stop();

         G.map.rev_loadnext = new utils.rev_spec.Current();
         var user_loggingin:Boolean = false;
         var user_loggedout:Boolean = true;
         var branch_changed:Boolean = false;
         // Is the user looking at something other than the baseline map?
         if ((G.item_mgr.active_branch !== null)
             //&& (G.item_mgr.active_branch.parent_id != 0)) {
             ) {
            m4_DEBUG('logout: clearing active_branch');
            G.item_mgr.active_branch = null;
            m4_ASSERT(G.item_mgr.branch_id_to_load == 0);
            branch_changed = true;
         }
         G.map.discard_and_update(user_loggingin, user_loggedout,
                                  branch_changed);

         this.rf_planner_default = Conf.rf_planner_default_default;
         this.rf_p1_priority = Conf.rf_p1_priority_default;
         this.rf_p2_transit_pref = Conf.rf_p2_transit_pref_default;
         this.rf_p3_weight_type = Conf.rf_p3_weight_type_default;
         this.rf_p3_rating_pump = Conf.rf_p3_rating_pump_default;
         this.rf_p3_burden_pump = Conf.rf_p3_burden_pump_default;
         this.rf_p3_spalgorithm = Conf.rf_p3_spalgorithm_default;
         this.flashclient_settings = Conf.flashclient_settings_default;
         this.routefinder_settings = Conf.routefinder_settings_default;
         // EXPLAIN: Setting route viz to random seems bizarre.
         //this.route_viz = Route_Viz.random();
         // Use the 'Normal' route visualization. Otherwise, users
         // will be confused. They should find the control and use
         // it to change the visualization to understand what's
         // happening, otherwise they'll have no clue. Silly CcpV1.
         this.route_viz = Conf.route_vizs[0];

         this.private_group_id = 0;

         // FIXME: Reset the public basemap ID?
         //        Branch.ID_PUBLIC_BASEMAP = 0;

         // FIXME: These components should listen on user_event_change.
         // FIXME: Statewide UI: Reimplement historic browsing.
         //        G.tabs.changes.history_browser_update();
         // 2014.04.27: Gosh it took a while to see that this CcpV1 relic is
         // incorrect: this is logout, so why would deep_link matter? Deep
         // links are processed on application start, and logout shouldn't
         // happen during boot, emmywright?
         /*
         if (!(G.deep_link.pending
               && (G.deep_link.fragment == 'discussion'))) {
            G.tabs.discussions.discussions_panel_update(/*thread=* /null,
                                                /*activate_panel=* /false);
         }
         G.panel_mgr.update_bg_and_title();
         */

         // 2012.08.17: Ideally, rather than couple this fcn. to lots of
         // classes, those classes should hook the logging-in-out event.
         // MAYBE: Move the above code to other classes that just listen on
         //        this event... that is, unless order matters.
         // Alert listeners that the loggedin user changed.
         m4_DEBUG('logout: dispatchEvent: user_event_change');
         G.app.dispatchEvent(new Event('user_event_change'));
      }

      //
      protected function logout_alert_handler(event:CloseEvent) :void
      {
         if (event.detail == Alert.OK) {
            this.logout();
            if (!this.logged_in) {
               this.force_login_maybe();
            }
         }
      }

      //
      public function reauthenticate() :void
      {
         this.reauthenticating = true;
         this.login_popup_open();
      }

      // *** Item watcher methods

      //
      public function enable_watchers_email_update() :void
      {
         var prefs:XML = <preferences/>;
         prefs.@enable_watchers_email =  int(this.enable_watchers_email);
         prefs.@enable_watchers_digest =  int(this.enable_watchers_digest);

         m4_ASSERT(this.logged_in);
         if (this.rememberme) {
            G.fcookies_user.set('enable_watchers_email',
                           int(this.enable_watchers_email));
            G.fcookies_user.set('enable_watchers_digest',
                           int(this.enable_watchers_digest));
         }

         // This GWIS_User_Preference_Put will display an error message if it
         // fails since this is an important preference.
         var show_errors:Boolean = true;
         new GWIS_User_Preference_Put(prefs, show_errors).fetch();
      }

      // *** Route finder methods

      // Backup all routefinding preferences
      public function rf_prefs_backup() :void
      {
         var t:Tag;
         this.rf_planner_default_old = this.rf_planner_default;
         this.rf_p1_priority_old = this.rf_p1_priority;
         this.rf_p2_transit_pref_old = this.rf_p2_transit_pref;
         this.rf_p3_weight_type_old = this.rf_p3_weight_type;
         this.rf_p3_rating_pump_old = this.rf_p3_rating_pump;
         this.rf_p3_burden_pump_old = this.rf_p3_burden_pump;
         this.rf_p3_spalgorithm_old = this.rf_p3_spalgorithm;
         this.flashclient_settings_old = this.flashclient_settings;
         this.routefinder_settings_old = this.routefinder_settings;
         for each (t in Tag.all_applied(Byway)) {
            t.pref_user_backup();
         }
      }

      // Set routefinding preferences to defaults
      public function rf_prefs_default() :void
      {
         var t:Tag;
         this.rf_planner_default = Conf.rf_planner_default_default;
         this.rf_p1_priority = Conf.rf_p1_priority_default;
         this.rf_p2_transit_pref = Conf.rf_p2_transit_pref_default;
         this.rf_p3_weight_type = Conf.rf_p3_weight_type_default;
         this.rf_p3_rating_pump = Conf.rf_p3_rating_pump_default;
         this.rf_p3_burden_pump = Conf.rf_p3_burden_pump_default;
         this.rf_p3_spalgorithm = Conf.rf_p3_spalgorithm_default;
         this.flashclient_settings = Conf.flashclient_settings_default;
         this.routefinder_settings = Conf.routefinder_settings_default;
         for each (t in Tag.all_applied(Byway)) {
            t.pref_user_default();
         }
      }

      // Restore all routefinding preferences
      public function rf_prefs_restore() :void
      {
         var t:Tag;
         this.rf_planner_default = this.rf_planner_default_old;
         this.rf_p1_priority = this.rf_p1_priority_old;
         this.rf_p2_transit_pref = this.rf_p2_transit_pref_old;
         this.rf_p3_weight_type = this.rf_p3_weight_type_old;
         this.rf_p3_rating_pump = this.rf_p3_rating_pump_old;
         this.rf_p3_burden_pump = this.rf_p3_burden_pump_old;
         this.rf_p3_spalgorithm = this.rf_p3_spalgorithm_old;
         this.flashclient_settings = this.flashclient_settings_old;
         this.routefinder_settings = this.routefinder_settings_old;
         for each (t in Tag.all_applied(Byway)) {
            t.pref_user_restore();
         }
      }

      // Save routefinding preferences via cookies/GWIS_Base (if needed)
      public function rf_prefs_save() :void
      {
         var prefs:XML;
         var t:Tag;
         var k:String;

         if (this.logged_in) {

            if (this.rememberme) {
               G.fcookies_user.set('rf_planner_default',
                                   int(this.rf_planner_default));
               G.fcookies_user.set('rf_p1_priority',
                                   this.rf_p1_priority);
               G.fcookies_user.set('rf_p2_transit_pref',
                                   this.rf_p2_transit_pref);
               G.fcookies_user.set('rf_p3_weight_type',
                                   this.rf_p3_weight_type);
               G.fcookies_user.set('rf_p3_rating_pump',
                                   int(this.rf_p3_rating_pump));
               G.fcookies_user.set('rf_p3_burden_pump',
                                   int(this.rf_p3_burden_pump));
               G.fcookies_user.set('rf_p3_spalgorithm',
                                   this.rf_p3_spalgorithm);
               //G.fcookies_user.set('flashclient_settings',
               //                    this.flashclient_settings);
               G.fcookies_user.set('routefinder_settings',
                                   this.routefinder_settings);
            }

            prefs = this.rf_prefs_xml(/*changes_only=*/true);

            if (prefs.attributes().length() > 0) {
               new GWIS_User_Preference_Put(prefs).fetch();
            }
         }
      }

      // Returns routefinding preferences as XML.
      //
      // Set changes_only=True to return only the preferences that have changed
      // since the last pref save.
      public function rf_prefs_xml(changes_only:Boolean=false,
                                   restrict_p1:Boolean=false,
                                   restrict_p2:Boolean=false,
                                   restrict_p3:Boolean=false) :XML
      {
         // The persist_all is kind of a band-aid: this fcn. is called to make
         // XML for saving the user's default preferences, and it's also used
         // to make XML for requesting a route. For the former, we want all
         // values in the XML; for the latter, we only care about values
         // that'll be used for the route request.

         var prefs:XML = <preferences/>
         var t:Tag;
         var k:String;

         var restrict_any:Boolean = restrict_p1 || restrict_p2 || restrict_p3;

         if (!restrict_any) {
            if ((!changes_only)
                || (this.rf_planner_default
                    != this.rf_planner_default_old)) {
               prefs.@rf_planner = int(this.rf_planner_default);
            }
         }

         // p1 planner.
         if ((!restrict_any) || (restrict_p1)) {
            if ((!changes_only)
                || (this.rf_p1_priority != this.rf_p1_priority_old)) {
               // If using p3 planner p1 emulation, this is the rating spread.
               prefs.@rf_p1_priority = this.rf_p1_priority;
            }
         }

         // p2 planner.
         if ((!restrict_any) || (restrict_p2)) {
            if ((!changes_only)
                || (this.rf_p2_transit_pref != this.rf_p2_transit_pref_old)) {
               prefs.@rf_p2_transit_pref = this.rf_p2_transit_pref;
            }
         }

         // p3 planner.
         if ((!restrict_any) || (restrict_p3)) {
            if ((!changes_only)
                || (this.rf_p3_weight_type != this.rf_p3_weight_type_old)) {
               prefs.@p3_wgt = this.rf_p3_weight_type;
            }
            if ((!changes_only)
                || (this.rf_p3_rating_pump != this.rf_p3_rating_pump_old)) {
               if ((!restrict_any)
                   || (this.rf_p3_weight_type == 'rat')
                   || (this.rf_p3_weight_type == 'prat')
                   || (this.rf_p3_weight_type == 'rac')
                   || (this.rf_p3_weight_type == 'prac')) {
                  prefs.@p3_rgi = int(this.rf_p3_rating_pump);
               }
            }
            if ((!changes_only)
                || (this.rf_p3_burden_pump != this.rf_p3_burden_pump_old)) {
               if ((!restrict_any)
                   || (this.rf_p3_weight_type == 'fac')
                   || (this.rf_p3_weight_type == 'pfac')
                   || (this.rf_p3_weight_type == 'rac')
                   || (this.rf_p3_weight_type == 'prac')) {
                  prefs.@p3_bdn = int(this.rf_p3_burden_pump);
               }
            }
            if ((!changes_only)
                || (this.rf_p3_spalgorithm != this.rf_p3_spalgorithm_old)) {
               prefs.@p3_alg = this.rf_p3_spalgorithm;
            }
         }

         // For classic finder, of for the p3 planner if classic emulation is
         // enabled.
         if ((!restrict_any)
             || (restrict_p1)
             || ((restrict_p3)
                 && (   (this.rf_p3_weight_type == 'prat')
                     || (this.rf_p3_weight_type == 'pfac')
                     || (this.rf_p3_weight_type == 'prac')))) {

            // If tags are not yet loaded for some reason (such as when Deep
            // Linking), tell server to use defaults.
            if ((!changes_only)
                && ((Tag.all_named === null)
                    || (Tag.all_applied(Byway).length == 0))) {
               // Using old GWIS name, and not 'tags_use_defaults'.
               prefs.@use_defaults = 'true';
            }

            for each (t in Tag.all_applied(Byway)) {
               if (((!changes_only) && (t.pref_enabled) && (t.preference > 0))
                   || ((changes_only) && (t.pref_user_dirty))) {

                  // Preference
                  k = Conf.rf_tag_pref_codes[t.preference];
                  if (prefs.@[k].length() > 0) {
                     prefs.@[k] += ',';
                  }
                  prefs.@[k] += t.stack_id;

                  // Enable state
                  if (changes_only) {
                     k = t.pref_enabled ? 'enabled' : 'disabled';
                     if (prefs.@[k].length() > 0) {
                        prefs.@[k] += ',';
                     }
                     prefs.@[k] += t.stack_id;
                  }
               }
            } // end: for each t in Tag.all_applied(Byway)
         } // if (... && ('prat', 'pfac', or 'prac'))

         // 2014.04.24: Are these the first non-route finder-related
         //             user options to be persisted?

         if ((!changes_only)
             || (this.flashclient_settings != this.flashclient_settings_old)) {
            prefs.@fc_opts = this.flashclient_settings;
         }

         if ((!changes_only)
             || (this.routefinder_settings != this.routefinder_settings_old)) {
            prefs.@rf_opts = this.routefinder_settings;
         }

         return prefs;
      }

      // *** Route visualization methods

      //
      public function get route_viz() :Route_Viz
      {
         return this.route_viz_;
      }

      //
      public function set route_viz(v:Route_Viz) :void
      {
         this.route_viz_ = v;
         if (this.logged_in) {
            this.route_viz_update();
         }
      }

      //
      public function route_viz_update() :void
      {
         var prefs:XML = <preferences/>;
         prefs.@viz_id = this.route_viz.id_;

         m4_ASSERT(this.logged_in);
         if (this.rememberme) {
            G.fcookies_user.set('route_viz', this.route_viz.id_ );
         }

         new GWIS_User_Preference_Put(prefs).fetch();
      }

      // *** Gripe methods

      //
      public function gripe_ban_maybe(public_user:String,
                                      full_user:String,
                                      public_ip:String,
                                      full_ip:String) :void
      {
         var p:Ban_Warning_Popup;

         // 0 = no change, 1 = new ban, -1 = ban removed
         var pu_user_sw:int = 0;
         var fl_user_sw:int = 0;
         var pu_ip_sw:int = 0;
         var fl_ip_sw:int = 0;

         var topic:String = '';
         var bans:String = '';
         var gone:String = '';

         if (this.public_user_ban !== null && public_user === null) {
            pu_user_sw = -1;
         }
         else if (this.public_user_ban != public_user) {
            pu_user_sw = 1;
         }

         if (this.full_user_ban !== null && full_user === null) {
            fl_user_sw = -1;
         }
         else if (this.full_user_ban != full_user) {
            fl_user_sw = 1;
         }

         if (this.public_ip_ban !== null && public_ip === null) {
            pu_ip_sw = -1;
         }
         else if (this.public_ip_ban != public_ip) {
            pu_ip_sw = 1;
         }

         if (this.full_ip_ban !== null && full_ip === null) {
            fl_ip_sw = -1;
         }
         else if (this.full_ip_ban != full_ip) {
            fl_ip_sw = 1;
         }

         if (pu_user_sw != 0
             || fl_user_sw != 0
             || pu_ip_sw != 0
             || fl_ip_sw != 0) {
            // the ban state of this user has changed, so create gripe msg
            if (pu_user_sw == 1 || fl_user_sw == 1) {
               topic +=
                  'There is a hold <i>placed</i> on your <b>account</b><br>';
            }
            if (pu_ip_sw == 1 || fl_ip_sw == 1) {
               topic +=
                  'There is a hold <i>placed</i> on this <b>computer</b><br>';
            }

            if (pu_user_sw == -1 || fl_user_sw == -1) {
               topic +=
                  'A hold on your <b>account</b> has been <i>removed</i><br>';
            }
            if (pu_ip_sw == -1 || fl_ip_sw == -1) {
               topic +=
                  'A hold on this <b>computer</b> has been <i>removed</i><br>';
            }

            if (pu_user_sw == 1) {
               bans += 'Public <b>account</b> hold, expires: '
                       + public_user + '<br>';
               this.public_user_ban = public_user;
            }
            else if (pu_user_sw == -1) {
               gone += 'Public <b>account</b> hold, expired: '
                       + this.public_user_ban + '<br>';
               this.public_user_ban = null;
            }

            if (fl_user_sw == 1) {
               bans += 'Full <b>account</b> hold, expires: '
                       + full_user + '<br>';
               this.full_user_ban = full_user;
            }
            else if (fl_user_sw == -1) {
               gone += 'Full <b>account</b> hold, expired: '
                       + this.full_user_ban + '<br>';
               this.full_user_ban = null;
            }

            if (pu_ip_sw == 1) {
               bans += 'Public <b>computer</b> hold, expires:'
                       + public_ip + '<br>';
               this.public_ip_ban = public_ip;
            }
            else if (pu_ip_sw == -1) {
               gone += 'Public <b>computer</b> hold, expired: '
                       + this.public_ip_ban + '<br>';
               this.public_ip_ban = null;
            }

            if (fl_ip_sw == 1) {
               bans += 'Full <b>computer</b> hold, expires: '
                       + full_ip + '<br>';
               this.full_ip_ban = full_ip;
            }
            else if (fl_ip_sw == -1) {
               gone += 'Full <b>computer</b> hold, expired: '
                       + this.full_ip_ban + '<br>';
               this.full_ip_ban = null;
            }

            // Actually show the pop-up
            p = new Ban_Warning_Popup();
            UI.popup(p, 'ok');
            p.init(topic, bans, gone);
         }
      }

      //
      public function gripe_bouncing_maybe(address:String) :void
      {
         // 2013.10.10: There are 245 user accounts marked 'email_bouncing'.
         //   select count(*) from user_ where email_bouncing is true;
         // Historically, the only way to reset the bouncing flag is to logon
         // to mediawiki and change your email. But what if it's not broken?
         // We need a "stop bugging" me button for users who don't want to
         // see the popup every time they log in.
         // See also: updateExternalDB in mediawiki/extensions/CycloAuth.php,
         // which sets user_.email_bouncing to false.

         if (!this.email_bouncing_griped) {
            this.email_bouncing_griped = true;
            Alert_Dialog.show(
               'Please Update E-mail',
               'The email address you provided to Cyclopath, <b>'
                  + address
                  // FIXME: Since this is HTML, can we use linebreaks here?
                  + '</b>, is not working.\n\n'
                  + 'The <b>Update email</b> button will take you to the '
                  + 'Preferences page, where you can correct or update '
                  + 'your email address and then click <b>Save</b>.',
               /*html?=*/true,
               /*on_ok?=*/
               function () :void
                  { UI.mediawiki('/Special:Preferences'); },
               /*ok_label?=*/'Update email',
               /*on_cancel?=*/null,
               /*cancel_label=*/'Not now',
               /*on_third_option?=*/this.gripe_bouncing_stop_bugging_me,
               /*third_option_label=*/'Stop bugging me');
         }
      }

      //
      protected function gripe_bouncing_stop_bugging_me() :void
      {
         m4_DEBUG('gripe_bouncing_stop_bugging_me');

         var prefs:XML = <preferences/>;
         prefs.@ebouncg = int(false);

         m4_ASSERT(this.logged_in);

         var gwis_cmd:GWIS_User_Preference_Put;
         gwis_cmd = new GWIS_User_Preference_Put(prefs, /*show_errors=*/false);
         // MAYBE: Use G.map.update_supplemental(gwis_cmd);
         //        or maybe we don't need to, since this command doesn't
         //        need to be managed by the update mgr (read: cancellable).
         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_cmd);
         m4_ASSERT_SOFT(!found_duplicate);
      }

      //
      public function belongs_to_group(group_name:String) :Boolean
      {
         var is_group_member:Boolean = false;
         if ((this.logged_in) && (G.grac !== null)) {
            var gm:Group_Membership;
            for each (gm in G.grac.group_memberships) {
               if ((gm.group.name_ == group_name)
                   && (gm.group.is_shared)
                   && (Access_Level.can_edit(gm.access_level_id))) {
                  is_group_member = true;
                  break;
               }
            }
         }

         return is_group_member;
      }

   }
}

