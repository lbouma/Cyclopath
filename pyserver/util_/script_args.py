# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: This is a base class for Cyclopath command line scripts that want
# basic, boilerplate command line support for the most common settings.

# NOTE: Not all Ccp devs on Python >= 2.7, so import argparse
#       stealthfully.
try:
   import argparse
except ImportError:
   # This is argparse back-ported for Python < 2.7.
   from util_ import argparse

import os
import sys
import time

import conf
import g

from grax.user import User
from grax.item_manager import Item_Manager
from gwis.query_branch import Query_Branch
from gwis.query_overlord import Query_Overlord
from gwis.exception.gwis_error import GWIS_Error
from item.feat import branch
from item.grac import group
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_ import misc

log = g.log.getLogger('script_args')

# *** Cli arg. parser

class Ccp_Script_Args(argparse.ArgumentParser):

   # *** Class definitions.

   revdef_name = 0
   revdef_ctor = 1
   revdef_narg = 2
   # NOTE: Each CLI keyword in this list should start with a unique letter, or
   # you'll want to edit verify_revision_parts.
   revision_defns = (
      # CLI keyword, revision object, nargs,
      ('Current',    revision.Current,    1,),
      ('Historic',   revision.Historic,   2,),
      ('Diff',       revision.Diff,       3,),
      ('Updated',    revision.Updated,    3,),
      )

   # *** Constructor.

   __slots__ = (
      'script_name',
      'script_version',
      'cli_opts',
      'handled',
      'user_id',
      'branch_id',
      'branch_hier',
      'revision',
      'group_ids',
      'group_defs',
      'branch_use_hier',
      'rev_allow_deleted',
      'qb',
      'exclude_normal',
      )

   #
   def __init__(self, script_name, script_version, usage=None):
      argparse.ArgumentParser.__init__(self, description=script_name,
                                             usage=usage)
      self.script_name = script_name
      self.script_version = script_version
      self.cli_opts = None
      self.handled = False
      # We'll set these after parsing the arguments.
      self.user_id = 0
      self.branch_id = 0
      self.branch_hier = []
      self.revision = None
      #
      self.group_ids = ()
      self.group_defs = ()
      # Derived classes should override these as necessary.
      self.branch_use_hier = True
      self.rev_allow_deleted = False
      #
      self.exclude_normal = False
      #
      self.groups_none_use_public = False
      self.groups_expect_one = False
      #
      self.master_worker_expected = False

   # *** Main routine

   #
   def get_opts(self):
      self.prepare();
      self.parse();
      self.verify();
      g.assurt(self.cli_opts is not None)
      return self.cli_opts

   # *** Helpers: Define the arguments.

   # This class uses the CLI args: -v, -U, -P, -D, -b, -R, -m, -g

   #
   def prepare(self, exclude_normal=False):
      '''Defines the CLI options for this script'''

      # Script version.

      self.add_argument('-v', '--version', action='version',
         version='%s version %2s' % (self.script_name, self.script_version,))

      # *** HACK: In lieu of overriding argparse.ArgumentDefaultsHelpFormatter,
      #           making our own divider for when user prints --help.

      self.add_argument('--################', dest='script_specific1',
         action='store_true', default=False,
         help="###########################################")

      if not exclude_normal:
         self.prepare_normal()
      else:
         self.exclude_normal = True

   #
   def prepare_normal(self):

      # Username and password of user making request.

      self.add_argument('-U', '--username', dest='username',
         action='store', required=False, default='',
         help='the username of the user making this request')

      self.add_argument('-P', '--password', dest='password',
         action='store', required=False, default='',
         help='the password for --username')

      # NOTE: It's hard to convince apache and pyserver that we're on the same
      #       team with a password or token, so we use a shared secret by way
      #       of the CONFIG file.
      self.add_argument('--no-password', dest='password_skip',
         action='store_true', required=False, default=False,
         help='run as --username without a password (uses shared_secret)')

      # Branch name or ID.

      # Branch can be str or int, so don't specify type=.
      self.add_argument('-b', '--branch', dest='branch',
         action='store', required=False, default=[0,], nargs='+',
         help='the branch name or its stack ID')

      # Revision.

      # FIXME: Can I make this -r? Or maybe ./ccp.py -r[ead] is more important.
      # E.g., --revision Historic 1234, --revision hist 1234, etc.
      # (That is, you can used lowercase abbreviations if they're unique.)
      self.add_argument('-R', '--revision', dest='revision',
         action='store', required=False, default=None, nargs='+',
        help='revision: {curr, [hist] rid, d[iff] old new, u[pdated] min max}')

      self.add_argument('--revision_id', dest='revision_id',
         action='store', required=False, default=None, type=int,
         help='historical revision ID to load, or 0 for current revision')

      self.add_argument('--has-revision-lock', dest='has_revision_lock',
         action='store_true', required=False, default=False,
         help='indicates caller is allowed to commit; use with litemaint.sh')

      # Changenote for commit operations.

      self.add_argument('-m', '--message', '--changenote', dest='changenote',
         action='store', required=False, default=None,
         help='the commit operation changenote')

      # Group name or ID.

      if not self.groups_expect_one:
         group_nargs = "*"
         group_required = False
      else:
         group_nargs = 1
         group_required = True
      self.add_argument('-g', '--group', dest='group',
         action='store',
         required=group_required, default=[], nargs=group_nargs,
         help='the group name(s) and/or their stack ID(s)')

      # Database.

      self.add_argument('-D', '--database', dest='database',
         action='store', required=False, default='',
         help="alternative database to load, rather than CONFIG's")

      # Some scripts are daemonizable.

      # MAYBE: This argument only needed by routed and mr_do...
      self.add_argument('--no-daemon', dest='no_daemon',
         action='store_true', default=False,
         help='run this process in the background')

      # *** HACK: In lieu of overriding argparse.ArgumentDefaultsHelpFormatter,
      #           making our own divider for when user prints --help.

      self.add_argument('--#################', dest='script_specific2',
         action='store_true', default=False,
         help="###########################################")

      # Restrict to installation instance.

      self.add_argument('--instance', dest='ccp_instance',
         action='store', required=False, default='', type=str,
         help="restrict instance for scripts that use server_instances")

      # Asychronous database updates.

      # Limit the number of items we'll process. You could, e.g., determine
      # that there are 1,000,000 unique things to process, and you could run
      # this script four times asynchronously and process 250,000 with each.
      self.add_argument('--items-limit', dest='items_limit',
         action='store', type=int, default=0,
         help='limit number of nodes for populate_nodes')
      self.add_argument('--items-offset', dest='items_offset',
         action='store', type=int, default=0,
         help='offset to use when limiting number of nodes (0-based)')
      # In order to use LIMIT/OFFSET from multiple instances, you'll
      # have to run a master instance that grabs the revision lock.
      # And then all the worker bees can do their sting.
      self.add_argument('--instance-master', dest='instance_master',
         action='store_true', default=False,
         help="one instance to rule them all: sit on rev. lock 'til ^-C")
      self.add_argument('--instance-worker', dest='instance_worker',
         action='store_true', default=False,
         help="used with limit and offset when running asynchronously")

      self.add_argument('--##################', dest='script_specific3',
         action='store_true', default=False,
         help="###########################################")

   # *** Helpers: Parse the arguments.

   #
   def parse(self):
      '''Parse the command line arguments.'''

      # If we're a daemon, the option parser wouldn't look past the
      # double-dash, which we have to use when we call daemon, but it also ends
      # up here, so deal with it.
      log.debug('parse: argv: %s' % (sys.argv,))
      try:
         if (sys.argv[1] == '--'):
           del sys.argv[1]
      except IndexError:
         pass

      self.cli_opts = self.parse_args()
      # NOTE: parse_args halts execution if user specifies:
      #       (a) '-h', (b) '-v', or (c) unknown option.

      if self.exclude_normal:
         # Fill in the missing arguments, just to keep existing code happy.
         self.cli_opts.username = ''
         self.cli_opts.password = ''
         self.cli_opts.password_skip = False
         self.cli_opts.branch = [0,]
         self.cli_opts.revision = None
         self.cli_opts.revision_id = None
         self.cli_opts.has_revision_lock = False
         self.cli_opts.changenote = None
         self.cli_opts.group = None
         self.cli_opts.database = ''
         self.cli_opts.no_daemon = False
         # Skipping: self.cli_opts.script_specific2
         self.cli_opts.ccp_instance = ''
         self.cli_opts.items_limit = 0
         self.cli_opts.items_offset = 0
         self.cli_opts.instance_master = False
         self.cli_opts.instance_worker = False
         # Skipping: self.cli_opts.script_specific3

      # This is a little sneaky. Set the database here, globally.
      # NOTE: This should be the first time for any script that db_glue.new()
      #       is called; i.e., calling set_db_name /must/ always come before
      #       the first db_glue.new() of any script or process.
      if self.cli_opts.database:
         log.debug('Using database named "%s"' % (self.cli_opts.database,))
         db_glue.DB.set_db_name(self.cli_opts.database)

   # *** Helpers: Verify the arguments.

   #
   def verify(self):
      verified = self.verify_handler()
      # Mark handled if we handled an error, else just return.
      if not verified:
         # Print the help text if something errored
         ##self.print_usage()
         #self.print_help()
         log.info('Type "%s help" for usage.' % (sys.argv[0],))
         self.handled = True
      return verified

   #
   def verify_handler(self):
      db = db_glue.new()
      ok = True
      ok &= ok and self.verify_username(db)
      ok &= ok and self.verify_password(db)
      ok &= ok and self.verify_revision(db)
      ok &= ok and self.verify_branchid(db)
      ok &= ok and self.verify_chg_note(db)
      ok &= ok and self.verify_usergrps(db)
      ok &= ok and self.verify_asynchro(db)
      db.close()
      return ok

   #
   def verify_username(self, db):
      ok = True
      self.user_id = 0
      if not self.cli_opts.username:
         log.info('No username: using: "%s"'
                  % (conf.anonymous_username,))
         self.cli_opts.username = conf.anonymous_username
      try:
         user_id = User.user_id_from_username(db, self.cli_opts.username)
         g.assurt(user_id > 0)
         self.user_id = user_id
      except Exception, e:
         log.error('Username %s not found in database: %s'
                   % (self.cli_opts.username, str(e),))
         ok = False
      return ok

   #
   def verify_password(self, db):
      ok = True
      if self.cli_opts.password and self.cli_opts.password_skip:
         log.error('Mutually exclusive: --password and --no-password.')
         ok = False
      return ok

   #
   def verify_revision(self, db):
      ok = True
      if ((self.cli_opts.revision is not None)
          and (self.cli_opts.revision_id is not None)):
         log.error('Mutually exclusive: --revision and --revision_id.')
         ok = False
      elif ((self.cli_opts.revision is None)
            and (self.cli_opts.revision_id is None)):
         self.revision = revision.Current(allow_deleted=self.rev_allow_deleted)
      else:
         ok = self.verify_parse_revision(db)
      return ok

   #
   def verify_parse_revision(self, db):
      ok = True
      self.revision = None
      # First see if the user specified --revision_id
      if self.cli_opts.revision_id is not None:
         allowd = self.rev_allow_deleted
         if self.cli_opts.revision_id:
            self.revision = revision.Historic(self.cli_opts.revision_id,
                                              allow_deleted=allowd)
         else:
            self.revision = revision.Current(allow_deleted=allowd)
      # Next see if the user specified --revision
      else:
         g.assurt(self.cli_opts.revision)
         # Even though we supplied a default in argparse, the user can send us
         # an empty string on the command line.
         rev_parts = self.cli_opts.revision
         # First see if the argument is just an int.
         if (not rev_parts) or (rev_parts[0] == ''):
            log.error('Please specify a valid --revision or omit the switch.')
            ok = False
         else:
            try:
               rid = int(rev_parts[0])
               # Yes, the first argument is an int.
               if len(rev_parts) > 1:
                  log.error('Bad --revision: please specify Diff or Updated.')
               else:
                  allowd = self.rev_allow_deleted
                  if rid == 0:
                     self.revision = revision.Current(allow_deleted=allowd)
                  else:
                     self.revision = revision.Historic(rid,
                                       allow_deleted=allowd)
            except ValueError:
               # The user specified the name of the revision type.
               pass
         if ok and (self.revision is None):
            # Go through the list of revision definitions and look for a match.
            defns = list(Ccp_Script_Args.revision_defns)
            while defns:
               defn = defns.pop()
               self.verify_revision_parts(rev_parts, *defn)
               if self.revision is not None:
                  break
            if self.revision is None:
               log.error('Unrecognized revision: %s.' % (rev_parts,))
               ok = False
      return ok

   #
   def verify_revision_parts(self, rev_parts,
            # This matches the tuple elements in revision_defns
            target_name, target_ctor, target_narg):
      g.assurt(self.revision is None)
      # The --revision format may or may not require the rev type.
      #   E.g.,
      #     --revision 0 is same as --revision Current
      #   and
      #     --revision 10001 is same as --revision Hist 10001
      target_name = target_name.lower()
      argpar_name = rev_parts[0].lower()
      g.assurt(len(argpar_name) > 0)
      #log.debug('Testing %s vs. %s.' % (argpar_name[:len(argpar_name)],
      #                                  target_name[:len(argpar_name)],))
      # Compare the cli argument to the rev type name, and allow abbreviations.
      # NOTE: The
      if argpar_name == target_name[:len(argpar_name)]:
         # The name on the command line matches a real revision class name.
         if len(rev_parts) > target_narg:
            log.error('Bad --revision: too many args: %s.' % (rev_parts,))
         else:
            try:
               rid_old = None
               if target_narg > 1:
                  rid_old = int(rev_parts[1])
               rid_new = None
               if target_narg > 2:
                  rid_new = int(rev_parts[2])
               if not ((rid_old is None) or (rid_old > 0)
                       and ((rid_new is None) or (rid_new > 0))):
                  log.error('Bad --revision: expecting positive ints: %s.'
                      % (rev_parts,))
               else:
                  allowd = self.rev_allow_deleted
                  if target_narg == 1:
                     self.revision = target_ctor(allow_deleted=allowd)
                  elif target_narg == 2:
                     self.revision = target_ctor(rid_old, allow_deleted=allowd)
                  elif target_narg == 3:
                     self.revision = target_ctor(rid_old, rid_new)
                  else:
                     g.assurt(False)
            except ValueError, e:
               log.error('Bad --revision: unexpected type: arg not int: %s.'
                   % (rev_parts,))
            except IndexError, e:
               log.error('Bad --revision: not enough args: %s.'
                   % (rev_parts,))

   #
   def verify_branchid(self, db):
      okay = False
      # The user can specify a branch name or ID. Or, if the specified branch
      # is zero or the empty string, we lookup the public, baseline branch
      # ID. Or -- lastly -- if the branch is set to -1, it means the caller
      # wants a list of branches.
      g.assurt(self.cli_opts.branch is not None)
      # Note that routedctl causes something peculiar to happen when the branch
      # name is multiple words: even with, e.g., --branch="Metc Bikeways 2012",
      # the argparser thinks the name we want is
      #    "Metc
      # Yes, the five characters including the opening quote.
      # But this switch works fine from the command line, i.e.,
      #    ./ccp.py -b "Metc Bikeways 2012"
      # As such, we use nargs="+", which means we get a list now.
      if (not self.cli_opts.branch) or (self.cli_opts.branch[0] == ''):
         log.error('Please specify a valid --branch or omit the switch.')
      else:
         branch_name_or_id = None
         if len(self.cli_opts.branch) == 1:
            # We accept a number or a string, so figure out if it's a number.
            try:
               branch_id = int(self.cli_opts.branch[0])
               # If int worked, it's an int; might as well store it.
               self.cli_opts.branch[0] = branch_id
               # MAGIC_NUMBER: -1 means users wants no branch hier.
               if branch_id == -1:
                  log.debug('Skipping branch_hier.')
                  self.branch_id = 0
                  self.branch_hier = []
                  okay = True
               else:
                  branch_name_or_id = branch_id
                  if not branch_id:
                     log.debug('verify_branchid: using baseline branch id')
            except ValueError:
               # A string (name of the branch).
               branch_name_or_id = self.cli_opts.branch[0]
         else:
            # The arg is multiple words.
            branch_name_or_id = ' '.join(self.cli_opts.branch)
         if branch_name_or_id is not None:
            if self.branch_use_hier and (self.revision is not None):
               rev = self.revision
            else:
               rev = None
            (self.branch_id, self.branch_hier,
               ) = branch.Many.branch_id_resolve(db, branch_name_or_id, rev)
            if (self.branch_id and self.branch_hier):
               okay = True
            else:
               log.error('Bad branch_id or branch_hier: %s / %s'
                         % (self.branch_id, self.branch_hier,))
         else:
            g.assurt(okay)
      return okay

   #
   def verify_chg_note(self, db):
      return True

   #
   def verify_usergrps(self, db):
      # The group(s) is/are optional.
      okay = True
      group_ids = []
      group_defs = []
      # Use whatever the caller specifies on the command line, or use the
      # public group if the script says it's okay, or just use nothing.
      if self.cli_opts.group:
         group_ids_and_names = self.cli_opts.group
      elif self.groups_none_use_public:
         # MAGIC_NUMBER: 0 means use cp_group_public_id() to get 'All Users'.
         symbolic_public_group_stack_id = 0
         # And we also want the anonymous user's private group.
         # 2013.01.04: Do we also want the anonymous user's "private" group?
         #             All public items in group_item_access are assigned the
         #             group_id of the Public 'All Users' group. Really, the
         #             anonymous user is just so non-logged in users can check
         #             out items... nothing (no item) is ever saved with access
         #             by the anonymous user's Private group, is it? So
         #             specifying conf.anonymous_username here is probably a
         #             no-op.
         group_ids_and_names = [symbolic_public_group_stack_id,
                                conf.anonymous_username,]
      else:
         group_ids_and_names = []
      # All groups, if any, should be found/exist.
      for name_or_stack_id in group_ids_and_names:
         group_id, group_name = group.Many.group_resolve(db, name_or_stack_id)
         if group_id and group_name:
            group_ids.append(group_id)
            group_defs.append((group_id, group_name,))
         else:
            okay = False
            log.error('Unknown group ID or group name: %s'
                      % (name_or_stack_id,))
      # Convert the lists to tuples to indicate their immutability.
      self.group_ids = tuple(group_ids)
      self.group_defs = tuple(group_defs)
      # We'll only return False if one or more groups could not be found.
      return okay

   #
   def verify_asynchro(self, db):
      okay = True
      if (self.cli_opts.items_offset) and (not self.cli_opts.items_limit):
         log.error('Please specify a limit when specifying the offset')
         okay = False
      if (self.cli_opts.items_offset < 0) or (self.cli_opts.items_limit < 0):
         log.error('Please specify a non-negative value for limit or offset')
         okay = False
      return okay

   # ***

   # Do these really belong in the arg parser? Do we need a Script_Ccp base
   # class?

   #
   def begin_query(self, query_viewport=None, query_filters=None):

      db = db_glue.new()

      log.debug('Using database: %s' % (db.db_name,))

      self.qb = Item_Query_Builder(
         db, self.cli_opts.username, self.branch_hier, self.revision,
         query_viewport, query_filters)
      Query_Overlord.finalize_query(self.qb)

      # Should we always create the Item_Manager? Probably... it's not like we
      # have to load the caches yet.
      self.qb.item_mgr = Item_Manager()

      # Since we're calling the item classes directly, request.client
      # doesn't exist, so we need to set request_is_local explicitly.
      self.qb.request_is_local = True
      self.qb.request_is_script = True
      self.qb.request_is_secret = self.cli_opts.password_skip

      if self.cli_opts.has_revision_lock:
         self.qb.cp_maint_lock_owner = True

      return self.qb

   #
   def close_query(self, do_commit):
      if self.qb is not None:
         if self.qb.db is not None:
            time_0 = time.time()
            #
            if do_commit:
               log.debug('Committing to the database...')
               # BUG 2688: Use transaction_retryable?
               self.qb.db.transaction_commit()
            else:
               log.debug('Rolling back the database. %s' % self)
               self.qb.db.transaction_rollback()
            #
            self.qb.db.close()
            #
            log.info('... %s took %s'
               % ('Commit' if do_commit else 'Rollback',
                  misc.time_format_elapsed(time_0),))
            #
            self.qb.db = None
         self.qb = None

   # ***

# ***

if (__name__ == '__main__'):
   pass

