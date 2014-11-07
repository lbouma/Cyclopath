#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: call this script from another script.
#

# *** Installed Packages

# Manually installed by Systems
#
aptitude show apache2                     | pcregrep -M 'Package:.*\nState: not installed'
aptitude show ia32-libs                   | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libagg-dev                  | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libapache2-mod-python       | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libedit-dev                 | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libgd2-xpm-dev              | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libpam0g-dev                | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libxslt1-dev                | pcregrep -M 'Package:.*\nState: not installed'
aptitude show logcheck                    | pcregrep -M 'Package:.*\nState: not installed'
aptitude show logcheck-database           | pcregrep -M 'Package:.*\nState: not installed'
aptitude show nspluginwrapper             | pcregrep -M 'Package:.*\nState: not installed'
aptitude show par                         | pcregrep -M 'Package:.*\nState: not installed'
aptitude show postgresql                  | pcregrep -M 'Package:.*\nState: not installed'
aptitude show postgresql-server-dev-9.1   | pcregrep -M 'Package:.*\nState: not installed'
# [lb]: FIXME: Erm, do we need Ubuntu-specific package lists?
#aptitude show postgresql-8.4              | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-filedump-8.4     | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-server-dev-8.4   | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-9.1              | pcregrep -M 'Package:.*\nState: not installed'
# These are not necessary?:
#aptitude show postgresql-filedump-9.1     | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-server-dev-9.1   | pcregrep -M 'Package:.*\nState: not installed'
aptitude show proj                        | pcregrep -M 'Package:.*\nState: not installed'
aptitude show pylint                      | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-dev                  | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-imaging              | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-levenshtein          | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-profiler             | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-setuptools           | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-simplejson           | pcregrep -M 'Package:.*\nState: not installed'
aptitude show socket                      | pcregrep -M 'Package:.*\nState: not installed'
# These are necessary for conflation but can be manually compiled-installed.
#aptitude show libatlas-base-dev           | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show libatlas-cpp-0.6-dev        | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show libblas-dev                 | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show python-scipy                | pcregrep -M 'Package:.*\nState: not installed'
#
#

# Automatically installed
#
aptitude show apache2-mpm-worker          | pcregrep -M 'Package:.*\nState: not installed'
aptitude show apache2-utils               | pcregrep -M 'Package:.*\nState: not installed'
aptitude show apache2.2-common            | pcregrep -M 'Package:.*\nState: not installed'
aptitude show e2fsprogs                   | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libpq-dev                   | pcregrep -M 'Package:.*\nState: not installed'
aptitude show meld                        | pcregrep -M 'Package:.*\nState: not installed'
aptitude show openoffice.org              | pcregrep -M 'Package:.*\nState: not installed'
aptitude show pidgin                      | pcregrep -M 'Package:.*\nState: not installed'
aptitude show postgresql-common           | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-client-8.4       | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show postgresql-client-9.1       | pcregrep -M 'Package:.*\nState: not installed'
aptitude show postgresql-client          | pcregrep -M 'Package:.*\nState: not installed'
aptitude show postgresql-client-common    | pcregrep -M 'Package:.*\nState: not installed'
#
#

# Dependently installed (required)
#
aptitude show logtail                     | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-egenix-mxdatetime    | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-egenix-mxtools       | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-logilab-astng        | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-logilab-common       | pcregrep -M 'Package:.*\nState: not installed'
#
#

# Dependently installed (other)
#
aptitude show build-essential             | pcregrep -M 'Package:.*\nState: not installed'
aptitude show git-core                    | pcregrep -M 'Package:.*\nState: not installed'
#aptitude show libgd2-xpm                  | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libipc-signal-perl          | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libmime-types-perl          | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libproc-waitstat-perl       | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libproj-dev                 | pcregrep -M 'Package:.*\nState: not installed'
aptitude show libproj0                    | pcregrep -M 'Package:.*\nState: not installed'
aptitude show mime-construct              | pcregrep -M 'Package:.*\nState: not installed'
aptitude show proj-bin                    | pcregrep -M 'Package:.*\nState: not installed'
aptitude show proj-data                   | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-logilab-astng        | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-logilab-common       | pcregrep -M 'Package:.*\nState: not installed'
aptitude show python-profiler             | pcregrep -M 'Package:.*\nState: not installed'
#
#

# NOTE: odbcinst* is installed on dev. machines but really isn't necessary.
#if [[ -n "`cat /etc/issue | grep '^Ubuntu 12.04'`" ]]; then
#  #aptitude show libnetcdf6                | pcregrep -M 'Package:.*\nState: not installed'
#  #aptitude show odbcinst1debian2          | pcregrep -M 'Package:.*\nState: not installed'
#  :
#elif [[ -n "`cat /etc/issue | grep '^Ubuntu 11.04'`" ]]; then
#  #aptitude show libnetcdf6                | pcregrep -M 'Package:.*\nState: not installed'
#  #aptitude show odbcinst1debian2          | pcregrep -M 'Package:.*\nState: not installed'
#  :
#elif [[ -n "`cat /etc/issue | grep '^Ubuntu 10.04'`" ]]; then
#  #aptitude show libnetcdf4                | pcregrep -M 'Package:.*\nState: not installed'
#  #aptitude show odbcinst1debian1          | pcregrep -M 'Package:.*\nState: not installed'
#  :
#else
#  echo "Warning: Unexpected host OS."
#fi

# Not needed:
#  aptitude show libgdal1-1.6.0              | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libgeos-3.1.0               | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libgeos-3.2.0               | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libgeos-c1                  | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libhdf4-0-alt               | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libhdf5-serial-1.8.4        | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libogdi3.2                  | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show libxerces-c28               | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show python-gdal                 | pcregrep -M 'Package:.*\nState: not installed'
#  aptitude show unixodbc                    | pcregrep -M 'Package:.*\nState: not installed'

# *** Uninstalled Packages

#
#
aptitude show gdal-bin                    | pcregrep -M 'Package:.*\nState: installed'
aptitude show libgdal1-dev                | pcregrep -M 'Package:.*\nState: installed'
aptitude show libgeos-dev                 | pcregrep -M 'Package:.*\nState: installed'
aptitude show postgis                     | pcregrep -M 'Package:.*\nState: installed'
aptitude show postgresql-8.4-postgis      | pcregrep -M 'Package:.*\nState: installed'
aptitude show python-psycopg2             | pcregrep -M 'Package:.*\nState: installed'
#
#

# return 0, or if the last command failed, the parent exits.
exit 0

