# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import datetime
import math
import re
import subprocess
import time
import traceback
#import urllib
import urllib2

#import conf
import g

from util_.inflector import Inflector

log = g.log.getLogger('util_.misc')

# ***

#
def color_str_dec_to_hex(str_color):
   # Assuming, e.g., "123 456 78".
   if str_color != '':
      col_vals = str_color.split(' ')
      g.assurt(len(col_vals) == 3)
      new_vals = []
      for col_val in col_vals:
         # When you stringify hex, you get a leading '0x'.
         new_val = str(hex(int(col_val)))[2:]
         if len(new_val) == 1:
            new_val = '0%s' % (new_val,)
         else:
            g.assurt(len(new_val) == 2)
         new_vals.append(new_val)
      hex_str = ('0x%s%s%s'
                 % (new_vals[0],
                    new_vals[1],
                    new_vals[2],))
   else:
      #hex_str = '0x0'
      hex_str = None
   return hex_str

# ***

#
def dict_count_inc(the_dict, key):
   try:
      the_dict[key]
   except KeyError:
      the_dict[key] = 0
   finally:
      g.assurt(the_dict[key] >= 0)
   the_dict[key] += 1

#
def dict_dict_increment(dict_dict, key1, key2):
   try:
      dict_dict[key_1][key_2] += 1
   except KeyError:
      try:
         dict_dict[key_1][key_2] = 1
      except KeyError:
         dict_dict[key_1] = dict()
         dict_dict[key_1][key_2] = 1

#
def dict_dict_update(dict_dict, key1, key2, value, strict=False):
   try:
      dict_dict[key1]
      if strict:
         try:
            dict_dict[key1][key2]
            # key2 exists, and caller says strict, so complain.
            # But don't raise or whatnot; this is just for the logs.
            log.warning('dict_dict_update: key exists: dict_dict[%s][%s]: %s'
                        % (key1, key2, dict_dict[key1][key2],))
         except KeyError:
            pass
   except KeyError:
      dict_dict[key1] = dict()
   dict_dict[key1][key2] = value

#
def dict_list_append(dict_list, key, value):
   try:
      dict_list[key]
   except KeyError:
      dict_list[key] = list()
   dict_list[key].append(value)

#
def dict_set_add(dict_set, key, value, strict=False):
   try:
      dict_set[key]
      if strict and (value in dict_set[key]):
         log.warning(
            'dict_set_add: value exists: dict_set[key]: %s / value: %s'
            % (key, value,))
   except KeyError:
      dict_set[key] = set()
   dict_set[key].add(value)

#
def pprint_dict_count_normalized(the_dict, log_f):
   # Print the header.
   header = '%3s ||' % ('',)
   # [0, 1, 2, 3, 4, 5, 6, 7, 8, 9,]
   for ones in xrange(0, 10):
      header += ' %6s |' % (ones,)
   header += '|  Total |'
   log_f(header)
   # Print a dividing line.
   log_f('%3s %s' % ('', '='*(2+9*11+1),))
   # Print just the 0.00 results.
   all_cnt = 0
   try:
      zed_count = the_dict[0]
      all_cnt += zed_count
   except KeyError:
      zed_count = ''
   log_f('%3s || %6s | %s || %6s |' % (0, zed_count, '-'*(9*9-3), zed_count,))
   # Print 0.01 to 1.00.
   # [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100,]
   for tens in xrange(0, 101, 10):
      ten_str = ''
      ten_cnt = 0
      # [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,]
      for ones in xrange(0, 11):
         if ones == 10:
            ten_str += '|'
            usage_count = ten_cnt
         elif (((tens == 0) and (ones == 0))
             or ((tens == 100) and (ones > 0))):
            usage_count = '-'*6
         else:
            try:
               usage_count = the_dict[tens+ones]
               ten_cnt += usage_count
               all_cnt += usage_count
            except KeyError:
               usage_count = ''
         ten_str += ' %6s |' % (usage_count,)
      log.info('%3s ||%s' % (tens, ten_str,))
   # Print a dividing line.
   log_f('%3s %s' % ('', '='*(2+9*11+1),))
   # Print the total total.
   log_f('%3s || %6s || %6s |' % ('ALL', '-'*(9*10-3), all_cnt,))
   # Print a footerline.
   log_f('%s' % ('='*(4+2+9*11+1),))
   # Print an explanation.
   log.info(
      'Hint: Result values were 0.0 to 1.0, and cell val. is no. of')
   log.info(
      '      results rounded to 0.01 that == (row name + col name) / 100.0)')

# ***

#
def exception_format(ex):
   'Format an exception (not including the stacktrace) and return as a string.'
   # See http://docs.python.org/library/traceback.html. Indeed, this seems
   # the simplest/most logical way. Ugh!
   #
   # The array slice removes the trailing newline.
   return (''.join(traceback.format_exception_only(type(ex), ex)))[:-1]

# ***

#
def file_touch(fname, times=None):
   # We could use 'with open()', but file() is a little more low level.
   g.assurt(fname)
   with file(fname, 'a'):
      os.utime(fname, times)

# ***

#
def float_pigeon_hole(val_float):
   # This fcn. takes a float and finds its position in a logarithmic range we
   # define as follows. The fcn. returns the min and max values of the range in
   # which the float falls. (Remember that [] means inclusive and () means
   # exclusive.) This fcn. is useful for generating stats.
   #
   # [0, 10)
   # [10, 20)
   # ...
   # [80, 90)
   # [90, 100)
   # [100, 200)
   # ...
   # [1000, 2000)
   # [2000, 3000)
   # ...
   # [10000, 20000)
   #
   if (not val_float) or (val_float < 0):
      range_min = 0
      range_max = 0
   elif val_float < 10:
      range_min = 0
      range_max = 10
   else:
      val_str = str(int(val_float))
      num_digits = len(val_str)
      # If, e.g., val is 3443.7, magnitude is 1000.
      magnitude = pow(10, num_digits - 1)
      # Multiply by the highest order digit.
      range_min = int(val_str[0]) * magnitude
      # It's easy to calculate the upper bound of the range.
      range_max = range_min + magnitude
      # If, e.g., val is 3443.7, [range_min, range_max) is [3000, 4000).
   return range_min, range_max

# ***

#
def module_name_simple(o):
   # From, e.g., 'item.feat.byway', return 'byway'
   mod = o.__class__.__module__
   mod = mod[(mod.rfind('.') + 1):]
   return mod

# ***

#
def nowstr():
   'Return a string representing the current time down to microseconds.'
   time_0 = time.time()
   (fracp, intp) = math.modf(time_0)
   return time.strftime('%Y%m%d-%H:%M:%S',
                        time.localtime(time_0)) + '.%d' % (fracp * 1000000)

# ***

#
# FIXME: Consolidate with run_cmd?
def process_check_output(cmd_and_args):
   try:
      log.debug('Running cmd [>=2.7]: %s' % (cmd_and_args,))
      resp = subprocess.check_output(cmd_and_args)
   except AttributeError:
      # < Python 2.7
      cmd = ' '.join(cmd_and_args)
      log.debug('Running cmd [<2.7]: %s' % (cmd,))
      p = subprocess.Popen(cmd,
                           shell=True,
                           # bufsize=bufsize,
                           stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT,
                           close_fds=True)
      (resp_in, resp_out_and_err) = (p.stdin, p.stdout)
      resp = resp_out_and_err.read()
      resp_in.close()
      resp_out_and_err.close()
      p.wait()
      #(sout, serr) = subprocess.Popen(cmd,
      #                                stdout=subprocess.PIPE,
      #                                stderr=subprocess.STDOUT).communicate()
   except Exception, e:
      g.assurt(False)
   log.debug('process_check_output: resp: %s' % (resp,))
   return resp

# ***

#
def replace_i(s, old, new, count=0):
   'Like string.replace(), but case-insensitive.'
   pattern = re.compile(re.escape(old), re.I)
   return pattern.sub(new, s, count)

# ***

#
def run_cmd(the_cmd, outp=None):
   '''Runs the command the_cmd using the subprocess module. Optionally sends
      debug output to outp.'''
   #
   if outp is not None:
      time_0 = time.time()
      outp('run_cmd: %s' % (the_cmd,))
   #
   p = subprocess.Popen([the_cmd],
                        shell=True,
                        # bufsize=bufsize,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        close_fds=True)
   (sin, sout_err) = (p.stdin, p.stdout)
   while True:
      line = sout_err.readline()
      if not line:
         break
      elif outp is not None:
         outp(line)
   # FIXME: Parse the output for errors?
   sin.close()
   sout_err.close()
   p.wait()
   #
   if outp is not None:
      outp('run_cmd: complete in: %s'
           % (time_format_elapsed(time_0),))

# *** Timey Wimey fcns.

#
def sql_time_to_datetime(sql_timestamp):
   '''Parse a sql returned timestamp into a datetime.datetime object.
      This assumes that the sql_timestamp was formatted as per the sql
      function: to_char(col, 'YYYY-DD-MM HH:MI:SS').'''
   # In psycopg, SQL DATE columns are returned as strings and we convert them
   # to datetime.datetime objects here. In psycopg2, this is already done for
   # us.
   if not isinstance(sql_timestamp, datetime.datetime):
      g.assurt(isinstance(sql_timestamp, basestring))
      sql_timestamp = datetime.datetime(
                       *time.strptime(sql_timestamp, "%Y-%d-%m %H:%M:%S")[0:6])
   return sql_timestamp

#
def time_complain(task_name,
                  time_0,
                  threshold_s,
                  at_least_debug=True,
                  debug_threshold=0,
                  info_threshold=0):
   delta_s = time.time() - time_0
   logger = None
   if delta_s > threshold_s:
      preamble = 'time_complain: '
      logger = log.warning
   elif at_least_debug:
      preamble = 'task '
      if info_threshold and (delta_s > info_threshold):
         logger = log.info
      elif (not debug_threshold) or (delta_s > debug_threshold):
         logger = log.debug
   if logger is not None:
      time_fmtd, scale, units = time_format_scaled(delta_s)
      logger('%s"%s" took %s' % (preamble, task_name, time_fmtd,))
   return (logger == log.warning)

#
def time_format_elapsed(time_then):
   return time_format_scaled(time.time() - time_then)[0]

#
def time_format_scaled(time_amt):

   if time_amt > (60 * 60 * 24 * 365.25): # s * m * h * 365 = years
      units = 'years'
      scale = 60.0 * 60.0 * 24.0 * 365.25
   elif time_amt > (60 * 60 * 24 * 30.4375): # s * m * h * 30 = months
      units = 'months'
      scale = 60.0 * 60.0 * 24.0 * 30.4375
   elif time_amt > (60 * 60 * 24): # secs * mins * hours = days
      units = 'days'
      scale = 60.0 * 60.0 * 24.0
   elif time_amt > (60 * 60): # secs * mins = hours
      units = 'hours'
      scale = 60.0 * 60.0
   elif time_amt > 60:
      units = 'mins.'
      scale = 60.0
   else:
      units = 'secs.'
      scale = 1.0
   time_fmtd = '%.2f %s' % (time_amt / scale, units,)
   return time_fmtd, scale, units

#
def timestamp_age(db, tmstamp, other=None, calc_secs=False):
   '''Computes the age of a given timestamp against the current time,
      or against another timestamp. PSQL returns, e.g., "-03:22:34.724414",
      "10 years", "8 mons", "1 day", "23:59:00", but pyscopg2 converts it
      to a timedelta. Note the odd looking way that negatives are indicated:
         >>> datetime.timedelta(microseconds=-1)
         datetime.timedelta(-1, 86399, 999999)
      And here's an example of an event happening in 1 minute:
         >>> datetime.timedelta(minutes=1)
         datetime.timedelta(0, 60)
      If calc_secs is True, we'll figure out the number of seconds elapsed
      instead of fetching a timedelta.
       '''
   # NOTE: If you've started a transation session with the db connection,
   #       CURRENT_TIME is static and reflects the time when the transaction
   #       was started. That is, you can call CURRENT_TIME over and over again
   #       and it'll always return the same value.
   if not other:
      other = "CURRENT_TIMESTAMP"
   else:
      other = "'%s'::TIMESTAMP WITH TIME ZONE" % (other,)
   if not calc_secs:
      sql_tstamp_age = (
         "SELECT AGE('%s'::TIMESTAMP WITH TIME ZONE, %s) AS age"
         % (tmstamp, other,))
   else:
      sql_tstamp_age = (
         """
         SELECT (EXTRACT(EPOCH FROM '%s'::TIMESTAMP WITH TIME ZONE)
                 - EXTRACT(EPOCH FROM %s)) AS age
         """ % (tmstamp, other,))
   rows = db.sql(sql_tstamp_age)
   g.assurt(len(rows) == 1)
   ts_age = rows[0]['age']
   return ts_age

# ***

# 86400 secs in a day.
secs_in_a_day = 60.0 * 60.0 * 24.0
# 3600 secs in an hour.
secs_in_an_hour = 60.0 * 60.0
# 60 secs in a minute.
secs_in_a_minute = 60.0

#
def timestamp_age_est(tmdelta):

   # tmdelta is a datetime.timedelta object.
   try:
      tsecs = tmdelta.total_seconds()
   except AttributeError:
      # Python < 2.7. According to the documentation, similar to:
      tsecs = ((
         tmdelta.microseconds
         + (tmdelta.seconds + tmdelta.days * 24 * 3600) * 10**6) / 10**6)

   postfix = ''
   if tsecs < 0:
      postfix = ' ago'
      tsecs *= -1

   str_days = ''
   str_hours = ''
   str_mins = ''
   str_secs = ''
   remainder_secs = tsecs
   if remainder_secs > secs_in_a_day:
      # Using floor, since we'll show the remainder usings hours and mins/secs.
      num_days = math.floor(remainder_secs / secs_in_a_day)
      str_days = (
         '%d %s' % (num_days, Inflector.pluralize('day', num_days != 1),))
      remainder_secs -= (num_days * secs_in_a_day)
   #
   if remainder_secs > secs_in_an_hour:
      num_hours = math.floor(remainder_secs / secs_in_an_hour)
      str_hours = (
         '%d %s' % (num_hours, Inflector.pluralize('hour', num_hours != 1),))
      remainder_secs -= (num_hours * secs_in_an_hour)
   #
   if remainder_secs > secs_in_a_minute:
      # Using round, not floor, since we'll show seconds when under a minute.
      num_mins = round(remainder_secs / secs_in_a_minute)
      str_mins = (
         '%d %s' % (num_mins, Inflector.pluralize('minute', num_mins != 1),))
      remainder_secs -= (num_mins * secs_in_a_minute)
   #
   # We only show seconds if the total time is less than a minute; otherwise
   # we're content just to show days, hours, and minutes.
   if tsecs <= secs_in_a_minute:
      # This means str_days, str_hours, and str_mins are all unset.
      tsecs = abs(math.ceil(tsecs))
      str_secs = (
         '%d %s' % (tsecs, Inflector.pluralize('second', tsecs != 1),))

   # Assemble the friendly time delta.

   friendly = ''

   if str_secs:
      friendly = str_secs
   else:
      n_clauses = 0
      if str_days:
         friendly += str_days
         n_clauses += 1
      if str_hours:
         if friendly:
            if not str_mins:
               friendly += " and "
            else:
               friendly += ", "
         friendly += str_hours
         n_clauses += 1
      if str_mins:
         if friendly:
            if n_clauses == 1:
               friendly += " and "
            elif n_clauses == 2:
               friendly += ", and "
         friendly += str_mins
         n_clauses += 1

   friendly += postfix

   return friendly

# Regex to parse timezone offsets
RE_ts_offset = re.compile(r'^(?P<hour>[+-]\d\d)(?P<minute>\d\d)$')
#
def timestamp_parse(ts, offset=None):
   '''Parse ts, which is in the form "11/Jan/2009:09:04:12", and return a UNIX
      timestamp (integer seconds since the epoch). Assume that ts is in UTC,
      unless offset is given, in which case use that as the offset from UTC
      (e.g. CST is "-0600").'''
   t = time.mktime(time.strptime(ts, '%d/%b/%Y:%H:%M:%S'))
   if offset is not None:
      m = RE_ts_offset.search(offset)
      if m is None:
         raise Exception('invalid time zone offset %s' % (offset,))
      g.assurt(m.group('minute') == '00') # nonzero minute offsets unsupported
      # Convert the offset to second and apply it in the right direction.
      t += -1 * 3600 * int(m.group('hour'))
   return int(t)

#
def timestamp_tostring(t):
   return time.asctime(time.localtime(t)) + ' UTC'

# ***

#
def urllib2_urlopen_readall(url):
   # From the urllib docs, and also seems to apply to urllib2
   # (via testing with an echo server
   #   http://ilab.cs.byu.edu/python/socket/echoserver.html):
   # "One caveat: the read() method, if the size argument is omitted or
   #  negative, may not read until the end of the data stream; there is
   #  no good way to determine that the entire stream from a socket has
   #  been read in the general case." So use size and loop 'til done.
   resp_f = urllib2.urlopen(url)
   # WRONG: resp = resp_f.read(); Instead, specify a size and loop.
   resp_part = resp_f.read(size=8192)
   response = resp_part
   while resp_part:
      resp_part = resp_f.read(size=8192)
      response += resp_part
   return response

# ***

#
def xa_set(elem, attr, value):
   '''Set the attribute attr on Element elem to value, and be "smart": if
      value is a boolean, set as "0" or "1"; if value is None, do nothing;
      otherwise, set as the Python stringification of value.'''
   if value is not None:
      # BUG 1126 -- as_gpx() sets 'xmlns:xsi=asdf'
      #              and 'xsi:schemaLocation=asdf'
      #             When loading apache, it writes to
      #               /var/log/apache2/error.log:
      #             TagNameWarning: Tag names must not contain ':',
      #             lxml 2.0 will enforce well-formed tag names as
      #             required by the XML specification.
      if ':' in attr:
         # FIXME: Remove this code when you resolve Bug 1126. Or leave but
         #        also check if namespace if setup okay.
         #        See: ElementNamespaceClassLookup
         # DEVS: If you see this error, search the code for 'nsmap' and find
         # the correct usage of etree.Element().
         log.error('TagNameWarning: Tag names must not contain ":": %s=%s'
                   % (attr, value,))
         stack_lines = traceback.format_stack()
         stack_trace = '\r'.join(stack_lines)
         log.error('%s' % (stack_trace,))
      # 2012.09.29: The TagNameWarning happens on an old version of
      # lxml/Python, on itamae, but on newer versions, lxml throws a
      # ValueError.
      try:
         if isinstance(value, bool):
            elem.set(attr, str(int(value)))
         else:
            elem.set(attr, str(value))
      except ValueError:
         # We'll let this error slide so we don't crash the request, but this
         # is a programmer error, so log a message as such.
         log.error('xa_set: Tag namespace error: %s=%s' % (attr, value,))

# ***

# Progress_Bar is (well, was) used by tilecache_update.py when !quiet
class Progress_Bar(object):

   __slots__ = ('progress_max',
                'progress_cur',
                'progress_interval')

   PROGRESS_CHARS = 60

   #
   def __init__(self, progress_max):
      self.progress_cur = 0
      self.progress_interval = 0
      self.progress_max = progress_max
      sys.stdout.write(' %s]\b\b%s[' % (' ' * self.PROGRESS_CHARS,
                                        '\b' * self.PROGRESS_CHARS))
      sys.stdout.flush()

   #
   def inc(self, i=1):
      self.progress_cur += i
      ivl = int(1.0
                * self.PROGRESS_CHARS
                * self.progress_cur / self.progress_max)
      #print self.progress_cur, self.progress_interval, ivl
      if ivl > self.progress_interval:
         sys.stdout.write('.' * (ivl - self.progress_interval))
         sys.stdout.flush()
         self.progress_interval = ivl

   # ***

# ***

class Some_Test(object):

   #
   def __init__(self):
      '''2014.03.02: Tinkering with a new test framework.
      
      Just
         cd $cp/pyserver
         ./ccp.py -i
         from util_ import misc
         misc.Some_Test()
      '''

      ntdelta = 0
      for tdelta in [
         datetime.timedelta(microseconds=-1),
         datetime.timedelta(microseconds=-2),
         datetime.timedelta(minutes=1),
         datetime.timedelta(minutes=2),
         datetime.timedelta(minutes=1,seconds=22),
         datetime.timedelta(minutes=1,seconds=32),
         datetime.timedelta(days=15),
         datetime.timedelta(days=33),
         datetime.timedelta(days=2,hours=3,minutes=4,seconds=5),
         datetime.timedelta(days=2),
         datetime.timedelta(hours=3),
         datetime.timedelta(minutes=4),
         datetime.timedelta(seconds=5),
         datetime.timedelta(days=-2,hours=3,minutes=4,seconds=5),
         ]:

         friendly = timestamp_age_est(tdelta)
         log.info('test: timestamp_age_est: n %d: "%s"'
                  % (ntdelta, friendly,))
         ntdelta += 1

   # ***

# ***

if (__name__ == '__main__'):
   pass

