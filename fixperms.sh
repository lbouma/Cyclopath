#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# BUG 1998: Remove ' bettercp'

# FIXME: Include fixperms in scripts/?

script_relbase=$(dirname $0)
script_absbase=`pwd $script_relbase`

if [[ -e /ccp/bin/ccpdev/bin/fixperms ]]; then
   # Cyclopath (cs.umn.edu) development machine.
   /ccp/bin/ccpdev/bin/fixperms --public ${script_absbase}/
elif [[ -e /project/Grouplens/bin/fixperms ]]; then
   # Cyclopath (cs.umn.edu) development machine.
   /project/Grouplens/bin/fixperms --public ${script_absbase}/
else
   # All others.
   ${script_absbase}/scripts/util/fixperms.pl --public ${script_absbase}/
fi

