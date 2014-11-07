/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class manages the deep linking functionality.

package grax {

   import flash.events.Event;
   import flash.net.URLVariables;
   import mx.controls.Alert;
   import mx.managers.BrowserManager;
   import mx.managers.IBrowserManager;
   import mx.utils.ArrayUtil;

   import utils.misc.Logging;

   public class Deep_Link {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW//Deep_Lk');

      // Access to the URL displayed by the browser
      protected var browser_url:IBrowserManager;

      // True if the user was offered the chance to log in and declined. In
      // this case, ignore the login-required deep link, if any.
      protected var _login_canceled:Boolean = false;

      // True if the deep-link function has been called.
      protected var deeplink_called:Boolean = false;

      // Parsed fragment text
      protected var _fragment:String = null;
      protected var _params:Object = null;

      // Map deep-link URL fragments to functions. The tag defines when during
      // the application startup process the function is called. Tags:
      //
      //   ANONYMOUS: Action happens immediately upon application startup,
      //   regardless of login state.
      //
      //   LOGGED_IN: Action happens when client asserts that it is logged-in,
      //   without waiting for authentication at the server.
      //
      //   CONFIGURED: Action happens when configuration information arrives
      //   from the server, whether or not user is logged in.
      //
      //   AUTHENTICATED: Action happens when configuration has arrived from
      //   the server and the user has been authenticated by the server.
      //
      //   STARTUP_COMPLETE: Action happens when user startup is complete, i.e.
      //   either the user is authenticated, or the user is established as
      //   anonymous.
      //
      // If the deep link is of class 'logged-in' or 'authenticated', then the
      // client will offer a login window, but if the user cancels the login
      // process, the deep-link function will not be called.

      // enum for above
      public static const ANONYMOUS:int = 0;
      public static const LOGGED_IN:int = 1;
      public static const CONFIGURED:int = 2;
      //
      // Deprecated: AUTHENTICATED. Use LOGGED_IN instead.
      //public static const AUTHENTICATED:int = 3;
      //
      public static const STARTUP_COMPLETE:int = 4;

      // actions => name, callback, states
      protected var actions:Object;

      // *** Constructor

      public function Deep_Link()
      {
      }

      // *** Object initialization

      //
      public function init() :void
      {
         this.browser_url = BrowserManager.getInstance();
         this.browser_url.init('', 'Cyclopath Geowiki');

         // FIXME: Is this too tightly coupled? In this manner, Deep_Link has
         //        to be created or init()ed after the managers. If the
         //        managers had to register, this class would get created
         //        first....
         this.actions = {

            //
            // WARNING: The names of the actions and the URL keys are
            // strictly-named and cannot be changed without breaking
            // people's existing deeplinks.
            //

            // This is called from the javascript widget. See route_widget.js.
            // Also called from homepage, e.g., http://cyclopath.org.
            'route':
               [G.tabs.route.deep_link_single,
                // Too soon: Deep_Link.ANONYMOUS,
                //    MAYBE: Deep_Link.ANONYMOUS should wait until startup
                //            signalled
                // This is also too soon: Deep_Link.STARTUP_COMPLETE,
                Deep_Link.CONFIGURED,
                ['from_addr', 'to_addr', 'auto_find',],],

            //
            // This is for CcpV1-style links. User's could get this URL from a
            // flashclient get-hash-link popup.
            'route_shared':
               [G.tabs.route.deep_link_shared,
                Deep_Link.CONFIGURED,
                ['id',],],

            //
            // The URL is made by post.py and added to emails to users.
            'discussion':
               [G.tabs.discussions.deep_link_discussion,
                // See above: too soon: Deep_Link.STARTUP_COMPLETE,
                Deep_Link.CONFIGURED,
                ['thread_id', 'post_id',],],

            //
            // This is for CcpV2-style links.
            // FIXME: Doesn't work:
            //     http://cycloplan.cyclopath.org/#get?type=thread&link=4099711
            //     or is this just for UUID links? So you can't link by
            //     stack_id? Seems silly that you can't just use stack IDs...
            'get':
               [G.item_mgr.deep_link_get,
                Deep_Link.CONFIGURED,
                ['type', 'link',],],

            // 
            // See: Item_User_Access.get_stealth_secret_web_link, which shows
            //      a different link URL if the item cannot be seen by the
            //      public.
            //
            // 2013.09.05: Some test URLs for 'private':
            //
  // http://ccpv3/#get?type=route&link=d751db6b-2707-ed6a-f2cd-4c9f9f714d54
  // http://ccpv3/#get?type=route&link=877644ee-dd0d-f158-4e34-7056cb229da0
  // http://ccpv3/#private?type=route&link=d751db6b-2707-ed6a-f2cd-4c9f9f714d54
  // Should we impl. stack ID link? Oh, wait, it is implemented! =)
  //  See: deep_link_get.
  //  http://ccpv3/#private?type=route&link=1588505
  // http://ccpv3/#private?type=route&link=fe1bc44c-0a02-e01e-8b66-459fd5760f52
  // ./ccp.py -r -t route -f use_stealth_secret fe1bc44c-0a02-e01e-8b66-459fd5760f52
            // 
            // 2013.10.10: Some more test URLs for 'private':
   // http://ccpv3/#get?type=route&link=5fc61882-e6b6-4474-b19c-9c46bf9519cc
   // http://ccpv3/#private?type=route&link=5fc61882-e6b6-4474-b19c-9c46bf9519cc
            //
            'private':
               [G.item_mgr.deep_link_get,
                // EXPLAIN: What's the difference btw. AUTHENTICATED
                //          and LOGGED_IN? Here we need LOGGED_ID.
                //          [lb] seems to remember the LOGGED_IN fires after
                //          the map is loaded, but AUTHENTICATED comes before
                //          the map is done loading (so Update is still running
                //          and the OOB request might fail).
                Deep_Link.LOGGED_IN,
                ['type', 'link',],],

            //
            // Landmarks experiment
            'landmarks':
               [G.item_mgr.landmark_exp_get,
                Deep_Link.LOGGED_IN,
                [,],]

            //// BUG nnnn: Deep-link to user prefs, so users that unsubscribe
            ////           from email can load Cyclopath and jump to
            ////           (nonexistant, as of now) user prefs panel.
            //'user_prefs':
            //   [G.user.deep_link_user_prefs,
            //    //Deep_Link.AUTHENTICATED,
            //    Deep_Link.LOGGED_IN,
            //    [,],]

         };

         // For Deep_Link.LOGGED_IN to work, we can't run the deep link
         // as soon as the user logs on. We need to wait for the update
         // to start, otherwise any GWIS request we try to send just
         // gets discarded.
         // WEIRD: If we reach on updatedRevision instead of updateItems,
         // the route is drawn and we switch to its details panel, but the
         // route stop letters are not drawn (even though the route stop
         // circles are the correct style). But reacting on updatedItems
         // seems to work...
         //G.item_mgr.addEventListener(
         //   'updatedRevision', this.on_updated_revision, false, 0, true);
         G.item_mgr.addEventListener(
            'updatedItems', this.on_updated_items, false, 0, true);
      }

      // *** Static getters/setters

      // E.g., http://magic.cyclopath.org#route_shared?id={hex}.
      // Where {hex} may or may not contain dashes. E.g., either
      //    01234567-89ab-cdef-0123-456789abcdef
      // or
      //    0123456789abcdef0123456789abcdef

      // fragment name that's before the '?'
      public function get fragment() :String
      {
         if (this._fragment === null) {
            this.fragment_parse();
         }
         return this._fragment;
      }

      //
      public function set fragment(frag:String) :void
      {
         m4_ASSERT(false);
      }

      // Key-value pairs separated by '&' after the '?'.
      // There will not be keys that aren't contained in the 3rd element
      // of the actions array.  Key values not included in the url
      // will be set to null.
      protected function get params() :Object
      {
         if (this._params === null) {
            this.fragment_parse();
         }
         return this._params;
      }

      //
      protected function set params(params:Object) :void
      {
         m4_ASSERT(false);
      }

      // Return true if a deep-link action is waiting to be called.
      public function get pending() :Boolean
      {
         return ((!this.deeplink_called) && (this.fragment in this.actions));
      }

      //
      public function set pending(pending:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // Return true if a logged-in or authenticated deep-link action is
      // pending, and the user has not yet declined to log in.
      public function get wants_login() :Boolean
      {
         m4_DEBUG2('wants_login: fragment:', this.fragment,
                   '/ actions:', this.actions);
         var login_wanted:Boolean = false;
         if ((this.pending) && (!this._login_canceled)) {
            var the_action:int = this.actions[this.fragment][1];
            //login_wanted = ((the_action == Deep_Link.LOGGED_IN)
            //                || (the_action == Deep_Link.AUTHENTICATED));
            login_wanted = (the_action == Deep_Link.LOGGED_IN);
         }
         return login_wanted;
      }

      //
      public function set wants_login(wants_it:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // *** Other methods

      // parse the fragment name and parameters from browser_url.fragment
      protected function fragment_parse() :void
      {
         var param_index:int;
         var param_str:String;

         m4_DEBUG2('fragment_parse: browser_url.fragment:',
                   this.browser_url.fragment);

         this._params = new Object();
         param_index = this.browser_url.fragment.indexOf("?");
         if (param_index > 0) {
            // split the fragment root and then parse the parameters
            this._fragment =
               this.browser_url.fragment.substring(0, param_index);
         }
         else {
            // no params
            this._fragment = this.browser_url.fragment;
         }

         if (this._fragment in this.actions) {

            // parse the params
            param_str = this.browser_url.fragment.substring(param_index + 1);

            m4_DEBUG('fragment_parse: param_str:', param_str);

            // url compressors like bit.ly or tinyurl will add a '/' to the
            // end of the deep-link, which we don't like
            if (param_str.charAt(param_str.length - 1) == '/') {
               param_str = param_str.substring(0, param_str.length - 1);
            }

            var key:String;
            try {
               // Decode url encodings such as '%20' and split on '&'.
               var decoder:URLVariables = new URLVariables(param_str);
               // only take parameters defined in the action
               for each (key in this.actions[this._fragment][2]) {
                  m4_DEBUG('fragment_parse: key:', key);
                  if (key in decoder) {
                     this._params[key] = decoder[key];
                  }
                  else {
                     this._params[key] = null;
                  }
                  m4_DEBUG4('fragment_parse: key:', key,
                            '/ this._params[key]:',
                            (this._params[key] !== null)
                             ? this._params[key] : 'null');
               }
            }
            catch (e:Error) {
               // set all params to null for the action
               // we can't use a for-each loop because there's a bug
               // that causes it to not end the loop -> crash the browser.
               var frag_len:int = this.actions[this._fragment][2].length;
               for (var i:int = 0; i < frag_len; i++) {
                  key = this.actions[this._fragment][2][i];
                  this._params[key] = null;
                  m4_DEBUG2('fragment_parse: key:', key,
                            '/ this._params[key]: null...');
               }
            }
         }
         else {
            m4_WARNING('fragment_parse: unknown fragment', this._fragment);
            this.deeplink_called = true;
         }
      }

      // Do the deep link action. when is the tag which indicates which stage
      // of function to call (see above).
      //
      // Note: we depend on the caller to call with LOGGED_IN and
      // AUTHENTICATED at the appropriate times, since there's no way to tell
      // if we're authenticated or if the client just thinks it's logged in.
      public function load_deep_link(when:int) :void
      {
         if ((!this.deeplink_called) && (this.fragment in this.actions)) {
            switch (when) {
               case Deep_Link.ANONYMOUS:
                  break;
               case Deep_Link.LOGGED_IN:
               //case Deep_Link.AUTHENTICATED:
                  if (this._login_canceled) {
                     // Whatever; the user canceled the logon.
                     // MAYBE: Notify user that deep link requires logging on.
                     this.deeplink_called = true;
                     return;
                  }
                  else if (!(G.user.logged_in) || G.user.reauthenticating) {
                     return;
                  };
                  break;
               case Deep_Link.CONFIGURED:
                  break;
               case Deep_Link.STARTUP_COMPLETE:
                  break;
               default:
                  m4_ASSERT(false);
            }
            if (this.actions[this.fragment][1] == when) {
               // when is:
               //   public static const ANONYMOUS:int = 0;
               //   public static const LOGGED_IN:int = 1;
               //   public static const CONFIGURED:int = 2;
               //   //public static const AUTHENTICATED:int = 3;
               //   public static const STARTUP_COMPLETE:int = 4;
               m4_DEBUG('load_deep_link: when:', when, '/', this.fragment);
               this.actions[this.fragment][0](this._params);
               this.deeplink_called = true;
            }
         }
      }

      //
      public function login_canceled() :void
      {
         this._login_canceled = true;
      }

      //
      protected function on_updated_revision(event:Event=null) :void
      {
         // NOTE: This fcn. is not used; see on_updated_items.

         m4_DEBUG('on_updated_revision: updatedRevision');

         if (G.user.logged_in) {
            this.load_deep_link(Deep_Link.LOGGED_IN);
         }
      }

      //
      protected function on_updated_items(event:Event=null) :void
      {
         m4_DEBUG('on_updated_items: updatedItems');

         if (G.user.logged_in) {
            this.load_deep_link(Deep_Link.LOGGED_IN);
         }
      }

   }
}

