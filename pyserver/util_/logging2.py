# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import logging
import logging.handlers
#import os
import threading

__all__ = ['My_Logger', 'My_Handler']

"""

The Python logging library defines the following levels:

---Level---  ---Value---
 CRITICAL         50       
 ERROR            40
 WARNING          30
 INFO             20
 DEBUG            10
 NOTSET            0

But I [lb] sometimes like a little more verbosity, and sometimes I like a 
little more info'ness without out quite issuing a warning. So this file 
introduces two new levels:

---Level---  ---Value---
 NOTICE           25
 VERBOSE1          9
 VERBOSE2          8
 VERBOSE3          7
 VERBOSE4          6
 VERBOSE5          5
 VERBOSE           5

Also, this script splits long messages into multiple lines and prefixes 
each line except the first with a bunch of spaces, so that messages are 
right-justified and don't fill the columns on the left, which are used to 
show the timestamp, debug level, and logger name.

E.g.,

00:28:13  DEBUG  item_user_access  #  A one-line message
00:28:13  DEBUG     grax.grac_mgr  #  This is an example of a log message for
                                   #  which that spans two lines.
"""

# *** 

NOTICE = 25
VERBOSE1 = 9
VERBOSE2 = 8
VERBOSE3 = 7
VERBOSE4 = 6
VERBOSE5 = 5
VERBOSE = 5

# ***

APACHE_REQUEST = None

# *** 

def config_line_format(frmat_len, frmat_postfix, line_len=None, add_tid=False):
   global msg_continuation_prefix, line_len_log, line_len_msg, \
          include_thread_id
   if line_len == 0:
      # Most terminals' widths are 80 chars, right?
      line_len = 80
   msg_continuation_prefix = (' ' * frmat_len) + frmat_postfix
   line_len_log = line_len
   include_thread_id = add_tid
   if line_len_log is not None:
      line_len_msg = line_len_log - len(msg_continuation_prefix)
   else:
      line_len_msg = None

# *** 

class My_Logger(logging.Logger):

   def __init__(self, name, level=logging.NOTSET):
      logging.Logger.__init__(self, name, level)

   # C.f., e.g., /usr/lib64/python2.7/logging/__init__.py

   #
   def _log(self, level, msg, args, exc_info=None, extra=None):
      global include_thread_id
      global APACHE_REQUEST
      # For multi-threaded apps, including the thread ID.
      if include_thread_id:
         if APACHE_REQUEST is not None:
            # You'll see the same parent process ID (and it's not 1)
            # for all apache request threads (os.getppid()).
            # You'll see lots of unique process IDs for each request,
            # but some processes appear to handle multiple connections
            # per process (os.getpid()).
            # You'll find that each thread has a unique identifier. It
            # doesn't matter if we use the cooked-in get_ident() value,
            # or if we use the object id, id(threading.currentThread()).
            msg = ('%8d-%3d: %s'
                   % (threading.currentThread().ident,
                      int(APACHE_REQUEST.connection.id),
                      msg,))
         else:
            msg = '%8d: %s' % (threading.currentThread().ident, msg,)
      logging.Logger._log(self, level, msg, args, exc_info, extra)

   # NOTE: Old source used apply, which is deprecated. E.g.,:
   #         apply(self._log, (NOTICE, msg, args), kwargs)
   #       The new source uses the extended call syntax instead.

   #
   def notice(self, msg, *args, **kwargs):
      """
      Log 'msg % args' with severity 'NOTICE'.

      To pass exception information, use the keyword argument exc_info with
      a true value, e.g.

      logger.notice("Houston, we have a %s", "interesting problem", exc_info=1)
      """
      global NOTICE
      # Pre-Python 2.7:
      #if self.manager.disable >= NOTICE:
      #   return
      #if NOTICE >= self.getEffectiveLevel():
      #   apply(self._log, (NOTICE, msg, args), kwargs)
      # FIXME: This works in Python 2.7, but hasn't been tested on other
      # releases.
      if self.isEnabledFor(NOTICE):
         # NOTE: We don't repackages args. I.e., you'll get
         #   TypeError: _log() takes at least 4 arguments (3 given)
         # if you try: self._log(NOTICE, msg, *args, **kwargs)
         self._log(NOTICE, msg, args, **kwargs)

   #
   def verbose1(self, msg, *args, **kwargs):
      global VERBOSE1
      if self.isEnabledFor(VERBOSE1):
         self._log(VERBOSE1, msg, args, **kwargs)

   #
   def verbose2(self, msg, *args, **kwargs):
      global VERBOSE2
      if self.isEnabledFor(VERBOSE2):
         self._log(VERBOSE2, msg, args, **kwargs)

   #
   def verbose3(self, msg, *args, **kwargs):
      global VERBOSE3
      if self.isEnabledFor(VERBOSE3):
         self._log(VERBOSE3, msg, args, **kwargs)

   #
   def verbose4(self, msg, *args, **kwargs):
      global VERBOSE4
      if self.isEnabledFor(VERBOSE4):
         self._log(VERBOSE4, msg, args, **kwargs)

   #
   def verbose5(self, msg, *args, **kwargs):
      global VERBOSE5
      if self.isEnabledFor(VERBOSE5):
         self._log(VERBOSE5, msg, args, **kwargs)

   #
   def verbose(self, msg, *args, **kwargs):
      """
      Log 'msg % args' with severity 'VERBOSE'.

      To pass exception information, use the keyword argument exc_info with
      a true value, e.g.

      logger.notice("Houston, we have a %s", "loud problem", exc_info=1)
      """
      global VERBOSE
      # Pre-Python 2.7:
      #if self.manager.disable >= VERBOSE:
      #   return
      #if VERBOSE >= self.getEffectiveLevel():
      #   apply(self._log, (VERBOSE, msg, args), kwargs)
      # FIXME: This works in Python 2.7, but hasn't been tested on other
      # releases.
      if self.isEnabledFor(VERBOSE):
         self._log(VERBOSE, msg, args, **kwargs)

# *** 

class My_StreamHandler(logging.StreamHandler):

   def __init__(self):
      logging.StreamHandler.__init__(self)

   #
   def format(self, record):
      return My_Handler.format(self, record)

class My_FileHandler(logging.FileHandler):

   def __init__(self, filename, mode='a'):
      logging.FileHandler.__init__(self, filename, mode)

   #
   def format(self, record):
      return My_Handler.format(self, record)

class My_Handler(object):

   #
   @staticmethod
   def format(handler, record):
      """
      Format the specified record. If a formatter is set, use it. Otherwise, 
      use the default formatter for the module.
      """
      global msg_continuation_prefix, line_len_log, line_len_msg
      if handler.formatter:
         fmt = handler.formatter
      else:
         fmt = logging._defaultFormatter
      msg = fmt.format(record)
      if (line_len_log is None) or (msg.find('\n') != -1):
         verbatim = True
      else:
         verbatim = False
      #msg = msg % (('\n' if verbatim else ''),)
      if verbatim:
         # FIXME: This is completely correct. The msg is printed verbatim --
         # including newlines -- but the first part of the message still
         # follows the date and names; ideally, there'd be a newline after the
         # date and names, but before the message. Well, not when line_len_log
         # is None, but when the message already has newlines.
         formatted = '%s' % msg.strip()
      else:
         first = True
         multi_line = []
         while len(msg) > 0:
            # BUG nnnn: Only split (insert newlines) on whitespace, otherwise
            # if you are searching a trace your keyword may miss a hit.
            if not first:
               snip = msg_continuation_prefix
               snip += msg[0:line_len_msg]
               msg = msg[line_len_msg:]
            else:
               snip = msg[0:line_len_log]
               msg = msg[line_len_log:]
               first = False
            # FIXME: Newlines mess up formatting. If there's a newline in snip,
            #        you should back up to the newline and put the remainder   
            #        back in msg.                                              
            snip += '\n'
            multi_line.append(snip)
         multi_line[-1] = multi_line[-1].strip('\n')
         formatted = ''.join(multi_line)
      return formatted

# *** 

logging_inited = False

def init_logging(log_level=logging.INFO, 
                 log_fname=None, 
                 log_frmat=None, 
                 log_dfmat=None,
                 log_to_file=False,
                 log_to_console=False,
                 log_frmat_len=0,
                 log_frmat_postfix='#',
                 log_line_len=None,
                 add_thread_id=False):
   global logging_inited
   if not logging_inited:
      init_logging_impl(log_level, log_fname, log_frmat, log_dfmat,
                        log_to_file, log_to_console, 
                        log_frmat_len, log_frmat_postfix, log_line_len,
                        add_thread_id)
      logging_inited = True

def init_logging_impl(log_level, log_fname, log_frmat, log_dfmat,
                      log_to_file, log_to_console, 
                      log_frmat_len, log_frmat_postfix, log_line_len,
                      add_thread_id):

   config_line_format(log_frmat_len, log_frmat_postfix, log_line_len, 
                      add_thread_id)

   if not log_frmat:
      log_frmat = ('%%(asctime)s %%(levelname)-4s %%(name)-11s %s %%(message)s'
                   % (log_frmat_postfix,))

   if not log_dfmat:
      # See strftime() for the meaning of these directives.
      log_dfmat = '%a, %d %b %Y %H:%M:%S'

   #logging.basicConfig(
   #   level=log_level,
   #   filename=log_fname,
   #   format=log_frmat,
   #   datefmt=log_dfmat)

   formatter = logging.Formatter(log_frmat, log_dfmat)

   logging.setLoggerClass(My_Logger)

   logging.getLogger('').setLevel(log_level)

   logging.addLevelName(logging.CRITICAL,  'CRIT') # 50
   logging.addLevelName(logging.ERROR,     'ERRR') # 40
   logging.addLevelName(logging.WARNING,   'WARN') # 30
   logging.addLevelName(        NOTICE,    'NTCE') # 25
   logging.addLevelName(logging.INFO,      'INFO') # 20
   logging.addLevelName(logging.DEBUG,     'DEBG') # 10
   logging.addLevelName(        VERBOSE1,  'VRB1') # 09
   logging.addLevelName(        VERBOSE2,  'VRB2') # 08
   logging.addLevelName(        VERBOSE3,  'VRB3') # 07
   logging.addLevelName(        VERBOSE4,  'VRB4') # 06
   logging.addLevelName(        VERBOSE5,  'VRB5') # 05
   logging.addLevelName(        VERBOSE,   'VRBS') # 05

   if log_to_file:
      handler = My_FileHandler(log_fname)
      handler.setLevel(log_level)
      handler.setFormatter(formatter)
      logging.getLogger('').addHandler(handler)

   if log_to_console:
      handler = My_StreamHandler()
      handler.setLevel(log_level)
      handler.setFormatter(formatter)
      logging.getLogger('').addHandler(handler)

# *** 

# To initialize the logger when this module is loaded, uncomment the following:
# init_logging()

if __name__ == '__main__':
    pass

