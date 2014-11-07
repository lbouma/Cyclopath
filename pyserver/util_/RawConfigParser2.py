# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import csv
from ConfigParser import NoOptionError
from ConfigParser import NoSectionError
from ConfigParser import RawConfigParser

# This RawConfigParser subclass adds getlist() and also option defaults.

class RawConfigParser2(RawConfigParser):

   #
   def get(self, section, option, default=None):
      val = default
      try:
         val = RawConfigParser.get(self, section, option)
      except NoOptionError, e:
         # NOTE: "None" cannot be the default.
         if default is None:
            raise
      except NoSectionError, e:
         # NOTE: "None" cannot be the default.
         if default is None:
            raise
      return val

   # The base class, RawConfigParser, lets the caller set defaults only on
   # object creation, or by setting self.defaults, a dict(). But this requires
   # either assembling all of the defaults for __init__, or setting them
   # individually before calling getboolean. This is tedious. So we allow a
   # default to be specified now. See /usr/lib64/python2.7/ConfigParser.py
   def getboolean(self, section, option, default=None):
      # default should be a string.
      #    _boolean_states = {
      #        '1': True, 'yes': True, 'true': True, 'on': True,
      #        '0': False, 'no': False, 'false': False, 'off': False}
      val = default
      try:
         val = RawConfigParser.getboolean(self, section, option)
      except NoOptionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      except NoSectionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      # This also works (it lets the parent class handle the default):
      #   if not isinstance (default, basestring):
      #      if default:
      #         default = 'yes'
      #      else:
      #         default = 'no'
      #   if default is not None:
      #      #self._defaults.update({option: default,})
      #      self.defaults().update({option: default,})
      #   return RawConfigParser.getboolean(self, section, option)
      return val

   #
   def getfloat(self, section, option, default=None):
      val = default
      try:
         val = RawConfigParser.getfloat(self, section, option)
      except NoOptionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      except NoSectionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      return val

   #
   def getint(self, section, option, default=None):
      val = default
      try:
         val = RawConfigParser.getint(self, section, option)
      except NoOptionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      except NoSectionError, e:
         # NOTE: None cannot be the default.
         if default is None:
            raise
      except ValueError, e:
         # Happens when the config option exists but is empty or
         # not an integer.
         raw = self.get(section, option)
         if (raw != '') or (default is None):
            raise
      return val

   #
   def getlist(self, section, option, default=None):
      '''Parse the option in the specified section as a comma-separated list
         of strings and return that list (or None if that option has no
         value). Example:

           state_aliases: SD, Sodak, "South Dakota"

         returns ['SD', 'Sodak', 'South Dakota'].

      '''
      val = default
      try:
         # See http://docs.python.org/release/2.5.2/lib/module-csv.html
         raw = self.get(section, option)
         if (raw == ''):
            # At least return an empty list. This happens when the user
            # specifies the option but without any values, e.g., "key:".
            val = []
         else:
            val = list(csv.reader([raw], skipinitialspace=True))[0]
      except NoOptionError, e:
         # NOTE: "None" cannot be the default.
         if default is None:
            raise
      except NoSectionError, e:
         # NOTE: "None" cannot be the default.
         if default is None:
            raise
      return val

   # ***

# ***

