# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# From:
#
#   http://stackoverflow.com/questions/566746/how-to-get-console-window-width-in-python

import fcntl
import os
import struct
import termios

class Console(object):

   # *** Public interface

   @staticmethod   
   def getTerminalSize():
      cr = (Console.ioctl_GWINSZ(0) 
            or Console.ioctl_GWINSZ(1) 
            or Console.ioctl_GWINSZ(2))
      if not cr:
         try:
            fd = os.open(os.ctermid(), os.O_RDONLY)
            cr = Console.ioctl_GWINSZ(fd)
            os.close(fd)
         except:
            pass
      if not cr:
         try:
            cr = (env['LINES'], env['COLUMNS'],)
         except:
            # 2013.05.28: This happens for cron so return something big, so
            #             log files aren't too tight.
            # cr = (25, 80,)
            cr = (999, 999,)
      return int(cr[1]), int(cr[0])

   # *** Private interface

   @staticmethod   
   def ioctl_GWINSZ(fd):
      try:
         cr = struct.unpack('hh', fcntl.ioctl(fd, termios.TIOCGWINSZ, '1234'))
      except:
         cr = None
      return cr

