/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;

   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Handshake extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/HELLO');

      // *** Instance variables

      protected var username:String;
      protected var password:String;
      protected var rememberme:Boolean;

      // *** Constructor

      public function GWIS_Handshake(username:String,
                                     password:String,
                                     rememberme:Boolean) :void
      {
         var url:String = this.url_base('user_hello');

         this.username = username;
         this.password = password;
         this.rememberme = rememberme;

         super(url, this.doc_empty());
      }

      // *** Instance methods

      //
      override protected function creds_set() :void
      {
         this.data.metadata.user
            = <user name={this.username} pass={this.password} />;
      }

      // Report problems to the user.
      override protected function error_present(text:String) :void
      {
         // without this, the app is locked up because no controls are active
         // FIXME: this causes the login window to flicker. Solution seems to
         // be to set up an event handler function and pass it as argument
         // closeHandler to show().
         m4_DEBUG('error_present: setting login_window.enabled');
         G.user.login_window.enabled = true;
         Alert.show(text, "Login failed");
      }

      //
      override public function on_cancel_cleanup() :void
      {
         super.on_cancel_cleanup();
         m4_DEBUG('on_cancel_cleanup: setting login_window.enabled');
         G.user.login_window.enabled = true;
         // We really shouldn't be here: How does a login get canceled?
         m4_ASSERT_SOFT(false);
      }

      // Cleanup after IO errors on_io_error, on_security_error, and on_timeout
      override protected function on_error_cleanup() :void
      {
         super.on_error_cleanup();
         m4_DEBUG('on_error_cleanup: setting login_window.enabled');
         G.user.login_window.enabled = true;
      }

      // Process the incoming result set. The presence of a result set tells
      // us that login was successful.
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('resultset_process: username:', this.username);
         G.user.login_finish(this.username, rset.token.text(),
                             rset.preferences[0], this.rememberme);
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user;
      }

   }
}

