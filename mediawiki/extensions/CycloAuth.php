<?php

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/**
* CycloAuth (Cyclopath Authentication Module)
*
* Overrides built-in MediaWiki authentication and limits usernames and
* passwords to those found in the cycling project user_ table.
* Also allows users to change their email and password, or create new
* accounts from within MediaWiki.
*
* Based on AuthPlugin.php; see
*   http://svn.wikimedia.org/doc/classAuthPlugin.html
*
* Add the following to LocalSettings.php:

  # Cyclopath authentication
  require_once("extensions/CycloAuth.php");
  $authserver = "hostname.cs.umn.edu";
  $authdb = "database";
  $authuser = "username";
  $authpass = "password"
  $wgAuth = new CycloAuth($authserver, $authdb, $authuser, $authpass);

*/

/* BUG nnnn: Upgrade MediaWiki and run it from our server (i.e., don't
             rely on Systems).

   MediaWiki   1.15.1
   PHP         5.2.17 (apache2handler)
   MySQL       5.1.31

   See also list of plugins:

     http://cyclopath.org/wiki/Special:Version

 */

/* BUG nnnn: Make tests for CycloAuth.php.

   Currently, this module is not tested automatically.

   Test changing passwords, test creating new account on test db... etc... ug.
 */

include_once("AuthPlugin.php");

class CycloAuth extends AuthPlugin {

   var $pg_conn;

   // Initialize with parameters of Ccp database server.
   //
   function CycloAuth($hostname, $dbname, $dbuser, $dbpass) {
      $this->pg_conn = pg_pconnect(
            "host=$hostname dbname=$dbname user=$dbuser password=$dbpass")
         or die("Could not connect: " . $this->report_error());
   }

   // Verify user exists in external database (and is allowed to login).
   //
   function userExists($username, $login_disallowed_okay=false) {

      //wfDebug("userExists: raw username: " . $username . "\n");

      $username = strtolower($username);
      $username = str_replace(' ', '_', $username);

      //wfDebug("userExists: ready username: " . $username . "\n");

      $sql = "SELECT COUNT(*) FROM user_ WHERE username = $1";
      if (!$login_disallowed_okay) {
         $sql += " AND login_permitted = 't'";
      }

      //wfDebug("userExists: sql: " . $sql . "\n");

      // April, 2014: Systems recompiled PHP because of the heartbleed zero-day
      // but they forgot to include multibyte support. As a result, half the
      // postgres API reported, e.g., "PHP Fatal error:  Call to undefined
      // function pg_query_params() in .../CycloAuth.php ....". You can find
      // the PHP log in /web/logs/monk_error_log/. (And, unfortunately, we
      // didn't find out until a week later when a user notified us of the
      // problem.)
      //
      // [lb] found this code for helping handle psql errors more robustly,
      //      but we shouldn't need to do this...
      /*
      if (pg_send_query_params($this->pg_conn, $sql, array($username))) {
         wfDebug("pg_send_query_params: yes" . "\n");
         $result = pg_get_result($this->pg_conn);
         if ($result) {
            $state = pg_result_error_field($result, PGSQL_DIAG_SQLSTATE);
            if ($state == 0) {
               // success
               wfDebug("pg_send_query_params: okay: " . $result . "\n");
            }
            else {
               // an error happened
               if ($state == "23505") { // unique_violation
                  // process or ignore expected error
                  wfDebug("pg_send_query_params: weird: " . pg_last_error() . "\n");
               }
               else {
                  // process other errors
                  wfDebug("pg_send_query_params: other: " . pg_last_error() . "\n");
               }
            }
         }
         else {
            wfDebug("pg_send_query_params: no result: " . pg_last_error() . "\n");
         }
      }
      else {
         wfDebug("pg_send_query_params: send failed: " . pg_last_error() . "\n");
      }
      wfDebug("userExists: result: " . $result . "\n");
      if (!$result) {
         die($this->report_error());
      }
      */

      $result = pg_query_params($sql, array($username))
         or die($this->report_error());

      return (pg_num_rows($result) == 1);
   }

   // Authenticate external user (true if valid username and password).
   //
   function authenticate($username, $password) {

      if (!$username or !$password) {
         return false;
      }

      $username = strtolower($username);
      $username = str_replace(' ', '_', $username);

      $sql = "SELECT login_ok($1, $2)";
      $result = pg_query_params($sql, array($username, $password))
         or die($this->report_error());

      $row = pg_fetch_array($result);
      return ($row[0] == 't');
   }

   // Update MediaWiki user with external information.
   //
   function updateUser(&$user) {
      $this->initUser($user);
   }

   // Create MediaWiki accounts as necessary.
   //
   function autoCreate() {
      return true;
   }

   // CycloAuth can change passwords in external database.
   //
   function allowPasswordChange() {
      return true;
   }

   // Update external database with changes to password in MediaWiki user
   // preferences.
   //
   function setPassword($user, $password) {

      $username = strtolower($user->getName());

      $sql = "SELECT password_set($1, $2)";
      $result = pg_query_params($sql, array($username, $password))
         or die($this->report_error());

      return true;
   }

   // Update external database with changes to MediaWiki user preferences (just
   // email for now).
   //
   function updateExternalDB($user) {

      $username = strtolower($user->getName());

      $sql =
         "UPDATE user_ SET email = $1, email_bouncing = false WHERE username = $2";
      $result = pg_query_params($sql, array($user->getEmail(), $username))
         or die($this->report_error());

      return true;
   }

   // CycloAuth can create accounts in external database.
   //
   function canCreateAccounts() {
      return true;
   }

   // Create a new user in the external database with information from
   // MediaWiki "Create account" form.
   //
   // FIXME: In MediaWiki 1.15.1, only param is $user; last three are at
   //        least in 1.19.1.
   function addUser($user, $password, $email = '', $realname = '') {

      //wfDebug("===========================================\n");
      //wfDebug("addUser: raw username: " . $user->getName() . "\n");
      //wfDebug("addUser: user->mName: " . $user->mName . "\n");
      //wfDebug("addUser: user->mRealName: " . $user->mRealName . "\n");

      // WHAT!? WHY?! From https://www.mediawiki.org/wiki/AuthPlugin:
      // "The username is translated by MediaWiki before it is passed to the
      // function: First letter becomes upper case, underscore '_' become
      // spaces ' '."
      // It seems this is because usernames must also be valid Wiki titles.
      // Silly!
      $username = strtolower($user->getName());
      $username = str_replace(' ', '_', $username);

      //wfDebug("addUser: fixed username: " . $username . "\n");

      if ($this->userExists($username, true)) {
         wfDebug("addUser: username exists: " . $username . "\n");
         return false;
      }
      else {
         // Bug 2719: 2012.08.17: Don't allow usernames that start with an
         //           underscore.
         // FIXME: Enforce a valid charset?
         // FIXME: Tell the user why their username could not be saved.
         // BUG nnnn: In-band registration: This code doesn't belong here.
         //           Probably in user.py, where it'll be shared by this
         //           MediaWiki plugin and pyserver/flashclient. Or maybe
         //           we won't allow MediaWiki registrations anymore....
         //

         // Check the min/max username bounds.
         $name_length = strlen($username);
         // MAGIC_NUMBER: 4 is the minimum name length.
         // MAYBE: Make it three? I do like three-letter names...
         if ($name_length < 4) {
            // [lb] dislikes short-circuit returns, but at least in this file,
            // everyone seems to be doing it.
            wfDebug("addUser: username too short: " . $username . "\n");
            return false;
         }
         // MAYBE: Should we also enforce a maximum name length? For now... why
         //        not just prevent obnoxiously long names. Where obnoxious >
         //        32.
         if ($name_length > 32) {
            // FIXME: How do we alert users that this is a problem??
            wfDebug("addUser: username too long: " . $username . "\n");
            return false;
         }

         //wfDebug("addUser: length okay\n");

         // Check that the user isn't trying to create a system-ish username.
         // SELECT NOT ('_test' LIKE E'\\_%');
         // SELECT NOT ('test_test_' LIKE E'\\\\_%');
         $sql = "SELECT NOT ($1 LIKE E'\\\\_%')";
         $result = pg_query_params($sql, array($username))
            or die($this->report_error());
         $row = pg_fetch_array($result);
         if ($row[0] != 't') {
            // Proposed username starts with an underscore.
            return false;
         }

         // NOTE: The A-Z is meaningless; we lowercased above.
         //$sql = "SELECT regexp_matches($1, '^[-_a-zA-Z0-9]+$')";
// SELECT regexp_matches('test', '^[-_.~!@#$%^&*(){}|:;<>,.?a-zA-Z0-9]+$');
// SELECT regexp_matches('_test', '^[-_.~!@#$%^&*(){}|:;<>,.?a-zA-Z0-9]+$');
// SELECT regexp_matches('test_me_', '^[-_.~!@#$%^&*(){}|:;<>,.?a-zA-Z0-9]+$');
         // FIXME: This is the maximum charset we'd want to consider.
         //$sql =
      // "SELECT regexp_matches($1, '^[-_.~!@#$%^&*(){}|:;<>,.?a-zA-Z0-9]+$')";
         // These seems more sensible:
// SELECT regexp_matches('a_B-3_:;,yelp#*@^~', E'^[-~_.:;,*@#%^$&|a-zA-Z0-9]+$');
         // SYNC_ME: Search: Cyclopath username regex.
         $sql = "SELECT regexp_matches($1, E'^[-_.:;,*@%^$&a-zA-Z0-9]+$')";

         //wfDebug("regex sql:" . $sql . "\n");
         //wfDebug("regex username:" . $username . "\n");

         $result = pg_query_params($sql, array($username))
            or die($this->report_error());
         //wfDebug("regex result:" . $result . "\n");
         if (pg_num_rows($result) < 1) {
            // The proposed username contains chars outside imposed charset.
            return false;
         }

         //wfDebug("addUser: regexp okay\n");

         // CcpV2 has a special SQL fcn. we can call to create the user, create
         // the user's private group, and grant the user access to their public
         // group as well as the public group.
         //
         // MAYBE: [lb] doesn't like using SQL fcns., since they're tedious to
         // write, tedious to debug, and tedious to maintain. Ideally, this
         // module should send a GWIS command to create the user and wire the
         // memberships. But this works for now...
         //
         // FIXME/:   We have to specify the instance here... is that weird?
         // BUG nnnn: It's so the branch_id of the group is set... but then,
         //           well, you can't share logins across instances without
         //           also populating group_ and group_membership in every
         //           instance.
         // MAGIC_NUMBER: See pyserver's conf.instance_name.
         $sql = "SET search_path TO minnesota, public;";
         $result = pg_query($sql) or die($this->report_error());
         //
         $sql = "SELECT cp_user_new($1, $2, $3)";
         // BUG 2763: FIXME: Is the email valid?
         //           I.e., no whitespace, commas, etc.
         $result = pg_query_params($sql, array($username,
                                               $user->getEmail(),
                                               $password))
            or die($this->report_error());
         //
         return true;
      }
   }

   // Only allow external users.
   //
   function strict() {
      return true;
   }

   // Initialize MediaWiki user with external information (just email for now).
   //
   function initUser(&$user, $autocreate=false) {

      $username = strtolower($user->getName());
      $username = str_replace(' ', '_', $username);

      $sql = "SELECT email FROM user_ WHERE username = $1";
      $result = pg_query_params($sql, array($username))
         or die($this->report_error());

      $row = pg_fetch_array($result);
      if ($row[0]) {
         // BUG 2763: FIXME: Is the email valid?
         //           I.e., no whitespace, commas, etc.
         $user->setEmail($row[0]);
      }

      return true;
   }

   // Allow users to log in with external username (lowercase; MediaWiki
   // expects camel case).
   //
   function getCanonicalName($username) {
      return ucwords($username);
   }

   //
   function report_error() {
      $err_msg = pg_last_error();
      wfDebug("report_error: err_msg: " . $err_msg . "\n");
      return $err_msg;
   }

}

