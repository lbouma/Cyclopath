

# 2014.04.04: Delete this file. [lb] read it over and it looks deletable:
#             but maybe add a bug for searching routes by
#             min_length and max_length, and owner

# Copyright (c) 2006-2010 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME_2013_06_11: Parse this file before deleting it: there are some
#                   interesting things happening, it looks like.
#                   Consume whatever search features in here into 
#                   GWIS_Checkout, probably using query_filters.

# FIXME: route reactions. delete this file.
#        consume this file and use checkout instead, then
#        

# FIXME: route manip 2. this file is new.

# The SearchRoute request searches and returns a list of route metadata,
# so the route can be previewed without needing to load all of its geometry.

# e.g.:
#
# http://magnify.cs.umn.edu/wfs?&service=WFS&version=1.1.0&request=SearchRoute&
#   text=Hilly%20Midway
#   min_length=2.3
#   max_length=5.6
#   owner=username

from operator import attrgetter
import os
import re
import sys

import conf
import g

from gwis import command
from item.feat import route
from util_ import misc

log = g.log.getLogger('cmd.route_srch')

class Op_Handler(command.Op_Handler):

   __slots__ = (
      'text',
      #'min_length',
      #'max_length',
      #'owner',
      'search_user',
      'search_other',
      'offset',
      'count',
      'total',
      'routes',
      )

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)
      self.text = None
      #self.min_length = None
      #self.max_length = None
      #self.owner = None
      self.search_user = None
      self.search_other = None
      self.offset = None
      self.count = None
      self.total = None
      self.routes = None

   # ***

   #
   def __str__(self):
      selfie = (
         'route_search: text: %s / %s / %s / %s / %s / %s / %s'
         % (self.text,
            self.search_user,
            self.search_other,
            self.offset,
            self.count,
            self.total,
            self.routes,
            ))
      return selfie

   # *** GWIS Overrides

   #
   def decode_request(self):

      # The base class checks the user's credentials.
      command.Op_Handler.decode_request(self)

# FIXME: Offset and Count are in query_filters, aren't they?
      self.offset = int(self.decode_key('offset', 0))
      self.count = int(self.decode_key('count', 0))






this is... filter_by_text_smart?

      self.text = self.decode_key('text', False)
      # FIXME: These seems weird... how do we do bools elsewhere? As int?

this is filter_by_username

      self.search_user = (
         self.decode_key('search_user', False).lower() == 'true')

this is new

      self.search_other = (
         self.decode_key('search_other', False).lower() == 'true')

# FIXME: Try this instead: (but what about except ValueError?)
      self.search_user = bool(int(self.decode_key('search_user', 0)))
      self.search_other = bool(int(self.decode_key('search_other', 0)))

      as_gpx = bool(int(self.decode_key('asgpx', False)))

      #self.min_length = self.decode_key('min_length', False)
      #self.max_length = self.decode_key('max_length', False)
      #self.owner = self.decode_key('owner', False)

   #
   def fetch_n_save(self):

      # The base class just sets self.doc to the incoming XML document.
      command.Op_Handler.fetch_n_save(self)

      g.assurt(False) # route manip 2. FIXME: visibility and permission...

      if self.search_other:
         where_other = (
            """
            ((r.visibility = 1)
             AND ((r.permission = 1)
                  OR (r.permission = 2 AND r.owner_name <> %s)))
            """ % (self.req.db.quoted(self.req.client.username),))
      else:
         where_other = 'false'

# This gets routes that I created that are shared (public viewer routes, the 
# ones that were ignored by the last query) and all owner-visible routes, 
# meaning shared and private routes: private routes are in my library, and
# shared routes have a stealth_secret for them... so private routes have a GIA
# record for me, and shared routes have a GIA stealth record for the public...
      if self.search_user:
         where_user = (
            """
            ((r.owner_name IS NOT NULL)
             AND (r.owner_name = %s)
             AND ((r.visibility = 2 
                  OR (r.visibility = 1 AND r.permission = 2))))
             """ % (self.req.db.quoted(self.req.client.username),))
      else:
         where_user = 'false'

      where = ''
      if self.text is not None:
         tokens = tokenize(self.text)
         where = self.generate_text_match(['name', 'details',], tokens)
      else:
         tokens = None

# FIXME: route manip 2. process this brain dump.
      """
Is this two queries? two route.Many()s? -- NO, it is one query, but one of
                                           three possible queries.
solve: use gia to exclude items I own...
what are the route gia states:
   you/pub 
      stealth/empty -- you found route, in your session history, but not saved to library
      owner/empty -- in your library
      owner/stealth -- public can use stealth_secret to view
      owner/viewer -- public can view via route library
      empty/editor -- public can edit, you have no GIA record
BUG nnnn: Make stealth GIA for all old routes, and make button to show all
          'deleted' routes... they will not show normally because the session
          ID will not match. But a button could be activated... so stealth on
          the user-creator-private-user-group means user can see via a
          show-all-deleted button, and a stealth on the public means the
          stealth_secret works. So make sure public cannot trick pyserver into
          showing all forgotten routes: make sure you have a non-anon user.
search_other: empty/editor, empty/viewer, not owner/viewer
search_user: owner/viewer, owner/stealth, owner/empty
maybe in routes i have looked at: stealth/empty... and matches to routes_view.

So... search_other, search_user, and search_other + search_user...
search_other is simpler in CcpV2: 
   we do not have to worry about 'not owner/viewer', specifically
   that is, we can just do search_other using anon user, since 
   'not owner/viewer'... no, wrong wrong... we cannot use created_by,
   we have to see that there are only GIA records for the public and not for
   the user, since user has rights until route is made public...

GAR, THIS IS SO SIMPLE:
search_user + search_other is just a normal GIA search for all routes
search_user is using just private user group for GIA search
search_other is ... well, for usr_editor, pub_editor, there is always just one
  GIA record. so, for routes, there is sometimes a public record and a user
  record... but user always has better access? so you can search like 
  normal but then cull results... well, you could, but only acl_id is 
  returned in results, but not the GIA group ID... oh, no, I was thinking that
  we could order by user group ID first, but that would defeat branchy sql...
  no, wait, user group is always owner, but public would then be editor, i.e.,
  you can delete item but no longer change permissions! so... search_other
  without search_user mean search like normal but exclude acl_id better than
  editor...
  I think for search_other we can assume certain relationship between two GIA
  records and check the result row to cull... hmmm...
make a grid of acceptable states

=> select * from permissions;
    1 | public
    2 | shared
    3 | private
=> select * from visibility;
    1 | all
    2 | owner
    3 | noone

===========================================================================
||   user perms--> |  owner | editor | viewer | client | stealh |  empty ||
|| public perms--v |                                                     ||
|| --------------- | ------ | ------ | ------ | ------ | ------ | ------ ||
||          owner  |    n/a |    n/a |    n/a |    n/a |    n/a |    n/a ||
||         editor  |    n/a |    n/a |    n/a |    n/a |    n/a | 1-1 ok ||
||         viewer  | 2-1 ok |    n/a |    n/a |    n/a |    n/a |    n/a ||
||         client  | 2-2 ok |    n/a |    n/a |    n/a |    n/a |    n/a ||
||        stealth  | 2-2 ok |    n/a |    n/a |    n/a |    n/a | 2-3 ok ||
||          empty  | 3-2 ok |    n/a |    n/a |    n/a | 3-3 ok |    n/a ||
|| --------------- | ------ | ------ | ------ | ------ | ------ | ------ ||
|| * Not allowed: 1-2, 1-3, 3-1
missing: 2-3, and maybe duplicates of others
FIXME: 2-3 stealth/empty seems weird. check the database to understand better?
=====================================================


newly requested (and old-school, during v1->v2 upgrade) routes should have
stealth gia for user. make a checkbox to show routes a user has ever requested
and let user add these to library if they want.
so, in item_user_access, search for stealth & session Id (3-3)
                     and search for stealth & link hash Id (2-2)
      """


      # NOTE: these search options have been removed from the UI but
      # they may be added back in later


add these to query filters, and to route:

      #if (self.min_length is not None):
      #   where = '%s AND length(geometry) >= %f' % (where,
      #                                              float(self.min_length))
      #if (self.max_length is not None):
      #   where = '%s AND length(geometry) <= %f' % (where,
      #                                              float(self.max_length))
      #if (self.owner is not None):
      #   where = '%s AND owner_name = %s' % (where,
      #                                       self.req.db.quoted(self.owner))

# FIXME: Use route.py and one of the existing search_ or find_ fcns.
#        Most of this SQL is not needed -- we just need to incorporate where, 
#        where_user, and where_other.
# See also similar fcn. in route_history_get.
      sql = (
         """
         SELECT 
            id,
            name,
            details,
            created,
            valid_starting_rid,
            (SELECT name FROM route_stop rw
             WHERE rw.route_id = r.id AND rw.route_version = r.version
             ORDER BY stop_number ASC LIMIT 1) AS beg_addr,
            (SELECT name FROM route_stop rw
             WHERE rw.route_id = r.id AND rw.route_version = r.version
             ORDER BY stop_number DESC LIMIT 1) AS fin_addr,
            owner_name,
            permission,
            visibility,
            ST_Length(geometry) AS length

-- FIXME: Isn't this view expensive?
         FROM route_geo AS r

         WHERE
            NOT r.deleted
            AND r.valid_before_rid = %d
            AND (%s OR %s) %s
         """ % (conf.rid_inf,
                where_user,
                where_other,
                where,))

      # Assemble the qb from the request.
      qb = self.req.as_iqb(addons=False)

      rows = qb.db.sql(sql)
      routes = list()
      for row in rows:
         routes.append(route.One(qb, row=row))

# FIXME: Use full text search, and maybe just regular item_user_access
#        checkout (just use qb.filters.filter_by_text_*).
      routes.sort(cmp=route.One.cmp_fcn(tokens))
# FIXME: route reactions. Is this for pagination?
#                         get routes and then discard?
#                         we should do like discussions and fetch twice.
      self.total = len(routes)
      # Trim the results.
      last_index = self.offset + self.count
      self.routes = routes[self.offset:last_index]

   #
   def prepare_response(self):
      util.xa_set(self.doc, 'total', self.total)
      for rt in self.routes:
         rt.append_gml(self.doc)


# FIXME: Bug nnnn: Use Text Search here. Index yourself some tsvect_* cols.

   #
   def generate_text_match(self, columns, tokens):

      sql_where = ""

      # Check that there are usable tokens.
      if tokens:
         where = ""
         for column in columns:
            for t in tokens:
               match = ('(LOWER(%s) LIKE %s)'
                        % (column, 
                           self.req.db.quoted('%%%%%s%%%%' % t),))
               if where == '':
                  where = match
               else:
                  where = "%s OR %s" % (where, match)
         sql_where = " AND (%s)" % where

      return sql_where

   # *** Helper methods

   # EXPLAIN: Where is this list from? Should it be shared with normal search?
   #          Should it be stored in a string utility class? Or a search util
   #          class?
   # FIXME: Full Text Search, I think, already has a list of words like this?
   #        Or maybe I'm thinking of Ccp Search, which has another list of
   #        words it ignores (like short words...)...
   #        FIXME: Just find where this list comes from so you can reference
   #        the source, which will give more validity to this list.
   blacklist = ['the', 'and', 'are', 'has', 'this', 'that', 'in', 'on', 'of',
                'or', 'at', 'for', 'to', 'a', 'i']

   token_pattern = re.compile(r"([a-zA-Z0-9_\-']+)|\"([^\"]*)\"")

# FIXME: This doesn't belong here, or maybe not at all... what does [ft]'s
# search code do?
   #
   @staticmethod
   def tokenize(text):
      '''Return a list of tokens from text, where a token is a word or
         double-quoted substring and the word is not present in the blacklist
         and is not too short. The tokens are all lower-case.

         As an example, tokenize('This is testing a "GROUPED string") returns
           ['testing', 'grouped string']'''
      tuples = re.findall(Op_Handler.token_pattern, text.lower())
      tokens = list()
      for t in tuples:
         token = t[0] or t[1]
         if token not in Op_Handler.blacklist:
            tokens.append(token)
      return tokens

   # ***

   # 2014.05.14: [lb] moved these two staticmethod fcns -- cmp_fcn, and
   #             search_relevance -- from route.py to here just to clean
   #             up route.py. Also, we're got these searches re-implemented
   #             using qb.filters and psql full text search, so this is just
   #             for hanging onto until we finally re-implement searching
   #             routes like we search anything (ala search_map.py).
   #             Meaning: Test Searching Routes, Fix What's Broken,
   #                      And Then Delete This File.

   # *** Sorting fcns. for searching routes.

# FIXME: route manip. i think this can be deleted once full text search
#        is implemented.
# 2014.05.14: This is used by gwis/command_/route_search, which needs
#             to be reimplemented via qb.filters. It was part of route
#             reactions... or was it route manip? Either way
   #
   @staticmethod
   def cmp_fcn(tokens):

      def comparator(lhs_rt, rhs_rt):

         rel1 = lhs_rt.search_relevance(tokens)
         rel2 = rhs_rt.search_relevance(tokens)

         # First try ordering by relevance.
         if rel1 > rel2:
            comparison = -1
         elif rel2 > rel1:
            comparison = 1
         else:
            # The relevance is the same; try the newest revision first.
            if lhs_rt.valid_starting_rid > rhs_rt.valid_starting_rid:
               comparison = -1
            elif rhs_rt.valid_starting_rid > lhs_rt.valid_starting_rid:
               comparison = 1
            else:
               # In CcpV2, routes no longer get saved to a new revision. So,
               # finally, try the date_created timestamp.
               comparison = cmp(rhs_rt.created_date, lhs_rt.created_date)

         return comparison

      return comparator

# FIXME: route manip. i think this can be deleted once full text search
#        is implemented.
   #
   def search_relevance(self, tokens):
      if tokens:
         lower_name = None
         if self.name is not None:
            lower_name = self.name.lower()
         lower_details = None
         if self.details is not None:
            lower_details = self.details.lower()
         count = 0
         for t in tokens:
            if (lower_details is not None) and (t in lower_details):
               count = count + 1
            if (lower_name is not None) and (t in lower_name):
               count = count + 1
         # EXPLAIN: What algorithm is this? hits divided by twice the tokens?
         #          So if all tokens hit, relevance is one-half?
         relevance = float(count) / float(2 * len(tokens))
      else:
         relevance = 1.0
      return relevance

   # ***

# ***

