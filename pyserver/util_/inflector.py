# Copyright (c) 2014-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# [lb] ported this file from Flex to Python.
# Original code is courtesy Derek Wischusen
# http://www.flexonrails.net/samples/inflector_example/srcview/index.html

# The Inflector class provides static methods for generating
# the plural or singular form of a given word.
#
# This class is essentially a direct port of the Inflector
# class in Rails (www.rubyonrails.org).

import re

class Inflector(object):

   #
   def __init__(self):
      assert(False) # Not instantiable.

   plurals = [
      [r'$', 's'],
      [r's$', 's'],
      [r'(ax|test)is$', '\\1es'],
      [r'(octop|vir)us$', '\\1i'],
      [r'(alias|status)$', '\\1es'],
      [r'(bu)s$', '\\1ses'],
      [r'(buffal|tomat)o$', '\\1oes'],
      [r'([ti])um$', '\\1a'],
      [r'sis$', 'ses'],
      [r'(?:([^f])fe|([lr])f)$', '\\1\\2ves'],
      [r'(hive)$', '\\1s'],
      [r'([^aeiouy]|qu)y$', '\\1ies'],
      [r'(x|ch|ss|sh)$', '\\1es'],
      [r'(matr|vert|ind)ix|ex$', '\\1ices'],
      [r'([m|l])ouse$', '\\1ice'],
      [r'^(ox)$', '\\1en'],
      [r'(quiz)$', '\\1zes'],
      # Added by [lb]:
      [r'^is$', 'are'],
      [r'^was$', 'were'],
      [r'^this$', 'these'],
      ]

   singulars = [
      [r's$', ''],
      [r'(n)ews$', '\\1ews'],
      [r'([ti])a$', '\\1um'],
      [r'((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)ses$', '\\1\\2sis'],
      [r'(^analy)ses$', '\\1sis'],
      [r'([^f])ves$', '\\1fe'],
      [r'(hive)s$', '\\1'],
      [r'(tive)s$', '\\1'],
      [r'([lr])ves$', '\\1f'],
      [r'([^aeiouy]|qu)ies$', '\\1y'],
      [r'(s)eries$', '\\1eries'],
      [r'(m)ovies$', '\\1ovie'],
      [r'(x|ch|ss|sh)es$', '\\1'],
      [r'([m|l])ice$', '\\1ouse'],
      [r'(bus)es$', '\\1'],
      [r'(o)es$', '\\1'],
      [r'(shoe)s$', '\\1'],
      [r'(cris|ax|test)es$', '\\1is'],
      [r'(octop|vir)i$', '\\1us'],
      [r'(alias|status)es$', '\\1'],
      [r'^(ox)en', '\\1'],
      [r'(vert|ind)ices$', '\\1ex'],
      [r'(matr)ices$', '\\1ix'],
      [r'(quiz)zes$', '\\1'],
      # Added by [lb]:
      [r'^are$', 'is'],
      [r'^were$', 'was'],
      [r'^these$', 'this'],
      ]

   irregulars = [
      ['person', 'people'],
      ['man', 'men'],
      ['child', 'children'],
      ['sex', 'sexes'],
      ['move', 'moves'],
      ]

   uncountable = [
      'equipment',
      'information',
      'rice',
      'money',
      'species',
      'series',
      'fish',
      'sheep',
      ]

   inited = False

   #
   @staticmethod
   def pluralize(singular='', conditional=False):

      try:
         is_uncountable = Inflector.uncountable.index(singular)
      except ValueError:
         is_uncountable = False

      pluralized = singular
      if conditional and (not is_uncountable):
         for item in Inflector.plurals:
            candidate = re.sub(item[0], item[1], singular)
            if candidate != singular:
               pluralized = candidate
               # Don't break; use last substitute result.

      return pluralized

   #
   @staticmethod
   def singularize(plural=''):

      singularized = plural
      try:
         is_uncountable = Inflector.uncountable.index(plural)
      except ValueError:
         for item in Inflector.singulars:
            candidate = re.sub(item[0], item[1], plural)
            if candidate != plural:
               singularized = candidate
               # Don't break; use last substitute result.

      return singularized;

   #
   @staticmethod
   def init():
      if not Inflector.inited:
         for irr in Inflector.irregulars:
            Inflector.plurals.append([irr[0], irr[1],])
            Inflector.singulars.append([irr[1], irr[0],])
         Inflector.inited = True

# This is a cheap way for a static class to initialize itself.
Inflector.init();

# ***

if (__name__ == '__main__'):
   pass

