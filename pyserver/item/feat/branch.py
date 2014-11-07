# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import hashlib
from lxml import etree
import os
import psycopg2
import sys
import traceback

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_base
from item import item_user_watching
from item import item_versioned
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

log = g.log.getLogger('branch')

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Default = 109

   Z_DEFAULT = 134

# BUG nnnn: Should this derive from geofeature? It does in flashclient. Which
# makes sense, since branches can be linked to attachments much like
# geofeatures. Which kinda just means that a branch shares the same GUI panels
# as geofeatures. But that's got nothing to do with geofeature-ness, since not
# all links have to be geofeature (think of a post linking to a revision).
# Also, we don't currently store branch info in the geofeature table, so we'd
# have to do something about that if we decided to derive from geofeature.
# So, like, what? Move this file up a level and make on par with attachment,
# geofeature, link_value, and grac_record? Smells funny to me...

class One(item_user_watching.One):

   item_type_id = Item_Type.BRANCH
   item_type_table = 'branch'
   item_gwis_abbrev = 'branch'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('parent_id',           None,   True,  False),
      ('last_merge_rid',      None,   True,  False,    int,     0),
      # MAYBE: This should be False by default, i.e., conflicts_exist
      ('conflicts_resolved',  True,   True,  False),
      ('is_public_basemap',   None,   True,   None),
      # NOTE: This are settable from ./ccp.py. We could make 'em settable from
      # flashclient, and branch permissions should make sure only basemap
      # owners can do so.
      ('import_callback',     None,  False,  False,    str,     0),
      ('export_callback',     None,  False,  False,    str,     0),
      ('tile_skins',          None,  False,  False,    str,     0),
      # Note send? is False but we send coverage_area via append_gml_geometry.
      ('coverage_area',       None,  False,  False,    str,  None),
      #
      # BUG nnnn: 2013.06.08: Move branch's default zoom and pan here?
      #           Maybe also 'guess' where the user is connecting from,
      #           and zoom to a particular city or region of the state?
      # E.g., from Conf_Instance.as
      #   map_zoom: 16,
      #   map_center_x: 480208,
      #   map_center_y: 4980957,
      #('map_zoom',            None,   True,  False,    int,     0),
      #('map_center_x',        None,   True,  False,    int,     0),
      #('map_center_y',        None,   True,  False,    int,     0),
      ]
   attr_defns = item_user_watching.One.attr_defns + local_defns
   psql_defns = item_user_watching.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt((row is None) or ('is_public_basemap' not in row))
      g.assurt(copy_from is None) # Not supported for this class.
      #self.geofeature_layer_id = Geofeature_Layer.Default
      item_user_watching.One.__init__(self, qb, row, req, copy_from)
      if (qb is not None) and (self.stack_id == Many.baseline_id(qb.db)):
         self.is_public_basemap = True

   # *** Built-in Function definitions

   #
   def __str__(self):
      return (
         ('%s | par_sid: %s / last_rid: %s / xflicts: %s '
          + '/ cbs: %s | %s / skin: %s / ca: %s')
         % (item_user_watching.One.__str__(self),
            self.parent_id,
            self.last_merge_rid,
            not self.conflicts_resolved,
            self.import_callback,
            self.export_callback,
            self.tile_skins,
            #self.coverage_area,
            'yes' if self.coverage_area else 'none',
            ))

   # *** GML/XML Processing

   # MAYBE: Should we derive from geofeature like the branch class does in
   #        flashclient? Here, we mimic geofeature very much somewhat.
   def append_gml(self, elem, need_digest, new=None, extra_attrs=None,
                        include_input_only_attrs=False):
      # C.f. geofeature.One.append_gml
      g.assurt(not new)
      if new is None:
         # NOTE This code CxPx from item_versioned.append_gml
         g.assurt(self.item_type_id != '')
         new = etree.Element(Item_Type.id_to_str(self.item_type_id))
      g.assurt(not need_digest)
      # MAYBE: geofeature.One sends self.attrs and self.tagged!
      #        So right now branches aren't attrable or taggeable.
      self.append_gml_geometry(new)
      return item_user_watching.One.append_gml(self, elem, need_digest, new,
                                       extra_attrs, include_input_only_attrs)

   #
   def append_gml_geometry(self, new):
      log.debug('append_gml_geometry: %s' % (str(self),))
      if not self.coverage_area:
         log.error('append_gml_geom: coverage_area not set: %s' % (str(self),))
      gml.append_Polygon(new, self.coverage_area)

   #
   def from_gml(self, qb, elem):
      item_user_watching.One.from_gml(self, qb, elem)
      # The user is allowed to create a branch that was last merged before
      # Current(), because that's how we roll.
      if (self.version != 0) and (self.last_merge_rid is not None):
         raise GWIS_Error('The attr last_merge_rid may only be set on create.')

   # *** Saving to the Database

   #
   def save_core(self, qb):
      item_user_watching.One.save_core(self, qb)
      # A branch's stack ID always the same as its branch ID (self-referential)
      g.assurt(self.stack_id == self.branch_id) # see save_core_get_branch_id
      # NOTE: We only honor create-branch and delete from local requests. From
      #       flashclient, we just support renaming.
      g.assurt(((self.version > 1) and not self.deleted)
               or qb.request_is_local)
      # NOTE: We've already verified the parent ID is valid. If the item is
      # fresh, we've checked that the user has permissions to make a copy of
      # the parent. If not, we've checked the user can edit the branch.
      if self.fresh:
         self.parent_id = qb.branch_hier[0][0]
      else:
         g.assurt((not self.parent_id)
                  or (self.parent_id == qb.branch_hier[1][0]))
      # The user is allowed to set self.last_merge_rid only once: when the
      # branch is created. Once the branch exists, the user can only change
      # last_merge_rid by performing an update.
      # 2013.04.04: And remember to use rid_new and not rid_max.
      if self.last_merge_rid is None:
         self.last_merge_rid = qb.item_mgr.rid_new
      else:
         # NO: Allow update: g.assurt(self.fresh and (self.version == 1))
         if ((self.last_merge_rid < 0)
             or (self.last_merge_rid > qb.item_mgr.rid_new)):
            raise GWIS_Error('last_merge_rid out-of-bounds: %d'
                             % (self.last_merge_rid,))
      # We fetch coverage_area as SVG (which is what all the append_* fcns.
      # expect), but PostGIS has no SVG import function (weird, [lb] thinks).
      # 2014.04.27: Rather than just repeat what's in the database for the
      #             prevision branch version (and maybe losing precision since
      #             we fetched coverage_area using conf.db_fetch_precision),
      #             we can recalculate it: see: commit.py calls
      #             byway.Many.branch_coverage_area_update.
      restore_carea = self.coverage_area
      if self.coverage_area.startswith('M '):
         # There's no geometry.svg_polygon_to_xy like there's a svg_line_to_xy,
         # so we use the geometry-type agnostic gml.flat_to_xys rather than
         # just filling in the blanks in geometry.py and writing such a fcn.
         # And this is a little ugly: we have to close the polygon ring, and
         # we have to make it a multipolygon for our geometry translation.
         # (Instead of this dance, we could, e.g.,
         #  ST_AsEWKT(br.coverage_area) AS coverage_area_wkt.)
         # Note that we fetched coverage_area using conf.db_fetch_precision,
         # so we've lost precision, so the caller should make sure to call
         # byway.Many.branch_coverage_area_update if they care (commit does).
         coverage_pgon = gml.flat_to_xys(self.coverage_area)
         coverage_pgon.append(coverage_pgon[0])
         self.coverage_area = geometry.xy_to_ewkt_polygon([coverage_pgon,],
                                         precision=conf.postgis_precision)
      self.save_insert(qb, One.item_type_table, One.psql_defns)
      # Restore the geometry to SVG (even though in practive save_core
      # is just used by commit, so the coverage_area is no longer needed,
      # and is about to be recomputed).
      self.coverage_area = restore_carea

   #
   def save_core_get_branch_id(self, qb):
      # The branch may or may not already be part of the qb.branch_hier.
      branch_hier_sids = [ x[0] for x in qb.branch_hier ]
      g.assurt((self.fresh) or (self.stack_id in branch_hier_sids))
      g.assurt((not self.fresh) or (not self.stack_id in branch_hier_sids))
      #
      return self.stack_id

   #
   def save_update(self, qb):
      g.assurt(False) # Not impl. for branch.
      item_user_watching.One.save_update(self, qb)
      self.save_insert(qb, One.item_type_table, One.psql_defns,
                       do_update=True)

   # *** Client ID Resolution

   #
   def stack_id_set(self, stack_id):
      g.assurt(stack_id is not None)
      # NOTE: We have to maintain branch_id because we're an item_versioned.
      item_user_watching.One.stack_id_set(self, stack_id)
      # A branch's branch ID is always set to itself.
      self.branch_id = self.stack_id

   # ***

   #
   def branch_groups_basename(self):
      if self.is_public_basemap:
         group_name = 'Basemap'
      else:
         group_name = self.name
      return group_name

   # ***

   #
   def get_skin_names(self):
      skin_names = []
      if self.tile_skins:
         skin_names = [x.strip() for x in self.tile_skins.split(',')]
      return skin_names

   # ***

# ***

class Many(item_user_watching.Many):

   one_class = One

   __slots__ = ()

   # ***

   sql_clauses_cols_all = item_user_watching.Many.sql_clauses_cols_all.clone()

   # 2013.05.11: [lb] adding coverage_area. There shouldn't be a performance
   # hit (so no need to make fertching this attribute optional) because
   # ST_AsSVG and ST_Scale run quickly.
   # EXPLAINED: Cyclopath historically converts from PostGIS Geometry to SVG
   #            and then makes its own special GWIS XML to send geometry to
   #            the client. [lb] isn't sure why this is so -- we often
   #            work with WKT (and now, EWKT) in pyserver because PostGIS
   #            does not support importing SVG geometry. (So, e.g., in order
   #            to save coverage_area if we've got is as SVG is to convert
   #            it to WKT.)
   # 2014.04.27: Note that we checkout using conf.db_fetch_precision (3)
   #             rather than conf.postgis_precision (15), so if you convert
   #             the SVG to WKT to save it back to the database, you'll lose
   #             precision -- not that we guarantee any precision better than
   #             one-tenth, or 1 decimeter, but ST_Area will return a different
   #             answer.
   sql_clauses_cols_all.inner.shared += (
      """
      , br.parent_id
      , br.last_merge_rid
      , br.conflicts_resolved
      , br.import_callback
      , br.export_callback
      , br.tile_skins
      , ST_AsSVG(ST_Scale(br.coverage_area, 1, -1, 1), 0, %d)
            AS coverage_area
      """ % (conf.db_fetch_precision,)
      )

   sql_clauses_cols_all.inner.join += (
      """
      JOIN branch AS br
         ON (gia.item_id = br.system_id)
      """
      )

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.parent_id
      , group_item.last_merge_rid
      , group_item.conflicts_resolved
      , group_item.import_callback
      , group_item.export_callback
      , group_item.tile_skins
      , group_item.coverage_area
      """
      )

   # ***

   baseline_id_ = None

   # *** Constructor

   def __init__(self):
      item_user_watching.Many.__init__(self)

   # *** Static convenience methods

   # Get the baseline ID.
   @staticmethod
   def baseline_id(db):
      if Many.baseline_id_ is None:
         if db is None:
            db = db_glue.new()
         else:
            # Clone the db, since we might be in a dont_fetchall fetch.
            db = db.clone()
            log.verbose1('baseline_id: disabling dont_fetchall')
            db.dont_fetchall = False
         # Get the branch ID of the public base map
         Many.baseline_id_ = int(db.sql(
            "SELECT cp_branch_baseline_id() AS bid")[0]['bid'])
         #log.debug('Many.baseline_id = %d' % (Many.baseline_id_,))
         g.assurt(Many.baseline_id_ > 0)
         db.close()
      return Many.baseline_id_

   # Get the public branch ID. Convenience method for baseline_id, since
   # "baseline" is probably less well understood than "public branch", even
   # though former is more correct and will be understood by people familiar
   # with source control, but latter seems more colloquial and appropriate
   # for Cyclopath.
   @staticmethod
   def public_branch_id(db):
      return Many.baseline_id(db)

   #
   @staticmethod
   def branch_id_from_branch_name(db, branch_name):
      # This script only finds current branches that have not been deleted.
      branch_id = None
      try:
         # FIXME: Instead of =, use LIKE %% so we can loosely match?
         rows = db.sql(
            """
            SELECT
               DISTINCT(br.stack_id)
            FROM
               branch AS br
            JOIN
               item_versioned AS br_iv
                  USING (system_id)
            WHERE
               br_iv.name = %s
               AND NOT br_iv.deleted
               AND br_iv.valid_until_rid = %s
            """, (branch_name,
                  conf.rid_inf,))
         if not rows:
            raise GWIS_Error('Branch "%s" is not recognized.' % (branch_name,))
         elif len(rows) != 1:
            raise GWIS_Error('Branch named "%s" not unique.' % (branch_name,))
         else:
            branch_id = int(rows[0]['stack_id'])
      except psycopg2.ProgrammingError, e:
         #raise GWIS_Error('Unanticipated SQL error: "%s" on branch "%s".'
         #                 % (str(e), branch_name,))
         g.assurt(False)
      return branch_id

   # This fcn. is used by scripts, but not by pyserver.
   @staticmethod
   def branch_id_resolve(db, branch_name_or_id, branch_hier_rev):
      # This fcn. takes a branch name or ID and returns a branch ID and maybe a
      # branch_hier.
      g.assurt(branch_hier_rev is not None)
      branch_id = None
      branch_hier = None
      if branch_name_or_id is not None:
         if not branch_name_or_id:
            # i.e., '' or 0
            branch_id = 0
         else:
            try:
               log.verbose('branch_name_or_id: %s' % (branch_name_or_id,))
               branch_id = int(branch_name_or_id)
            except ValueError:
               try:
                  # Raises on not matched, or > 1 match.
                  branch_id = Many.branch_id_from_branch_name(db,
                                                branch_name_or_id)
               except Exception, e:
                  # FIXME: Allow use of magic 'Public'?
                  log.error('Branch named "%s" not found in db or not unique.'
                            % (branch_name_or_id,))
                  branch_id = None
         if branch_id is not None:
            if not branch_id:
               # i.e., 0
               branch_id = Many.public_branch_id(db)
            try:
               # Note that we don't check the user's permissions on the branch,
               # since we might be adding new permissions, or a developer
               # script might be doing its thang, so it's up to the caller to
               # enforce permissions.
               branch_id = (
                  db.sql("SELECT stack_id FROM branch WHERE stack_id = %s",
                         (branch_id,))[0]['stack_id'])
               if branch_hier_rev is not None:
                  branch_hier = Many.branch_hier_build(db, branch_id,
                                                           branch_hier_rev)
               else:
                  g.assurt(False) # This code is not accessible.
                  branch_hier = [ (branch_id, branch_hier_rev, '', ), ]
            except Exception, e:
               log.error(
                  'Branch with stack_id %d not found in database at %s: %s'
                  % (branch_id, branch_hier_rev.short_name(), str(e),))
               branch_id = None
      return branch_id, branch_hier

   #
   @staticmethod
   def branch_hier_build(db, branch_id, mainline_rev, diff_group=None,
                                                      latter_group=None):
      # Build the branch hierarchy, which is a list of tuples. The first
      # element is the branch ID and the second is the last_merge revision ID.
      # The first branch ID is the leaf branch, then its parent, etc., and the
      # baseline is the last item in the list, i.e., branch_hier[0] is the
      # leaf branch ID and branch_hier[-1] is the baseline branch ID.
      g.assurt(branch_id)
      g.assurt(mainline_rev is not None)
      # The tuples indicate at which revision to fetch items from a branch.
      # So the last_merge_rid applies not to the self-same branch but to
      # its ascendant. We start with the leaf branch, which is descendantless.
      cur_branch_id = branch_id
      prev_last_merge_rid = None
      # Walk the hierarchy from leaf to root.
      branch_hier = []
      not_at_baseline = True
      latter_group_i = 0
      while not_at_baseline:
         # We set a limit on the length of branch hierarchies in the CONFIG.
         if len(branch_hier) > conf.max_parent_chain_len:
            log.warning('Leaf branch %d has very long parent chain'
                        % (branch_id))
            raise GWIS_Error('Branch hierarchy has too many generations.')
         # Each branch must be checked out at the relevant revision.
         # EXPLAIN: Link to the Wiki docs (and make the Wiki docs first).
         #          Explaining how to make the branch hier could use some
         #          graphics....
         if prev_last_merge_rid is None:
            if (   isinstance(mainline_rev, revision.Current)
                or isinstance(mainline_rev, revision.Historic)
                or isinstance(mainline_rev, revision.Comprehensive)):
               rev = mainline_rev
            else:
               if isinstance(mainline_rev, revision.Diff):
                  if (diff_group == 'latter') or (diff_group is None):
                     rev_id = mainline_rev.rid_new
                  elif diff_group == 'former':
                     rev_id = mainline_rev.rid_old
                  else:
                     g.assurt(False)
               elif isinstance(mainline_rev, revision.Updated):
                  rev_id = mainline_rev.rid_max
               else:
                  g.assurt(False)
               rev = revision.Historic(rev_id)
         else:
            rev = revision.Historic(prev_last_merge_rid)
         # Grab the parent branch id
         # DOCS: All calls to psycopg2's sql() must use %s and not %d.
         # FIXME: Rename parent_id 2 parent_stack_id, 2 conform to 'the others'
         # FIXME: I was doing db.sql("blah %s", rev.as_sql_where()) but I get
         #        unicode, and wrapping with str() didn't help:
         # 	   AND E'((iv.valid_until_rid = 2000000000)
         #            AND (NOT iv.deleted))'

         basic_sql = (
            """
            SELECT
                 iv.stack_id
               , iv.name
               , br.parent_id
               , br.last_merge_rid
            FROM
               branch AS br
            JOIN
               item_versioned as iv
                  USING (system_id)
            WHERE
               br.stack_id = %d
               AND %%s
            """ % (cur_branch_id,))

         br_sql = basic_sql % (rev.as_sql_where('iv'),)

         # 2014.08.19: Weird exception happening... but so far
         # just on test server?
         #  dump.20140813-12:25:48.456171_e3aa5_EXCEPT
         #  dump.20140816-18:44:21.885138_e3aa5_EXCEPT
         # 1 Traceback (most recent call last):
         # 2   File "/ccp/dev/cycloplan_test/pyserver/gwis/request.py",
         #                                   line 454, in process_req
         # 3     self.command_process_req()
         # 4   File "/ccp/dev/cycloplan_test/pyserver/gwis/request.py",
         #                                   line 513, in command_process_req
         # 5     self.decode_gwis()
         # 6   File "/ccp/dev/cycloplan_test/pyserver/gwis/request.py",
         #                                   line 799, in decode_gwis
         # 7     self.parts.decode_gwis()
         # 8   File "/ccp/dev/cycloplan_test/pyserver/gwis/request.py",
         #                                   line 62, in decode_gwis
         # 9     self.branch.decode_gwis()
         # 10   File "/ccp/dev/cycloplan_test/pyserver/gwis/query_branch.py",
         #                                   line 52, in decode_gwis
         # 11     self.req.revision.rev)
         # 12   File "/ccp/dev/cycloplan_test/pyserver/item/feat/branch.py",
         #                                   line 513, in branch_hier_build
         # 13     rows = db.sql(br_sql)
         # 14   File "/ccp/dev/cycloplan_test/pyserver/util_/db_glue.py",
         #                                   line 1321, in sql
         # 15     self.curs.execute(sql, parms)
         # 16 ProgrammingError: relation "branch" does not exist
         # 17 LINE 8:                branch AS br

         try:
            rows = db.sql(br_sql)
         except Exception, e:
            log.error('Unexcepted exception: %s' % (str(e),))
            log.error('br_sql: %s' % (br_sql,))
            raise

         if not rows:
            # This means the branch didn't exist at that revision, so just
            # run up the parent until we find a branch that does, and then
            # start the hierarchy from there.
            # EXPLAIN: When/Why does this happen?
            log.debug('Branch ID %d does not exist at %s'
                      % (cur_branch_id, mainline_rev.short_name(),))
            # We shouldn't have started to build the hier at this point.
            if branch_hier:
               log.error('branch_hier_build: parent br. %d missing at %s'
                         % (cur_branch_id, mainline_rev.short_name(),))
               g.assurt(False)
            # Note that if the user wants Current, the branch ID really d.n.e.
            if not isinstance(rev, revision.Current):
               g.assurt(isinstance(rev, revision.Historic))
               # Get the parent's branch ID using the first vers of the branch.
               par_sql = basic_sql % ('iv.version = 1',)
               rows = db.sql(par_sql)
            # Back up scope so we also raise on revision.Current.
            if not rows:
               raise GWIS_Error('Branch ID %d does not exist.'
                                % (cur_branch_id,))
            # Now we've got one row and rev is Historic.
            g.assurt(len(rows) == 1)
            # Setup the next iteration.
            #
            # [lb] isn't quite sure of the appropriate behavior here, but it
            # shouldn't really matter: if the requested revision is before the
            # first version's last_merge_rid, do we use last_merge_rid, or the
            # requsted rid (and show an earlier version of the parent)? Since
            # the branch did not exist at the requested revision, we can just
            # assume, if the branch existed, it was updated at every revision,
            # so just serve the parent branch at the requested revision.
            last_merge_rid = rows[0]['last_merge_rid']
            if last_merge_rid <= rev.rid:
               prev_last_merge_rid = last_merge_rid
            else:
               prev_last_merge_rid = rev.rid
            # NOTE: The convention is that a child branch's stack ID is always
            #       greater than its parent. This simplifies some of the SQL
            #       used with stacked branching.
            parent_id = rows[0]['parent_id']
            g.assurt(cur_branch_id > parent_id)
            cur_branch_id = parent_id
         else:
            g.assurt(len(rows) == 1)

            # Store the branch_hier tuple.
            brh_tup = (cur_branch_id, rev, rows[0]['name'],)

            log.verbose('  >> br. hier tup: (%d, %s, %s)'
                        % (brh_tup[0],
                           brh_tup[1].short_name(),
                           brh_tup[2],))
            branch_hier.append(brh_tup)

            # Setup the next iteration.
            prev_last_merge_rid = rows[0]['last_merge_rid']
            # NOTE: The convention is that a child branch's stack ID is always
            #       greater than its parent. This simplifies some of the SQL
            #       used with stacked branching.
            if rows[0]['parent_id']:
               g.assurt(cur_branch_id > rows[0]['parent_id'])
            cur_branch_id = rows[0]['parent_id']

         # If the cur_branch_id is now not something, it means we're done.
         if not cur_branch_id:
            not_at_baseline = False # Now we're not not at the baseline.

      log.verbose2('branch_hier_build: %s'
                   % (Many.branch_hier_pretty_print(branch_hier),))

      return branch_hier

   #
   @staticmethod
   def branch_hier_pretty_print(branch_hier):
      hier_txts = []
      for tup in branch_hier:
         hier_txts.append(('(%d, %s, %s)'
                          % (tup[0], tup[1].short_name(), tup[2])))
      hier_txt = ', '.join(hier_txts)
      return hier_txt

   # *** Base class overrides

   #
   def search_for_names(self, *args, **kwargs):
      # The user is searching for a list of branches, so make sure not to
      # filter by branch ID, lest you just find zero or one branches.
      qb = self.query_builderer(*args, **kwargs)
      # Don't restrict to basemap branch ID, otherwise you won't find anything.
      branch_hier_limit = qb.branch_hier_limit
      g.assurt(branch_hier_limit is None)
      # This is probably redundant now...
      qb.branch_hier_limit = 0
      #item_user_watching.Many.search_for_names(self, qb)
      #qb.sql_clauses = self.sql_clauses_cols_name.clone()
      # Client should be parent_id, and might as well send last_merge_rid and
      # conflicts_resolved.
      self.sql_clauses_cols_setup(qb)
      self.search_get_items(qb)
      qb.branch_hier_limit = branch_hier_limit

   #
   def search_get_sql(self, qb):
      '''Getting a leafier branch when requesting a particular branch doesn't
         make sense, so make sure we're not being called as such.'''
      g.assurt(not qb.confirm_leafiness)
      log.verbose('search_get_sql: br_hier: %s / hier_limit: %s'
                  % (qb.branch_hier, qb.branch_hier_limit,))
      branch_hier_limit = qb.branch_hier_limit
      # We used to require the caller to setup qb.branch_hier_limit, otherwise
      # our default was the normal item class default: filter by the branch in
      # the qb. But this is wrong: most callers want a list of branches, or
      # they want a specific branch (by stack ID), so we should almost never
      # filter by the branch specified in the qb.
      if qb.branch_hier_limit is None:
         # Find all branches (by ignoring whatever qb.branch_hier is).
         qb.branch_hier_limit = 0
      else:
         # We don't expect -1 (meaning basemap branch), but 0 or 1 is okay.
         g.assurt(branch_hier_limit in (0,1,))
      sql = item_user_watching.Many.search_get_sql(self, qb)
      qb.branch_hier_limit = branch_hier_limit
      return sql

   #
   @staticmethod
   def branch_enforce_permissions(qb, min_access):
      '''
      Check the user's rights to access the branch at the given revision ID.
      Since the user might belong to more than one group, uses min() to get the
      user's greatest level of access.
      '''

      log.verbose('branch_enforce_permissions: br_id: %d / rev: %s / min: %s'
                  % (qb.branch_hier[0][0], qb.revision, min_access,))

      access_level_id = None

      branch_many = Many()

      branch_many.search_by_stack_id(qb.branch_hier[0][0], qb)

      if len(branch_many) > 0:
         g.assurt(len(branch_many) == 1)
         log.verbose('branch_many: %s' % (branch_many,))
         access_level_id = branch_many[0].access_level_id
         log.verbose('access_level_id: %s' % (access_level_id,))

      if access_level_id is None:
         raise GWIS_Error('Insufficient privileges or unknown branch.')

      if (min_access is not None) and (min_access < access_level_id):
         raise GWIS_Error('Insufficient privileges or unknown branch.')

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      g.assurt(qb.viewport.include is None)
      return ""

   # ***

# ***

