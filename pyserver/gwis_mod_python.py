# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This file calls gwis.request to decode and process the GWIS packet
# from the client, handed to us by mod_python.

# HACK_ALERT: conf.py wants us to chdir to the pyserver directory. We assume
# that this is the first directory in sys.path, which we configure in the
# Apache configuration. Unfortunately, getting PythonOption directives from
# the Apache config comes through the request object, and we'd like this to be
# working before we have one of those.
import os
import sys

try:
   from mod_python import apache
except ImportError:
   pass # script is being run locally
   # Wait, what? This makes zero sense,
   # we're gwis_mod_python, only called
   # from apache...
   assert(False)
# 2013.04.19: [lb] is trying to run multiple servers side-by-side.
# But whatever server is accessed first is the one whose Python
# is run. Or, more correctly, when the second server is accessed,
# PYSERVER_HOME is still set from the first server, and the second
# server stupidly chdirs to the wrong pyserver directory, because
# pyserver_glue uses PYSERVER_HOME, if it's set.
#
# Don't believe the environment variables. Believe the apache conf.
try:
   pyserver_home = os.environ['PYSERVER_HOME']
   del os.environ['PYSERVER_HOME']
   apache.log_error(
      'gwis_mod_python: Ignoring PYSERVER_HOME: %s' % (pyserver_home,),
      apache.APLOG_WARNING)
except KeyError:
   pass
try:
   instance_raw = os.environ['INSTANCE']
   del os.environ['INSTANCE']
   apache.log_error(
      'gwis_mod_python: Ignoring INSTANCE: %s' % (instance_raw,),
      apache.APLOG_WARNING)
except KeyError:
   pass
# The first directory in the path is the first directory from PythonPath
# in our Apache config, which is, by convention, always pyserver.
# pyserver_glue will complain if this isn't the case.
os.chdir(os.path.abspath(sys.path[0]))

import hotshot
import time
import traceback

import conf
import g

# NOTE: This must come early, before triggering any other pyserver imports.
import logging
from util_ import logging2
# FIXME: This is overriding CONFIG's and conf.py's logging.level.
log_level = logging.INFO
#log_level = logging.DEBUG
#log_level = logging2.VERBOSE1
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE3
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(log_to_file=True,
                  log_to_console=False,
                  log_line_len=conf.log_line_len,
                  log_level_force=log_level,
                  add_thread_id=True)

log = g.log.getLogger('gwis_mod_python')

import gwis.request
from gwis.exception.gwis_fatal import GWIS_Fatal
from gwis.exception.gwis_warning import GWIS_Warning

# ***

# Entry point from Apache
#
def handler(areq):

   '''
   The main handler method; all the work is done here.
      I.e., this is the entry point for flashclient, per
         /etc/apache2/sites-available/cyclopath
      See modpython.org for more info
   '''

   log.verbose("Welcome to pyserver!!")

   # DEVs: This is your first chance to break into an apache request.
   #log.info("DEBUGGING")
   #import rpdb2;rpdb2.start_embedded_debugger('password', fAllowRemote=True)

   start_time_msec = time.time()

   try:

      logging2.APACHE_REQUEST = areq

      resp = handler_wrapped(areq, start_time_msec)

      # resp is either apache.HTTP_NOT_IMPLEMENTED or apache.OK

   except GWIS_Warning, e:

      content_out = e.as_xml()

      gwis.request.Request.areq_send_response(areq, content_out,
                                              start_time_msec=start_time_msec)

      resp = apache.OK

   except Exception, e:

      # 2012.08.16: This never happens. The handler_wrapped fcn. will make a
      #             GWIS_Fatal for any unexpected exception.
      #             So, like, we could g.assurt(False) here and it should never
      #             fire...
      log.error('Unexpected exception (outer): %s' % (traceback.format_exc(),))
      # NOTE: In flashclient, Flex transforms HTTP_BAD_REQUEST into
      #       IOErrorEvent.IO_ERROR. As opposed to network disconnects, which 
      #       are sent to Event.COMPLETE as a 0-length response. Whatever.
      #       Silly Flex. It's easier just to be deliberate and catch all of
      #       our errors and return a nonzero length packet. Which is why this
      #       code never runs anymore, but when it did, we passed back this,
      #       i.e., 400 Bad Request.
      resp = apache.HTTP_BAD_REQUEST
      # We could, but don't, in case: g.assurt(False) # This code is a no-path.

   # NOTE: If we completely bail, i.e., if we were to call g.assurt(False)
   # right here, Apache sends an error message back to the client. But 
   # flashclient is waiting for an end-of-message, too (or maybe it's waiting
   # for a packet of pre-specified length?) but in either case flashclient gets
   # the mod_python error message but does nothing until its internal timeout
   # fires (because Apache doesn't FIN/ACK the request). See Footnote [1] for 
   # an example MOD_PYTHON ERROR msg. So, basically, make sure all of our 
   # responses are deliberate.
   #
   # For the curious dev, try either 
   #
   #    while True:
   #       time.sleep(1)
   #
   # and then load flashclient, wait a few seconds, and then restart apache.
   #
   # Or try 
   #
   #    g.assurt(False)
   #
   # and then load flashclient.
   #
   # In either case, flashclient loads but throbs continuously; to test,
   # restart apache, which immediately causes flashclient to display a message
   # that the server had a problem. (2012.08.18: I think my assurt test was 
   # wrong, since I had the rpdb2 debugger set to fire on assurt, so I think 
   # pyserver was waiting for an rpdb2 connection....)
   #
   # But with the assurt, if you don't dismiss that message for ten minutes 
   # (the length of the flashclient request timeout), you'll see in
   # the flashclient logs that Flash finally tried to complete the request
   # but that the XML was instead just the error text from mod_python (see
   # Footnote [1] for an example of a mod_python error message). (With the 
   # while loop, I never saw anything show up in flashclient.)
   #
   # Anway, I can't explain why the assurt response gets processed twice in
   # flashclient... is it still waiting on an EOF from Apache, or a FIN?
   # But in any case, there's one simple solution: always catch your errors!

   return resp

# ***

# A wrapper so we can catch any raise (otherwise Apache prints a stack dump to
# the apache log file, but it's nice to dump the error into the pyserver log
# file instead).
#
def handler_wrapped(areq, start_time_msec):

   try:

      # Bug 0072/2411: Does profiling still work?
      if conf.profiling:
         profiler = hotshot.Profile(conf.profile_file)
         profiler.start()

      # We only handle GET and POST (that is, we're not RESTful!)
      if areq.method not in ('GET', 'POST'):
         log.debug('Not GET or POST')
         resp = apache.HTTP_NOT_IMPLEMENTED
      else:
         log.debug('Processing request')
         # Wrap the Apache request with our own object
         req = gwis.request.Request(areq, start_time_msec)
         # Defer all processing to the request object
         req.process_req()
         resp = apache.OK

      if conf.profiling:
         profiler.close()

   except GWIS_Warning, e:

      # Raise again; caller will catch and send the gwis_error XML packet.

      raise

   except Exception, e:

      log.error('Unexpected exception (inner): %s' % (traceback.format_exc(),))

      # Well, we caught an unexpected error, a/k/a Our Fault! Make a special 
      # gwis_fatal response for it -- this lets flashclient know we crashed.

      # This is the client-facing error, so we don't want to send specifics,
      # since not even we know what happened!
      raise GWIS_Fatal('Unexpected exception')

   return resp

# ***

# Footnote [1]: Example MOD_PYTHON ERROR message.
#
#  <pre>
#  MOD_PYTHON ERROR
#  
#  ProcessId:      29118
#  Interpreter:    'minnesota'
#  
#  ServerName:     'ccp.some-server.tld'
#  DocumentRoot:   '/ccp/dev/cp_nnnn/htdocs'
#  
#  URI:            '/gwis'
#  Location:       '/gwis'
#  Directory:      None
#  Filename:       '/ccp/dev/cp_nnnn/htdocs/gwis'
#  PathInfo:       ''
#  
#  Phase:          'PythonHandler'
#  Handler:        'gwis_mod_python'
#  
#  Traceback (most recent call last):
#  
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      default=default_handler, arg=req, silent=hlist.silent)
#  
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      result = _execute_target(config, req, object, arg)
#  
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      result = object(arg)
#  
#    File "/ccp/dev/cp_nnnn/pyserver/gwis_mod_python.py", line 97, in handler
#      g.assurt(False)
#  
#    File "/ccp/dev/cp_nnnn/pyserver/g.py", line 95, in assurt
#      raise Ccp_Assert(message)
#  
#  Ccp_Assert:   
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      default=default_handler, arg=req, silent=hlist.silent)
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      result = _execute_target(config, req, object, arg)
#    File "/usr/lib64/python2.7/site-packages/mod_python/importer.py", line ...
#      result = object(arg)
#    File "/ccp/dev/cp_nnnn/pyserver/gwis_mod_python.py", line 97, in handler
#      g.assurt(False)
#  
#  </pre>

