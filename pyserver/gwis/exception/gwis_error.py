# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis.exception.gwis_warning import GWIS_Warning
from util_ import misc

log = g.log.getLogger('gwis.error')

class GWIS_Error(GWIS_Warning):
   '''An error which should be reported to the user (flashclient),
      and also logged as a warning to the pyserver log.'''

   def __init__(self, message, tag=None, logger=log.error):
      GWIS_Warning.__init__(self, message, tag, logger)

   def as_xml(self, elem_name='gwis_error'):
      xml = GWIS_Warning.as_xml(self, elem_name)
      return xml

