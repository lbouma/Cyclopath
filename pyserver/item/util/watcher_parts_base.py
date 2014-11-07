# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import datetime
import os
import sys
import time

import conf
import g

from grax.user import User
from item import item_user_access
from item.attc import post
from item.attc import thread
from item.feat import branch
from item.feat import route
from item.grac import group_revision
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency
from util_ import misc

log = g.log.getLogger('wtcprts_base')

# ***

class Watcher_Parts_Base(object):

   # MAYBE: There's only only msg_type_id, but if we add more, we
   #        might want to formalize it as an enum class or something.
   MSG_TYPE_UNSET        = 0
   MSG_TYPE_WITHIN       = 1 # Watched item intersects w/ edited or new
   MSG_TYPE_DIRECT       = 2 # Watched item directly edited.
   MSG_TYPE_THREAD       = 3 # New or edited post in watched thread.
   MSG_TYPE_REV_FEEDBACK = 4 # Revision feedback.
   MSG_TYPE_REV_REVERT   = 5 # Revision revert.
   MSG_TYPE_RTE_REACTION = 6 # Route reaction reminder.
   # BUG nnnn: Re-enable Route Reactions / Route Feedback.
   #           Do we need another msg_type? Route Feedback is a special
   #           type of Discussions, so either just use MSG_TYPE_THREAD or
   #           wire an analagous msg_type for reaction threads.
   # FIXME/BUG nnnn: Just like how commit asks the user if they want an email
   # if another user comments on or reverts their revision, we could either:
   # a. Ask route owners if they want an email when another user writes
   #    feedback on their route;
   # b. Instead of a., just add an "I'm interested in alert emails" option
   #    to the route panel;
   # c. Just automatically assume route owners want route feedback emails; or
   # d. Make one checkbox for all routes (i.e., a global setting instead of one
   #    setting-per-route); this way, we could default to assuming user wants
   #    route feedback emails, and then we could add an opt-out link to the
   #    email so they can easily disable the I-want-route-feedback option.
   #MSG_TYPE_RTE_FEEDBACK = 7 # Route feedback.

   def __init__(self):
      self.msg_text = ''
      self.msg_html = ''

   #
   def __str__(self):
      as_str = ('Watcher_Parts_Base: %s / %s'
                % (self.msg_text, self.msg_html,))
      return as_str

   # BUG nnnn: Move email strings to a presentation file -- [lb] knows
   # Cyclopath doesn't cuurently implement localization, so we often mix
   # code and user-facing messages, but usually the messages are small,
   # like, one sentence small. But here, the email is long, and it's
   # construction is unfortunately intermingled with code... but at least
   # all of the email messages are in one file, so it'd at least be easier
   # to internationalize this module.

   #
   def combine(self, other):
      self.msg_text += other.msg_text
      self.msg_html += other.msg_html

   # *** Helpers for the MSG_TYPE_WITHIN + MSG_TYPE_DIRECT email

   #
   def compose_email_header(self, w_composer):

      g.assurt(False) # Abstract.

   #
   def compose_email_footer(self, w_composer):

      g.assurt(False) # Abstract.

   #
   def compose_email_revision(self, rev_rid, rev_row):

      g.assurt(False) # Abstract.

   #
   def compose_email_item_list(self, qb, msg_type_id, items_fetched):

      g.assurt(False) # Abstract.

   # ***

   #
   def compose_email_branch(self, the_branch):

      self.msg_text += (
'''
Activity in branch: "%s"
''' % (the_branch.name,))

      self.msg_html += (
'''
<p>
Activity in branch: "%s"
</p>
''' % (the_branch.name,))

      # end: compose_email_branch

   #
   def compose_email_msg_type(self, msg_type_id):

      #change_context = ''
      #if msg_type_id == Watcher_Parts_Base.MSG_TYPE_WITHIN:
      #   change_context = (
      #      '''Another user edited items within your watched regions or that intersect with other items you are watching:''')
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_DIRECT:
      #   change_context = (
      #      '''Another user edited items that you are watching:''')
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_THREAD:
      #   change_context = (
      #      '''There was activity in some discussions you are watching:''')
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_REV_FEEDBACK:
      #   change_context = (
      #      '''Someone posted feedback on some of your revisions:''')
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_REV_REVERT:
      #   change_context = (
      #      '''Someone reverted some of your revisions:''')
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_RTE_REACTION:
      #   g.assurt(False)
      #elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_RTE_FEEDBACK:
      #   change_context = (
      #      '''Someone posted feedback about one or more of your routes:''')
      #else:
      #   g.assurt(False)

      change_context = self.friendly_msg_type(msg_type_id)

      if change_context:

         self.msg_text += '\n%s\n' % (change_context,)

         self.msg_html += '\n<p>\n%s\n</p>\n' % (change_context,)

   #
   def friendly_msg_type(self, msg_type_id):

      g.assurt(False) # Abstract

   # ***

# ***

