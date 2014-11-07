# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Search request.
# Example output:
#
#<results query="stadium">
#  <result object_type="point"
#          text="Macalester Stadium"
#          distance="954455674.686"
#          name_match="1" tag_match="0" comment_match="0">
#    <object x="486718.0" y="4975770.0" id="1363631"/>
#  </result>
#  <result object_type="point"
#          text="Williams Arena"
#          distance="1673115887.17"
#          name_match="0" tag_match="1" comment_match="0">
#    <object x="482034.0" y="4980386.0" id="1363627"/>
#  </result>
#  <result object_type="byway"
#          text="Energy Park Dr"
#          distance="1812190880.51"
#          name_match="0" tag_match="0" comment_match="1">
#    <object x="484352.41" y="4980260.0" id="1003129" 
#            geometry="484158.82 4980339.29 484200.59 4980314"/>
#    <object x="484562.94" y="4980135.0" id="1357215" 
#            geometry="484468.56 4980205 484488.28 4980186 484532.75 
#                      4980151.5"/>
#    <object x="484695.56" y="4980106.5" id="1059434" 
#            geometry="484663.91 4980112 484677.81 4980109.5 484695.56 
#                      4980106.5"/>
#  </result>
#  <result object_type="point"
#          text="Apple Valley Johnny Cake Ridge Stadium"
#          distance="2027441784.19"
#          name_match="1" tag_match="0" comment_match="0">
#    <object x="485248.0" y="4954460.0" id="1419537"/>
#  </result>
#</results>

from lxml import etree
import os
import sys
import urllib

import conf
import g

from gwis import command
from item import geofeature
from item.util import search_map
from util_ import misc

log = g.log.getLogger('cmd.search')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'results',
      'gfs',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.results = None
      self.gfs = None

   # ***

   #
   def __str__(self):
      selfie = (
         'search: results: %s / gfs: %s'
         % (self.results,
            self.gfs,))
      return selfie

   # ***

   #
   def decode_request(self):
      command.Op_Handler.decode_request(self)
      self.results = None
      self.gfs = None

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      searcher = search_map.Search_Map(self.req.as_iqb())
      self.results = searcher.search()
      ## This is just a wrapper around a geofeature checkout
      #self.gfs = item.geofeature.Many()
      #self.gfs.search_by_full_text(self.req.as_iqb())

   #
   def prepare_response(self):
      results_xml = etree.Element('results')
      misc.xa_set(results_xml, 'ftxt', self.req.filters.filter_by_text_smart)
      # NOTE: revision_get does this instead of as_xml:
      #       self.results = qb.db.table_to_dom('revision', grevs_sql_all)
      for res in self.results:
         results_xml.append(res.as_xml())
      self.doc.append(results_xml)

   # ***

# ***

