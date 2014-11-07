# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from util_ import misc
from gwis.exception.gwis_error import GWIS_Error

log = g.log.getLogger('gwis.fatal')

# CONFUSING: GWIS_Error is a GWIS protocol error and not a pyserver error
# (which is why GWIS_Error uses log.warning, but GWIS_Fatal is a pyserver 
# crash, so we use log.error.

class GWIS_Fatal(GWIS_Error):
   '''A fatal error which should be reported to the user (flashclient),
      and also logged as an error to the pyserver log.'''

   def __init__(self, message, tag=None, logger=log.error):
      GWIS_Error.__init__(self, message, tag, logger)

   def as_xml(self, elem_name='gwis_fatal'):
      xml = GWIS_Error.as_xml(self, elem_name)
      return xml

