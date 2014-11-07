# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from gwis import command_base
from gwis import user_client_ban
from gwis import user_email
from gwis.query_overlord import Query_Overlord
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import geofeature
from item.util import revision
from util_ import misc

log = g.log.getLogger('command_client')

class Op_Handler(command_base.Op_Handler):

   __slots__ = (
      'login_required',       # If True, fail request unless user is logged in.
      'user_client_ban',      # If True, too many failed logins, so bounce 'em.
      'branch_update_enabled', # True if the user is committing a new revision.
      'filter_geo_enabled',   # True if request may contain bbox.
      'filter_rev_enabled',   # True if request may contain revision ID(s).
      )

   def __init__(self, req):
      command_base.Op_Handler.__init__(self, req)
      self.login_required = False # descendants should enable as necessary
      self.user_client_ban = None
      self.branch_update_enabled = False
      self.filter_geo_enabled = False
      self.filter_rev_enabled = False

   # *** Base class overrides

   #
   def pre_decode(self):

      command_base.Op_Handler.pre_decode(self)

      # Check that the user's IP isn't banned; raise if it is. Do this now,
      # before checking the user password or token, so we don't waste time on a
      # banned host's request.
      self.check_ban_all_gwis()

   #
   def decode_request(self, expect_no_token=False):

      command_base.Op_Handler.decode_request(self)

      # Validate the user token if the credentials did not include a password
      # (i.e., if this isn't the user_hello command, in which case we already 
      # checked). Also check that the user has access to the branch, or raise.
      if not expect_no_token:
         self.req.client.user_validate_maybe('token')
      # else, this is user_hello, and we looked for a password in pre_decode.

      # Some commands types explicitly require the user to be logged on.
      if ((self.req.client.username == conf.anonymous_username)
          and self.login_required):
         log.error('decode_request: not logged in: %s' % (self.req,))
         raise GWIS_Error('This operation requires logging in (%s).'
                          % (type(self),))

      # See if the specified user is banned.
      self.user_client_ban = user_client_ban.User_Client_Ban(
         self.req.db, self.req.client.username, self.req.client.ip_addr)

      # Check the query filters.
      self.req.filters.verify_filters(self.req)

   #
   def fetch_n_save(self):
      command_base.Op_Handler.fetch_n_save(self)
      # Configure user-specific query filter things, like filter_by_watch_geom.
# FIXME: Is this needed? See as_iqb
      Query_Overlord.prepare_filters(self.req)

   #
   def prepare_metaresp(self):
      command_base.Op_Handler.prepare_metaresp(self)

      # MAYBE: Like cp_maint_beg and cp_maint_fin, we could have the client
      #        ask for 'semiprotect', since flashclient should only need it if
      #        the user is editing (it restricts new and anonymous users from
      #        editing but not from getting routes). See: kval_get.py.
      misc.xa_set(self.doc, 'semiprotect', self.semiprotect_wait())

      if self.user_client_ban.is_banned():
         self.doc.append(self.user_client_ban.as_xml())

      # Check if the user's email address is invalid
      # NOTE: Flashclient will show a popup to tell the user if
      #       their email address is marked bouncing.
      if self.req.client.username != conf.anonymous_username:
         if (user_email.flag_get(
               self.req.db, self.req.client.username, 'bouncing')):
            misc.xa_set(
               self.doc,
               'bouncing',
               user_email.addr_get(
                  self.req.db, self.req.client.username, False))

   ##
   ## Private interface
   ##

# FIXME How are you going to test this? 
# FIXME How are you going to test all of pyserver? Coverage analysis tool?

   #
   def check_ban_all_gwis(self):
      '''If the client IP address has ban_all_gwis ban in place, abort the
         operation with gwis.gwis_error.GWIS_Error.

         Note that ban_all_gwis on users is kind of pointless, since they could
         just clear their cookies and keep going.'''
      # get bans
      rows = self.req.db.sql(
         """
         SELECT
            reason,
            expires
         FROM
            ban
         WHERE
            activated
            AND expires > now()
            AND ban_all_gwis
            AND host(ip_address) = %s
         ORDER BY
            expires DESC
         LIMIT 1
         """, (self.req.client.ip_addr,))
      if len(rows) > 0:
         # there's a ban - deny access
         g.assurt(len(rows) == 1)
         the_reason = rows[0]['reason']
         the_expiry = rows[0]['expires']
         # MAYBE: The 'Please try again after' text is wrong or misleading if
         #        the ban is permanent.
         raise GWIS_Warning(
            '%s%s%s%s%s'
            % ('Cyclopath is currently refusing service to your IP address. ',
               'This is because: %s.\n\n' % (the_reason,),
               'Please try again after: %s\n\n' % (the_expiry,),
               'If you believe this is an error, or if you have any ',
               'questions, please contact %s.' % (conf.mail_from_addr,),),
            tag='authfailban')

   #
   def semiprotect_wait(self):
      '''Return the semi-protection waiting period applicable to the current
         user. Note that this is NOT the time remaining but rather the whole
         waiting period.'''
      if (conf.semiprotect == 0):
         return 0
      if (self.req.client.username == conf.anonymous_username):
         return conf.semiprotect
      rows = self.req.db.sql(
         """
         SELECT
            (age(created) > '%d hours') AS waited
         FROM
            user_
         WHERE
            username = %s
         """ % (conf.semiprotect,
                self.req.db.quoted(self.req.client.username),))
      if (rows[0]['waited']):
         return 0
      else:
         return conf.semiprotect

   # ***

# ***

