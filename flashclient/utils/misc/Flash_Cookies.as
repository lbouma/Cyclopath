/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.events.NetStatusEvent;
   import flash.net.SharedObject;
   import flash.net.SharedObjectFlushStatus;

   public class Flash_Cookies {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('FlashCookies');

      // *** Instance variables

      protected var so:SharedObject;

      // Each cookie store (Flash SharedObject) has three states --
      // 1) It could be off (unsupported), i.e., if the user right-clicks
      // the Flash Movie in their UA and chooses Settings..., then clicks
      // the Local Storage tab and sets the size to 0 KB, then Flash
      // won't let us store any data client-side; 2) it could be Inactive,
      // if the user is not logged in and the SharedObject is not being
      // persisted; or, 3) it could be Persistent, meaning the SharedObject
      // lives between logins and logouts, i.e., to track anonymous (non
      // logged-in) users or to support remembering certain preferences
      // without forcing users to create accounts and login.
      protected var supported:Boolean;    // Usually true, but false if the
                                          //  user explicitly disables it
      protected var _active:Boolean;      // True if the user is logged in
      protected var _persistent:Boolean;  // True if this SO should be
                                          //  persisted across logins

      // *** Constructor

      public function Flash_Cookies(cookie_name:String,
                                    persistent:Boolean=false) :void
      {
         var fres:String;

         this.activate();
         this.supported = false;
         this._persistent = persistent;
         try {
            this.so = SharedObject.getLocal(cookie_name);
            this.so.addEventListener(NetStatusEvent.NET_STATUS, on_net_status,
                                     false, 0, true);
            this.so.data.test = 'hello world';
            fres = this.so.flush();
         }
         catch (e:Error) {
            m4_DEBUG('flash cookies not available (immediate)');
         }
         if (fres == SharedObjectFlushStatus.FLUSHED) {
            m4_DEBUG('flash cookies available (immediate)');
            this.supported = true;
         }
      }

      // *** Getters and setters

      //
      [Bindable] public function get active() :Boolean
      {
         return ((this._active || this._persistent) && this.supported);
      }

      //
      public function set active(x:Boolean) :void
      {
         this._active = x;
      }

      // *** Event handlers

      //
      public function on_net_status(ev:NetStatusEvent) :void
      {
         switch (ev.info.code) {
         case 'SharedObject.Flush.Success':
            this.supported = true;
            m4_DEBUG('flash cookies available (event)');
            break;
         case 'SharedObject.Flush.Failed':
            this.supported = false;
            m4_DEBUG('flash cookies not available (event)');
            break;
         }
      }

      // *** Other methods

      //
      public function activate() :void
      {
         this.active = true;
      }

      //
      public function clear() :void
      {
         if (!this._persistent) {
            this.so.clear();
            this._active = false;
         }
         else {
            // Cannot (should not) be called on persistent Flash_Cookie
            m4_ASSERT(false);
         }
      }

      //
      public function get(key:String) :String
      {
         if (this.active) {
            return this.so.data[key];
         }
         else {
            return null;
         }
      }

      //
      public function has(key:String) :Boolean
      {
         return (this.get(key) !== null);
      }

      //
      public function set(key:String, value:*, flush:Boolean=false) :void
      {
         if (this.active) {
            this.so.data[key] = String(value);
            if (flush) {
               this.so.flush();
            }
         }
      }

   }
}

