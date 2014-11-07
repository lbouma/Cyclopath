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

# 2014.01.21: Linux Mint 16 Cinnamon: The taskbar does not do multi-line.
# There's an applets that's suppose to be a multi-line taskbar/window list,
# but it doesn't seem to work.
#
# So we've disabled the ideal config so that we open fewer windows.

if false; then

  # 1st row
  DUBS_TERMNAME="rpdb" \
    DUBS_STARTIN=/ccp/dev/cp/pyserver/bin/winpdb \
    DUBS_STARTUP="py rpdb2.py" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  # 2nd row
  DUBS_TERMNAME="Trunk" \
    DUBS_STARTIN=/ccp/dev/cp_trunk_v3 \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="Working" \
    DUBS_STARTIN=/ccp/dev/cp/flashclient \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  # 3rd row
  DUBS_TERMNAME="Logs" \
    DUBS_STARTIN=/ccp/var/log/daily \
    DUBS_STARTUP="logs" \
    /ccp/dev/cp/scripts/util/openterm.py -t logs \
    &
  do_sleep

  DUBS_TERMNAME="Logc" \
    DUBS_STARTIN=/ccp/var/log/daily \
    DUBS_STARTUP="logc" \
    /ccp/dev/cp/scripts/util/openterm.py -t logc \
    &
  do_sleep

  # 4th row
  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t logs \
    &
  do_sleep


  DUBS_TERMNAME="Psql-Ccp" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="psql -U cycling ccpv3_lite" \
    /ccp/dev/cp/scripts/util/openterm.py -t logc \
    &
  do_sleep

  #
  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  #
  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  #
  DUBS_TERMNAME="" \
    DUBS_STARTIN="/ccp/dev/cp/pyserver" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="py" \
    DUBS_STARTIN="/ccp/dev/cp/pyserver" \
    DUBS_STARTUP="python" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

fi

# Until Linux Mint 16 Cinnamon Multi-Line Window List Applet is fixed,
# open fewer windows, and just on one line.

if true; then

  DUBS_TERMNAME="Working" \
    DUBS_STARTIN=/ccp/dev/cp/flashclient \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="rpdb" \
    DUBS_STARTIN=/ccp/dev/cp/pyserver/bin/winpdb \
    DUBS_STARTUP="py rpdb2.py" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="Logs" \
    DUBS_STARTIN=/ccp/var/log/daily \
    DUBS_STARTUP="logs" \
    /ccp/dev/cp/scripts/util/openterm.py -t logs \
    &
  do_sleep

  DUBS_TERMNAME="Logc" \
    DUBS_STARTIN=/ccp/var/log/daily \
    DUBS_STARTUP="logc" \
    /ccp/dev/cp/scripts/util/openterm.py -t logc \
    &
  do_sleep

  DUBS_TERMNAME="Psql-Ccp" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="psql -U cycling ccpv3_lite" \
    /ccp/dev/cp/scripts/util/openterm.py -t logc \
    &
  do_sleep

  DUBS_TERMNAME="py" \
    DUBS_STARTIN="/ccp/dev/cp/pyserver" \
    DUBS_STARTUP="python" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

  DUBS_TERMNAME="" \
    DUBS_STARTIN="" \
    DUBS_STARTUP="" \
    /ccp/dev/cp/scripts/util/openterm.py -t dbms \
    &
  do_sleep

fi

