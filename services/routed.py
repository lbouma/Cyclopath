#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This is the daemon which handles routing requests. You probably want to
# start and stop it with the routedctl script.
#
# Requests are made using a simple text language, and the result consists of
# (a) the length of the main result in bytes, (b), a newline, and (c) an XML
# document suitable for direct forwarding to the client.
#
# The client is expected to drop the connection when it is finished.
#
# Note that this daemon should be used internally only; it should _not_ be
# exposed to the world directly. The client should be a local apache server
# that does the listening to the outside world for us.
#
# You can use the program "socket" to test this daemon.
# EXPLAIN: What program "socket"? You mean, the python module?

# See routedctl for usage examples.

import datetime
import errno
import gc
import hotshot
import psycopg2
import re
import select
import signal
import socket
import SocketServer
import threading
import time
import traceback

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../pyserver'
                   % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.WARNING
# FIXME: Use DEBUG logging until code is more production-worthy.
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
#conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)
# NOTE: Must manually configure the logger
# FIXME: It took me a few minutes to remember this... how to remind self when
# files need it? Like: ccp.py, routed, gwis_mod_python.
#conf.init_logging(True, False, conf.log_line_len)


# Fixed: All of the route finders will end up writing to the same log file!
#        Causing lots of interleaving. Hrmpf. (I added the thread id to _log.)
# FIXME: Added add_tid/include_thread_id but maybe we should have it print the
#        port number instead?
conf.init_logging(True, False, conf.log_line_len, log_level, True)

log = g.log.getLogger('routed')

from grax.access_level import Access_Level
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
import gwis.request
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_base
from item.feat import branch
from item.feat import route
from item.util import landmark
from item.util import ratings
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from planner.travel_mode import Travel_Mode
import planner.routed_p1.tgraph
import planner.routed_p2.tgraph
import planner.routed_p3.tgraph
from util_ import db_glue
from util_ import mem_usage
from util_ import misc
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
import VERSION

script_name = 'Cyclopath Route Daemon'
script_version = '1.1'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-06-21'

# *** Server class

# Bug 2304: A forked Python process duplicates its parent's memory footprint
#           because Copy-on-demand doesn't work with Python reference
#           counters. So instead of ForkingMixIn, use ThreadingMixIn.
# BUG nnnn: "In CPython, the global interpreter lock, or GIL, is a mutex that
# prevents multiple native threads from executing Python bytecodes at once.
# This lock is necessary mainly because CPython's memory management is not
# thread-safe. (However, since the GIL exists, other features have grown to
# depend on the guarantees that it enforces.)"
#   http://wiki.python.org/moin/GlobalInterpreterLock
# So the ThreadingMixIn is still just one CPU thread. But ForkingMixIn will
# be able to take advantage of other CPU threads. So we could use ForkingMixIn
# if we gaited with routed_ports to make sure we didn't process too many
# requests at once.
# What this really means is that either the route finder should be written in
# C, or we could use Jython or IronPython
# http://wiki.python.org/moin/IronPython (.NET, so Windows only, probably)
# BUG nnnn: Test ThreadingMixIn with http://www.jython.org/
# BUG nnnn: If just one thread is allowed from conf, then use ThreadingMixIn,
# since ForkingMixIn always forks and runs slow on dev machines.
#class Server(SocketServer.ThreadingMixIn, SocketServer.TCPServer):
class Server_Threading(SocketServer.ThreadingMixIn, SocketServer.TCPServer):

   __slots__ = (
      'routed',
      )

   def __init__(self, server_address, handler_class, routed,
                      allow_reuse_address=True):
      # Note: ThreadingMixIn/ForkingMixIn do/does not have an __init__
      log.debug('Server: server_address: %s / allow_reuse: %s'
                % (server_address, allow_reuse_address,))
      # From the Python library reference, "Running an example several times
      # with too small delay between executions, could lead to this error:
      #   socket.error: [Errno 98] Address already in use
      # This is because the previous execution has left the socket in a
      # TIME_WAIT state, and can't be immediately reused."
      #   s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      #   s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
      #   s.bind((HOST, PORT))
      try:
         self.allow_reuse_address = allow_reuse_address
         # NOTE: self.timeout is None.
         #       2012.04.22: py2.7: [lb] tried self.timeout=10, both here and
         #       after the init, and defined def handle_timeout(self), and
         #       wrapped the handle_request call, but I never saw a timeout.
         # Note: self.daemon_threads = True # don't wait for thread on shutdown
         # Note: self.request_queue_size usually defaults to 5, which is max
         #       no. of simultaneous requests the server will process.
         # BUG nnnn: gait no. simultaneous requests in pyserver
         SocketServer.TCPServer.__init__(self, server_address, handler_class)

         # FIXME: The request_queue_size defaults to only 5...
         # FIXME: Do this?:
         #  self.request_queue_size = max(self.request_queue_size,
         #                                conf.routed_async_limit,
         #                                conf.analysis_async_limit,)
         # [lb] tested with six brower windows sending route requests,
         #      but maybe we should test twenty route requests.

      except socket.error, e:
         # [Errno 98] Address already in use
         log.error('routed: port already in use: %d [%s] / %s'
                   % (server_address[1], server_address[0], str(e),))
         if e[0] != 98:
            log.error('Unexpected: Not [Errno 98] Address already in use')
         raise GWIS_Error('Port in use')
      except Exception, e:
         log.error('Unexpected Exception: "%s" / %s'
                   % (str(e), traceback.format_exc(),))
         raise GWIS_Error('Unknown error')
      self.routed = routed

# C.f. Server_Threading
class Server_Forking(SocketServer.ForkingMixIn, SocketServer.TCPServer):

   __slots__ = (
      'routed',
      )

   def __init__(self, server_address, handler_class, routed,
                      allow_reuse_address=True):
      # Note: ThreadingMixIn/ForkingMixIn do/does not have an __init__
      log.debug('Server: server_address: %s / allow_reuse: %s'
                % (server_address, allow_reuse_address,))
      try:
         self.allow_reuse_address = allow_reuse_address
         SocketServer.TCPServer.__init__(self, server_address, handler_class)

         # FIXME: The request_queue_size defaults to only 5...
         # FIXME: Do this?:
         # self.request_queue_size = max(self.request_queue_size,
         #                               conf.routed_async_limit,
         #                               conf.analysis_async_limit,)
         # [lb] tested with six brower windows sending route requests,
         #      but maybe we should test twenty route requests.

      except socket.error, e:
         # [Errno 98] Address already in use
         log.error('routed: port already in use: %d [%s] / %s'
                   % (server_address[1], server_address[0], str(e),))
         if e[0] != 98:
            log.error('Unexpected: Not [Errno 98] Address already in use')
         raise GWIS_Error('Port in use')
      except Exception, e:
         log.error('Unexpected Exception: "%s" / %s'
                   % (str(e), traceback.format_exc(),))
         raise GWIS_Error('Unknown error')
      self.routed = routed

# *** Handler class

class Handler(SocketServer.StreamRequestHandler):

   # Regexes matching each command
   cmd_res = {
      #
      ## Configuration Parameters
      #
      # User making request
      'user': re.compile(r'^user (.+)'),
      'host': re.compile(r'^host (.+)'),
      'ipaddy': re.compile(r'^ipaddy (.+)'),
      'session_id': re.compile(r'^session_id (.+)'),
      'caller_source': re.compile(r'^source (.+)'),
      # Specific route being requested (from the client).
      'beg_addr': re.compile(r'^beg_addr (.+)'),
      'beg_ptx': re.compile(r'^beg_ptx (.+)'),
      'beg_pty': re.compile(r'^beg_pty (.+)'),
      'fin_addr': re.compile(r'^fin_addr (.+)'),
      'fin_ptx': re.compile(r'^fin_ptx (.+)'),
      'fin_pty': re.compile(r'^fin_pty (.+)'),
      # If 'analysis', the caller (the route_analysis.py script) also sets the
      # beginning and finishing node IDs.
      'beg_nid': re.compile(r'^beg_nid (.+)'),
      'fin_nid': re.compile(r'^fin_nid (.+)'),
      # Route-finder parameters used to calculate route.
      'travel_mode': re.compile(r'^travel_mode (.+)'),
      # Planner p1 options.
      'priority': re.compile(r'^priority (\w+) (.+)'),
      # Transit/Multi-modal Planner p2 options.
      'p2_depart_at': re.compile(r'^p2_depart (.+)'),
      'p2_transit_pref': re.compile(r'^p2_txpref (.+)'),
      # Planner p3 options.
      'p3_wgt': re.compile(r'^p3_wgt (.+)'),
      'p3_rgi': re.compile(r'^p3_rgi (\d+)'),
      'p3_bdn': re.compile(r'^p3_bdn (\d+)'),
      'p3_alg': re.compile(r'^p3_alg (.+)'),
      # Personalized routes using tag preferences.
      'rating_min': re.compile(r'^rating_min (.+)'),
      'tagpref': re.compile(r'^tagpref (\d+) (\d+)'),
      'tags_use_defaults': re.compile(r'^use_defaults (\d)'),
      # Whether or not to spend a little extra time to compute landmarks.
      'add_lmrks': re.compile(r'^add_lmrks (\d)'),
      # Output format: GML (default) or gpx
      'asgpx': re.compile(r'^asgpx (\d)'),
      # Whether or not to save the route after it's found.
      # This is True for new or saved routes from flashclient,
      # and not True for route analysis and route stop editing.
      'save_route': re.compile(r'^save_route (\d)'),
      #
      # NOTE: We used to allow changing branch ID and/or revision ID on the fly
      # and reloading the map, but because Python doesn't return memory pages
      # to the free pool, we don't support this anymore. You should kill routed
      # and start a new instance with the branch ID and revision you want. No:
      #  'branch_id': re.compile(r'^branch_id (\d+)'),
      #  'revision_id': re.compile(r'^revision_id (\d+)'),
      #  # Reload the graph after changing the branch and revision
      #  'reload_graph': re.compile(r'^reload_graph'),
      #
      ## Routed Commands
      #
      # The hello command is used to figure out when the server is ready.
      'hello': re.compile(r'^hello'),
      # The command that triggers the route-finding operation.
      'route': re.compile(r'^route'),
      }

   # Don't be fooled: for this class, Python won't raise if you assign
   # to attributes not named here in __slots__.
   __slots__ = (
      #
      'username', #'user',
      'host',
      'ipaddy',
      'session_id',
      'caller_source',
      #
      'beg_xy',
      'beg_nid',
      'beg_addr',
      'fin_xy',
      'fin_nid',
      'fin_addr',
      # Temporary vars.
      'beg_ptx',
      'beg_pty',
      'fin_ptx',
      'fin_pty',
      'travel_mode',
      'travel_modes',
      # p1 options
      'p1_priority',
      # p2 options
      'p2_depart_at',
      'p2_transit_pref',
      # p3 options
      'p3_weight_type',
      'p3_rating_pump',
      'p3_burden_pump',
      'p3_spalgorithm',
      # personalized options (all p*s)
      'rating_min',
      'tagprefs',
      'tags_use_defaults',
      #
      'compute_landmarks',
      'as_gpx',
      'save_route',
      )

   #
   def reset(self):
      #
      log.debug('reset')
      #
      # NOTE: SYNC_ME: These must have same defaults as other class.
      self.username = conf.anonymous_username
      #
      self.host = None
      self.ipaddy = None
      self.session_id = None
      self.caller_source = None
      #
      self.beg_xy = None
      self.beg_nid = None
      self.beg_addr = None
      self.fin_xy = None
      self.fin_nid = None
      self.fin_addr = None
      #
      self.travel_modes = list()
      #
      self.p1_priority = 0.5
      #
      self.p2_depart_at = ''
      self.p2_transit_pref = -1 # FIXME: This ranges -4 to 6 in flashclient?
                                # Default should be 0? None? -1 is from [cd].
      #
      self.p3_weight_type = ''
      self.p3_rating_pump = 0
      self.p3_burden_pump = 0
      self.p3_spalgorithm = ''
      #
      self.rating_min = None
      self.tagprefs = dict()
      self.tags_use_defaults = False
      #
      self.compute_landmarks = False
      self.as_gpx = False
      self.save_route = True

   #
   def handle(self):
      '''Manage the routed protocol dialogue on the incoming connection.'''

      log.debug('routed.handle: handling new connection')

      # Startup

      if conf.profiling:
         profiler = hotshot.Profile(conf.profile_file + '.routed')
         profiler.start()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      self.reset()

      priorities = {}

      # SECURITY: Someone could keep us very busy by sending us endless
      # commands. We should check that we're not getting redundant commands.
      # Also, we don't close the connection after sending the final route
      # response, but instead keep listening on the pipe until the client
      # disconnects (this could be because it's not clean otherwise, but it
      # feels like we should be proactively shutting down the connection when
      # we're done with it). Granted, the connection comes locally from apache,
      # but still! (Maybe we at least assert that route requests come locally.)
      while True:

         try:

            # Read a line
            line = self.rfile.readline()
            if line == '':
               # client went away
               log.debug('client closed connection')
               break
            line = line.rstrip()

            # Parse it
            crm = dict()
            for cr in Handler.cmd_res:
               crm[cr] = Handler.cmd_res[cr].search(line)

            # Execute the appropriate command. Note that finding an actual
            # route happens when the "route" command arrives.

            #
            ## Configuration Parameters
            #
            # NOTE: We expect local requests only. So it might seem weird
            #       to accept the username without, say, also verying the
            #       token... and maybe it is still weird... but this is
            #       the way things are: the route daemon generally trusts
            #       that the data it receives on the pipe is already cleansed
            #       and verified and can be trusted...
            if crm['user']:
               self.username = crm['user'].group(1)
               if not self.username:
                  log.warning('Username missing?! Using anon.')
                  self.username = conf.anonymous_username
            elif crm['host']:
               self.host = crm['host'].group(1)
            elif crm['ipaddy']:
               self.ipaddy = crm['ipaddy'].group(1)
            elif crm['session_id']:
               self.session_id = crm['session_id'].group(1)
            elif crm['caller_source']:
               self.caller_source = crm['caller_source'].group(1)
            #
            elif crm['beg_ptx']:
               self.beg_ptx = float(crm['beg_ptx'].group(1))
            elif crm['beg_pty']:
               self.beg_pty = float(crm['beg_pty'].group(1))
            elif crm['beg_nid']:
               self.beg_nid = int(crm['beg_nid'].group(1))
            elif crm['beg_addr']:
               self.beg_addr = crm['beg_addr'].group(1)
            #
            elif crm['fin_ptx']:
               self.fin_ptx = float(crm['fin_ptx'].group(1))
            elif crm['fin_pty']:
               self.fin_pty = float(crm['fin_pty'].group(1))
            elif crm['fin_nid']:
               self.fin_nid = int(crm['fin_nid'].group(1))
            elif crm['fin_addr']:
               self.fin_addr = crm['fin_addr'].group(1)
            #
            elif crm['travel_mode']:
               self.travel_mode = crm['travel_mode'].group(1)
               self.travel_modes.append(crm['travel_mode'].group(1))
               log.debug('handle: travel_modes: %s' % (self.travel_modes,))
            #
            elif crm['priority']:
               ptag = crm['priority'].group(1)
               pval = float(crm['priority'].group(2))
               priorities[ptag] = pval
            #
            elif crm['p2_depart_at']:
               self.p2_depart_at = crm['p2_depart_at'].group(1)
               log.debug('handle: p2_depart_at: %s' % (self.p2_depart_at,))
            elif crm['p2_transit_pref']:
               self.p2_transit_pref = int(crm['p2_transit_pref'].group(1))
               log.debug('handle: p2_transit_pref: %s'
                         % (self.p2_transit_pref,))
            #
            elif crm['p3_wgt']:
               self.p3_weight_type = crm['p3_wgt'].group(1)
            elif crm['p3_rgi']:
               self.p3_rating_pump = int(crm['p3_rgi'].group(1))
            elif crm['p3_bdn']:
               self.p3_burden_pump = int(crm['p3_bdn'].group(1))
            elif crm['p3_alg']:
               self.p3_spalgorithm = crm['p3_alg'].group(1)
            #
            elif crm['rating_min']:
               self.rating_min = float(crm['rating_min'].group(1))
            elif crm['tagpref']:
               tid = int(crm['tagpref'].group(1))
               # FIXME: In V2, tap_preference_type.code was renamed id
               #code = int(crm['tagpref'].group(2))
               #self.tagprefs[tid] = code
               tpt_id = int(crm['tagpref'].group(2))
               self.tagprefs[tid] = tpt_id
            elif crm['tags_use_defaults']:
               self.tags_use_defaults = bool(int(crm['tags_use_defaults']
                                                               .group(1)))
            #
            elif crm['add_lmrks']:
               self.compute_landmarks = (int(crm['add_lmrks'].group(1)) == 1)
            #
            elif crm['asgpx']:
               self.as_gpx = (int(crm['asgpx'].group(1)) == 1)
            #
            elif crm['save_route']:
               self.save_route = (int(crm['save_route'].group(1)) == 1)
            #
            ## Routed Commands
            #
            elif crm['hello']:
               self.xml_print(etree.Element('hello'))
            #
            elif crm['route']:
               # This is where's the beef's at.
               xml = self.route_as_xml()
               self.xml_print(xml)
            #
            else:
               log.warning('ignoring unknown command "%s"' % (line,))

         except GWIS_Warning, e:

            xml = e.as_xml()
            self.xml_print(xml)
            # FIXME: So we continue the while loop?

         except Exception, e:

            log.error('Unexpected Exception!: "%s" / %s'
                        % (str(e), traceback.format_exc(),))
            # FIXME: EXPLAIN: What does the client receive/do? Does this kill
            # routed? Does it need to be restarted?: alert a developer! (SMS?)
            # BUG nnnn: Better routed error handling

            # It's not safe to continue after random exception, so return.
            return

      # end: while True

      # Legacy: Clients send "priority bike %.f"
      #               and/or "priority dist %.f"
      try:
         self.p1_priority = priorities['bike']
      except KeyError:
         try:
            self.p1_priority = 1.0 - priorities['dist']
         except KeyError:
            pass

      # Cleanup

      if conf.profiling:
         profiler.close()

      conf.debug_log_mem_usage(log, usage_0, 'routed.handle')

      log.debug('routed.handle: done.')

   #
   def xml_print(self, xml):
      # len(xml) will be incorrect if xml becomes a Unicode string.
      self.wfile.write('%d\n' % (len(xml)))
      self.wfile.write(xml)

   #
   def route_as_xml(self):
      '''Calculate a route from beg_addr to fin_addr and return the result
         as an XML string.'''

      # Time the route-finding operation
      log.debug('finding route')
      time_0 = time.time()

      # Get a handle to the route daemon.
      routed = self.server.routed

      # Currently, only one travel_mode is supported.
      if len(self.travel_modes) == 1:
         try:
            travel_mode = int(self.travel_modes[0])
         except ValueError:
            travel_mode = Travel_Mode.lookup_by_str[self.travel_modes[0]]
      else:
         g.assurt(len(self.travel_modes) == 0)
         travel_mode = Travel_Mode.bicycle
      if not Travel_Mode.is_valid(travel_mode):
         raise GWIS_Error('Unrecognized travel mode: %s' % (travel_mode,))
      # This is a hack but it's only because the code used to just
      # rely on travel_modes array... which is never more than 1 items deep.
      self.travel_mode = travel_mode
      self.travel_modes = [travel_mode,]

      # Get a handle to the database.
      db = db_glue.new()

      # BUG 2688: Use self.req.db.transaction_retryable?

      # Since we're contacted from apache through a socket connection, we don't
      # have an apache or Cyclopath request of our own. Create a basic one that
      # we can pass to the route object.
      apache_req = None
      req = gwis.request.Request(apache_req)
      req.db = db
      # Use the user's username, which was passed via the socket. (We don't
      # use self.cli_opts.username, which is the user-context of the network
      # graph (generally the anon user).)
      req.client.ip_addr = self.ipaddy
      req.client.remote_ip = self.ipaddy
      req.client.remote_host = self.host
      # See below: req.client.remote_what = self.caller_source
      # Skipping: req.client.browser_id
      req.client.session_id = self.session_id
      req.client.username = self.username
      req.client.user_id = User.user_id_from_username(db, self.username)
      req.client.user_group_id = User.private_group_id(db, self.username)
      #req.client.request_is_mobile
      #req.client.request_is_local
      #req.client.request_is_script
      #req.client.request_is_secret
      #req.client.token_ok
      # The branch_id is static; the user cannot specify it via the socket.
      req.branch.branch_id = routed.cli_args.branch_id
      req.branch.branch_hier = routed.cli_args.branch_hier

      # The revision doesn't really matter for route finding -- if this is a
      # normal ('general') route finder, this is the Current revision, or if
      # this is an 'analysis' route finder, this is an Historic revision, but
      # in neither case can we tell search_graph what revision to use, since
      # it's already loaded it. But we need the revision for later in this fcn.
      # and also for the item classes to work right. (That is, we're calling
      # search_graph which uses routed.graph which has already loaded a
      # specific revision of the graph.)
      req.revision.rev = routed.cli_args.revision

      # Find route
      rt = None
      try:

         # FIXME: This blocks while p1 and p2 planners/route daemons are
         #        updating (the p3 planner doesn't hold on to the lock
         #        while it runs).
         routed.searchers_increment()

         if not routed.shutdown:
            rt = route.Many().search_graph(req, routed, self)
            log.debug('route search completed')
         # else, we'll return that the route finder is restarting.
      except GWIS_Error, e:
         # This is, e.g., "Locations given are too close to each other".
         log.info('route op. failed/gwis_errr: %s' % (str(e),))
         raise
      except GWIS_Warning, e:
         log.info('route op. failed/gwis_warn: %s' % (str(e),))
         raise
      except IOError, e:
         # If the error is the client simply going away, ignore it.
         # MAYBE: See dir(socket.errno), and os.strerror(socket.errno.EXXXX)
         #        To which constants do these map?
         log.debug('route_as_xml: IOError: %s / %s' % (e[0], str(e),))
         if ((str(e).find('Write failed, client closed connection.') == 0)
             or (str(e).find('Client read error (Timeout?)') == 0)):
            log.info('route op. failed/0: ignoring IOError: %s' % (str(e),))
         else:
            log.error('route op. failed/2: %s' % (str(e),))
            # FIXME: The log file is not displaying the right stack trace...
            log.error('Stack trace (2a): %s' % (traceback.format_exc(),))
            #log.error('Stack trace (2b): %s' % (traceback.format_stack(),))
            #
            db.close()
            raise
      except Exception, e:
         log.error('route op. failed/3: %s' % (str(e),))
         # FIXME: The log file is not displaying the right stack trace...
         log.error('Stack trace (3a): %s' % (traceback.format_exc(),))
         #log.error('Stack trace (3b): %s' % (traceback.format_stack(),))
         #
         db.close()
         raise
      finally:
         routed.searchers_decrement()

      # BUG 2688: Use transaction_retryable?
      db.transaction_commit()

      if rt is None:
         raise GWIS_Error(
            'The route finder is restarting. '
            #+ 'Please try again within the next half hour.')
            + 'It may take thirty minutes to start up.')

      # Save the route if it's a real user request and not a routing analytics
      # request. (Routing Analytics always sets revision_id; command.route_get
      # does not.)
      # Also, route sharing, circa 2012.02, introduced computing of sub-routes,
      # which are also not saved.

      if ((routed.cli_opts.routed_purpose == 'general')
          and (self.save_route)):

         # Setup the query context object.
         qb = req.as_iqb()

         qb.remote_what = self.caller_source

         # See: rt.setup_item_revisionless_defaults(qb, force=True)
         log.debug('route_as_xml: %s / %s / %s / %s / %s'
                   % (rt.edited_date,
                      rt.edited_user,
                      rt.edited_addr,
                      rt.edited_host,
                      rt.edited_what,))
         rt.edited_date = datetime.datetime.now()
         rt.edited_user = qb.username
         rt.edited_addr = qb.remote_ip
         rt.edited_host = qb.remote_host
         rt.edited_what = qb.remote_what

         # Save the route at the current revision and commit the transaction.
         #
         # NOTE: Route version=1 is saved by the route daemon. So there's
         #       another process/request: the apache pyserver request. It
         #       sends us (pipes us) the route request and information about
         #       the user making the request (username, hostname and ip, etc.).
         rt.prepare_and_commit_revisionless(qb, Grac_Manager())

      else:
         # This is either a route for analysis or a route not being saved.
         # Compute that which did not get computed via the save functions.
         rt.compute_stats_raw()

      # Landmarks feature.
      # 2014.05.09: [lb] making this feature opt-in after seeing it take 30
      #             seconds on a route from Gateway Fountain to Guthrie.
      if conf.landmarks_experiment_active and self.compute_landmarks:
         time_0 = time.time()
         landmark.landmarks_compute(rt.rsteps, req.as_iqb())
         log.debug('route_as_xml: landmarks_compute took %s'
                   % (misc.time_format_elapsed(time_0),))

         # else: don't do landmarks for now. It's slow. I'm seeing:
         #  May-08 21:11:47 DEBG routed # landmarks_compute took 30.53 secs.
         # and mobile is timing out.
     # FIXME/BUG nnnn: This should be opt-in from the client.

      xml = rt.as_xml(db, self.as_gpx)

      db.close()

      log.debug('route found: %s'
                % (misc.time_format_elapsed(time_0),))

      return xml

   # ***

# *** Logfile write() wrapper

class File_Log(object):

   '''Simple file-like wrapper class which logs writes.'''

   __slots__ = ('log',
                'note')

   #
   def __init__(self, logger):
      self.log = logger
      self.note = ''

   #
   def write(self, s):
      for c in s:
         self.writec(c)

   #
   def writec(self, c):
      if c == '\n':
         self.log.error(self.note)
         self.note = ''
      else:
         self.note += c

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version,
                                     usage=None)

   #
   def prepare(self):
      '''Defines the CLI options for this script'''

      Ccp_Script_Args.prepare(self)

      # Routed options.

      ## FIXME: I think we can delete this argument. Convention is to use
      ##        PYSERVER_HOME
      #self.add_argument('-H', '--pyserver_home', dest='pyserver_home',
      #   action='store', default=True,
      #   help='directory on your local hard drive where cyclopath lives')

      # The version of the daemon to use.
      self.add_argument('-V', '--routed_pers', dest='routed_pers',
         action='store', default='p1',
         help='routed vers to use: "p1", "p2", or "p3"')

      # The purpose of the daemon.
      self.add_argument('--purpose', dest='routed_purpose',
         action='store', default='general',
         help='routed purpose: "general" or "analysis-*"')

      #
      self.add_argument('--shp_cache_dir', dest='shp_cache_dir',
         action='store', default='',
         help='Path to the Shapefile cache directory for the p3 planner')
      self.add_argument('--source_shp', dest='source_shp',
         action='store', default='',
         help='Path to the Shapefile for the p3 planner')
      self.add_argument('--source_zip', dest='source_zip',
         action='store', default='',
         help='Path to the Zipfile of the Shapefile for the p3 planner')

      # 2013.03.19: routedctl used to specify instance but now it's always
      #             specified as an environment variable.
      # self.add_argument('-I', '--instance', dest='instance',
      #    action='store', default='minnesota',
      #    help='instance: "minnesota" or "colorado"')

      # FIXME: This is for devs to use until we understand better.
      # If True, don't close the daemon io handles.
      self.add_argument('--no_io_close', dest='no_io_close',
         action='store_true', default=False,
         help='for use by analytics to prevent daemon from sticking')

      # The revision ID to initialise routed on.
      self.add_argument('--regions', dest='regions',
         action='store', default=None,
         help='regions(s) of the map to load')

   #
   def verify(self):
      '''Verify the options. Handle the simplest of 'em.'''

      verified = Ccp_Script_Args.verify(self)

      if self.cli_opts.routed_pers == 'p3':
         self.cli_opts.travel_mode = Travel_Mode.wayward
      elif self.cli_opts.routed_pers == 'p2':
         self.cli_opts.travel_mode = Travel_Mode.transit
         # BUG nnnn: Support analysis for p2
         g.assurt(self.cli_opts.routed_purpose == 'general')
      elif self.cli_opts.routed_pers == 'p1':
         self.cli_opts.travel_mode = Travel_Mode.classic
      else:
         log.error('Please specify --routed_pers=p3|p2|p1')
         verified = False
         self.handled = True

      if self.cli_opts.routed_purpose == 'general':
         g.assurt(isinstance(self.revision, revision.Current))
      elif self.cli_opts.routed_purpose.startswith('analysis'):
         # NOTE: If you're testing (see SKIP_ROUTED), you might be using
         # Current...
         #g.assurt(isinstance(self.revision, revision.Historic))
         g.assurt(isinstance(self.revision, revision.Historic)
                  or isinstance(self.revision, revision.Current))
      else:
         g.assurt(False)

      return verified

# *** Route Daemon Graph Update Thread

class Graph_Updater(threading.Thread):

   def __init__(self, routed):
      threading.Thread.__init__(self)
      self.routed = routed
      self.keep_running = threading.Event()

   # This fcn. is Graph_Updater's thread.
   def run(self):
      log.debug('Graph_Updater: running')
      self.keep_running.set()
      while self.keep_running.isSet():
         try:
            self.routed.lock_updates.acquire()
            while (self.keep_running.isSet()
                   and not self.routed.update_required):
               self.routed.lock_updates.wait()
            if self.routed.processing_cnt == 0:
               while (self.keep_running.isSet()
                      and self.routed.update_required):
                  log.debug('keep_running: %s / ureq: %s'
                            % (self.keep_running.isSet(),
                               self.routed.update_required,))
                  self.routed.state_update()
         except g.Ccp_Shutdown, e:
            log.warning('Ccp_Shutdown deteted.')
            g.assurt(not self.keep_running.isSet())
         except Exception, e:
            log.warning('Unexpected Exception: "%s" / %s'
                        % (str(e), traceback.format_exc(),))
            raise
         finally:
            self.routed.lock_updates.release()
      log.debug('Graph_Updater: done running')

   # This fcn. is called from routed's thread.
   def stop(self, wait=True):
      log.debug('Graph_Updater.stop: stopping...')
      self.keep_running.clear()
      if wait:
         log.debug('Graph_Updater.stop: getting lock_updates lock...')
         self.routed.lock_updates.acquire()
         log.debug('Graph_Updater.stop: got lock_updates lock')
         self.routed.lock_updates.notify()
         self.routed.lock_updates.release()
         if self.isAlive():
            log.debug('Graph_Updater.stop: joining...')
            self.join()
         log.debug('Graph_Updater.stop: stopped')

# *** The Route Daemon

# FIXME: Do we need to synchronize log messages? I.e., if two threads call
# log.debug(), is the output interleaved in the log file?

# WARNING: This class is used by multiple threads. Make sure you lock resources
#          as appropriate!
class Route_Daemon(Ccp_Script_Base):

   __slots__ = (
      'port',              # Port being listened on.
      'server',            # Handle to the Server.
      'shutdown',          # True if the route daemon is shutting down.
      'pidfiles',          # File(s) containing this process's PID.
      'readyfile',         # File whose existence indicates routed is ready.
      'processing_cnt',    # Number of route requests being processed.
      'lock_updates',      # Gait access to updating the Graph.
      'update_thread',     # Graph_Updater
      'graph',             # The graph holds all of the byways with tags and
                           #  attributes, as well as the predictor (which
                           #  stores all of the ratings). The graph is
                           #  sub-classed to implement different algorithms.
      'update_required',   # True if db has been updated; set by SIGHUP hndler.
      'update_db',         #
      )

   #
   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.port = None
      self.server = None
      self.shutdown = False
      self.pidfiles = []
      self.readyfile = None
      self.processing_cnt = 0
      self.lock_updates = threading.Condition()
      self.update_thread = Graph_Updater(self)
      #
      self.graph = None
      self.reset()
      #
      self.skip_query_builder = True

   #
   def reset(self):
      if self.graph is not None:
         # Graphserver is C-code, so explicitly clean it up
         self.graph.destroy()
         self.graph = None
      self.update_required = False
      self.update_db = None

   #
   @staticmethod
   def routedctl_path():
      g.assurt(os.getenv('PYSERVER_HOME'))
      routedctl_path = ('%s/../services/routedctl'
                        % (os.getenv('PYSERVER_HOME'),))
      return routedctl_path

   # *** routed_ports helpers

   #
   def port_claim(self):

      g.assurt(self.port is None)
      g.assurt(self.server is None)

      # Start at the starting port and increase by 1 until an insert succeeds,
      # or we run out of ports. Unless we're being asked to use a well known
      # port.
      if conf.remote_routed_role == 'server':
         port_0 = conf.remote_routed_port
         # Well... what about additional branches' finders?
         #port_n = conf.remote_routed_port + 1
         port_n = conf.remote_routed_port + conf.maximum_routed_ports
      else:
         port_0 = conf.starting_routed_port
         port_n = conf.starting_routed_port + conf.maximum_routed_ports

      db = db_glue.new()

      db.transaction_lock_try('routed_ports', caller='routed.py')

      for port_num in xrange(port_0, port_n, 1):
         # This checks if Ccp thinks the port is available, but not the OS.
         if not self.port_is_claimed(db, port_num):
            # Try to open the port. If it fails, we'll try a different port.
            self.setup_server(port_num)
            if self.server is not None:
               # In routed_ports, make an entry for us.
               self.port_reserve(db, port_num)
               self.port = port_num
               break

      if self.port:
         g.assurt(self.server is not None)
         log.info('port_claim: port: %d / branch: %d / path: %s / instance: %s'
                  % (self.port, self.cli_args.branch_id,
                     conf.ccp_dev_path, conf.instance_raw,))
         # BUG 2688: Use transaction_retryable?
         db.transaction_commit()
      else:
         g.assurt(self.server is None)
         log.error(
            'port_claim: no more ports! tried from %d to %d / %d on %s:%s.'
            % (port_0, port_n - 1, self.cli_args.branch_id,
               conf.ccp_dev_path, conf.instance_raw,))
         db.transaction_rollback()

      db.close()

      if self.server is None:
         raise GWIS_Error('Unable to start server: no ports available.')

   #
   def port_is_claimed(self, db, port_num):
      is_claimed = False
      if port_num:
         rows = db.sql("SELECT * FROM routed_ports WHERE port = %d"
                       % (port_num,))
         if rows:
            g.assurt(len(rows) == 1)
            is_claimed = True
      return is_claimed

# BUG nnnn: Does [mm]'s new use of purpose breaks this fcn?
# NOTE: Using analysis-GUID means the other columns for analysis jobs are not
# important, since the job just looks up the port from the table using the
# unique name... but for the general route finders the other columns are still
# necessary.

   #
   def port_release(self):
      if self.port:
         db = db_glue.new()
         db.transaction_lock_try('routed_ports', caller='routed.py')
         if self.port_is_claimed(db, self.port):
            db.sql("DELETE FROM routed_ports WHERE port = %d" % (self.port,))
            # BUG 2688: Use transaction_retryable?
            db.transaction_commit()
         else:
            log.error('Cannot clean up routed_ports: port not claimed: %s'
                      % (self.port,))
            db.transaction_rollback()
         db.close()
         # NOTE: We don't actually release the port from the system.
         self.port = None

   #
   def port_reserve(self, db, port_num):
      # This is called after we've started the server on a port, so we know the
      # port we're adding is good. That also means we can clear any gunk we may
      # have left behind if we were killed.
# FIXME: Don't do this for p2 finder if you're starting a new one like you want
# to switch over to new one, cause new one would do this before it was started.
#
# So maybe do this step once the route finder is ready.
# What about a 'ready' flag in the database? I.e., for
# restarting p2, otherwise which route finder gets chosen?
# So on sighup, routed starts a new p2 (if one not already starting, otherwise
# mark that a new-new one should get started), and then the new routed
# shutsdown the old routed? I think that'll work -- the old routed can finish
# processing requests and then exit silently. so on sighup p2 can check if
# it's 'ready', and if not, it can shutdown (checking that another one is
# ready, i guess).
# FIXME: p2 can update if just attrs changed. but if endpoints change, then
# graphserver has to be restarted? but you can restart in background and
# smoothly transition once new finder is started. (you could do this for p1
# periodically, too)


      # The p1 route finder knows how to update itself, so there's only ever
      # one instance of it running. And for analytics, there should be only one
      # (of any one configuration).
      if ((self.cli_opts.routed_pers == 'p1')
          or (self.cli_opts.routed_purpose.startswith('analysis'))):
         db.sql(
            """
            DELETE FROM
               routed_ports
            WHERE
               instance='%s'
               AND branch_id=%d
               AND routed_pers='%s'
               AND purpose='%s'
            """ % (conf.instance_raw,
                   self.cli_args.branch_id,
                   self.cli_opts.routed_pers,
                   self.cli_opts.routed_purpose,
                   ))
      # Otherwise, for p2 route finder, we may start a new route finder in the
      # background and let the old one keep running; then, when the new route
      # finder is ready, then we'll delete the old port numbers from the table.

      db.sql(
         """
         INSERT INTO routed_ports
            (pid, port, ready, instance,
             branch_id, routed_pers, purpose)
         VALUES
            (%d, %d, FALSE, '%s',
             %d, '%s', '%s')
         """ % (0,
                port_num,
                # FALSE,
                conf.instance_raw,
                self.cli_args.branch_id,
                self.cli_opts.routed_pers,
                self.cli_opts.routed_purpose,
                ))

   #
   def port_update_routed_ports(self):
      db = db_glue.new()
      db.transaction_lock_try('routed_ports', caller='routed.py')
      db.sql(
         """
         UPDATE routed_ports
         SET pid = %d
         WHERE port = %d
           AND ready IS FALSE
           AND instance = '%s'
           AND branch_id = %d
           AND routed_pers = '%s'
           AND purpose = '%s'
         """ % (os.getpid(),
                self.port,
                conf.instance_raw,
                self.cli_args.branch_id,
                self.cli_opts.routed_pers,
                self.cli_opts.routed_purpose,
                ))
      db.transaction_commit()
      db.close()

   #
   def ports_remove_similar_servers(self, db):
      db.sql(
         """
         DELETE FROM
            routed_ports
         WHERE
            instance='%s'
            AND branch_id=%d
            AND routed_pers='%s'
            AND purpose='%s'
            AND (NOT port=%d)
         """ % (conf.instance_raw,
                self.cli_args.branch_id,
                self.cli_opts.routed_pers,
                self.cli_opts.routed_purpose,
                self.port,
                ))

   #
   def ports_supercede_similar_servers(self, db):
      db.sql(
         """
         UPDATE
            routed_ports
         SET
            ready = TRUE
         WHERE
            port=%d
         """ % (self.port,
                ))
      db.sql(
         """
         UPDATE
            routed_ports
         SET
            ready = FALSE
         WHERE
            instance='%s'
            AND branch_id=%d
            AND routed_pers='%s'
            AND purpose='%s'
            AND (NOT port=%d)
         """ % (conf.instance_raw,
                self.cli_args.branch_id,
                self.cli_opts.routed_pers,
                self.cli_opts.routed_purpose,
                self.port,
                ))

   #
   def setup_server(self, port_num):

      # NOTE: You can see that the service is listening with:
      #         'netstat -l -n | grep [port_number... 4444?]
      #       Sometimes, routed will start up perfectly normal, but pyserver
      #       will not be able to connect to it. pyserver catches the error
      #       (see socket.error in route_get.routed_fetch), and returns it to
      #       flashclient, which says, "[Errno 111] Connection refused" If you
      #       see this, kill the service and run fixperms on your source, and
      #       then try again.

      log.info('trying to start server: port: %d...' % (port_num,))

      # NOTE: Assuming self.server.request_queue_size == 5, which means if we
      # get a sixth simultaneous find-route request, we'll return "Connection
      # denied."

      async_limit = 0
      if routed.cli_opts.routed_purpose == 'general':
         async_limit = conf.routed_async_limit
      elif self.cli_opts.routed_purpose.startswith('analysis'):
         async_limit = conf.analysis_async_limit
      else:
         g.assurt(False)
      g.assurt(async_limit >= 1)
      if async_limit == 1:
         server_class = Server_Threading
      else:
         server_class = Server_Forking

      g.assurt(self.server is None)
      try:
         self.server = server_class(('localhost', port_num), Handler, self,
                                    allow_reuse_address=False)
      except GWIS_Warning, e:
         log.warning('port %d in use. trying again with allow_reuse_address.'
                     % (port_num,))
         try:
            self.server = server_class(('localhost', port_num), Handler, self,
                                       allow_reuse_address=True)
         except GWIS_Warning, e:
            log.warning('port %d in use. not trying again.' % (port_num,))

      if self.server is not None:
         if async_limit > self.server.request_queue_size:
            log.warning(
               'setup_server: async larger than TCP queue size: %d > %d'
               % (async_limit, self.server.request_queue_size,))
            # NOTE: If set gets more requests than request_queue_size,
            # they fail with "Connection denied."

      # BUG nnnn: Should self.server.request_queue_size be larger? 5 seems
      #           limited, especially for route requests... although, the real
      #           solution is to have pyserver wait to connect routed if there
      #           are too many requests. So the route daemon should only handle
      #           requests locally, since it's relying on other code to not
      #           call it too often.

   # *** The 'go' method

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      try:

         self.port_claim()

         self.go_go_main()

      except Exception, e:

         tb = ' / %s' % traceback.format_exc()
         log.error('go_main: massive failure: "%s"%s' % (str(e), tb,))

         self.cleanup_port_and_pid()

         raise

   #
   def go_go_main(self):

      # Determine the pidfile name(s). Plural because we make a convenience
      # pidfile for the basemap for developers to use.
      # SYNC_ME: Search: Routed PID filename.
      self.pidfiles = [conf.get_pidfile_name(self.cli_args.branch_id,
                                             self.cli_opts.routed_pers,
                                             self.cli_opts.routed_purpose),]

      # If this is the instance's basemap, make a convenience link.
      if len(self.cli_args.branch_hier) == 1:
         # We don't have a db handle yet, but if we did, we could verify:
         # g.assurt(self.cli_args.branch_id
         #          == branch.Many.public_branch_id(self.qb.db)
         g.assurt(self.cli_args.branch_id
                  == branch.Many.public_branch_id(db=None))
         self.pidfiles += [conf.get_pidfile_name(
               0, self.cli_opts.routed_pers, self.cli_opts.routed_purpose),]

      # Make another pidfile for the branch name so that, e.g., this works:
      #   routedctl --branch "Metc Bikeways 2012" stop
      self.pidfiles += [conf.get_pidfile_name(
            self.cli_args.branch_hier[0][2],
            self.cli_opts.routed_pers,
            self.cli_opts.routed_purpose),]

      log.debug('pidfiles: %s' % (self.pidfiles,))

      self.readyfile = '%s-ready' % (self.pidfiles[0],)
      if os.path.exists(self.readyfile):
         os.unlink(self.readyfile)

      # Set up signal handlers.
      log.verbose('Setting up signal handlers...')
      signal.signal(signal.SIGTERM, self.sigterm)
      signal.signal(signal.SIGHUP, self.sighup)
      signal.signal(signal.SIGUSR1, self.sigusr1)

      # Daemonize if appropriate.
      if not self.cli_opts.no_daemon:
         self.fork_process()

      self.port_update_routed_ports()

      # Disable the garbage collector so we can manage it.
      # EXPLAIN: Is this really advantageous?
      # FIXME: Could this explain the memory leak?? What about GraphServer?
      # FIXME: It can't hurt to test without this, right? Like, we can still
      #        call gc.collect(), I assume.
      #gc.disable()
      log.debug('automatic gc is enabled? <%s>' % (str(gc.isenabled()),))

      # Load data.
      log.info('loading graph')
      # NOTE: This is called before we start handling requests, so no need
      #       to acquire the lock.
      self.state_initialize()

      # Start the updater thread.
      # NOTE This _must_ be called after state_initialize.
      log.info('starting updater thread')
      self.update_thread.start()

      # Start serving
      log.info('entering run loop')
      while True:
         try:
            # 2012.04.22: [lb] tried both server.handle_request() with
            # server.timeout set, and also server.server_forever() here with
            # server.shutdown() later, but I can't get this call to exit on
            # shutdown.
            self.server.handle_request()
         except select.error, e:
            # On SIGHUP, Python kvetches, "Interrupted system call". Which we
            # promptly ignore.
            if e[0] != errno.EINTR:
               raise
      # The while loop never ends. The only way out of routed is when sigterm
      # calls os.exit().

   # *** State methods

   #
   def state_initialize(self):

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.info('state_init.: cur. mem_usage: %.2f Mb' % (usage_0,))

      log.debug('self.cli_opts: %s' % self.cli_opts)
      log.debug('self.cli_args.branch_id: %s' % self.cli_args.branch_id)

      log.debug('Initializing map: Branch ID %s / Revision %s'
                % (self.cli_args.branch_id, self.cli_args.revision))

      g.assurt(self.cli_args.branch_id and self.cli_args.revision)

      g.assurt(self.graph is None)

      time_0 = time.time()

      if self.cli_opts.routed_pers == 'p3':
         g.assurt(self.cli_opts.travel_mode == Travel_Mode.wayward)
         log.debug('state_initialize: p3')
         graph_class = planner.routed_p3.tgraph.Trans_Graph
      elif self.cli_opts.routed_pers == 'p2':
         g.assurt(self.cli_opts.travel_mode == Travel_Mode.transit)
         log.debug('state_initialize: p2')
         graph_class = planner.routed_p2.tgraph.Trans_Graph
      elif self.cli_opts.routed_pers == 'p1':
         log.debug('state_initialize: p1')
         g.assurt(self.cli_opts.travel_mode == Travel_Mode.classic)
         graph_class = planner.routed_p1.tgraph.Trans_Graph
      else:
         g.assurt(False)

      self.graph = graph_class(self)

      self.lock_updates.acquire()
      self.update_required = True
      self.lock_updates.notify()
      self.lock_updates.release()

      log.info('state_initialize: done!: %s'
               % (misc.time_format_elapsed(time_0),))

      conf.debug_log_mem_usage(log, usage_0, 'routed.state_initialize')

   #
   def state_update(self):

      # This fcn. should only ever run in the context of the update thread.
      # We also lock access to the graph while we're updating it.
      g.assurt(threading.currentThread() == self.update_thread)

      time_0 = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.info('state_update: mem_usage: beg: %.2f Mb' % (usage_0,))

      self.update_required = False

      loaded = False
      try:
         self.graph.load(self.update_thread.keep_running)
         loaded = True
      except g.Ccp_Shutdown, e:
         log.warning('state_update: shutdown detected while loading.')
      finally:
         # Create file saying we're ready for route requests.
         if loaded:
            # Update our sitchuation in the database.
            db = db_glue.new()
            db.transaction_lock_try('routed_ports', caller='routed.py')
            # NOTE: This sets this finder's ready to TRUE and others' to FALSEs
            self.ports_supercede_similar_servers(db)
            # FIXME: This DELETEs others' ports from db, to free them. Ideally,
            # we should wait for them to gracefully stop (i.e., in case they're
            # producing a route for a user). But maybe it's okay to delete
            # their entries from the database anyway?
            self.ports_remove_similar_servers(db)
            # BUG 2688: Use transaction_retryable?
            db.transaction_commit()
            db.close()
            # Create the 'ready!' file.
            if not os.path.exists(self.readyfile):
               fp = open(self.readyfile, 'w')
               fp.write('ready!')
               fp.close()
         elif os.path.exists(self.readyfile):
            os.unlink(self.readyfile)

      conf.debug_log_mem_usage(log, usage_0, 'routed.state_update')

      log.info('state_update: load complete: in %s'
               % (misc.time_format_elapsed(time_0),))

   # *** Threading helpers

   #
   def searchers_increment(self):
      self.lock_updates.acquire()
      self.processing_cnt += 1
      log.verbose('searchers_increment: cnt: %d' % (self.processing_cnt,))
      self.lock_updates.release()

   #
   def searchers_decrement(self):
      self.lock_updates.acquire()
      self.processing_cnt -= 1
      log.verbose('searchers_decrement: cnt: %d' % (self.processing_cnt,))
      if ((self.processing_cnt == 0)
          and (self.update_required)):
         self.lock_updates.notify()
      self.lock_updates.release()

   #
   def sighup(self, signum, frame):
      log.info('SIGHUP received, updating')
      self.lock_updates.acquire()
      self.update_required = True
      if self.processing_cnt == 0:
         log.info('sighup: processing_cnt == 0')
         self.lock_updates.notify()
      self.lock_updates.release()
      log.info('sighup: released lock')

   #
   def sigterm(self, signum, frame):

      # E.g., sudo kill -s 15 $PID

      log.info('SIGTERM received, exiting')

      pids_ok = self.cleanup_port_and_pid()

      log.debug('sigterm: see ya!')

      if not pids_ok:
         # NOTE: This is CcpV1 behaviour. It happens if the PID file is not
         # found. I'm [lb] not sure if/why this happens.
         os._exit(1) # sys.exit() not reliable?

      sys.exit()

   #
   def sigusr1(self, signum, frame):
      # E.g., sudo kill -s SIGUSR1 $PID
      log.info("SIGUSR1 received, breaking, foo'!")
      conf.break_here()
      pass
      #
      # An example using rpdb2:
      #
      # #rid_latest = 22622
      # #qb_curr = self.graph.load_make_qb_new(rid_latest)
      # x from util_ import db_glue
      # x from item.util import revision
      # x from item.util.item_query_builder import Item_Query_Builder
      # x db = db_glue.new()
      # x rev = revision.Current(allow_deleted=False)
      # x (br_id, br_hier,) = branch.Many.branch_id_resolve(db, 2500677, rev)
      # x qb_curr = Item_Query_Builder(db, 'landonb', br_hier, rev)
      #
      # x from item.feat import route
      # x pt_xy = (conf.known_node_pt_x, conf.known_node_pt_y,)
      # #x nearest_byway = route.One.byway_closest_xy(qb_curr,
      # # addr_name='identify_subtree', pt_xy=pt_xy, rating_func=None,
      # # rating_min=0.5, is_latlon=False, radius=None)
      # 
      # x import networkx as nx
      # x nodes = nx.node_connected_component(self.graph.graph_undi, 1301266)
      # 
      # x ast_path = nx.astar_path(self.graph.graph_di, 1298046, 2786225,
      #  heuristic=None, weight='len', pload=None)
      # x ast_path = nx.astar_path(self.graph.graph_di, 2786225, 1298046,
      #  heuristic=None, weight='len', pload=None)

   #
   def cleanup_port_and_pid(self):

      log.info('cleanup_port_and_pid')

      # Tell the socket listener to stop processing route requests.
      self.shutdown = True

      if self.readyfile and os.path.exists(self.readyfile):
         os.unlink(self.readyfile)
      # else, we're being shutdown before we finished loading, either cause of
      # an internal error or because a dev shutdown the service right after
      # booting it.

      # Tell the update thread that we're shutting down but don't wait for it.
      self.update_thread.stop(wait=False)

      if self.update_db is not None:
         self.update_db.cancel()

      # Stop the update thread
      self.update_thread.stop(wait=True)

      # Wait for client threads to complete
      self.lock_updates.acquire()
      log.debug('cleanup_port_and_pid: waitin for update_thread to stop...')
      while self.processing_cnt > 0:
         log.debug('sigterm: waiting...')
         self.lock_updates.wait()
      # Release Graphserver memory
      self.reset()
      # 2014.07.21: Hanging here on service stop?
      log.debug('cleanup_port_and_pid: lock_updates.release')
      self.lock_updates.release()

      # Clear the port entry in the db
      log.debug('cleanup_port_and_pid: freeing port_num...')
      self.port_release()

      # Clear the PID file(s)
      pids_ok = True
      log.debug('cleanup_port_and_pid: removing pid files...')
      for pidfile in self.pidfiles:
         try:
            pidinfile = int(open(pidfile).read())
            if (pidinfile != os.getpid()):
               raise IOError('not my pid in file')
            os.unlink(pidfile)
            log.info('removed %s' % (pidfile))
         except IOError, e:
            log.warning('ignoring pidfile: %s' % (str(e),))
            pids_ok = False

      log.debug('cleanup_port_and_pid: all done.')

      return pids_ok

   # *** Support methods

   # See http://www.noah.org/wiki/Daemonize_Python
   def fork_process(self):

      # FIXME: Aforementioned documentation says not to fork if we're started
      # by inetd. Hahaha.

      # Fork.
      if os.fork() != 0:
         sys.exit(0) # parent exits

      # Daemon voodoo (decouple from parent environment).
      os.chdir("/")
      #os.umask(0)
      os.setsid()

      # Fork again.
      if os.fork() != 0:
         sys.exit(0) # parent exits

      # Now I am a daemon!

      # Set up standard I/O.

      # FIXME: Figure this out.
      #
      # FIXME: [mm] Don't know if these os.close() calls are needed. If they
      # are there, when routed is started from Mr. Do! (analysis time), the
      # script gets just stuck indefinitely at one of these (os.close(1), I
      # think) -- no exceptions raised, just stuck.
      # FIXME: [lb] If we don't close the pipes, Popen gets stuck waiting for
      # the command to complete. And my code does not stick indefinitely. So
      # I think we should get rid of no_io_close.
      if not self.cli_opts.no_io_close:
         os.close(0)
         os.close(1)
         os.close(2)
      else:
         g.assurt(False) # Delete no_io_close, or don't use.
      # FIXME: g.log, or just use our local log?
      # 2013.05.01: [lb] switched from g.log to log
      sys.stdout = File_Log(log)
      sys.stderr = File_Log(log)

      # Write the PID file(s).
      for pidfile in self.pidfiles:
         fp = open(pidfile, 'w')
         fp.write('%s\n' % (os.getpid()))
         fp.close()

   # FIXME/V2: In V2, this is revision.Revision.revision_max(db)
   def revision_max(self, db):
      g.assurt(False) # FIXME: I think we can delete this fcn.
      return db.sql("""SELECT max(id) FROM revision
                       WHERE id != rid_inf()""")[0]['max']

# *** Main thunk

#
if (__name__ == '__main__'):
   routed = Route_Daemon()
   routed.go()

