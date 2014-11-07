# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from item.grac import group_revision
from util_ import gml
from util_ import misc

log = g.log.getLogger('cmd.rev_get')

# NOTE: This class could probably get consumber by, or be derived from, 
# grac_get, e.g., class Op_Handler(grac_get.Op_Handler). This works for now.
# 2014.05.09: Or, more accurately, this works for ever. The grac_get class
# is very generic- so much so that it takes a lot of effort to groc it.
# This class is probably easier to understand and maintain.

class Op_Handler(command.Op_Handler):

   # Max no. of revisions user can fetch with list of IDs.
   # Not really important enough to be moved to CONFIG.
   constraint_rids_max = 100

   __slots__ = (
      'rid_count', # total no. of revs that match the query (helpful if paging)
      'results', # private variable to hold results as XML etree
      )

   # BUG nnnn: revision_get and other commands will return all results unless
   # paginations specifically applied --> should maybe default to page 1 of 50
   # results so that we can't be DDOS'ed with route_get.

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      # 2014.05.13: We've always set filter_rev_enabled=True for this class,
      #             but [lb] checked group_revision and it looks like we
      #             use qb.filters.rev_* to fetch items, and not qb.revision...
      #             I only comment because I'm wiring the new revision
      #             class, Comprehensive, and I want to make sure it doesn't
      #             affect this command. Now I'm pretty sure it doesn't.
      self.filter_rev_enabled = True # Look for a revision ID
      self.filter_geo_enabled = True # Look for a bbox
      log.debug('revision_get: new')
      self.rid_count = None
      self.results = None

   # ***

   #
   def __str__(self):
      selfie = (
         'revision_get: rid_count: %s / results: %s'
         % (self.rid_count,
            self.results,))
      return selfie

   # *** 

   #
   def decode_request(self):
      log.debug('decode_request')
      command.Op_Handler.decode_request(self)
      g.assurt(self.req.branch.branch_id > 0)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)

      # NOTE: This command fetches a page of results and can also calculate the
      #       total results count in one fell swoop. The commit class, on the 
      #       other hand, forces callers to separate the two calls.
      # FIXME: Maybe commit should be more like this command, and do both at
      #        once.
      # Or, FIXME: Should this be how it works for item_user_access? Or should
      # this work like that? That is, should 'count' be returned with a list of
      # records, or should 'count' always be its own separate gwis request?

      qb = self.req.as_iqb()

      # Limit to just the leaf branch, so we only return its revisions.
      branch_hier_limit = qb.branch_hier_limit
      qb.branch_hier_limit = 1

      qb.use_filters_and_viewport = True

      if qb.filters.pagin_count:
         if qb.filters.pagin_count > conf.constraint_page_max:
            raise GWIS_Error('Count too large for item request (%s).'
                             % (self.item_type,))
         else:
            qb.use_limit_and_offset = True
      else:
         # It's, e.g., filter by revision ID, and filters.rev_ids is set.
         # See: query_filters.get_id_count(); this is similar. Also see
         #      commit.py, whence from we c.f. the gwis_errs.
         if len(qb.filters.rev_ids) == 0:
            raise GWIS_Error('Revision IDs missing from request (%s).'
                             % (self.item_type,))
         # MAGIC_NUMBER: conf.constraint_sids_max is large; when filtering by
         #               revision ID, let's do something reasonable, like 100?
         #               Currently, the user manually enters these numbers, so
         #               it doesn't need to be large.
         # elif len(qb.filters.rev_ids) > conf.constraint_sids_max:
         elif len(qb.filters.rev_ids) > Op_Handler.constraint_rids_max:
            raise GWIS_Error('Too many revision IDs in request (%s).' 
                             % (self.item_type,))

      self.fetch_n_save_impl(qb)

      qb.branch_hier_limit = branch_hier_limit

   #
   def fetch_n_save_impl(self, qb):

      grevs = group_revision.Many()

      grevs_sql_all = grevs.sql_context_user(qb)
      self.results = qb.db.table_to_dom('revision', grevs_sql_all)

      if qb.filters.pagin_total:
         
         qb.use_limit_and_offset = False
         grevs_sql_cnt = grevs.sql_context_user(qb)

         # Is this costly? Should it be cached?
         csql = (
            """
            SELECT 
               COUNT(grev.revision_id)
            FROM 
               (%s) AS grev
            WHERE 
               grev.revision_id != %d 
            """ % (grevs_sql_cnt, 
                   conf.rid_inf))

         self.rid_count = qb.db.sql(csql)[0]['count']

   #
   def prepare_response(self):

      if self.rid_count is not None:
         # Tell the user the complete number of revision that match their query
         misc.xa_set(self.results, 'total', self.rid_count)

      if self.req.filters.include_geosummary:
         # Remove each geosummary attribute and install in its place a
         # geosummary child element with a properly formatted coordinate list.
         for row in self.results:
            if row.get('geosummary'):
               g.assurt(row.get('geosummary')[:2] == 'M ')
               geosummary_child = etree.Element('geosummary')
               gml.append_MultiPolygon(geosummary_child, row.get('geosummary'))
               del row.attrib['geosummary']
               row.append(geosummary_child)

      self.doc.append(self.results)

   # ***

# ***

