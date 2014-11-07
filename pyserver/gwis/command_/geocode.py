# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The GetGeocode request geocodes addresses.
#
# FIXME Is this still accurate (ask lb, 20101106)
#
# Example input:
#
# <data>
#   <metadata>
#     <user name="reid" token="..."/>
#   </metadata>
#   <addrs>
#     <addr addr_line="200 union st se minneapolis"/>
#     <addr addr_line="CS Building"/>
#     <addr addr_line="600 washington minneapolis 55455"/>
#   </addrs>
# </data>
#
# Example output (the 3rd address is ambiguous):
#
# <data rid_max="2625" major="trunk">
#   <addr text="200 union st se minneapolis">
#     <addr x="481714.468433" y="4980088.29067"
#           text="200 Union St SE, Minneapolis, MN 55455-0167"/>
#   </addr>
#   <addr text="CS Building">
#     <addr x="481658.0" y="4980145.0"
#           text="CS Building"/>
#   </addr>
#   <addr text="600 washington minneapolis 55455">
#     <addr x="478234.176248" y="4981543.34118"
#           text="600 Washington Ave N, Minneapolis, MN 55401-1221"/>
#     <addr x="478257.788381" y="4981532.15195"
#           text="600 Washington Ave N, Minneapolis, MN 55401-1249"/>
#     <addr x="481840.503693" y="4980043.49628"
#           text="600 Washington Ave SE, Minneapolis, MN 55414-2916"/>
#     <addr x="479703.472517" y="4982482.75504"
#           text="600 Washington St NE, Minneapolis, MN 55413-2137"/>
#   </addr>
# </data>

from lxml import etree
import os
import sys
import urllib

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error 
from gwis.exception.gwis_warning import GWIS_Warning
from item.util import address
from item.util.address import Address
from item.util.item_type import Item_Type
from item.util.search_map import Search_Map
from util_ import misc

log = g.log.getLogger('cmd.geocode')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'addrs',
      'xml',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.addrs = None
      self.xml = None

   # ***

   #
   def __str__(self):
      selfie = (
         'geocode: addrs: %s'
         % (self.addrs,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.addrs = []
      # Bug 2797 - Pyserver: Missing payload triggers AttributeError
      # 2013.06.24: This has been failing for a while in CcpV1 production:
      #   AttributeError: 'NoneType' object has no attribute 'findall'
      #   POST /wfs?request=GetGeocode&addr=...&addr=...
      # The problem is that the payload is missing...
      try:
         for addr_xml in self.req.doc_in.findall('./addrs/addr'):
            self.addrs.append(addr_xml.get('addr_line'))
      except AttributeError, e:
         log.warning('Cannot decode geocode request: %s' % (str(e),))
      if not self.addrs:
         raise GWIS_Warning('Please specify at least one address to geocode.')

   #
   def fetch_n_save(self):

      command.Op_Handler.fetch_n_save(self)

      qb = self.req.as_iqb()

      for addr in self.addrs:

         addr_qb = None
         try:
            # Start with fresh qb for each addr, so that qb_filters is
            # fresh and so none of the temp tables pre-exist.
            addr_qb = qb.clone(skip_clauses=True, skip_filtport=True,
                               db_get_new=True)
            (result_gps, hit_count_text,) = self.addr_geocode(addr_qb, addr)
         finally:
            if (addr_qb is not None) and (addr_qb.db is not None):
               addr_qb.db.close()
               addr_qb.db = None

         # FIXME Better, I [reid] think, to _not_ throw an exception and let 
         #       flashclient deal with it (perhaps in Address_Choose.mxml)?
         #       But this is fine for now.
         self.raise_error_if_no_results(addr, result_gps)
         #
         # FIXME: This used to use Address().as_xml(), but the results from
         # addr_geocode are search results now. So maybe implement
         # gp_res.as_xml_addr()
         addr_xml = etree.Element('addr')

         # BUG nnnn: Android does not encode properly, e.g., raw '&'s in XML.
         # [lb] tried to work around the android bug by converting raw '&'s,
         #      but android expects the addr in our response to match the addr
         #      in the query... so we'd have to replace our corrected addr
         #      query with the original, incorrectly (un)encoded request here.
         #      If not (as the code is here, now) if we change the addr by
         #      fixing it, android will ignore the response and will send
         #      another request. And the cycle repeats itself....
         misc.xa_set(addr_xml, 'text', addr)

         # HACK: hit_count_text is used by the route finder to complain to the
         # user if too many userpoints of the same name were found.
         misc.xa_set(addr_xml, 'hit_count_text', hit_count_text)
         for gp_res in result_gps:
            # See the class: Search_Result_Geofeature.
            gf_res = gp_res.result_gfs[0]
            # SYNC_ME: gwis.command_.geocode.fetch_n_save 
            #          and item.util.address.as_xml
            res_xml = etree.Element('addr')
            # From Search_Result_Group:
            misc.xa_set(res_xml, 'text', gp_res.gf_name)
            misc.xa_set(res_xml, 'gc_id', gp_res.gc_fulfiller)
            misc.xa_set(res_xml, 'gc_ego', gp_res.gc_confidence)
            # From Search_Result_Geofeature:
            misc.xa_set(res_xml, 'x', gf_res.x)
            misc.xa_set(res_xml, 'y', gf_res.y)
            misc.xa_set(res_xml, 'width', gf_res.width)
            misc.xa_set(res_xml, 'height', gf_res.height)
            #
            addr_xml.append(res_xml)
         self.doc.append(addr_xml)

   #
   def addr_geocode(self, qb, addr):
      '''Geocodes addr and returns a list Address objects.'''

      # FIXME: Close this bug. regex is fine.
      # BUG 1789: Should we be outsourcing fulltext? Or at least the query
      #           parsing (shlex module? something else?).

      hit_count_text = ''
      results = []

      qb.filters.filter_by_text_smart = addr
      srcm = Search_Map(qb)
      # By default, Search_Map looks for all item types, but for route
      # requests, we'll just check waypoints and regions. We could look
      # for byways, too, but there would be lots of different groupings
      # and there's no easy way for the user to distinguish between them
      # using the route destination resolution popup.
      self.search_for = [
         # Nope: Item_Type.BYWAY,
         Item_Type.REGION,
         Item_Type.WAYPOINT,
         # Nope: Item_Type.TERRAIN,
         ]
      self.search_for_addresses = True
      self.search_for_except_waypoint = (
         [x for x in self.search_for if x != Item_Type.WAYPOINT])
      # By default, Search_Map also looks at tags and notes, but that's not
      # meaningful when searching for route destinations.
      self.search_in_attcs = [
         # Nope: Item_Type.TAG,
         # Nope: Item_Type.ANNOTATION,
         ]
      self.search_in_names = True

      # Setting qb.filters.pagin_count doesn't save us any processing.
      # This is because it's hard to support pagination for search, at least
      # how the database search is currently implemented. So we have to
      # artifically paginate, meaning Search_Map.search fetches all results
      # from the database or from the external geocoder and then trims the
      # results. So let's just grab one more record than we'll return to the
      # client to know if we should send the "found a lot of results" warning.
      # This also provides more code coverage, meaning more of our code is
      # needless executed, because now we're trimming the results twice,
      # once in srcm.search() and again in self.impose_hit_limit().
      qb.filters.pagin_count = conf.geocode_sql_limit + 1

      # 2014.06.13: Old comments:
      #   By default, Search_Map.search is not the quickest function: it'll
      #   parse the address and search on substrings within it. E.g., if we're
      #   searching "123 Main St S, Mpls", in addition to geocoding, we'll
      #   search the database for matches to "Main St", both in names and also
      #   in notes, etc. But flashclient pops up a dialog if we return multiple
      #   results, and 99 times out of 99 the user will probably choose a
      #   result from the external geocoder, so there's no reason to waste time
      #   looking for internal results and bugging the user to choose. (But we
      #   still might return more than one external result, since, e.g., '222
      #   hennepin mpls' hits twice, once on '222 hennepin' and then on '222
      #   hennepin e'.)  Therefore, short-circuit geocoding if the external
      #   result is found first.
      #     result_gps = srcm.search(short_circuit_if_external_results=True)
      # ... nowadays, we find all results and let client decide how to present.
      # (It's been too difficult not accidentally suppressing results, so
      #  find 'em all.)
      result_gps = srcm.search()

      # BUG nnnn/HACK ALERT: flashclient now supports all the results.
      #                      But for mobile we still send at most five
      #                      geocoded results. (In flashclient now, you
      #                      can see the results on the map; it used to
      #                      be that a modal dialog popped up, so you
      #                      couldn't see the geocoded results on the
      #                      map....)
      if self.req.client.request_is_mobile:
         (result_gps, hit_count_text,) = self.impose_hit_limit(result_gps)

      return (result_gps, hit_count_text,)

   #
   def impose_hit_limit(self, result_gps):
      # Limit results and alert user if we have more results than the client
      # GUI is setup to display.
      #
      # BUG nnnn: The client should just show all results, since we've already
      #           spent the time finding them all. Use a pageinator... and let
      #           the user see them on the map: just put a list below the
      #           destination?
      hit_count_text = ''
      if len(result_gps) > conf.geocode_hit_limit:
         hit_count_text = 'Note: '
         if len(result_gps) <= conf.geocode_sql_limit:
            hit_count_text += str(len(result_gps))
         else:
            hit_count_text += 'More than ' + str(conf.geocode_sql_limit)
         hit_count_text += (
            ' locations were found, but only %s '
            'are shown. If the location you are looking '
            'for is not shown, be more specific or use more words.' 
            % (conf.geocode_hit_limit,))
      return (result_gps[:conf.geocode_hit_limit], hit_count_text,)

   #
   def raise_error_if_no_results(self, addr, geocoded):
      if len(geocoded) == 0:
         if not self.req.client.request_is_mobile:
            error_text = (
               '%s. %s'
               % ('Could not find location',
                  'Please try a different address or search.',))
         else:
            error_text = (
               '%s: "%s". %s'
               % ('Could not find location',
                  addr,
                  'Please try a different address or search.',))
            # EXPLAIN Why does mobile need urllib encoding but not flashclient?
            error_text = urllib.quote(error_text)
         # 2014.08.13: Send logs to info to avoid logcheck emails.
         raise GWIS_Warning(error_text, logger=log.info)

   # ***

# ***

