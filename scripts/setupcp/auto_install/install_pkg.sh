#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script. If it produces any output, it
# failed.

# FIXME: This should be a different apt-get command for each distro
#        and each distro version. For now, this just works on Mint 16.
#        cat /etc/issue | grep "^Linux Mint 16"
#        cat /etc/issue | grep "^Fedora release 14"
#        cat /etc/issue | grep "^Ubuntu 12.04"

if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
  # echo Ubuntu!

  # See Install_Notes/Linux_Mint_16 on the text wiki.

  sudo apt-get install \
    \
    dkms \
    build-essential \
    vim-gnome \
    meld \
    apache2 \
    apache2-threaded-dev \
    libxml2-dev \
    libjpeg-dev \
    libpng++-dev \
    mysql-server \
    libapache2-mod-php5 \
    php5-mysql \
    postgresql \
    postgresql-server-dev-9.1 \
    libgd-dev \
    imagemagick \
    libmagick++-dev \
    texlive \
    autoconf \
    git \
    libicu48 \
    libicu-dev \
    php5-dev \
    dh-make-php \
    fakeroot \
    libicu48 \
    libicu-dev \
    xsltproc \
    vsftpd \
    libcurl3 \
    exuberant-ctags \
    par \
    xdotool \
    wmctrl \
    subversion \
    pcregrep \
    dia \
    wireshark \
    \
    ia32-libs \
    libgd-dev \
    libgd2-xpm-dev \
    libagg-dev \
    libapache2-mod-python \
    libedit-dev \
    libpam0g-dev \
    libxslt1-dev \
    logcheck \
    logcheck-database \
    nspluginwrapper \
    pylint \
    python-dev \
    python-levenshtein \
    python-setuptools \
    python-simplejson \
    socket \
    apache2-mpm-worker \
    apache2-utils \
    postgresql-client \
    logtail \
    python-egenix-mxdatetime \
    python-egenix-mxtools \
    python-logilab-astng \
    python-logilab-common \
    git-core \
    libipc-signal-perl \
    libmime-types-perl \
    libproc-waitstat-perl \
    libproj-dev \
    libproj0 \
    mime-construct \
    proj-bin \
    proj-data \
    python-logilab-astng \
    python-logilab-common

    # 2014.01.17: These used to be installed. So we might need some of these.
    #libatlas-base-dev           \
    #libatlas-cpp-0.6-dev        \
    #libblas-dev                 \
    #python-profiler             \
    #python-scipy                \
    #proj                        \
    #python-imaging              \
    #apache2.2-common            \
    #e2fsprogs                   \
    #libpq-dev                   \
    #postgresql-common           \
    #postgresql-client-8.4       \
    #postgresql-client-common    \
    #libnetcdf4                  \
    #odbcinst                    \
    #odbcinst1debian1
    #sendmail

elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
  # echo Red Hat!
  
  # FIXME: Implement

else

  echo "Error: Unknown OS!"
  exit 1

fi;

exit 0

