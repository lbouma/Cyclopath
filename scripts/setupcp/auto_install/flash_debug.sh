#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: ./flash_debug.sh
#  (also called from ccp_install.sh)

# NOTE: This script calls sudo a few times, so you gotta be staff with lab-wide
# sudo to run this script.

# Exit on error.
set -e

script_relbase=$(dirname $0)

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its 
#          variables become ours.
. $script_relbase/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,

#            reload_databases, PYTHONVERS2, and httpd_user.

# *** This script only works on x64.

if [[ "x86_64" != "`uname -m`" ]]; then
  echo
  echo "Warning: Flash debug plugin setup is for 64-bit machines only"
  echo "Skipping Flash debug plugin setup. Please fix it yourself!"
  # This doesn't have to be an error but I want the developer to not miss this.
  exit 1
fi

# *** Install Firefox

echo
echo "Preparing Firefox"

# FIXME/MAYBE: Do we still need to install our own version of Firefox?
if false; then
  cd /ccp/opt/.downloads
  if ! [[ -e /ccp/opt/.downloads/firefox-11.0.tar.bz2 ]]; then
    /bin/rm -rf /ccp/opt/.downloads/firefox-11.0.tar.bz2
    wget -Ofirefox-11.0.tar.bz2 \
     'http://download.mozilla.org/?product=firefox-11.0&os=linux&lang=en-US'
  fi
  /bin/rm -rf /ccp/opt/.downloads/firefox-11.0
  tar xvf firefox-11.0.tar.bz2
  mv firefox firefox-11.0
fi

# NOTE: You'll want to make a Gnome launcher and/or shell shortcut to run this 
# version of firefox.

# *** Install Flash debug plugin

echo
echo "Preparing Flash debug plugin"

# *** 

# 2012.06.21: The Adobe plugin we've been using is no longer accessible at its
# old location. Also, the structure of the archive is changed in the new
# version. So this code is obsolete:
# 
#  cd /ccp/opt/.downloads
#  wget -N http://download.macromedia.com/pub/flashplayer/updaters/10/flash_player_10_linux_dev.tar.gz
#  /bin/rm -rf /ccp/opt/.downloads/flash_player_10_linux_dev
#  tar xvf flash_player_10_linux_dev.tar.gz \
#    > /dev/null
#  # Unwrap archives within the archive.
#  cd /ccp/opt/.downloads/flash_player_10_linux_dev
#  cd plugin/debugger
#  tar xvf install_flash_player_10_linux.tar.gz
##  
#  cd /ccp/opt/.downloads/flash_player_10_linux_dev
#  cd standalone/debugger
#  tar xvf flashplayer.tar.gz

cd /ccp/opt/.downloads

# Delete the old-named folder, if it even exists.
/bin/rm -rf /ccp/opt/.downloads/flash_player_10_linux_dev
/bin/rm -rf /ccp/opt/.downloads/flashplayer_debug_plugin
# Make a new folder for unpacking the archives -- the new Adobe archives unpack
# to the current working directory.
/bin/rm -rf /ccp/opt/.downloads/flashplayer_debug_plugin
mkdir flashplayer_debug_plugin
# Change to the new folder, since the archives don't make their own when
# unpacked.
cd flashplayer_debug_plugin

# I think they just changed the filename; see
# https://www.adobe.com/support/flashplayer/downloads.html

if false; then

  wget -N http://download.macromedia.com/pub/flashplayer/updaters/10/flashplayer_10_plugin_debug.tar.gz
  wget -N http://download.macromedia.com/pub/flashplayer/updaters/10/flashplayer_10_sa_debug.tar.gz
  wget -N http://download.macromedia.com/pub/flashplayer/updaters/10/flashplayer_10_sa.tar.gz

  # FIXME: Test 11.2 
  #wget -N http://fpdownload.macromedia.com/pub/flashplayer/updaters/11/flashplayer_11_plugin_debug.i386.tar.gz
  #wget -N http://fpdownload.macromedia.com/pub/flashplayer/updaters/11/flashplayer_11_sa_debug.i386.tar.gz
  #wget -N http://fpdownload.macromedia.com/pub/flashplayer/updaters/11/flashplayer_11_sa.i386.tar.gz

  tar xvf flashplayer_10_plugin_debug.tar.gz \
    > /dev/null
  tar xvf flashplayer_10_sa_debug.tar.gz \
    > /dev/null
  tar xvf flashplayer_10_sa.tar.gz \
    > /dev/null

  flash_lib_dir="???"
  
elif false; then

  wget -N http://fpdownload.macromedia.com/get/flashplayer/installers/archive/fp10.1_debug_archive.zip

  unzip fp10.1_debug_archive.zip

  cd fp10.1_debug_archive/10_1r82_76

  tar xvf flashplayer_10_1r82_76_linux_debug.tar.gz \
    > /dev/null
  tar xvf flashplayer_10_1r82_76_linux_sa_debug.tar.gz \
    > /dev/null

  flash_lib_dir="/ccp/opt/.downloads/flashplayer_debug_plugin/fp10.1_debug_archive/10_1r82_76"

else

  wget -N http://fpdownload.macromedia.com/pub/flashplayer/updaters/11/flashplayer_11_plugin_debug.i386.tar.gz

  tar xvf flashplayer_11_plugin_debug.i386.tar.gz \
    > /dev/null

  flash_lib_dir="/ccp/opt/.downloads/flashplayer_debug_plugin"

fi

# NOTE: Flash is a 32-bit library. If you try to install it on x64, e.g.,
#
#   ./flashplayer-installer
#
# you'll get nasty complaints,
#
#   ERROR: Your architecture, \'x86_64\', is not supported by the Adobe Flash 
#          Player installer.
# 
# Fortunately, we can use the nspluginwrapper to install it.

# NOTE: The release build of flashplugin might already be installed. We can
# leave it installed, but we need to whack its library and its link.
#
# $ aptitude search flash
# i A flashplugin-installer - Adobe Flash Player plugin installer
# i   flashplugin-nonfree   - Adobe Flash Player plugin installer (transitional
#
# NOTE: I'm not sure this is necessary, but it can't hurt to disable the
# existing plugin.
#if ! [[ -e /usr/lib/flashplugin-installer/libflashplayer.so.ORIG ]]; then
if [[ -e /usr/lib/flashplugin-installer/libflashplayer.so ]]; then
  sudo mv /usr/lib/flashplugin-installer/libflashplayer.so \
    /usr/lib/flashplugin-installer/libflashplayer.so.ORIG
fi

# EXPLAIN: What about this location?:
#
#  /opt/mint-flashplugin-11/

# Copy the debug library to the mozilla plugins folder.

if [[ -d /usr/lib64/mozilla/plugins ]]; then
  moz_plugs_dir="/usr/lib64/mozilla/plugins"
elif [[ -d /usr/lib/mozilla/plugins ]]; then
  moz_plugs_dir="/usr/lib/mozilla/plugins"
else
  echo
  echo "ERROR: Where is the mozilla plugins directory?"
  exit 1
fi

# Whack the flashplugin link, lest Firefox load that instead.
#  Ubuntu 11ish:
#   flashplugin-alternative.so -> /etc/alternatives/mozilla-flashplugin*
#   sudo /bin/rm -f /usr/lib/mozilla/plugins/flashplugin-alternative.so
sudo /bin/mv -f ${moz_plugs_dir}/libflashplayer.so \
                ${moz_plugs_dir}/libflashplayer.so-MINT
 # which is just a symlink to /etc/alternatives/libflashplayer.so.

if [[ "x86_64" == "`uname -m`" ]]; then

  #sudo cp \
  #  /ccp/opt/.downloads/flash_player_10_linux_dev/plugin/debugger/install_flash_player_10_linux/libflashplayer.so \
  #  ${moz_plugs_dir}
  #sudo cp \
  #  /ccp/opt/.downloads/flashplayer_debug_plugin/libflashplayer.so \
  #  ${moz_plugs_dir}
  mkdir -p /ccp/opt/flashdebugger
  sudo /bin/cp \
    ${flash_lib_dir}/libflashplayer.so \
    ${moz_plugs_dir}
    #/ccp/opt/flashdebugger
  #chmod 664 /ccp/opt/flashdebugger/libflashplayer.so
  sudo chmod 775 ${moz_plugs_dir}/libflashplayer.so
  #sudo chmod 775 /ccp/opt/flashdebugger/libflashplayer.so

  # Create a 64-bit wrapper for the 32-bit library.
  if [[ -d /usr/lib64/nspluginwrapper/x86_64/linux ]]; then
    npconfig_dir=/usr/lib64/nspluginwrapper/x86_64/linux
  elif [[ -d /usr/lib64/nspluginwrapper ]]; then
    npconfig_dir=/usr/lib64/nspluginwrapper
  elif [[ -d /usr/lib/nspluginwrapper/x86_64/linux/ ]]; then
    # 2014.01.17: Is this right? Mint 16 doesn't have lib64...
    #  did they invert the standard, so that 64-bit is now
    #  the norm (think the very cryptic and/or misleading
    #  name: C:\Windows\SysWOW32).
    npconfig_dir=/usr/lib/nspluginwrapper/x86_64/linux/
  else
    echo "Where is nspluginwrapper?"
    exit 1
  fi

  # 2014.01.17:
  # $   sudo ./npconfig -i ${moz_plugs_dir}/libflashplayer.so
  # nspluginwrapper: no appropriate viewer found for
  #   /usr/lib/mozilla/plugins/libflashplayer.so
  # $ ll /usr/lib/mozilla/plugins/libflashplayer.so
  # -rwxrwxr-x 1 root root 13M Jan 17 06:12
  #   /usr/lib/mozilla/plugins/libflashplayer.so*
  # $ nspluginwrapper -v -i /usr/lib/mozilla/plugins/libflashplayer.so
  # *** NSPlugin Viewer  *** ERROR: libssl3.so:
  #   cannot open shared object file: No such file or directory
  # *** NSPlugin Viewer  *** ERROR: libssl3.so:
  #   cannot open shared object file: No such file or directory
  # nspluginwrapper: no appropriate viewer found for
  #   /usr/lib/mozilla/plugins/libflashplayer.so
  #
  # Mint 16. Weird.
  # $ sudo ./npconfig -i ${moz_plugs_dir}/libflashplayer.so
  # nspluginwrapper: no appropriate viewer found for
  #  /usr/lib/mozilla/plugins/libflashplayer.so
  #sudo ln -s /usr/lib/nspluginwrapper/noarch/npviewer.sh \
  #  /usr/bin/npviewer
  #
  # Oh, okay, we need the 32-bit shim package:
  #  sudo apt-get install ia32-libs
  # In Ubuntu, this package is now ia32-libs-multiarch, maybe.
  cd $npconfig_dir
  #sudo ./npconfig -v -i /ccp/opt/flashdebugger/libflashplayer.so

  # NOTE: You'll see an error, but you can ignore it.
  #     Install plugin /usr/lib/mozilla/plugins/libflashplayer.so
  #       into /usr/lib/nspluginwrapper/plugins/npwrapper.libflashplayer.so
  #     And create symlink to plugin in /usr/lib/mozilla/plugins: failed!
  sudo ./npconfig -v -i ${moz_plugs_dir}/libflashplayer.so

  #cd $moz_plugs_dir
  #sudo $npconfig_dir/npconfig -v -i ./libflashplayer.so

  # Fix the permissions on the new wrapper.
  if [[ -d /usr/lib/nspluginwrapper/plugins ]]; then

    sudo chmod 775 /usr/lib/nspluginwrapper/plugins/npwrapper.libflashplayer.so

  elif [[ -d /usr/lib64/mozilla/plugins ]]; then

    sudo chmod 775 /usr/lib64/mozilla/plugins/npwrapper.libflashplayer.so

  elif [[ -d /usr/lib/mozilla/plugins ]]; then

    sudo chmod 775 /usr/lib/mozilla/plugins/npwrapper.libflashplayer.so

  else
    echo "Where is the shim plugin?"
    exit 1
  fi

  sudo /bin/mkdir -p /usr/lib/nspluginwrapper/plugins
  sudo chmod 2775 /usr/lib/nspluginwrapper/plugins

  # FIXME: I'm just guessing here. I really don't know where flashplayer belongs.
  # I'm assuming it belongs alongside the library.
  #sudo cp \
  #  /ccp/opt/.downloads/flashplayer_debug_plugin/standalone/debugger/flashplayer \
  #  /usr/lib/nspluginwrapper/plugins
  sudo /bin/rm -f /usr/lib/nspluginwrapper/plugins/flashplayer
  #sudo cp \
  #  /ccp/opt/.downloads/flashplayer_debug_plugin/flashplayerdebugger \
  #  /usr/lib/nspluginwrapper/plugins

  #sudo /bin/cp \
  #  ${flash_lib_dir}/flashplayerdebugger \
  #  /usr/lib/nspluginwrapper/plugins
  #
  ##sudo chmod 775 /usr/lib/nspluginwrapper/plugins/flashplayer
  #sudo chmod 775 /usr/lib/nspluginwrapper/plugins/flashplayerdebugger

else 

  # 32-bit Linux.

  sudo cp \
    /ccp/opt/.downloads/flashplayer_debug_plugin/libflashplayer.so \
    /usr/lib/mozilla/plugins

  sudo chmod 775 /usr/lib/mozilla/plugins/libflashplayer.so

fi

# Install the macromedia config file.

# For tilde expansion to work, we have to use eval. Otherwise the tilde is just
# part of the string and not resolved to the user's home directory.
echo -n "Setting up mm.cfg... "
eval targethome=~$targetuser
if ! [[ -e $targethome/mm.cfg ]]; then
  # NOTE: I [lb] can write to some users' home directories (like masli's) but
  # not to others' (like mludwig's).
  set +e
  sudo cp \
    ${script_relbase}/../ao_templates/common/home/user/mm.cfg \
    $targethome
  if [[ $? -eq 0 ]]; then
    sudo chmod 664 $targethome/mm.cfg
    sudo chown $targetuser $targethome/mm.cfg
    sudo chgrp $targetgroup $targethome/mm.cfg
    echo "copied ok."
  else
    echo "denied!"
    echo
    # MAYBE: Shouldn't this be: schklim/schklerself?
    echo "WARNING: Cannot copy mm.cfg. Tell $targetuser to do it him/herself."
    echo
  fi
else
  echo "already setup."
fi

# Cleanup.

/bin/rm -rf /ccp/opt/.downloads/flashplayer_debug_plugin

# To test:
#
# Run firefox, then open the location
#
#   about:plugins
#
# and look for
#
#   Shockwave Flash
#   
#       File: libflashplayer.so
#       Version: 
#       Shockwave Flash 10.1 r53

# *** Restore our spot

cd $script_path

# *** All done!

echo
echo "Flash debug plugin installed"
echo 
echo "To run firefox: /usr/bin/firefox &"

exit 0

# FIXME: Delete this if not needed:
# sudo cp \
#   /ccp/opt/.downloads/flashplayer_debug_plugin/standalone/debugger/flashplayer \
#   /usr/lib64/mozilla/plugins
# sudo chmod 775 /usr/lib64/mozilla/plugins/flashplayer

# cd /usr/lib64/nspluginwrapper/x86_64/linux/
# sudo ./npconfig -i /usr/lib/mozilla/plugins/libflashplayer.so

