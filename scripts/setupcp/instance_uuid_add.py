#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script creates a unique UUID for an installation of Cyclopath.
#
# Usage:
#
#   $ PYSERVER_HOME=/ccp/dev/cp ./server_uuid_add.py
#

# The script creates a UUID for a specific Cyclopath instance (specified using
# the $INSTANCE environment variable) to be shared by all copies of the same
# database. This lets scripts and code act upon specific database IDs without
# interfering with other databases.

# E.g., the production server at http://cycloplan.cyclopath.org shares the same
# UUIDs with copies of the database on the developer machines at the Univ. of
# MN. But it doesn't share the same UUIDs with other databases that have been
# created by third-party or open source developers.

import uuid

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue

log = g.log.getLogger('server_uuid_add')

class Server_UUID_Add(object):

   def __init__(self):
      pass

   def go(self):

      db = db_glue.new()

      # See that the UUID doesn't already exist.

      existings = db.sql(
         """
         SELECT value FROM key_value_pair 
         WHERE key = 'cp_instance_uuid';
         """)

      if len(existings):
         raise Exception('UUID already exists!: %s' % (existings[0]['value'],))

      # Create a new UUID

      # Python docs on uuid1: "Generate a UUID from a host ID, sequence number,
      # and the current time."
      instance_uuid = uuid.uuid1()

      # Insert the new UUID

      db.transaction_begin_rw()
      db.insert(
         'key_value_pair', {
            'key': 'cp_instance_uuid',
            'value': str(instance_uuid),
         }, {})
      db.transaction_commit()
      db.close()

      # All done!

      log.debug('Inserted new UUID: %s' % (instance_uuid,))

if (__name__ == '__main__'):
   add_uuid = Server_UUID_Add()
   add_uuid.go()

