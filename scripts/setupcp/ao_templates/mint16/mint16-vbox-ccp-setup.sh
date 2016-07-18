#!/bin/bash

echo
echo "Mint 16 Setup Script"
echo
echo "- Installs Dubsacks Vim and Bash"
echo "- Installs Cyclopath Development Environment"
echo "- Configures Cinnamon to a Particular Liking"
echo

script_relbase=$(dirname $0)
script_absbase=`pwd $script_relbase`

# *** DEVs: Configure these values for your environment.
#

# New O.S. User:Password@Machine ==> cyclopath:cyclopath@cyclodev
USE_MOUNTPT="C_DRIVE"
#
#USE_DOMAIN="$MACHINE_DOMAIN"
# This is a dummy domain.
USE_DOMAIN="cyclopath.edu" # Schooled you!
#
USE_SVN_URI="svn://cycloplan.cyclopath.org/cyclingproject/public/ccpv3_trunk"
# FIXME: Implement Git.
USE_GIT_URI="FIXME"
#
USE_CCPDFILES="/home/$USER/cyclopath-installer"
USE_HOMEFILES="$USE_CCPDFILES/scripts/setupcp/ao_templates/common/home/user"
USE_TIMEZONE="America\/Menominee"
#
# Name the Wiki with the first char of the username, e.g., for cyclopath, [c].
#USE_WIKINAME="[${USER:0:1}]"
# Or name the Wiki with the first and last char of the username.
#  Note the space after the colon and before the -1; otherwhise,
#  "defaults to full string, as in ${parameter:-default}."
#   http://tldp.org/LDP/abs/html/string-manipulation.html
# Or name the Wiki whatever you like...
#USE_WIKINAME="[${USER:0:1}${USER: -1}]"
USE_WIKINAME="[cp]"
USE_PSQLWIKIPWD=$($USE_CCPDFILES/scripts/util/random_password.py 13)
USE_WIKIUSERNAME="Cyclopath"
#USE_WIKIUSERPASS=$($USE_CCPDFILES/scripts/util/random_password.py 13)
USE_WIKIUSERPASS='Cyclopath'
USE_WIKISITELOGO="$USE_CCPDFILES/scripts/setupcp/ao_templates/common/other/wiki_logo-cyclopath.png"
#
USE_GREETER_THEME="$USE_CCPDFILES/scripts/setupcp/ao_templates/mint16/target/usr/share/mdm/html-themes/Retrosoft"
USE_RESOURCES_URI=""
USE_RESOURCES_USER=""
USE_RESOURCES_PASS=""
USE_DESKTOP_IMAGE=""
USE_GREETER_IMAGE=""
USE_MINT_MENU_ICON="$USE_CCPDFILES/scripts/setupcp/ao_templates/common/other/applications-boardgames-21x21.png"
#
USE_WIKIDB_DUMP=""
# NOTE: We shouldn't publish a db for community developers, i.e., the
#       scrub_db "lite" database is not appropriate except for U devs
#       on laptops, because there's still route origin-destination pairs,
#       but not any personal user data. Kinda of a quasi middle ground?
#       Anyway, hello, FIXME, we need to lead by example: import a Shapefile.
USE_DATABASE_SCP=""
#
# This script is meant to run on an offsite install,
# so rather than using the group name we use in the
# lab ("grplens"), we use something more Cyclopathy.
USE_CYCLOP_GROUP="cyclop"
#
# We cannot distribute Adobe Reader on a virtual machine image, so we don't
# include it by default.
# If you're running this script yourself, you can change this to true, but
# then you're bound by the EULA not to distribute the virtual machine image.
INCLUDE_ADOBE_READER=false
#
EXCLUDE_CYCLOPATH=false

# *** DEVs: Copy-paste the following to your terminal if testing
#           parts of this script.

if false; then
  # NOTE: These were copied from below and may be out of date/may have drifted!
  #USE_CCPDFILES="/home/$USER/cyclopath-installer"
  USE_CCPDFILES="/ccp/dev/cp"
  MINT_FILES=$USE_CCPDFILES/scripts/setupcp/ao_templates/mint16/target
  AUTO_INSTALL=$USE_CCPDFILES/scripts/setupcp/auto_install
  COMMON_FILES=$USE_CCPDFILES/scripts/setupcp/ao_templates/common
  #mwiki_basename="mediawiki-1.22.0"
  #mwiki_basename="mediawiki-1.22.5"
  mwiki_basename="mediawiki-1.23.6"
  mwiki_basepath=/ccp/var/cms/${mwiki_basename}
  #mwiki_wgetpath="http://download.wikimedia.org/mediawiki/1.22/${mwiki_basename}.tar.gz"
  mwiki_wgetpath="http://download.wikimedia.org/mediawiki/1.23/${mwiki_basename}.tar.gz"
  bzilla_basename="bugzilla-4.4.4"
  bzilla_basepath=/ccp/var/cms/${bzilla_basename}
  source ${USE_CCPDFILES}/scripts/util/bash_base.sh
fi

# *** Let's get started!

# Start a timer.
ccp_time_0=$(date +%s.%N)

# Enable or disable errexit.
#
# FIXME: Run with set -e?
#        Or should we always check return statii?
#
# NOTE: From the shell, you can determine the current e, or errexit,
#       setting with the command:
#
#        $ set -o | grep errexit | /bin/sed -r 's/^errexit\s+//'
#
#       which returns on or off.
#
#       However, from within this script, whether we set -e or set +e,
#       the set -o always returns the value from our terminal -- from
#       when we started the script -- and doesn't reflect any changes
#       herein. So use a variable to remember the setting.
#
USING_ERREXIT=true
reset_errexit () {
  if $USING_ERREXIT; then
    #set -ex
    set -e
  else
    set +ex
  fi
}
reset_errexit

# Determine Python version.
PYVERS_RAW=`python3 --version \
	|& /usr/bin/awk '{print $2}' \
	| /bin/sed -r 's/^([0-9]+\.[0-9]+)\.[0-9]+/\1/g'`
if [[ -z $PYVERS_RAW ]]; then
	echo "Unexpected: Could not parse Python version."
	exit 1
fi

# *** Helper fcns.

# NOTE: VirtualBox does not supply a graphics driver for Cinnamon 2.0, 
#       which runs DRI2 (Direct Rendering Interface2). But Xfce runs
#       DRI1, which VirtualBox supports.
determine_window_manager () {
  WM_IS_CINNAMON=false
  WM_IS_XFCE=false
  WM_IS_MATE=false # Pronouced, mah-tay!
  WM_IS_UNKNOWN=false
  if [[ `wmctrl -m | grep -e "^Name: Mutter (Muffin)$"` ]]; then
    WM_IS_CINNAMON=true
  elif [[ `wmctrl -m | grep -e "^Name: Xfwm4$"` ]]; then
    WM_IS_XFCE=true
  elif [[ `wmctrl -m | grep -e "^Name: Marco$"` ]]; then
    WM_IS_MATE=true
  else
    WM_IS_UNKNOWN=true
    echo
    echo "ERROR: Unknown Window manager."
    exit 1
  fi
  echo "WM_IS_CINNAMON: $WM_IS_CINNAMON"
  echo "WM_IS_XFCE: $WM_IS_XFCE"
  echo "WM_IS_MATE: $WM_IS_MATE"
  echo "WM_IS_UNKNOWN: $WM_IS_UNKNOWN"
}

# This script runs multiple times and reports its running time each time.
print_install_time () {
  ccp_time_n=$(date +%s.%N)
  echo "Install started at: $ccp_time_0"
  echo "Install finishd at: $ccp_time_n"
  ccp_elapsed=$(echo "$ccp_time_n - $ccp_time_0" | bc -l)
  echo "Elapsed: $ccp_elapsed secs."
  echo
}

# If you'd like to automate future installs, you can compare
# your home directory before and after setting up the window
# manager and applications just the way you like.
#
# To test:
#   cd ~/Downloads
#   RELAT=new_01
#   user_home_conf_dump $RELAT
#
# DEVs: Uncomment the latter if you'd like to make conf dumps.
MAKE_CONF_DUMPS=false
#MAKE_CONF_DUMPS=true
#
user_home_conf_dump() {

  RELAT=$1

  # One method:
  # pushd /home/$USER/
  # tar cvzf $RELAT-home_conf.tar.gz .config .gconf .linuxmint .local .mozilla
  # popd
  # /bin/mv /home/$USER/$RELAT-home_conf.tar.gz .

  # Another method:
  # tar \
  #   -cvz \
  #   --file $RELAT-home_conf.tar.gz \
  #   --directory /home \
  #   \
  #   $USER/.config \
  #   $USER/.gconf \
  #   $USER/.linuxmint \
  #   $USER/.local \
  #   $USER/.mozilla

  mkdir $RELAT

  pushd $RELAT

  gsettings list-recursively > cmd-gsettings.txt

  gconftool-2 --dump / > cmd-gconftool-2.txt

  dconf dump / > cmd-dconf.txt

  /bin/cp -raf \
    /home/$USER/.config \
    /home/$USER/.gconf \
    /home/$USER/.gnome2 \
    /home/$USER/.gnome2_private \
    /home/$USER/.linuxmint \
    /home/$USER/.local \
    /home/$USER/.mozilla \
    .

  popd

  tar cvzf $RELAT-user_home_conf_dump.tar.gz $RELAT

}

# Ask a yes/no question and take just one key press as answer
# (not waiting for user to press Enter), and complain if answer
# is not y or n.
ask_yes_no_default () {

  # Don't exit on error, since `read` returns $? != 0 on timeout.
  set +e
  # Also -x prints commands that are run, which taints the output.
  set +x

  if [[ $1 != 'Y' && $1 != 'N' ]]; then
    echo "Developer: Please specify 'Y' or 'N' for ask_yes_no_default."
    exit 1
  fi

  if [[ $1 == 'Y' ]]; then
    choices='[Y]/n'
  else
    choices='y/[N]'
  fi

  if [[ -z $2 ]]; then
    # Default timeout: 15 seconds.
    timeo=15
  else
    timeo=$2
  fi

  # https://stackoverflow.com/questions/2388090/
  #   how-to-delete-and-replace-last-line-in-the-terminal-using-bash
  # $ seq 1 1000000 | while read i; do echo -en "\r$i"; done

  valid_answers="nNyY"

  unset the_choice
  # Note: The while-pipe trick causes `read` to return immediately with junk.
  # Nope: seq 1 5 | while read i; do
  not_done=true
  while $not_done; do
    not_done=false
    for elaps in `seq 0 $((timeo - 1))`; do 
      echo -en \
        "[Default in $((timeo - elaps)) seconds...] Please answer $choices "
      read -n 1 -t 1 the_choice
      if [[ $? -eq 0 ]]; then
        # Thanks for the hint, stoverflove.
        # https://stackoverflow.com/questions/8063228/
        #   how-do-i-check-if-a-variable-exists-in-a-list-in-bash
        if [[ $valid_answers =~ $the_choice ]]; then
          # The user answered the call correctly.
          echo
          break
        else
          echo
          #echo "Please try answering with a Y/y/N/n answer!"
          echo "That's not the answer I was hoping for..."
          echo "Let's try this again, shall we?"
          sleep 1
          not_done=true
          break
        fi
      fi
      if [[ $elaps -lt $((timeo - 1)) ]]; then
        # Return to the start of the line.
        echo -en "\r"
      fi
    done
  done

  if [[ -z $the_choice ]]; then
    the_choice=$1
    echo $1'!'
  fi

  if [[ $the_choice == "n" ]]; then
    the_choice="N"
  elif [[ $the_choice == "y" ]]; then
    the_choice="Y"
  fi

  reset_errexit
}

# Test:
#  ask_yes_no_default 'Y'
#  echo $the_choice

# *** EVERY BOOT: Always get a fresh sudo, so we don't ask for the password
#                 at some random time during the install.

# E.g.,
#   $ sudo -n -v
#   sudo: a password is required
if ! `sudo -n -v`; then
  echo
  echo "Please enter your root password to get started..."
  echo
  sudo -v
fi

# *** FIRST/FRESH BOOT: Upgrade and Install Packages

# See if dkms is installed, if not, assume this is a fresh Mint 16
# installation. We'll update/upgrade the system and install all the
# packages we think we'll need to setup our environment.

set +ex
dpkg -s build-essential &> /dev/null
if [[ $? -ne 0 ]]; then

  reset_errexit

  echo 
  echo "It looks like you've just installed Mint 16."
  echo
  echo "We're going to install lots of packages and then reboot."
  echo
  echo "NOTE: The Mysql installer will ask you for a new password."
  echo
  echo "Let's get moving, shall we?"
  ask_yes_no_default 'Y'

  if [[ $the_choice != "Y" ]]; then

    echo "Awesome! See ya!!"
    exit 1

  else

    # *** Make a snapshot of the user's home directory.

    #sudo apt-get install dconf-tools
    sudo apt-get install dconf-cli
    if $MAKE_CONF_DUMPS; then
      cd ~/Downloads
      user_home_conf_dump "new_01"
    fi

    # *** Install wmctrl so we can determine the window manager.

    sudo apt-get install wmctrl
    determine_window_manager

    # *** Make sudo'ing a little easier (just ask once per terminal).

    # Disable screen locking so the user can move about the cabin freely.

    if $WM_IS_CINNAMON; then
      # Cinnamon:
      set +ex
      gsettings set org.cinnamon.desktop.screensaver lock-enabled false \
        &> /dev/null
      reset_errexit
    fi
    # else, for MATE, see after the apt-get update.

    # Tweak sudoers: Instead of a five-minute sudo timeout, disable it.
    # You'll be asked for a password once per terminal. If you care about
    # sudo not being revoked after a timeout, just close your terminal when
    # you're done with it, Silly.

    if sudo grep "Defaults:$USER" /etc/sudoers 1> /dev/null; then
      echo "UNEXPECTED: /etc/sudoers already edited."
      exit 1
    fi

    sudo /bin/cp /etc/sudoers /etc/sudoers-ORIG

    sudo chmod 0660 /etc/sudoers

    # For more info on the Defaults, see `man sudoers`.
    # - tty_tickets is on by default.
    # - timestamp_timeout defaults to 5 (seconds).
    # Note the sudo tee trick, since you can't run e.g.,
    # sudo echo "" >> to a write-protected file, since
    # the append command happens outside the sudo.
    echo "
# Added by Cyclpath's ccp-mint16-vbox-setup.sh.
Defaults tty_tickets
Defaults:$USER timestamp_timeout=-1
" | sudo tee -a /etc/sudoers &> /dev/null

    sudo chmod 0440 /etc/sudoers
    sudo visudo -c 
    if [[ $? -ne 0 ]]; then
      echo "WARNING: We messed up /etc/sudoers!"
      echo
      echo "To recover: login as root, since sudo is broken,"
      echo "and restore the original file."
      echo
      echo "$ su"
      echo "$ /bin/cp /etc/sudoers-ORIG /etc/sudoers"
      exit 1
    fi

    # *** Upgrade and install packages.

    # Update the cache.
    sudo apt-get update

    # Update all packages.
    sudo apt-get upgrade

    determine_window_manager
    if $WM_IS_MATE; then
      # Disable screensaver and lock-out.
      # gsettings doesn't seem to stick 'til now.
      #?: sudo gsettings set org.mate.screensaver lock-enabled false
      # Or did it just require an apt-get update to finally work?
      gsettings set org.mate.screensaver idle-activation-enabled false
      gsettings set org.mate.screensaver lock-enabled false
    fi

    # Install our packages.

    # NOTE: The Mysql package wants you to enter a password.
    #       (You'd think the package installer wouldn't be
    #       interactive, but I guess there are some exceptions.
    #       Or maybe there's an apt-get switch I'm missing.)
    #       So enter a password. (You could leave it blank, since
    #       we only use Postgres (we need Mysql to compile MediaWiki),
    #       but it's probably better to set a password, just in case
    #       leaving it empty opens up some vulnerability... but hopefully
    #       the installer doesn't setup Mysql to start accepting external
    #       connections by default.)
    # MAYBE: Is there a way to pass a password to the Mysql installer, so
    #        that it doesn't bother us?

    sudo apt-get install \
      \
      dkms \
      build-essential \
      \
      dconf-cli \
      gconf-editor \
      wmctrl \
      xdotool \
      \
      vim-gnome \
      par \
      exuberant-ctags \
      \
      meld \
      \
      dia \
      eog \
      ghex \
      \
      git \
      git-core \
      subversion \
      mercurial \
      \
      wireshark \
      fakeroot \
      \
      apache2 \
      apache2-threaded-dev \
      apache2-mpm-worker \
      apache2-utils \
      \
      mysql-server \
      \
      postgresql \
      postgresql-client \
      postgresql-server-dev-9.1 \
      \
      php5-dev \
      php5-mysql \
      libapache2-mod-php5 \
      dh-make-php \
      \
      libxml2-dev \
      libjpeg-dev \
      libpng++-dev \
      libgd-dev \
      imagemagick \
      libmagick++-dev \
      texlive \
      autoconf \
      vsftpd \
      libcurl3 \
      pcregrep \
      gir1.2-gtop-2.0 \
      libgd-dev \
      libgd2-xpm-dev \
      libxslt1-dev \
      xsltproc \
      libicu48 \
      libicu-dev \
      \
      python-dev \
      python-setuptools \
      libapache2-mod-python \
      python-simplejson \
      python-logilab-astng \
      python-logilab-common \
      python-gtk2 \
      python-wnck \
      python-xlib \
      python-dbus \
      pylint \
      python-egenix-mxdatetime \
      python-egenix-mxtools \
      python-logilab-astng \
      python-logilab-common \
      python-subversion \
      python-levenshtein \
      \
      libagg-dev \
      libedit-dev \
      mime-construct \
      \
      libproj-dev \
      libproj0 \
      proj-bin \
      proj-data \
      \
      libipc-signal-perl \
      libmime-types-perl \
      libproc-waitstat-perl \
      \
      ia32-libs \
      nspluginwrapper \
      \
      logcheck \
      logcheck-database \
      \
      logtail \
      \
      socket \
      \
      libpam0g-dev \
      \
      openssh-server
      \
      gnupg2 \
      signing-party \
      \
      thunderbird \
      \
      whois \
      \
      python-nltk \
      python-matplotlib \
      python-tk \

      # wine \
      # wine-gecko1.4
      # srm, wipe, shred
      # http://www.cyberciti.biz/tips/linux-how-to-delete-file-securely.html
      # shred -n 200 -z -u  personalinfo.tar.gz
      # shred -n 3 --zero --remove  personalinfo.tar.gz

    # Install additional MATE theme, like BlackMATE. We don't change themes,
    # but it's nice to be able to see what the other themes look like.

    if $WM_IS_MATE; then
      sudo apt-get install mate-themes
    fi

    # All done.

    print_install_time

    # *** The user has to reboot before continuing.

    echo
    echo "All done! Are you ready to reboot?"
    ask_yes_no_default 'Y' 20

    if [[ $the_choice != "Y" ]]; then
      echo "Fine, be that way."
    else
      sudo /sbin/shutdown -r now
    fi
    exit

  fi # upgrade all packages and install extras that we need

fi

# *** SECOND and SUBSEQUENT BOOTs

# Now that wmctrl is installed...
determine_window_manager

# *** SECOND BOOT: Install Guest Additions

# NOTE: This doesn't work for checking $? (the 2&> replaces it?)
#        ll /opt/VBoxGuestAdditions* 2&> /dev/null
ls -la /opt/VBoxGuestAdditions* &> /dev/null
if [[ $? -ne 0 ]]; then

  reset_errexit

  echo 
  echo "Great, so this is your second reboot."
  echo
  echo "You've just upgraded and installed packages."
  echo
  echo "Now we're ready to install VirtualBox Guest Additions."
  echo
  echo "NOTE: The installer will bark at you about an existing version"
  echo "      of VBoxGuestAdditions software. Type 'yes' to continue."
  echo
  echo "I sure hope you're ready"'!'
  ask_yes_no_default 'Y'


  if $WM_IS_CINNAMON || $WM_IS_MATE; then
    not_done=true
    while $not_done; do
      if [[ `ls /media/$USER | grep VBOXADDITIONS` ]]; then
        not_done=false
      else
        echo
        echo "PLEASE: From the VirtualBox menu bar, choose"
        echo "         Devices > Insert Guest Additions CD Image..."
        echo "        and hit Enter when you're ready."
        echo
        read -n 1 __ignored__
      fi
    done
    if [[ $the_choice != "Y" ]]; then
      echo "Nice! Catch ya later!!"
      exit 1
    fi
    cd /media/$USER/VBOXADDITIONS_*/
  elif $WM_IS_XFCE; then
    sudo mkdir /media/VBOXADDITIONS
    sudo mount -r /dev/cdrom /media/VBOXADDITIONS
    cd /media/VBOXADDITIONS
  fi

  # You'll see a warning and have to type 'yes': "You appear to have a
  # version of the VBoxGuestAdditions software on your system which was
  # installed from a different source or using a different type of
  # installer." Type 'yes' to continue.

  set +ex
  sudo sh ./VBoxLinuxAdditions.run
  echo "Run return code: $?"
  reset_errexit

  print_install_time

  echo
  echo "All done! Are you ready to reboot?"
  echo "Hint: Shutdown instead if you want to remove the Guest Additions image"
  ask_yes_no_default 'Y' 20

  if [[ $the_choice != "Y" ]]; then
    echo "Ohhhh... kay."
  else
    sudo /sbin/shutdown -r now
  fi
  exit

fi

reset_errexit

# *** THIRD BOOT: Setup Bash and Home Scripts and User Groups

if [[ ! -e ~/.bashrc ]]; then

  # Check that the DEV edited the start of this script and set
  # all the values we need to continue.
# MAYBE: Not all of these options are actually necessary.
#        If some of these aren't set, you can still install
#        (e.g., if you don't specify the greeter theme, it
#        won't be changed).
  if [[    -z $USE_MOUNTPT \
        || -z $USE_DOMAIN \
        || -z $USE_CCPDFILES \
        || -z $USE_HOMEFILES \
        || -z $USE_TIMEZONE \
        || -z $USE_WIKINAME \
        || -z $USE_PSQLWIKIPWD \
        || -z $USE_WIKIUSERNAME \
        || -z $USE_WIKIUSERPASS \
        || -z $USE_WIKISITELOGO \
        || -z $USE_GREETER_THEME \
        || -z $USE_MINT_MENU_ICON \
        ]]; then
    echo
    echo "ERROR: Please set all of the variables at the start of this script."
    exit 1
  fi

  echo
  echo "Wow, after three reboots, you've come back for more"'!'
  echo
  echo "Now we're ready to setup some groups and install Bash scripts."
  echo
  echo "NOTE: If we mess up your Bash scripts, it could break your"
  echo "account so that you cannot logon. So after this script runs,"
  echo "be sure to open a new terminal window to test that everything"
  echo "works before logging off."
  echo
  echo "Now, are you ready to let 'er rip?"
  ask_yes_no_default 'Y'

  if [[ $the_choice != "Y" ]]; then

    echo "Great! Peace, ya'll"'!!'
    exit 1

  else

    # Setup user groups.
    sudo groupadd $USE_CYCLOP_GROUP
    sudo usermod -a -G $USE_CYCLOP_GROUP $USER
    # Let the user access the auto-mounted VBox drives.
    sudo usermod -aG vboxsf $USER

    # So that postgres can write to /ccp/var/log/postgresql
    sudo usermod -a -G $USE_CYCLOP_GROUP postgres
    # So that www-data can write to /ccp/var/log/apache2
    sudo usermod -a -G $USE_CYCLOP_GROUP www-data

    # So that Wireshark can be run unprivileged.
    # References:
    #  http://ask.wireshark.org/questions/7523/ubuntu-machine-no-interfaces-listedn
    #  http://wiki.wireshark.org/CaptureSetup/CapturePrivileges
    # Add the wireshark group and tell dumpcap to run privileged.
    sudo dpkg-reconfigure wireshark-common
    # Add the user to the new group.
    sudo usermod -a -G wireshark $USER
    # You need to logout or reboot to see changes.

    # Try to mount the host drive. We do this now because
    # the user has to reboot before their new access to
    # the vboxsf group is realized.
    if [[ -n $USE_MOUNTPT ]]; then
      sudo /bin/mkdir -p /win
      sudo chmod 2775 /win
      sudo mount -t vboxsf $USE_MOUNTPT /win
      if [[ $? -ne 0 ]]; then
        echo "WARNING: Could not mount host drive using the command:"
        echo "         sudo mount -t vboxsf $USE_MOUNTPT /win"
        exit 1
      fi
    fi

    # Grab the Cyclopath source.

    skip_bashrc_m4=true
    if [[ -n $USE_SVN_URI || -n $USE_GIT_URI ]]; then
      skip_bashrc_m4=false
      if [[ -e $USE_CCPDFILES ]]; then
        echo
        echo "NOTICE: The ccp checkout folder already exists: $USE_CCPDFILES"
        echo
      elif [[ -n $USE_SVN_URI ]]; then
        # E.g., svn co \
        #   svn://cycloplan.cyclopath.org/cyclingproject/public/ccpv3_trunk \
        #   ccpv3_trunk
        svn co $USE_SVN_URI $USE_CCPDFILES
      elif [[ -n $USE_GIT_URI ]]; then
        git clone $USE_GIT_URI $USE_CCPDFILES
      else
        echo
        echo "ERROR: Where can I download Cyclopath source?"
        exit 1
      fi
      # else, we expect that the human installed files to $USE_CCPDFILES.
    fi

    # Try to copy home directory scripts and config.
    # Test:
    #  USE_HOMEFILES="/home/$USER/.dubs/.install/home"
    if [[ -n $USE_HOMEFILES ]]; then

      if [[ ! -e $USE_HOMEFILES ]]; then
        echo "WARNING: Could not find directory: $USE_HOMEFILES"
        exit 1
      fi

      # Try to copy Bash scripts.
      if [[ ! -e $USE_HOMEFILES/.bashrc ]]; then
        echo "WARNING: No Bash scripts?: $USE_HOMEFILES/.bashrc"
        exit 1
      fi
      # Copy bash scripts.
      /bin/cp $USE_HOMEFILES/.bashrc* /home/$USER/
      # Fix the private scripts, if this is a generic install.
      if ! $skip_bashrc_m4; then
        mv \
          /home/$USER/.bashrc_private.hostname \
          /home/$USER/.bashrc_private.$HOSTNAME
        # Skipping: .bashrc_private, which the user should edit manually.
      fi
      # The new bash command, rm_safe, sends files to ~/.trash.
      /bin/mkdir /home/$USER/.trash

      # Try to copy Vim scripts.
      if [[ ! -e $USE_HOMEFILES/.vimrc ]]; then
        echo "WARNING: No Vim scripts?: $USE_HOMEFILES/.vimrc"
        exit 1
      fi
      # Copy Vim scripts.
      /bin/cp -r \
        $USE_HOMEFILES/.vim \
        $USE_HOMEFILES/.vimprojects \
        $USE_HOMEFILES/.vimrc \
          /home/$USER/

      # Grab whatever else is lying around.
      /bin/cp -f $USE_HOMEFILES/.ctags        /home/$USER/ &> /dev/null
      # NOTE: For anonymous installs, it's up to the user to make .forward.
      #       But if you're copying your home value, this might exist.
      /bin/cp -f $USE_HOMEFILES/.forward      /home/$USER/ &> /dev/null
      /bin/cp -f $USE_HOMEFILES/.gitconfig    /home/$USER/ &> /dev/null
      /bin/cp -f $USE_HOMEFILES/.psqlrc       /home/$USER/ &> /dev/null
      /bin/cp -f $USE_HOMEFILES/.xmodmap*     /home/$USER/ &> /dev/null
      /bin/cp -f $USE_HOMEFILES/mm.cfg        /home/$USER/ &> /dev/null
      /bin/cp -f $USE_HOMEFILES/synergy.conf  /home/$USER/ &> /dev/null
      /bin/cp -rf $USE_HOMEFILES/.ssh         /home/$USER/ &> /dev/null
      /bin/cp -rf $USE_HOMEFILES/.wireshark   /home/$USER/ &> /dev/null
      #
      HG_USER_NAME="Your Name"
      HG_USER_EMAIL="Your Email"
      HG_DEFAULT_PATH="ssh://hg@bitbucket.org/grouplens/cyclopath"
      m4 \
        --define=HG_USER_NAME="$HG_USER_NAME" \
        --define=HG_USER_EMAIL="$HG_USER_EMAIL" \
        --define=HG_DEFAULT_PATH="$HG_DEFAULT_PATH" \
        $USE_HOMEFILES/.hgrc \
          > /home/$USER/.hgrc

      # If you setup sshd on the new machine, from the old machine...
      #
      # cd ~
      # scp -pr .bashrc* $USER@$NEW_VM:/home/$USER
      # scp -pr .vim .vimprojects .vimrc $USER@$NEW_VM:/home/$USER
      # scp -pr .ctags .forward .gitconfig .psqlrc .xmodmap* mm.cfg \
      #          synergy.conf .ssh/ .wireshark/ $USER@$NEW_VM:/home/$USER
      # scp -pr Pictures/.cinnaskins/ $USER@$NEW_VM:/home/$USER/Pictures
      # maybe also ~/Documents, ~/Downloads, ~/Desktop, ~/dubs, ~/.dubs, ...
      #
      # CAVEAT/Don't use scp without first archiving:
      #    scp -r doesn't copy symlinks but rather the referenced file.
      # # cd /ccp ; scp -pr bin dev doc etc var $USER@$NEW_VM:/ccp
      # #scp -pr /ccp/opt/.downloads/* $USER@$NEW_VM:/ccp/opt/.downloads
      #
      # cd /ccp ; tar -vczf devo.tar.gz doc etc var opt
      # scp devo.tar.gz $USER@$NEW_VM:/ccp
      # cd /ccp ; tar -vczf bindev.tar.gz bin dev
      # scp bindev.tar.gz $USER@$NEW_VM:/ccp
      # # On the client: tar -xvzf devo.tar.gz
      #
      # You can use the scp commands on the home directory so long as you're
      # sure there are no symbolic links therein.
      #  ls -lR /home/$USER | grep ^l

    else
      echo "FIXME: Get Bash scripts online."
      echo "FIXME: Get Vim scripts online."
      exit 1
    fi

    print_install_time

    # Fix the VBox mount.
    # After the reboot, the user has access to the auto-mount,
    # so just symlink it.
    sudo umount $USE_MOUNTPT
    sudo /bin/rmdir /win
    sudo /bin/ln -s /media/sf_$USE_MOUNTPT /win

    echo
    echo "NOTE: Open a new terminal window now and test the new bash scripts."
    echo
    echo "If you get a shell prompt, it means everything worked."
    echo
    echo "If you see any error messages, it means it kind of worked."
    echo
    echo "But if you do not get a prompt, you'll want to cancel this script."
    echo "Then, run: /bin/rm ~/.bashrc*"
    echo "Finally, open a new new terminal and make sure you get a prompt."
    echo
    echo -en "Were you able to open a new terminal window? (y/n) "
    read -n 1 the_choice
    if [[ $the_choice != "y" && $the_choice != "Y" ]]; then
      echo "Sorry about that! You'll have to take it from here..."
      exit 1
    else
      # Kill everything but kill and init using the special -1 PID.
      # And don't run this as root or you'll be sorry (like, you'll
      # kill kill and init, I suppose). This will cause a logout.
      # http://aarklonlinuxinfo.blogspot.com/2008/07/kill-9-1.html
      #kill -9 -1
      echo
      echo "Sweet! Are you ready to reboot again?"
      ask_yes_no_default 'Y' 20

      if [[ $the_choice != "Y" ]]; then
        echo "But I was trying to be nice to you!"
      else
        sudo /sbin/shutdown -r now
      fi
      return
    fi

  fi

fi

# *** FOURTH BOOT: Configure Cinnamon and Install Cyclopath.

if [[ ! -e /ccp/dev/cp/flashclient/build/main.swf ]]; then

  echo 
  echo "Swizzle, so you've rebotted four times so far!"
  echo
  echo "This should be the last step."
  echo
  echo "We're going to configure your system, and we're"
  echo "going to download and compile lots of software."
  echo
  echo "Our goal is to customize Mint and to install a"
  echo "Cyclopath dev. environment."
  echo
  echo "NOTE: You might need to perform a few actions throughout."
  echo
  echo "Are we golden?"
  ask_yes_no_default 'Y'

  if [[ $the_choice != "Y" ]]; then

    echo "Obviously not. Ya have a nice day, now."
    return 1

  else

    # *** Make a snapshot of the user's home directory.

    if $MAKE_CONF_DUMPS; then
      cd ~/Downloads
      user_home_conf_dump "usr_04a"
    fi

    # *** Common environment variables.

    #source ${script_absbase}/../../../util/ccp_base.sh
    source ${script_absbase}/../../../util/bash_base.sh

    # *** Miscellaneous Cinnamon and Application Configuration

    #mwiki_basename="mediawiki-1.22.0"
    #mwiki_basename="mediawiki-1.22.5"
    mwiki_basename="mediawiki-1.23.6"
    #mwiki_wgetpath="http://download.wikimedia.org/mediawiki/1.22/${mwiki_basename}.tar.gz"
    mwiki_wgetpath="http://download.wikimedia.org/mediawiki/1.23/${mwiki_basename}.tar.gz"

    mwiki_basepath=/ccp/var/cms/${mwiki_basename}

    bzilla_basename="bugzilla-4.4.4"
    bzilla_basepath=/ccp/var/cms/${bzilla_basename}

    AUTO_INSTALL=$USE_CCPDFILES/scripts/setupcp/auto_install

    COMMON_FILES=$USE_CCPDFILES/scripts/setupcp/ao_templates/common

    MINT_FILES=$USE_CCPDFILES/scripts/setupcp/ao_templates/mint16/target

    # DEVS: To debug this script, throw an "if false; then" down right
    #       here and a "fi" after all the code you've already tested.

    # Hide desktop icons.

    if $WM_IS_CINNAMON; then
      gsettings set org.nemo.desktop computer-icon-visible false
      gsettings set org.nemo.desktop home-icon-visible false
      gsettings set org.nemo.desktop volumes-visible false
    elif $WM_IS_MATE; then
      gsettings set org.mate.caja.desktop computer-icon-visible false
      gsettings set org.mate.caja.desktop home-icon-visible false
      gsettings set org.mate.caja.desktop volumes-visible false
    fi

    if $WM_IS_CINNAMON || $WM_IS_XFCE; then
      # Fix the Terminal colors: it's really hard to read against
      # the default Mint background!
      # - Make White text on Solid White background.
      if $WM_IS_CINNAMON; then
        terminal_conf=.gconf/apps/gnome-terminal/profiles/Default/%gconf.xml
      elif $WM_IS_XFCE; then
        terminal_conf=.config/xfce4/terminal/terminalrc
      fi
      #
      /bin/cp -f \
        $MINT_FILES/home/$terminal_conf \
        /home/$USER/$terminal_conf
    fi

    /bin/mkdir -p /home/$USER/.gconf/apps/meld
    /bin/chmod 2700 /home/$USER/.gconf/apps/meld
    if $WM_IS_CINNAMON || $WM_IS_XFCE; then
      # Configure Meld (Monospace 9 pt font; show line numbers).
      /bin/cp -f \
        $MINT_FILES/home/.gconf/apps/meld/%gconf.xml-cinnamon \
        /home/$USER/.gconf/apps/meld/%gconf.xml
    elif $WM_IS_MATE; then
      /bin/cp -f \
        $MINT_FILES/home/.gconf/apps/meld/%gconf.xml-mate \
        /home/$USER/.gconf/apps/meld/%gconf.xml
      # MAYBE: There are also keys in gconftool-2, just after the existing meld
      #        entry. Might the absense of these conflict with the %gconf.xml?
      #   
      #        <entry>
      #          <key>/apps/gnome-settings/meld/history-fileentry</key>
      #          ...
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/edit_wrap_lines</key>
      #          <value>
      #            <int>2</int>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/show_line_numbers</key>
      #          <value>
      #            <bool>true</bool>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/spaces_instead_of_tabs</key>
      #          <value>
      #            <bool>true</bool>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/tab_size</key>
      #          <value>
      #            <int>3</int>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/use_syntax_highlighting</key>
      #          <value>
      #            <bool>true</bool>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/window_size_x</key>
      #          <value>
      #            <int>1680</int>
      #          </value>
      #        </entry>
      #        <entry>
      #          <key>/apps/meld/window_size_y</key>
      #          <value>
      #            <int>951</int>
      #          </value>
      #        </entry>
    fi

    # Setup sshd.
    #
    # See:
    #  https://help.ubuntu.com/community/SSH/OpenSSH/Keys
    #
    # Disable password auth. You'll have to setup SSH keys to connect.
    sudo /bin/sed -i.bak \
      "s/^#PasswordAuthentication yes$/#PasswordAuthentication yes\nPasswordAuthentication no/" \
      /etc/ssh/sshd_config

    sudo service ssh restart

    # Postgres config. Where POSTGRESABBR is, e.g., "9.1".

    if [[ -z ${POSTGRESABBR} ]]; then
      echo
      echo "ERROR: POSTGRESABBR is not set."
      exit 1
    fi

    # Add the postgres group user.
    sudo -u postgres createuser \
      --no-superuser --createdb --no-createrole \
      cycling

    # Backup existing files. With a GUID. Just to be Grazy.
    if false; then
      sudo mv /etc/postgresql/${POSTGRESABBR}/main/pg_hba.conf \
              /etc/postgresql/${POSTGRESABBR}/main/pg_hba.conf.`uuidgen`
      sudo mv /etc/postgresql/${POSTGRESABBR}/main/pg_ident.conf \
              /etc/postgresql/${POSTGRESABBR}/main/pg_ident.conf.`uuidgen`
      sudo mv /etc/postgresql/${POSTGRESABBR}/main/postgresql.conf \
              /etc/postgresql/${POSTGRESABBR}/main/postgresql.conf.`uuidgen`
    fi

    #
    sudo /bin/cp \
      $MINT_FILES/etc/postgresql/${POSTGRESABBR}/main/pg_hba.conf \
      /etc/postgresql/${POSTGRESABBR}/main/pg_hba.conf

    #
    m4 \
      --define=HTTPD_USER=www-data \
      --define=TARGETUSER=$USER \
        $MINT_FILES/etc/postgresql/${POSTGRESABBR}/main/pg_ident.conf \
      | sudo tee /etc/postgresql/${POSTGRESABBR}/main/pg_ident.conf \
      &> /dev/null

    # NOTE: Deferring installing postgresql.conf until /ccp/var/log
    #       is created (otherwise the server won't start) and until we
    #       configure/install other things so that the server won't not
    #       not start because of some shared memory limit issue.

    sudo chown postgres:postgres /etc/postgresql/${POSTGRESABBR}/main/*

    #sudo /etc/init.d/postgresql reload
    sudo /etc/init.d/postgresql restart

    # Make the Apache configs group-writeable.

    sudo /bin/chgrp -R $USE_CYCLOP_GROUP /etc/apache2/
    sudo /bin/chmod 664  /etc/apache2/apache2.conf
    sudo /bin/chmod 664  /etc/apache2/ports.conf
    sudo /bin/chmod 2775 /etc/apache2/sites-available
    sudo /bin/chmod 2775 /etc/apache2/sites-enabled
    sudo /bin/chmod 664  /etc/apache2/sites-available/*.conf

    # Avoid an apache gripe and set ServerName.
    m4 \
      --define=HOSTNAME=$HOSTNAME \
      --define=MACH_DOMAIN=$USE_DOMAIN \
        $MINT_FILES/etc/apache2/apache2.conf \
        > /etc/apache2/apache2.conf

    # Enable the virtual hosts module, for VirtualHost.
    sudo a2enmod vhost_alias
    # Enable the headers module, for <IfModule...>Header set...</IfModule>
    sudo a2enmod headers

    # Same as: service apache2 restart
    sudo /etc/init.d/apache2 restart

    # Remove the default conf.
    /bin/rm -f /etc/apache2/sites-enabled/000-default.conf

    # MAYBE: [lb] thinks Apache will start on boot, but it might be that
    #        I ran the following commands and forgot to include them herein:
    #
    #           sudo update-rc.d apache2 enable
    #           sudo /etc/init.d/apache2 restart
    #

    # Preemptively add hosts mappings for
    # http://mediawiki and http://cyclopath.
    m4 \
      --define=HOSTNAME=$HOSTNAME \
      --define=MACH_DOMAIN=$USE_DOMAIN \
        $MINT_FILES/etc/hosts \
        | sudo tee /etc/hosts &> /dev/null

    # Make the /ccp hierarcy.
    # (We'll run the rest of the auto_install scripts later)

    cd $AUTO_INSTALL
    ./dir_prepare.sh $HOSTNAME $USER

    # *** MediaWiki Install

    # Download PHP source.

    # -O doesn't work with -N so just download as is and then rename.
    # And use a special directory because the download name is obscure.
    #PHP_5X=5.4.24
    #PHP_5X=5.5.10
    #   2014.05.14: I [lb] $(sudo apt-get upgrade)ed and PHP got
    #               whacked, so I'm re-installing (something reverted
    #               to using the PHP from the package repository and
    #               not ours).
    #PHP_5X=5.5.12
    # 2014.11.07: And again something whacked MediaWiki and PHP seems at fault.
    PHP_5X=5.6.2
    mkdir -p /ccp/opt/.downloads/php-${PHP_5X}.download
    cd /ccp/opt/.downloads/php-${PHP_5X}.download
    #wget -N http://us1.php.net/get/php-${PHP_5X}.tar.gz/from/this/mirror
    wget -N http://php.net/get/php-${PHP_5X}.tar.gz/from/this/mirror
    cd /ccp/opt/.downloads/
    /bin/rm -f /ccp/opt/.downloads/php-${PHP_5X}.tar.gz
    /bin/ln -s php-${PHP_5X}.download/mirror php-${PHP_5X}.tar.gz
    /bin/rm -rf /ccp/opt/.downloads/php-${PHP_5X}/
    tar -zxvf php-${PHP_5X}.tar.gz

    # The new x64s have assumed /usr/lib as their own, rather
    # than /usr/lib64, so old software might be looking for
    # 32-bit libraries in the old standard location, /usr/lib,
    # but now they're found in /usr/lib/x86_64-linux-gnu.
    # So this is very much a hack that could easily break
    # if an app expected 64-bit ldap libs... but it seems to work.
    sudo /bin/ln -s \
      /usr/lib/x86_64-linux-gnu/libldap.so \
      /usr/lib/libldap.so
    sudo /bin/ln -s \
      /usr/lib/x86_64-linux-gnu/libldap_r.so \
      /usr/lib/libldap_r.so
    sudo /bin/ln -s \
      /usr/lib/x86_64-linux-gnu/liblber.so \
      /usr/lib/liblber.so

    # -- Build PHP

    cd /ccp/opt/.downloads/php-${PHP_5X}
    if [[ -e /ccp/opt/.downloads/php-${PHP_5X}/Makefile ]]; then
      make clean
    fi
    ./configure \
      --enable-maintainer-zts \
      --with-mysql \
      --with-pgsql \
      --with-apxs2=/usr/bin/apxs2 \
      --with-zlib \
      --with-ldap \
      --with-gd \
      --with-jpeg-dir \
      --with-iconv-dir \
      --enable-mbstring \
      --enable-intl
    make
    # You might also want to run:
    #  make test
    # but it triggers a known bug and you are asked to send a bug
    # email (all versions I've tried through 5.6.2).
    # So it's not enabled for this "automated" install.

    # The docs say to stop Apache before installing.
    sudo /etc/init.d/apache2 stop
    sudo make install
    sudo /etc/init.d/apache2 start
    # [lb] is not convinced this is necessary. And it fails at the end:
    #        Do you want to send this report now? [Yns]:
    #      You'll want to answer 'n' since we haven't configured email.
    #  make test

    # For whatever reason, make install didn't install a config file.
    # (Well, it does to /etc/php5/apache2/, but it doesn't use that one.)
    # ((Hint: run `php -i | grep ini` to see where it looks.))
    sudo /bin/cp \
      /ccp/opt/.downloads/php-${PHP_5X}/php.ini-development \
      /usr/local/lib/php.ini
    # Make sure www-data can read the file.
    sudo chmod 644 /usr/local/lib/php.ini

    # Set the timezone.
    sudo /bin/sed -i.bak \
      "s/^;date.timezone =/date.timezone = $USE_TIMEZONE/" \
      /usr/local/lib/php.ini

    # Loves to restart.
    sudo /etc/init.d/apache2 restart

    # -- Download and configure MediaWiki.

    cd /ccp/opt/.downloads
    wget -N ${mwiki_wgetpath}
    # Make the final directory, e.g., /ccp/var/cms/${mwiki_basename}.
    if [[ -d ${mwiki_basepath} ]]; then
      echo
      echo "WARNING: MediaWiki installation already exists. Skipping."
      echo
    else
      # Unpack to /ccp/opt/.downloads and then move to /ccp/var/cms.
      /bin/rm -rf ${mwiki_basename}
      tar -zxvf ${mwiki_basename}.tar.gz
      /bin/mkdir -p /ccp/var/cms/
      /bin/mv ${mwiki_basename} ${mwiki_basepath}
    fi
    cd ${mwiki_basepath}
    # Old apache versions: chmod a+w config
    sudo chown -R www-data:www-data ${mwiki_basepath}
    sudo chmod 2775 ${mwiki_basepath}
    sudo chmod 2777 ${mwiki_basepath}/mw-config

    # Create and configure the Wiki db user.

    psql --no-psqlrc -U postgres -c "
      CREATE USER wikiuser
      WITH NOCREATEDB NOCREATEROLE NOSUPERUSER ENCRYPTED
      PASSWORD '$USE_PSQLWIKIPWD'"
    psql --no-psqlrc -U postgres -c "
      CREATE DATABASE wikidb WITH OWNER=wikiuser ENCODING='UTF8';"
    psql --no-psqlrc -U postgres -c "
      GRANT SELECT ON pg_ts_config TO wikiuser;" wikidb
    psql --no-psqlrc -U postgres -c "
      GRANT SELECT ON pg_ts_config_map TO wikiuser;" wikidb
    psql --no-psqlrc -U postgres -c "
      GRANT SELECT ON pg_ts_dict TO wikiuser;" wikidb
    psql --no-psqlrc -U postgres -c "
      GRANT SELECT ON pg_ts_parser TO wikiuser;" wikidb

    # Install a bunch of support software.

    # APC User Cache.
    #
    # -O doesn't work with -N so just download as is and then rename.
    # And use a subdir to keep strays out of .downloads.
    #APCU_V4=apcu-4.0.2
    #APCU_V4=4.0.4
    #APCU_TGZ="v${APCU_V4}.tar.gz"
    APCU_V4=4.0.7
    APCU_TGZ="apcu-${APCU_V4}.tgz"
    cd /ccp/opt/.downloads
    mkdir -p /ccp/opt/.downloads/apcu-${APCU_V4}.download
    cd /ccp/opt/.downloads/apcu-${APCU_V4}.download
    #wget -N https://github.com/krakjoe/apcu/archive/${APCU_TGZ}
    wget -N http://pecl.php.net/get/${APCU_TGZ}
    cd /ccp/opt/.downloads/
    /bin/rm -f /ccp/opt/.downloads/apcu-${APCU_V4}.tar.gz
    /bin/ln -s apcu-${APCU_V4}.download/${APCU_TGZ} \
               apcu-${APCU_V4}.tar.gz
    /bin/rm -rf /ccp/opt/.downloads/apcu-${APCU_V4}
    gunzip -c apcu-${APCU_V4}.tar.gz | tar xf -
    cd /ccp/opt/.downloads/apcu-${APCU_V4}
    # Unalias the cp command for phpize...
    # Ha. If we don't run as sudo, phpize fails:
    #   me@machine:apcu-${APCU_V4} $ /usr/local/bin/phpize
    #    Configuring for:
    #    PHP Api Version:         20100412
    #    Zend Module Api No:      20100525
    #    Zend Extension Api No:   220100525
    #    cp: cannot stat 'run-tests*.php': No such file or directory
    #  because /usr/local/lib/php/build is off limits.
    sudo /usr/local/bin/phpize
    # The phpize results in some files owned by root.
    sudo chown -R $USER:$USER /ccp/opt/.downloads/apcu-${APCU_V4}
    ./configure --with-php-config=/usr/local/bin/php-config
    make
    # MAYBE, Or do it yourself:
    #         make test
    #        but you'll get an error like with PHP compile that
    #        requires intervention so cannot automate `make test`.
    sudo make install

    # 2014.03.13: MediaWiki stopped working. Firefox windows are loaded,
    # but refresh says "Fatal exception of type MWException", and enabling
    # $wgShowExceptionDetails in LocalSettings.php says "CACHE_ACCEL requested
    # but no suitable object cache is present. You may want to install APC."
    # Weird. I might have installed something with PIP and messed up
    # permissions, or maybe I uninstalled something and whacked APC...?
    #  Nope: sudo apt-get install php-apc
    #  I reinstalled APC from source...
    # See also:
    #  php -r 'phpinfo();' | grep apc
    #
    # ARGH: I think it was 'sudo apt-get upgrade':
    # $ php --version
    # PHP 5.4.24 (cli) (built: Jan 28 2014 15:16:11) 
    # $ php5 --version
    # PHP 5.5.3-1ubuntu2.2 (cli) (built: Feb 28 2014 20:06:05) 
    #
    # I reinstalled (newer versions of) MediaWiki and APC.
    # For MediaWiki, after you make the new folder in /ccp/var/cms:
    #   cd ${mwiki_basepath}
    #   sudo cp -a ../mediawiki-1.22.0/LocalSettings.php .
    #   sudo /bin/cp -a \
    #     ../mediawiki-1.22.0/skins/common/images/mediawiki_custom.png \
    #     skins/common/images/
    #   php maintenance/update.php
    # and then update /etc/apache2/sites-available/mediawiki.conf
    # and restart Apache.

    # Pecl Intl
    # NOTE: It'd be nice to run this first, right after we interacted with the
    #       user, but it needs PHP to be installed. So, whatever, interruption!
    echo
    echo "NOTE: The pecl intl installer will axe you a question."
    echo "Just hit return when asked where the ICU directory is."
    echo
    # 2014.05.14: We ./configure --enable-intl when we build PHP, so this may
    #             no longer be necessary:
    sudo pecl install intl
    # Weird, the permissions are 0640.
    sudo /bin/chmod 755 \
      /usr/local/lib/php/extensions/no-debug-zts-20100525/intl.so
    # 2014.04.17: Don't include intl.so. It's not part of the newer PHP.
    # The newer PHP uses /usr/local/lib/php/extensions/no-debug-zts-20121212,
    #  and there's no intl.so there within.
    # EXPLAIN: What happened? Did we miss something in the build process,
    #          or is intl integrated into the base package now?

    echo "
; [Ccp Installer] For MediaWiki:
;       APC User Cache and I18N.
extension=apcu.so
;extension=intl.so
; Do we need to rename these for PHP5.6?
;extension=php_apcu.so
;;extension=php_intl.so


error_log = /ccp/var/log/mediawiki/php_errors.log
" | sudo tee -a /usr/local/lib/php.ini &> /dev/null

    # MAYBE: Additional php.ini settings we might want to set.
    #
    #apc.enabled=1
    #apc.shm_size=32M
    #apc.ttl=7200
    #apc.enable_cli=1

    # Configure the Web server before finishing MediaWiki installation.

    # Make an apache config.
    m4 \
      --define=MWIKI_BASENAME=$mwiki_basename \
      --define=MACH_DOMAIN=$USE_DOMAIN \
        $MINT_FILES/etc/apache2/sites-available/mediawiki \
        > /etc/apache2/sites-available/mediawiki.conf

    # Activate the apache conf.
    cd /etc/apache2/sites-enabled/
    ln -s ../sites-available/mediawiki.conf mediawiki.conf

    #sudo /etc/init.d/apache2 reload
    sudo /etc/init.d/apache2 restart

    # Ideally, we'd generate a LocalSetting.php file via the command line, but
    # it doesn't seem to produce the same file as going through the Web
    # installer (e.g., at http://mediawiki). For one, if your $wgSitename is
    # non-conformist, e.g., "[lb]", the Web installer adds to LocalSettings,
    #  $wgMetaNamespace = "Lb";
    # but the CLI installer doesn't do this. (And for another, the Web
    # installer will set $wgLogo = "$wgStylePath/common..." but the CLI
    # installer sets $wgLogo ="/wiki/skins/common...". So the Web installer
    # definitely seems like the better one for which to generate the config.
    #
    # So if we're going to automate the MediaWiki installation, we might as
    # well pre-generate a LocalSettings.php using the Web installer and just
    # use m4 to configure it here... 'tevs, man.
    #
    # This is the CLI code. We could run this and then make appropriate changes
    # using, e.g., `sed`, but, as discussed above, let's just use m4 on a file
    # we've previously generated using the Web installer.
    if false; then
      # Mandatory arguments:
      #  <name>: The name of the wiki
      #  <admin>: The username of the wiki administrator (WikiSysop)
      # The rest of the arguments should make sense.
      #  --installdbuser: The user to use for installing (root)
      #  --installdbpass: The pasword for the DB user to install as.
      cd ${mwiki_basepath}
      sudo php maintenance/install.php \
        --scriptpath "" \
        \
        --dbtype "postgres" \
        \
        --dbuser "wikiuser" \
        --dbpass "$USE_PSQLWIKIPWD" \
        \
        --dbname "wikidb" \
        \
        --installdbuser "wikiuser" \
        --installdbpass "$USE_PSQLWIKIPWD" \
        \
        --pass "$USE_WIKIUSERPASS" \
          $USE_WIKINAME $USE_WIKIUSERNAME 
    fi # end: Not using the MediaWiki CLI installer.

    # 2014.11.05: How to upgrade mediawiki. Install MediaWiki,
    # PHP, and APCU, etc., and check that the Web site works
    # and shows the Let's Get Started screen. Then, do this:
    if false; then
      old_mwiki_basename="mediawiki-1.22.5"
      new_mwiki_basename="mediawiki-1.23.6"
      cd /ccp/var/cms
      /bin/cp ${old_mwiki_basename}/LocalSettings.php ${new_mwiki_basename}/
      /bin/cp ${old_mwiki_basename}/skins/common/images/mediawiki_custom.png \
        ${new_mwiki_basename}/
      cd /ccp/var/cms/${new_mwiki_basename}
      php maintenance/update.php
      # You're done!
    fi

    # Install the logo for your mediawiki site.

    wiki_base=/ccp/var/cms/${mwiki_basename}
    wk_images=${wiki_base}/skins/common/images
    # NOTE: $wk_images is 0771, so you can't ls it.
    sudo /bin/cp \
      $USE_WIKISITELOGO \
      ${wk_images}/mediawiki_custom.png

    sudo /bin/chmod 0660 ${wk_images}/mediawiki_custom.png
    sudo /bin/chown www-data:www-data ${wk_images}/mediawiki_custom.png

    # Install the LocalSettings file, and set the custom logo. Note that we
    # shouldn't just overwrite the existing logo, because that file may get
    # overwritten if you upgrade MediaWiki.

    # We have to make the namespace name...
    # See: mediawiki-1.22.0/includes/installer/WebInstallerPage.php
    #  // This algorithm should match the JS one in WebInstallerOutput.php
    #  $name = preg_replace( '/[\[\]\{\}|#<>%+? ]/', '_', $name );
    #  $name = str_replace( '&', '&amp;', $name );
    #  $name = preg_replace( '/__+/', '_', $name );
    #  $name = ucfirst( trim( $name, '_' ) );
    # We just copy the MediaWiki source and run a snippet of PHP from the CLI.
    META_NAMESPACE=$(
      php -r "
        \$name = '$USE_WIKINAME';
        \$name = preg_replace( '/[\[\]\{\}|#<>%+? ]/', '_', \$name );
        \$name = str_replace( '&', '&amp;', \$name );
        \$name = preg_replace( '/__+/', '_', \$name );
        \$name = ucfirst( trim( \$name, '_' ) );
        print \$name;
        "
      )

    # Make an intermediate LocalSettings.php, otherwise calling php
    # from the command line fails (and we want to generate some keys
    # using PHP).
    m4 \
      --define=NEW_WIKINAME="$USE_WIKINAME" \
      --define=META_NAMESPACE="$META_NAMESPACE" \
      --define=CUSTOM_LOGO_PNG="mediawiki_custom.png" \
      --define=MACH_DOMAIN="$USE_DOMAIN" \
      --define=DB_PASSWORD="$USE_PSQLWIKIPWD" \
      --define=SECRET_KEY="" \
      --define=UPGRADE_KEY="" \
        $COMMON_FILES/other/LocalSettings.php \
        | sudo tee ${mwiki_basepath}/LocalSettings.php &> /dev/null

    # See mediawiki-1.22.0/includes/installer/Installer.php::doGenerateKeys
    sudo /bin/cp \
      $COMMON_FILES/other/regenerateSecretKey.php \
      ${mwiki_basepath}/maintenance
    sudo chown www-data:www-data \
      ${mwiki_basepath}/maintenance/regenerateSecretKey.php
    #sudo chmod 660 \
    sudo chmod 664 \
      ${mwiki_basepath}/maintenance/regenerateSecretKey.php
    SECRET_KEY=$(
      sudo -u www-data \
       php /ccp/var/cms/${mwiki_basename}/maintenance/regenerateSecretKey.php \
       --hexlen 64)
    UPGRADE_KEY=$(
      sudo -u www-data \
       php /ccp/var/cms/mediawiki-${mwiki_basename}/maintenance/regenerateSecretKey.php \
       --hexlen 16)

    # Make the final LocalSettings.php.
    m4 \
      --define=NEW_WIKINAME="$USE_WIKINAME" \
      --define=META_NAMESPACE="$META_NAMESPACE" \
      --define=CUSTOM_LOGO_PNG="mediawiki_custom.png" \
      --define=MACH_DOMAIN="$USE_DOMAIN" \
      --define=DB_PASSWORD="$USE_PSQLWIKIPWD" \
      --define=SECRET_KEY="$SECRET_KEY" \
      --define=UPGRADE_KEY="$UPGRADE_KEY" \
        $COMMON_FILES/other/LocalSettings.php \
        | sudo tee ${mwiki_basepath}/LocalSettings.php &> /dev/null

    sudo chmod 660 ${mwiki_basepath}/LocalSettings.php
    sudo chown www-data:www-data ${mwiki_basepath}/LocalSettings.php
    #sudo chown $USER:$USE_CYCLOP_GROUP \
    #  /ccp/var/cms/${mwiki_basename}/LocalSettings.php
    #chmod 664 /ccp/var/cms/${mwiki_basename}/LocalSettings.php

    # NOTE: It can be convenient to make the MediaWiki directory 
    #       world-readable, so you don't have to sudo just to get a directory
    #       listing...
    # sudo /ccp/dev/cp/scripts/util/fixperms.pl --public ${wiki_base}/

    # If you made a new LocalSettings.php, save that file
    # but drop-replace the database that was created.

    # Download the remote file if the path is relative, indicating as such
    # (from $USE_RESOURCES_URI).
    if [[ -n $USE_WIKIDB_DUMP && $(dirname $USE_WIKIDB_DUMP) == "." ]]; then
      if [[ -z $USE_RESOURCES_URI ]]; then
        echo
        echo "ERROR: Set USE_RESOURCES_URI or abs path for USE_WIKIDB_DUMP"
        exit 1
      fi
      cd /ccp/var/cms
      wget -N \
        --user "$USE_RESOURCES_USER" \
        --password "$USE_RESOURCES_PASS"
        $USE_RESOURCES_URI/$USE_WIKIDB_DUMP
      if [[ $? -ne 0 || ! -e /ccp/var/cms/$USE_WIKIDB_DUMP ]]; then
        echo
        echo "WARNING: No MediaWiki dump: $USE_RESOURCES_URI/$USE_WIKIDB_DUMP"
        echo
      else
        $USE_WIKIDB_DUMP = /ccp/var/cms/$USE_WIKIDB_DUMP
      fi
    fi

    if [[ -e $USE_WIKIDB_DUMP ]]; then

      psql --no-psqlrc -U postgres -c "
        DROP DATABASE wikidb;"
      psql --no-psqlrc -U postgres -c "
        CREATE DATABASE wikidb WITH OWNER=wikiuser ENCODING='UTF8';"
      psql --no-psqlrc -U postgres -c "
        GRANT SELECT ON pg_ts_config TO wikiuser;" wikidb
      psql --no-psqlrc -U postgres -c "
        GRANT SELECT ON pg_ts_config_map TO wikiuser;" wikidb
      psql --no-psqlrc -U postgres -c "
        GRANT SELECT ON pg_ts_dict TO wikiuser;" wikidb
      psql --no-psqlrc -U postgres -c "
        GRANT SELECT ON pg_ts_parser TO wikiuser;" wikidb

      # Load the existing Wiki database.
      psql --no-psqlrc -U postgres wikidb -f $USE_WIKIDB_DUMP

      # Upgrade the Wiki database to the current MediaWiki version.
      cd /ccp/var/cms/${mwiki_basename}
      sudo php maintenance/update.php

    fi

    # We can probably cleanup but this script is green, so retaining the db we
    # just loaded, at least for now.
    if false; then
      if [[ -e $USE_WIKIDB_DUMP ]]; then
        /bin/rm -f $USE_WIKIDB_DUMP
      fi
    fi

    #sudo /etc/init.d/apache2 reload
    sudo /etc/init.d/apache2 restart

    # *** Bugzilla Install

# FIXME/BEWARE: 2014.06.12: This install might still be incompletely automated.

    bzilla_basename="bugzilla-4.4.4"
    bzilla_basepath=/ccp/var/cms/${bzilla_basename}

    cd /ccp/opt/.downloads
    wget -N \
      http://ftp.mozilla.org/pub/mozilla.org/webtools/${bzilla_basename}.tar.gz
    # Make the final directory, e.g., /ccp/var/cms/${bzilla_basename}.
    if [[ -d ${bzilla_basepath} ]]; then
      echo
      echo "WARNING: Bugzilla installation already exists. Skipping."
      echo
    else
      /bin/rm -rf ${bzilla_basename}
      tar -zxvf ${bzilla_basename}.tar.gz
      /bin/mkdir -p /ccp/var/cms/
      /bin/mv ${bzilla_basename} ${bzilla_basepath}
    fi
    cd ${bzilla_basepath}
    # Old apache versions: chmod a+w config
    sudo chown -R www-data:www-data ${bzilla_basepath}
    sudo chmod 2775 ${bzilla_basepath}

    # Install mod_perl for Apache.
    # 2014.05.27: Skip mod_perl. While it might be faster than mod_cgi,
    # it's newer, it takes a lot more RAM, and it doesn't necessarily
    # play well with other mod_perl-enabled sites.
    #
    #  sudo apt-get install libapache2-mod-perl2

    # Make an apache config.
    m4 \
      --define=MWIKI_BASENAME=$bzilla_basename \
      --define=MACH_DOMAIN=$USE_DOMAIN \
        $MINT_FILES/etc/apache2/sites-available/bugzilla \
        > /etc/apache2/sites-available/bugzilla.conf
    # Activate the apache conf.
    cd /etc/apache2/sites-enabled/
    ln -s ../sites-available/bugzilla.conf bugzilla.conf
    #sudo /etc/init.d/apache2 reload
    sudo /etc/init.d/apache2 restart

    cd ${bzilla_basepath}
    # Check for missing modules.
    #   ./checksetup.pl --check-modules
    # You'll see a suggestion to
    #   install CPAN
    #   reload cpan
    # but this isn't right and is not something we should worry about.
    # (If we want to update cpan, we should download and compile it
    #  ourselves.)
    # And then run either,
    #  /usr/bin/perl install-module.pl --all
    # or,
    /usr/bin/perl install-module.pl DateTime
    /usr/bin/perl install-module.pl DateTime::TimeZone
    /usr/bin/perl install-module.pl Template
    /usr/bin/perl install-module.pl Email::Send
    /usr/bin/perl install-module.pl Email::MIME
    /usr/bin/perl install-module.pl Math::Random::ISAAC
    # Install all the optional modules (why not!... except
    # this takes a few minutes, takes up hard drive space,
    # and adds complexity to the software and probably lots
    # of features we won't use).
    /usr/bin/perl install-module.pl --all
    # Check for missing modules again.
    #   ./checksetup.pl --check-modules
    # For whatever reason, two modules will be indicated as missing,
    # but when you try to install them, they'll say they're up to date.
    #   Daemon-Generic: /usr/bin/perl install-module.pl Daemon::Generic
    #   Apache-SizeLimit: /usr/bin/perl install-module.pl Apache2::SizeLimit

    # Run checksetup without the --check-modules.
    ./checksetup.pl

    # Configure db vars
    cd ${bzilla_basepath}
    #
    sudo /bin/sed -i.bak \
      "s/^\$webservergroup = 'apache';$/\$webservergroup = 'www-data';/ ; 
       s/^\$db_driver = 'mysql';$/\$db_driver = 'pg';/ ; " \
      /usr/local/lib/php.ini
    #

# FIXME: Finish implementing permissions
#        (move this to the setup.$HOSTNAME.sh private file)
#$db_name = 'bugs';
#$db_user = 'bugs';
#$db_pass = '';

    # Run checksetup with the updated localconfig.
    ./checksetup.pl

    # *** Cinnamon/Xfce/MATE Customization

    # Change the background image.

    # Download the remote file, maybe.
    if [[ -n $USE_DESKTOP_IMAGE && $(dirname $USE_DESKTOP_IMAGE) == "." ]];
      then
      if [[ -z $USE_RESOURCES_URI ]]; then
        echo
        echo "ERROR: Set USE_RESOURCES_URI or abs path for USE_DESKTOP_IMAGE"
        exit 1
      fi
      /bin/mkdir -p /ccp/var/.install
      cd /ccp/var/.install
      wget -N \
        --user "$USE_RESOURCES_USER" \
        --password "$USE_RESOURCES_PASS" \
        $USE_RESOURCES_URI/$USE_DESKTOP_IMAGE
      if [[ $? -ne 0 || ! -e /ccp/var/.install/$USE_DESKTOP_IMAGE ]]; then
        echo
        echo "ERROR: No desktop image: $USE_RESOURCES_URI/$USE_DESKTOP_IMAGE"
        exit 1
      fi
      USE_DESKTOP_IMAGE=/ccp/var/.install/$USE_DESKTOP_IMAGE
    fi

    if [[ -n $USE_DESKTOP_IMAGE ]]; then
      USER_BGS=/home/$USER/Pictures/.backgrounds
      /bin/mkdir -p $USER_BGS
      /bin/cp $USE_DESKTOP_IMAGE $USER_BGS
      BG_FILE_PATH="$USER_BGS/`basename $USE_DESKTOP_IMAGE`"
    fi

    if $WM_IS_CINNAMON; then
      gsettings set \
        org.cinnamon.desktop.background picture-uri "file://$BG_FILE_PATH"
    elif $WM_IS_XFCE; then
      bg_conf=.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
      #/bin/cp -f \
      #  $MINT_FILES/home/$bg_conf \
      #  /home/$USER/$bg_conf
      m4 --define=USE_DESKTOP_IMAGE=$USE_DESKTOP_IMAGE \
        $MINT_FILES/home/$bg_conf \
        > /home/$USER/$bg_conf
    elif $WM_IS_MATE; then
      gsettings set \
        org.mate.background picture-filename "$BG_FILE_PATH"
      # There's also a dconf setting but I didn't explicitly set it:
      #   [org/mate/desktop/background]
      #   color-shading-type='solid'
      #   primary-color='#000000000000'
      #   picture-options='zoom'
      #   picture-filename='/home/cyclopath/Pictures/.backgrounds/desktop_bg.jpg'
      #   secondary-color='#000000000000'
    fi

    # Keep the image, at least while we keep testing this script.
    if false; then
      if [[ -e $USE_DESKTOP_IMAGE ]]; then
        /bin/rm -f $USE_DESKTOP_IMAGE
      fi
    fi

    # Xfce Tweaks

    if $WM_IS_XFCE; then

      # Enable left/right edit snapping (or whatever it's called, maybe,
      # drag-to-edge-expands-window-to-half-screen feature).
      #   Thanks: http://www.linuxquestions.org/questions/slackware-14/
      #             snapping-windows-in-xfce-4175432017/
      wm_conf=.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
      /bin/cp -f \
        $MINT_FILES/home/$wm_conf \
        /home/$USER/$wm_conf

      # Make the panel two rows tall and rearrange things. Also enable dragging
      # the window list icons around (so you can reorder them).
      panel_conf=.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
      /bin/cp -f \
        $MINT_FILES/home/$panel_conf \
        /home/$USER/$panel_conf

      # For more Xfce panel plugins, see:
      #   http://goodies.xfce.org/projects/panel-plugins/start
      # I guess it's a tie between these two system monitors:
      sudo apt-get install \
        xfce4-cpugraph-plugin \
        xfce4-systemload-plugin \
      # "Your system does not support cpufreq," it says.
      #   sudo apt-get install xfce4-cpufreq-plugin
      # And this monitor kinda sucks. Then again, it does call itself
      # "Generic Monitor", so what would you expect?
      #   sudo apt-get install xfce4-genmon-plugin

      # You can change the background color of the panel but you cannot change
      # the text color of the built-in calendar panel plugin?

      # Ug, fail. Xfce is okay, but I [lb] cannot make a two-row window list in
      # the same panel as other applets without strecting other applets' icons.
      # So you have to make two panels and stack them both at the bottom of the
      # screen. Which is how I've been rolling in GNOME 2 for the past forever.
      # But in Xfce, when you resize your VirtualBox window, the two panels
      # become unhinged and don't realign properly. So... I'm done with Xfce
      # tweaks, and have since moved on to MATE.

    fi # end: if $WM_IS_XFCE

    # QuickTile by ssokolow (similar to WinSplit Revolution) is an edge tiling
    # window feature. It lets you quickly resize and move windows to
    # pre-defined tiles. This is similar to a behavior in Windows 7, GNOME 3,
    # and Cinnamon, when you drag a window to the top, bottom, left or right
    # of the screen and it assumes a window size half of the screen).
    #  See: http://ssokolow.com/quicktile/
    #
    # Usage: With the target window active, hold Ctrl + Alt and hit numpad
    # 1 through 9 to tile the window. 1 through 9 map to the relative screen
    # positions, e.g., 1 is lower-left, 6 is right-half, etc.

    if $WM_IS_MATE; then

      if [[ ! -d /ccp/opt/.downloads/quicktile ]]; then
        cd /ccp/opt/.downloads
        # http://github.com/ssokolow/quicktile/tarball/master
        git clone git://github.com/ssokolow/quicktile
      else
        cd /ccp/opt/.downloads/quicktile
        git pull origin
      fi
      cd /ccp/opt/.downloads/quicktile
      # ./quicktile.py # Writes: /home/landonb/.config/quicktile.cfg
      # It also spits out the help and returns an error code.
      set +ex
      ./quicktile.py
      reset_errexit
      #
      # 2014.11.17: Make sure we use Python2.
      /bin/sed -i.bak \
        "s/^#\!\/usr\/bin\/env python$/#\!\/usr\/bin\/env python2/" \
        ./setup.py
      #
      # ./setup.py build
      sudo ./setup.py install
      #
      # Test:
      #  quicktile.py --daemonize
      # Well, that's odd:
      sudo chmod 644 /etc/xdg/autostart/quicktile.desktop
      sudo chmod 755 /usr/local/bin/quicktile.py
      #sudo /bin/ln -s \
      #  /usr/local/lib/python${PYVERS_RAW}/dist-packages/QuickTile-0.0.0-py${PYVERS_RAW}.egg \
      #  /usr/local/lib/python${PYVERS_RAW}/dist-packages/QuickTile-0.2.2-py${PYVERS_RAW}.egg
      sudo $USE_CCPDFILES/scripts/util/fixperms.pl --public \
        /usr/local/lib/python${PYVERS_RAW}/dist-packages/QuickTile-0.2.2-py${PYVERS_RAW}.egg
      # Hrm. I reinstalled but then had to make my own startup file, since 
      # /etc/xdg/autostart/quicktile.desktop no longer seemed to work (it
      # doesn't appear to be registered; probably a dconf problem). SO
      # just make your own startup file and have it execute:
      #   /usr/local/bin/quicktile.py --daemonize
      # If you want to run quicktile from the command line, try:
      #   sudo /usr/local/bin/quicktile.py --daemonize &

    fi

    # Custom login screen.

    # Download the remote file, maybe.
    if [[ -n $USE_GREETER_IMAGE && $(dirname $USE_GREETER_IMAGE) == "." ]];
      then
      if [[ -z $USE_RESOURCES_URI ]]; then
        echo
        echo "ERROR: Set USE_RESOURCES_URI or abs path for USE_GREETER_IMAGE."
        exit 1
      fi
      /bin/mkdir -p /ccp/var/.install
      cd /ccp/var/.install
      # -O doesn't work with -N so just download as is and then rename.
      wget -N \
        --user "$USE_RESOURCES_USER" \
        --password "$USE_RESOURCES_PASS" \
        $USE_RESOURCES_URI/$USE_GREETER_IMAGE
      if [[ $? -ne 0 || ! -e /ccp/var/.install/$USE_GREETER_IMAGE ]]; then
        echo
        echo "ERROR: No greeter image at $USE_RESOURCES_URI/$USE_GREETER_IMAGE"
        exit 1
      fi
      USE_GREETER_IMAGE=/ccp/var/.install/$USE_GREETER_IMAGE
    fi

    if [[ -n $USE_GREETER_IMAGE && -n $USE_GREETER_THEME ]]; then

      THEME_NAME=$(basename $USE_GREETER_THEME)

      sudo /bin/cp -r \
        $USE_GREETER_THEME \
        /usr/share/mdm/html-themes/
      sudo /bin/cp \
        $USE_GREETER_IMAGE \
        /usr/share/mdm/html-themes/$THEME_NAME/bg.jpg
      sudo /bin/cp \
        $USE_GREETER_IMAGE \
        /usr/share/mdm/html-themes/$THEME_NAME/screenshot.jpg

      sudo chown -R root:root /usr/share/mdm/html-themes/$THEME_NAME
      sudo chmod 2755 /usr/share/mdm/html-themes/$THEME_NAME
      sudo $USE_CCPDFILES/scripts/util/fixperms.pl --public \
        /usr/share/mdm/html-themes/$THEME_NAME

      # Keep the image, at least while we keep testing this script.
      if false; then
        if [[ -e $USE_GREETER_IMAGE ]]; then
          /bin/rm -f $USE_GREETER_IMAGE
        fi
      fi

      # NOTE: You have to reboot to see changes. Logout is insufficient.

      if $WM_IS_CINNAMON; then
        gconftool-2 --set /desktop/cinnamon/windows/theme \
          --type string "$THEME_NAME"
        gconftool-2 --set /apps/metacity/general/theme \
          --type string "$THEME_NAME"
        gconftool-2 --set /desktop/gnome/interface/gtk_theme \
          --type string "$THEME_NAME"
        gconftool-2 --set /desktop/gnome/interface/icon_theme \
          --type string "$THEME_NAME"
      fi
      sudo ln -s /usr/share/icons/Mint-X \
        /usr/share/icons/$THEME_NAME
      sudo ln -s /usr/share/icons/Mint-X-Dark \
        /usr/share/icons/$THEME_NAME-Dark
      #sudo ln -s /usr/share/mdm/html-themes/Mint-X \
      #  /usr/share/mdm/html-themes/$THEME_NAME
      sudo ln -s /usr/share/pixmaps/pidgin/tray/Mint-X \
        /usr/share/pixmaps/pidgin/tray/$THEME_NAME
      sudo ln -s /usr/share/pixmaps/pidgin/tray/Mint-X-Dark \
        /usr/share/pixmaps/pidgin/tray/$THEME_NAME-Dark
      sudo ln -s /usr/share/themes/Mint-X \
        /usr/share/themes/$THEME_NAME
      gsettings set org.gnome.desktop.wm.preferences theme "$THEME_NAME"
      gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
      gsettings set org.gnome.desktop.interface icon-theme "$THEME_NAME"
      # org.gnome.desktop.sound theme-name 'LinuxMint'
      if $WM_IS_CINNAMON; then
        gsettings set org.cinnamon.desktop.wm.preferences theme "$THEME_NAME"
        gsettings set org.cinnamon.desktop.interface gtk-theme "$THEME_NAME"
        gsettings set org.cinnamon.desktop.interface icon-theme "$THEME_NAME"
      elif $WM_IS_MATE; then
        gsettings set org.mate.Marco.general theme "$THEME_NAME"
        gsettings set org.mate.interface gtk-theme "$THEME_NAME"
        gsettings set org.mate.interface icon-theme "$THEME_NAME"
        gsettings set org.mate.Marco.general theme "$THEME_NAME"
        # org.mate.sound theme-name 'LinuxMint'
      fi

      sudo /bin/sed -i.bak \
        "s/^\[greeter\]$/[greeter]\nHTMLTheme=$THEME_NAME/" \
        /etc/mdm/mdm.conf
    fi

    if $WM_IS_CINNAMON; then

      # Disable screensaver and lock screen.
      gconftool-2 --set \
        /apps/gnome-screensaver/lock_enabled \
        --type bool "0"
      gconftool-2 --set \
        /apps/gnome-screensaver/idle_activation_enabled \
        --type bool "0"

      # Disable alert sounds.
      #gsettings set org.cinnamon.sounds close-enabled false
      gsettings set org.cinnamon.sounds login-enabled false
      #gsettings set org.cinnamon.sounds map-enabled false
      #gsettings set org.cinnamon.sounds maximize-enabled false
      #gsettings set org.cinnamon.sounds minimize-enabled false
      gsettings set org.cinnamon.sounds plug-enabled false
      gsettings set org.cinnamon.sounds switch-enabled false
      gsettings set org.cinnamon.sounds tile-enabled false
      #gsettings set org.cinnamon.sounds unmaximize-enabled false
      gsettings set org.cinnamon.sounds unplug-enabled false

      # Disable the annoying HUD (heads-up display) message,
      # "Hold <CTRL> to enter snap mode
      #  Use the arrow keys to change workspaces"
      # which seems to appear when you're dragging a window and
      # then disappears quickly -- it's information I already know,
      # it's distracting when it pops up (and it doesn't always pop
      # up when dragging windows), and it hides itself so quickly it
      # seem useless.
      # NOTE: These instructions are wrong: [lb] thought I solved the
      #       problem, but it continued to happen.
      #gsettings set org.cinnamon hide-snap-osd true
      # Hrmpf, that setting didn't seem to work, or maybe it half worked:
      # I still see the popup notices, but it doesn't seem like as many.
      # Try another option, found on the Cinnamon panel at
      # System Settings > General > display notifications.
      #gsettings set org.cinnamon display-notifications false

      # Screensaver & Lock Settings > [o] Dim screen to save power
      gsettings set org.cinnamon.settings-daemon.plugins.power \
        idle-dim-battery false
      # MAYBE: Where's the setting for "Turn screen off when inactive for: "
      #        I want to set it to Never but neither gsettings nor gconftool-2
      #        reveal any differences...

      # Map Ctrl + Alt + Backspace to Immediate Logout
      gconftool-2 --type list --list-type string \
        --set /desktop/gnome/peripherals/keyboard/kbd/options \
        '[lv3 lv3:ralt_switch,terminate terminate:ctrl_alt_bksp]'
      # NOTE: MATE already implements this behavior.

    fi # end: if $WM_IS_CINNAMON

    # Cinnamon applets

    if $WM_IS_CINNAMON; then

      # Calendar applet
      home_path=.cinnamon/configs/calendar@cinnamon.org
      /bin/cp \
        $MINT_FILES/home/$home_path/calendar@cinnamon.org.json \
        ~/$home_path/

      # System monitor applet
      # Requires: gir1.2-gtop-2.0
      cd ~/Downloads
      wget -N \
        http://cinnamon-spices.linuxmint.com/uploads/applets/YYRT-ZCAP-A2Y2.zip
      unzip YYRT-ZCAP-A2Y2.zip -d system_monitor_applet
      /bin/rm -rf ~/.local/share/cinnamon/applets/sysmonitor@orcus
      mv system_monitor_applet/sysmonitor@orcus \
         ~/.local/share/cinnamon/applets
      rmdir system_monitor_applet
   
      home_path=.local/share/cinnamon/applets/sysmonitor@orcus
      /bin/cp \
        $MINT_FILES/home/$home_path/settings.json \
        ~/$home_path/

      # Weather applet
      cd ~/Downloads
      wget -N \
        http://cinnamon-spices.linuxmint.com/uploads/applets/E51P-PRLJ-G0D8.zip
      unzip E51P-PRLJ-G0D8.zip -d weather_applet
      /bin/rm -rf ~/.local/share/cinnamon/applets/weather@mockturtl
      mv weather_applet/weather@mockturtl \
         ~/.local/share/cinnamon/applets
      rmdir weather_applet

      home_path=.local/share/cinnamon/applets/weather@mockturtl
      /bin/cp \
        $MINT_FILES/home/$home_path/metadata.json \
        ~/$home_path/

      # Screenshot applet
      cd ~/Downloads
      wget -N \
        http://cinnamon-spices.linuxmint.com/uploads/applets/10JS-URQD-PS1K.zip
      unzip 10JS-URQD-PS1K.zip -d capture_applet
      /bin/rm -rf ~/.local/share/cinnamon/applets/capture@rjanja
      /bin/mv capture_applet/capture@rjanja \
         ~/.local/share/cinnamon/applets/
      rmdir capture_applet
   
      home_path=.local/share/cinnamon/applets/capture@rjanja
      /bin/cp \
        $MINT_FILES/home/$home_path/metadata.json \
        ~/$home_path/

      # Cinnamon Multi-Line Taskbar

      # http://cinnamon-spices.linuxmint.com/applets/view/123
      # UUID: cinnamon-multi-line-taskbar-applet

      # FIXME: This applet doesn't seem to work. It's completely AWOL once
      #        installed.
      #
      # See also: http://cinnamon-spices.linuxmint.com/extensions/view/9
      #  There's a Cinnamon Extension called 2 Bottom Panels 0.1 that should
      #  do something similar, but it, too, doesn't work.
      #  ... fingers crossed on Mint 17! Or maybe these authors or another
      #  dev will pickup and fix these applets/extensions: if you're going
      #  to stay true to the Gnome 2 ethos, how can you not support a multi-
      #  row panel? After all, not everyone likes to use workspaces! (I like
      #  one workspace, and a taskbar that can handle a dozen plus windows.)
      #
      # See also: "Window List With App Grouping 2.7"
      #  http://cinnamon-spices.linuxmint.com/applets/view/16
      # http://cinnamon-spices.linuxmint.com/uploads/applets/3IDA-0443-B57M.zip
      # WindowListGroup@jake.phy@gmail.com
      # 

      if false; then
        
        cd ~/Downloads
        wget -N \
          http://cinnamon-spices.linuxmint.com/uploads/applets/R9H5-FHOY-QOGM.zip
        unzip R9H5-FHOY-QOGM.zip -d multi_line_taskbar_applet
        /bin/rm -rf \
          ~/.local/share/cinnamon/applets/cinnamon-multi-line-taskbar-applet-master
        /bin/mv \
           multi_line_taskbar_applet/cinnamon-multi-line-taskbar-applet-master \
           ~/.local/share/cinnamon/applets/
        rmdir multi_line_taskbar_applet
     
        home_path=.local/share/cinnamon/applets/capture@rjanja
        /bin/cp \
          $MINT_FILES/home/$home_path/metadata.json \
          ~/$home_path/

      fi

      # Show hidden Startup Applications.
      # http://www.howtogeek.com/103640/
      #   how-to-make-programs-start-automatically-in-linux-mint-12/
      # sudo /bin/sed -i \
      #   's/NoDisplay=true/NoDisplay=false/g' /etc/xdg/autostart/*.desktop

    fi # end: if $WM_IS_CINNAMON

    # *** Additional Software

    # Configure Firefox.

    # FIXME: MAYBE: Do this... cp or maybe use m4.
    #cp ~/.mozilla/firefox/*.default/prefs.js ...
    ## Diff the old Firefox's file and the new Firefox's file?
    #cp ... ~/.mozilla/firefox/*.default/prefs.js

    # Install Chrome.
    #
    # NOTE: We should be okay to distribute Chrome. Per:
    #   https://www.google.com/intl/en/chrome/browser/privacy/eula_text.html
    #
    # "21.2 Subject to the Terms, and in addition to the license grant
    #  in Section 9, Google grants you a non-exclusive, non-transferable
    #  license to reproduce, distribute, install, and use Google Chrome
    #  solely on machines intended for use by your employees, officers,
    #  representatives, and agents in connection with your business
    #  entity, and provided that their use of Google Chrome will be
    #  subject to the Terms. ...August 12, 2010"
    #
    cd ~/Downloads
    wget -N \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo dpkg -i google-chrome-stable_current_amd64.deb

    # Firefox Google Search Add-On
    # Hrm, [lb] thinks the user has to do this themselves...
    #mkdir -p /ccp/opt/.downloads/firefox-google-search-add_on
    #cd /ccp/opt/.downloads/firefox-google-search-add_on
    #wget -N \
    #  https://addons.mozilla.org/firefox/downloads/file/157593/google_default-20120704.xml?src=search

    # Install Abode Reader.

    # NOTE: We cannot distribute Reader...
    #   cd /opt/Adobe/Reader9/bin
    #   sudo ./UNINSTALL
    if $INCLUDE_ADOBE_READER; then
      cd ~/Downloads
      wget -N \
        http://ardownload.adobe.com/pub/adobe/reader/unix/9.x/9.5.5/enu/AdbeRdr9.5.5-1_i486linux_enu.bin
      chmod a+x ./Adbe*.bin
      # Specify the install path otherwise the installer will ask us.
      sudo ./Adbe*.bin --install_path=/opt
      # Remove the Desktop icon that it creates.
      /bin/rm -f /home/$USER/Desktop/AdobeReader.desktop
    fi

    cd /opt/Adobe/Reader9/bin && sudo ./UNINSTALL

    # HTTPS Everywhere.
    #
    # See: https://www.eff.org/https-everywhere

    # NOTE: It looks like you have to install xpi via the
    #       browser. The CLI command is deprecated, it seems.
    # See: scripts/setup/auto_install/startup_eg.txt for a reminder to the
    #      user and instructions on setting up https everywhere and mouse
    #      gestures in both Firefox and Chrome.
    if false; then
      mkdir -p /ccp/opt/.downloads/https-everywhere
      cd /ccp/opt/.downloads/https-everywhere
      # 2014.01.28: The Firefox version is labeled "stable".
      wget -N https://www.eff.org/files/https-everywhere-latest.xpi
      # Hmmm... can't get cli install to work.
      #   sudo /bin/cp https-everywhere-latest.xpi /usr/lib/firefox/extensions/
      #   sudo chmod 664 /usr/lib/firefox/extensions/https-everywhere-latest.xpi
      #   #
      #   sudo /bin/cp https-everywhere-latest.xpi /usr/lib/firefox-addons/extensions/
      #   sudo chmod 664 /usr/lib/firefox-addons/extensions/https-everywhere-latest.xpi
      #   #
      #   sudo /bin/cp https-everywhere-latest.xpi /opt/firefox/extensions/
      #   sudo chmod 664 /opt/firefox/extensions/https-everywhere-latest.xpi
      #   #
      #   sudo unzip https-everywhere-latest.xpi -d \
      #  /usr/lib/firefox-addons/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384
      #   sudo /ccp/dev/cp/scripts/util/fixperms.pl --public \
      #  /usr/lib/firefox-addons/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384
    fi

    # Pidgin.

    # NOTE: In Cinnamon, Pidgin is hosed. I tried and tried to get Gmail to
    #       work but I just couldn't. Anyway, it works without any tweaking in
    #       MATE. Hooray!.

    # *** Finalize the custom panel thingies.

    if $WM_IS_CINNAMON; then

      # Rearrange all applets
      #
      # As noted above, the multi-line taskbar doesn't work, so don't exchange
      # the built-in window list:
      #   'panel1:left:3:window-list@cinnamon.org:37',
      # for the hopefully-fixed-soon-but-currently-broken-multi-line-window-list:
      #   'panel1:left:3:cinnamon-multi-line-taskbar-applet-master:18',
      #
      # The user applet seems worthless: it just accesses the panel settings,
      # lets you toggle panel edit mode, and lets you log off, same as options
      # you can find elsewhere in other panel applets.
      #   'panel1:right:7:user@cinnamon.org:5',
      #
      # The notifications applet also smells like a waste of space.
      #   'panel1:right:5:notifications@cinnamon.org:36',
      #
      # [lb] is still looking for a better window list applet. I choose not to
      # accept that people don't or shouldn't use the minimize action on a
      # window. I have lots of terminal windows for different things and I'm not
      # a workspace kinduv guy.
      #
      #  Cinnamon default:
      #    'panel1:left:5:window-list@cinnamon.org:37',
      #  Don't work:
      #    'panel1:left:5:cinnamon-multi-line-taskbar-applet-master:24',
      #    'panel1:left:3:windowPreviewWindowList@dalcde:25',
      #  Double-click icon to maximize window... weird. And, why?
      #    'panel1:left:3:window-list@zeripath.sdf-eu.org:26',
      #
      # [lb] is also annoyed that he can't stack his window list using multiple
      # rows. Not only does that save space, but then I can have, e.g., a
      # terminal that takes the top half of the screen and is logged onto the
      # production server and tailing all the logs be one icon in the window
      # list, and below that icon is another terminal that takes the bottom half
      # of the screen and is tailing the local client application logs. Duh!
      #
      #  Possible alternative window list applet that doesn't like look crap when
      #  you've got tons of windows open:
      #    'panel1:left:3:WindowListGroup@jake.phy@gmail.com:21',

      if false; then
        gsettings set org.cinnamon enabled-applets \
          "['panel1:left:0:menu@cinnamon.org:0',
            'panel1:left:1:panel-launchers@cinnamon.org:2',
            'panel1:left:2:show-desktop@cinnamon.org:1',
            'panel1:left:3:window-list@cinnamon.org:37',
            'panel1:right:0:systray@cinnamon.org:12',
            'panel1:right:1:sysmonitor@orcus:29',
            'panel1:right:2:capture@rjanja:18',
            'panel1:right:3:sound@cinnamon.org:10',
            'panel1:right:4:network@cinnamon.org:9',
            'panel1:right:5:weather@mockturtl:17',
            'panel1:right:6:calendar@cinnamon.org:13']"
      else
        # Try this if you want to experiment with the window list that groups
        # windows by application. It's kind of like how Windows 7 groups windows,
        # but clicking the icon in the window list is different: You can keep
        # clicking the icon to minimize each successive application window until
        # they're all minimized: which means, unlike Windows 7, clicking the icon
        # does not bring up a list of the application's windows; rather, you have
        # to hover over the icon to see a row of icons, but if you have a lot of
        # windows open, the row extends beyond the edges of the screen (WTF, it
        # makes the applet kind of useless). So, clicking the icon is different.
        # Also, once all windows are closed, then clicking just shows/hides the
        # last non-hidden application window. Also, there's no way to show all
        # windows of an application or to close all windows of an application.
        #
        # I guess I can try pinning gVim to all workspaces and just have
        # terminals on different work spaces?
        #
        # Interesting note: the number at the end of each string (after the
        # fourth colon) is just a unique ID? I notice that if two numbers match,
        # then only one applet appears, and maybe not where you expect....
        gsettings set org.cinnamon enabled-applets \
          "['panel1:left:0:menu@cinnamon.org:0',
            'panel1:left:1:panel-launchers@cinnamon.org:2',
            'panel1:left:2:show-desktop@cinnamon.org:1',
            'panel1:left:3:WindowListGroup@jake.phy@gmail.com:21',
         'panel1:left:4:window-list@cinnamon.org:37',
            'panel1:right:0:systray@cinnamon.org:12',
         'panel1:right:1:windows-quick-list@cinnamon.org:28',
            'panel1:right:3:sysmonitor@orcus:29',
            'panel1:right:4:capture@rjanja:18',
            'panel1:right:5:sound@cinnamon.org:10',
            'panel1:right:6:network@cinnamon.org:9',
            'panel1:right:7:weather@mockturtl:17',
            'panel1:right:8:calendar@cinnamon.org:13',
         'panel1:right:9:workspace-switcher@cinnamon.org:31'
            ]"
      fi

      # Copy .desktop entry files before making them panel launchers.
      home_path=.cinnamon/panel-launchers
      /bin/mkdir -p /home/$USER/.cinnamon/panel-launchers
      # It's not quite this simple:
      #   /bin/cp $MINT_FILES/home/$home_path/*.desktop ~/$home_path/
      # We can't use environment variables, and since some of the
      #   executables (like .dubs/bin/*) live in the user's directory,
      #   we have to set the path according to the user name.
      # See also: http://heath.hrsoftworks.net/archives/000198.html
      #   "Enable for loops over items with spaces in their name."
      #   We don't really need to change IFS, but it's good form.
      #   ... unless you never use spaces in your file names.
      OLD_IFS=$IFS
      IFS=$'\n'
      # Huh. I guess the wildcard doesn't work in the quotes.
      #  for dir in `ls "$MINT_FILES/home/$home_path/*.desktop"`
      for dtop_file in `ls $MINT_FILES/home/$home_path/*.desktop`;
      do
        #echo $dtop_file
        m4 --define=TARGETUSER=$USER \
          $dtop_file \
          > ~/$home_path/`basename $dtop_file`
      done
      # Similar to: IFS=$' \t\n'
      IFS=$OLD_IFS
      # You can view the IFS using: printf %q "$IFS".

      # Rearrange the Panel launchers
      gsettings set org.cinnamon panel-launchers \
        "['firefox.desktop',
          'google-chrome.desktop',
          'gvim-ccp.desktop',
          'meld-ccp.desktop',
          'gnome-terminal.desktop',
          'openterms-all.desktop',
          'openterms-dbms.desktop',
          'openterms-logs.desktop',
          'openterms-logc.desktop',
          'gnome-screenshot.desktop',
          'dia-ccp.desktop',
          'acroread-ccp.desktop',
          'wireshark.desktop']"

      # Customize the Mint Menu: Change icon and remove text label.

      # MAYBE: Use /bin/sed instead, since you're just changing two values.
      home_path=.cinnamon/configs/menu@cinnamon.org
      /bin/cp -f \
        $MINT_FILES/home/$home_path/menu@cinnamon.org.json \
        ~/$home_path/

    fi # end: if $WM_IS_CINNAMON

    if $WM_IS_MINT; then

      #dconf write /org/mate/panel/objects/clock/position 0
      #dconf write /org/mate/panel/objects/clock/panel-right-stick true

      # From the Mint Menu in the lower-left, remove the text and change the
      # icon (to a playing die with five pips showing).
      USER_BGS=/home/$USER/Pictures/.backgrounds
      /bin/cp \
        $USE_MINT_MENU_ICON \
        ${USER_BGS}/mint_menu_custom.png
      gsettings set com.linuxmint.mintmenu applet-icon \
        "${USER_BGS}/mint_menu_custom.png"
      gsettings set com.linuxmint.mintmenu applet-icon-size 22
      gsettings set com.linuxmint.mintmenu applet-text ''

    fi # end: if $WM_IS_MINT

    # *** Install Cyclopath

    if ! $EXCLUDE_CYCLOPATH; then

      echo
      echo "Installing Cyclopath..."

      echo
      echo -n "Fixing permissions before overlay... "
      sudo $USE_CCPDFILES/scripts/util/fixperms.pl --public /ccp/ \
        > /dev/null 2>&1
      echo "ok"

      # Reset the positional parameters
      masterhost=$HOSTNAME
      targetuser=$USER
      isbranchmgr=0
      isprodserver=0
      reload_databases=0
      svn_update_sources=0
      git_update_sources=0
      set -- $masterhost $targetuser $isbranchmgr $isprodserver \
             $reload_databases $svn_update_sources $git_update_sources
      # This script is meant for user-managed machines, i.e., not those on the CS
      # net, where [[ "$MACHINE_DOMAIN" == "cs.umn.edu" ]], targetgroup=grplens.
      targetgroup=$USE_CYCLOP_GROUP

      echo
      echo "Using params: $*"

      # We called dir_prepare already:
      #  $script_absbase/dir_prepare.sh $*

      # Setup third-party dev docs locally.
      cd $AUTO_INSTALL
      ./usr_dev_doc.sh $*

      # Setup Apache and Postgresql.
      cd $AUTO_INSTALL
      ./etc_overlay.sh $*
      #
      # We wait until now to install postgresql.conf, otherwise the server won't
      # start: it complains are the shared memory settings, or, our /ccp/var/log
      # folder doesn't exist, which also causes it not to start (and not to log).
      touch /ccp/var/log/postgresql/postgresql-9.1-main.log
      sudo chown postgres /ccp/var/log/postgresql/postgresql-9.1-main.log
      sudo chmod 664 /ccp/var/log/postgresql/postgresql-9.1-main.log
      tot_sys_mem=`cat /proc/meminfo | grep MemTotal | /bin/sed s/[^0-9]//g`
      PGSQL_SHBU=$(($tot_sys_mem / 3))kB
      m4 \
        --define=PGSQL_SHBU=$PGSQL_SHBU \
          $MINT_FILES/etc/postgresql/${POSTGRESABBR}/main/postgresql.conf \
        | sudo tee /etc/postgresql/${POSTGRESABBR}/main/postgresql.conf \
        &> /dev/null
      sudo /etc/init.d/postgresql restart

      # Setup the debug flash player.
      cd $AUTO_INSTALL
      # NOTE: The npconfig commands indicate a particular failure, but the plugin
      #       seems to work just fine.
      #       "And create symlink to plugin in /usr/lib/mozilla/plugins: failed!"
      ./flash_debug.sh $*

      # Compile the GIS suite.
      cd $AUTO_INSTALL
      ./gis_compile.sh $*

      # Prepare Cyclopath so user can hit http://ccp

      cd $AUTO_INSTALL
      USE_DOMAIN=$USE_DOMAIN \
        USE_DATABASE_SCP=$USE_DATABASE_SCP \
        CHECK_CACHES_BR_LIST="\"minnesota\" \"Minnesota\" \"minnesota\" \"Metc Bikeways 2012\"" \
        reload_databases=1 \
          ./prepare_ccp.sh $*

      # MAYBE: Copy or build tiles. Maybe setup cron jobs?

    fi # end: if $EXCLUDE_CYCLOPATH; then

    # *** Make one last configy dump.

    # One of the sudo installs must've installed root files in the user's home
    # directory, but not to worry: it's an empty file. But fix its perms.
    sudo chown -R $USER:$USER /home/$USER/.config/menus

    if $MAKE_CONF_DUMPS; then
      cd ~/Downloads
      user_home_conf_dump "usr_04b"
    fi

    # *** Make the fake /export/scratch, if you're a remote lab dev.

    sudo mkdir -p /export/scratch
    sudo chmod 2755 /export
    sudo chmod 2755 /export/scratch
    sudo ln -s /ccp /export/scratch/ccp

    # *** Cleanup/Post-processing

    # For now, keep the .install directory.
    if false; then
      if [[ -d /ccp/var/.install ]]; then
        /bin/rm -rf /ccp/var/.install
      fi
    fi

    # Be nice and update the user's `locate` database.
    # (It runs once a day, but run it now because we
    # might make a virtual machine image next.)
    sudo updatedb

    # *** Print a reminder(s)

    echo
    #cat startup_eg.txt
    cat ${script_absbase}/reminders.txt
    echo

    print_install_time

    echo
    echo "Thanks for installing Cyclopath!"
    echo

    exit 0

  fi

# end: if [[ ! -e /ccp/dev/cp/flashclient/build/main.swf ]]; then ... fi
else

  echo
  echo "WARNING: Script failure: Do what now?"
  exit 1

fi

