# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import rfc822

import conf
import g

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from gwis.exception.gwis_warning import GWIS_Warning

# FIXME: Still not sure about if we need this class or not.
# FIXME: Why is this in grax/ and group.py in item/grac/?

log = g.log.getLogger('user')

# BUG nnnn: Enforce username rules, like min length and no leading underscore.

class User(object):

   __slots__ = ()

   def __init__(self):
      pass

   #
   @staticmethod
   def email_valid(email):
      # rfc822 is pretty forgiving, but we want to be strict. [rp]
      is_valid = False
      if email:
         real_name, email_addy = rfc822.parseaddr(email)
         if email == email_addy:
            is_valid = True
         else:
            # 2012.11.12: [lb] is not sure this ever happens. Parseaddr just
            # splits a To: or a From: into the friendly name and the email
            # address, e.g., "Some Person <some.person@gmail.com>".
            # See BUG 2763: Bad email addys.
            log.warning('Since when does rfc822.parseaddr fail? "%s" != "%s"'
                        % (email, email_addy,))
      return is_valid

   #
   @staticmethod
   def group_ids_for_user(db, username):
      g.assurt(username)
      group_ids = None
      rid_clause = (
         """
         AND gm.valid_until_rid = %d
         AND gr.valid_until_rid = %d
         """ % (conf.rid_inf, conf.rid_inf,))
      if False:
         # 2014.05.10: This is so wrong. I've felt it in my bones for years,
         # and I [lb] finally deboned it: We used to allow using a user's
         # group IDs at an historic revision by using a user's old group
         # memberships. We had meant to make permissions somewhat wiki-like,
         # e.g., if a user has access to an item at some revision, they
         # always had access to that item at that revision. But then a
         # branch arbiter cannot, say, deny a user access and *really*
         # deny them access (or they cannot add a new user and let them have
         # access to all branch history without setting their group
         # membership's valid_start_rid to 1). This model also doesn't make
         # much sense or serve much utility, since map items never change
         # permissions, but routes do (and we want users to really be able to
         # deny users access to all versions of a route), and a user's group
         # memberships that change are usually just branch memberships (since
         # we don't have any other types of groups than the public group, the
         # private groups, and the various branch groups (editors, arbiters,
         # etc.)). So don't consider a user's old group memberships, only their
         # current ones.
         g.assurt(False)
         # Deprecated:
         g.assurt(rid < conf.rid_inf)
         rid_clause = (
            """
            AND gm.valid_start_rid <= %d
            AND gm.valid_until_rid > %d
            AND gr.valid_start_rid <= %d
            AND gr.valid_until_rid > %d
            """ % (rid, rid, rid, rid,))
      try:
         user_sql = (
            """
            SELECT
               DISTINCT (gr.stack_id) AS group_id
            FROM
               user_ AS u
            JOIN group_membership AS gm
               ON (u.id = gm.user_id)
            JOIN group_ AS gr
               ON (gm.group_id = gr.stack_id)
            WHERE
               u.username = %s
               AND gm.access_level_id <= %s
               %s
               AND NOT gm.deleted
               AND NOT gr.deleted
            ORDER BY
               gr.stack_id
            """ % (db.quoted(username),
                   Access_Level.client,
                   rid_clause,))
         rows = db.sql(user_sql, force_fetchall=True)
         group_ids = [x['group_id'] for x in rows]
      except Exception, e:
         log.error('Is this an error? %s' % str(e))
         raise GWIS_Warning('User "%s" is not recognized.' % (username,))
      return group_ids

   #
   @staticmethod
   def private_group_id(db, username, do_raise=True):
      g.assurt(username)
      # FIXME: Make a cache of group IDs?
      private_group_id = None
      # Checks that the user's membership is current (valid_until_rid is 
      # cp_rid_inf) and that the user's access is not 'denied'.
      # See also the similar PL/pgSQL function:
      #    private_group_id = int(db.sql(
      #       "SELECT cp_group_private_id(%s) AS id", (username,))[0]['id'])
      rows = db.sql(
         """
         SELECT 
            stack_id AS id
         FROM 
            group_ 
         WHERE 
                name = %s 
            AND access_scope_id = %s
            AND valid_until_rid = %s
            AND deleted IS FALSE
         """, 
         (username, Access_Scope.private, conf.rid_inf,),
         force_fetchall=True)
      try:
         private_group_id = int(rows[0]['id'])
      except IndexError:
         log.warning('Unexpected IndexError: username: "%s"' % (username,))
         g.assurt(False)
      except KeyError:
         if do_raise:
            raise GWIS_Warning('Private group "%s" not found.' % (username,))
      return private_group_id

   #
   @staticmethod
   def spam_get_user_info(db, extra_where='',
                              sort_mode='',
                              make_lookup=False,
                              ignore_flags=False):

      user_ids = []
      invalid_ids = []
      not_okay = []
      user_infos = []

      # 2012.11.12: This function used to not check enable_email, but we've
      # been inconsistent with opt-out requests ([lb] has only ever set
      # enable_email to FALSE, but it seems maybe I was suppose to set
      # enable_email_research to FALSE). But an opt-out seems like an opt-out:
      # enable_email is tied to a user's Wiki preference about getting email
      # regarding posts and discussions and route feedback, but you'd think if
      # someone said the didn't want automatic emails from the site about that,
      # they certainly wouldn't want mass emails, either.

      # NOTE: If you're searching by email, note that some users have multiple
      #       accounts with the same email, so you'll get more records than
      #       you'd expect!
      where_clause = ""
      if extra_where:
         where_clause = "WHERE %s" % (extra_where,)

      order_by_clause = ""
      if sort_mode:
         order_by_clause = "ORDER BY %s" % (sort_mode,)

      ids_sql = (
         """
         SELECT
            id AS user_id
            , username
            , email
            , email_bouncing
            , enable_email
            , enable_email_research
            , dont_study
            , unsubscribe_proof
         FROM
            user_
         %s
         %s
         """ % (where_clause,
                order_by_clause,))

      dont_fetchall = db.dont_fetchall
      db.dont_fetchall = True
      rows = db.sql(ids_sql)

      generator = db.get_row_iter()
      for row in generator:

         if (row['email']
             and (not row['email_bouncing'])
             and row['enable_email']
             and row['enable_email_research']
             and ((not row['dont_study']) or ignore_flags)):
            if User.email_valid(row['email']):
               user_ids.append(row['user_id'])
               info_tuple = (row['user_id'],
                             row['username'],
                             row['email'],
                             row['unsubscribe_proof'],)
               user_infos.append(info_tuple)
            else:
               invalid_ids.append(row['user_id'])
         else:
            not_okay.append(row['user_id'])

      generator.close()

      db.dont_fetchall = dont_fetchall

      info_lookup = {}
      if make_lookup:
         for info_tuple in user_infos:
            user_id = info_tuple[0]
            g.assurt(user_id not in info_lookup)
            # Set, i.e., info_lookup[user_id] = info_tuple
            info_lookup[user_id] = info_tuple

      return (user_ids, invalid_ids, not_okay, user_infos, info_lookup,)

   #
   @staticmethod
   def user_id_from_username(db, username, do_raise=True):
      g.assurt(username)
      user_id = None
      # MAYBE: Use a cache...
      try:
         # We run the SQL directly just to be transparent, but the equivalent
         # PL/pgSQL fun is:
         #    user_id = int(db.sql("SELECT cp_user_id(%s) AS id", 
         #                         (username,))[0]['id'])
         user_id = int(db.sql("SELECT id FROM user_ WHERE username = %s", 
                              (username,), force_fetchall=True)[0]['id'])
      except IndexError:
         if do_raise:
            raise GWIS_Warning('User "%s" is not recognized.' % (username,))
      return user_id

   #
   @staticmethod
   def user_is_script(username):
      g.assurt(username)
      # MAGIC_NUMBER: When a script runs, it fakes a username (one that's not
      # in the user table) using a beginning underscore. See also the
      # CycloAuth.php script in the mediawiki project. (BUG nnnn: In-band reg.)
      return username.startswith('_')

   #
   # Make a friendly name from a username or host that was munged in SQL.
   @staticmethod
   def what_username(remote_idents):

      friendlier = None

      is_anon = False

      for username_or_host_or_addr in remote_idents:
         if username_or_host_or_addr:
            if username_or_host_or_addr == conf.anonymous_username:
               is_anon = True
               # Loop to next one...
            else:
               if username_or_host_or_addr in ('localhost.localdomain',
                                               'localhost',
                                               '127.0.0.1'):
                  if not is_anon:
                     log.warning('what_username: not is_anon: %s'
                                 % (remote_idents,))
                  friendlier = 'anonymous biker (localhost)'
               elif is_anon:
                  # E.g., "anonymous biker (domain.tld)"
                  #       or "anonymous biker (12.45.78.90)"
                  friendlier = ('anonymous biker (%s)'
                                % (username_or_host_or_addr,))
               else:
                  friendlier = username_or_host_or_addr
               break
         # else, not username_or_host_or_addr.

      if not friendlier:
         log.warning('what_username: not friendlier: %s' % (remote_idents,))
         if is_anon:
            friendlier = 'anonymous biker'
         else:
            friendlier = 'ghost biker'

      return friendlier

   # ***

# ***

