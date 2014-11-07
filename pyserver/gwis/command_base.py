# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree
import os
import signal
import traceback

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.util import revision
from util_ import misc
import VERSION

log = g.log.getLogger('command_base')

class Op_Handler(object):

   __slots__ = (
      'req',         # Cyclopath request.py object 
      'doc',         # Our response, as an XML document
      'cp_maint_beg',
      'cp_maint_fin',
      )

   def __init__(self, req):
      self.req = req
      self.cp_maint_beg = None
      self.cp_maint_fin = None

   # ***

   # FIXME: Implement __str__ in each command class so we can log more
   #        meaningful information about each request.
   #
   def __str__(self):
      selfie = (
         'command: %s / req: %s'
         % (type(self),
            self.req,))
      return selfie

   ##
   ## Public interface
   ##

   #
   def doit(self):
      'Process the request, hooking the derived class to do much of the work.'
      # Check that the host IP is not banned and then look for a user password.
      # (Only user_hello uses passwords; after logging on, clients use a token,
      # which is look for in decode_request).
      self.pre_decode()
      # Parse the request packet from the client.
      self.decode_request()
      # Log a simple message about the request.
      log.info('doit: cmd: %s' % (self,))
      # Fetch anything and save anything from and to the database.
      self.fetch_n_save()
      # Do any cleaning up that needs cleaning up.
      self.prepare_metaresp()
      # Prepare the response packet for the client.
      self.prepare_response()

   ##
   ## Private interface
   ##

   #
   def decode_key(self, key, *args, **kwargs):
      return self.req.decode_key(key, *args, **kwargs)

   #
   def decode_key_bool(self, key):
      return self.req.decode_key_bool(key)

   #
   def pre_decode(self):
      pass

   #
   def decode_request(self):
      'Validate and decode the incoming request.'
      pass

   # 
   # In CcpV1 there were two fcns., fetch() and save(), but to optimize
   # postgres and memory bandwitch, we often fetch while we save, so the two
   # operations have been combined into one callback in CcpV2.
   def fetch_n_save(self):
      '''Fetch any needed data from the database. Derived classes should 
         override this class to provide additional behavior. This class 
         checks for user-related stuff.'''
      self.doc = etree.Element('data')
      # See kval_get: We could always return the maintenance mode, but
      # client can poll for this value instead (saving us two sql fetches
      # per request).
      #  # Return the maintenance situation.
      #  (cp_maint_beg, cp_maint_fin,) = self.maintenance_mode()
      #  misc.xa_set(self.doc, 'maint0', cp_maint_beg)
      #  misc.xa_set(self.doc, 'maint1', cp_maint_fin)

   #
   def maintenance_mode(self):
      # Fetch and maybe set the globals, Op_Handler.cp_maint_beg/_fin.
      cp_maint_beg = self.maintenance_mode_fetch('cp_maint_beg')
      cp_maint_fin = self.maintenance_mode_fetch('cp_maint_fin')
      return (cp_maint_beg, cp_maint_fin,)

   #
   def maintenance_mode_fetch(self, attrkey_name):
      cp_maint_mode = getattr(self, attrkey_name, None)
      if cp_maint_mode is None:
         sql_maint_mode = (
            "SELECT value FROM key_value_pair WHERE key = '%s'"
            % (attrkey_name,))
         rows = self.req.db.sql(sql_maint_mode)
         if rows:
            g.assurt(len(rows) == 1)
            cp_maint_mode = rows[0]['value']
            sql_interval = (
               "SELECT value FROM key_value_pair WHERE key = '%s'"
               % (attrkey_name,))
         else:
            cp_maint_mode = ''
         setattr(self, attrkey_name, cp_maint_mode)
      return cp_maint_mode

   #
   def prepare_metaresp(self):
      'Another fetch cycle for things best done after saving.'
      # SYNC_ME: Search fetch doc metadata.
      #log.debug('prepare_metaresp: VERSION.major: %s' % (VERSION.major,))
      misc.xa_set(self.doc, 'major', VERSION.major)
      misc.xa_set(self.doc, 'gwis_version', conf.gwis_version)
      # BUG nnnn: How best to handle updating the user's working revision.
      #           For now, we always send the rid_max, because of how
      #           flashclient is programmed (which is to reset rev_viewport
      #           and make it again when the first GWIS response is received).
      # MAYBE/BUG nnnn: Flashclient and Android should ping periodically for
      #                 the revision ID, e.g., maybe via key_value_get.py.
      rid_max = str(revision.Revision.revision_max(self.req.db))
      misc.xa_set(self.doc, 'rid_max', rid_max)
      # MAYBE: Use abbreviations or pack the data better?
      #  misc.xa_set(self.doc, 'gwv', conf.gwis_version)

   #
   def prepare_response(self):
      pass

   #
   def response_xml(self):
      'Return the XML output of myself.'
      return etree.tostring(self.doc, pretty_print=True)

   #
   def routed_hup(self, db):
      Op_Handler.routed_hup(db)

   #
   @staticmethod
   def routed_hup(db):
      'Tell routed(s) to update itself(themselves).'
      # We can skip the analytics route finders, but for all the 'general'
      # route finders -- those that follow the current working version -- tell
      # 'em to update their graphs.
      rows = db.sql(
         """
         SELECT
            port, branch_id, routed_pers, purpose
         FROM
            routed_ports
         WHERE
            instance = '%s'
            AND purpose = 'general'
         """ % (conf.instance_raw,))
      if rows:
         for row in rows:
            # SYNC_ME: Search: Routed PID filename.
            pidfile = conf.get_pidfile_name(
               int(row['branch_id']), row['routed_pers'], row['purpose'])
            try:
               routed_pid = int(open(pidfile).read())
               os.kill(routed_pid, signal.SIGHUP)
            except Exception, e:
               # FIXME: Search p_error: logs to same as log.error()?
               # Or does it log to the apache log file? [lb] is confused.
               # 2014.09.04: If you manually kill a route finder and don't
               # clean the db, or if a route finder dies, you can check the
               # routed_ports table; if you purposefully killed the finder,
               # delete its row from the table.
               err_s = ('Failed to hup routed: "%s" / %s' 
                        % (e, traceback.format_exc(),))
               #self.req.p_error(err_s)
               # Also log to pyserver log.
               log.warning(err_s)
      else:
         log.warning('routed_hup: Cannot hup route finders: none running.')

   # ***

# ***

