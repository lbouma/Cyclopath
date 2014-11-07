# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis import command_client

log = g.log.getLogger('command')

# We use a command class hierarchy to keep different bits of related code in
# their own modules.

# This class is very bare; it's here so clients can always use the name
# 'command' and not have to worry about changes to the class hierarchy.

class Op_Handler(command_client.Op_Handler):

   def __init__(self, req):
      command_client.Op_Handler.__init__(self, req)

# That's all, folks!

