# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The Hello request removes the users token from the system (forces immediate
# expiration).

import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from util_ import misc

log = g.log.getLogger('cmd.user_goodbye')

class Op_Handler(command.Op_Handler):

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)

   # ***

   #
   def __str__(self):
      selfie = 'user_goodbye'
      return selfie

   # ***

   # BUG nnnn: user_goodbye request so we delete the token.
   # BUG nnnn: Where's the FIXME on making a session ID table and generating
   #           session IDs on the server, rather than in the client?
   # See also: comments in gwis/query_client.py
   #           We should move expired rows to a log table (ignore guid
   #           but record username, date started, ended, and request count).

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

   #
   def prepare_response(self):
      pass

