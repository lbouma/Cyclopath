#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This is the daemon which manages the jobs queue. Mr. Do! is its name.
#  https://en.wikipedia.org/wiki/Mr._Do!
# tl;dr "Mr. Do can also be crushed by a falling apple causing a loss of life."
#
# The jobs queue is, essentially, a table of requests from users to do some
# work. Generally, the work being asked is a lot to do, otherwise we wouldn't
# need the queue.
#
# To be fair, as of 2011.12.18, there isn't the most robust approach to
# managing the work queue. We apply a general set of rules to all users:
#   * There are three types of expensive requests:
#       - Web-originated Find-Route
#       - Scheduled SImport/Export Shapefile
#       - Scheduled Bulk Route Analysis
#     * The first type, Find-Route, we process using the routed service. It
#       handles up to 5 simultaneous find-route requests.
#     * The second and third types are handled by the Mr. Do! service.
#   * For Mr. Do!, each job tends to consume much of a machine's resources for
#     a long period of time. But each machine is unique (e.g., depending on
#     RAM, number of processor cores, etc.), and this service can be used to
#     optimize for specific machines. (At least that's the hope! We'll see how
#     it all actually goes...).
#   * The most conservative use of Mr. Do! is to process one job at a time, to
#     preference import/export jobs over bulk route analysis (the idea being
#     that import/export takes a few hours and bulk route analysis takes five
#     times that), and to process one job from each group of branch requests
#     (that is, if you have multiple branches with jobs, make sure you don't
#     starve any branches, because likely the branches are managed by different
#     users). Like I said, the management of the work queue is not that
#     sophisticated. This is Heavy Lifting. We really need on-demand cloud
#     computing and customer billing!
# FIXME: Schedule jobs based on time of day, i.e., don't run during peak hours.

# See mr_doctl and /etc/init.d/cyclopath-mr_do for usage examples.

"""
/* Reset work items (for testing). */
UPDATE work_item SET job_finished = TRUE;
DELETE FROM work_item_step;
INSERT INTO work_item_step
   (work_item_id, step_number,
    status_text, status_code,
    cancellable)
   (SELECT
      system_id AS work_item_id
      , '1' AS step_number
      , 'queued' AS status_text
      , '4' AS status_code
      , TRUE AS cancellable
   FROM work_item);


UPDATE item_versioned SET deleted = TRUE FROM work_item
  WHERE work_item.system_id = item_versioned.system_id;
DELETE FROM work_item_step;
DELETE FROM work_item;
DELETE FROM group_item_access WHERE item_type_id = 29; -- merge_job
"""

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
# FIXME: Make DEBUG the default on this and all services and make logcheck not
# look for 'em. I think it's more important to have a good trace when we
# release all this new code.
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
#conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)
# NOTE: Must manually configure the logger
# FIXME: It took me a few minutes to remember this... how to remind self when
# files need it? Like: ccp.py, routed, gwis_mod_python.
conf.init_logging(True, False, conf.log_line_len, log_level, True)

log = g.log.getLogger('mr._do!')

# ***

import errno
import re
import select
import signal
import socket
import SocketServer
import threading
import time
import traceback

from grax.item_manager import Item_Manager
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from gwis.query_overlord import Query_Overlord
from item.feat import branch
from item.jobsq import work_item
from item.jobsq import work_item_step
from item.jobsq.job_action import Job_Action
from item.jobsq.job_status import Job_Status
from item.util import item_factory
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_ import misc
from util_.mod_loader import Mod_Loader
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
from util_.task_queue import Task_Queue
from util_.task_queue import Task_Queue_At_Capacity_Error
from util_.task_queue import Task_Queue_Complete_Error
import VERSION

script_name = 'Cyclopath Mr. Do! Jobs Queue Manager and Friend of Work Items'
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-12-18'

# *** Server class

# The Mr. Do! server simply exists to get 'kicks' when new work items are saved
# or when work item stages have completed.
#
# I [lb] tried instead to use the Postgres LISTEN command, which would allow
# the script to be alerted when the work item table gets updated, but I
# couldn't get it to work. Which is why we need the server -- we need some way
# for other processes to notify us when there's work. Otherwise, our only other
# option is to poll (which we do anyway, as a safety guard, but we mostly rely
# on other processes to ding us when there's work to do).
#
# Also, we choose ThreadingMixIn instead of ForkingMixIn for reasons described
# in routed.py, but it really doesn't matter: the Handler objects that get
# created are lightweight, and simply exist to wake up a processing thread, and
# it's the child threads the processing thread creates that are the heavyweight
# objects.

# NOTE: TO TEST:
#
#     $ telnet 127.0.0.1 4999
#
#   You'll see
#
#     Trying 127.0.0.1...
#     Connected to 127.0.0.1.
#     Escape character is '^]'.
#
#   Then type
#
#     kick
#
#   and hit return. You'll see
#
#     0
#     Connection closed by foreign host.
#

class Server(SocketServer.ThreadingMixIn, SocketServer.TCPServer):

   # FIXME: C.f. routed.py

   __slots__ = (
      'mr_do',
      )

   def __init__(self, server_address, handler_class, mr_do,
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
         SocketServer.TCPServer.__init__(self, server_address, handler_class)
      except socket.error, e:
         # [Errno 98] Address already in use
         log.error('mr_do: port already in use: %d [%s] / %s'
                   % (server_address[1], server_address[0], str(e),))
         if e[0] != 98:
            log.error('Unexpected: Not [Errno 98] Address already in use')
         raise GWIS_Error('Port in use')
      except Exception, e:
         log.error('Unexpected Exception: "%s" / %s'
                   % (str(e), traceback.format_exc(),))
         raise GWIS_Error('Unknown error')
      self.mr_do = mr_do

# *** Handler class

class Handler(SocketServer.StreamRequestHandler):

   # Regexes matching each command
   #
   cmd_res = {
      #
      # The command that triggers waking up the processing thread.
      'kick': re.compile(r'^kick'),
      #
      }

   __slots__ = (
      )

   #
   def handle(self):

      line_count = 0

      # SECURITY: See concerns about the same while loop in routed.py.
      # FIXME: Test sending multiple lines. Do we just hangup? Should we send
      # error? Does it matter?
      while line_count < 1:

         try:

            # Read a line.
            line = self.rfile.readline()
            if (line == ''):
               # Client went away, or we processed the complete request.
               log.debug('Done processing or Client closed connection.')
               break
            line = line.rstrip()

            # Parse it
            crm = dict()
            for cr in Handler.cmd_res:
               crm[cr] = Handler.cmd_res[cr].search(line)

            # Execute the appropriate command.

            # FIXME: Server should accept a shutdown command, so it can
            # gracefully finish processing jobs, i.e., shutdown the jobs queue,
            # wait, and then update the server or whatever.

            # This is where's the beef's at.
            if (crm['kick']):
               log.debug('Kicking the do!')
               self.kick_mr_do()
               xml = ''
               self.xml_print(xml)
            #
            else:
               err_s = 'ignoring unknown command "%s"' % (line,)
               log.warning(err_s)
               raise GWIS_Warning(err_s)

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
            break

         # FIXME: This is hacky. We only process one line/one command currently
         line_count += 1

      # End, while True

   #
   def xml_print(self, xml):
      # len(xml) will be incorrect if xml becomes a Unicode string.
      self.wfile.write('%d\n' % (len(xml)))
      self.wfile.write(xml)

   #
   def kick_mr_do(self):
      # Get a handle to mister. do!
      mr_do = self.server.mr_do
      # Wake up the processing thread.
      log.debug('kick_mr_do: Tickling the do.')
      mr_do.kick()

# *** Logfile write() wrapper

# FIXME: Move to somewhere you can share with routed.py. Find all other
# commonalities.
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
      if (c == '\n'):
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

      # General Cyclopath Service options.

      # The port this service listens on for Kick! messages.
      self.add_argument('-p', '--listen_port', dest='listen_port',
         action='store', default=conf.jobs_queue_port, type=int,
         help='port number to listen on')

   #
   def verify(self):
      verified = Ccp_Script_Args.verify(self)

# *** Route Daemon Graph Update Thread

class Jobs_Thread(threading.Thread):

   def __init__(self, mr_do):
      threading.Thread.__init__(self)
      self.mr_do = mr_do
      self.keep_running = threading.Event()
      self.keep_running.set()

   # This fcn. is Jobs_Thread's thread.
   def run(self):
      log.debug('Jobs_Thread: running')
      # Since we just started running, we can audit the database to see if
      # there are any jobs that didn't shutdown gracefully.
      first_loop = True
      while self.keep_running.isSet():
         try:
            log.verbose('jobs_thread.run: want lock: jobs_kick...')
            self.mr_do.jobs_kick.acquire()
            if first_loop:
               g.assurt(not self.mr_do.task_queue.busy())
               self.mr_do.start_jobs_maybe(cleanup_only=True)
               first_loop = False
            log.verbose('jobs_thread.run: got lock: jobs_kick')
            while (self.keep_running.isSet()
                   and not self.mr_do.kick_requested):
               log.verbose('jobs_thread.run: wait lock: jobs_kick...')
               self.mr_do.jobs_kick.wait()
               log.verbose('jobs_thread.run:  got lock: jobs_kick.')
            if self.keep_running.isSet():
               self.mr_do.check_for_work()
            log.verbose('jobs_thread.run: end of try.')
         except Exception, e:
            # FIXME: This kills the thread, which is good, but I think we need
            # to tell our handler to try processing the next thread.
            log.warning('run: Unexpected Exception: "%s" / %s'
                        % (str(e), traceback.format_exc(),))
            raise
         finally:
            log.verbose('jobs_thread.run: give lock: jobs_kick.')
            self.mr_do.jobs_kick.release()
      log.debug('Jobs_Thread: done running')

   # This fcn. is called from mr_do's thread.
   def stop(self):
      log.debug('Jobs_Thread: stopping')
      self.keep_running.clear()
      log.verbose('jobs_thread.stop: want lock: jobs_kick...')
      self.mr_do.jobs_kick.acquire()
      log.verbose('jobs_thread.stop:  got lock: jobs_kick')
      self.mr_do.jobs_kick.notify()
      log.verbose('jobs_thread.stop: give lock: jobs_kick.')
      self.mr_do.jobs_kick.release()
      if self.isAlive():
         log.debug('Jobs_Thread: joining...')
         self.join()
      log.debug('Jobs_Thread: stopped')

# *** The Mr. Do! Daemon

# FIXME: Do we need to synchronize log messages? I.e., if two threads call
# log.debug(), is the output interleaved in the log file?

# WARNING: This class is used by multiple threads. Make sure you lock resources
#          as appropriate!
class Mr_Do(Ccp_Script_Base):

   __slots__ = (
      'cli_opts',          # Command-line options (see above).
      'pidfile',           # File containing this process's PID.
      'server',            # Handle to the Server.
      'shutdown',          # True if the mr_do daemon is shutting down.
      'task_queue',        # This is the thread pool that does our bidding.
      'jobs_thread',       # The Jobs_Thread used to talk to the thread pool.
      'jobs_kick',         # Don't kick 'em when down. Help 'em up, srsly.
      'kick_requested',
      )

   #
   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.pidfile = None
      self.shutdown = False
      self.server = None
      self.task_queue = None
      self.jobs_thread = Jobs_Thread(self)
      self.jobs_kick = threading.Condition()
      self.kick_requested = True
      #
      self.skip_query_builder = True

   #
   def setup_server(self, port_num):
      # Set up server
      log.info('trying to start server: port: %d...' % (port_num,))
      g.assurt(self.server is None)
      try:
         self.server = Server(('localhost', port_num), Handler, self,
                              allow_reuse_address=False)
      except GWIS_Warning, e:
         log.warning('port %d in use. trying again with allow_reuse_address.'
                     % (port_num,))
         try:
            self.server = Server(('localhost', port_num), Handler, self,
                                 allow_reuse_address=True)
         except GWIS_Warning, e:
            log.warning('port %d in use. not trying again.' % (port_num,))

      if self.server is None:
         raise GWIS_Error('Unable to start server: port is not available.')

   # *** The 'go' method

   #
   def go_main(self):
      time_0 = time.time()
      try:
         self.go_go()
      except Exception, e:
         log.error('Fatal error. Please debug!: %s' % (str(e),))
         raise
      finally:
         # Don't forget to stops the threads!
         if self.jobs_thread.isAlive():
            log.debug('Stopping jobs thread...')
            self.jobs_thread.stop()
         if self.task_queue is not None:
            log.debug('Stopping task queue...')
            try:
               self.task_queue.stop_consumers(wait_empty=True,
                                              do_joins=True)
            except Task_Queue_Complete_Error:
               log.debug('  .. task queue was already stopped!')
         log.info('Service complete! Ran in %s'
                  % (misc.time_format_elapsed(time_0),))

   #
   def go_go(self):

      # Determine the pidfile name, based on the port number.
      # SYNC_ME: Search: Mr. Do! PID filename.
      self.pidfile = conf.mr_do_pidfile_basename

      # Set up signal handlers.
      signal.signal(signal.SIGTERM, self.sigterm)
      signal.signal(signal.SIGHUP, self.sighup)

      # Daemonize if appropriate.
      if not self.cli_opts.no_daemon:
         self.fork_process()

      # Start the work queue.
      log.info('Starting Work Queue.')
      self.task_queue = Task_Queue(num_consumers=conf.mr_do_total_consumers)

      # Start the jobs thread.
      log.info('Starting jobs thread.')
      self.jobs_thread.start()

      # Set up server
      # FIXME: Does this NOTE about routed pertain to mr_do.
      # NOTE: You can see that the service is listening with:
      #         'netstat -l -n | grep [self.cli_opts.listen_port]
      #       Sometimes, routed will start up perfectly normal, but pyserver
      #       will not be able to connect to it. pyserver catches the error
      #       (see socket.error in route_get.routed_fetch), and returns it to
      #       flashclient, which says, "[Errno 111] Connection refused" If you
      #       see this, kill the service and run fixperms on your source, and
      #       then try again.
      log.info('starting server: port: %d' % (self.cli_opts.listen_port,))
      # NOTE: Assuming request_queue_size == 5, which means if we get a sixth
      # simultaneous find-route request, we'll return "Connection denied." This
      # will probably never happen for mr_do. Question: can you catch requests
      # that get denied so we can log the problem?
      self.setup_server(self.cli_opts.listen_port)
      #server = Server(('localhost', self.cli_opts.listen_port), Handler, self)

      mr_do_port_num_key_name = 'mr_do_port_num_%s' % (conf.ccp_dev_path,)
      db = db_glue.new()
      update_kvp_sql = (
         "UPDATE key_value_pair SET value = '%s' WHERE key = '%s'"
         % (self.cli_opts.listen_port,
            mr_do_port_num_key_name,))
      db.sql(update_kvp_sql)
      if db.rowcount() != 1:
         g.assurt(db.rowcount() == 0)
         insert_kvp_sql = (
            "INSERT INTO key_value_pair (key, value) VALUES ('%s', '%s')"
            % (mr_do_port_num_key_name,
               self.cli_opts.listen_port,))
         db.sql(insert_kvp_sql)
         g.assurt(db.rowcount() == 1)
      db.close()

      # Kick the queue once to see if there's anything waiting for us.
      log.debug('Booting the do on start.')
      self.kick()

      # Start serving.
      log.info('entering run loop')
      while True:
         try:
            self.server.handle_request()
         except select.error, e:
            # On SIGHUP, Python kvetches, "Interrupted system call". Which we
            # promptly ignore.
            if e[0] != errno.EINTR:
               raise

   # *** State methods

   #
   # This is called from the context of the socket server handler or the sighup
   # listener.
   def kick(self):
      if self.jobs_thread.keep_running.isSet():
         log.debug('Kicking Mr. Do!')
         log.verbose('kick: want lock: jobs_kick...')
         self.jobs_kick.acquire()
         log.verbose('kick: got lock: jobs_kick')
         self.kick_requested = True
         #if not self.task_queue.stop_event.isSet()
         self.jobs_kick.notify()
         log.verbose('kick: give lock: jobs_kick.')
         self.jobs_kick.release()

   #
   # This is called from the context of the work queue management thread, which
   # can be signalled by either the socket server handler or the sighup
   # listener. It's a shim so whatever we do herein we don't delay the calling
   # process from telling the client we're actually doing something, and also
   # so we only ever call this function once at a time.
   def check_for_work(self):
      self.kick_requested = False
      if self.task_queue.busy():
         log.debug('check_for_work: Work queue is busy.')
         # FIXME: Make sure work queue not being busy triggers another
         # check_for_work.
      else:
         log.debug('check_for_work: Checking for work!')
         self.start_jobs_maybe()

   #
   def start_jobs_maybe(self, cleanup_only=False):

      check_again = True

      while check_again:
         check_again = self.start_jobs_maybe_(cleanup_only)

   #
   def start_jobs_maybe_(self, cleanup_only=False):

      check_again = False

      log.verbose4('=== start_jobs_maybe: getting "work_item" r-w connection')
      qb = self.get_qb()

      wtems = work_item.Many()
      wtems.search_by_latest_branch_job(qb)

      qb.db.close()

      log.debug('start_jobs_maybe_: Found %d work items' % (len(wtems),))

      # NOTE: The wtems search only grabs one work item per (branch_id,
      # job_class), so there might be more work items for this branch/job type.
      # This is by design, so that we don't starve other branch-jobtypes.

      consumers_avail = self.task_queue.available()
      log.debug('start_jobs_maybe: Work Queue: num. consumers avail.: %d'
                % (consumers_avail,))

      # FIXME: on restart, route analysis needs to check each pidfile that
      # has a guid. dont stop, just kill. then delete matching pid files
      # in one fell swoop. /bin/rm routed-pid-minnesota.Metc Bikeways
      # 2012.p1.analysis-6bb5ffac-99a6-11e1-8d33-08002708b8f0 and branch id and
      # 0 and -ready.

      for wtem in wtems:
         log.debug('  inspecting work item: %s' % (wtem,))
         # Get the item again so we can get a lock on it. Also, the item may
         # have have changed (probably unlikely; the client would basically
         # have to save a new job and then cancel it immediately, since the
         # mr_do service is generally kicked right after a new save).
         log.debug('start_jobs_maybe_: getting row lock: stack_id: %d'
                   % (wtem.stack_id,))
         wtem, qb = self.wtem_refresh(wtem)
         # Check the status of each job and start new ones as appropriate.
         if wtem.latest_step.status_text == 'queued':
            g.assurt(not wtem.job_finished)
            if cleanup_only:
               log.debug('  work item ok: %s' % (wtem,))
            else:
               log.debug('  trying to add work item: %s' % (wtem,))
               try:
                  # FIXME: Marked starting, but what if consumer never picks it
                  #   up? We need to have a timeout associated with this state!
                  self.stage_create_next(qb, wtem, 'starting')
                  # Commit the transaction while we have the row lock, then get
                  # a new handle.
                  # BUG 2688: Use transaction_retryable?
                  qb.db.transaction_commit()
                  qb.db.close()

                  wtem, qb = self.wtem_refresh(wtem)
                  g.assurt(wtem.latest_step.status_text == 'starting')

                  # FIXME: BUG 2641: Poor Python Memory Management
                  # 1. add mem_usage output to mr do
                  # 2. fork your work items so you get your memory back...

               # BUG nnnn: use fork here to take advantage of multi-processing.
               # currently, all merge jobs will run under the same thread (same
               # as the analysis threads, but analysis spends most of its time
               # I/Oing with the route finder, which runs in a separate process
               # (and therefore the OS can run it on another thread)).
               # BUG nnnn (fixed): MP aware Step 1: use task_queue in analysis
               #   and have routed smartly choose ThreadingMixin or Forking.

                  self.task_queue.add_work_item(
                        f_process=self.job_callback_process,
                        process_args=[wtem,],
                        process_kwds=None,
                        f_on_success=self.job_callback_success,
                        f_on_exception=self.job_callback_failure,
                        f_postprocess=self.job_callback_postprocess)

                  qb.db.close()
                  qb = None

               except Task_Queue_At_Capacity_Error:
                  log.debug('Job Queue is full!')
                  self.stage_create_next(qb, wtem, 'queued')
                  # BUG 2688: Use transaction_retryable?
                  qb.db.transaction_commit()
                  qb.db.close()
                  break
               log.verbose('  added work item')
               consumers_avail -= 1
               log.debug('  consumers_avail: %d' % (consumers_avail,))
         elif wtem.job_finished:
            # EXPLAIN: Would this happen is a job finishes right as this fcn.
            # is running? I.e., search_by_latest_branch_job returned the job
            # not in this state, and then wtem_refresh picked it up finished.
            log.warning('Job already finished? %s %s'
                        % (wtem, wtem.latest_step,))
            check_again = True
         else:
            processing_statuses = ('starting', 'working', 'canceling',)
            g.assurt(wtem.latest_step.status_text in processing_statuses)
            # If you cancel a job and then start Mr. Do!, we know this job is
            # abandoned.
            if cleanup_only:
               log.debug('Cleaning up job not properly shutdown.')
               if wtem.latest_step.status_text == 'starting':
                  self.stage_create_next(qb, wtem, 'queued')
               elif wtem.latest_step.status_text == 'working':
                  failure_reason = 'improper shutdown'
                  self.process_failure(qb, wtem, failure_reason, warn=True)
               elif wtem.latest_step.status_text == 'canceling':
                  self.stage_create_next(qb, wtem, 'canceled')
               else:
                  g.assurt(False)
            else:
               log.debug('Skipping job that is being processed: %s / %s'
                         % (wtem.latest_step.status_text, wtem,))

         if qb is not None:
            # BUG 2688: Use transaction_retryable?
            qb.db.transaction_commit()
            qb.db.close()
            log.verbose4('=== start_jobs_maybe_: .. committed!')

         log.debug('start_jobs_maybe: released row lock.')

      # end for

      return check_again

   #
   # This function is called in the context of one of the work queue consumer
   # threads.
   def job_callback_process(self, wtem_stale):

      # BUG 2641: Because Python doesn't release OS memory pages once claimed,
      # job processing should be done in a forked process, and not just a
      # separate thread. We still need the thread to setup I/O piping, though,
      # so that the forked process and Mr. Do! can still coordinate activity.
      # For now, just watch 'top' and maybe restart mr do periodically.

      log.debug('job_callback_process: %s' % (wtem_stale,))
      # Alright, we've been called! Let the world know we've started working.
      log.debug('  active threads: %s' % (threading.active_count(),))
      log.debug('  this thread: %s / %s' % (threading.current_thread().name,
                                            id(threading.current_thread()),))

      # Refresh the work item since it's been sitting on the work queue and we
      # haven't coordinated with the lock; which is to say, the state may have
      # changed. Refreshing the item also puts a FOR UPDATE on the transaction,
      # so we can be assured we're not competing with a Nonwiki commit on the
      # same item (; which is to say, we're preventing a race condition between
      # us processing a job and the user trying to cancel the same job).

      log.debug('job_callback_process: getting row lock: stack_id: %d'
                % (wtem_stale.stack_id,))
      wtem, qb = self.wtem_refresh(wtem_stale)
      # There might still be a race condition between queued-starting-working.
      g.assurt(wtem.latest_step.status_text == 'starting')
      log.debug('job_callback_process: marking "working"')
      self.stage_create_next(qb, wtem, 'working')
      # BUG 2688: Use transaction_retryable?
      qb.db.transaction_commit()
      qb.db.close()
      log.debug('=== job_callback_process: .. committed!')
      log.debug('job_callback_process: released row lock.')

      # FIXME: See comment above about starting. How do we guarantee this state
      #        doesn't zombie?
      # FIXME: this is the Consumer thread. Figure out the fcn and its params
      # to call.

      # Note that we trust the job_fcn value. It's only set by our code, i.e.,
      # never by user input.
      # e.g., job_fcn = merge.merge_job_export:Merge_Job_Export:process_request
      try:
         err_s = None
         log.debug('  loading and firing: %s' % (wtem.job_fcn,))
         job_fcn = Mod_Loader.get_mod_attr(wtem.job_fcn)
         # This callback is allowed to take a Very Long Time. But we also trust
         # that it checks periodically for state updateds, e.g., should the
         # user want to cancel the operation.
         # BUG nnnn: Maybe fork these operations, so we don't steal pages. But
         # if this forks... there are a bunch of local variables to worry about
         job_fcn(wtem, self)
      except Exception, e:
         # We're not in the stack that threw the error, so find it.
         err_s, detail, trbk = sys.exc_info()
         log.warning('job_callback_process: failed:')
         log.warning('%s' % (err_s,))
         log.warning('%s\n%s' % (detail, ''.join(traceback.format_tb(trbk)),))

      # Refresh the work item.
      ## CAVEAT: If we bailed with the database lock... deadlock!
      #if err_s is not None:
      #   # Avoid deadlock; release the lock.
      #   qb.db.transaction_rollback()
      #qb.db.close()

      wtem, qb = self.wtem_refresh(wtem)
      if err_s is None:
         # Verify that the job updated the status to some sort of finished. Or
         # maybe the job was suspended, in which case it should be marked
         # queued.
         log.debug('  job finished!')
         g.assurt((wtem.job_finished)
                or (wtem.latest_step.status_text == 'queued'))
         qb.db.transaction_rollback()
      else:
         #log.warning('job_callback_process: failed!: ===%s===' % (err_s,))
         # The first element in exc_info()'s response (called err_s, above) is
         # the name of the object, e.g., "&lt;type 'exceptions.Exception'&gt;"
         # The second element, detail, is the error message.
#May-16 16:39:11  ERRR              root  #  /ccp/dev/cp/pyserver/../services/mr_do.py:809: DeprecationWarning: BaseException.message has been deprecated as of Python 2.6
#May-16 16:39:11  ERRR              root  #    self.process_failure(qb, wtem, detail.message)
         # FIXME: Do we call exc_info() and use detail.message elsewhere?
         #self.process_failure(qb, wtem, detail.message)
         self.process_failure(qb, wtem, str(detail))
         # BUG 2688: Use transaction_retryable?
         qb.db.transaction_commit()
      qb.db.close()

   #
   def wtem_refresh(self, wtem):
      log.verbose('wtem_refresh: %s' % (wtem,))
      # Refresh the work item.
      g.assurt(wtem is not None)
      # MAYBE: [lb] had problems reaching max allowed connections. See
      #   SELECT * FROM pg_stat_activity;
      # We could try cursor_recycle() but I'm concerned that won't work (or
      # will be tricky) because of how we lock and update work_items.
      qb = self.get_qb(wtem)
      g.assurt(not qb.request_lock_for_update)
      qb.request_lock_for_update = True
      qb.db.transaction_begin_rw()
      # Get the actual derived class, and not just the base class.
      wtems = item_factory.get_item_module(wtem.job_class).Many()
      # Make sure we get deleted items, in case the job is marked finished.
      qb.revision.allow_deleted = True
      wtems.search_by_stack_id(wtem.stack_id, qb)
      qb.revision.allow_deleted = False
      g.assurt(len(wtems) == 1)
      qb.request_lock_for_update = False
      wtem = wtems[0]
      return wtem, qb

   #
   def job_callback_success(self, result, wtem):
      log.debug('job_callback_success: result: %s / wtem: %s'
                % (result, wtem,))

   #
   def job_callback_failure(self, exc_inf, wtem):
      (err_type, err_val, err_traceback,) = exc_inf
      log.debug('job_callback_failure: exc_inf: %s | %s | %s / wtem: %s'
                % (err_type, err_val, err_traceback.__str__(), wtem,))
      stack_trace = traceback.format_exc()
      log.warning('job_callback_failure: %s' % (stack_trace,))
      #
      # FIXME: AssertionError does not print anything?
      #import pdb; pdb.set_trace()
      #
      # Refresh the work item.
      wtem, qb = self.wtem_refresh(wtem)
      self.process_failure(qb, wtem, stack_trace)
      # BUG 2688: Use transaction_retryable?
      qb.db.transaction_commit()
      qb.db.close()

   #
   def job_callback_postprocess(self, wtem):
      log.debug('Done processing job, kicking self')
      self.kick()

   #
   # We can mark jobs failed for reasons that are the user's fault, or reasons
   # that are our own. Use warn to control the log file level.
   def process_failure(self, qb, wtem, failure_reason, warn=None):
      if warn:
         log_ = log.warning
         # This is the stack trace for error, e.g., 'raise GWIS_Nothing_Found'.
         stack_trace = traceback.format_exc()
         log.warning('job_callback_failure/1: %s' % (stack_trace,))
         # This is the stack trace of the error handler, i.e., this fcn.
         stack_lines = traceback.format_stack()
         stack_trace = '\r'.join(stack_lines)
         log.warning('job_callback_failure/2:\r%s' % (stack_trace,))
      else:
         log_ = log.info
      log_('job_mark_failed: process_failure: %s' % (failure_reason,))
      wtem.job_stage_msg = failure_reason
      self.stage_create_next(qb, wtem, 'failed')

   #
   def stage_create_next(self, qb, wtem, new_status):
      # It's assumed the caller has a row-level lock; guarantees there isn't
      # a race condition.
      do_commit = False
      if qb is None:
         # qb is None when called from job_cleanup. The state is 'working', and
         # the processing thread is dead, and the user cannot change the
         # 'working' state, so no need to get an UPDATE FOR row lock.
         do_commit = True
         qb = self.get_qb(wtem)
         # We do have to start the transaction, though.
         qb.db.transaction_begin_rw()
      cancellable = not (new_status in Job_Status.incancellable_statuses)
      wtem.stage_create_next(qb, new_status, cancellable=cancellable)
      if do_commit:
         # BUG 2688: Use transaction_retryable?
         qb.db.transaction_commit()

   #
   def get_qb(self, wtem=None):

      # MAYBE: [lb] has had issues here. Sometimes getting a new db connection
      # fails because postgresql says it's out of connections. Which implies
      # we're calling db_glue.new() too often and should recycle the cursor
      # instead. Or maybe our callers are not closing() their dbs and Python
      # is keeping handles on the objects? See also
      #     "connection limit exceeded for non-superusers"
      #     psql -U postgres ccpv2
      #        SELECT * FROM pg_stat_activity;
      #     Search max_connections in postgresql.conf
      db = db_glue.new()

      allow_deleted = False
      rev = revision.Current(allow_deleted=allow_deleted)

      if wtem is not None:
         g.assurt(wtem.created_by)
         username = wtem.created_by
         (branch_id, branch_hier) = branch.Many.branch_id_resolve(db,
                                 wtem.branch_id, branch_hier_rev=rev)
         # Save job just to leafy branch.
         branch_hier = [branch_hier[0],]
      else:
         # This is balsy. This is only for Mr. Do! to search for the next job
         # of each type for each branch. (Normally you wouldn't search without
         # a username or branch_hier.)
         username = ''
         branch_hier = []

      qb = Item_Query_Builder(db, username, branch_hier, rev)

      qb.request_is_local = True
      qb.request_is_script = True
      if not username:
         qb.filters.gia_userless = True

      qb.item_mgr = Item_Manager()

      Query_Overlord.finalize_query(qb)

      return qb

   # *** Threading helpers

   # FIXME: Catch Ctrl-C from non-daemoned instance.
   # Maybe also catch another Ctrl for forcing kick?

   #
   # FIXME: This doesn't get sent to Mr. Do!, does it?
   # This is used to tell routed when a new revision has been saved. We could
   # use the same mechanism instead of/in addition to the kick command....
   def sighup(self, signum, frame):
      log.info('SIGHUP received. Kicking Mr. Do!')
      self.kick()

   #
   def sigterm(self, signum, frame):
      log.info('SIGTERM received, exiting')
      # Stop the jobs thread.
      log.info(' >> stopping jobs thread...')
      self.jobs_thread.stop()
      # Wait for jobs thread to finish.
      log.verbose('sigterm: want lock: jobs_kick...')
      self.jobs_kick.acquire()
      log.verbose('sigterm: got lock: jobs_kick')
      # Stop the work queue. This may take a while...
      log.info(' >> stopping work queue consumers...')
      try:
         self.task_queue.stop_consumers(wait_empty=True, do_joins=True)
      except Task_Queue_Complete_Error:
         log.debug('  .. task queue was already stopped!')
      #
      self.shutdown = True
      log.verbose('sigterm: give lock: jobs_kick.')
      self.jobs_kick.release()
      # Clear the PID file
      try:
         pidinfile = int(open(self.pidfile).read())
         if (pidinfile != os.getpid()):
            raise IOError('not my pid in file')
         os.unlink(self.pidfile)
         log.info('removed %s' % (self.pidfile))
      except IOError, e:
         log.warning('ignoring pidfile: %s' % (str(e),))
         os._exit(1) # sys.exit() not reliable?
      sys.exit()

   # *** Support methods

   # See http://www.noah.org/wiki/Daemonize_Python
   def fork_process(self):

      # Fork
      if (os.fork() != 0):
         sys.exit(0) # parent exits

      # Daemon voodoo
      os.chdir('/')
      os.setsid()

      # Fork again
      if (os.fork() != 0):
         sys.exit(0) # parent exits

      # Set up standard I/O
      os.close(0)
      os.close(1)
      os.close(2)
      # FIXME: g.log, or just use our local log?
      # 2013.05.01: [lb] switched from g.log to log
      sys.stdout = File_Log(log)
      sys.stderr = File_Log(log)

      # Write the PID file
      fp = open(self.pidfile, 'w')
      fp.write('%s\n' % (os.getpid()))
      fp.close()

# *** Main thunk

#
if (__name__ == '__main__'):
   mr_do = Mr_Do()
   mr_do.go()

