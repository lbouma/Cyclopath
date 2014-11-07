# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import optparse
import time

import conf
import g

from gwis import query_viewport
from item import link_value
from item.feat import branch
from item.util import item_factory
from item.util import revision
from util_ import db_glue
from util_ import misc

if (__name__ == '__main__'):
   # NOTE A more robust unittest would use Python's built-in unittest class

   def ask_yesno(x):
      resp = raw_input('%%% ' + x + ' (y/n) ')
      if (resp):
         resp = (resp.lower()[0] == 'y')
      else: # None or ''
         resp = False
      return resp

   #print('Testing user_item_access classes...')

   # py user_item_access.py -u landonb -t byway \
   #                        --start 10101 --until 10102 --new/--old/--static
   #                        --viewport xmin ymin xmax ymax

   db = db_glue.new()
   db.transaction_begin_rw()

   # Parse the args

   clopts = None
   usage = None
   op = optparse.OptionParser(usage)
   op.add_option('-u', '--username',
                 action='store', type='string', dest='username')
   op.add_option('-t', '--type', dest='item_type')
   op.add_option('-a', '--attc', dest='attc_type')
   op.add_option('-f', '--feat', dest='feat_type')
   op.add_option('-b', '--branch', type='int', dest='branch_id')
   #op.add_option(None, '--start', type='int', dest='valid_start_rid')
   #op.add_option(None, '--until', type='int', dest='valid_until_rid')
   #op.add_option('-n', '--new', action='store_true', dest='diff_new')
   #op.add_option('-o', '--old', action='store_true', dest='diff_old')
   #op.add_option('-s', '--static', action='store_true', dest='diff_static')
   op.add_option('-r', '--revision')
   #op.add_option('-v', '--viewport', type='float', nargs=4, dest='viewport')
   op.add_option('-v', '--viewport')
   op.add_option('-V', '--viewport_none', action='store_true')
   op.add_option('-q', '--quieter', action='store_true')
   op.set_defaults(
      username='_user_anon_minnesota',
      item_type='byway',
      branch_id=branch.Many.baseline_id(db),
      #valid_start_rid=None,
      #valid_start_rid=None,
      #diff_new=False,
      #diff_old=False,
      #diff_static=False,
      revision=None,
      viewport=None,
      quieter=False,
      )
   (clopts, args) = op.parse_args()

   items_fetched = item_factory.get_item_module(clopts.item_type).Many()

   if (not clopts.quieter):
      print('...checking revision')

   rev = None
   if (clopts.revision):
      rev = revision.Revision.revision_object_get(rev)
   else:
      rev = revision.Current()

   if (not clopts.quieter):
      print('...checking viewport')

   # NOTE Ignoring bbox_exclude
   vp = None
   areq = None
   req = gwis.request.Request(areq)
   if (clopts.viewport):
      bbox = clopts.viewport
      vp = query_viewport.Query_Viewport(req)
      vp.parse_strs(bbox, None)
   elif (not clopts.viewport_none):
      bbox = '483690,4978196,487454,4981236'
      vp = query_viewport.Query_Viewport(req)
      vp.parse_strs(bbox, None)

   # Make the branch_hier.
   branch_hier = branch.Many.branch_hier_build(db, clopts.branch_id, rev)

   if (not clopts.quieter):
      print('Fetching!')

   t0 = time.time()
   items_fetched.search_for_items(db, clopts.username, branch_hier, rev, vp)
   tdelta = time.time() - t0

   db.close()

   if (not clopts.quieter):
      print('\n')

   print('Found %d %ss in %s'
         % (len(items_fetched),
            clopts.item_type,
            misc.time_format_scaled(tdelta)[0],))

   if (not clopts.quieter):
      print('\n')

   if ((not clopts.quieter) and ask_yesno('See items?')):
      for item in items_fetched:
         print item

