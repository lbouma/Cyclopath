# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

'''This file defines the database handle class.

   Note: All transactions are read-only unless writing is specifically
   requested in transaction_begin_rw(). See Bug 1203 for why this is so.'''

import conf
import g

from lxml import etree
import psycopg2
import random
import threading
import time
import traceback
import urllib2

from util_ import misc

log = g.log.getLogger('util_.db_glue')
# Ug: Why doesn't this work?:
#     from util_ import logging2
#     log.setLevel(logging2.VERBOSE)

# WARNING: Tracebacks can be sent to the browser.
# Use caution; don't let a traceback include things like passwords.
def make_connect_string(db_name=None, db_user=None):
   if db_name is None:
      db_name = conf.db_name
   if db_user is None:
      db_user = conf.db_user
   if db_user == conf.db_user:
      db_password = conf.db_password
   else:
      g.assurt(db_user == conf.db_owner)
      db_password = conf.db_owner_pass
   # NOTE: The ordering of these params is strick, even though they are named=.
   # 2013.08.30: Well this took forever to figure out: We need to use
   #             quote marks in the connect string.
   # http://comments.gmane.org/gmane.comp.python.db.psycopg.devel/5155
   # WRONG:
   #   connect_string = (
   #      "dbname=%s user=%s password=%s host=%s port=%d"
   #      % (db_name, db_user, db_password, conf.db_host, conf.db_port,))
   connect_string = (
      "dbname='%s' user='%s' host='%s' port='%d' password='%s'"
      % (db_name, db_user, conf.db_host, conf.db_port, db_password,))

   return connect_string

def new(db_user=None, use_transaction=True, trans_serializable=False):
   '''Return a DB object which is not in use by any other requests. FIXME:
      Currently, this may be too inefficient; should use some kind of
      connection pooling.'''
   return DB(db_user, use_transaction, trans_serializable)

log.debug('DB: starting with database: %s' % (conf.db_name,))

class DB(object):

   # Default to whatever's set at $PYSERVER_DB or to CONFIG at [db] database.
   db_name = conf.db_name
   conn_str = make_connect_string(db_name)
   # The conn_lookup is a lookup of id(self.conn) => id(self). It's used for
   # debugging: if you see complaints that self.conn already maps to self, it
   # means you didn't db.close() and instead let the db close by running out of
   # scope. So not a huge deal, since close() isn't necessary, but it is good
   # form.
   conn_lookup = {}
   conn_lock = threading.RLock()

   # This tracks open cursors, but it doesn't track which cursors belong to
   # which connections (but if you trace the log file you can figure it out).
   cursors_open = set()

   concurrency_prefix = (
      "ERROR:  could not serialize access due to concurrent update\n")
   # MAYBE: logcheck sends these errors our way, even though we catch
   #        concurrency errors. Can we tell logcheck to ignore them?
   #        Also, note the out-of-order sequencing.
   #    WHERE id = 1569893 AND version = 342
   #  WHERE id = 1569893 AND version = 342 / UPDATE route SET valid_before_rid = 22460
   #  WHERE id = 1569893 AND version = 342
   # 2014-01-29 16:18:35 CST ERROR:  could not serialize access due to concurrent update
   # Jan-29 16:18:35 WARNING  Waited 2.42 secs. for lock on revision
   # UPDATE route SET valid_before_rid = 22460

   __slots__ = (
      'conn',
      'curs',
      'dont_fetchall',
      'locked_tables',
      'locked_on_table',
      'locked_on_table_row',
      'locked_on_time0',
      'integrity_errs_okay',
      )

   def __init__(self, db_user=None,
                      use_transaction=True,
                      trans_serializable=False,
                      skip_connect=False):
      if not skip_connect:
         if db_user is None:
            connect_string = DB.conn_str
         else:
            connect_string = make_connect_string(DB.db_name, db_user)
         self.connect_and_setup(connect_string, use_transaction,
                                trans_serializable)

   # ***

   #
   @staticmethod
   def set_db_name(db_name):
      log.debug('set_db_name: switching to database: %s' % (db_name,))
      DB.db_name = db_name
      DB.conn_str = make_connect_string(DB.db_name)

   # ***

   #
   def cancel(self):
      log.verbose('cancel db_glue connection')
      if self.conn is not None:
         self.conn.cancel()

   # Clone the db, creating a new cursor. This is technically better than
   # db_glue.new(), since we don't have to connect.
   def clone(self):

      g.assurt(not self.conn.closed)

      new_db = DB(skip_connect=True)
      new_db.conn = self.conn
      # Make a new cursor
      new_db.curs = self.cursor()
      # FIXME: With cursors, do they inherit each others transactions? I think
      # so... can we test the connection to see if there's a transaction in
      # progress? For now, not copying locked_tables, which is probably wrong.
      new_db.locked_tables = None # self.locked_tables
      new_db.locked_on_table = None
      new_db.locked_on_table_row = None
      new_db.locked_on_time0 = None

      # DEVS: Watch out! If what you're cloning set dont_fetchall,
      #       then "rows = db.sql(some_sql)" will not return any rows.
      #       The caller is responsible for resetting this value... oddly.
      #
      new_db.dont_fetchall = self.dont_fetchall

      # Register the new database object with the psycopg2 connection.
      DB.conn_lock.acquire()
      g.assurt(id(self.conn) in DB.conn_lookup)
      misc.dict_list_append(DB.conn_lookup, id(self.conn), id(new_db))
      DB.conn_lock.release()

      # DEVS: If the have problems with cursors and committing, e.g.,
      #        Exception: Cannot commit when multiple cursors open...
      #       then enable this trace statement and find out who's not
      #       calling db.curs.close() before the commit: that is, all
      #       but one cursor must be closed before you can commit any
      #       transaction. See also: curs_close, and connect_and_setup.
      #log.debug('    clone: new_db: curs: %s / conn: %s / self: %s'
      #   % (hex(id(new_db.curs)), hex(id(new_db.conn)), hex(id(new_db)),))

      return new_db

   # Python doesn't call, like, __del__() when an object is deleted or goes out
   # of scope. So users of DB() must call close() when they're done, especially
   # if they've db_clone'd.
   #
   # FIXME: 2013.07.09: Does clone matter as much now that we use PgBouncer?
   def close(self):
      if hasattr(self, 'conn'):
         if self.conn is not None:
            log.verbose('close: calling conn_decrement...')
            n_ref = self.conn_decrement()
            if n_ref > 0:
               #log.debug(
               #   'close: conn_lookup: %7d conns open / to: %s /selfs: %s'
               #   % (n_ref, hex(id(self.conn)),
               #      ','.join([hex(x) for x
               #                in DB.conn_lookup[id(self.conn)]]),))
               self.curs_close()
            else:
               # Skipping: self.transaction_rollback() and/or self.cancel().
               try:
                  if self.curs is not None:
                     g.assurt(self.conn is not None)
                     self.curs_close()
               except AttributeError, e:
                  g.assurt(str(e) == 'curs')
                  pass
               if self.conn is not None:
                  if not self.conn.closed:
                     self.conn.close()
                  del self.conn
               log.verbose('close: closed!')
         else:
            log.verbose('close: skipped (self.conn is None)')
            del self.conn

   #
   def conn_decrement(self):
      n_ref = None
      DB.conn_lock.acquire()
      if id(self.conn) not in DB.conn_lookup:
         log.error('conn_decrement: missing: self.conn: %s'
                   % (hex(id(self.conn)),))
         if conf.db_glue_strict_assurts:
            g.assurt(False)
      elif id(self) not in DB.conn_lookup[id(self.conn)]:
         log.error('conn_decrement: missing: self: %s'
                   % (hex(id(self)),))
         if conf.db_glue_strict_assurts:
            g.assurt(False)
      log.verbose('conn_decrement: conn_lookup: nixxing: %s / %s'
                % (hex(id(self.conn)), hex(id(self)),))
      try:
         DB.conn_lookup[id(self.conn)].remove(id(self))
      except KeyError:
         pass
      n_ref = len(DB.conn_lookup[id(self.conn)])
      if n_ref == 0:
         del DB.conn_lookup[id(self.conn)]
      DB.conn_lock.release()
      return n_ref

   #
   def curs_close(self):
      try:
         try:
            if not self.curs.closed:
               #log.debug('       curs_close: curs: %s / conn: %s / self: %s'
               #   % (hex(id(self.curs)), hex(id(self.conn)), hex(id(self)),))
               self.curs.close()
               DB.cursors_open.remove(self.curs)
         except psycopg2.InterfaceError, e:
            # I.e., InterfaceError: already closed
            # Is this an error? Checking self.curs.closed should prevent this.
            log.error('curs_close: InterfaceError: %s' % (str(e),))
            pass
         # Not really sure why, but removing attr rather than setting to None.
         del self.curs # No longer valid.
      except AttributeError, e:
         g.assurt(str(e) == 'curs')
         pass
      self.locked_tables = None
      self.locked_on_table = None
      self.locked_on_table_row = None
      self.locked_on_time0 = None

   #
   def curs_recycle(self):
      # The cursor stores the results of the postgres query in memory, so toss
      # it and get a new cursor.
      self.curs_close()
      # Now get a new cursor from the database connection.
      if not self.conn.closed:
         self.curs = self.cursor()
      else:
         log.error('curs_recycle: connection is closed')
         if conf.db_glue_strict_assurts:
            g.assurt(False)

   #
   def cursor(self):
      g.assurt(self.conn is not None)
      try:
         new_cursor = self.conn.cursor()
         DB.cursors_open.add(new_cursor)
         #log.debug('cursor: DB.cursors_open: %s' % (DB.cursors_open,))
      except psycopg2.extensions.QueryCanceledError, e:
         log.error('cursor: QueryCanceledError: %s' % (str(e),))
         raise
      except psycopg2.extensions.TransactionRollbackError, e:
         log.error('cursor: TransactionRollbackError: %s' % (str(e),))
         raise
      except psycopg2.OperationalError, e:
         # Bug 2796: "FATAL: connection limit exceeded for non-superusers"
         # DEVS: Maybe use PgBouncer or other connection pool, or raise
         # postgresql.conf's max_connections (which defaults to 100).
         log.error('cursor: OperationalError: %s' % (str(e),))
         raise # MAYBE: Raise gwis_error.GWIS_Error instead?
      #log.debug('           cursor: curs: %s / conn: %s / self: %s'
      #   % (hex(id(new_cursor)), hex(id(self.conn)), hex(id(self)),))
      return new_cursor

   #
   def quoted(self, s):
      return DB.quoted_(s)

   #
   @staticmethod
   def quoted_(s):
      if s is None:
         return "''"
      # NOTE: This is the same as (but less wordy than)
      #   psycopg2.extensions.QuotedString(str(s)).getquoted()
      return str(psycopg2.extensions.adapt(str(s)))

   #
   def recycle(self):
      self.curs_recycle()

   #
   def rowcount(self):
      try:
         rowcount = self.curs.rowcount
      except AttributeError:
         rowcount = -1
      return rowcount

   #
   def sequence_get_next(self, seq_name):
      return self.sql("SELECT nextval('%s')"
                      % (seq_name,))[0]['nextval']

   #
   def sequence_peek_next(self, seq_name):
      # COUPLING: This SQL is Postgres-specific.
      return self.sql("SELECT last_value + 1 AS nextval FROM %s"
                      % (seq_name,))[0]['nextval']

   #
   def sequence_set_value(self, seq_name, latest_val):
      self.sql("SELECT setval('%s', %d)" % (seq_name, latest_val,))

   # ***

   #
   def connect_and_setup(self, connect_string,
                               use_transaction,
                               trans_serializable=False):
      log.verbose('connect_string: %s' % (connect_string,))
      self.conn = psycopg2.connect(connect_string)
      #
      DB.conn_lock.acquire()
      if id(self.conn) in DB.conn_lookup:
         log.error('connect_and_setup: conn_lookup: self.conn exists: %s / %s'
                   % (hex(id(self.conn)), hex(id(self)),))
         if conf.db_glue_strict_assurts:
            g.assurt(False)
         else:
            del DB.conn_lookup[id(self.conn)]
      misc.dict_list_append(DB.conn_lookup, id(self.conn), id(self))
      DB.conn_lock.release()
      #log.verbose('connect_and_setup: conn_lookup: added: %s / %s'
      #            % (hex(id(self.conn)), hex(id(self)),))
      # If you get complaints above that self.conn exists, enable this stack
      # trace; it's usually the caller prior to the one that complains that
      # forgot to close().
      #log.warning(traceback.format_stack())
      #
      # NOTE: Psql says we need to START TRANSACTION or BEGIN before setting
      # the isolation level. [lb] guesses psycopg2 does this for us. In any
      # case, you should test: with ISOLATION_LEVEL_AUTOCOMMIT, do you see
      # rows committed by other threads? probably okay, since only scripts use
      # that to vacuum; usually, it's all read committed. so, e.g., using
      # Current() is okay when read-committed, because a commit of a new
      # revision won't be seen once the transaction starts.
      #
      if use_transaction:
         if not trans_serializable:
            # From psql docs, read committed means "a statement can only see
            # rows committed before it began. This is the default."
            self.conn.set_isolation_level(
               psycopg2.extensions.ISOLATION_LEVEL_READ_COMMITTED)
         else:
            # Serializable: "All statements of the current transaction can only
            # see rows committed before the first query or data-modification
            # statement was executed in this transaction." Used by the transit
            # graph. [lb] is not sure why it's necessary, since the transit
            # graph uses explicit revision IDs to fetch items.
            #
            # 2012.07.17: Serializable is no longer used in Cyclopath. It lets
            # you run two transactions in parallel, and if one of them commits,
            # then it fails if the other one also tries to commit. This is
            # silly! We know what our transactions are going to do (i.e., a
            # commit is going to write data, but a checkout is just going to
            # read data at a specific revision) so we should wait to start a
            # transaction rather than trying to recover from one that fails.
            g.assurt(False) # Don't use this anymore.
            #
            # The only difference is that serializeable causes an error after
            # the blocking thread unblocks once the blocker commits. If not
            # serializable, the blocking thread would successfully write and
            # never know the difference.
            #
            self.conn.set_isolation_level(
               psycopg2.extensions.ISOLATION_LEVEL_SERIALIZABLE)
      else:
         # Auto-commit is not a psql option but is supported by psycopg2.
         #
         # Auto-commit is generally not used -- it's akin to "tail"ing a
         # file: you see data as soon as it's committed. But we're usually
         # more deliberate: when we start using a database connection, we
         # usually don't want the contents of the database to change unless we
         # change them. At least this is how commit and checkout work. But for
         # some operations, this is useful. E.g., a lot of local scripts use
         # auto-commit when vacuuming.
         self.conn.set_isolation_level(
            psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
      self.curs = self.cursor()
      self.sql("SET SEARCH_PATH TO %s, public" % (conf.instance_name,))
      self.sql("SET TIME ZONE '%s'" % (conf.db_timezone,))

      # EXPLAIN: What does this mean?: That we have to call READ WRITE later if
      # we want to write? So isolation level is different...

# FIXME_2013_06_11: Confirm that removing SET SESSION is okay.

      # 2013.06.11: Landon T upgraded bad to Ubuntu 12.04 which uses
      #             Postgres 9.1 and until now Cyclopath has just run on
      #             Postgres 8.4 or older, and this SET SESSION causes
      #             a problem if you later try SET TRANSACTION READ WRITE,
      #             so Landon B wonders if we can't just not call SET SESSION.
      #    CDT ERROR:  transaction read-write mode must be set before any query
      #    CDT STATEMENT:  SET TRANSACTION READ WRITE
      #
      # Can we just not do this?
      #self.sql("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY")
      #
      # Commit because SET SESSION applies to future transactions only.
      # 2013.06.11: See previous comments. This simply recycles the
      #             cursor. But we no longer SET SESSION... so can we not
      #             do this, too, MAYBE?
      self.transaction_commit()

      self.dont_fetchall = False
      self.locked_tables = None
      self.locked_on_table = None
      self.locked_on_table_row = None
      self.locked_on_time0 = None
      self.integrity_errs_okay = False

      #log.debug('connect_and_setup: curs: %s / conn: %s / self: %s'
      #   % (hex(id(self.curs)), hex(id(self.conn)), hex(id(self)),))

   # ***

   #
   def dict_prep(self, dict_, skip_empties=False):
      '''Prepare the values in dict_ for storage.'''

      for key in dict_.keys():

         # Empty string becomes None
         if (dict_[key] == '') and (not skip_empties):
            dict_[key] = None

         # 2012.07.25: This CcpV1 hack is almost repaired: internally, and when
         # fetching from the database, geometry is either raw or WKT, but when
         # committing WKT to the database, we have to specify the SRID or else
         # a db constraint fails: srid(geometry) = cp_srid().
         if (((key == 'geometry') or (key[-3:] == '_xy'))
             and (dict_[key] is not None)):
            if dict_[key].startswith('SRID='):
               log.verbose('dict_prep: Thank You!: %s' % (key,))
            else:
               # Prepend the SRID... if this is WKT format.
               # NOTE: The SRID is encoded in the raw geometry (which is just a
               # hexadecimal string) but you can still prepend the srid, if you
               # want (Postgis actually ignores SRID=n, even if different from
               # what's in the raw geometry).
               # MAYBE: Prepending SRID to raw geometry seems like bad form.
               #        What if PostGIS decides that's no longer cool? Well,
               #        at least the SRID should always match...
               # Here's a nice hack: raw geometry is hex chars, and wkt txt is
               # of the form "GEOMETRY-TYPE((123.45 67.890))". So just look for
               # a parenthesis. Or dots and spaces.
               if '(' in dict_[key]:
                  # MAYBE: Put this in geometry.py? See also: db_glue.py and
                  #        geofeature.py.
                  dict_[key] = 'SRID=%s;%s' % (conf.default_srid, dict_[key],)
                  #
                  log.warning('dict_prep: obsolete usage: %s' % (key,))
               # else, this is a raw geometry whose spat ref is encoded within.

   #
   def get_row_iter(self):
      fetching = True
      while fetching:
         tup = self.curs.fetchone()
         if tup is not None:
            row = self.pack_result(self.curs.description, [tup,])[0]
            yield row
         else:
            fetching = False
      if self.curs.rowcount:
         try:
            # NOTE: I'm [lb] not sure this is necessary. I think if you call
            # get_row_iter again there's an implicit reset?
            self.curs.scroll(0, mode='absolute')
         except (psycopg2.ProgrammingError, IndexError), e:
            log.warning('get_row_iter: scroll error: %s' % (e,))

   #
   def pack_result(self, desc, result):
      '''Return the result set as a list of col_name => col_value dicts.'''
      fres = []
      #time_0 = time.time()
      for row in result:
         frow = {}
         for i in xrange(len(row)):
            frow[desc[i][0]] = row[i]
         fres.append(frow)
      #log.verbose('Packed %d rows in %s'
      #            % (len(fres),
      #               misc.time_format_elapsed(time_0),))
      return fres

   # ***

   #
   def transaction_add_lock(self, table, **kwargs):
      # Possible kwargs:
      #  debug_longer_wait
      #  mode
      #  nowait
      start = time.time()
      # This locking mode allows concurrent reads but prevents concurrent
      # writes (i.e., it's not really exclusive). Details:
      # http://postgresql.org/docs/8.4/interactive/explicit-locking.html
      # http://www.postgresql.org/docs/8.4/interactive/sql-lock.html
      #
      # I [rp] should add that I find the Postgres docs on this nearly
      # incomprehensible and struck out with Google too.
      #
      # NOTE: If one thread gets an exclusive lock and another thread gets
      # an access share lock, both can read from the table, and the exclusive
      # locker can write as often as it wants, but the access share locker
      # is allowed to write, too. So whoever is the first to write first gets
      # an implicit exclusive lock, i.e., if the access share locker writes to
      # the table, boom, it waits if the exclusive locker already writ,
      # otherwise it gets an implicit exclusive lock and then the thread with
      # the exclusive lock actually hangs once it tries writing for the first
      # time. But you can still edit other tables without conflicting... so
      # just use locking wisely, I guess....
      # NOTE: Two threads can create the same-named temporary table but
      # creating a non-temporary table with the same name does not work.
      #
      # 2013.09.30: No callers specify 'mode' or 'nowait'.
      try:
         mode = kwargs['mode']
      except KeyError:
         # Danger, will robinson?
         #mode='EXCLUSIVE'
         mode='SHARE ROW EXCLUSIVE'
      try:
         nowait = kwargs['nowait']
      except KeyError:
         # MAYBE: Default should be nowait and raise so we can cleanup the
         # code and improve our QOS.
         nowait = False
      self.transaction_add_lock_lock_table(table, mode, nowait)
      end = time.time()
      # 2011.07.13: Originally, if the lock took longer than two seconds to
      # acquire, a warning would be logged. But since releasing Multimodal,
      # there have been many more complaints from tilecache_update.py on
      # my [lb's] development machine, Huffy. So I'm making this value
      # configurable.
      # MAGIC NUMBER: Log msg. if lock takes longer than this to get.
      timeout_info = 0.5
      delta = end - start
      if (delta > timeout_info):
         try:
            longer_wait = kwargs['debug_longer_wait']
         except KeyError:
            longer_wait = False
         to_normal = conf.db_glue_acquire_timeout_normal
         to_longer = conf.db_glue_acquire_timeout_longer
         if ((longer_wait and (delta > to_longer))
             or (not longer_wait and (delta > to_normal))):
            log.warning('Waited %s for lock on %s'
                        % (misc.time_format_scaled(delta)[0], table,))
         else:
            log.info('Waited %s for lock on %s'
                     % (misc.time_format_scaled(delta)[0], table,))
      self.locked_tables.append(table)
      self.locked_on_table = table
      self.locked_on_time0 = time.time()

   #
   def transaction_add_lock_lock_table(self, table, mode, nowait=False):
      # LOCK TABLE is unique to Postgres. The SQL standard is to use
      # SET TRANSACTION. Which Postgres also supports.
      #    http://www.postgresql.org/docs/8.4/static/sql-set-transaction.html
      # 2013.09.30: No callers specify 'mode' or 'nowait'.
      # OTHERWISE: We'd want to maybe use SET STATEMENT_TIMEOUT and not NOWAIT.
      self.sql("LOCK TABLE %s IN %s MODE %s"
               % (table, mode, "NOWAIT" if nowait else ""))

   #
   def transaction_begin_rw(self, *tables_to_lock, **kwargs):
      '''Begin a read-write transaction; give as arguments the tables to lock.
         (Note that a read-only transaction is implicitly started immediately
         after the session opens and after each commit. If this method is
         called as the first action, it's converted to read-write. Calling
         this method after any SQL will fail.) You should also lock any tables
         that need to remain stable during the transaction. If you want to
         hold the wiki stable, lock table revision.'''
      g.assurt(self.locked_tables is None)
      self.locked_tables = []
      # HINT_HINT: If you're cxpxing and debugging at a prompt, don't forget:
      #self.sql("BEGIN TRANSACTION") # psycopg does this for us
      self.sql("SET TRANSACTION READ WRITE")
      self.sql("SET CONSTRAINTS ALL DEFERRED")
      tables_to_lock = sorted(tables_to_lock) # prevent deadlock
      #log.verbose('transaction_begin_rw: curs: %s / locking tables: %s'
      #            % (hex(id(self.curs)), tables_to_lock,))
      for table in tables_to_lock:
         self.transaction_add_lock(table, **kwargs)

   #
   def transaction_lock_try(
         self,
         table_to_lock,
         caller='',
         # Danger, will robinson?
         #mode='EXCLUSIVE',
         mode='SHARE ROW EXCLUSIVE',
         timeout=None,
         max_tries=None):

      if timeout is None:
         timeout = conf.gwis_default_timeout
      if max_tries is None:
         max_tries = 99

      g.assurt((timeout is None) or (timeout >= 0))
      g.assurt((max_tries is None) or (max_tries >= 0))
      tried_tries = 0

      # It's okay if transaction_begin_rw has been called but no tables were
      # locked; calling SET TRANSACTION and SET CONSTRAINTS again is okay.
      # Skipping: g.assurt(self.locked_tables is None)
      g.assurt(not self.locked_tables)

      # We'll try every second to get a lock on the table.
      # NOTE: TCP/IP uses a back-off heuristic to avoid perpetual competition
      # from denying all users access to a resource. I don't think we'll have a
      # problem here.
      time_0 = time.time()

      locked_table = False
      keep_trying = True

      while keep_trying and ((max_tries is None) or (max_tries > 0)):

         tried_tries += 1

         try:

            # psycopg2 BEGINs the transaction for us; here we set a few opts.
            self.sql("SET TRANSACTION READ WRITE")
            self.sql("SET CONSTRAINTS ALL DEFERRED")

            # NOTE: Not using NOWAIT, but statement_timeout instead.
            self.sql("SET STATEMENT_TIMEOUT TO %s" % (conf.psql_lock_timeout,))
            log.debug('transaction_lock_try: locking table: %s...'
                      % (table_to_lock,))
            self.sql("LOCK TABLE %s IN %s MODE" % (table_to_lock, mode,),
                     raise_on_canceled=True)
            #self.sql("SET STATEMENT_TIMEOUT TO 0")
            self.sql("RESET STATEMENT_TIMEOUT")
            log.debug('transaction_lock_try: locked table: %s'
                      % (table_to_lock,))

            keep_trying = False
            locked_table = True

         # NOTE: QueryCanceledError is a subclass of OperationalError,
         #       so it has to come first.
         except psycopg2.extensions.QueryCanceledError, e:

            self.transaction_rollback()
            log.debug('transaction_lock_try: timeout: cannot lock table: %s'
                        % (table_to_lock,))

         except psycopg2.OperationalError, e:

            # NOTE: If we close without rolling back and then get a new cursor,
            #       we'll get an error. So rollback the connection before
            #       closing the cursor.
            self.transaction_rollback()
            log.debug('transaction_lock_try: op-error: cannot lock table: %s'
                        % (table_to_lock,))

         finally:

            if keep_trying:

               if timeout is not None:
                  time_elapsed = time.time() - time_0
                  if time_elapsed > timeout:
                     log.debug('transaction_lock_try: giving up after %s'
                               % (misc.time_format_scaled(time_elapsed)[0],))
                     keep_trying = False
               elif max_tries is not None:
                  max_tries -= 1
                  if max_tries == 0:
                     log.debug('transaction_lock_try: giving up after %s tries'
                               % (tried_tries,))
                     keep_trying = False
               else:
                  # No timeout and no max_tries; only try once.
                  keep_trying = False

            # Sleep before trying again.
            if keep_trying:
               decent_sleep = 0.15 + random.random() * 0.15
               time.sleep(decent_sleep)

      if not locked_table:
         raise Exception('%s%sCannot lock table: %s'
                         % (caller, ': ' if caller else '', table_to_lock,))

      # MAYBE: locked_tables is no longer really used, as we only ever lock one
      # table (or one table's rows).
      self.locked_tables = [table_to_lock,]
      self.locked_on_table = table_to_lock
      self.locked_on_time0 = time.time()

      return locked_table # True if we're here, otherwise we raised.

   #
   def transaction_lock_row(self, table_to_lock, col_name, col_value,
                                  timeout=None, max_tries=None):
      g.assurt(self.locked_tables is None)
      row_logic = [(col_name, '=', col_value,),]
      (found_row, locked_table,
         ) = self.transaction_lock_row_logic(
               table_to_lock, row_logic, timeout, max_tries)
      return (found_row, locked_table,)

   #
   # CAVEAT: This fcn. really only works in the row being sought really exists.
   def transaction_lock_row_logic(self, table_to_lock,
                                        row_logic,
                                        timeout=None,
                                        max_tries=None,
                                        timeout_logger=None):

      g.assurt(self.locked_tables is None)

      if timeout is None:
         timeout = conf.gwis_default_timeout
      if max_tries is None:
         max_tries = 99

      if timeout:
         time_0 = time.time()

      if timeout_logger is None:
         timeout_logger = log.warning

      locked_rows = False
      keep_trying = True
      locked_table = False
      found_row = None

      g.assurt((timeout is None) or (timeout >= 0))
      g.assurt((max_tries is None) or (max_tries >= 0))
      tried_tries = 0

      select_clause = ", ".join(["%s" % x[0] for x in row_logic])

      where_clause = " AND ".join(["(%s %s %s)" % (x[0], x[1], x[2],)
                              for x in row_logic if (x[1] and x[2])])

      while keep_trying and ((max_tries is None) or (max_tries > 0)):

         tried_tries += 1

         # 2014.09.08: [lb] seeing:
         #   trans_lock_row_logic: Unexpected: Ccp_Shutdown deteted
         last_sql = None

         try:

            log.debug('_lock_row_logic: locking %s...' % (table_to_lock,))

            # psycopg2 BEGINs the transaction for us; here we set a few opts.
            last_sql = "SET TRANSACTION READ WRITE"
            self.sql(last_sql)
            last_sql = "SET CONSTRAINTS ALL DEFERRED"
            self.sql(last_sql)

            # [lb] finds that NOWAIT fails repeatedly when the server is busy,
            # so maybe we shouldn't NOWAIT, otherwise our lock request doesn't
            # get queued. Or so I'm guessing. But when I run the daily.runic.sh
            # script, all the NOWAIT locking selects fail. Fortunately, we can
            # set the statement_timeout so that we wait for a little bit. But
            # we're usually called while processing an HTTP request, so don't
            # wait too long.
            last_sql = ("SET STATEMENT_TIMEOUT TO %s"
                        % (conf.psql_lock_timeout,))
            self.sql(last_sql)

            # [lb] first coded this fcn. to lock table IN ROW EXCLUSIVE MODE,
            # but we really just need the ROW SHARE lock, which SELECT FOR
            # UPDATE will acquire.

            # Start by just looking to see if the row exists, so if we cannot
            # get the lock, at least we can tell the caller if the row at least
            # exists. E.g., the user__token code will just skip the row update
            # if it can't get the lock.
            #
            # Note: SELECT just acquires the ACCESS SHARE lock, which only
            #       conflicts with ACCESS EXCLUSIVE.

            # SYNC_ME: ccpdev...logcheck/pyserver...sql().
            master_sql = ("SELECT %s FROM %s WHERE %s"
                          % (select_clause, table_to_lock, where_clause,))

            if found_row is None:

               last_sql = master_sql
               selected_rows = self.sql(last_sql, raise_on_canceled=True)

               if selected_rows:
                  g.assurt(len(selected_rows) == 1)
                  found_row = selected_rows[0]
               else:
                  log.verbose('trans_lock_row_logic: nothing found: %s'
                              % (last_sql,))
                  # MAYBE: We don't need to rollback/recycle, do we? The db
                  #        should be ready for, e.g., transaction_begin_rw.
                  #           self.curs_recycle()
                  found_row = False

            if found_row:

               # Select the rows that the caller wants locked.
               # NOPE: locked_sql = "%s FOR UPDATE NOWAIT" % (master_sql,)
               locked_sql = "%s FOR UPDATE" % (master_sql,)
               #
               # NOTE: SELECT FOR UPDATE will acquire ROW SHARE lock. ROW SHARE
               #       blocks other threads from SELECT FOR UPDATE on the same
               #       row, as well as UPDATE and DELETE of the row.

               # If NOWAIT is not used, if statement_timeout fires, sql()
               # raises QueryCanceledError; otherwise, if using NOWAIT, sql()
               # raises OperationalError if it cannot lock the rows. If not
               # using NOWAIT, an empty result set means no matching rows were
               # found.
               last_sql = locked_sql
               locked_rows = self.sql(last_sql, raise_on_canceled=True)
               # The sql() raises OperationalError on statement_timeout,
               # and found_row is not None, so we'll loop back around and
               # try again, unless it's time to give up.

               log.verbose('trans_lock_row_logic: locked %d row(s): %s: %s'
                           % (len(locked_rows), table_to_lock, where_clause,))

               if locked_rows:
                  g.assurt(len(locked_rows) == 1)
                  locked_table = True
               else:
                  g.assurt_soft(False) # We already SELECTed, so this path
                                       # shouldn't be possible.

            keep_trying = False

            #last_sql = "SET STATEMENT_TIMEOUT TO 0"
            last_sql = "RESET STATEMENT_TIMEOUT"
            self.sql(last_sql)

            if not locked_table:
               self.conn.rollback()
               self.curs_close()
               self.curs_recycle()
            # else, we locked the table-row, so don't rollback or otherwise
            #       recycle the cursor.

         # NOTE: QueryCanceledError is a subclass of OperationalError,
         #       so it has to come first.
         except psycopg2.extensions.QueryCanceledError, e:

            # ERROR:  canceling statement due to statement timeout

            self.conn.rollback()
            self.curs_close()

            log.debug('trans_lock_row_logic: could not lock (qc-e): table: %s'
                      % (table_to_lock,))
            log.debug(' .. where_clause: %s' % (where_clause,))

         except psycopg2.OperationalError, e:
         # ?? : except psycopg2.extensions.TransactionRollbackError, e:

            # We know the row exists, it's just that we couldn't lock it.

            g.assurt_soft(found_row)

            self.conn.rollback()
            self.curs_close()

            err_s = 'could not obtain lock on row in relation "user__token"'
            if not str(e).startswith(err_s):
               log.error('Unexpected OperationalError: %s' % (str(e),))
            #
            log.debug('trans_lock_row_logic: could not lock (op-e): table: %s'
                      % (table_to_lock,))
            log.debug(' .. where_clause: %s' % (where_clause,))

         except g.Ccp_Shutdown, e:

            # 2014.09.08: [lb] added more output to diagnose periodic issue
            # timing out on user__token something or other and then
            # GWIS_Erroring to the user to Please try your request again
            # (Token server too busy).
            log.error('trans_lock_row_logic: Unexpected: Ccp_Shutdown deteted')
            log.error('trans_lock_row_logic: last_sql: %s' % (last_sql,))
            stack_lines = traceback.format_stack()
            stack_trace = '\r'.join(stack_lines)
            log.warning('Error detected:\r%s' % (stack_trace,))

            self.conn.rollback()
            self.curs_close()

            raise

         except psycopg2.DataError, e:

            # Happens if input is malformed.

            self.conn.rollback()
            self.curs_close()

            raise

         except Exception, e:

            log.error('trans_lock_row_logic: unknown error: %s' % (str(e),))

            self.conn.rollback()
            self.curs_close()

            raise

         finally:

            if keep_trying:

               if timeout is not None:
                  time_elapsed = time.time() - time_0
                  if time_elapsed > timeout:
                     timeout_logger(
                        'trans_lock_row_logic: giving up after %s'
                        % (misc.time_format_scaled(time_elapsed)[0],))
                     keep_trying = False
               elif max_tries is not None:
                  max_tries -= 1
                  if max_tries == 0:
                     timeout_logger(
                        'trans_lock_row_logic: giving up after %s tries'
                        % (tried_tries,))
                     keep_trying = False
               else:
                  # No timeout and no max_tries; only try once.
                  timeout_logger(
                     'trans_lock_row_logic: giving up after one attempt')
                  keep_trying = False

               # Sleep before trying again.
               if keep_trying:
                  #time.sleep(1) # Sleep One Second
                  # MAGIC_NUMBER: Sleep one tenth to one twentieth of a second.
                  decent_sleep = 0.15 + random.random() * 0.15
                  time.sleep(decent_sleep)

               # User started with valid db, so always end with one, or create
               # a valid db for the next try.
               self.curs_recycle()

            # else, not keep_trying, so either locked_table or found_row False.

         # end: finally

      # end: while

      if found_row and locked_table:
         self.locked_tables = [table_to_lock,]
         self.locked_on_table_row = table_to_lock
         self.locked_on_time0 = time.time()

      log.debug('trans_lock_row_logic: found_row: %s / locked_table: %s'
                % (found_row, locked_table,))

      return (found_row, locked_table,)

   #
   def transaction_commit(self):

      g.assurt(self.curs is not None)

      try:
         if len(DB.conn_lookup[id(self.conn)]) > 1:
            err_msg = (
                  '%s curs: %s / conn: %s / cursors_open: %s'
               % ('Cannot commit when multiple cursors open (commit):',
                  hex(id(self.curs)), hex(id(self.conn)), DB.cursors_open,))
            log.error(err_msg)
            raise Exception(err_msg)
      except KeyError:
         log.error('conn_decrement: missing: conn: %s'
                   % (hex(id(self.conn)),))
         if conf.db_glue_strict_assurts:
            g.assurt(False)

      try:
         self.conn.commit()
      except psycopg2.Error, e:
         log.error('commit: error: %s (%s)' % (e.pgerror, e.pgcode,))
         raise
      except psycopg2.Warning, e:
         log.error('commit: warning: %s' % (str(e),))
         raise

      self.curs_recycle()

   #
   def transaction_finish(self, do_commit):
      time_0 = time.time()
      #
      if do_commit:
         log.debug('Committing to the database...')
         self.transaction_commit()
      else:
         log.debug('Rolling back the database. %s' % self)
         self.transaction_rollback()
      #
      log.debug('... %s took %s'
         % ('Commit' if do_commit else 'Rollback',
            misc.time_format_elapsed(time_0),))

   #
   def transaction_in_progress(self):
      return (self.locked_tables is not None)

   #
   def transaction_retryable(self, processing_fcn, req_or_qb, *args, **kwargs):

      # Bugs 2686 and 2688:
      #    DatabaseError: {<cursor object at 0x7fd830156e00>:
      #    'ERROR:  could not serialize access due to concurrent update
      #     CONTEXT:  SQL statement
      #                 "SELECT 1 FROM ONLY "public"."user_" x
      #                  WHERE "username" = $1 FOR SHARE OF x"\n'}
      # If we get this, we just have to start the transaction over....

      success = False

      # FIXME: What's a reasonable number of times to retry?
      #        Should we sleep between tries?
      # 2013.07.10: Let's try thrice with some sleep betwixt.
      #max_tries = 5
      #max_tries = 3
      max_tries = 15
      n_attempts = 0

      # Our self is req_or_qb.db for the first attempt, but if we have to
      # retry, we make a new connection.
      assert(id(req_or_qb.db) == id(self))

      while (not success) and (max_tries > 0):
         n_attempts += 1
         try:
            error_e = None
            # If retrying, we made a new db connection, so don't use self.
            # Wrong: processing_fcn(self)
            processing_fcn(req_or_qb.db, *args, **kwargs)
            success = True
         # NOTE: In psycopg2, we catch TransactionRollbackError, of
         # type OperationalError. In psycopg, it's ProgrammingError.
         except psycopg2.extensions.TransactionRollbackError, e:
            error_e = e
         # This is in CcpV1 but shouldn't be needed:
         #   except psycopg2.Error, e:
         #      error_e = e
         # MAYBE: Catch Warning?
         #   except psycopg2.Warning, e:
         #      error_e = e
         #      log.warning('Unexpected psycopg.Warning: %s' % (str(e),))
         finally:
            if error_e is not None:
               # See if we can retry the transaction.
               try:
# FIXME: Is this message the same for psycopg2?
#        ERROR:  could not serialize access due to concurrent update\n
                  if error_e.message.startswith(DB.concurrency_prefix):
                     log.warning('_retryable: concurrency error; retry maybe.')
                     max_tries -= 1
                     # MAYBE: Is it excessive that we're rebuilding the
                     #        database connection and not just getting
                     #        a new cursor? By calling new(), we make
                     #        a new TCP connection to the database
                     #        service. See transaction_lock_row_logic,
                     #        which justs closes the cursor, sleeps,
                     #        and then gets a new cursor.
                     req_or_qb.db.close()
                     if max_tries > 0:
                        # MAGIC_NUMBER: Sleep 1/20thish of a second.
                        #decent_sleep = 0.05
                        decent_sleep = 0.05 + random.random() * 0.05
                        time.sleep(decent_sleep)
                        req_or_qb.db = new()
                  # NOTE: After last try, req_or_qb.db is closed.
                  else:
                     log.error('_retryable: programming error: %s'
                               % (str(error_e),))
                     # NOTE: 'raise error_e' same as simply 'raise'.
                     raise error_e
               except AttributeError:
                  # EXPLAIN: Does this happen w/ psycopg2, or just the g1?
                  # 2012.11.07: WTF, psycopg? Some psycopg exception's message
                  #             is really a dict...?
                  log.error('_retryable: %s (type: %s) / max_tries: %d / %s:%s'
                            % (str(error_e.message), type(error_e.message),
                               max_tries, str(error_e), type(error_e),))
                  max_tries -= 1

      if not success:
         log.error('_retryable: too many errors; bailed!')
      elif n_attempts > 1:
         log.warning('_retryable: saved after %d attempts.' % (n_attempts,))

      return success

   #
   def transaction_rollback(self):
      self.locked_tables = None
      try:
         if not self.conn.closed:
            if len(DB.conn_lookup[id(self.conn)]) > 1:
               err_msg = (
                     '%s curs: %s / conn: %s / cursors_open: %s'
                  % ('Cannot commit when multiple cursors open (rollback):',
                     hex(id(getattr(self, 'curs', -1))),
                     hex(id(getattr(self, 'conn', -1))),
                     DB.cursors_open,))
               log.error(err_msg)
               raise Exception(err_msg)
            self.conn.rollback()
            self.curs_recycle()
            complain = False
         else:
            complain = True
      except AttributeError, e:
         # self.conn isn't set.
         complain = True
      if complain:
         log.error('transaction_rollback: connection is closed/never existed')
         if conf.db_glue_strict_assurts:
            g.assurt(False)

   # ***

   #
   def delete(self, table, id_cols):
      self.sql(
         """
         DELETE FROM
            %s
         WHERE
            %s
         """ % (table,
                " AND ".join(map(lambda x: '%s = %%(%s)s' % (x, x,),
                                 id_cols.keys()))),
         id_cols)

   #
   def insert(self, table, id_cols, nonid_cols, skip_empties=False):
      # ID columns with value None are assumed to have a useful default
      # value specified in the database, so don't mention them.
      #
      # all_cols has the values of the columns we're updating, including nones
      all_cols = dict()
      all_cols.update(id_cols)
      all_cols.update(nonid_cols)
      # Convert empty strings to None and maybe prepend geometry cols w/ SRID=.
      self.dict_prep(all_cols, skip_empties)
      # insert_cols has the names of the columns, and we exclude columns for
      # which we don't have non-null values
      insert_cols = dict()
      # The non_ids columns can be null, so include all of 'em
      insert_cols.update(nonid_cols)
      # For id_cols, only include values that are not null;
      # if a value is null, the database will assign a default
      for key, value in id_cols.items():
         if value is not None:
            insert_cols[key] = value
      # Make the SQL query, and use Python's nifty %(string-name-hook)s
      # to ignore null values in all_cols
      sql = "INSERT INTO %s (%s) VALUES (%s)" \
            % (table,
               ", ".join(insert_cols.keys()),
               ", ".join(map(lambda x: '%%(%s)s' % x,
                             insert_cols.keys())))
      self.sql(sql, all_cols)

   #
   def insert_clobber(self, table, id_cols, nonid_cols):
      '''
      Like insert(), but clobber any existing row with matching PK. Data
      from any existing row is NOT merged with the new data.
      '''
      self.delete(table, id_cols)
      self.insert(table, id_cols, nonid_cols)

   #
   def insert_and_lock_row(self, table, key_name, key_value):
      '''
      A simple fcn. to lock the row of a database table. The row is created if
      it doesn't exist. We'll commit and recycle the cursor, so that we don't
      block other threads that are also trying to insert -- by committing, we
      unblock the other threads, which get an error, and then all threads try
      again for the lock.
      '''

      if isinstance(key_value, basestring):
         key_value = self.quoted(key_value)

      # NOTE: Not using NOWAIT.
      select_sql = ("SELECT %s FROM %s WHERE %s = %s FOR UPDATE"
                    % (key_name, table, key_name, key_value,))

      insert_sql = ("INSERT INTO %s (%s) VALUES (%s)"
                     % (table, key_name, key_value,))

      integrity_errs_okay = self.integrity_errs_okay
      self.integrity_errs_okay = True

      n_tries = 0
      while n_tries < 2:
         #g.assurt(self.locked_tables is None)
         if self.locked_tables is None:
            self.sql("SET TRANSACTION READ WRITE")
            self.sql("SET CONSTRAINTS ALL DEFERRED")
         # else, we either locked already, or a basic transaction_begin_rw was
         # called and we started the transaction and set locked_tables to [].
         # The NOWAIT option seems delicate: if the server is busy, even if the
         # row isn't locked, trying to lock with NOWAIT can repeatedly fail.
         self.sql("SET STATEMENT_TIMEOUT TO %s" % (conf.psql_lock_timeout,))
         try:
            # NOTE: Not using NOWAIT.
            # MAYBE: SHARE ROW EXCLUSIVE?
            self.sql("LOCK TABLE %s IN ROW EXCLUSIVE MODE" % (table,),
                     raise_on_canceled=True)
            try:
               rows = self.sql(select_sql, raise_on_canceled=True)
               g.assurt(len(rows) <= 1)
               if not rows:
                  # The row doesn't exist.
                  g.assurt(n_tries == 0)
                  try:
                     rows = self.sql(insert_sql)
                     #self.sql("SET STATEMENT_TIMEOUT TO 0")
                     self.sql("RESET STATEMENT_TIMEOUT")
                     # Success! Commit and get a new cursor. If we don't
                     # commit, any competing threads will continue to wait
                     # until we finally do commit. So don't keep them waiting,
                     # which could be hours (e.g., tilecache_update.py); by
                     # waking them up, they'll see their insert failed and now
                     # we can all race for the row lock on the new row.
                     self.transaction_commit()
                     # Note that our commit calls curs_recycle, so we're good.
                  except psycopg2.IntegrityError, e:
                     # This is the duplicate key warning, meaning we were
                     # racing against another thread but lost. We can recycle
                     # the cursor and try again.
                     self.transaction_rollback()
                     # MAYBE: Do we need to sleep here?
                     #        This fcn. is only called by tilecache_update.
               else:
                  # We got a response, so we got the lock!
                  #self.sql("SET STATEMENT_TIMEOUT TO 0")
                  self.sql("RESET STATEMENT_TIMEOUT")
                  break
            # NOTE: QueryCanceledError is a subclass of OperationalError,
            #       so it has to come first.
            except psycopg2.extensions.QueryCanceledError, e:
               # The STATEMENT_TIMEOUT fired.
               log.debug('insert_and_lock_row: timedout: %s' % (str(e),))
               # Wrong: self.transaction_rollback()
               pass # Don't raise; keep trying.
            except psycopg2.OperationalError, e:
               # The row is already locked.
               self.transaction_rollback()
               raise
         # NOTE: QueryCanceledError is a subclass of OperationalError,
         #       so it has to come first.
         except psycopg2.extensions.QueryCanceledError, e:
            # The STATEMENT_TIMEOUT fired.
            # 2013.09.30: [lb] can't think of any tables where some code gets a
            # table lock but other code only wants a row lock, so this case is
            # unanticipated.
            log.error('insert_and_lock_row: someone has table lock: %s'
                      % (str(e),))
            self.transaction_rollback()
            raise
         except psycopg2.OperationalError, e:
            log.error('insert_and_lock_row: unexpected failure: %s'
                      % (str(e),))
            self.transaction_rollback()
            raise
         except g.Ccp_Shutdown, e:
            log.error('insert_and_lock_row: Unexpected: Ccp_Shutdown deteted')
            raise
         n_tries += 1
      # We actually don't need n_tries, because our logic means we'll raise or
      # break before we try a third time through the loop.
      g.assurt(n_tries < 2)

      self.integrity_errs_okay = integrity_errs_okay

   #
   def sql(self,
           sql,
           parms=None,
           prog_err_ok=False,
           assurt_on_integrity_err=True,
           force_fetchall=False,
           raise_on_canceled=False):

      # Rather then call log.debug(sql), I [lb] generally have postgresql log
      # it. E.g., edit postgresql.conf,
      #    log_statement = 'all' # none, ddl, mod, all

      # Start the query timer
      time_0 = time.time()

      # Pass the request to psycopg via the connection cursor
      # NOTE All SQL variables should be passed in parms. That is, don't
      #      use string interpolation (%) to build the SQL query, but let
      #      psycopg do it for you. This ensures that Python variables are
      #      converted to the appropriate SQL data type. In addition,
      #      (1) use %s or %%(key_name)s in the sql string,
      #          and only ever use %s, not %d or anything; and
      #      (2) make parms a (tuple,) even if it's just one element.
      #      See the following for more info:
      #
      #         http://initd.org/psycopg/docs/usage.html#query-parameters
      #
      # FIXME: The last comment's recommendation is not enforced. There are
      #        many calls to sql() where the caller has done the interpolation.
      #log.debug('sql: %s' % (sql,))
      #log.debug('parms: %s' % (parms,))

      try:
         unexceptional = False
         self.curs.execute(sql, parms)
      #
      # except:
      #   We catch all psycopg2 exceptions. Here's the inheritance layout:
      #
      #     StandardError
      #     |__ Warning
      #     |__ Error
      #         |__ InterfaceError
      #         |__ DatabaseError
      #             |__ DataError
      #             |__ OperationalError
      #             |   |__ psycopg2.extensions.QueryCanceledError
      #             |   |__ psycopg2.extensions.TransactionRollbackError
      #             |__ IntegrityError
      #             |__ InternalError
      #             |__ ProgrammingError
      #             |__ NotSupportedError
      #
      # Start with the leafiest classes, dervied from OperationalError.
      except psycopg2.extensions.QueryCanceledError, e:
         # I.e., 'canceling statement due to user request\n'
         # This tends to happen when the server is very busy.
         # You can fiddle with postgres's statement timeout, or
         # you can just try the sql again (and again and again).
         if raise_on_canceled:
            logger_f = log.info
         else:
            # If caller sets raise_on_canceled, we can assume they'll
            # handle it, but it's not set, log a warning for the DEVs
            # to see.
            logger_f = log.warning
         logger_f('sql: query canceled: raise_on_canceled: %s'
                  % (raise_on_canceled,))
         logger_f('sql: query canceled: %s' % (sql,))
         logger_f('sql: query canceled: %s' % (str(e),))
         unexceptional = True
         if raise_on_canceled:
            raise
         else:
            raise g.Ccp_Shutdown()
      except psycopg2.extensions.TransactionRollbackError, e:
         # Bug 2688: 'could not serialize access due to concurrent update'.
         # We don't just want to fail; we want to try to redo the transaction.
         # See transaction_retryable.
         # FIXME: Do we re-raise and expect the caller to handle concurrency
         # errors? Or should we check the message, too?
         log.warning('sql: trans. rollback: %s (%s)' % (e.pgerror, e.pgcode,))
         unexceptional = True
         raise
      #
      # Catch all errors derived from DatabaseError.
      except psycopg2.DataError, e:
         log.warning('sql: DataError: %s (%s) / %s'
                     % (e.pgerror, e.pgcode, sql % (parms or {}),))
         raise
      except psycopg2.OperationalError, e:
         # Log the message, but don't log the keyword 'ERROR' or our cron
         # script double-checker, check_prev_cmd_for_error, may complain.
         # The pgerror may be, e.g., 'ERROR:  could not obtain lock on
         # relation "revision"' and, pgcode is '(55P03)'.
         log.debug('sql: operational: %s (e.pgcode: %s)'
            % (str(e.pgerror).replace('ERROR', 'ER*OR')
                              .replace('\n', ''),
               e.pgcode,))
         # This happens when locking is NOWAIT and being denied. We'll still
         # raise (so we know the caller has to deal with it) but mark
         # unexceptional so we don't assurt in the finally.
         #
         # 2013.08.20: On itamae, the CcpV1 production server, [lb] is seeing
         # OperationalError when it's just DB.concurrency_prefix. Since we're
         # already treating this exception as unexceptional, I assume CcpV2 is
         # safe. Indeed, our fcn., transaction_retryable, doesn't care what
         # error raises; it tests e.message.startswith(DB.concurrency_prefix).
         #
         unexceptional = True
         raise
      except psycopg2.IntegrityError, e:
         if self.integrity_errs_okay:
            logger = log.debug
         else:
            logger = log.error
         logger('sql: integrity: %s (%s) / %s'
                % (e.pgerror, e.pgcode, sql % (parms or {}),))
         # Call assurt so devs can catch the failure on the py prompt.
         if not self.integrity_errs_okay:
            g.assurt(False)
         else:
            unexceptional = True
         # Always raise.
         raise
      except psycopg2.InternalError, e:
         log.error('sql: internal: %s (%s) / %s'
                   % (e.pgerror, e.pgcode, sql % (parms or {}),))
         raise
      except psycopg2.ProgrammingError, e:
         log.error('sql: programming: %s (%s) / %s'
                   % (e.pgerror, e.pgcode, sql % (parms or {}),))
         if not prog_err_ok:
            raise
         else:
            # FIXME: This path shouldn't be accessible on production machine?
            log.warning('Ignoring psycopg2.ProgrammingError!')
            # NOTE: We'll still assurt in finally if dev turned on
            #       db_glue_strict_assurts.
      except psycopg2.NotSupportedError, e:
         log.error('sql: interface error: %s (%s)' % (e.pgerror, e.pgcode,))
         raise
      #
      # Exceptions derived from psycopg2.Error
      except psycopg2.InterfaceError, e:
         log.error('sql: interface error: %s (%s)' % (e.pgerror, e.pgcode,))
         raise
      except psycopg2.DatabaseError, e:
         # Since we catch DatabaseError-derived errors before this, this code
         # should be unreachable.
         log.error('sql: database error: %s (%s)' % (e.pgerror, e.pgcode,))
         raise
      #
      # psycopg2's two top-level exception base classes.
      except psycopg2.Error, e:
         # Subclass of Python's StandardError. This is a catch-all for all
         # psycopg2 exception, but we can them all specifically above, so this
         # block should be unreachable.
         log.error('SQL error: %s (%s)' % (e.pgerror, e.pgcode,))
         raise
      except psycopg2.Warning, e:
         # Subclass of Python's StandardError.
         # 2012.06.11: [lb] has never seen this code execute.
         log.error('SQL warned: %s' % (str(e),))
         raise
      #
      # Python exception handler.
      except Exception, e:
         # This case probably won't happen, since we catch all psycopg2.Errors.
         log.error('Unknown SQL failure: %s: %s'
                   % (str(e), sql % (parms or {}),))
         raise
      #
      else:
         unexceptional = True
      finally:
         # All exceptional exceptions are programming errors. All other
         # exceptions that psycopg2 might throw we've gracefully handled.
         if not unexceptional:
            ##stack_trace = traceback.format_exc()
            ##log.warning(stack_trace)
            #log.warning(traceback.format_stack())
            stack_lines = traceback.format_stack()
            stack_trace = '\r'.join(stack_lines)
            log.warning('Error detected:\r%s' % (stack_trace,))
            # Call assurt so devs can catch the failure on the py prompt.
            if conf.db_glue_strict_assurts and not prog_err_ok:
               g.assurt(False)

      # FIXME: Use a lookup to store sql that takes a while and group by
      # relative lengths of time.
      delta = time_0 - time.time()
      if delta > conf.db_glue_sql_time_limit:
         log.warning('Long query: SQL took %s: %s'
                     % (misc.time_format_scaled(delta)[0],
                        sql % (parms or {}),))

      if self.curs.description is None:
         rows = None
      else:
         # Don't call fetchall for Very Large Queries. Even though Python has
         # a garbage collector, its memory allocator never returns pages to the
         # OS. That is, if you make a big list that takes 100 MB, you can
         # gc.collect() and reclaim those 100 MB for your Python process, but
         # the OS won't reclaim the 100 MB until your process exits. One
         # approach is to use fetchone() or fetchmany() instead of fetchall().
         # Another approach to use a pipe and fork and to do the heavy lifting
         # in the child process which pipes the results and then exits. Note
         # that I [lb] tested this on a fetch of 500,000 records and saw no
         # performance difference between using fetchall and fetchone to fetch
         # rows and make items.
         #
         # See also a good article on how the Python memory allocator behaves,
         #
         #   http://www.evanjones.ca/memoryallocator/

         # NOTE: The reason self.dont_fetchall defaults to False is because
         # that's the original behavior. Maybe if we clean up all sql() calls
         # we could switch the default behavior (but there are a lot of sql()
         # calls!). For now, we complain if we fetchall lots of rows, so
         # developers can just focus on sql() calls that matter. (And, really,
         # most calls to db.sql() are for just a few rows, and there are
         # hundreds of calls, so auditing the code and changing to a fetchone()
         # design is probably a bad idea.)

         if force_fetchall or not self.dont_fetchall:
            # MAGIC NUMBER: 1000 is the threshold for complaining. It might
            # even make sense to make it 10,000, but I'm curious how often
            # this'll get tickled. I assume most queries return a handful of
            # results, hundreds of results, or tens of thousands of results.
            # 2013.09.23: On runic, 13831 rows takes but a millisecond.
            #if self.curs.rowcount > 1000:
            if self.curs.rowcount > 100000:
               log.warning('sql: hydrating %d rows. Consider using fetch_row.'
                           % (self.curs.rowcount,))
            rows = self.pack_result(self.curs.description,
                                    self.curs.fetchall())
         else:
            rows = None

      return rows

   #
   def table_columns(self, tablename):
      'Return the column names of the given table as a set of strings.'
      rows = self.sql(
         """
         SELECT attname FROM pg_attribute
         WHERE
            attnum > 0
            AND NOT attisdropped
            AND attrelid = (SELECT oid
                            FROM pg_class
                            WHERE relname = '%s' LIMIT 1)
         """ % (tablename))
      # LIMIT 1 because there may be multiple tables with the same name in
      # different schemas.  The table definitions are all the same though so
      # it doesn't matter which one we get.
      return set([row['attname'] for row in rows])

   #
   def table_drop_constraint_safe(self, table_name, constraint_name):
      # If the constraint does not exist, the db connection becomes invalid.
      # I [lb] can't find a way to
      #try:
         # FIXME: The interpolation here produces, e.g.,
         # Feb-13 13:39:37  ERRR     util_.db_glue  #  Unknown SQL failure:
         #                             syntax error at or near "E'node_endpoint'"
         # LINE 1: ALTER TABLE E'node_endpoint' DROP CONSTRAINT E'node_endpoint_syste
         #self.sql("ALTER TABLE %s DROP CONSTRAINT %s",
         #         (table_name, constraint_name,))
         #
         # Ug. this leaves the db connection broken until rollback.
         #self.sql("ALTER TABLE %s DROP CONSTRAINT %s"
         #         % (table_name, constraint_name,),
         #         parms=None, prog_err_ok=True)
         #
      self.sql("SELECT cp_constraint_drop_safe('%s', '%s')"
               % (table_name, constraint_name,))
      #except psycopg2.ProgrammingError, e:
      #   pass

   #
   def table_to_dict(self, tablename, key_name, value_name, *key_names):
      table_vals = {}
      for kval_key in key_names:
         table_vals[kval_key] = None
      sql_kval_keys = ','.join([self.quoted(x) for x in key_names])
      sql_kval_vals = (
         "SELECT %s, %s FROM %s WHERE %s IN (%s)"
         % (key_name, value_name, tablename, key_name, sql_kval_keys,))
      rows = self.sql(sql_kval_vals)
      for row in rows:
         table_vals[row['key']] = row['value']
      return table_vals

   #
   def table_to_dom(self, tablename, sql=None):
      te = etree.Element(tablename)
      if sql is None:
         sql = "SELECT * FROM %s" % (tablename,)
      # This fcn. accepts the dont_fetchall flag, but it also processes the
      # results immediately, because we want to return XML from this fcn.
      # (whereas db.sql() returns None if dont_fetchall and lets the client
      # process the results).
      result = self.sql(sql)
      if result is not None:
         for row in result:
            el = etree.Element('row')
            for (col, value) in row.items():
               misc.xa_set(el, col, value)
            te.append(el)
      else:
         generator = self.get_row_iter()
         for row in generator:
            el = etree.Element('row')
            for (col, value) in row.items():
               misc.xa_set(el, col, value)
            te.append(el)
         generator.close()
      # But now that we've consumed the results and expect the caller to
      # consume the returned XML, don't confuse anyone into thinking the
      # cursor can be iterated.
      log.verbose('table_to_dom: disabling dont_fetchall')
      self.dont_fetchall = False
      return te

   #
   def table_exists(self, table_name, use_public_schema=False):
      # NOTE: This is postgres-specific.
      if use_public_schema:
         schema_name = 'public'
      else:
         schema_name = conf.instance_name
      sql = (
         """
         SELECT
            COUNT(*) AS count
         FROM
            pg_tables
         WHERE
            tablename='%s'
            AND schemaname='%s'
         """ % (table_name,
                schema_name,))
      rows = self.sql(sql)
      g.assurt(len(rows) == 1)
      if rows[0]['count'] == 1:
         exists = True
      else:
         g.assurt(rows[0]['count'] == 0)
         exists = False
      return exists

   # ***

# ***

