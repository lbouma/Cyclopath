# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The Null request does nothing.
# FIXME Or does it return a response with rid_max?

import os
import sys

import conf
import g

from gwis import command

log = g.log.getLogger('cmd.null')

class Op_Handler(command.Op_Handler):

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      g.assurt(False) # Who uses this class?

   # ***

   #
   def __str__(self):
      selfie = 'null cmd'
      return selfie

   # ***

# ***

