#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Exit on error
set -e

export PYTHONPATH=`python ../pyserver/conf.py`

filenames=`find . -name '*.py' | sed -e 's|^./||' | grep -v '^norvig' | sort`
#filenames="conf.py"

# IGNORING GRIPES.
#
# - If you want to ignore _all_ gripes of a certain class, put the message
#   number in pylint.rc in the list "disable-msg".
# - If you want to ignore _some_ gripes of a ceratin class, put the message
#   text below. (E.g.: "No name 'log' in module 'g'", but simply ignoring
#   E0611 would be overreaching.)
# - If you want to ignore a _specific_ gripe, write e.g.
#   "#pylint: disable-msg=W0123,E4567" at the end of the line or the beginning
#   of the block.
#
# This is a list of regular expressions, one per line. 
# (The tr/sed voodoo is so that the regexes can be specified one per line.)
IGNORE=`(tr '\n' '|' | sed -e 's/|$//' | sed -e 's/|/\\\\|/g') <<EOF
No name 'log' in module 'g'
Undefined variable '__abstract__'
EOF`

# FIXME: This should be rewritten to use a single invocation of pylint on all
# files at once, in order to catch code duplication, but currently this
# crashes pylint.
rm pylint.txt
for filename in $filenames; do
    echo "linting $filename"
    pylint --rcfile=../misc/pylint.rc $filename | grep -v "$IGNORE" - | sed -e "s|^$PWD/||" >> pylint.txt
done

echo 'diff output follows. Note that this output does not show line numbers --'
echo 'you can look in pylint.txt if you need them.'
svn cat pylint.txt | sed -e 's/:[0-9]\+:/:/' > pylint.txt.old
cat pylint.txt | sed -e 's/:[0-9]\+:/:/' > pylint.txt.new
diff -u pylint.txt.old pylint.txt.new

