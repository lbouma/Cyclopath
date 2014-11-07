# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The Hello request verifies login.
#
# A successful Hello request means that login was successful. Unsuccessful
# logins raise GWIS_Error.

from lxml import etree
import os
import sys

import conf
import g

from gwis import command
from gwis.exception.gwis_error import GWIS_Error
from util_ import misc

log = g.log.getLogger('cmd.user_hello')

class Op_Handler(command.Op_Handler):

   # *** Constructor

   def __init__(self, req):
      command.Op_Handler.__init__(self, req)

   # ***

   #
   def __str__(self):
      selfie = 'user_hello'
      return selfie

   # ***

   #
   def pre_decode(self):
      # Call the base class first, we raises if the user's host IP is banned.
      command.Op_Handler.pre_decode(self)
      # Validate the user password. If validated, checks that the user has
      # access to the branch, which raises an exception otherwise.
      self.req.client.user_validate_maybe('password')

   #
   def decode_request(self):
      # Not really anything to do; we already got the password, but we have to
      # tell the base class to not check for the token as a consequence.
      command.Op_Handler.decode_request(self, expect_no_token=True)

   #
   def fetch_n_save(self):
      command.Op_Handler.fetch_n_save(self)
      if (self.req.client.username == conf.anonymous_username):
         raise GWIS_Error('No credentials provided', 'nocreds')

   #
   def prepare_response(self):

      g.assurt(self.req.client.username != conf.anonymous_username)

      # Skipping: BUG 2688: No need to use transaction_retryable,
      #                     since user_token_gen does it own retrying.
      e = etree.Element('token')
      e.text = self.req.client.user_token_generate(self.req.client.username)
      self.doc.append(e)

      # FIXME: Bug nnnn: Generate the session ID / sessid here, too...

      e = etree.Element('preferences')
      p = self.preferences_get()
      for (col, value) in p.items():
         misc.xa_set(e, col, value)

      self.doc.append(e)

# Bug nnnn: do not piggyback user prefs on hello's token resp.
#           This also means we cannot close self.req.db until after
#           preparing response -- all other prepare_response do not
#           use db.
   #
   def preferences_get(self):
      # NOTE: If client sends token, we never send this until they logon again.
      #       That is, if a user changes preferences from one browser, we
      #       won't reflect the changes in another browser until they
      #       explicitly logoff and then back on -- so people who save their
      #       tokens to logon automatically won't see preferences update
      #       across browsers automatically.
      g.assurt(self.req.client.username != conf.anonymous_username)
      # FIXME Why are quoting the string ourselves (with psycopg.QuotedString)
      #       rather than letting the connection cursor do it?
      sql = (
         """
         SELECT
            email,
            enable_watchers_email,
            enable_watchers_digest,
            route_viz,
            rf_planner AS rf_planner,
            rf_p1_priority AS p1_priority,
            rf_p2_transit_pref AS p2_txpref,
            rf_p3_weight_type AS p3_wgt,
            rf_p3_rating_pump AS p3_rgi,
            rf_p3_burden_pump AS p3_bdn,
            rf_p3_spalgorithm AS p3_alg,
            flashclient_settings AS fc_opts,
            routefinder_settings AS rf_opts
         FROM
            user_
         WHERE
            user_.username = %s
         """ % (self.req.db.quoted(self.req.client.username),))
      return self.req.db.sql(sql)[0]

   # ***

# ***

