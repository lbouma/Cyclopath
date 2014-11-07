#!/bin/bash

# 2012.10.17: This script created so I don't need to click so many terminal
#             buttons... and so I don't need to keep editing Gnome shortcuts.

# MAYBE: You can kill all existing gnome-terminals (they're just one process),
#        run,
# killsomething gnome-terminal

# NOTE: If we don't use & to execute these terminals in the background, the
#       gnome shortcut opens just the first terminal, and then when you close
#       that one, it'll open the second terminal, etc.
# NOTE: If we don't wait between each terminal being opened, they won't claim
#       their proper place in the gnome taskbar.

function do_sleep () {
  echo "import time;time.sleep(0.5)" | python
}

# Make sure we reset the DUBs vars btw calls, otherwise they'll be used in
# subsequent commands (if you're running this openterms.sh script from a gnome
# taskbar shortcut).

# 
DUBS_TERMNAME="rpdb" \
  DUBS_STARTIN=/ccp/dev/ccpv3_trunk/pyserver/bin/winpdb \
  DUBS_STARTUP="py rpdb2.py" \
  /home/$USER/dubs/bin/termdub.py -t lhs \
  &
do_sleep

DUBS_TERMNAME="" \
  DUBS_STARTIN=/ccp/bin/ccpdev \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t lhs \
  &
do_sleep

#
DUBS_TERMNAME="V2" \
  DUBS_STARTIN=/ccp/dev/cp_trunk_v2 \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="V1" \
  DUBS_STARTIN=/ccp/dev/cp_trunk_v1 \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="V3" \
  DUBS_STARTIN=/ccp/dev/cp_trunk_v3 \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="Working" \
  DUBS_STARTIN=/ccp/dev/cp/flashclient \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

#
DUBS_TERMNAME="Logs" \
  DUBS_STARTIN=/ccp/var/log/daily \
  DUBS_STARTUP="logs" \
  /home/$USER/dubs/bin/termdub.py -t logs \
  &
do_sleep

DUBS_TERMNAME="Logc" \
  DUBS_STARTIN=/ccp/var/log/daily \
  DUBS_STARTUP="logc" \
  /home/$USER/dubs/bin/termdub.py -t logc \
  &
do_sleep

#
DUBS_TERMNAME="Psql-v1" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="psql -U cycling ccpv1_lite" \
  /home/$USER/dubs/bin/termdub.py -t logs \
  &
do_sleep

# FIXME: Change from ccpv3_demo to ccpv3_live/_lite.
DUBS_TERMNAME="Psql-v2" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="psql -U cycling ccpv3_demo" \
  /home/$USER/dubs/bin/termdub.py -t logc \
  &
do_sleep

#
DUBS_TERMNAME="rLogs" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="sss runic" \
  /home/$USER/dubs/bin/termdub.py -t logs \
  &
do_sleep

DUBS_TERMNAME="rPsql" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="sss runic" \
  /home/$USER/dubs/bin/termdub.py -t logc \
  &
do_sleep

#
DUBS_TERMNAME="" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

#
DUBS_TERMNAME="" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="" \
  DUBS_STARTIN="/ccp/etc/cp_confs" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

#
DUBS_TERMNAME="" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="" \
  DUBS_STARTIN="" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

#
DUBS_TERMNAME="" \
  DUBS_STARTIN="/ccp/dev/cp/pyserver" \
  DUBS_STARTUP="" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

DUBS_TERMNAME="py" \
  DUBS_STARTIN="/ccp/dev/cp/pyserver" \
  DUBS_STARTUP="python" \
  /home/$USER/dubs/bin/termdub.py -t dbms \
  &
do_sleep

#
# Skipping: /home/$USER/dubs/bin/termdub.py -t mini

