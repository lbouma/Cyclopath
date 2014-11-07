# Copyright (c) 2006-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys
import time

import conf
import g

log = g.log.getLogger('problem_base')

__all__ = ('Problem_Base',)

class Problem_Base(object):

   # FIXME: This is ridonculous. The server should really just send an error
   #        code and it should be up to the client to display a thoughtful
   #        message... in whatever language that client might support...
   #        so, yeah, rework GWIS_Error and GWIS_Warning to send an error
   #        code rather than English strings.
   error_msg_basic = (
      "Our apologies, but we were unable to find a route for you!\n\n"
      + "Our code had a problem and so it sent you this message instead.\n\n"
      + "Our engineers were sent an email about the problem, but "
      + "you can email %s if you would like to know more about it "
        % (conf.mail_from_addr,)
      + "or to bug us to fix it.\n\n"
      + "Sorry again!"
      )

   # *** Constructor

   def __init__(self):
      pass # No-op.

   # ***

# ***

