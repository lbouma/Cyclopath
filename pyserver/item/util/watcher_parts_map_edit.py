# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import datetime
import os
import sys
import time

import conf
import g

from grax.user import User
from item.util.item_type import Item_Type
from item.util.watcher_parts_base import Watcher_Parts_Base
from util_ import misc

log = g.log.getLogger('wtcprts_mape')

# ***

class Watcher_Parts_Map_Edit(Watcher_Parts_Base):

   def __init__(self):
      Watcher_Parts_Base.__init__(self)

   #
   def __str__(self):
      as_str = ('Watcher_Parts_Map_Edit: %s / %s'
                % (self.msg_text, self.msg_html,))
      return as_str

   # *** Helpers for the MSG_TYPE_WITHIN + MSG_TYPE_DIRECT email

   #
   def compose_email_header(self, w_composer):

      self.msg_text += (
'''Hello, %s,

The Cyclopath map has been edited, and something you're watching changed.
''' % (w_composer.username,))

      self.msg_html += (
'''
<p>
Hello, %s,
</p>

<p>
The Cyclopath map has been edited, and something you're watching changed.
</p>
''' % (w_composer.username,))

   # end: compose_email_header

   #
   def compose_email_footer(self, w_composer):

      self.msg_text += (
'''
We sent this e-mail because you are a registered Cyclopath user
and you asked to be alerted when certain events happen.

You can also visit http://%s and go to Revision Activity
to see what changed.

You can log onto Cyclopath to change your alert settings, or you
can click the following link to disable all of your item alerts.
 Disable all of your alerts:
  %s
Please email %s if you have any problems.
''' % (conf.server_name,
       w_composer.unsubscribe_link,
       conf.mail_from_addr,))

      self.msg_html += (
'''
<p>
We sent this e-mail because you are a registered Cyclopath user
and you asked to be alerted when certain events happen.
</p>

<p>
You can also visit http://%s and go to Revision Activity
to see what changed.
</p>

<p>
You can log on to Cyclopath to change your alert settings, or you can
click this link to <a href="%s">disable all of your alerts</a>.
Please email <a href="mailto:%s">%s</a> if you have any problems.
</p>
''' % (conf.server_name,
       w_composer.unsubscribe_link,
       conf.mail_from_addr,
       conf.mail_from_addr,))

   # end: compose_email_footer

   # ***

   #
   def compose_email_revision(self, rev_rid, rev_row):

#      conf.break_here('ccpv3')

      if rev_row is not None:

         # 2014.07.02: FIXME: test changes to what_username:
         # FIXME: Should use 'host' and 'addr' instead of 'raw_username'.
         rev_username = User.what_username([rev_row['username'],
                                            rev_row['raw_username'],])

         self.msg_text += (
'''
Revision %d by %s at %s
Change note: %s
''' % (rev_row['revision_id'],
       rev_username,
       rev_row['timestamp'],
       rev_row['comment'],))

         self.msg_html += (
'''
<p>
Revision %d by %s at %s
<br/>
Change note: %s
</p>
''' % (rev_row['revision_id'],
       rev_username,
       rev_row['timestamp'],
       rev_row['comment'],))

      else:

         # rev_row is None is user does not have at least one group_revision
         # record for the revision.

         self.msg_text += (
'''
Revision %d (hidden)
''' % (rev_rid,))

         self.msg_html += (
'''
<p>
Revision %d (hidden)
</p>
''' % (rev_rid,))

   # end: compose_email_revision

   #
   def friendly_msg_type(self, msg_type_id):

      change_context = ''

      if msg_type_id == Watcher_Parts_Base.MSG_TYPE_WITHIN:
         change_context = (
'''These regions and items you are watching contain or overlap
with items there were edited:''')
      elif msg_type_id == Watcher_Parts_Base.MSG_TYPE_DIRECT:
         # FIXME: MSG_TYPE_WITHIN will always contain these, because
         #        ST_Intersects will find directly-edited items?
         #        Maybe we don't want to include these items in
         #        the MSG_TYPE_WITHIN list.
         #        Anyway, [lb] notices that if you edit an item
         #        you're watching, you get both a WITHIN and a
         #        DIRECT hit, so the item appears twice in the email.
         change_context = (
            '''These items that you are watching were edited:''')
      else:
         g.assurt(False)

      return change_context

   # end: compose_email_msg_type

   #
   def compose_email_item_list(self, qb, msg_type_id, items_fetched):

      for item in items_fetched:

         item_type_str = Item_Type.id_to_str(item.real_item_type_id)
         if item.stealth_secret:
            deeplink = ('http://%s/#private?type=%s&link=%s'
                        % (conf.server_name,
                           item_type_str,
                           item.stealth_secret,))
         else:
            deeplink = ('http://%s/#private?type=%s&link=%s'
                        % (conf.server_name,
                           item_type_str,
                           item.stack_id,))
         if deeplink:
            deeplink_text = ' (%s)' % (deeplink,)
            deeplink_html = (' (<a href="%s">go to</a>)'
                             % (deeplink,))
         else:
            deeplink_text = ''
            deeplink_html = ''

         if ((msg_type_id == Watcher_Parts_Base.MSG_TYPE_WITHIN)
             or (msg_type_id == Watcher_Parts_Base.MSG_TYPE_DIRECT)):

            # The item is an item that was edited, or a region wherein one
            # or more items were edited, or an item that intersects with
            # an item that was edited.

            self.msg_text += (
'''%s%s
'''            % (item.name, deeplink_text,))
            self.msg_html += (
'''%s%s<br/>
'''            % (item.name, deeplink_html,))

      # end: for item in items_fetched:

   # end: compose_email_item_list

   # ***

# ***

