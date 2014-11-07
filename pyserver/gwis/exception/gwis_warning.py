# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree

import conf
import g

from util_ import misc

log = g.log.getLogger('gwis.warning')

class GWIS_Warning(Exception):
   '''An error which should be reported to the user (flashclient).'''

   __slots__ = (
      #'docs',
      'gerrs',
      'tag',
      )

   def __init__(self, message, tag=None, logger=log.warning):
      Exception.__init__(self, message)
      # EXPLAIN: How is tag used? What are its distinct values?
      self.tag = tag
      self.gerrs = []
      logger('GWIS_Exception caught: %s.' % (message,))

   # *** Public interface

   #
   # EXPLAIN: Why isn't this gwis_warning?
   #          Because all warnings are really errors?
   def as_xml(self, elem_name='gwis_error'):
      doc = etree.Element(elem_name)
      misc.xa_set(doc, 'msg', str(self))
      if self.tag is not None:
         misc.xa_set(doc, 'tag', self.tag)
      for gerr in self.gerrs:
         gerr.append_gml(doc, False)
      xml = etree.tostring(doc)
      return xml

# *** Unit test code

if __name__ == '__main__':
   print 'Testing Error()...'
   try:
      raise Error('escaping test: <>?&\'"')
   except Error, e:
      print e.as_xml()

