# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Used to get the region names for the revision filter autocomplete.

from lxml import etree
import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item.feat import region
from item.util import item_factory
from util_ import misc

log = g.log.getLogger('cmd.itm_names')

# Test URI
# /gwis?rqst=item_names_get&ityp=branch&gwv=3&body=yes

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'item_type',
      'items_fetched',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.item_type = None
      self.items_fetched = None

   # ***

   #
   def __str__(self):
      selfie = (
         'item_names_get: item_type: %s / items_fetched: %s'
         % (self.item_type,
            self.items_fetched,))
      return selfie

   # *** Base class overrides

   #
   def decode_request(self):
      '''Validate and decode the incoming request.'''
      command.Op_Handler.decode_request(self)
      self.decode_request_item_type()

   #
   def decode_request_item_type(self):
      self.item_type = self.decode_key('ityp')
      success = item_factory.is_item_valid(self.item_type, True)
      if not success:
         raise GWIS_Error('Invalid item type: ' + self.item_type)
      log.verbose1('decode_request_item_type: %s' % (self.item_type))

   # Returns a list of names and stack_ids of items of the specified type to 
   # which the user has viewer-or-better access.
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      self.items_fetched = item_factory.get_item_module(self.item_type).Many()
      log.verbose1('fetch_n_save: getting name of items of type: %s' 
                   % (self.items_fetched.one_class,))

      # FIXME: See checkout.py, which is a lot more strict. E.g., commit.py
      #        requires that the user use pagination for certain item types.
      #        PROBABLY: Just use checkout command, with, e.g., &colgrp=names
      self.items_fetched.search_for_names(self.req.as_iqb()) 

   #
   def prepare_response(self):
      need_digest = False
      for item in self.items_fetched:
         e = etree.Element(self.item_type)
         #misc.xa_set(e, 'name', item.name)
         #misc.xa_set(e, 'stack_id', item.stack_id)
         item.attrs_to_xml(e, need_digest)
         self.doc.append(e)

   # ***

# ***

