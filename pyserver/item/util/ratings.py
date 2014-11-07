# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import time

import conf
import g

from item.feat import branch
from item.util.item_type import Item_Type
from item.util import revision
from util_ import mem_usage
from util_ import misc

log = g.log.getLogger('ratings')

t_bonus = 1
t_penalty = 2
t_avoid = 3

# FIXME: Double-check this file's SQL for correctness and grac compliance

# BUG nnnn: Support quasi-revisioned ratings, so Historic route requests work
# with the old ratings. For now, we just load the Current ratings.

class Predictor(object):

   __slots__ = (
      # The graph for which we're supplying ratings, so we know the branch_hier
      # and revision.
      'graph',
      # Ratings, organized as ratings[byway_segment_id][username][branch_id]
      'ratings',
      # The timestamp of the last load operation, since ratings are stored by
      # timestamp.
      'last_updated',
      'last_last_modified', # temp var. used when updating
      # Historically, the ratings we get were always the current ratings. But
      # we have historic ratings, so if we're running an historic route finder,
      # maybe we don't want current ratings.
      'honor_historic',
      #
      # These are user for debugging.
      'rats_found',
      'rats_missing',
      )

   def __init__(self, graph):
      g.assurt(graph is not None)
      self.graph = graph
      self.ratings = dict()
      self.last_updated = None
      # BUG nnnn: Make honor_historic selectable for route analytics.
      self.honor_historic = False
      #
      self.rats_found = 0
      self.rats_missing = 0

   #
   def load(self, db, keep_running=None):

     # Load ratings from the database.

      t0_all = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      # Load all users' ratings and the generic ratings.

      g.assurt(self.graph.branch_hier)
      if len(self.graph.branch_hier) > 1:
         branch_ids = ','.join([str(x[0]) for x in self.graph.branch_hier])
         where_branch = "branch_id IN (%s)" % (branch_ids,)
      else:
         where_branch = "branch_id = %d" % (self.graph.branch_hier[0][0],)

      if not self.honor_historic:
         rats_sql = self.sql_current(db, where_branch)
      else:
         rats_sql = self.sql_historic(db, where_branch)

      if rats_sql:

         # Get and process all ratings

         log.info('load: reading byway_rating table...')
         time_0 = time.time()

         log.verbose('load: enabling dont_fetchall')
         db.dont_fetchall = True

         rats = db.sql(rats_sql)

         log.verbose('load: disabling dont_fetchall')
         db.dont_fetchall = False

         log.info('load: read %d ratings %s in %s'
            % (db.curs.rowcount,
               '[Current]' if not self.last_last_modified
                  else ('[since %s]' % self.last_last_modified),
               misc.time_format_elapsed(time_0),))

         g.check_keep_running(keep_running)

         self.cache_rats(db)

         db.curs_recycle()

         # Uncomment for remote debugging...
         #g.assurt(False)

         conf.debug_log_mem_usage(log, usage_0, 'ratings.load')

         log.info('load: done loading ratings in %s'
                  % (misc.time_format_elapsed(t0_all),))

      self.last_last_modified = None

   #
   def sql_current(self, db, where_branch):

      # Get most recent rating timestamp, so we can quickly update later.
      # We cast to text to prevent psycopg from eating the subsecond portion.

      res = db.sql("SELECT MAX(last_modified)::TEXT FROM byway_rating")
      last_modified = res[0]['max']
      g.assurt(last_modified)

      if last_modified == self.last_updated:

         log.debug('load_current: skippin: last_modified same as last_updated')

         rats_sql = None

      else:

         where_last_updated = ""
         if self.last_updated is not None:
            where_last_updated = ("AND (last_modified > '%s')"
                                  % (self.last_updated,))
         self.last_last_modified = self.last_updated
         self.last_updated = last_modified

         # Use a DISTINCT and ORDER BY so we only get one user rating per
         # user per byway, otherwise we'd get each user's rating for each
         # branch-byway they've rated.
         #
# FIXME: Is the reason the distinct is munged is because we're not DISTINCT ON?
         rats_sql = (
            """
            SELECT
               DISTINCT ON (byway_stack_id, username)
               byway_stack_id,
               username,
               branch_id,
               value
            FROM
               byway_rating
            WHERE
               %s
               %s
               AND (username !~ '^_'
                    OR username = '%s')
            ORDER BY
               byway_stack_id ASC,
               username ASC,
               branch_id DESC
            """ % (where_branch,
                   where_last_updated,
                   conf.generic_rater_username,))

      return rats_sql

   #
   def sql_historic(self, db, where_branch):

      # BUG nnnn: Implement.
      log.warning('sql_historic: this code is not tested!')

      # Use self.graph.revision to find a timestamp.

      g.assurt(isinstance(self.graph.revision, revision.Historic))
      res = db.sql("SELECT timestamp FROM revision WHERE id = %d"
                   % (self.graph.revision.rid,))
      last_modified = res[0]['timestamp']
      g.assurt(last_modified)

      self.last_updated = last_modified

      rats_sql = (
# FIXME: Is the reason the distinct is munged is because we're not DISTINCT ON?
         """
         SELECT
            DISTINCT ON (byway_stack_id, username)
            byway_stack_id,
            username,
            branch_id,
            value
         FROM
            byway_rating_event
         WHERE
            %s
            created <= '%s'
            AND (username !~ '^_'
                 OR username = '%s')
         ORDER BY
            byway_stack_id ASC,
            username ASC,
            branch_id DESC,
            created DESC
         """ % (where_branch,
                last_modified,
                conf.generic_rater_username,))

      return rats_sql

   #
   def cache_rats(self, db):

      #
      log.info('load: caching byway_rating table...')
      time_0 = time.time()

      generator = db.get_row_iter()
      for rat in generator:
         if (rat['value'] >= 0):
            sid = self.ratings.setdefault(rat['byway_stack_id'], dict())
            #sid['username'] = rat['value']
            uname = sid.setdefault(rat['username'], dict())
            uname[rat['branch_id']] = rat['value']
         else:
            try:
               #self.ratings[rat['byway_stack_id']].pop(rat['username'], None)
               #if not self.ratings[rat['byway_stack_id']]:
               #   self.ratings.pop(rat['byway_stack_id'], None)
               self.ratings[rat['byway_stack_id']] \
                           [rat['username']]       \
                           .pop(rat['branch_id'], None)
               if not self.ratings[rat['byway_stack_id']][rat['username']]:
                  self.ratings[rat['byway_stack_id']].pop(rat['username'],
                                                          None)
               if not self.ratings[rat['byway_stack_id']]:
                  self.ratings.pop(rat['byway_stack_id'], None)
            except KeyError:
               pass
      generator.close()

      log.info('load: cached ratings in %s'
               % (misc.time_format_elapsed(time_0),))

   #
   def rating_func(self, username, tagprefs, ccp_graph, rating_restrict=False):
      '''Return a closure which returns a bikeability rating given a
         route_step.One, appropriate for username (which can be None).'''
      self.rats_found = 0
      self.rats_missing = 0
      def f(byway_stack_id):
         try:
            brats = self.ratings[byway_stack_id]
            self.rats_found += 1
         except KeyError:
            #g.assurt(False)
            #log.warning('Byway ID %d is not rated.' % (byway_stack_id,))
            self.rats_missing += 1
            # MAGIC NUMBER: Return "avg" rating
            return 2.5
         try:
            # BUG nnnn: Support directional attrs and tags...
            byway_tags = ccp_graph.step_lookup_get(byway_stack_id).tagged
         except KeyError:
            # Bug nnnn/FIXME/2014.09.19: There's always a few dozen of these
            # that logcheck reports when the route daemons are restarted of
            # when gtfsdb_build_cache runs, so make this an info trace (to
            # spare logcheck verbosity) and fix this bug...
            log.info('Byway ID %d not found in graph!' % (byway_stack_id,))
            # MAGIC NUMBER: Return "avg" rating
            return 2.5
         # Get user's rating if it exists, else get the generic user rating.
         branch_vals = brats.get(username, None)
         if branch_vals is None:
            try:
               branch_vals = brats[conf.generic_rater_username]
            except KeyError:
               log.warning('rating_func: no rating for "%s"?!: by_stk_id: %s'
                           % (conf.generic_rater_username, byway_stack_id,))
               branch_vals = {} # { branch_id: value, }
               last_val = 2.5
         if not rating_restrict:
            # Use the leafiest rating, otherwise use a parent's.
            last_bid = None
            last_val = None
            for k,v in branch_vals.iteritems():
               if (not last_bid) or (k > last_bid):
                  last_bid = k
                  last_val = v
         else:
            # Only use the rating for the leaf branch, otherwise None.
            last_val = branch_vals.get(self.graph.branch_hier[0][0], None)
            if last_val is None:
               try:
                  last_val = brats[conf.generic_rater_username] \
                                  [self.graph.branch_hier[0][0]]
               except KeyError:
                  log.warning('rating_func: missing rating: brats[%s][%s]'
                              % (conf.generic_rater_username,
                                 self.graph.branch_hier[0][0],))
                  last_val = 2.5
         # Modify the user rating by the tag preferences.
         vals = [last_val,]
         for t in tagprefs:
            if t in byway_tags:
               if tagprefs[t] == t_bonus:
                  vals.append(5.0)
               elif tagprefs[t] == t_penalty:
                  vals.append(0.5)
               elif tagprefs[t] == t_avoid:
                  return 0.0
         return sum(vals) / len(vals)
      return f

   # ***

# ***

