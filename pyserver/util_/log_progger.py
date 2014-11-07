#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: This is a base class for Cyclopath command line scripts.

import os
import sys
import time

import conf
import g

from util_ import misc

log = g.log.getLogger('log_progger')

__all__ = ('Debug_Progress_Logger',)

# ***

class Debug_Progress_Logger(object):

   __slots__ = (
      #
      'progress',
      'time_0',
      #
      'log_freq',
      'freq_msg',
      'loop_max',
      'log_listen',
      'user_data',
      'log_silently',
      #
      'debug_break_loops',
      'debug_break_loop_cnt',
      'debug_break_loop_off',
      #
      'callee',
      #
      'info_print_speed_enable',
      'info_print_speed_beging',
      'info_print_speed_during',
      'info_print_speed_finish',
      #
      'runtime_guess',
      )

   # *** Constructor

   def __init__(self, copy_this=None, log_freq=1, loop_max=None, callee=None):

      # Copy the copy_this's attrs. We copy all of them now, but some of them
      # we reset following this block.
      if copy_this is not None:
         for mbr in Debug_Progress_Logger.__slots__:
            setattr(self, mbr, getattr(copy_this, mbr))
      else:
         self.log_listen = None
         # The caller can attach a payload. But currently none do.
         self.user_data = None
         self.debug_break_loops = False
         self.debug_break_loop_cnt = 1
         self.debug_break_loop_off = 0

      g.assurt(log_freq >= 1)
      self.log_freq = log_freq
      self.freq_msg = ''
      self.loop_max = loop_max

      self.loops_reset()

      self.log_silently = False

      self.callee = callee

      self.info_print_speed_enable = False
      self.info_print_speed_beging = 1
      self.info_print_speed_during = 10
      self.info_print_speed_finish = 1

      self.runtime_guess = 0

   # ***

   #
   def loops_reset(self):
      self.progress = 0
      self.time_0 = time.time()

   #
   def loops_inc(self, log_freq=None, freq_msg=None):
      if log_freq is None:
         log_freq = self.log_freq
      if freq_msg is None:
         freq_msg = self.freq_msg
      debug_short_circuit = False
      self.progress += 1
      if self.progress % log_freq == 0:
         if not self.log_silently:
            percentage_and_speed = ''
            if self.loop_max:
               runtime_guess = self.total_time_guess()
               runtime_fmtd, scale, units = misc.time_format_scaled(
                                                      runtime_guess)
               remaining = self.runtime_guess - (time.time() - self.time_0)
               percentage = (
                  100.0 * (float(self.progress) / float(self.loop_max)))
               # MAGIC_NAME: lps = loops per second.
               time_delta = time.time() - self.time_0
               time_delta = time_delta if time_delta else 0.000000001
               percentage_and_speed = (
                  ' (%2d.%s%%) [%.1f lps] {%s to go}'
                  % (int(percentage),
                     # No '0.', and just one-tenth.
                     str(float(percentage - int(percentage)))[2:3],
                     float(self.progress) / time_delta,
                     misc.time_format_scaled(remaining)[0],))
            log.debug(' >> %s %7d%s'
                      % (('%s:' % self.callee) if self.callee else '...',
                         self.progress,
                         percentage_and_speed,))
            if freq_msg:
               log.verbose3('%s' % (freq_msg,))
               if ((self.loop_max is not None)
                   and (self.loop_max < self.progress)):
                  log.warning(
                     'loops_inc: unexpected loop count: cur: %d / max: %d'
                     % (self.progress, self.loop_max,))
         if self.debug_break_loops:
            threshold = log_freq * self.debug_break_loop_cnt
            if self.progress % threshold == 0:
               debug_short_circuit = True
         if self.log_listen is not None:
            # Trigger the user's callback. The caller can setup user_data
            # via init_progger() if that helps it figure out where it's at.
            self.log_listen(self)

         if (self.info_print_speed_enable
             and (   (self.info_print_speed_beging
                      and (self.progress == self.log_freq))
                  #or (self.info_print_speed_during
                  #    and (self.progress
                  #         % (self.log_freq * self.info_print_speed_during)
                  #         == 0))
                  )):
            self.loops_info(self.callee, make_guess=True)

      return debug_short_circuit

   #
   def loops_fin(self, callee=''):
      if not callee:
         callee = self.callee
      if self.info_print_speed_enable and self.info_print_speed_finish:
         self.loops_info(callee)
      log.info('%s%d loops took %s'
         % (('%s: ' % callee) if callee else '', self.progress,
            misc.time_format_elapsed(self.time_0),))

   #
   def loops_info(self, callee='', make_guess=False):
      if not callee:
         callee = self.callee
      log.info('After %d loops, %saveraged %.2f items per sec.'
         % (self.progress, ('%s ' % callee) if callee else '',
            (float(self.progress) / (time.time() - self.time_0)),))
      #if (self.progress == self.log_freq) and self.loop_max:
      if make_guess and self.loop_max:
         runtime_guess = self.total_time_guess()
         runtime_fmtd, scale, units = misc.time_format_scaled(runtime_guess)
         remaining = self.runtime_guess - (time.time() - self.time_0)
         log.info('Adjusted expected runtime: %s (%s remaining)'
                  % (runtime_fmtd, misc.time_format_scaled(remaining)[0],))

   #
   def setup(self, debug_prog_log, log_freq, loop_max=None):
      self.log_freq = log_freq
      if ((debug_prog_log.debug_break_loops)
          and (debug_prog_log.debug_break_loop_cnt < self.log_freq)):
          # Show a handful or two of frequency updates, even if just
          # a handful or score of loops being run.
          self.log_freq = max(
             round(float(debug_prog_log.debug_break_loop_cnt)/8.0), 1)
      if loop_max is not None:
         self.loop_max = loop_max

   #
   def total_time_guess(self, items_per_second_guess=0):

      self.runtime_guess = 0

      if self.loop_max:

         if self.progress:

            thus_far = time.time() - self.time_0

            self.runtime_guess = (
               (float(self.loop_max) / float(self.progress)) * thus_far)

         elif items_per_second_guess > 0:

            self.runtime_guess = (
               float(self.loop_max) / float(items_per_second_guess))

      return self.runtime_guess

   # ***

# ***

