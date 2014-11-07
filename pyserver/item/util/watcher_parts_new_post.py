# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import datetime
import os
import sys
import time

import conf
import g

from grax.user import User
from item.attc import post
from item.attc import thread
from item.util.item_type import Item_Type
from item.util.watcher_parts_base import Watcher_Parts_Base
from util_ import misc

log = g.log.getLogger('wtcprts_newp')

# ***

class Watcher_Parts_New_Post(Watcher_Parts_Base):

   def __init__(self):
      Watcher_Parts_Base.__init__(self)

   #
   def __str__(self):
      as_str = ('Watcher_Parts_New_Post: %s / %s'
                % (self.msg_text, self.msg_html,))
      return as_str

   # *** Helpers for the MSG_TYPE_THREAD

   #
   def compose_email_header(self, w_composer):

      self.msg_text += (
'''Hello, %s,

There are new posts some of the threads that you watch on Cyclopath.
''' % (w_composer.username,))

      self.msg_html += (
'''
<p>
Hello, %s,
</p>

<p>
There are new posts some of the threads that you watch on Cyclopath.
</p>
''' % (w_composer.username,))

      # end: compose_email_header

   #
   def compose_email_footer(self, w_composer):

      self.msg_text += (
'''
To reply to a discussion, click the link given with each post above.

We sent this e-mail because you are a registered Cyclopath user
and you are watching one of more threads in Cyclopath Discussions.
We notify you when new posts are added to watched conversations.

You can change how soon you're notified of new posts in a thread,
or you can disable watching particular threads, by opening the thread
in Cyclopath Discussions. Look for Item Alerts and click the 'Change'
button.

You can also disable all of your item watchers -- including region
watchers and item watchers, in addition to thread watchers -- by
clicking the following link to disable all of your item alerts.
 Disable all of your alerts: %s
Please email %s if you have any problems.
''' % (w_composer.unsubscribe_link,
       conf.mail_from_addr,))

      self.msg_html += (
'''
<p>
To reply to a discussion, click the link given with each post above.
</p>

<p>
We sent this e-mail because you are a registered Cyclopath user
and you are watching one of more threads in Cyclopath Discussions.
We notify you when new posts are added to watched conversations.
</p>

<p>
You can change how soon you're notified of new posts in a thread,
or you can disable watching particular threads, by opening the thread
in Cyclopath Discussions. Look for Item Alerts and click the 'Change'
button.
</p>

<p>
You can also disable all of your item watchers -- including region
watchers and item watchers, in addition to thread watchers -- by
clicking <a href="%s">disable all of your alerts</a>.
Please email <a href="mailto:%s">%s</a> if you have any problems.
</p>
''' % (w_composer.unsubscribe_link,
       conf.mail_from_addr,
       conf.mail_from_addr,))

      # end: compose_email_footer

   #
   def compose_email_revision(self, rev_rid, rev_row):

      # Don't show revision info for threads (it's meaningless).

      pass # do nothing

   #
   def friendly_msg_type(self, msg_type_id):

      # Since there's only on msg_type, we include what would be this message
      # in the header.

      return ''

   #
   def compose_email_item_list(self, qb, msg_type_id, items_fetched):

      for item in items_fetched:

         g.assurt(item.real_item_type_id == Item_Type.post)

         # The item is the post. Get the post and the thread.
         #qb.filters.context_stack_id = {thread_stack_id}
         posts = post.Many()
         posts.search_by_stack_id(item.stack_id, qb)
         if len(posts) > 0:
            g.assurt(len(posts) == 1)
            the_post = posts[0]
         else:
            the_post = None
            log.warning('_compose_item_list: cannot see post: %s / %s'
                        % (qb.username, item.stack_id,))

         if the_post is not None:

            threads = thread.Many()
            threads.search_by_stack_id(the_post.thread_stack_id, qb)

            if len(threads) > 0:
               g.assurt(len(threads) == 1)
               the_thread = threads[0]

               # 2014.07.02: FIXME: test changes to what_username:
               post_username = User.what_username([the_post.edited_user,
                                                   the_post.edited_host,
                                                   the_post.edited_addr,])

               # A CcpV1 link:
               deeplink_text_v1 = (
                  'http://%s/#discussion?thread_id=%d&post_id=%d'
                  % (conf.server_name,
                     the_thread.stack_id,
                     the_post.stack_id,))
               # MAYBE: A CcpV2 link so the user is asked to log on:
               deeplink_text_v2 = (
                  'http://%s/#private?type=post&link=%d'
                  % (conf.server_name,
                     the_post.stack_id,))
               log.debug('MAYBE: deeplink_text_v2: %s' % (deeplink_text_v2,))

               self.msg_text += (
'''Discussion: %s
Posted by:  %s
View post:  %s (Flash required)
+-----
%s
+-----
'''               % (the_thread.name,
                     post_username,
                     deeplink_text_v1,
                     the_post.body,))
               self.msg_html += (
'''<table>
<tr><td>Discussion:</td> <td>%s</td></tr>
<tr><td>Posted by:</td> <td>%s</td></tr>
<tr><td>View post:</td> <td><a href="%s">%s</a> (Flash required)</td></tr>
</table><br/>
+-----<br/>
%s<br/>
+-----<br/>
'''               % (the_thread.name,
                     post_username,
                     deeplink_text_v1, 
                     deeplink_text_v1, 
                     the_post.body,))

            else: # len(threads) == 0
               log.warning(
                  '_compose_item_list: cannot see thread: %s / %s'
                  % (qb.username, the_post.thread_stack_id,))

         # else: the_post is None

      # end: for item in items_fetched:

   # end: compose_email_item_list


   # ***

# ***

