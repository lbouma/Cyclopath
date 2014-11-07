# Copyright (c) 2006-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This command is for general queries about the state of the server...
# we could piggyback on command_base (which adds the gwis version,
# wiki revision, and VERSION.major to all responses), but 

from lxml import etree
import os
import sys

import conf
import g

from gwis import command
from gwis import command_base
from util_ import misc

log = g.log.getLogger('cmd.kval_get')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'kval_keys',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.kval_keys = None

   # ***

   #
   def __str__(self):
      selfie = (
         'kval_get: kval_keys: %s'
         % (self.kval_keys,))
      return selfie

   # ***

   #
   def pre_decode(self):
      command.Op_Handler.pre_decode(self)

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.kval_keys = self.decode_key('vkey', '').split(',')

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      kvals_doc = etree.Element('kvals')
      # MAGIC_NUMBER: The "0" keys fetches a known collection of key values.
      if (   (not self.kval_keys)
          or (not self.kval_keys[0])
          or (self.kval_keys[0] == "0")):
         # Return the maintenance situation.
         (cp_maint_beg, cp_maint_fin,) = self.maintenance_mode()
         #
         if cp_maint_beg:
            #kval_doc = etree.Element('kval')
            #misc.xa_set(kval_doc, 'key', 'cp_maint_beg')
            #misc.xa_set(kval_doc, 'value', cp_maint_beg)

            # MAYBE: Implement timestamp_age in Python...
            #         save a few db calls.

            beg_age = misc.timestamp_age(
               self.req.db, cp_maint_beg, calc_secs=True)
            kval_doc = etree.Element('cp_maint_beg_age')
            #kval_doc.text = cp_maint_beg
            kval_doc.text = str(beg_age)
            kvals_doc.append(kval_doc)
         #
         if cp_maint_fin:
            #kval_doc = etree.Element('kval')
            #misc.xa_set(kval_doc, 'key', 'cp_maint_fin')
            #misc.xa_set(kval_doc, 'value', cp_maint_fin)
            fin_age = misc.timestamp_age(
               self.req.db, cp_maint_fin, calc_secs=True)
            kval_doc = etree.Element('cp_maint_fin_age')
            #kval_doc.text = cp_maint_fin
            kval_doc.text = str(fin_age)
            kvals_doc.append(kval_doc)
         #
      else:
         #
         # NOTE/CAVEAT/MAYBE:
         #   Users can query anything from the key_value_table!!
         #   So don't store anything important in there.
         #
         kval_keys = ','.join([self.req.db.quoted(x) for x in self.kval_keys])
         sql_kval_vals = (
            "SELECT key, value FROM key_value_pair WHERE key IN (%s)"
            % (kval_keys,))
         rows = self.req.db.sql(sql_kval_vals)
         for row in rows:
            #kval_doc = etree.Element('kval')
            #misc.xa_set(kval_doc, 'key', row['key'])
            #misc.xa_set(kval_doc, 'value', row['value'])
            kval_doc = etree.Element(row['key'])
            kval_doc.text = row['value']
            kvals_doc.append(kval_doc)
      # NOTE: We don't return documents for keys that do not exist.
      self.doc.append(kvals_doc)

   #
   def prepare_response(self):
      log.verbose('prepare_response')

   # ***

# ***

