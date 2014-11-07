# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import errno
import os
import socket
import sys

import conf
import g

# Because we use GWIS_Error and know routed_ports, maybe this module doesn't
# belong in util_?
from gwis.exception.gwis_error import GWIS_Error

log = g.log.getLogger('routed_ports')

class Routed_Ports(object):

   def __init__(self):
      g.assurt(False) # Not instantiable.

   #
   @staticmethod
   def find_routed_port_num(db, branch_id, routed_pers, purpose, caller=None):

      # Look for the PID file and raise if not found. There's only
      # one PID file for whatever type of route finder we're looking
      # for, so this'll be the PID of the last route finder of this
      # type that was started. (I.e., you might run a finder that
      # crashes and then run another finder, and the former finder
      # will have left gunk in routed_ports but at least its PID
      # file will be replaced by the latter finder.)
      pidfile = conf.get_pidfile_name(branch_id, routed_pers, purpose)
      the_pid = Routed_Ports.verify_running(pidfile, caller)

      rows = db.sql(
         """
         SELECT
            pid,
            port,
            ready
         FROM
            routed_ports
         WHERE 
            instance = '%s'
            AND branch_id = %d
            AND routed_pers = '%s'
            AND purpose = '%s'
            AND pid = %d
         """ % (conf.instance_raw,
                branch_id,
                routed_pers,
                purpose,
                the_pid,))

      if not rows:
         log.error('find_rd_portn: PID file but no routed_ports: %s / %s'
                   % (the_pid, pidfile,))
         raise GWIS_Error("We're sorry, but that route finder was not found!")

      port_num = rows[0]['port']
      rd_ready = rows[0]['ready']
      if len(rows) > 1:
         # This is probably very unlikely -- two finders with the same PID?
         log.error('find_rd_portn: multiple routed_ports: %s / %s'
                   % (the_pid, pidfile,))
         for row in rows:
            if row['ready']:
               port_num = row['port']
               rd_ready = row['ready']
               break

      # Check that the process is actually running.
      Routed_Ports.verify_ready(pidfile, rd_ready)

      return port_num

   #
   @staticmethod
   def verify_ready(pidfile, is_ready):
      readyfile = '%s-ready' % (pidfile,)
      if (not os.path.exists(readyfile)) or (not is_ready):
         if os.path.exists(readyfile):
            log.error('verify_ready: db says ready but no readyfile: %s'
                      % (readyfile,))
         raise GWIS_Error('%s%s%s'
            % ("We're sorry, but the route finder is being restarted. ",
               #'Please try again in a few minutes.',
               'It may take thirty minutes to start up. ',
               'Please try again soon!',
               ))

   #
   @staticmethod
   def verify_running(pidfile, caller=None):
      the_pid = None
      try:
         the_pid = int(open(pidfile).read())
         if not os.path.exists('/proc/%d' % (the_pid,)):
            the_pid = None
      except:
         pass
      if not the_pid:
         log.error('verify_running: no routed for req.: %s' % (caller,))
         raise GWIS_Error("We're sorry, but that route finder is not running!")
      return the_pid

   #
   @staticmethod
   def pidfiles_cleanup():

      # BUG nnnn: FIXME: Implement this fcn. and cleanup /tmp?

      g.assurt(False)

      # E.g., find all files that startwith /tmp/routed-pid-minnesota.
      # and check their pid and delete the file if the daemon is dead?

# FIXME: Call this on routed startup? Or from cron periodically?

      # FIXME: check PID first.

# FIXME: Put pid in db table, or just recalculate?
# maybe do both? look for /tmp files and use pid to look in routed_ports table
# (rather than parsing the /tmp filename for the branch, ver, and purpose).
      conf.get_pidfile_name(branch_id_or_name, routed_pers, purpose)

      # FIXME: for x in y:
      port_available = False
      try:
         testsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
         # FIXME: Hard-coded port number here...
         testsock.bind(('localhost', 4446))
         # If we're here, bind did not through, so the port is available.
         testsock.close()
         port_available = True
      except socket.error, e:
         # I.e., errno.EADDRINUSE == 98 # Address already in use
         if e.errno != errno.EADDRINUSE:
            log.warning('pidfiles_cleanup: unexpected errno: %d (%s)'
                        % (e.errno, str(e),))
      # If the port is available, clean up the entry in routed_ports.
      if port_available:
         pass # FIXME: Implement.

   # ***

# ***

