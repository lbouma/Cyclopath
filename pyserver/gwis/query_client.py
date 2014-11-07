# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import hashlib
import os
import psycopg2
import time
import urllib
import uuid

from grax.user import User
from gwis.query_base import Query_Base
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from util_ import db_glue
from util_ import misc

log = g.log.getLogger('gwis.q_client')

class Query_Client(Query_Base):

   __after_slots__ = (
      'ip_addr',           # ip address of the request
      'remote_ip',
      'remote_host',
      'browser_id',        # UUID session id for the browser
      'session_id',        # UUID session id for the client
      'username',          # User making request, or conf.anonymous_username
      'user_id',           # ID of user making request, or None for anon
      'user_group_id',     # User's private group ID, which could be anon group
      'request_is_mobile', # Used to know if request came from Ccp Android app.
      'request_is_local',  # If the request is coming from a local(host) script
      'request_is_script', # If the request is coming from a local(host) script
      'request_is_secret', # If the request used the shared secret
      'token_ok',          # True if the user token is valid
      )

   # *** Constructor

   def __init__(self, req):
      Query_Base.__init__(self, req)
      log.areq = req.areq
      # Cache the IP address for simpler retrieval later
      # FIXME: Are these always the same? Is one 'safer' to use?
      if self.req.areq is not None:
         self.ip_addr = self.req.areq.subprocess_env['REMOTE_ADDR']
         self.remote_ip = self.req.areq.connection.remote_ip
         # This is set in Fedora but not in Ubuntu.
         self.remote_host = self.req.areq.connection.remote_host
         rem_host = self.req.areq.get_remote_host()
         if self.remote_host is None: # Ubuntu
            # Ubuntu: '127.0.0.1', not Fedora: 'localhost'
            self.remote_host = rem_host
         # FIXME: I don't quite get the differences between OSes yet.
         if self.remote_host == '127.0.0.1':
            self.remote_host = 'localhost'
         # FIXME: assert-if-debugging, like, m4 preprocess? with intent to be
         #        faster (you could test with the update script)
         #g.assurt(self.remote_host == self.req.areq.hostname)
         log.verbose('remote: ip: %s (%s) / host: %s (%s) / (%s)'
                     % (self.remote_ip, # same as ip_addr
                        self.ip_addr, # should be == eg 127.0.0.1
                        self.remote_host, # None in Ubuntu, else hostname
                        rem_host, # Ubuntu: 127.0.0.1
                        self.req.areq.hostname, # Ubuntu: localhost
                        ))
      else:
         self.ip_addr = '127.0.0.1'
         self.remote_ip = '127.0.0.1'
         self.remote_host = 'localhost.localdomain'
      self.request_is_mobile = False
      self.request_is_local_set()
      #
      self.username = None
      self.user_id = None
      self.user_group_id = None

   # ***

   #
   def request_is_local_set(self):

      self.request_is_local = False
      self.request_is_script = False
      self.request_is_secret = False

      try:
         hostname = self.req.areq.hostname
         g.assurt(hostname)
      except AttributeError:
         # This happens from routed.py, which creates a fake request for
         # search_graph.
         g.assurt(self.req.areq is None)
         hostname = ''

      log.verbose1('request_is_local_set: %s'
                   % (self.str_remote_ip_and_host_and_local_host(),))

      # Validate the server from where the request came. This has to be the
      # conf.server_names (set in CONFIG). [M.f. command_client.py]
      # 2012.08.16: Instead of assurting, return a nice error code instead
      # (otherwise user sees "Cyclopath is having difficulty communicating
      # with the Cyclopath servers", which is wrong because that's not the
      # issue (and it's also wrong because there's only one Cyclopath server,
      # not many of them)). See Bug 2713.
      if ((hostname)
          and (hostname not in conf.server_names)
          and (hostname != conf.server_name)
          and (hostname != 'localhost')
          and (hostname != '127.0.0.1')):
         log.error('Unexpected request on hostname: %s.'
                   % (hostname,))
         raise GWIS_Error(
            '%s%s'
            % ('The Cyclopath server does not expect requests from %s. '
                % (hostname,),
               'Please check your URL or email %s for help.'
                % (conf.mail_from_addr,),))

      # We like to know if the request is local so we can enable commands we
      # don't normally accept from remote clients (i.e., so we can support
      # developer or experimental features, like changing group access
      # permissions).
      # NOTE The ccp.py script can be used to directly interact with pyserver,
      #      or it can interface with GWIS packets. In the latter case, we
      #      cannot determine if the call is coming from the script or from the
      #      user using flashclient.
      # NOTE I've [lb has] seen os.getenv('PythonHandler') set in other
      #      environs, but not on Fedora Linux.
      # NOTE: On Fedora, from ccp.py, os.getenv('_') == './ccp.py'
      # NOTE: On Fedora, if you disable the network, these... return False?
      is_httpd_user = ((os.getenv('APACHE_RUN_USER') == 'www-data')  # Ubuntu
                       or (os.getenv('_') == '/usr/sbin/httpd'))     # Fedora

      if (    ((self.remote_host == 'localhost.localdomain')
               or (self.remote_host == 'localhost')
               or (self.remote_host == conf.server_ip))
          and ((self.remote_ip == '127.0.0.1')
               or (self.remote_ip == conf.server_ip))
          and ((not hostname) or (hostname in conf.server_names))):

         # FIXME (and EXPLAIN): Are the Apache request's host and IP
         #       trustworthy? I don't think so. But can they be spoofed
         #       to look like they're from localhost?
         # BUG nnnn: We need to better lockdown the site... --no-password
         #           is such a back-door: you just need terminal access to
         #           the machine...

         self.request_is_local = True

         if not is_httpd_user:
            g.assurt(self.req.areq is None)
            # LOGNAME is set when a human user runs script, but not for apache.
            g.assurt(os.getenv('LOGNAME'))
            # NOTE: Also, normally, os.getenv('_') == '/usr/bin/python'
            #                                   or == './ccp.py', depending.
            self.request_is_script = True

      else:
         g.assurt(is_httpd_user)
         g.assurt(self.req.areq is not None)

   #
   def str_remote_ip_and_host_and_local_host(self):
      remote_id = (
         'from: %s / %svia: %s'
         % (self.remote_ip,
            '' if (self.remote_host == self.remote_ip)
               else '%s / ' % (self.remote_host,),
            self.req.areq.hostname if self.req.areq is not None else 'none',))
      return remote_id

   # *** Base class overrides

   #
   def decode_gwis(self):

      self.browser_id = self.req.decode_key('browid', None)

      # FIXME/Bug nnnn: This should be verified and maybe stored by us somehow.
      # FIXME: GIA records that use sessid should timeout the sessid and clear
      #        the value eventually...
      self.session_id = self.req.decode_key('sessid', None)
      try:
         self.session_id = uuid.UUID(self.session_id)
         # Convert to string to get rid of the class wrapper.
         # >>> uuid.uuid4()
         #  UUID('ed05a929-6acf-4315-abf2-8b229babf347')
         # >>> str(uuid.uuid4())
         #  'b1f691f6-0fb7-419f-811e-1a74c3c995a1'
         self.session_id = str(self.session_id)
      except TypeError:
         g.assurt(not self.session_id)
         # The user did not specify a session ID, so we should do it.
         self.session_id = str(uuid.uuid4())
         # But currently this is unexpected, since flashclient and android
         # currently make up their own UUID (see Bug nnnn mentioned above
         # about having pyserver assign and manage unique session IDs).
         # MAYBE: For devs testing, e.g., with wget, there's no session ID.
         #        But maybe we should always make it mandatory so people
         #        don't game the system?
         # 2014.09.20: logcheck says this happened again. Nothing weird
         # in the apache log, though. And it wasn't a dev using wget or
         # anything, [lb] don't think.
         #             
         log.error('decode_gwis: unexpected: no Session ID')
         # MAYBE: Is it ok to log the request?
         log.info('EXPLAIN: decode_gwis: areq.the_request: %s'
                  % (self.req.areq.the_request,))
      except:
         # ValueError on wrongly-formatted str; AttributeError on other types.
         raise GWIS_Error('decode_gwis: bad session ID')
      # FIXME: Is this the proper place for this code?
      # FIXME: Why does device come in metadata and not GET?
      if self.req.doc_in is not None:
         device = self.req.doc_in.find('metadata/device')
         # FIXME: Compare to other place request_is_mobile is set (below).
         if device is not None:
            # NOTE: The URL might also contain "android=true".
            # EXPLAIN: Diff. btw URL and metadata indicating android?
            #          The two seem redundant...
            self.request_is_mobile = device.get('is_mobile', False)

   # *** Public interface

   #
   def remote_host_or_remote_ip(self):
      return (self.remote_host or self.remote_ip)

   #
   def user_token_generate(self, username):
      ''' '''

      # Lookup the userid
      res = self.req.db.sql(
         "SELECT id FROM user_ WHERE username = %s", (username,))

      # Bail if user doesn't exist
      if len(res) != 1:
         return None # no such user

      user_id = res[0]['id']

      # In Ccpv1, this fcn. used the user's hashed password and some request
      # parameters (remote_addr, self.req.areq.protocol, HTTP_USER_AGENT,
      # HTTP_ACCEPT_CHARSET, and HTTP_ACCEPT_LANGUAGE) to make the token, but
      # that's not a very robust solution.
      #
      #   See http://bugs.grouplens.org/show_bug.cgi?id=2608
      #
      # Basically, random, unique tokens are more secure, and flashclient
      # uses different headers for normal GWIS requests vs. uploads, so a
      # generated-token approach doesn't work, anyway; we should store the
      # token in the database rather than trying to make it.

      # Ccpv1:
      #   # Lookup the password
      #   r = self.req.db.sql(
      #      "SELECT password FROM user_ WHERE username = %s", (username,))
      #   token = (
      #      r[0]['password']
      #      + remote_addr
      #      + env.get('HTTP_USER_AGENT', '@')
      #      + env.get('HTTP_ACCEPT_CHARSET', '@')
      #      + self.req.areq.protocol
      #      + env.get('HTTP_ACCEPT_LANGUAGE', '@'))
      #   #self.req.p_notice('unhashed token for %s: %s' % (username, token))
      #   token = hashlib.md5(token).hexdigest()

      # Count the number of times we try, so we don't try indefinitely.
      num_tries = 1

      if self.req.db.integrity_errs_okay:
         log.warning('user_token_generate: unexpected integrity_errs_okay')
      self.req.db.integrity_errs_okay = True

      found_unique = False
      while not found_unique:
         token = str(uuid.uuid4())
         # For now, test the same one and see what server throws
         log.debug('user_token_generate: trying token: %s' % (token,))
         if num_tries > 99:
            raise GWIS_Error('user_token_generate: Too many tries!')
         try:
            # Lock the user_ table on the user name so we don't ever generate
            # two active tokens for a user.
            # FIXME: What about multiple devices? Like, desktop Web browser and
            # mobile phone app...
            # (found_row, locked_ok,
            #    ) = self.req.db.transaction_lock_row(
            #       'user_', 'username', username)
            # Ug, we don't need a lock so long as we're just inserting...
            self.req.db.transaction_begin_rw()
            # FIXME: Set date_expired after x minutes of inactivity!
            #        (In CcpV1, there was no expiry...)....
            # FIXME: Don't do this, because user should be allowed to logon
            # from more than one client.
            #res = self.req.db.sql(
            #   """
            #   UPDATE
            #      user__token
            #   SET
            #      date_expired = now()
            #   WHERE
            #      username = '%s'
            #      -- AND user_id = %d
            #      AND date_expired IS NULL
            #   """ % (username, user_id,))
            #g.assurt(res is None)
            # Try the insert.
            res = self.req.db.sql(
               # SYNC_ME: ccpdev...logcheck/pyserver...sql().
               #          Don't use a preceeding newline.
               """INSERT INTO user__token
                     (user_token, username, user_id)
                  VALUES
                     ('%s', '%s', %d)
               """ % (token, username, user_id,))
            g.assurt(res is None)
            found_unique = True
            # BUG 2688: Use transaction_retryable?
            self.req.db.transaction_commit()
         except psycopg2.IntegrityError, e:
            # IntegrityError: duplicate key value violates unique constraint
            # "user__token_pkey"\n
            log.debug('token_gen: IntegrityError: %s' % (str(e),))
            g.assurt(str(e).startswith('duplicate key value violates'))
            num_tries += 1 # Try again
            self.req.db.transaction_rollback()

      self.req.db.integrity_errs_okay = False

      log.debug('user_token_generate: %s / new token: %s' % (user_id, token,))

      return token

   #
   # If called via transaction_retryable:
   #  def user_token_verify(self, db, *args, **kwargs):
   #     (token, username,) = args
   # but let's try the transaction_lock_row_logic fcn.
   # with a timeout and/or max_tries.
   #
   # FIXME/BUG nnnn: mobile should use the token we send it.
   #
   def user_token_verify(self, token, username, going_deeper=False):

      g.assurt(token and username)

      # Get a lock on the token just so we can update its count. This
      # shouldn't block except for overlapping requests from the same
      # client, so no biggee.
      # MAYBE: We don't need the lock except to update usage_count...
      #        which doesn't seem very much that important...

      self.token_ok = False

      # MAYBE: Using NOWAIT fails when server load is high, so [lb]
      #        uses STATEMENT_TIMEOUT instead of NOWAIT.
      #        But another solution might be to wrap UPDATE with a try/catch
      #        and not to lock at all...
      time_0 = time.time()

      found_row = None
      locked_ok = False

      try:

         (found_row, locked_ok,
            ) = self.req.db.transaction_lock_row_logic(
               table_to_lock='user__token',
               row_logic=[('user_token', '=', self.req.db.quoted(token),),
                          ('date_expired', 'IS', 'NULL',),
                          ('usage_count', None, None,),
                          ('username', None, None,),
                          ],
               #timeout=conf.gwis_default_timeout, # 2014.09.09: 80.0 secs.
               # 2014.09.14: We can continue without the token lock (we'll
               # just not update the user__token.usage_count value) so don't
               # take forever until timing out.
               # FIXME/BUG nnnn: Seriously, locking a user__token row should
               # almost always work, so why is this not working when the server
               # is busy running daily.runic.sh?
               timeout=10.0, # MAGIC NUMBER: Try for at most 10 seconds...
               max_tries=None,
               timeout_logger=log.info)

         # Log a Warning (which logcheck will see) above a certain
         # threshold, and at least log a debug message above a lower
         # bar. [lb] doesn't want to flood us with emails but I want
         # to track this issue... i.e., What is causing it to take so
         # long to get the lock: is the server "just busy"? I've seen
         # this issue when I run the daily cron job, which dumps the
         # database, etc. Maybe having one hard drive doing all of the
         # dirty work just really sucks...
         misc.time_complain('user_token_verify get user__token lock',
                            time_0,
                            # 2014.09.08: [lb] sees upwards of 2 seconds
                            #             here and there... hrmmmm, should
                            #             we worry?
                            #threshold_s=0.75,
                            #threshold_s=1.00,
                            #threshold_s=2.00,
                            #threshold_s=2.50,
                            # 2014.09.14: When cron runs our overnight jobs,
                            # this always seems to fire (try, say, at 3:15 AM).
                            # 2014.09.19: How exactly does this work?:
                            # Sep-19 03:28:20: time_complain: ... took 13.12 m.
                            #threshold_s=conf.gwis_default_timeout, # No errs?
                            # BUG nnnn/LOW PRIORITY?/EXPLAIN:
                            # gwis_default_timeout is not being honored,
                            # i.e., we set a 10 sec. timeout on lock-row but
                            # db_glue spins for 13 minutes? How does that work?
                            # The only reasonable explanation is that
                            # psycopg2's curs.execute took that long, right?
                            #threshold_s=840.0, # MAGIC_NUMBER: 840 s = 14 mins
                            threshold_s=1338.0, # MAGIC_NUMBER: 22.30 mins
                            at_least_debug=True,
                            debug_threshold=0.10,
                            info_threshold=0.25)

      except psycopg2.DataError, e:
         # This is only possible if client request is malformed. E.g.,
         #   DataError: invalid input syntax for uuid: "gibberish"
         #   LINE 10:             AND user_token = 'gibberish'
         log.error('user_token_verify: bad token: %s' % (token,))
         raise GWIS_Warning('Unknown username or token',
                            'badtoken')

      except Exception, e:
         raise

      if found_row:
         # NOTE: This commits self.req.db, which recycles the cursor.
         self.token_ok = self.user_token_verify_(found_row,
                                                 token,
                                                 username,
                                                 lock_acquired=locked_ok)

      log.verbose(
         'user_token_verify: found_row: %s / locked_ok: %s / token_ok: %s'
         % (found_row, locked_ok, self.token_ok,))

      return found_row

   #
   def user_token_verify_(self, found_row, token, username, lock_acquired):

      token_ok = False

      if found_row['username'] != username:
         self.req.db.transaction_rollback()
         log.error('user_token_verify_: tkn: %s / row[0][u]: %s / usrnm: %s'
                   % (token, found_row['username'], username,))
         raise GWIS_Error('%s %s'
            % ('Token found but username does not match.',
               'Please log out and log on again.',))

      # Token ok! Update the count, if we can.
      # BUG nnnn: When the server is busy, especially during the nightly
      # cron, since each user and each script generates lots of requests,
      # oftentimes psql timesout trying to lock the user__token row for
      # update (after trying for 4 secs., e.g.). Fortunately, the
      # usage_count is not an important value, so it can underrepresent
      # it's true value.
      # EXPLAIN: Each request only locks user__token briefly at the start
      #          of each request, but releases it soon after. So why are
      #          we timing out??
      # Here's a snippet from the production server: note the big time gap
      # between log messages:
      # 03:56:38 util_.db_glue # Thd 2 # lck_row_lgc: locking user__token...
      # 03:56:42  gwis.request # Thd 1 # areq_send_resp: sent 70 gwis bytes.
      # 03:56:42 util_.db_glue # Thd 2 # sql: query canceled:
      #                         canceling statement due to statement timeout
      #
      if lock_acquired:
         update_sql = (
            """
            UPDATE user__token
               SET usage_count = usage_count + 1
             WHERE date_expired IS NULL
               AND user_token = %s
            """)
         update_row = self.req.db.sql(update_sql, (token,))
         g.assurt(update_row is None)
         # BUG 2688: Use transaction_retryable?
         self.req.db.transaction_commit()
         log.info('user_validate: token and lock: %s / %s / new cnt >=: %s'
            % (username,
               self.str_remote_ip_and_host_and_local_host(),
               found_row['usage_count'] + 1,))
      else:
         log.info('user_validate: token w/o lock: %s / %s / old cnt: %s'
            % (username,
               self.str_remote_ip_and_host_and_local_host(),
               found_row['usage_count'],))

      token_ok = True

      return token_ok

   #
   def user_validate_maybe(self, variant=None):

      if self.username is None:
         self.user_validate(variant)

   #
   def user_validate(self, variant=None):
      '''
      Check the username and password/token included in the GWIS request.

         - If not provided          set self.username to anonymous username
         - If provided and valid    set self.username to validated username
         - If provided and invalid  raise GWIS_Error.

      '''

      log.verbose1('user_validate: variant: %s' % (str(variant),))
      user = None
      if self.req.doc_in is not None:
         user = self.req.doc_in.find('metadata/user')
      if user is None:
         # No auth data; set username to the anonymous user
         log.info('user_validate: anon: %s / %s'
                  % (conf.anonymous_username,
                     self.str_remote_ip_and_host_and_local_host(),))
         self.username = conf.anonymous_username
         self.user_group_id = User.private_group_id(self.req.db,
                                                    conf.anonymous_username)
         g.assurt(self.user_group_id > 0)
      else:
         # Parse and validate the username and credentials; raises on error.
         self.user_validate_parse(user, variant)
      if self.username is not None:
         # Check user's access to branch. Raises GWIS_Error if access denied.
         self.req.branch.branch_hier_enforce()

   #
   def user_validate_parse(self, user, variant):
      '''
      Called if the GWIS client includes a username. Here we verify the
      username and password or token. The fcn. raises GWIS_Error if the
      user cannot be authenticated.
      '''

      valid = False

      username = user.get('name').lower()
      password = user.get('pass')
      sdsecret = user.get('ssec')
      token = user.get('token')
      g.assurt((password is None) or (token is None))

      # NOTE: In CcpV1, route reactions adds save_anon. E.g.,
      #    # If save_anon is set, then perform the save as an anonymous user.
      #    save_anon = bool(int(self.decode_key('save_anon', False)))
      #    if save_anon:
      #       self.req.username = None
      # but this is hopefully unnecessary. And it seems... wrong, like, we
      # should set a bool that the user wants to save anonymously, otherwise
      # none of the code will know there's a real user here (e.g., for tracing
      # or storing stats).

      # *** MAGIC AUTH

      if ((conf.magic_localhost_auth)
          and (self.ip_addr == conf.magic_auth_remoteip)):

         # HACK: localhost can be whomever they like
         # This is similar to the ccp script's --no-password, but this is used
         # for spoofing another user via flashclient.
         # Logs an Apache warning.
         self.req.p_warning('user %s from localhost: magic auth' % (username,))
         # Redundantly log a pyserver warning.
         # FIXME: Do we really need to log Apache warnings at all?
         log.warning('SPOOFING USER: %s from %s' % (username, self.ip_addr,))

      # *** PASSWORD AUTH

      elif variant == 'password':

         if password:
            r = self.req.db.sql("SELECT login_ok(%s, %s)",
                                (username, password,))
            g.assurt(len(r) == 1)
            if not r[0]['login_ok']:
               self.auth_failure(username, 'password')
               raise GWIS_Warning(
                  'Incorrect username and/or password.',
                  tag=None, logger=log.info)
         elif not sdsecret:
            raise GWIS_Warning(
               'Please specify a password with that username.',
               tag=None, logger=log.info)

         log.info('user_validate: pwdd: %s / %s'
                  % (username,
                     self.str_remote_ip_and_host_and_local_host(),))

            # FIXME: Statewide UI: Cleanup Session IDs records on login/logout.
# FIXME: Use cron job to mark date_expired where last_modified is
#        some number of minutes old? flashclient log should keep
#        token active, right?
#        See the unimplemented: gwis/command_/user_goodbye.py
#        2014.09.09: The date_expired field in really old tokens
#                    is still NULL...

      # *** TOKEN AUTH

      elif variant == 'token':

         log.verbose1('user_validate_parse: token: %s / username: %s'
                      % (token, username,))

         if token is None:
            log.warning('user_validate_parse: EXPLAIN: Why is the token None?')
            raise GWIS_Warning('Token not found! Please login again.',
                               'badtoken')

         # Avoid transaction_retryable, at least so long as it expects a
         # specific TransactionRollbackError, but transaction_lock_row_logic
         # simply raises Exception.
         #   success = self.req.db.transaction_retryable(
         #      self.user_token_verify, self.req, token, username)
         # 2013.09.25: Using SELECT... FOR UPDATE NOWAIT seemed to work okay
         # until [lb] started running runic's daily cron job and also a
         # shapefile import script -- then all lock-rows came back failed.
         # But the scripts aren't even touching that database or the
         # user__token row! What gives?! I searched and couldn't find any
         # indication that NOWAIT and FOR UPDATE do anything other than on
         # the row on which they're suppose to behave... so this is truly
         # strange. So now db_glue uses STATEMENT_TIMEOUT instead of NOWAIT.
         found_row = self.user_token_verify(token, username)

         if found_row is None:
            log.info(
               'user_validate_parse: timeout on token verify: username: %s'
               % (username,))
            raise GWIS_Warning(
               'Please try your request again (server very busy).',
               'sadtoken',
               logger=log.info)
         elif found_row is False:
            log.warning(
               'user_validate_parse: not found_row: token: %s / username: %s'
               % (token, username,))
            raise GWIS_Warning(
               'Please log off and log back on (incorrect token).',
               'badtoken')
         # else, found_row is True

         # EXPLAIN: Does p_notice write to Apache log? We're fine, because
         #          GWIS_Warning writes to the pyserver log... right?
         #self.req.p_notice('tokens: %s %s' % (token, token_valid,))

         if not self.token_ok:
            # [lb] guessing this unreachable; would've raised exception by now.
            log.debug('user_validate_parse: token not ok: %s' % (token,))
            self.auth_failure(username, 'token')
            raise GWIS_Warning(
               'Please log off and log back on (incorrect token).',
               'madtoken')

      # *** MISSING AUTH

      else:
         # No match for variant.
         log.warning('user_validate_parse: unknown variant: %s' % (variant,))
         raise GWIS_Error('Unknown variant.', 'badvariant')

      # *** SHARED SECRET

      if sdsecret:
         log.debug('user_validate_parse: using shared_secret to login')
         if (   ('' == conf.gwis_shared_secret)
             or (sdsecret != conf.gwis_shared_secret)
             or (not self.request_is_local)):
            log.error('Expected: %s / Got: %s / Local: %s'
               % (conf.gwis_shared_secret, sdsecret, self.request_is_local,))
            raise GWIS_Error('Whatchutalkinboutwillis?', 'badssec')
         self.request_is_secret = True

      # *** And The Rest.

      # If we got and verified a token, the username was checked against what's
      # in the db, so it should be clean. But if the username contains a quote
      # in it, we want to make sure it's delimited properly.
      # This is the simplest form of SQL injection: add a single quote and
      # a true result and then terminate the statement, e.g., same username is:
      #     ' or 1=1;--
      # E.g., SELECT * FROM user_ WHERE username='%s' AND password='%s';
      #   could be turned into, with, e.g., "fake_username' OR 1=1; --"
      #       SELECT * FROM user_ 
      #        WHERE username='fake_username' OR 1=1; -- AND password='%s';
      # Of course, this is just a trivial example.

      self.username = urllib.quote(username).strip("'")
      if self.username != username:
         raise GWIS_Warning('Bad username mismatch problem.',
                            'badquoteusername')

      if self.req.areq is not None:
         # Update Apache request_rec struct so username is recorded in logs.
         self.req.areq.user = username

      # Get the user ID
      self.user_id = User.user_id_from_username(self.req.db, username)
      g.assurt(self.user_id > 0)

      # Get the user's private group ID
      self.user_group_id = User.private_group_id(self.req.db, self.username)
      g.assurt(self.user_group_id > 0)

      # FIXME: We checked 'metadata/device' above, and now 'metadata/user' --
      #        which one is it?
      # BUG nnnn: Don't rely on this value, since the client can spoof it.
      if not self.request_is_mobile:
         self.request_is_mobile = user.get('is_mobile', False)

   # *** Private interface

   #
   def auth_failure(self, username, kind):
      '''
      Responds to an authentication failure.
      '''
      g.assurt(kind in ('password', 'token',))
      # To make the sql calls easier, make a lookup
      args = {
         'username': username,
         'is_password': (kind == 'password'),
         'client_host': self.ip_addr,
         'instance': conf.instance_name,
         }
      # We need a r/w transaction in order to record the failure
      # BUG 2688: Use transaction_retryable?
      self.req.db.transaction_commit()
      self.req.db.transaction_begin_rw()
      # Log the auth failure
      # 2012.06.08: [lb] In CcpV1, I see 24 of these in a row for myself.
      #                  What gives?
      #
      # EXPLAIN: The daily.runic.sh nightly cron will look at user login
      # failures, and it'll complain/email if there are more than a certain
      # amount per day per user.
      # BUG nnnn: Do we need a better mechanism for detecting username attacks?
      #           Have we tested brute-force password attacks?
      #           What about other attacks....?
      self.req.p_notice('auth failed for "%s" (%s)' % (username, kind))
      log.info('auth_failure: username: %s / kind: %s' % (username, kind,))

      self.auth_failure_log_event(args)
      # Check if there have been too many recent failures
      self.auth_failure_check_recent(kind, args)
      # Commit now; we'll raise an exception shortly
      # BUG 2688: Use transaction_retryable?
      self.req.db.transaction_commit()

   # Check if there have been too many recent failures
   def auth_failure_check_recent(self, kind, args):
      if (kind == 'password'):
         limit_day = conf.auth_fail_day_limit_password
         limit_hour = conf.auth_fail_hour_limit_password
      else:
         limit_day = conf.auth_fail_day_limit_token
         limit_hour = conf.auth_fail_hour_limit_token
      fail_ct_day = self.auth_failure_recent_fail_count(args, '1 day')
      fail_ct_hour = self.auth_failure_recent_fail_count(args, '1 hour')
      if ((fail_ct_day > limit_day)
          or (fail_ct_hour > limit_hour)):
         # over the limit - host is banned
         self.req.p_warning('host banned - too many authentication failures!')
         if (fail_ct_day > limit_day):
            expires = "'infinity'"
         else:
            expires = "now() + '61 minutes'::interval"
         self.auth_failure_mark_banned(args, expires)

   #
   def auth_failure_log_event(self, args):
      self.req.db.sql(
         """
         INSERT INTO auth_fail_event
            (username,
             client_host,
             is_password,
             instance)
         VALUES
            (%(username)s,
             %(client_host)s,
             %(is_password)s,
             %(instance)s)
         """, args)

   #
   def auth_failure_mark_banned(self, args, expires):
      self.req.db.sql(
         """
         INSERT INTO ban
            (ip_address,
             public_ban,
             full_ban,
             ban_all_gwis,
             activated,
             expires,
             reason)
         VALUES
            (%%(client_host)s,
             FALSE,
             FALSE,
             TRUE,
             TRUE,
             %s,
             'Too many authentication failures')
         """ % (expires,), args)

   #
   def auth_failure_recent_fail_count(self, args, interval):
      # NOTE args is a dict w/ 'is_password' and 'client_host'
      bans = self.req.db.sql(
         """
         SELECT
            count(*) AS count
         FROM
            auth_fail_event
         WHERE
            is_password = %%(is_password)s
            AND NOT ignore
            AND client_host = %%(client_host)s
            AND created > (now() - '%s'::interval)
         """ % (interval,), args)
      return bans[0]['count']

   # ***

# ***

