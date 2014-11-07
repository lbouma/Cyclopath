# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import datetime
from lxml import etree
import time

import conf
import g

from util_ import misc

log = g.log.getLogger('user_client_ban')

class User_Client_Ban(object):
   ''' Represents the banned state of a client '''
   
   # Each slot is a datetime.datetime object. If one is None, then that one
   # is not currently banned, otherwise the date is the end date of the ban.
   __slots__ = (
      'public_ban_user',
      'full_ban_user',
      'public_ban_ip',
      'full_ban_ip',
      )

   def __init__(self, db, username, ip):
      self.load_ban_status(db, username, ip)

   ##
   ## Public interface
   ##

   def as_xml(self):
      bans = etree.Element('bans')
      misc.xa_set(bans, 'public_user', self.public_ban_user)
      misc.xa_set(bans, 'full_user', self.full_ban_user)
      misc.xa_set(bans, 'public_ip', self.public_ban_ip)
      misc.xa_set(bans, 'full_ip', self.full_ban_ip)
      return bans

   def is_banned(self):
      return (self.public_ban_user is not None
              or self.public_ban_ip is not None
              or self.is_full_banned())

   def is_full_banned(self):
      return (self.full_ban_user is not None
              or self.full_ban_ip is not None)

   ##
   ## Private interface / object methods
   ##

   def load_ban_status(self, db, username, ip):
      '''
      Updates each ban date, or sets it to None if not banned for that type
      '''

      username = db.quoted(username)
      
      rows = db.sql(User_Client_Ban.build_sql_user('public_ban', username))
      if (len(rows) > 0):
         self.public_ban_user = User_Client_Ban.create_datetime(
                                             rows[0]['ban_end'])
      else:
         self.public_ban_user = None

      rows = db.sql(User_Client_Ban.build_sql_user('full_ban', username))
      if (len(rows) > 0):
         self.full_ban_user = User_Client_Ban.create_datetime(
                                             rows[0]['ban_end'])
      else:
         self.full_ban_user = None

      rows = db.sql(User_Client_Ban.build_sql_ip('public_ban', ip))
      if (len(rows) > 0):
         self.public_ban_ip = User_Client_Ban.create_datetime(
                                             rows[0]['ban_end'])
      else:
         self.public_ban_ip = None

      rows = db.sql(User_Client_Ban.build_sql_ip('full_ban', ip))
      if (len(rows) > 0):
         self.full_ban_ip = User_Client_Ban.create_datetime(
                                             rows[0]['ban_end'])
      else:
         self.full_ban_ip = None   

   ##
   ## Private interface / static class methods
   ##

   @staticmethod
   def build_sql(where, active):
      sql = (
         """
         SELECT 
            username,
            ip_address,
            public_ban,
            full_ban,
            activated,
            expires,
            to_char(expires, 'YYYY-DD-MM HH:MI:SS') as ban_end,
            to_char(created, 'YYYY-DD-MM HH:MI:SS') as created
         FROM ban
         WHERE %s
         """ % (where))
      if (active):
         sql = (
            """
            %s
            AND activated
            AND (created, expires) OVERLAPS (now(), now())
            """ % (sql))
      sql = "%s ORDER BY expires DESC" % (sql)
      return sql

   @staticmethod
   def build_sql_ip(scope, ip):
      return User_Client_Ban.build_sql("%s AND ip_address = INET '%s'" 
                                       % (scope, ip), True)

   @staticmethod
   def build_sql_user(scope, username):
      return User_Client_Ban.build_sql("%s AND username = %s" 
                                       % (scope, username), True)

   @staticmethod
   def create_datetime(sql_timestamp):
      return misc.sql_time_to_datetime(sql_timestamp)

