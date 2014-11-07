# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import errno
import json
from lxml import etree
import pprint
import re
import sys
import traceback
import urllib
import urllib2

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.util import address
from planner.problem_base import Problem_Base
from util_ import geometry
from util_ import misc

log = g.log.getLogger('geocode')

class Geocode(object):

   __slots__ = ()

   def __init__(self):
      pass

   # ***

   # The error message template. For reporting errors.
   error_msg_template = (
      'Error contacting address translation service. '
      + 'Please try again in a few minutes. '
      + 'We are also looking into the problem.\n\n'
      + 'The specific error was: %s')

   # ** External geocoder fcns.

   # FIXME: Make files for each flavor? E.g., geocode_bing.py?

   # *** Geocoder: BING (the current geocoder, circa 2010-*)

   # Bug 1991 and 2118 and 2666 -- Intersections Issues
   # We get a Bing response, which looks like the following.
   #
   # <?xml version="1.0" encoding="utf-8"?>
   # <Response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   #           xmlns:xsd="http://www.w3.org/2001/XMLSchema"
   #           xmlns="http://schemas.microsoft.com/search/local/ws/rest/v1">
   #  <Copyright>Copyright (c) 2012 Microsoft and its suppliers. All rights
   #             reserved. This API cannot be accessed and the content and any
   #             results may not be used, reproduced or transmitted in any manner
   #             without express written permission from Microsoft Corporation.
   #   </Copyright>
   #  <BrandLogoUri>http://dev.virtualearth.net/Branding/logo_powered_by.png
   #   </BrandLogoUri>
   #  <StatusCode>200</StatusCode>
   #  <StatusDescription>OK</StatusDescription>
   #  <AuthenticationResultCode>ValidCredentials</AuthenticationResultCode>
   #  <TraceId>ab01baf0ea8a4ac1b328230ffee33675|CH1M001459|02.00.160.3000|
   #   CH1MSNVM001394, CH1MSNVM002951, CH1MSNVM004171</TraceId>
   #  <ResourceSets>
   #   <ResourceSet>
   #    <EstimatedTotal>1</EstimatedTotal>
   #    <Resources>
   #     <Location>
   #      <Name>W 40th St &amp; S Dupont Ave, Minneapolis, MN 55419</Name>
   #      <Point>
   #       <Latitude>44.912329986691475</Latitude>
   #       <Longitude>-93.293379843235016</Longitude>
   #      </Point>
   #      <BoundingBox>
   #       <SouthLatitude>44.908509871540652</SouthLatitude>
   #       <WestLongitude>-93.312127354100753</WestLongitude>
   #       <NorthLatitude>44.916235306682005</NorthLatitude>
   #       <EastLongitude>-93.297583339258622</EastLongitude>
   #      </BoundingBox>
   #      <EntityType>RoadIntersection</EntityType>
   #      <Address>
   #       <AddressLine>W 40th St &amp; S Dupont Ave</AddressLine>
   #       <AdminDistrict>MN</AdminDistrict>
   #       <AdminDistrict2>Hennepin Co.</AdminDistrict2>
   #       <CountryRegion>United States</CountryRegion>
   #      <FormattedAddress>W 40th St &amp; S Dupont Ave, Minneapolis, MN 55419
   #        </FormattedAddress>
   #       <Locality>Minneapolis</Locality>
   #       <PostalCode>55409</PostalCode>
   #      </Address>
   #      <Confidence>High</Confidence>
   #      <MatchCode>Good</MatchCode>
   #      <GeocodePoint>
   #       <Latitude>44.912329986691475</Latitude>
   #       <Longitude>-93.293379843235016</Longitude>
   #       <CalculationMethod>Interpolation</CalculationMethod>
   #       <UsageType>Display</UsageType>
   #       <UsageType>Route</UsageType>
   #      </GeocodePoint>
   #     </Location>
   #    </Resources>
   #   </ResourceSet>
   #  </ResourceSets>
   # </Response>

   # MAGIC_NUMBER: The Bing MAPS service uses SRID 4326.
   #
   # http://stackoverflow.com/questions/6708362/
   #     bing-maps-api-sql-geometry-vs-geography-type
   #  says SRID 3875 (which is not true)
   # http://social.msdn.microsoft.com/Forums/sqlserver/en-US/
   #    52556712-4cfc-4083-baa6-23e8045c5ec0/
   #    what-spatial-reference-system-should-i-use-for-with-
   #    virtual-earth-lat-long-values?forum=sqlspatial
   #  says SRID 4326 for Bing Maps (Virtual Earth)
   #   and SRID 3857 (Mercator) for displaying maps.
   #  Which [lb] thinks means, geocode results are SRID 4326,
   #  which is what we already have set...
   # NOTE: See conf.srid_latlon instead...
   #  bing_srid = 4326

   # Bing returns an entity type with the set of results, and some entity
   # types are uninteresting to us, like ShoppingCenter (if users want, they
   # can make a shopping center waypoint, but returning that as a geocoded
   # result seems... well, [lb] isn't quite sure... maybe we should add it
   # but rank it really low... and maybe put a friendly entity name in parans.

   # STYLE_GUIDE_LESSON: CcpV1 builds a similar entity_types lookup. There
   #  are two issues: it's built in the geocode fcn., rather than in the class,
   #  so it's possible that Python will rebuild it every time the fcn. is run,
   #  rather than just when the code is loaded and the class defition is read.
   #  Also, the lookup is a tuple, and tuples are basically static lists. For
   #  collections, the Python set and dict have the fastest lookup times;
   #  arrays and tuples, not so much, since they're ordered lists. So here
   #  we've moved the lookup to class-level (so Python builds the lookup
   #  when the code is loaded, and not when the fcn. is called), and we've
   #  also changed from a tuple to a set (to maybe improve performance; but
   #  regardless, it's good to be better).
   #     So rather than (), this should be set([]):
   #      bing_entity_types = (
   #      # These are the original CcpV1 entity types that CcpV1 accepted.
   #      # This is why geocoding intersections didn't work. But at
   #      # least for cities and counties, we'd just find the Cyclopath
   #      # region.
   #         'Address',
   #         'Postcode',
   #         'Postcode1',
   #         'Postcode2',
   #         'Postcode3',
   #         'Postcode4',)

   # For the list of entity names, see
   #  http://msdn.microsoft.com/en-us/library/ff728811.aspx
   #
   # See also: item/util/search_bing_entities.py.

   bing_entity_type_ranks = {

      'Address': 1,
      # 2012.09.13: This has been missing for a long time!
      #  Bugs 2666/2118/1991: Intersections not found.
      'RoadIntersection': 1,

      'Postcode': 2,
      'Postcode1': 2,
      'Postcode2': 2,
      'Postcode3': 2,
      'Postcode4': 2,

      # See bing_entity_ranks_address:
      #
      #   For the previous entity types, we'll assume the externally
      #   geocoded result is the exact result the user wants.
      #   * Caveat: If a Cyclopath item is named like a zip code,
      #             e.g., "55401", the geocoder won't bother looking
      #             for it, since it'll assume the Bing result is
      #             the perfect match.
      #
      # The following entity types will be shown alongside Cyclopath results:

      'PopulatedPlace': 3,
      'Neighborhood': 3,

      'AdminDivision1': 4,
      'AdminDivision2': 4,
      'AdminDivision3': 4,
      'AdministrativeDivision': 4,

# TEST: 123 rice st stp
      # RoadBlock is the center of a road that geocodes. E.g., Bing returns a
      # RoadBlock for '123 Rice St, St Paul', which is the road, 'Rice St, St
      # Paul'.  (So RoadBlock is not something blocking the road, but a road,
      # a/k/a a block... and not a census block, which is what traffic planners
      # always think of as a block.)
      'RoadBlock': 4,

      'Lake': 5,

      # MAYBE: Also include airports?
      'Airport': 6,
      # And since this is MN and there's no HockeyArena:
      'SkiArea': 6,

      # And then any Entity not listed explicitly is ranked 6.
      }
   # MAGIC_NUMBER: This is one more than the highest value in the lookup.
   bing_entity_rank_values = bing_entity_type_ranks.values()
   bing_entity_rank_values.sort()
   bing_lowest_entity_rank = bing_entity_rank_values[-1] + 1
   # MAGIC_NUMBER: Only these rank values are considered addresses that
   #               should be used by the route finder geocoder (which
   #               doesn't bother searching for internal results if
   #               the user is just looking for an address).
   bing_entity_ranks_address = set([1, 2,])

   # This is the match Confidence:
   #  http://msdn.microsoft.com/en-us/library/hh868068.aspx
   bing_gc_confidences = {
      'high': 1,
      'medium': 2,
      'low': 3,
      'unknown': 4,
      }
   
   #   # This is the match MatchCode:
   #   #  http://msdn.microsoft.com/en-us/library/hh868058.aspx
   #   bing_gc_match_codes = {
   #      # DEVS: These should be lowercased.
   #      'none': 10,       # No match found.
   #      'good': 1,        # Match was good.
   #      'ambiguous': 3,   # Match was ambiguous; multiple results returned.
   #      # Also known as upHierarchy and UpHierarchy...
   #      'uphierarchy': 3, # Match was found by a broader search.
   #      'modified': 3,    # Match found, but possibly using a modified query.
   #      }

   # ***

   @staticmethod
   def geocode_bing(addr):
      '''Geocode address using the Microsoft Bing Maps REST API.'''

      addr = Geocode.normalize_intersection_query(addr, ' and ')

      # Bing doesn't like colons.
      addr = addr.replace(':', ' ')

      bing_ns = 'http://schemas.microsoft.com/search/local/ws/rest/v1'
      url = ('http://dev.virtualearth.net/REST/v1/Locations/'
             + urllib.quote(addr.strip())
             + '?o=xml&key='
             + conf.bing_maps_id)
      log.debug('geocode_bing: %s / %s' % (addr.strip(), url,))

      resp = None
      try:
         resp = misc.urllib2_urlopen_readall(url)
         xml_in = etree.XML(resp)
         results = xml_in.findall('.//{%s}Location' % (bing_ns,))
      except IOError, e:
         # 2012.04.17: I [lb] was getting this error on the second geocode
         #             request (i.e., the first one worked). Problem
         #             eventually went away....
         # "[Errno socket error] [Errno -2] Name or service not known".
         # 2012.05.15: Having geocode problems agains...
         # We expect, e.g.,
         #   IOError: [Errno socket error] [Errno -2] Name or service not known
         # 2012.08.09: e.errno is a str, not an int, for 'socket error'.
         # 2012.08.09: This happens when pyserver cannot connect to external
         #             geocoder.
         # 2014.09.22: e.errno is None:
         #              <urlopen error [Errno 110] Connection timed out>
         if e[0] not in (errno.EAGAIN, errno.ETIMEDOUT,):
            log.error('unexpected errno! %s / %s' % (e.errno, str(e),))
         log.error('Error finding location: "%s" / %s\n%s\n%s'
                   % (str(e), traceback.format_exc(), url, resp,))
         # We could raise and completely fail, or we could try geocoding
         # to a Cyclopath point or region. This is useful for debugging,
         # e.g., if you're offline (say, at a cabin up north with no
         # internet, though I wouldn't advocate mixing coding with pleasure).
         #  Meh: raise GWIS_Error('Error finding location: %s' % (str(e),))
         results = []
         # MAYBE: If Cyclopath geocoding doesn't return any results, maybe
         #        then we could return a GWIS_Error. In the very least,
         #        logcheck will alert us to the problem.
      except Exception, e:
         # BUG 2715: Better errors: FIXME: Double-check all GWIS_Error and
         #           make sure we're not returning sensitive info. (I saw in
         #           one error that we were returning the call stack or
         #           something silly).
         log.error('Error finding location: "%s" / %s\n%s\n%s'
                   % (str(e), traceback.format_exc(), url, resp,))
         #raise GWIS_Error('Error finding location: %s' % (str(e),))
         raise GWIS_Error('Error finding location "%s"' % (addr,))

      log.debug('geocode_bing: received %d results' % (len(results),))

      geocoded = list()
      for result in results:

         addr_g = address.Address()

         addr_g.text = Geocode.xfind(result, 'Name', bing_ns).text
         # The Bing reply is Unicode but our GML is still just ASCII; if
         # we don't replace special characters, str() in xa_set throws
         # UnicodeEncodeError.
         # MAYBE/BUG nnnn: Change GML encoding to Unicode?
         addr_g.text = unicode(addr_g.text)
         addr_g.text = addr_g.text.encode('ascii', 'xmlcharrefreplace')

         if Geocode.xfind(result, 'AddressLine', bing_ns) is not None:
            addr_g.street = Geocode.xfind(result, 'AddressLine', bing_ns).text

         if Geocode.xfind(result, 'Locality', bing_ns) is not None:
            addr_g.city = Geocode.xfind(result, 'Locality', bing_ns).text

         if Geocode.xfind(result, 'AdminDistrict', bing_ns) is not None:
            addr_g.state = Geocode.xfind(result, 'AdminDistrict', bing_ns).text

         if Geocode.xfind(result, 'AdminDistrict2', bing_ns) is not None:
            addr_g.county = Geocode.xfind(
                  result, 'AdminDistrict2', bing_ns).text

         if Geocode.xfind(result, 'CountryRegion', bing_ns) is not None:
            addr_g.country = Geocode.xfind(
                  result, 'CountryRegion', bing_ns).text

         if Geocode.xfind(result, 'PostalCode', bing_ns) is not None:
            addr_g.zip = Geocode.xfind(result, 'PostalCode', bing_ns).text

         addr_g.y = float(Geocode.xfind(result, 'Latitude', bing_ns).text)
         addr_g.x = float(Geocode.xfind(result, 'Longitude', bing_ns).text)

         #confidence = Geocode.xfind(result, 'Confidence', bing_ns).text
         confidences = result.findall('.//{%s}Confidence' % (bing_ns,))
         if len(confidences) > 1:
            log.warning('geocode_bing: unexpected: confidences: %s'
                        % (confidences,))
         # Store the confidence as an integer,
         #  e.g., 1 (high), 2 (medium), 3 (low), or 4 (unknown).
         try:
            # Using pow(2, (1 to 4)/4.0) - 1.0: 0.1892, 0.4142, 0.6818, 1.0.
            addr_g.gc_confidence = pow(
               2, Geocode.bing_gc_confidences[
                   confidences[0].text.lower()]
                  / len(Geocode.bing_gc_confidences)) - 1.0
         except KeyError:
            log.warning('geocode_bing: unexpected: Confidence: %s'
                        % (confidences[0].text,))
            addr_g.gc_confidence = pow(
               2, Geocode.bing_gc_confidences['unknown']
                  / len(Geocode.bing_gc_confidences)) - 1.0
         # But we want to be in control of what's 100% confidence.
         addr_g.gc_confidence = min(max(addr_g.gc_confidence, 0.0), 0.9)
         entity_type = Geocode.xfind(result, 'EntityType', bing_ns).text
         try:
            entity_rank = Geocode.bing_entity_type_ranks[entity_type]
         except:
            entity_rank = Geocode.bing_lowest_entity_rank
         # We're 100% iff an addy, xsection, or zip code.
         # NOTE: The caller, search_map, will set confidence to 100
         #       if the user requested a city-state (e.g., 'mpls, mn').
         if entity_rank in Geocode.bing_entity_ranks_address:
            addr_g.gc_confidence = 100
         # FIXME/BUG nnnn: See comments in item.util.search_result, where
         # it sets confidence for internal geocode results: it's calculation
         # and the calculation we just performed here cannot be compared,
         # except when confidence is 100%, otherwise it's 80% confidence
         # is not our 80% confidence.

         # We don't need the MatchCode... confidence should be enough, and
         # other external geocoders may not have a comparable value.
         #
         #  match_codes = result.findall('.//{%s}MatchCode' % (bing_ns,))
         #  # Store the worst match code value, from 1 (good) to 10 (none).
         #  mc_val = 1
         #  for mcode in match_codes:
         #     try:
         #        mc_val = max(mc_val,
         #                     Geocode.bing_gc_match_codes[mcode.text.lower()])
         #     except KeyError:
         #        log.warning('geocode_bing: unxpctd: MatchCode: %s / addr: %s'
         #                    % (mcode.text, addr,))
         #        mc_val = Geocode.bing_gc_match_codes['none'] # 10
         #  addr_g.gc_match_code = mc_val

         addr_g.gc_fulfiller = 'bing'

         log.debug('geocode_bing: adding: %s' % (addr_g,))

         geocoded.append(addr_g)

      return geocoded

   # ***

   mapquest_confident_categories = set(['POINT',
                                        'ADDRESS',
                                        'INTERSECTION',
                                        'ZIP',
                                        'ZIP_EXTENDED',])

   # Oops, an arithmetic progression... should be okay...? =)
   mapquest_confidence_lookup = {'A': 90, # 'Exact'
                                 'B': 60, # 'Good'
                                 'C': 30, # 'Approx'
                                 'X': 0,} #  N/a

   @staticmethod
   def geocode_mapquest(addr):
      '''Geocode address using the MapQuest Geocoder service..'''

      # CAVEAT: We cannot use MapQuest.
      # 2014.09.10: It's a violation of the MapQuest TOS to geocode only
      #             and not get a route or a map...

      # See: http://www.mapquestapi.com/geocoding/
      # Also: https://en.wikipedia.org/wiki/MapQuest

      # The MapQuest service uses a heliko to denote an intersection query.
      addr = Geocode.normalize_intersection_query(addr, ' @ ')

      # Note that we do not need to encode spaces for the request.
      # Also, we use other formats, e.g., 5-box address format: KVP Request:
      #   http://www.mapquestapi.com/geocoding/v1/address?key=YOUR_KEY_HERE
      #   &street=1090 N Charlotte St&city=Lancaster&state=PA&postalCode=17603
      # but we can just stick to using our well-formed address and hopefully
      # we'll get the same result as the 5-box query.
      url = ('%s?key=%s&location=%s'
             % ('http://www.mapquestapi.com/geocoding/v1/address',
                conf.mapquest_application_key,
                urllib.quote(addr.strip()),))

      resp = None
      try:
         resp = misc.urllib2_urlopen_readall(url)
         json_in = json.loads(resp)
      except IOError, e:
         if e[0] not in (errno.EAGAIN, errno.ETIMEDOUT,):
            log.error('unexpected errno! %s / %s' % (e.errno, str(e),))
         log.error('Error finding location: "%s" / %s\n%s\n%s'
                   % (str(e), traceback.format_exc(), url, resp,))
         json_in = None
      except ValueError, e:
         # 2014.09.07: Problems with truncated responses: json complains, e.g.:
         #    ValueError: Expecting , delimiter: line 1 column 252 (char 252)
         #    ValueError: Expecting object: line 1 column 252 (char 252)
         #             See above: This should be fixed?
         log.error('Error finding location/2: "%s" / %s\n%s\n%s'
                   % (str(e), traceback.format_exc(), url, resp,))
         json_in = None
      except Exception, e:
         log.error('Error finding location/1: "%s" / %s\n%s\n%s'
                   % (str(e), traceback.format_exc(), url, resp,))
         #raise GWIS_Error('Error finding location: %s' % (str(e),))
         #raise GWIS_Error(Problem_Base.error_msg_basic)
         # Just search internally... don't tell user we screwed up!
         json_in = None

      # >>> pprint.pprint(json_in)
      #
      # {'info': {'copyright': {
      #                 'imageAltText': '\\u00a9 2014 MapQuest, Inc.',
      #                 'imageUrl': 'http://api.mqcdn.com/res/mqlogo.gif',
      #                 'text': '\\u00a9 2014 MapQuest, Inc.'},
      #           'messages': [],
      #           'statuscode': 0},
      #  'options': {'ignoreLatLngInput': False,
      #              'maxResults': -1,
      #              'thumbMaps': True},
      #  'results': [{'locations': [{
      #                 'adminArea1': 'US',
      #                 'adminArea1Type': 'Country',
      #                 'adminArea3': 'MN',
      #                 'adminArea3Type': 'State',
      #                 'adminArea4': 'Hennepin',
      #                 'adminArea4Type': 'County',
      #                 'adminArea5': 'Minneapolis',
      #                 'adminArea5Type': 'City',
      #                 'displayLatLng': {'lat': 44.911173,
      #                                   'lng': -93.293729},
      #                 'dragPoint': False,
      #                 'geocodeQuality': 'POINT',
      #                 'geocodeQualityCode': 'P1AAA',
      #                 'latLng': {'lat': 44.91117, 'lng': -93.29337},
      #                 'linkId': '278400000305781',
      #                 'mapUrl':
      #                    'http://www.mapquestapi.com/staticmap/v4/getmap?
      #                       key=OUR_KEY&
      #                       type=map&
      #                       size=225,160&
      #                       pois=purple-1,44.91117,-93.29337,0,0,|&
      #                       center=44.91117,-93.29337&
      #                       zoom=15&
      #                       rand=871890857',
      #                 'postalCode': '55419-1150',
      #                 'sideOfStreet': 'R',
      #                 'street': '5038 Dupont Ave S',
      #                 'type': 's',
      #                 'unknownInput': ''}],
      #               'providedLocation': {
      #                    'location': '5038 dupont ave s, minneapolis, mn'}}]}

      # Some differences using just the zip (for one, now 'Hennepin County'
      # and not just 'Hennepin'; also, why unicode all of a sudden?).
      #
      #   u'results': [{u'locations': [{
      #                    u'adminArea1': u'US',
      #                    u'adminArea1Type': u'Country',
      #                    u'adminArea3': u'MN',
      #                    u'adminArea3Type': u'State',
      #                    u'adminArea4': u'Hennepin County',
      #                    u'adminArea4Type': u'County',
      #                    u'adminArea5': u'Minneapolis',
      #                    u'adminArea5Type': u'City',
      #                    u'displayLatLng': {u'lat': 44.911395,
      #                                       u'lng': -93.293355},
      #                    u'dragPoint': False,
      #                    u'geocodeQuality': u'ZIP',
      #                    u'geocodeQualityCode': u'Z1XAA',
      #                    u'latLng': {u'lat': 44.911395,
      #                                u'lng': -93.293355},
      #                    u'linkId': u'328193748',
      #                    u'mapUrl': ...,
      #                    u'postalCode': u'55419-1150',
      #                    u'sideOfStreet': u'N',
      #                    u'street': u'',
      #                    u'type': u's',
      #                    u'unknownInput': u''}],
      #         u'providedLocation': {u'location': u'55419-1150'}}]}
      #
      # And with just 55419 you'll get the same except for lat/lon, and linkID:
      #                    u'displayLatLng': {u'lat': 44.905909,
      #                                       u'lng': -93.287431},
      #                    u'latLng': {u'lat': 44.905909,
      #                                u'lng': -93.287431},
      # I.e., geocodeQuality=='ZIP' and not 'ZIP_EXTENDED'.

      # And here's an intersection:
      #
      #  > v url
      #  b'http://www.mapquestapi.com/geocoding/v1/address?key=OUR_KEY
      #     &location=w 50th st @ dupont ave s, minneapolis, mn'
      #  > x resp_f = urllib.urlopen(url)
      #  Textual output will be done at the debuggee.
      #  > x resp = resp_f.read()
      #  Textual output will be done at the debuggee.
      #  > x json_in = json.loads(resp)
      #  Textual output will be done at the debuggee.
      #  > v json_in
      #  ... >>> pprint.pprint(jin)
      #   u'results': [{u'locations': [{
      #                    u'adminArea1': u'US',
      #                    u'adminArea1Type': u'Country',
      #                    u'adminArea3': u'MN',
      #                    u'adminArea3Type': u'State',
      #                    u'adminArea4': u'Hennepin',
      #                    u'adminArea4Type': u'County',
      #                    u'adminArea5': u'Minneapolis',
      #                    u'adminArea5Type': u'City',
      #                    u'displayLatLng': {u'lat': 44.912317,
      #                                       u'lng': -93.293372},
      #                    u'dragPoint': False,
      #                    u'geocodeQuality': u'INTERSECTION',
      #                    u'geocodeQualityCode': u'I1AAA',
      #                    u'latLng': {u'lat': 44.912317,
      #                                u'lng': -93.293372},
      #                    u'linkId': u'68394696r91787271s68394696r60407163',
      #                    u'mapUrl': ...,
      #                    u'postalCode': u'55419',
      #                    u'sideOfStreet': u'N',
      #                    u'street': u'W 50th St & Dupont Ave S',
      #                    u'type': u's',
      #                    u'unknownInput': u''}],
      #         u'providedLocation': {
      #           u'location': u'w 50th st @ dupont ave s, minneapolis, mn'}}]}

      geocoded = list()

      if json_in:

         try:
            geocoded = Geocode.geocode_mapquest_process(json_in, geocoded)
         except Exception, e:
            # 2014.09.06: [lb] sees this with the query, "work". Not an error.
            log.debug('geocode_mapquest: no beuno: addr: %s / json_in: %s'
                      % (addr, pprint.pprint(json_in),))
            # Naw...: raise GWIS_Error(Problem_Base.error_msg_basic)
            #   Instead, just continue along and search internally.

      return geocoded

   #
   @staticmethod
   def geocode_mapquest_process(json_in, geocoded):

      # We only sent one address (i.e., not a bulk query) so 'results' will
      # have length of 0 or 1, and 'locations' within it might have many.
      g.assurt_soft(len(json_in['results']) <= 1)

      log.debug('geocode_mapquest_proc: received %s results'
                % (str(len(json_in['results'][0]['locations']))
                   if json_in['results'] else 'zero',))

      for matches in json_in['results']:
         for result in matches['locations']:

            addr_g = address.Address()

            addr_g.text = ', '.join(
               [x for x in [result['street'], # House/Street or Xsct
                            result['adminArea5'], # City
                            result['adminArea3'], # State
                            result['postalCode'],] # ZIP(r)
                if x])

            # MAYBE: This includes house number or intersection... should be
            #        fine?
            addr_g.street = result['street']

            addr_g.city = result['adminArea5']
            g.assurt_soft(result['adminArea5Type'] == 'City')

            addr_g.state = result['adminArea3']
            g.assurt_soft(result['adminArea3Type'] == 'State')

            addr_g.county = result['adminArea4']
            g.assurt_soft(result['adminArea4Type'] == 'County')

            addr_g.country = result['adminArea1']
            g.assurt_soft(result['adminArea1Type'] == 'Country')

            addr_g.zip = result['postalCode']

            # EXPLAIN: Is there a difference btw. displayLatLng and latLng?
            addr_g.y = float(result['latLng']['lat'])
            addr_g.x = float(result['latLng']['lng'])

            # See: http://www.mapquestapi.com/geocoding/geocodequality.html
            if (result['geocodeQuality']
                in Geocode.mapquest_confident_categories):
               addr_g.gc_confidence = 100
            else:
               # From MapQuest docs: "The geocodeQualityCode value in a
               #   Geocode Response is a five character string which
               #   describes the quality of the geocoding results.
               #      Character Position 1 2 3 4 5
               #                   Value G S F A P
               #   where:      G = Granularity Code
               #               S = Granularity Sub-Code
               #               F = Full Street Name Confidence Level
               #               A = Administrative Area Confidence Level
               #               P = Postal Code Confidence Level
               #
               # We handle granularities (see mapquest_confident_categories)
               # and administrative and postal codes specially, so
               # all we want to check out is the full street confidence.
               # It's one of: 'A', 'B', 'C', 'X'.
               #   http://www.mapquestapi.com/geocoding/geocodequality.html
               # MAGIC_NUMBER: 2 is Full Street Name Confidence Level Index.
               #               That is, no street name confidence, 0 overall.
               try:
                  addr_g.gc_confidence = Geocode.mapquest_confidence_lookup[
                                             result['geocodeQualityCode'][2]]
               except Exception, e:
                  log.warning('geocode_mapquest_proc: what gQC?: %s / %s / %s'
                              % (result['geocodeQualityCode'][2],
                                 pprint.pprint(json_in),
                                 str(e),))
                  addr_g.gc_confidence = 0

            addr_g.gc_fulfiller = 'mapq'

            log.debug('geocode_mapquest_proc: adding: %s' % (addr_g,))

            geocoded.append(addr_g)

         # end: for result in matches['locations']
      # end: for matches in json_in['results']

      return geocoded

   ## *** Geocoder: MetroGIS (not used anymore)

   # FIXME: Currently obsolete due to addresses going back to one line.
   #        Must fix to use parser.
   @staticmethod
   def geocode_metrogis(addr):

      g.assurt(False) # Not used; not updated to CcpV2

      gis_ns = "http://www.metrogis.org/geocode"
      gml_ns = "http://www.opengis.net/gml"
      gis_url = "http://geoserver.state.mn.us/geocoder/geocode_response"
      hits_limit = conf.geocode_hit_limit

      # Have to split so that we can separate the address number.
      split_street = addr.street.split()
      split_street_mod = " ".join(split_street[1:len(split_street)])
      # FIXME: Is there a more efficient way to build this long string?
      url2 = (gis_url
              + "?methodName=GeocodeRequest&Version=1.1&CountryCode=US"
              + "&maximumResponses=" + str(hits_limit)
              + "&CompleteAddressNumber=" + urllib.quote(split_street[0])
              + "&CompleteStreetName=" + urllib.quote(split_street_mod)
              + "&PlaceName=" + urllib.quote(addr.city)
              + "&StateName=" + urllib.quote(addr.state)
              + "&ResponseFormat=XML")

      try:
         resp = misc.urllib2_urlopen_readall(url2)
      except Exception, e:
         log.error('Is this an error? %s / %s' % (str(e), resp_f,))
         raise GWIS_Error('Error finding location')
      xml_in = etree.XML(resp)
      #log.debug(etree.tostring(xml_in, pretty_print=True))
      results = xml_in.findall('.//{%s}GeocodedAddress' % (gis_ns))

      geocoded = list()
      for result in results:
         addr_g = address.Address()
         addr_g.text = Geocode.xfind(result, 'CompleteAddressNumber',
                                     gis_ns).text
         addr_g.text += ' ' + Geocode.xfind(result, 'StreetName', gis_ns).text
         temp_result = Geocode.xfind(result, 'PostType', gis_ns)
         if (temp_result is not None):
            addr_g.text += ' ' + temp_result.text
         temp_result = Geocode.xfind(result, 'PostDirectional', gis_ns)
         if (temp_result is not None):
            addr_g.text += ' ' + temp_result.text
         addr_g.street = addr_g.text
         addr_g.text += ', ' + Geocode.xfind(result, 'PlaceName', gis_ns).text
         addr_g.city = Geocode.xfind(result, 'PlaceName', gis_ns).text
         temp_result = Geocode.xfind(result, 'StateName', gis_ns)
         if (temp_result is not None):
            addr_g.text += ', ' + temp_result.text
         temp_result = Geocode.xfind(result, 'ZipCode', gis_ns)
         if (temp_result is not None):
            addr_g.text += ' ' + temp_result.text
            addr_g.zip = temp_result.text
         temp_result = Geocode.xfind(result, 'ZipPlus4', gis_ns)
         if (temp_result is not None):
            addr_g.text += '-' + temp_result.text
            addr_g.zip += '-' + temp_result.text
         latlon = Geocode.xfind(result, 'pos', gml_ns).text.split()
         addr_g.x = float(latlon[0])
         addr_g.y = float(latlon[1])
         addr_g.gc_fulfiller = 'mgis'
         geocoded.append(addr_g)

      return geocoded

   ## *** Geocoder: Microsoft (pre-Bing; not used anymore)

   @staticmethod
   def geocode_microsoft(addr_text):
      '''Parses and geocodes address, returning a list of address.Address
         objects with (x,y) in WGS84 latitute/longitude. Uses the Microsoft
         MapPoint service.'''
      g.assurt(False) # Not used; not updated to CcpV2
      results = None
      addr_words = len(addr_text.split(' '))
      i = 0
      while (i < addr_words):
         split_addr = addr_text.rsplit(' ',i)
         i += 1
         split_addr[0] += ","
         new_addr = " ".join(split_addr)
         parsed_addr = Geocode.geocode_microsoft_parse_try(new_addr)
         results = geocode_try_microsoft(parsed_addr)
         if (len(results) > 0):
            break
      return results

   @staticmethod
   def geocode_microsoft_file(log):
      ''' Utility for parsing list of addresses in a file. It currently just
          prints out addresses that the parser was not able to parse.'''
      g.assurt(False) # Not used; not updated to CcpV2
      f = open(log, 'r')
      for line in f:
         if line is not None:
            x = geocode_microsoft(line)
            if x == []:
               print line

   @staticmethod
   def geocode_microsoft_nohack(addr_text):
      '''Currently for testing purposes.  Parses and geocodes address without
      comma iteration, returning a list of address.Address objects with (x,y)
      in WGS84 latitute/longitude. Uses the Microsoft MapPoint service.'''
      g.assurt(False) # Not used; not updated to CcpV2
      results = None
      parsed_addr = Geocode.geocode_microsoft_parse_try(addr_text)
      results = geocode_try_microsoft(parsed_addr)
      return results

   @staticmethod
   def geocode_microsoft_parse_try(addr):
      '''Try to parse address using the Microsoft MapPoint service.'''

      mp_ns = "http://s.mappoint.net/mappoint-30/"
      mp_url = "http://findv3.staging.mappoint.net/Find-30/FindService.asmx"
      data = (
         '''
         <?xml version="1.0" encoding="UTF-8"?>
         <soap:Envelope
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
            xmlns:xsd="http://www.w3.org/2001/XMLSchema"
            soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
            xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Header>
               <UserInfoHeader xmlns="%(mp_ns)s">
                  <DefaultDistanceUnit>km</DefaultDistanceUnit>
               </UserInfoHeader>
            </soap:Header>
            <soap:Body>
               <ParseAddress xmlns="%(mp_ns)s">
                  <inputAddress></inputAddress>
                  <countryRegion>United States</countryRegion>
               </ParseAddress>
            </soap:Body>
         </soap:Envelope>
         ''' % locals())

      g.assurt(False) # Not used; not updated to CcpV2

      soap_out = etree.XML(data)

      Geocode.xfind(soap_out, 'inputAddress', mp_ns).text = addr

      req = urllib2.Request(mp_url)
      req.add_data(etree.tostring(soap_out, pretty_print=True))
      req.add_header('Content-Type',
                     'text/xml; charset=utf-8')
      req.add_header('SOAPAction',
                     'http://s.mappoint.net/mappoint-30/ParseAddress')
      auth = urllib2.HTTPDigestAuthHandler()
      auth.add_password('MapPoint',
                        'findv3.staging.mappoint.net',
                        conf.mappoint_user,
                        conf.mappoint_password)
      try:
         urllib2.install_opener(urllib2.build_opener(auth))
         resp = misc.urllib2_urlopen_readall(req)
      except urllib2.HTTPError, e:
         raise GWIS_Error(Geocode.error_msg_template % (str(e),))

      soap_in = etree.XML(resp)

      results = soap_in.findall('.//{%s}ParseAddressResult' % (mp_ns))

      result = address.Address()
      result.text = Geocode.xfind(results[0], 'AddressLine', mp_ns).text
      result.city = Geocode.xfind(results[0], 'PrimaryCity', mp_ns).text
      if result.city is None:
         result.city = ""
      result.state = Geocode.xfind(results[0], 'Subdivision', mp_ns).text
      if result.state is None:
         # This seems rather assumptious.
         result.state = conf.admin_district_primary[0]
      result.zip = Geocode.xfind(results[0], 'PostalCode', mp_ns).text
      if result.zip is None:
         result.zip = ""
      result.gc_fulfiller = 'mapp'

      return result

   @staticmethod
   def geocode_try_microsoft(addr):
      '''Geocode address using the Microsoft MapPoint service.'''

      g.assurt(False) # Not used; not updated to CcpV2

      mp_ns = "http://s.mappoint.net/mappoint-30/"
      # The .asm URL has been giving intermittent 404s, while the .asmx seems
      # to be OK. -- Reid 3/10/2009
      #mp_url = "http://findv3.staging.mappoint.net/Find-30/FindService.asm"
      mp_url = "http://findv3.staging.mappoint.net/Find-30/FindService.asmx"
      hits_limit = conf.geocode_hit_limit

      # Dummy SOAP XML payload. We parse this and fill in appropriate values.
      # NOTE: Leading return character causes HTTP 500
      data = (
         '''
         <?xml version="1.0" encoding="UTF-8"?>
         <soap:Envelope
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
            xmlns:xsd="http://www.w3.org/2001/XMLSchema"
            soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
            xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Header>
               <UserInfoHeader xmlns="%(mp_ns)s">
                  <DefaultDistanceUnit>km</DefaultDistanceUnit>
               </UserInfoHeader>
            </soap:Header>
            <soap:Body>
               <FindAddress xmlns="%(mp_ns)s">
                  <specification>
                     <DataSourceName>MapPoint.NA</DataSourceName>
                     <InputAddress>
                        <AddressLine/>
                        <PrimaryCity/>
                        <Subdivision/>
                        <PostalCode/>
                        <CountryRegion/>
                     </InputAddress>
                     <Options>
                        <ThresholdScore>0.85</ThresholdScore>
                        <Range>
                           <Count>%(hits_limit)d</Count>
                        </Range>
                     </Options>
                  </specification>
               </FindAddress>
            </soap:Body>
         </soap:Envelope>
         ''' % locals())

      soap_out = etree.XML(data)

      Geocode.xfind(soap_out, 'AddressLine', mp_ns).text = addr.text
      Geocode.xfind(soap_out, 'PrimaryCity', mp_ns).text = addr.city
      Geocode.xfind(soap_out, 'Subdivision', mp_ns).text = addr.state
      Geocode.xfind(soap_out, 'CountryRegion', mp_ns).text = "United States"
      Geocode.xfind(soap_out, 'PostalCode', mp_ns).text = addr.zip

      req = urllib2.Request(mp_url)
      req.add_data(etree.tostring(soap_out, pretty_print=True))
      req.add_header('Content-Type',
                     'text/xml; charset=utf-8')
      req.add_header('SOAPAction',
                     'http://s.mappoint.net/mappoint-30/FindAddress')
      auth = urllib2.HTTPDigestAuthHandler()
      auth.add_password('MapPoint',
                        'findv3.staging.mappoint.net',
                        conf.mappoint_user,
                        conf.mappoint_password)
      try:
         urllib2.install_opener(urllib2.build_opener(auth))
         resp = misc.urllib2_urlopen_readall(req)
      except urllib2.HTTPError, e:
         raise GWIS_Error(Geocode.error_msg_template % (str(e),))

      soap_in = etree.XML(resp)
      #log.debug(etree.tostring(soap_out, pretty_print=True))
      #log.debug(etree.tostring(soap_in, pretty_print=True))
      results = soap_in.findall('.//{%s}FindResult' % (mp_ns))

      geocoded = list()
      for result in results:
         addr_g = address.Address()
         addr_g.text = Geocode.xfind(result, 'DisplayName', mp_ns).text
         addr_g.street = Geocode.xfind(result, 'AddressLine', mp_ns).text
         addr_g.city = Geocode.xfind(result, 'PrimaryCity', mp_ns).text
         addr_g.zip = Geocode.xfind(result, 'PostalCode', mp_ns).text
         latlon = Geocode.xfind(result, 'LatLong', mp_ns)
         addr_g.x = float(latlon[1].text)
         addr_g.y = float(latlon[0].text)
         addr_g.gc_fulfiller = 'mapp'
         geocoded.append(addr_g)

      return geocoded

   ## *** Geocoder: Encoded point

   # FIXME: Test me: py ccp.py -s -q "P(123.456, 789.10)"
   @staticmethod
   def geocode_coordinate(query_text):
      '''e.g. "P(123.456, 789.10)"'''
      (coord_x, coord_y,) = (None, None,)
      coord_maybe = query_text.upper()
      point_re = r'\s*P\(\s*(?P<x>\d+\.?\d*)\s*,\s*(?P<y>\d+\.?\d*)\s*\)\s*'
      m = re.match(point_re, coord_maybe)
      if m is not None:
         coord_x = float(m.group('x'))
         coord_y = float(m.group('y'))

      return (coord_x, coord_y,)

   ## ***

   @staticmethod
   def normalize_intersection_query(addr, replacement_token):

      # FIXME: DRY this up. Use a list of '&', '@', ' and '.
      #        Although, the code is more readible just repeating ourselves.

      # BUG nnnn: Intelligenter searching.
      # E.g., If I search from "sea salt eatery"
      # to "w 50th st @ emerson ave s" then the latter should be assumed
      # to be in "mpls, mn". Without the 'city, state' assumption, the latter
      # destination is ambiguously geocoded.

      # Bug 2728 - Geocoder: Intersection Query fails with ampersand ('&').
      #            I.e., urllib.quote('&') == '%26' but addr isn't yet encoded.
      ampersand_cnt = addr.count('&')
      if ampersand_cnt:
         if ampersand_cnt > 1:
            log.warning('normlz_isectn_query: many ampersands: %s' % (addr,))
         addr = addr.replace('&', replacement_token, 1)
      # 2014.06.16: MapQuest only uses @s for intersection queries.
      # MAGIC_NAME: There are many names for the @ symbol: 'commercial at',
      #  'monkey tail', 'wrapped A', 'puppy', helix', 'snail', 'crazy A',
      #  ''little monkey', 'a badly written letter', enclosed A',
      #  'a little mouse', 'rollmops', and many, many more.
      #  https://en.wikipedia.org/wiki/At_sign#Names_in_other_languages
      # Let's just stick with Esperanto, shall we: 'heliko', or 'snail'.
      #  https://en.wiktionary.org/wiki/heliko
      #  http://reddwarf.wikia.com/wiki/Esperanto
      heliko_count = addr.count('@')
      if heliko_count:
         if heliko_count > 1:
            log.warning('normlz_isectn_query: many helikos: %s' % (addr,))
         addr = addr.replace('@', replacement_token, 1)
      #
      and_count = addr.count(' and ')
      if and_count:
         if and_count > 1:
            log.warning('normlz_isectn_query: many literal-ands: %s' % (addr,))
         addr = addr.replace(' and ', replacement_token, 1)

      return addr

   ## *** Geocoder: Consume externally-geocoded results

   # These are [lb]'s evolving notes of coverage_area.
   # NOTE: The coverage_area table has one row: it's name is "metro7". It's
   #       geometry's st_area is 7,703,678,473 meters^2. Which is 2,974 square
   #       miles. Wiki says Mpls/St. Paul is 6,364.12 total sq m., but that
   #       includes St. Cloud and two counties in Wisconsin.
   # 2012.08.23: The database or disk was corrupted in June, but the rebuild
   #             wasn't perfect. There were a few problems. On pg_restore,
   #             --disable-triggers was not used, so most tables' date
   #             fields all got set to 2012-06-07 16:33:16.359402-05. Also,
   #             the coverage_area table had duplicate entries, so we were
   #             getting errors: "ProgrammingError: ERROR: more than one row
   #             returned by a subquery used as an expression."
   # BUG nnnn: See 212-replace-coverage_area_.sql: We nixxed the
   #           coverage_area table and made it a branch attribute. Sillily,
   #           in CcpV1, coverage_area was set manually, but only once --
   #           there wasn't a note to keep it up to date nor did any code
   #           try. So in CcpV2, cron frequently triggers check_cache_now.sh
   #           which calls gen_tilecache_cfg.py which updates coverage_area.
   #           The code is better fit for revision.Revision.revision_save,
   #           but revision_save blocks the user client, so we shouldn't add
   #           more delay.
   # LASTLY PLEASE NOTE: This fcn. uses coverage_area of the latest revision.
   #                     It does not do historic(al) geocoding.

   @staticmethod
   def geocode_external(qb, results_latlon):

      g.assurt(False) # Not called.

      results_default = []

      for addr in results_latlon:
         rows = qb.db.sql(
            """
            SELECT
               ST_AsText(geom.g) AS xy
            FROM
               (SELECT
                  (ST_Transform(
                     ST_GeomFromEWKT(
                        'SRID=%(srid_latlon)d;POINT(%(x)f %(y)f)'),
                        %(srid_default)d)) AS g) AS geom
            WHERE
               ST_DWithin(
                  (SELECT coverage_area
                   FROM branch JOIN item_versioned USING (system_id)
                   WHERE
                     branch.stack_id = %(branch_sid)d
                     AND item_versioned.valid_until_rid = %(rid_inf)d),
                  geom.g,
                  %(buffer)d);

            """ % ({
               'x': addr.x,
               'y': addr.y,
               'srid_latlon': conf.srid_latlon,
               'srid_default': conf.default_srid,
               'branch_sid': qb.branch_hier[0][0],
               'rid_inf': conf.rid_inf,
               'buffer': conf.geocode_buffer}))
         if rows:
            wkt = rows[0]
            (x, y,) = geometry.wkt_point_to_xy(wkt['xy'])
            addr.x = x
            addr.y = y
            addr.gc_fulfiller = 'This fcn not called'
            results_default.append(addr)
         # else, the result from the geocode service is outside of our map, so
         #       we can safely ignore it (see Bug 1985)

      return results_default

   ## *** Helper methods

   @staticmethod
   def xfind(elem, name, ns):
      'Find an element, encapsulating namespace stuff.'
      return elem.find('.//{%s}%s' % (ns, name))

   # *** Geocoder implementation

   # Create a function geocode which is aliased to the geocoder we're currently
   # using.
   geocode = geocode_bing

   # ***

# *** Unit test code

if (__name__ == '__main__'):
   import sys
   print 'Geocoding "%s"' % (sys.argv[1])
   print geocode(sys.argv[1])

