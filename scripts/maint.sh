#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Enables/disables "maintenance mode" Apache configuration.

set -e

if [[ "$1" == "cycle" ]]; then
  pushd /ccp/dev/cycloplan_live
  CCP_ACTIVE=$(basename `pwd -P`)
  if [[ $CCP_ACTIVE == "cycloplan_sib2" ]]; then
    $1="sib1"
  elif [[ $CCP_ACTIVE == "cycloplan_sib1" ]]; then
    $1="sib2"
  else
    echo "ERROR: Confused by /ccp/dev/cycloplan_live"
    exit 0
  fi
  popd
fi

if [[ "$1" == "sib1" || "$1" == "sib2" ]]; then
  # Fix the symlinks. See also:
  #  http://wiki.grouplens.org/index.php/Cyclopath/Production_and_Deployment
  if [[ -h /ccp/dev/cycloplan_live ]]; then
    /bin/rm -f /ccp/dev/cycloplan_live
  fi
  if [[ -h /ccp/dev/cycloplan_idle ]]; then
    /bin/rm -f /ccp/dev/cycloplan_idle
  fi
  if [ -h /ccp/dev/cycloplan_work ]; then
    /bin/rm -f /ccp/dev/cycloplan_work
  fi
fi

# SYNC_ME: Search: Apache maintenance conf.

case $1 in
  maint)
    echo 'enabling maintenance mode'
    #
    sudo a2ensite maintenance
    #
    sudo a2dissite cycloplan.live
    sudo a2dissite cycloplan_sib1_live
    sudo a2dissite cycloplan_sib2_live
    ;;
  sib2)
    echo 'changing to cycloplan_sib2'
    #
    ln -s /ccp/dev/cycloplan_sib2 /ccp/dev/cycloplan_live
    ln -s /ccp/dev/cycloplan_sib1 /ccp/dev/cycloplan_idle
    sudo update-rc.d -f cyclopath-routed remove
    sudo update-rc.d cyclopath-routed-sib1 disable
    sudo update-rc.d cyclopath-routed-sib2 enable
    #
    sudo a2dissite maintenance
    #
    sudo a2dissite cycloplan.live
    sudo a2dissite cycloplan_sib1_test
    sudo a2dissite cycloplan_sib1_live
    sudo a2dissite cycloplan_sib2_test
    #sudo a2dissite cycloplan_sib2_live
    #sudo a2dissite cycloplan.test
    sudo a2dissite cycloplan.work
    #
    sudo a2ensite cycloplan_sib2_live
    #sudo a2ensite cycloplan.live
    ##sudo a2ensite cycloplan_sib1_test
    # Skipping: cycloplan_work (only temporarily used during upgrade)
    ;;
  sib1)
    echo 'changing to cycloplan_sib1'
    #
    ln -s /ccp/dev/cycloplan_sib1 /ccp/dev/cycloplan_live
    ln -s /ccp/dev/cycloplan_sib2 /ccp/dev/cycloplan_idle
    sudo update-rc.d -f cyclopath-routed remove
    sudo update-rc.d cyclopath-routed-sib1 enable
    sudo update-rc.d cyclopath-routed-sib2 disable
    #
    sudo a2dissite maintenance
    #
    sudo a2dissite cycloplan.live
    sudo a2dissite cycloplan_sib1_test
    #sudo a2dissite cycloplan_sib1_live
    sudo a2dissite cycloplan_sib2_test
    sudo a2dissite cycloplan_sib2_live
    #sudo a2dissite cycloplan.test
    sudo a2dissite cycloplan.work
    #
    sudo a2ensite cycloplan_sib1_live
    #sudo a2ensite cycloplan.live
    ##sudo a2ensite cycloplan_sib2_test
    # Skipping: cycloplan_work (only temporarily used during upgrade)
    ;;
  *)
    echo 'huh? say maint or sib1 or sib2'
    exit 1
    ;;
esac

# NOTE: A reload is the same as a graceful restart: don't close any
#       active sessions.
#         sudo /etc/init.d/apache2 reload
#       is the equivalent of
#         sudo /usr/sbin/apache2ctl -k graceful
#       Bad: sudo /etc/init.d/apache2 restart
sudo /etc/init.d/apache2 reload

