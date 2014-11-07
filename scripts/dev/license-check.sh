#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script greps the source tree and prints out all the files that don't
# contain the licence header.

set -e

find . -path '*/.svn' -prune -o -path '*/build' -prune -o -xtype f -a -not \( -name '*.png' -o -name '*.xls' -o -name '*.swf' -o -name '*.svg' -o -name '*~' -o -name '*.pyc' \) -exec grep 'Copyright (c) 2006-2013 Regents of the University of Minnesota' --files-without-match {} \;

