# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import cPickle
import psycopg2
import socket

from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import item_helper
from item import nonwiki_item
#from item.jobsq.job_base import Callback_Def_Base
from item.util import item_query_builder
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('work_item_step')

class One(item_helper.One):

   PICKLE_PROTOCOL_ASCII = 0
   PICKLE_PROTOCOL_BINARY = cPickle.HIGHEST_PROTOCOL

   # Base class overrides

   item_type_id = Item_Type.WORK_ITEM_STEP
   item_type_table = 'work_item_step'
   item_gwis_abbrev = 'wkst'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('work_item',           None,  False,   None),
      ('work_item_id',        None,  False,   True),
      ('step_number',         None,  False,  False),
      ('last_modified',       None,  False,  False),
      ('epoch_modified',      None,   True,   None),
      ('stage_num',           None,   True,  False),
      ('stage_name',          None,   True,  False),
      ('stage_progress',      None,   True,  False),
      ('status_code',         None,   True,  False),
      ('status_text',         None,   True,  False),
      ('cancellable',        False,   True,  False),
      # The callback_def is a Python object (usually a dict) that is hydrated
      # from callback_dat/_raw.
      ('callback_dat',        None,  False,  False),
      ('callback_raw',        None,  False,  False),
      # These are callback_def values we send to the client. callback_def
      # values are values that don't need to be their own database column,
      # meaning we can edit these without having to alter table.
      ('suspendable',         None,   True,   None),
      #('failure_reason',      None,   True,   None),
      #('indepth_reason',      None,   True,   None),
      #('err_s',               None,   True,   None),
      ]
   attr_defns = item_helper.One.attr_defns + local_defns
   psql_defns = item_helper.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   # FIXME: these defaults are just like those in local_defns... violates DRY!
   _callback_def_cols = [
      ('suspendable',         None,),
      #('failure_reason',      None,),
      #('indepth_reason',      None,),
      #('err_s',               None,),
      ]
   callback_def_cols = _callback_def_cols

   __slots__ = [
      'callback_def',
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, wtem=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      if row is not None:
         row.setdefault('step_number', 1)
      item_helper.One.__init__(self, qb, row, req, copy_from)
      g.assurt(wtem is not None)
      self.work_item = wtem
      g.assurt(req is None) # Not supported
      self.callback_def = None
      self.callback_data_prepare()
      if row is not None:
         self.callback_data_unpack()

   # 
   def __str__(self):
      return (
         'Work Item Step / %s.%s / last: %s / stage:%s-%s-%s%%-stat:%s-%s-%s%s'
         % (self.work_item_id, self.step_number, self.last_modified,
            self.stage_num, self.stage_name, self.stage_progress, 
            self.status_code, self.status_text, 
            'C' if self.cancellable else 'c',
            'S' if self.suspendable else 's',))

   # 
   def __str_verbose__(self):
      return ('%s / cb_def: %s' % (self.__str__(), self.callback_def,))

   #
   def from_gml(self, qb, elem):
      # Derived classes should override this and set job_class='job_type'
      item_helper.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   #
   def stage_update_current(self, qb, stage_num, stage_progress):
      log.verbose('stage_update_current: was: %s, %s, %s%%' 
                  % (self.stage_name, self.stage_num, self.stage_progress,))
      g.assurt(self.work_item_id)
      g.assurt(self.step_number > 1) # Not supprtd for step '1', i.e., 'queued'
      self.stage_num = stage_num
      self.stage_progress = stage_progress
      ## Always preserve callback_def.
      #if callback_def is not None:
      #   self.callback_def.update(callback_def)
      # FIXME: But remove any None values the user provides.
      self.callback_data_prepare()
      self.callback_data_packit()

      log.verbose('stage_update_current: %s' % (self.stage_name,))
      log.verbose(' no.: %s of %s / %s%% [%s|%s]'
                  % (self.stage_num, 
                     self.work_item.num_stages,
                     self.stage_progress, 
                     'C' if self.cancellable else 'c', 
                     'S' if self.suspendable else 's',))

      # It's assumed qb.db has started a transaction and has a row lock.
      rows = qb.db.sql(
         """
         UPDATE 
            work_item_step 
         SET 
            stage_num = %s,
            stage_progress = %s,
            callback_dat = %s,
            callback_raw = %s
         WHERE 
            work_item_id = %s
            AND step_number = %s
         """, (self.stage_num, 
               self.stage_progress, 
               self.callback_dat, 
               self.callback_raw, 
               self.work_item_id, 
               self.step_number,))
      # Sql throws on error or returns naught otherwise.
      g.assurt(rows is None)

      # BUG 2688: Use transaction_retryable?
      qb.db.transaction_commit()
      log.verbose4('stage_update_current: committed/released database lock.')

   #
   def save_core(self, qb, kick_mr_do=True):

      # NOTE: This class doesn't manage its step_number; we leave that to the
      #       work_item class.

      # Before saving, pack the job data. We only pack/unpack when marshalling
      # to/from the database, since the job data is copied to the item itself
      # (see job_def_cols).
      self.callback_data_prepare()
      self.callback_data_packit()

      log.verbose('save_core: kick?: %s / callback_dat: %s' 
                  % (kick_mr_do, self.callback_dat,))

      # Save to the base table(s) first.
      item_helper.One.save_core(self, qb)

      # Save to the 'work_item_step' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

      # If this is the first step if a new work_item, or if the user sending a
      # new command to an exisiting work_item, we need to tickle the task mgr.
      # However, it's pointless to tell Mr. Do! to check for work until after
      # we've committed to the database.
      if kick_mr_do:
         qb.item_mgr.please_kick_mr_do = True

   # ***

   # C.f. work_item.job_data_prepare
   def callback_data_prepare(self):
      if self.callback_def is None:
         self.callback_def = {}
      for defn in self.callback_def_cols:
         attr_val = getattr(self, defn[0], defn[1])
         self.callback_def[defn[0]] = attr_val

   #
   def callback_data_packit(self):
      log.verbose('callback_data_packit: %s' % (self.callback_def,))
      if self.callback_def is not None:
         self.callback_dat = cPickle.dumps(self.callback_def, 
                                           One.PICKLE_PROTOCOL_ASCII)
         self.callback_raw = cPickle.dumps(self.callback_def, 
                                           One.PICKLE_PROTOCOL_BINARY)
         self.callback_raw = psycopg2.Binary(self.callback_raw)

   #
   def callback_data_unpack(self):
      if self.callback_raw is not None:
         g.assurt(self.callback_dat is not None)
         # FIXME: Settle on one of these.
         g.assurt(self.callback_dat)
         g.assurt(self.callback_raw)
         callback_def_dat = cPickle.loads(self.callback_dat)
         callback_def_raw = cPickle.loads(str(self.callback_raw))
         g.assurt(callback_def_dat == callback_def_raw)
         self.callback_def = callback_def_raw
         ## Make sure we reset any missing attrs.
         #for defn in self.callback_def_cols:
         #   self.callback_def.setdefault(defn[0], defn[1])
         # Rehydrate our locals that are stored in callback_def.
         # C.f. work_item.callback_data_unpack
         for defn in self.callback_def_cols:
            attr_val = self.callback_def.get(defn[0], defn[1])
            setattr(self, defn[0], attr_val)
         log.verbose('callback_data_unpack: %s' % (self.callback_def,))
      else:
         log.verbose('callback_data_unpack: No callback data: %s' % (self,))

   #
   def reset_callback_def(self, callback_def):
      self.callback_def.update(callback_def)
      for defn in self.callback_def_cols:
         attr_val = self.callback_def.get(defn[0], defn[1])
         setattr(self, defn[0], attr_val)

   # ***

   #
   @staticmethod
   def kick_mr_do(qb):

      # Kick the task daemon.
      try:

         mr_do_port_num_key_name = 'mr_do_port_num_%s' % (conf.ccp_dev_path,)
         port_num_sql = ("SELECT value FROM key_value_pair WHERE key = '%s'"
                         % (mr_do_port_num_key_name,))
         rows = qb.db.sql(port_num_sql)
         if len(rows) == 1:
            jobs_queue_port = int(rows[0]['value'])
         else:
            g.assurt(len(rows) == 0)
            jobs_queue_port = conf.jobs_queue_port

         log.debug('kick_mr_do_: kicking task daemon on port: %d' 
                   % (jobs_queue_port,))

         # Open connection
         sock = socket.socket()
         sock.connect(('localhost', jobs_queue_port,))
         sockf = sock.makefile('r+')

         # Write commands
         sockf.write('kick\n')
         sockf.flush()

         # Read XML response
         byte_count_str = sockf.readline().rstrip()
         log.debug('routed_fetch: kicked! byte_count_str: %s' 
                   % (byte_count_str,))
         # FIXME: Check for error?
         #if (byte_count_str == ''):
         #   raise GWIS_Error(Op_Handler.error_message 
         #                    % ('No response from', '',))

         # Close connection (must close both to avoid "Connection reset by
         # peer" on server).
         sockf.close()
         sock.close()

      except socket.error, e:
         err_s = 'There was a problem kicking the jobs daemon: %s' % (str(e),)
         #raise GWIS_Error(err_s)
         log.warning(err_s)

      except IOError, e:
         err_s = 'There was a problem kicking the jobs daemon: %s' % (str(e),)
         #raise GWIS_Error(err_s)
         log.warning(err_s)

class Many(item_helper.Many):

   one_class = One

   __slots__ = ()

   # Format the dates so they can easily be consumed by Flex's Date() ctor.
 # http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/Date.html
 # toString(): Day Mon Date H:M:S GMT Year ("Tue Feb 1 00:00:00 GMT-0800 2005")
   # E.g., Fri Dec 09 00:29:13 CST 2011
   date_fmt = 'Dy Mon DD HH24:MI:SS TZ IYYY'

   # *** SQL clauseses

   # BUG nnnn: If we're passing epoch seconds, make sure client and server use
   # same TZ.

   #sql_clauses_cols_all = item_helper.Many.sql_clauses_cols_all.clone()
   sql_clauses_cols_all = item_query_builder.Sql_Bi_Clauses()
   #sql_clauses_cols_all = item_query_builder.Sql_Clauses()

   sql_clauses_cols_all.inner.enabled = True

   sql_clauses_cols_all.inner.select = (
      """
      , wkst.step_number
      --, to_char(wkst.last_modified, %(date_fmt)s)
      , EXTRACT(EPOCH FROM wkst.last_modified) AS epoch_modified
      , wkst.stage_num
      , wkst.stage_name
      , wkst.stage_progress
      , wkst.status_code
      , wkst.status_text
      , wkst.cancellable
      , wkst.callback_dat
      , wkst.callback_raw
      """ % {'date_fmt': date_fmt,}
      )

   sql_clauses_cols_all.inner.from_table = (
      """
      work_item_step AS wkst
      """
      )

   # sql_clauses_cols_all.inner.group_by_enable = True
   sql_clauses_cols_all.inner.group_by = (
      """
      wkst.work_item_id
      , wkst.step_number
      , wkst.last_modified
      , wkst.stage_num
      , wkst.stage_name
      , wkst.stage_progress
      , wkst.status_code
      , wkst.status_text
      , wkst.cancellable
      , wkst.callback_dat
      , wkst.callback_raw
      """
      )

   sql_clauses_cols_all.inner.order_by_enable = True
   sql_clauses_cols_all.inner.order_by = (
      """
      wkst.work_item_id DESC
      , wkst.step_number DESC
      """
      )
   
   # *** Constructor

   def __init__(self):
      item_helper.Many.__init__(self)

   # ***

   #
   def search_by_work_item_id(self, qb, wtem, system_id, latest_only):
      # qb.sql_clauses is the Many clauses, so don't use it.
      # Not using: sql_clauses_cols_setup().
      clauses = self.sql_clauses_cols_all.clone().inner
      g.assurt(not clauses.where)
      g.assurt(system_id)
      clauses.where = " wkst.work_item_id = %d " % (system_id,)
      if not latest_only:
         select_preamble = "wkst.work_item_id"
      else:
         select_preamble = "DISTINCT ON (wkst.work_item_id) wkst.work_item_id"
      #
      sql = (
         """
         SELECT
            %s
            %s
         FROM
            %s
         WHERE
            %s
         GROUP BY
            %s
         ORDER BY
            %s
         """ % (select_preamble,
                clauses.select,
                clauses.from_table,
                clauses.where,
                clauses.group_by,
                clauses.order_by,))
      #
      rows = qb.db.sql(sql)
      for row in rows:
         # Cannot call get_one because of wtem. FIXME: Remove get_one.
         item = self.one_class(qb=qb, wtem=wtem, row=row)
         self.append(item)

   #
   def search_get_sql(self, qb):
      g.assurt(False) # Not used this way.

