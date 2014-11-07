# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree

import conf
import g

from util_ import misc

log = g.log.getLogger('address')

class Address(object):

   __slots__ = (
      'text', # Full address.
      #
      'x',
      'y',
      'width', # if the bbox...
      'height', # if the bbox...
      #
      'street',
      'city',
      'county',
      'state',
      'country',
      'zip',
      #
      'gc_fulfiller', # I.e., Bing, MapQuest, Cyclopath, etc.
      'gc_confidence', # Confidence result might be what user is looking for.
      )

   def __init__(self, xml=None):
      self.text = None
      self.x = None
      self.y = None
      self.width = None
      self.height = None
      self.street = None
      self.city = None
      self.county = None
      #self.state = conf.state
      #self.state = conf.admin_district_primary[0]
      self.state = None
      self.zip = None
      #self.country = 'US'
      self.country = None
      self.gc_fulfiller = None
      self.gc_confidence = None
      if xml is not None:
         self.text = xml.get('addr_line')

   ## *** Instance methods

   #
   def as_xml(self):

      # SYNC_ME: gwis.command_.geocode.fetch_n_save 
      #          and item.util.address.as_xml

      elem = etree.Element('addr')

      misc.xa_set(elem, 'text', self.text)
      misc.xa_set(elem, 'x', self.x)
      misc.xa_set(elem, 'y', self.y)
      misc.xa_set(elem, 'width', self.width)
      misc.xa_set(elem, 'height', self.height)

      #misc.xa_set(elem, 'street', self.street)
      #misc.xa_set(elem, 'city', self.city)
      #misc.xa_set(elem, 'county', self.county)
      #misc.xa_set(elem, 'state', self.state)
      #misc.xa_set(elem, 'zip', self.zip)
      #misc.xa_set(elem, 'country', self.country)

      # BUG nnnn: Should flashclient use the entity type?
      misc.xa_set(elem, 'gc_fulfiller', self.gc_fulfiller)
      misc.xa_set(elem, 'gc_confidence', self.gc_confidence)

      return elem

   #
   def __str__(self):
      as_str = (
         'addr: %s / %s, %s, %s, %s / x,y: %s,%s / %s'
         % (self.text if self.text else '[no self.text]',
            self.street if self.street else '[no self.street]',
            self.city if self.city else '[no self.city]',
            self.state if self.state else '[no self.state]',
            self.zip if self.zip else '[no self.zip]',
            # Skipping: self.county, self.country
            ('%.2f' % self.x) if self.x else '-',
            ('%.2f' % self.y) if self.y else '-',
            'fulfllr: %s / cfdnc: %s'
             % (self.gc_fulfiller,
                self.gc_confidence,),
            ))
      return as_str

   # ***

# ***

