#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script. If it produces any output, it
# failed.

# FIXME: Should probably check distro and version.
#        cat /etc/issue | grep "^Linux Mint 16"
#        cat /etc/issue | grep "^Fedora release 14"
#        cat /etc/issue | grep "^Ubuntu 12.04"
#
if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
  # echo Ubuntu!

  # *** Installed Packages

  # Manually installed by Systems
  aptitude show                \
   apache2                     \
   ia32-libs                   \
   libagg-dev                  \
   libapache2-mod-python       \
   libedit-dev                 \
   libgd2-xpm-dev              \
   libpam0g-dev                \
   libxslt1-dev                \
   logcheck                    \
   logcheck-database           \
   nspluginwrapper             \
   par                         \
   postgresql                  \
   postgresql-server-dev-9.1   \
   pylint                      \
   python-dev                  \
   python-imaging              \
   python-levenshtein          \
   python-setuptools           \
   python-simplejson           \
   socket                      \
   | grep "^State:"            \
   | grep -v "^State: installed$"
   #postgresql-8.4              \
   #postgresql-filedump-8.4     \
   #postgresql-server-dev-8.4   \
   # 2014.01.17: Mint 16: Is this just libproj0 and libproj-dev?
   #proj                        \

   # Required for conflation:
   # MAYBE: Make a ccp_install setting for scipy et al.
   #libatlas-base-dev           \
   #libatlas-cpp-0.6-dev        \
   #libblas-dev                 \
   #python-scipy                \

   # 2013.06.10: On Ubuntu 12.04, python-profiler is not a real package?
   # So, it's found, it's just not real? Maybe we can just install it
   # ourselves... unless maybe it needs sudo to profile.
   #    landonb@bad:scratch$ aptitude show python-profiler
   #    No current or candidate version found for python-profiler
   #    Package: python-profiler
   #    State: not a real package
   #    Provided by: python
   #python-profiler             \

  # Automatically installed
  # FIXME: Need to abstract 9.1 v. 8.4...
  aptitude show                \
   apache2-mpm-worker          \
   apache2-utils               \
   e2fsprogs                   \
   libpq-dev                   \
   meld                        \
   pidgin                      \
   postgresql-common           \
   postgresql-client-9.1       \
   postgresql-client-common    \
   | grep "^State:"            \
   | grep -v "^State: installed$"
   #postgresql-client-8.4       \
   # 2014.01.17: Mint 16: Gone:
   #apache2.2-common            \
   #openoffice.org              \

  # Dependently installed (required)
  aptitude show                \
   logtail                     \
   python-egenix-mxdatetime    \
   python-egenix-mxtools       \
   python-logilab-astng        \
   python-logilab-common       \
   | grep "^State:"            \
   | grep -v "^State: installed$"

  # Not needed:
# FIXME: the next two are actually needed
  #  libxerces-c28 # Actually, yes
  #  libhdf5-serial-1.8.4 # Same here
  #  libogdi3.2
  #  libgeos-3.1.0 [Ubuntu 10.04]
  #  libgeos-3.2.0 [Ubuntu 11.04]
  #  libgeos-c1
  #  libhdf4-0-alt
  #  unixodbc

  # Dependently installed (other)
  aptitude show                \
   build-essential             \
   git-core                    \
   libipc-signal-perl          \
   libmime-types-perl          \
   libproc-waitstat-perl       \
   libproj-dev                 \
   libproj0                    \
   mime-construct              \
   proj-bin                    \
   proj-data                   \
   python-logilab-astng        \
   python-logilab-common       \
   | grep "^State:"            \
   | grep -v "^State: installed$"
  # 2013.06.10: python-profiler is missing on bad.
  # The comment above says this is a dependency for
  # something else -- what is that something else or
  # don't we care?
  # python-profiler             \
  # In Ubuntu 12 but not Mint 16:
  # libgd2-xpm                  \

  #
  #if [[ -n "`cat /etc/issue | grep '^Ubuntu 12.04'`" ]]; then
  #   #libnetcdf6                
  #  aptitude show              \
  #   | grep "^State:"          \
  #   | grep -v "^State: installed$"
  #elif [[ -n "`cat /etc/issue | grep '^Ubuntu 11.04'`" ]]; then
  #   #libnetcdf6                
  #  aptitude show              \
  #   | grep "^State:"          \
  #   | grep -v "^State: installed$"
  #elif [[ -n "`cat /etc/issue | grep '^Ubuntu 10.04'`" ]]; then
  #   #libnetcdf4                
  #  aptitude show              \
  #   | grep "^State:"          \
  #   | grep -v "^State: installed$"
  #else
  #  echo "Warning: Unexpected host OS."
  #fi

  # NOTE: odbcinst and odbcinst1debian2 (Ubuntu 11.04) 
  #                  / odbcinst1debian1 (Ubuntu 10.04)
  #       get dependently installed when Systems does it for a dev machine, but
  #       not for a production machine. I [lb] ran the scripts and it appears
  #       not to be necessary.

  # *** Uninstalled Packages

  # Manually uninstalled by Systems
  # FIXME: Abstract Postgres version, i.e., 8.4 v. 9.1.
  aptitude show                \
   gdal-bin                    \
   libgdal1-dev                \
   libgeos-dev                 \
   postgis                     \
   postgresql-9.1-postgis      \
   python-psycopg2             \
   | grep "^State:"            \
   | grep -v "^State: not installed$"
   #postgresql-8.4-postgis      \

  # These should not be installed but it's really okay if they are:
  #  python-gdal                 \
  #  libgdal1-1.6.0              \

elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
  # echo Red Hat!
  
  # FIXME: Implement

  : # no-op

else

  echo "Error: Unknown OS!"
  exit 1

fi

exit 0

