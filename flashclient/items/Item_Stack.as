/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Tricked ya! In pyserver, item_stack is part of the item class hierarchy.
// Here, it's on its own. We lazy-load item_stack only when an item is
// selected, so we might as well segregate its attributes (the idea being that
// we'll save memory if we don't declare these attributes for the 1000s of
// geofeatures we load for the viewport).

package items {

   import flash.utils.getQualifiedClassName;

   import grax.Access_Style;
   import grax.Library_Squelch;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Strutil;

   public class Item_Stack {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Stack');

      // *** Instance variables

      protected var item:Item_Versioned;

      protected var access_style_id_:* = undefined; // int
      protected var access_infer_id_:* = undefined; // int
      public var created_date:* = undefined; // String
      public var created_user:* = undefined; // String
      public var stealth_secret:* = undefined; // String; UUID
      public var cloned_from_id:* = undefined; // int

      // MAYBE: Audit the item classes and see what else can be moved here.

      // 2013.08.29: [lb] is sticking the item_findability values here.
      //             It kind of breaks Item_Stack as directly relating
      //             to the item_stack table, but item_stack is lazy-loaded
      //             and so are the item_findability values (though the latter
      //             are only loaded for routes).
      public var fbilty_pub_libr_squel:* = undefined; // int (Library_Squelch)
      public var fbilty_usr_histy_show:* = undefined; // Boolean
      public var fbilty_usr_libr_squel:* = undefined; // int (Library_Squelch)

      // 2014.05.20: So, we're still creeping feats?
      //             Behold: The new item_revisionless table!
      public var edited_date:String;
      public var edited_user:String;
      public var edited_addr:String;
      public var edited_host:String;
      public var edited_note:String;
      public var edited_what:String;

      // 2014.06.26: The latest version. See commands.Item_Reversion.
      public var reversion_version:int = 0;
      public var master_item:* = null;

      // *** Constructor

      public function Item_Stack(item:Item_Versioned, xml:XML=null)
      {
         this.item = item;
         // Because of informationless, we don't want to set any defaults.
         this.gml_consume(xml);
         // The caller sometimes overwrites its item_stack, so maintain
         // the reversion_version.
         this.reversion_version = item.reversion_version;
      }

      // *** Getters and setters

      // Returns true if all attributes are unset.
      public function get informationless() :Boolean
      {
         var uninteresting:Boolean;
         uninteresting = (true
                          && (!this.access_style_id_)
                          && (!this.access_infer_id_)
                          && (!this.created_date)
                          && (!this.created_user)
                          && (!this.stealth_secret)
                          && (!this.cloned_from_id)
                          && (!this.fbilty_pub_libr_squel)
                          && (!this.fbilty_usr_histy_show)
                          && (!this.fbilty_usr_libr_squel)
                          && (!this.edited_date)
                          && (!this.edited_user)
                          && (!this.edited_addr)
                          && (!this.edited_host)
                          && (!this.edited_note)
                          && (!this.edited_what)
                          //&& (!this.reversion_version)
                          //&& (!this.master_item)
                          );
         return uninteresting;
      }

      // *** Instance methods

      // See also: Record_Base.clone_item().
      public function clone_item(the_clone:Item_Stack=null) :Item_Stack
      {
         if (this === the_clone) {
            // We can't clone ourselves, because the derived clone_once fcns.
            // clobber cl and then copy from this, which doesn't work.
            m4_WARNING('clone: cannot clone against self:', this);
            m4_WARNING(Introspect.stack_trace());
            the_clone = this;
         }
         else {
            if (the_clone === null) {
               var cls:Class = (Introspect.get_constructor(this) as Class);
               m4_ASSERT(cls === Item_Stack); // the one and only...
               the_clone = new cls(this.item); // new Item_Stack(this.item);
            }
            // Not calling: this.clone_id(the_clone);
            this.clone_once(the_clone);
         }

         return the_clone;
      }

      // The clone function copies everything except unique identifiers.
      public function clone_once(to_other:Object) :void
      {
         var other:Item_Stack = (to_other as Item_Stack);
         other.reversion_version = this.reversion_version;
      }

      //
      public function clone_id(to_other:Item_Stack) :void
      {
         var other:Item_Stack = (to_other as Item_Stack);

         // MAYBE: Skip these or not? init_update uses clone(), so, include?
         other.access_style_id_ = this.access_style_id_;
         m4_VERBOSE('clone_id: oth.access_style:', other.access_style_id);

         other.access_infer_id_ = this.access_infer_id_;
         m4_VERBOSE2('clone_id: oth.access_infer:',
                     Strutil.as_hex(other.access_infer_id));
         // Tell other to recalculate its calculated access_infer_id.
         other.item.latest_infer_id = null;

         // STYLE_GUIDE_CAVEAT: A hidden fcn. call in a debug statement.
         // This log state will force a recalculation... except in production.
         // Where m4_* statements are omitted. Ha!
         //  m4_VERBOSE2('clone_id: other.item.latest_infer_id:',
         //     other.item.latest_infer_id, '/', other.item);
         // The correct way to do this is:
         var latest_infer_id:int = other.item.latest_infer_id;
         m4_VERBOSE2('clone_id: other.item.latest_infer_id:',
            latest_infer_id, '/', other.item);

         other.created_date = this.created_date;

         other.created_user = this.created_user;

         other.stealth_secret = this.stealth_secret;

         other.cloned_from_id = this.cloned_from_id;

         other.fbilty_pub_libr_squel = this.fbilty_pub_libr_squel;

         other.fbilty_usr_histy_show = this.fbilty_usr_histy_show;

         other.fbilty_usr_libr_squel = this.fbilty_usr_libr_squel;

         other.edited_date = this.edited_date;

         other.edited_user = this.edited_user;

         other.edited_addr = this.edited_addr;

         other.edited_host = this.edited_host;

         other.edited_note = this.edited_note;

         other.edited_what = this.edited_what;

         other.reversion_version = this.reversion_version;

         // Skipping: master_item
      }

      //
      protected function clone_update( // no-op
         to_other:Item_Stack, newbie:Boolean) :void
      {
         var other:Item_Stack = (to_other as Item_Stack);
         super.clone_update(other, newbie);
         // The clone_update fcn. is only called when we re-fetch an existing
         // item, and it should only lazy-load items (parts of items that
         // weren't previously loaded), so all this should be the same.
         m4_ASSERT_SOFT(other.access_style_id_ == this.access_style_id_);
         m4_ASSERT_SOFT(other.access_infer_id_ == this.access_infer_id_);
         m4_ASSERT_SOFT(other.created_date == this.created_date);
         m4_ASSERT_SOFT(other.created_user == this.created_user);
         m4_ASSERT_SOFT(other.stealth_secret == this.stealth_secret);
         m4_ASSERT_SOFT(other.cloned_from_id == this.cloned_from_id);
         m4_ASSERT_SOFT(other.fbilty_pub_libr_squel
                        == this.fbilty_pub_libr_squel);
         m4_ASSERT_SOFT(other.fbilty_usr_histy_show
                        == this.fbilty_usr_histy_show);
         m4_ASSERT_SOFT(other.fbilty_usr_libr_squel
                        == this.fbilty_usr_libr_squel);
         m4_ASSERT_SOFT(other.edited_date == this.edited_date);
         m4_ASSERT_SOFT(other.edited_user == this.edited_user);
         m4_ASSERT_SOFT(other.edited_addr == this.edited_addr);
         m4_ASSERT_SOFT(other.edited_host == this.edited_host);
         m4_ASSERT_SOFT(other.edited_note == this.edited_note);
         m4_ASSERT_SOFT(other.edited_what == this.edited_what);
         // Skipping: reversion_version
         // Skipping: master_item
      }

      // Use contents of XML element to init myself.
      public function gml_consume(gml:XML) :void
      {
         if (gml !== null) {
            // NOTE: If a key is not in the XML, the empty string is set, or 0.
            if ('@acst' in gml) {
               this.access_style_id = int(gml.@acst);
            }
            if ('@acif' in gml) {
               this.access_infer_id = int(gml.@acif);
               m4_DEBUG2('gml_consume: access_infer_id:',
                         Strutil.as_hex(this.access_infer_id));
            }
            if ('@crat' in gml) {
               this.created_date = gml.@crat;
            }
            if ('@crby' in gml) {
               this.created_user = gml.@crby;
            }
            if ('@stlh' in gml) {
               this.stealth_secret = gml.@stlh;
            }
            if ('@clid' in gml) {
               this.cloned_from_id = int(gml.@clid);
            }
            // The next two are requested via GWIS_Item_Findability_Get.
            // Skipping: fbilty_pub_libr_squel
            // Skipping: fbilty_usr_histy_show
            // Skipping: fbilty_usr_libr_squel
            //m4_DEBUG('gml_consume: access_style/1:', this.access_style_id);
            this.edited_date = gml.@ed_dat;
            this.edited_user = gml.@ed_usr;
            this.edited_addr = gml.@ed_adr;
            this.edited_host = gml.@ed_hst;
            this.edited_note = gml.@ed_not;
            this.edited_what = gml.@ed_wht;
            // Skipping: reversion_version
            // Skipping: master_item
         }
         else {
            // EXPLAIN... who calls gml_consume with a null gml object??
            this.access_style_id_ = null; // Access_Style.nothingset;
            this.access_infer_id_ = null; // Access_Infer.not_determined;
            this.created_date = null;
            this.created_user = null;
            this.stealth_secret = null;
            this.cloned_from_id = null; // 0;
            // Skipping: fbilty_pub_libr_squel
            // Skipping: fbilty_usr_histy_show
            // Skipping: fbilty_usr_libr_squel
            //m4_DEBUG('gml_consume: access_style/2:', this.access_style_id);
            this.edited_date = null;
            this.edited_user = null;
            this.edited_addr = null;
            this.edited_host = null;
            this.edited_note = null;
            this.edited_what = null;
            // Skipping: reversion_version
            // Skipping: master_item
         }
      }

      // Return an XML element representing myself.
      public function gml_append(gml:XML) :void
      {
         // Skipping: access_style_id
         // Skipping: access_infer_id
         // Skipping: created_date
         // Skipping: created_user
         // Skipping: stealth_secret
         if (this.cloned_from_id > 0) {
            gml.@cloned_from_id = this.cloned_from_id;
         }
         // For the next two (which the user can set, just not via item_stack),
         // see GWIS_Item_Findability_Put.
         //   Skipping: fbilty_pub_libr_squel
         //   Skipping: fbilty_usr_histy_show
         //   Skipping: fbilty_usr_libr_squel
         //   Skipping: edited_date
         //   Skipping: edited_user
         //   Skipping: edited_addr
         //   Skipping: edited_host
         //   Skipping: edited_note
         //   Skipping: edited_what
         //   Skipping: reversion_version
         //   Skipping: master_item
      }

      // ***

      //
      public function get access_infer_id() :int
      {
         return this.access_infer_id_;
      }

      //
      public function set access_infer_id(access_infer_id:int) :void
      {
         //m4_VERBOSE('set access_infer_id:', access_infer_id);

         // This is the value that the server sends.
         this.access_infer_id_ = access_infer_id;

         // And this is the value that we the client calculate.
         this.item.latest_infer_id = null;
         // (Since m4_* is ommitted in production and uses a setter...):
         var latest_infer_id:int = this.item.latest_infer_id;
         m4_VERBOSE2('set access_infer_id: latest_infer_id: 0x:',
                     Strutil.as_hex(latest_infer_id), '/', this.item);
      }

      //
      public function get access_style_id() :int
      {
         return this.access_style_id_;
      }

      //
      public function set access_style_id(access_style_id:int) :void
      {
         // Ignore the real access_style if the user cannot change it.
         // This makes it easier for our view widgets to display more
         // meaningful information, i.e., access_style_id_amity will
         // be set to all_denied and not undefined if the collection
         // of selected items canned be edited, regardless of the items'
         // particular access_styles. (Really, access_styles that lock
         // once the item is saved don't matter to us -- we just care
         // that the item's permissions cannot be changed by the user.)
         /*
         if ((access_style_id)
             && (!this.is_access_changeable(access_style_id))) {
            m4_DEBUG('set access_style_id all_denied from:', access_style_id);
            access_style_id = Access_Style.all_denied;
         }
         */
         this.access_style_id_ = access_style_id;
         if (this.access_style_id_) {
            m4_VERBOSE('set access_style_id:', this.access_style_id_);
         }
      }

      //
      protected function is_access_changeable(scope:int) :Boolean
      {
         m4_ASSERT(false); // Not used.
         return (
            false
            || (scope == Access_Style.all_access)
            || (scope == Access_Style.permissive)
            || (scope == Access_Style.restricted)
            // For fresh items (with client IDs < 0) or while loading a branch
            // (and checking new item permissions by faking a call to bless_new
            // from on_process_new_item_policy) where item ID is 0 (invalid),
            // we can always "change" permissions (really we're just creating a
            // new item and choosing what permissions become permanent).
            || (((this.item.fresh)
                 || (this.item.invalid))
                && ((scope == Access_Style.pub_choice)
                    || (scope == Access_Style.usr_choice)
                    || (scope == Access_Style.usr_editor)
                    || (scope == Access_Style.pub_editor)))
            );
      }

      // *** Developer methods

      //
      public function toString() :String
      {
         return (getQualifiedClassName(this)
                 + '/ Sty ' + this.access_style_id_
                 + '/ Ifr ' + Strutil.as_hex(this.access_infer_id_)
                 + '/ Dte ' + this.created_date
                 + '/ Cre ' + this.created_user
                 + '/ StS ' + this.stealth_secret
                 + '/ Clo ' + this.cloned_from_id
                 + '/ PSql ' + this.fbilty_pub_libr_squel
                 + '/ UHsy ' + this.fbilty_usr_histy_show
                 + '/ USql ' + this.fbilty_usr_libr_squel
                 + '/ eDate ' + this.edited_date
                 + '/ eUser ' + this.edited_user
                 + '/ eAddr' + this.edited_addr
                 + '/ eHost' + this.edited_host
                 + '/ eNote' + this.edited_note
                 + '/ eWhat' + this.edited_what
                 + '/ revV' + this.reversion_version
                 //+ '/ revV' + this.master_item
                 );
      }

   }
}

