#!/bin/bash
#
# See: ccpdev/private/runic/etc/logrotate.d/cyclopath
#
# Tell apache to reload. [lb] notes this weird comment about m4 is
# because of auto_install, because this file is generated from a
# template. So the comment is about the m4 template, and not what's
# installed on the server.
# NOTE: m4 is very particular about backticks and singlequotes. The
#  easiest way to p0wn it is by using changequote. If we don't, we can't
#  quote (or, if we do, bah! ``ERROR: end of file in string'').
#
if [[ -f "`. /etc/apache2/envvars ; \
     echo ${APACHE_PID_FILE:-/var/run/apache2.pid}`" ]]; then
   /etc/init.d/apache2 reload > /dev/null
   # FIXME: Do we need to restart mr_do or routed?
   #        [lb] doesn't really want to restart routed,
   #             since it takes so long (at least not until
   #             BUG nnnn is fixed: start new route finder
   #             and then elegantly switch to the new route
   #             finder).
fi
#
# Per https://httpd.apache.org/docs/2.2/logs.html#rotation
# we would want to sleep for a while we the server reloads,
# so it can continue processing requests and writing to the
# old log file. But since we're using delaycompress, we'll
# inherently wait until the next time cron calls us, which
# is once per day.

