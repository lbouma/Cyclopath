# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A versioned feature is one that follows the valid_start_id/valid_until_id
# revisioning model.

import sys

import conf
import g

from gwis.exception.gwis_error import GWIS_Error

log = g.log.getLogger('cmd_factory')

def get_command(module_name, req):

   try:
      log.verbose('get_command: %s' % (module_name,))
      cmd_module = __import__('gwis.command_.' + module_name,
         globals(), locals(), ['Op_Handler',], -1)
   except ImportError, e:
      log.warning('ImportError: %s' % (str(e),))
      raise GWIS_Error(
         "Invalid GWIS request type: '%s' (this is possibly our fault)." 
         % (module_name,))
   g.assurt(cmd_module is not None)

   log.debug('cmd_module: %s' % (cmd_module.__name__,))

   return cmd_module.Op_Handler(req)

