# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Request object; contains Apache request object and other handy stuff.

try:
   from mod_python import apache
   import mod_python.util
except ImportError:
   pass # script is being run locally
import hashlib
from lxml import etree
import re
import time
import traceback

import conf
import g

from grax.item_manager import Item_Manager
from gwis import cmd_factory
from gwis.query_branch import Query_Branch
from gwis.query_client import Query_Client
from gwis.query_filters import Query_Filters
from gwis.query_overlord import Query_Overlord
from gwis.query_revision import Query_Revision
from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_ import mem_usage
from util_ import misc

log = g.log.getLogger('gwis.request')

class Request_Parts(object):

   __slots__ = (
      'branch',            # query_branch object
      'client',            # query_client object
      'filters',           # query_filters object
      'revision',          # query_revision object
      'viewport',          # query_viewport object
      )

   def __init__(self, req):
      self.branch = Query_Branch(req)
      self.client = Query_Client(req)
      self.filters = Query_Filters(req)
      self.revision = Query_Revision(req)
      self.viewport = Query_Viewport(req)

   def decode_gwis(self):
      # Decode the GWIS packet. Do this is a particular order, since some
      # routines expect previous routines to have populated some things.
      self.client.decode_gwis()
      self.filters.decode_gwis()
      self.revision.decode_gwis()
      self.viewport.decode_gwis()
      #
      self.branch.decode_gwis()

# Request wraps an Apache request object from ModPython. For more info:
# http://www.modpython.org/live/current/doc-html/pyapi-mprequest-mem.html
class Request(object):

   __slots__ = (
      'start_time_str',    # time of request initialization (string)
      'start_time_msec',   # time of request initialization (float)
      'areq',              # Apache request object from mod_python
      'cmd',               # command object
      'db',                # db_glue object
      'doc_in',            # incoming request body (XML tree)
      'raw_content',       # incoming request body (raw)
      'content_in',        # incoming request body (text)
      'content_out',       # outgoing response body (text)
      'file_data_in',      #
      'htmlfile_out',      # override content_out and send html back instead
      'sendfile_out',      # override content_out and send file back instead
      'gwis_kvp_in',       # GWIS key-value parameters
      'parts',             # Request_Parts object
      #
      'branch',            # query_branch object
      'client',            # query_client object
      'filters',           # query_filters object
      'revision',          # query_revision object
      'viewport',          # query_viewport object
      )

   def __init__(self, areq, start_time_msec=None):

      log.verbose('Creating new request')

      # Remember when we starting processing this request so we can compute
      # how long it takes
      self.start_time_str = misc.nowstr()
      self.start_time_msec = start_time_msec or time.time()

      self.areq = areq

      self.cmd = None

      self.db = None
      self.doc_in = None

      self.raw_content = ''
      self.content_in = ''

      self.content_out = None
      self.file_data_in = None
      self.htmlfile_out = None
      self.sendfile_out = None

      self.gwis_kvp_in = dict()

      if self.areq is not None:
         self.setup_areq()

      # Do this last, since these guys do a lot more processing of things we
      # just configured.
      self.parts = Request_Parts(self)
      # Convenience ptrs.
      self.branch = self.parts.branch
      self.client = self.parts.client
      self.filters = self.parts.filters
      self.revision = self.parts.revision
      self.viewport = self.parts.viewport

   # ***

   #
   def __str__(self):
      selfie = (
        #'request: raw: %s / rln: %s / req: %s / hdr: %s'
        'request: rln: %s / req: %s'
         % (#self.raw_content,
            self.areq.read_length if self.areq is not None else '',
            self.areq.the_request if self.areq is not None else '',
            #self.areq.headers_in if self.areq is not None else '',
            ))
      return selfie

   #
   def setup_areq(self):

      # Tell mod_python to populate the subprocess_env member
      self.areq.add_common_vars()
      #log.verbose('Apache request: %s' % (dir(areq),))

      # If you send a direct request from your browser or wget, e.g.,
      #   http://ccpv2/gwis?rqst=item_names_get&ityp=branch&gwv=3
      # you'll get a KeyError on Content-Type.

      try:

         time_0 = time.time()

         log.verbose('self.areq.headers_in[\'Content-Type\']: %s'
                     % (self.areq.headers_in['Content-Type'],))

         if self.areq.headers_in['Content-Type'] == 'text/xml':
            # FIXME: This voodoo strips out any non-ASCII characters and
            #        replaces them with question marks. This is a nasty hack
            #        to address SQL injection (see Bug 1599), because I [reid]
            #        don't have time to figure out character encoding problems
            #        right now (see Bug 1224). I believe psycopg may also be a
            #        problem (Bug 1532).
            do_decode = True
         elif (self.areq.headers_in['Content-Type']
                == 'application/x-www-form-urlencoded'):
            # This is a download request from the client. For whatever reason,
            # when you use Flex's FileReference, Flash sends this header. The
            # content is still our GML, though (can we start calling it CCPML
            # or something? It's XML, I guess, but it's our XML, and not
            # Geometric XML, per se).
            do_decode = True
         else:
            # This is upload data. Or unexpected unsomethings.
            do_decode = False

         if do_decode:
            # 2014.02.04: Hrmpf. I copied and pasted from a Web page and
            # there was a hidden unicode control character (the left-to-right
            # mark). It gets decoded from three characters to one (the "?").
            #   http://bugs.cyclopath.org/show_bug.cgi?id=2826
            self.raw_content = self.areq.read()
            cnt_decoded = self.raw_content.decode('utf-8')

            # BUG nnnn: i18n support. Here we dump anything that's not ASCII!
            # 2014.02.04: If we 'replace', then unicode characters become
            #             question marks. But sometimes the unicode character
            #             is a hidden control character, so why not just ignore
            #             it.
            #  self.content_in = cnt_decoded.encode('ascii', 'replace')
            self.content_in = cnt_decoded.encode('ascii', 'ignore')

         else:
            self.setup_areq_incoming()

      except KeyError, e:

         # setup_areq: KeyError: e: 'Content-Type'
         # setup_areq: rln: 0 / req: GET /gwis?request=Null&ping=mon.itor.us
         # HTTP/1.0 / hdr: {'Accept': '*/*', 'Host': 'cycloplan.cyclopath.org',
         # 'Connection': 'close', 'User-Agent': 'Mozilla/5.0 (compatible;
         # mon.itor.us - free monitoring service; http://mon.itor.us)'}
         mon_itor_us_req_g = 'GET /gwis?request=Null&ping=mon.itor.us HTTP'
         # 2014.02.18: Wait, what? When did they start POSTing?
         mon_itor_us_req_p = 'POST /gwis?request=Null&ping=mon.itor.us HTTP'
         if (self.areq.the_request.startswith(mon_itor_us_req_g)
             or self.areq.the_request.startswith(mon_itor_us_req_p)):
            # It doesn't really matter what we return, since the answer is not
            # parsed. So just short-circuit the byte outta here!
            raise GWIS_Warning('Hello, mon.itor.us.',
                               tag=None, logger=log.info)

         # This is a bit of a hack, but it's fine unless we add a bunch
         # more HTML-responding commands. For now, the user_unsubscribe
         # command is a rare command that returns HTML.
         unsubscribe_req = 'GET /gwis?request=user_unsubscribe&'
         nowatchers_req = 'GET /gwis?request=user_nowatchers&'
         if (    (not self.areq.the_request.startswith(unsubscribe_req))
             and (not self.areq.the_request.startswith(nowatchers_req))):
            # We should make exceptions for known non-conformities, like
            # mon.itor.us. But the rest are suspect and we should investigate.
            # E.g.,
            # Jan-12 05:17:31 WARN gwis.request # 140702243264344-67:
            #   setup_areq: KeyError: e: 'Content-Type'
            # Jan-12 05:17:31 WARN gwis.request # 140702243264344-67:
            #   setup_areq: rln: 0 / req: GET /gwis?rqst=item_draw_class_get&
            #   ...&android=true HTTP/1.1 / hdr: {'Accept-Encoding': 'gzip',
            #   'Connection': 'Keep-Alive', 'Host': 'cycloplan.cyclopath.org',
            #   'User-Agent': 'Dalvik/1.6.0 (Linux; U; Android 4.1.1;
            #                                sdk Build/JRO03R)'}
            # So... this is a rogue Android app, or is someone testing?
            log.warning('setup_areq: KeyError: e: %s' % (str(e),))
            log.warning('setup_areq: rln: %s / req: %s / hdr: %s'
                        % (self.areq.read_length,
                           self.areq.the_request,
                           self.areq.headers_in,))
            # Content-Type is missing. Or this is a GET not POST.
            # And we want logcheck complaints, so log to warning or error.
            raise GWIS_Error('Malformed request. Sorry!',
                             tag=None, logger=log.error)
            # To continue processing instead, just comment the last line, then:
         # else, it's a special command, user_unsubscribe or user_nowatchers.
         self.content_in = ''

      except IOError, e:

         # E.g., "IOError: Client read error (Timeout?)"
         self.content_in = ''
         elapsed = time.time() - time_0
         log.debug('setup_areq: %s / err: %s'
                   % (misc.time_format_scaled(elapsed)[0], str(e),))
         # Raising GWIS_Error is the easiest way to stop processing the
         # request, but then we'll try to send a response... which should fail.
         raise GWIS_Error('IOError on Timeout. Are you there?',
                          tag=None, logger=log.info)

   #
   def setup_areq_incoming(self):

      #import rpdb2
      #rpdb2.start_embedded_debugger('password', fAllowRemote=True)
      g.assurt(self.areq.headers_in['Content-Type'].startswith(
         'multipart/form-data; boundary='))

      # BUG nnnn: This is nuts. I [lb] can't figure out how to process a
      # download in parts. So, for now, everything gets loaded in memory.
      # Also, I can't figure out how to get req.data in flashclient to
      # set its Content-Disposition: form-data; name= to something other
      # than the first few chars of the GML.

      # FieldStorage calls read(), which exhausts the request of data.
      # It also converts the URL components as well as the multipart
      # components into dictionary key,value pairs.
      #
      # I looked and I looked and I looked and this seems like the best
      # way to get megabytes of data via a download (i.e., an upload from
      # the client). There is, like, no forum chatter about gettings
      # downloads via mod_python. Pyhton's library.pdf says to use
      # FieldStoarge "if you are expecting megabytes to be uploaded -- in
      # that case, use the FieldStorage class instead which is much more
      # flexible." I'm not sure that flexible means faster. Not that that
      # matters -- networks packets can come out of order. And it's not
      # our job to worry about how a download is stored while being
      # received. That is, it could be in memory or on disk, and we don't
      # care. But it seems to me -- and I could be wrong, but I've not
      # read otherwise -- that FieldStorage probably calls the mod_python
      # request's read(), which probably probably means the file we just
      # downloaded, which apache could have chucked on disk, might now be
      # loaded into memory? Or maybe not. Anyway, I think we're left with
      # FieldStorage and nothing else. (I'm not sure how to authenticate
      # the user before making this FieldStorage object: when the client
      # connection is first made, what data can we access to verify the
      # user?)
      fs = mod_python.util.FieldStorage(self.areq)

      # These are all the things from the URL.
      g.assurt(fs['body'].value == 'yes')
      g.assurt(fs['rqst'].value == 'commit')
      # E.g., g.assurt(fs['gwv'].value == '3')
      g.assurt(fs['gwv'].value == str(conf.gwis_version))

      # Skipping: brid, rev, browid, sessid

      # I have no idea what this means. Flex must set it. (The 'Submit
      # Query' sounds vaguely Web 1.0 to me... a blast from the 1997 past
      g.assurt(fs['Upload'].value == 'Submit Query')

      #import rpdb2
      #rpdb2.start_embedded_debugger('password', fAllowRemote=True)

      # FIXME: Use a filter handler?
      #  http://www.modpython.org/live/current/doc-html/pyapi-filter.html
      # So you can periodically track and save bits of the upload
      # (download?) and not have to process it all in memory all at once
      # at the end of the HTTP. Anyway, your httpd.conf will probably
      # time out...............
      log.debug('request.py: Filename: %s' % (fs['Filename'].value,))
      # FIXME: BIG BIG BUG BUG: The way we currently handles files sets
      # us up for huge DDOS attack vector boo-yeah. Should check creds
      # before consuming the whole file, eh buddy?
      # MAGIC_NUMBER: 'Filedata' is Flex's name. Or maybe a Web
      #               standard....
      self.file_data_in = fs['Filedata'].value

      # I don't know how to name the the GML content, so we look for it.
      # startswith.(
      #  '<data>\n  <metadata>\n    <changenote/>\n    <user name')
      # '<data>\n  <metadata>\n    <changenote/>\n    <user name':
      #  [Field('<data>\n  <metadata>\n    <changenote/>\n
      #    <user name', '"username" token="sdfdsfdsfdsfsd"/>\n
      #    </metadata>\n  <items>\n
      #    <merge_job stack_id="-10" version="0" name="null" deleted="0"
      #     job_act="upload" job_priority="0" for_group_id="0"
      #     for_revision="0"/>\n  </items>\n</data>')]

      for key in fs:
         if key.startswith('<data>'):
            # This is so strange. The first number of chars are made into
            # its name, since we didn't specify a name. So reassemble.
            # Oh, baloney. it split on the =. what am i suppose to do??!!
            # This is a superhack. Add the equals back into the XML....
            # I figure figure how else to split a multipart (in python),
            # and I can't figure out how to tell Flash to name to XML
            # data portion of the URLRequest... jeepers! At this this
            # works, super wonder golden trick.
      # FIXME: There's still a problem decoding the xml..........
            self.content_in = key + '=' + fs[key]
            self.content_in = \
               self.content_in.decode('utf-8').encode('ascii', 'replace')
            #
            #self.content_in = key + fs[key]
            log.debug('found data/content_in: %s' % (self.content_in,))
            break # Don't allow us to be fooled twice, fool you
         else:
            log.verbose('request.py: key: %s' % (key,))
            g.assurt(key in ('body', 'rqst', 'gwv',
                             'brid', 'rev', 'browid', 'sessid',
                             'Upload', 'Filedata', 'Filename',))

   # *** Public interface

   #
   def as_iqb(self, addons=True, username=None, user_group_id=None):
      # See if the caller wants the user's viewport or filters or not.
      if addons:
         viewport = self.viewport
         filters = self.filters
      else:
         viewport = None
         filters = None
      # Respect anonymous cowards.
      if (not username) and (not user_group_id):
         username = self.client.username
         user_group_id = self.client.user_group_id
      else:
         g.assurt(username and user_group_id)
      # Check the rev.
      # Make the query builder based on the request parts.
      qb = Item_Query_Builder(self.db,
                              username,
                              self.branch.branch_hier,
                              self.revision.rev,
                              viewport, filters)
      # This is a lotta hacky. Setup the dev. switches.
      # Skipping qb.request_is_mobile = self.client.request_is_mobile
      qb.request_is_local = self.client.request_is_local
      qb.request_is_script = self.client.request_is_script
      qb.request_is_secret = self.client.request_is_secret
      # This is a littler more hacky.
      # NOTE: self.doc_in is None during route analysis.
      if self.doc_in is not None:
         riat = self.doc_in.find('./metadata').get('request_is_a_test', False)
         qb.request_is_a_test = bool(int(riat))
      # This one's not too hacky.
      qb.user_group_id = user_group_id
      #
      qb.session_id = self.client.session_id
      qb.remote_ip = self.client.remote_ip
      qb.remote_host = self.client.remote_host
      # Make sure the Item_Manager is available, whether or not we use it
      # (and do it before we call finalize_query, which may need it).
      qb.item_mgr = Item_Manager()
      # Call finalize_query now so we calculate, e.g., only_in_multi_geometry.
      Query_Overlord.finalize_query(qb)
      # Return the completed query builder.
      return qb

   #
   def process_req(self):
      '''
      Processes a client request.

      This request always succeeds, even if the request cannot really be
      processed (that is, if the request cannot be completed for the user,
      we return error text instead).
      '''

      log.verbose('Processing request')

      # This server isn't RESTful; we only support GET and POST, not UPDATE or
      # DELETE.
      g.assurt(self.areq.method in ('GET', 'POST',))

      # Developers can enable dump_requests to get local copies of client
      # request (but Landon recommends you use a network sniffer instead,
      # namely, WireShark).
      if conf.dump_requests:
         self.dump_request(conf.dump_dir)

      # Track memory usage, if requested.
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      # Wrap our control logic with an outer try block so we can catch
      # exceptions raised by the inner try block exception handler
      try:

         # Use one try block to try to process the user's request; if anything
         # fails, we'll catch it and try to send the user an error message.
         try:
            # Developers can break into the debugger here if they wish,
            # after the client request is parsed but before it's processed
            if conf.break_on_gwis_request:
               log.debug('Waiting for remote debug client...')
               import rpdb2
               rpdb2.start_embedded_debugger('password', fAllowRemote=True)
            # Open the database connection
            log.verbose('Opening database connection')
            g.assurt(self.db is None)
            self.db = db_glue.new()
            # Process the request
            self.command_process_req()
         # GWIS throws an error if Cyclopath cannot (or will not) complete the
         # request (i.e., GML syntax error, or user doesn't have access, etc.)
         # This catches both GWIS_Warning and GWIS_Error.
         except GWIS_Warning, e:
            self.error_handler_gwis(e)
         # Python throws an error if we made a programming error; these
         # should always be bugs that we must fix (otherwise use GWIS_Error).
         except Exception, e:
            self.error_handler_exception(e)

         # Fall-through from try-block; the exception handlers for the
         # previous try-block never re-raise, so execution always makes
         # it here.

         # Let go of the database lock once outside of the try block
         if self.db is not None:
            # NOTE: Under normal conditions -- that is, the request succeeded
            #       -- there's nothing to rollback. However, if processing the
            #       request threw an exception, here's where we roll it back.
            self.db.transaction_rollback()
            self.db.close()
            self.db = None

         # Send the response to the client. At this point, we know that the
         # response is a GWIS XML response of some kind, even if it's an
         # error, so 200 OK is always the right HTTP response code.
         # NOTE This raises if there's an unexpected error (in which case
         #      we won't be returning 200 OK)
         self.command_process_resp()

      # Handle unhandled exceptions
      except Exception, e:
         log.debug('Caught exception "%s" / %s'
                   % (str(e), traceback.format_exc(),))
         # EXPLAIN: Why don't we call apache.log_error like in
         #          error_handler_exception()?
         # Catastrophic failure or IOError; unknown exception;
         #   dump and re-raise
         self.dump_exception(conf.dump_dir)
         # If the developer hasn't already asked for the dump, dump it.
         # NOTE This means we always dump exceptions on the production
         #      server, since we always want to investigate these failures.
         if not conf.dump_requests:
            self.dump_request(conf.dump_dir)
         # NOTE Re-raise the failure, which Apache catches, not us!
         raise

      conf.debug_log_mem_usage(log, usage_0, 'request.process_req')

      return

   # *** Private interface

   # Process the request
   def command_process_req(self):
      # Prepare the request object
      # NOTE The request object called this earlier
      #self.areq.add_common_vars()
      self.decode_gwis()
      # Tell the class object to process the request
      self.cmd.doit()
      # Prepare the response.
      self.content_out = self.cmd.response_xml()
      # FIXME: reset self.cmd to None?
      self.cmd = None

   #
   def command_process_resp(self):
      Request.areq_send_response(self.areq,
                                 self.content_out,
                                 self.htmlfile_out,
                                 self.sendfile_out,
                                 self.start_time_msec,
                                 self.dump_response)

   #
   @staticmethod
   def areq_send_response(areq,
                          content_out,
                          htmlfile_out=None,
                          sendfile_out=None,
                          start_time_msec=None,
                          dump_response_fcn=None):

      # Mark the processing time, or how long we took to handle the request.
      # FIXME: Are we sending ptime to the client? (It's in the Apache req.)
      elapsed = time.time() - start_time_msec
      areq.subprocess_env['ptime'] = ('%.3g' % (elapsed,))

      # Setup the response.
      if htmlfile_out is not None:
         areq.content_type = 'text/html'
         areq.set_content_length(len(htmlfile_out))
         try:
            log.verbose('areq_send_response: sending html...')
            areq.write(htmlfile_out)
            time_elapsed = misc.time_format_elapsed(start_time_msec)
            log.info('areq_send_response: sent %d html bytes in %s'
                     % (len(htmlfile_out), time_elapsed,))
         except IOError, e:
            Request.raise_on_non_remote_problem(e, callee='html')
      elif sendfile_out is not None:
         # See modpython.org/live/current/doc-html/pyapi-mprequest-meth.html
         #
         # This fcn. obviously blocks.
         try:
            # If we run into problem, we could trying implementing a download
            # resume feature: sendfile(path, offset, len)
            bytes_sent = areq.sendfile(sendfile_out)
            log.debug('bytes_sent: %d' % (bytes_sent,))
         except IOError, e:
            Request.raise_on_non_remote_problem(e, callee='file')
      else:
         g.assurt(content_out)
         areq.content_type = 'text/xml'
         # Set the length of the response.
         areq.set_content_length(len(content_out))
         # We use a try/except block to send the request. It's okay if this
         # fails because the client disconnected, but if it fails for any other
         # reason, re-raise.
         try:
            # Send the response to the client.
            log.verbose('areq_send_response: sending...')
            areq.write(content_out)
            time_elapsed = misc.time_format_elapsed(start_time_msec)
            log.info('areq_send_response: sent %d gwis bytes in %s'
                     % (len(content_out), time_elapsed,))
            # See if the developer wants a local copy of the response.
            # (Again, Landon suggests using WireShark to sniff the network,
            #  which is quicker and more powerful.)
            if conf.dump_responses and (dump_response_fcn is not None):
               dump_response_fcn(conf.dump_dir)
         except IOError, e:
            Request.raise_on_non_remote_problem(e, callee='xml')

   #
   @staticmethod
   def raise_on_non_remote_problem(io_err, callee):
      # If the error is the client simply going away, we want to ignore
      # that. But re-raise other IOError's. See bug 1479.
      # DeprecationWarning: BaseException.message deprecated as of Python 2.6
      #  Not needed: io_err.message
      if ((str(io_err).find('Write failed, client closed connection.') == 0)
          or (str(io_err).find('Client read error (Timeout?)') == 0)):
         log.info('Ignoring IOError [%s]: %s' % (callee, io_err,))
      else:
         log.error('Unexpected IOError: %s' % (io_err,))
         raise

   #
   def decode_gwis(self):
      '''
      Decode the GWIS parameters of the request.
      * Decode the Request-URI query string (the part of the URL after '?').
        We place keyword-value pairs (KVPs) in self.gwis_kvp_in as a dictionary
        with lowercase keys (similar to WFS spec sec. 13). GWIS does not
        support multiple occurences of the same keyword.
      * Parse any XML input and place the etree object at req.doc_in.
      * Verify the GWIS 'version' of the request.
      * Create a command object based on the type of request.
      * Set up the request helpers based on the incoming request.
      '''
      # FIXME: Check the mobile version.

      # Decode KVPs (from URL query string).
      if self.areq.args is not None:
         kvp = mod_python.util.parse_qs(self.areq.args)
         for (k, v) in kvp.iteritems():
            self.gwis_kvp_in[k.lower()] = v[0]

      # Parse incoming GML (from HTTP POST content part).
      # BUG 2725: Mobile sometimes sends a WFS_Log (GWIS_Log) with nonzero
      #           Content-Length but no content.
      # FIXME: This doesn't fix the mobile problem, it just catches it here;
      #        we still need to fix the problem in the android code.
      try:
         found_errs = []
         raise_error = ''
         content_len_hdr = int(self.areq.headers_in['Content-Length'])
         content_len_req = int(self.areq.read_length)
         if content_len_hdr != content_len_req:
            found_errs.append('content_len_hdr != content_len_req')
         if (content_len_hdr == 0) or (content_len_req == 0):
            found_errs.append('content_len_* is zero')
            # FIXME: Should we raise?? Or are there XML-less commands?
         if len(self.content_in) == 0:
            found_errs.append('len(self.content_in) is zero')
            # FIXME: Should we raise?? Or are there XML-less commands?
         # Because we drop unicode control characters, the length of the
         # decoded string might be less than the input string's length.
         # See: http://bugs.cyclopath.org/show_bug.cgi?id=2826
         if len(self.content_in) > content_len_hdr:
            found_errs.append('content_len_hdr > len(self.content_in)')
            raise_error = 'Unexpected XML content length: so large'
         if found_errs:
            # 2014.02.04: Investigate this now that the length code above is
            #             different.
            log_f = log.error
            if False:
               # 2014.09.23: Happened twice at 18:03:05, but says android=true.
               #             Do we need to cast the_request to str?
               # Misses some: if '&android=true' in self.areq.the_request:
               if '&android=true' in str(self.areq.the_request):
                  log_f = log.info
               else:
                  log_f = log.error
            # SYNC_ME: Search: logcheck.
            log_f('decode_gwis: found errors: %s' % (' / '.join(found_errs),))
            log_f('decode_gwis: raw req: %s' % (self.raw_content,))
            log_f('decode_gwis: decoded: %s' % (self.content_in,))
            log_f('decode_gwis: req_ln: %s / hdr_ln: %s / req: %s / hdr: %s%s'
               % (content_len_req,
                  content_len_hdr,
                  self.areq.the_request,
                  self.areq.headers_in,
                  '' if not raise_error else ' / raising',))
         # FIXME: Does Android display an error when this happens to WFS_Log,
         #        or does it silently fail?
         if raise_error:
            raise GWIS_Error(raise_error)
      except KeyError:
         # Requests from Flashclient usually specify Content-Length. But other
         # commands, like a ping from mon.it.or.us, don't specify it.
         g.assurt(not self.content_in)
         pass

      if self.content_in:

         try:
            # BUG 2825: Mobile doesn't encode ampersands. E.g.:
            #   b'<data><metadata><device is_mobile="True" /></metadata><addrs>
            #    <addr addr_line="Gateway Fountain" />
            #    <addr addr_line="W 50th St & S Dupont Ave" /></addrs></data>'
            # XMLSyntaxError(u'xmlParseEntityRef: no name, line 1, column 89',)
            # BUG 2825 (part 2): Mobile Geocoding fails, presumably because the
            #  addr they send us does not match the one we return (we'd have to
            #  unencode the &amp; in our response to match the original query).
            # Bug 2825 - Mobile does not encode to/from addresses in GWIS 
            #  http://bugs.cyclopath.org/show_bug.cgi?id=2825
            # The XML is not URL encoded, so, e.g.,
            #   >>> from lxml import etree
            #   >>> test='<addr addr_line="Central & university"/>'
            #   >>> etree.fromstring(test)
            #   Traceback (most recent call last):
            #     File "<stdin>", line 1, in <module>
            #     ...
            #   lxml.etree.XMLSyntaxError: xmlParseEntityRef: ...
            #   >>> test='<addr addr_line="Central &amp; university"/>'
            #   >>> etree.fromstring(test)
            #   <Element data at 0xbcb280>
            #   >>>
            try:
               self.doc_in = etree.fromstring(self.content_in)
            except etree.XMLSyntaxError, e:
               log.error('mobile bug not encoding: "%s"' % (self.content_in,))
               # MAYBE: [lb] tried a work-around but this is only half of it:
               #        In the response, we want to use the original content_in
               #        but I didn't add the second part of the work-around: at
               #        this point it seems wiser to just fix the android app.
               #        Nonetheless, here's the work-around code, which we use
               #        to not work-around the bug but to tailor our error msg.
               encode_re = re.compile(r'&([^a-zA-Z]+[^;])')
               try_again = re.sub(encode_re, r'&amp;\1', self.content_in)
               self.doc_in = etree.fromstring(try_again)
               if try_again != self.content_in:
                  # BUG nnnn: This is lame; fix android.
                  raise GWIS_Error('%s%s'
                     % ('There was a problem -- which is our fault. You might',
                        ' have better luck trying "and" instead of "&".',))
               else:
                  log.error(
                    'decode_gwis: %s / cin: %s / req: %s / hdr: %s'
                     % ('not the mobile bug after all?',
                        self.content_in,
                        self.areq.the_request,
                        self.areq.headers_in,))
                  # MAYBE: Really send the Exception text to the client?
                  #        [lb]'s two concerns: 1.) revealing sensitive data
                  #                             2.) confusing users with code
                  raise GWIS_Error('Error parsing XML: %s' % (e,))

         except Exception, e:

            # MAYBE/BUG nnnn: Android Bug nnnn on user_hello?
            # Sep-19 13:44:16 ERRR gwis.request # Error parsing XML:
            # "EntityRef: expecting ';', line 1, column 45" / Traceback:
            #   File "/export/scratch/ccp/dev/cycloplan_live/pyserver/gwis/
            #    request.py", line 571, in decode_gwis
            #     self.doc_in = etree.fromstring(self.content_in)
            #   File "lxml.etree.pyx", line 2532, in
            #    lxml.etree.fromstring (src/lxml/lxml.etree.c:48270)
            #   File "parser.pxi", line 1545, in
            #    lxml.etree._parseMemoryDocument (src/lxml/lxml.etree.c:71812)
            #   File "parser.pxi", line 1424, in
            #    lxml.etree._parseDoc (src/lxml/lxml.etree.c:70673)
            #   File "parser.pxi", line 938, in
            #    lxml.etree._BaseParser._parseDoc (src/lxml/lxml.etree.c:67442)
            #   File "parser.pxi", line 539, in
            #    lxml.etree._ParserContext._handleParseResultDoc
            #     (src/lxml/lxml.etree.c:63824)
            #   File "parser.pxi", line 625, in
            #    lxml.etree._handleParseResult (src/lxml/lxml.etree.c:64745)
            #   File "parser.pxi", line 565, in
            #    lxml.etree._raiseParseError (src/lxml/lxml.etree.c:64088)
            # XMLSyntaxError: EntityRef: expecting ';', line 1, column 45
            #
            # 70.197.196.92 - - [19/Sep/2013:13:44:16 -0500]
            # "POST /gwis?rqst=user_hello&browid=...&sessid=...&android=true
            #   HTTP/1.1" 200 103 "-" "Dalvik/1.6.0 (Linux; U; Android 4.2.2;
            #   Galaxy Nexus Build/JDQ39)" 0.0113

            # NOTE: logcheck filters all log statements from this file because
            #       some of them -- like this one -- might reveal sensitive
            #       user information. But by raising GWIS_Error, logcheck will
            #       see that message, we'll get an email, and then it's up to
            #       a DEV to poke around the log files.
            #
            log.error(
              'decode_gwis: cin: %s / rln: %s / cln: %s / req: %s / hdr: %s'
               % (self.content_in,
                  self.areq.read_length,
                  content_len_hdr, # self.areq.headers_in['Content-Length'],
                  self.areq.the_request,
                  self.areq.headers_in,))
            log.error('Error parsing XML: "%s" / %s'
                      % (e, traceback.format_exc(),))
            # MAYBE: Really send the Exception text to the client?
            #        [lb]'s two concerns: 1.) revealing sensitive data
            #                             2.) confusing users with code
            raise GWIS_Error('Error parsing XML: %s' % (e,))

      # end: if self.content_in

      # Verify GWIS version of request.
      self.verify_request_version()

      # Instantiate a class from gwis.req.* to handle this request.
      try:
         # This throws a GWIS_Error if the request type is unknown.
         try:
            req_class = self.decode_key('rqst')
         except GWIS_Error, e:
            # 'request' is an alias for 'rqst'.
            req_class = self.decode_key('request')
         self.cmd = cmd_factory.get_command(req_class, self)
         #log.debug('Got cmd: %s' % self.cmd)
      except KeyError:
         raise GWIS_Error('GWIS request type not specified.')

      # Configure the request helpers.
      self.parts.decode_gwis()

   #
   def decode_key(self, key, *args, **kwargs):
      '''Return the value of the request parameter key. If required is true
         and the key isn't specified, raise GWIS_Error.'''
      # NOTE: Ignoring kwargs (included for completeness).
      try:
         val = self.gwis_kvp_in[key]
      except KeyError:
         # If the callee specifies a second positional argument, it's the
         # default value to use. If the callee does not specify the second
         # argument, this is a required parameter.
         if len(args) == 1:
            val = args[0]
         else:
            g.assurt(len(args) == 0)
            # From /ccp/var/log/apache2/access.log:
            #  54207 123.456.789.10 - - [23/Dec/2013:17:27:50 -0600]
            #     "GET /gwis HTTP/1.1" 200 96 "-" "Dalvik/1.6.0 (Linux; U;
            #     Android 4.0.3; HTC PH39100 Build/IML74K)" 0.00485
            #  118375 123.456.789.10 - - [02/Feb/2014:15:27:51 -0600]
            #     "GET /gwis HTTP/1.1" 200 81 "-" "Dalvik/1.6.0 (Linux; U;
            #     Android 4.1.1; HTC One X Build/JRO03C)" 0.00537
            #
            # So... a GET request from a phone?
            # See also setup_areq, which sees a similar problem, but the GET is
            # at least filled in...
            log_msg = ('Missing param key: %s / req: %s'
                       % (key, self.areq.the_request,))
            if key in ('rqst', 'request',):
               # This happens when no params are specified, so don't complain.
               logger_f = log.info
            else:
               logger_f = log.warning
            logger_f(log_msg)
            # From logcheck, you'll see
            #   ... GWIS_Exception caught:
            #          Request param "rqst" required but not specified..
            #   ... GWIS_Exception caught:
            #          Request param "request" required but not specified..
            if self.areq.method == 'POST':
               raise GWIS_Error('Request param "%s" required but not specified'
                                % (key,), logger=logger_f)
            else:
               # 2014.09.07: This is that mobile BUG nnnn:
               # E.g., from access.log:
               #   119406 NN.NN.NN.NN - - [07/Sep/2014:10:26:25 -0500]
               #   "GET /gwis HTTP/1.1" 200 81 "-" "Dalvik/1.6.0 (Linux; U;
               #   Android 4.0.4; SAMSUNG-SGH-I777 Build/IMM76D)" 0.00534
               # except when [lb] tries to reproduce it, like,
               #   wget http://cycloplan.cyclopath.org/gwis
               # I just get <gwis_error msg="Malformed request. Sorry!"/>.
               #   132292 lb.lb.lb.lb - - [07/Sep/2014:12:25:12 -0500]
               #   "GET /gwis HTTP/1.1" 200 45 "-" "Wget/1.14 (linux-gnu)" -
               # So, yeah, hrmm...
               #
               g.assurt_soft(self.areq.method == 'GET')
               raise GWIS_Error('Please try a POST request, not "%s"'
                                % (self.areq.method,), logger=logger_f)
      return val

   #
   def decode_key_bool(self, key_name):
      attr_value = self.decode_key(key_name, False)
      try:
         attr_value = bool(int(attr_value))
      except ValueError, e:
         # E.g., ValueError: invalid literal for int() with base 10: 'false'.
         try:
            attr_value = attr_value.lower()
            attr_value = ((attr_value == 'true') or (attr_value == 't'))
         except AttributeError:
            # Not an integer or string.
            attr_value = False
      return attr_value

   #
   def error_handler_exception(self, ex):
      # We wrap exceptions here because the flashclient uses a single
      # io/error event for any status code that's not 200 and we lose the
      # error information to present to the user. We do _not_ re-raise.
      apache.log_error(
         'Unhandled exception; see $dump_dir/dump.EXCEPT for details: '
            + misc.exception_format(ex), apache.APLOG_ERR)
      self.dump_exception(conf.dump_dir)
      if (not conf.dump_requests):
         self.dump_request(conf.dump_dir)
      # 2012.05.10: For whatever reason, I wasn't seeing errors in the log
      # until I added this log trace. So weird....
      log.error('Unhandled exception: %s / %s'
                % (misc.exception_format(ex),
                   traceback.format_exc(),))
      # This message is shown to the user, so make it moderately friendly.
      # NOTE: We use an Exception object, but we don't raise it.
      self.content_out = GWIS_Error(
         'We apologize for the inconvenience, but Cyclopath had a problem. '
         + 'This is not your fault. '
         + 'Our developers have been notified of the problem. '
         + ('If you have any questions, please email %s.'
            % (conf.mail_from_addr,))
         ).as_xml()

   #
   def error_handler_gwis(self, gwis_err):
      self.content_out = gwis_err.as_xml()

   # Check request version (only on non-GetCapabilities)
   def verify_request_version(self):
      versions_supported = [conf.gwis_version,]
      for syn in ('v', 'gwv', 'gwis_version'):
         gwis_version = self.decode_key(syn, '')
         if gwis_version:
            break
      if not gwis_version:
         #log.warning('Client did not specify gwis_version.')
         # 2014.09.09: This happens too often... and it's low priority.
         # EXPLAIN/BUG nnnn: What client is not sending gwis version?
         #log.info('Client did not specify gwis_version.')
         log.debug('Client did not specify gwis_version.')
         gwis_version = conf.gwis_version
      elif (not gwis_version in versions_supported):
         raise GWIS_Warning(
                  'Invalid GWIS version %s; this server only knows %s.'
                  % (gwis_version, str(versions_supported), ))

   # *** Developer interface

   # Developer string dump helpers

   #
   def dump_names(self, dump_dir, kind):
      # obscure IP address in filename
      h = hashlib.md5(self.areq.get_remote_host()).hexdigest()[:5]

      # WARNING: The details of this format are used by cron jobs to detect
      # and report crashes. Do not change unless you know what you are doing!
      return (('%s/dump.%s_%s_%s' % (dump_dir, self.start_time_str, h, kind)),
              ('%s/dump.%s' % (dump_dir, kind)))

   #
   def dump_exception(self, dump_dir):
      'Dumps the pending exception.'
      for filename in self.dump_names(dump_dir, 'EXCEPT'):
         traceback.print_exc(file=open(filename, 'w'))

   #
   def dump_headers(self, fp, headers):
      hs = headers.items()
      hs.sort()
      for h in hs:
         fp.write('%s: %s\n' % (h[0], h[1]))

   #
   def dump_request(self, dump_dir):
      for filename in self.dump_names(dump_dir, 'REQUEST'):
         fp = open(filename, 'w')
         fp.write('*** Request from %s\n' % (self.areq.get_remote_host()))
         fp.write('*** %s\n' % (self.areq.the_request))
         fp.write('\n')
         self.dump_headers(fp, self.areq.headers_in)
         fp.write('\n')
         fp.write(self.content_in)

   #
   def dump_response(self, dump_dir):
      for filename in self.dump_names(dump_dir, 'RESPONSE'):
         fp = open(filename, 'w')
         fp.write('*** Response to %s\n' % (self.areq.get_remote_host()))
         fp.write('*** %s\n' % (self.areq.status_line))
         fp.write('\n')
         self.dump_headers(fp, self.areq.headers_out)
         fp.write('\n')
         fp.write(self.content_out)

   #
   # Logging shortcuts -- this stuff goes to Apache error log.

   #
   def p_notice(self, message):
      self.areq.log_error(message, apache.APLOG_NOTICE)

   def p_warning(self, message):
      self.areq.log_error(message, apache.APLOG_WARNING)

   def p_error(self, message):
      self.areq.log_error(message, apache.APLOG_ERR)

