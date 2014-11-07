#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

echo "This script is Deprecated. See the auto_install scripts."
exit

# This script cleans up the ownership and permissions in a stock Ubuntu
# install, making them suitable for Cyclopath development.

set -e

export FIXPERMS=/ccp/bin/ccpdev/bin/fixperms

cleanup_perms()
{
   echo 'Fixing perms on' $1
   sudo chgrp -R grplens $1
   sudo $FIXPERMS $1
}

# Rather than explicitly indicate the Psql version, walk the directory instead
for d in $( ls -d /etc/postgresql/8.* ); do
   cleanup_perms $d/main
done

# Also fix perms. on the Psql log and Apache
for d in /var/log/postgresql /etc/apache2 /var/log/apache2; do
   cleanup_perms $d
done

