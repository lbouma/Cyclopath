#!/bin/bash

# Copyright (c) 2006-2013, 2016 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: This file is not used. It exists for documentary purposes.
#       [lb] tried to install this code to get at a
#       SciPy and also at a Travelling Salesperson Problem solver.
#       For SciPy, we've asked Operator to just run apt-get;
#       for a TSP solver, see Concorde TSP, installed by gis_compile.py.
#       
#       
echo "NOT USED: tsp_ignored.sh"
exit 1

echo
echo "Installing TSP software"

# *** Choke on error.

set -e

#script_relbase=$(dirname $0)
#script_absbase=`pwd $script_relbase`
echo "SCRIPT_DIR=\$(dirname \$(readlink -f $0))"
SCRIPT_DIR=$(dirname $(readlink -f $0))

# SYNC_ME: This block of code is shared.
#    NOTE: Don't just execute the check_parms script but source it so its
#          variables become ours.
. ${SCRIPT_DIR}/check_parms.sh $*
# This sets: masterhost, targetuser, isbranchmgr, isprodserver,
#            reload_databases, PYTHONVERS, and httpd_user.

# Make a spot for the downloads...

#mkdir -p /ccp/opt/.downloads

# *** Use machine's GCC, not System's.

# On the CS network, MODULESHOME is set.
if [[ -n "$MODULESHOME" ]]; then
  . ${MODULESHOME}/init/sh
  module unload soft/gcc/4.5.2
fi

# ***

# *** Silly, Silly OOFramework!

# See also: gix_compile.sh installs NumPy and networkx.

# 2013.05.08: The following libraries:
#
#   LAPACK — Linear Algebra PACKage
#   GLPK (GNU Linear Programming Kit)
#   ATLAS (Automatically Tuned Linear Algebra Soft)
#   SciPy
#   OpenOPT Framework
#   DSDP -- Software for Semidefinite Programming
#   CVXOPT -- Python Software for Convex Optimization
#
#   were installed by [lb] trying to get a TSP solution
#   working -- I was under the disillusion that OpenOPT's
#   TSP library would be simple to install and work well.
#
#   Ha!
#
#   My first chance to decide to not use OpenOPT was when
#   I first came across its Web site, shamelessly colorful
#   and full of distracting, dancing widgets. Who wants to
#   partay like it's nineteen ninety nine?
#
#   My next chance to decide to not use OpenOPT was going
#   through dependencies. OO claimed to only need one or two,
#   but each of those needed a few more. Fortunately, most of
#   the libraries were easy to find, download and install. But
#   some were tricky to build (I love reading incorrect build
#   instructions on the project page and find the correct ones
#   in discussion threads elsewhere). And others would build
#   but will then something obscure would fail -- in one case
#   because the library was too recent for another library and
#   its old, deprecated API had finally been removed.
#
#   Then there's the fact that it's OOFramework. They have a
#   beautiful Web page straight out of 1999. They have lots of
#   seemingly good usage examples. But my experience trying to
#   get TSP to run was dismal. No matter how I messed with the
#   weights, I couldn't get any of the solvers to pick the best
#   path, which meant I couldn't really solve my TSP problem. Not
#   to be picky, but I want a perfect solution. Also, not being
#   able to effectively set weights meant that I couldn't weight
#   one node so heavily on input that no one would go there (start
#   node) and weight another node so much on output that no one
#   would leave there (finish node). So either I was messing up
#   something that seems like it should be super simple, or the
#   OOFramework TSP is wrong or not documented correctly/well.
#
#   Given a normal networkx directed graph, e.g., where [{2,3,1.0},{3,2,2.0}]
#   means nodes 2 and 3 connect and 2->3 is a cost of 1.0 and the reverse is a
#   cost of 2.0, I thought this might work, given documentation at OO's nook:
#
#     from openopt import *
#     import networkx as nx
#
#     my_graph = [
#      (0, 1, .01,), (0, 2, .01,), (0, 4, .01,),
#      # NOTE: No (1, *) because you can't leave node 1 (final node).
#      (2, 0, .01,), (2, 1, .01,), (2, 4, .01,),
#      # NOTE: No (*, 3) because you can't enter node 3 (start node).
#      (3, 0, .13,), (3, 1, .12,), (3, 2, .11,), (3, 4, .01,),
#      (4, 0, .01,), (4, 1, .01,), (4, 2, .01,),]
#
#     G = nx.DiGraph()
#     G.add_node(1) # Since we didn't define any edges.
#     G.add_weighted_edges_from(my_graph)
#
#     # Trying the 'glpk' solver.
#
#     p = TSP(G, objective='cost', goal='min', start=0, returnToStart=False)
#     r = p.solve('sa')
#     # oologfcn.OpenOptException: input graph has node 1 that does not lead
#     #                            to any other node; solution is impossible
#     ...
#
#     # Add the missing nodes to make OO happy...
#     G.add_weighted_edges_from(
#       [(1, 0, 100.0,), (1, 2, 100.0,), (1, 4, 100.0,),])
#
#     # Trying min again:
#     p = TSP(G, objective='cost', goal='min', start=0, returnToStart=False)
#     r = p.solve('sa')
#     print(r.Edges)
#     # [(3, 2, {'weight': 0.11}), # WRONG: (3,4) only costs 0.01.
#     #  (2, 0, {'weight': 0.01}),
#     #  (0, 4, {'weight': 0.01}),
#     #  (4, 1, {'weight': 0.01})] # CORRECT: Final node!
#     #
#     # Trying max:
#     p = TSP(G, objective='cost', goal='max', start=0, returnToStart=False)
#     r = p.solve('sa')
#     print(r.Edges)
#     # [(3, 2, {'weight': 0.11}),
#     #  (2, 1, {'weight': 0.01}),
#     #  (1, 4, {'weight': 100.0}), # WRONG: Final node, drr!
#     #  (4, 0, {'weight': 0.01})]
#
#     # Trying the 'glpk' solver.
#     p = TSP(G, objective='cost', goal='min', start=0, returnToStart=False)
#     r = p.solve('glpk')
#     # oologfcn.OpenOptException: input graph has node 3 that has no edge
#     #                            from any other node; solution is impossible
#     ...
#
#     # Add the missing nodes to make OO happy...
#     G.add_weighted_edges_from(
#       [(0, 3, 100.0,), (2, 3, 100.0,), (4, 3, 100.0,),])
#
#     # Trying min again:
#     p = TSP(G, objective='cost', goal='min', start=0, returnToStart=False)
#     r = p.solve('glpk')
#     print(r.Edges)
#     # [(3, 1, {'weight': 0.12}),
#     #  (1, 2, {'weight': 100.0}), # WRONG: Final node, drr!
#     #  (2, 0, {'weight': 0.01}),
#     #  (0, 4, {'weight': 0.01})]
#     #
#     # Trying max:
#     p = TSP(G, objective='cost', goal='max', start=0, returnToStart=False)
#     r = p.solve('glpk')
#     print(r.Edges)
#     # [(3, 4, {'weight': 0.01}),
#     #  (4, 1, {'weight': 0.01}),
#     #  (1, 2, {'weight': 100.0}), # WRONG: Final node, drr!
#     #  (2, 0, {'weight': 0.01})]
#
#   As seen above, on a graph with five nodes where you can't leave the finish
#   node, and where all but one of the exits of the start node is expensive,
#   the algorithm (a) won't always pick the least expensive start node exit,
#   and (b) won't always visit the finish node last. So frustrating!!
#   (Though, in the examples, I see 'time' as another parameter, so maybe
#   I just needed to specify a time and a weight... bah, whatever, the alleyoop
#   service uses an awesome custom-build permutation iterator and its own TSP
#   that can handle first and final destinations.)
#
#   But really [lb] is happy that networkx does TSP (well, it kinda does
#   TSP, it really just calculates all possible paths and then we look for
#   Hamiltonian cycles and decide which one is the shortest (a Hamiltonian
#   cycle visits every node in a graph)). To be honest, I skipped past networkx
#   because it's so generic (which I guess TSP is, too) and also because most
#   TSP chatter online is about "constraint programming"... which is way, way
#   too complex for me. I'm also guessing my search terms weren't optimal, even
#   though you'd expect "python travelling salesperson" or "networkx visit
#   all nodes" to be hit-worthy. I guess I'm just not a graph theorist, so I
#   don't know the correct terms.
#
#   I'm also happy to finally have an excuse to use networkx, since I've seen
#   it before and have been impressed by its simplicity. I think [rp] used it
#   for the original route finder, before just brewing his own solution (using
#   simple Python lookups of nodes and edges and using the norvig library to
#   find the shortest path). And I think [cd] may have looked into networkx
#   when researching finders for multimodal (she picked GraphServer).
#
#   Anywhoway, I'm keeping this code and for some reason deciding to keep this
#   blathering comment. The install code below I'm keeping because I've
#   installed these libraries on my development machine, and I like to keep
#   records of installed code; also because if new code doesn't work on new
#   machines, it might be because maybe one of the libraries below really
#   does need to be installed. And this comment I'm just keeping, mostly
#   because I don't want to visit OOFramework ever again, and I want to
#   remember my experience with it to be sure I remember not to revisit
#   OOFramework ever again. (No offense to OOFramework, you seem like a very
#   nice piece of software, but I think we just got off on the wrong foot.)
#
#   See the alleyoopcat service for the TSP implementation that uses just
#   networkx.all_simple_paths.
#

__ignore_me () {

  # *** LAPACK — Linear Algebra PACKage

  # http://www.netlib.org/lapack/

  cd /ccp/opt/.downloads
  wget -N http://www.netlib.org/lapack/lapack-3.4.2.tgz
  /bin/rm -rf /ccp/opt/.downloads/lapack-3.4.2
  tar xvf lapack-3.4.2.tgz \
    > /dev/null
  cd /ccp/opt/.downloads/lapack-3.4.2

  # [lb] has problems with the real download. It makes static libs or something
  # and OOFramework wants shared... and I tried the -fPIC trick (editing
  # make.inc and compiling shared libraries...).
  #
  #   cp make.inc.example make.inc
  #   make
  #
  # Meh. I found some autoconf wrapper files someone wrote. Download them and
  # unpack them on top of the lapack files.

  cd /ccp/opt/.downloads/lapack-3.4.2
  wget -N http://users.wfu.edu/cottrell/lapack/lapack-3.4.0-autoconf.tar.gz
  #/bin/rm -rf /ccp/opt/.downloads/lapack-3.4.0-autoconf
  ## This archive extracts not to its own folder so make one.
  #mkdir lapack-3.4.0-autoconf
  #/bin/cp lapack-3.4.0-autoconf.tar.gz lapack-3.4.0-autoconf/
  #cd lapack-3.4.0-autoconf
  tar xvf lapack-3.4.0-autoconf.tar.gz \
    > /dev/null
  #/bin/rm lapack-3.4.0-autoconf.tar.gz

  # Now we can do a proper build using ./configure.
  ./configure --prefix=/ccp/opt/lapack
  make
  make check
  make install

  # *** GLPK (GNU Linear Programming Kit)

  # CVXOPT uses GLPK.

  # Argh. "As of version 4.49, developers must migrate to these new APIs. The
  # old API routines, whose names begin with lpx_, have now been removed from
  # the AGLPK API and are no longer available."
  #   http://ftp.gnu.org/gnu/glpk/glpk-4.48.tar.gz
  #
  # So don't use, i.e., 4.49 and above...
  #
  # (note that `make uninstall` seems to have worked for [lb] to remove 4.49.

  cd /ccp/opt/.downloads
  wget -N http://ftp.gnu.org/gnu/glpk/glpk-4.48.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/glpk-4.48
  tar xvf glpk-4.48.tar.gz \
    > /dev/null
  cd /ccp/opt/.downloads/glpk-4.48

  ./configure --prefix=/ccp/opt/glpk
  make
  make check
  make install

  # Wire the library to everyone's path.
  #
  # MAYBE: This code C.f. elsewhere. Make a common fcn.
  #
  if [[ "`cat /etc/ld.so.conf \
        | grep '/ccp/opt/glpk/lib'`" ]]; then
    # No-op. Entry already exists.
    echo "Skipping ld.so.conf"
  else
    RANDOM_NAME=/tmp/ccp_setup_lj123gklj094dfjklh234asd1234
    mkdir $RANDOM_NAME
    cp /etc/ld.so.conf $RANDOM_NAME/
    echo "/ccp/opt/glpk/lib" >> $RANDOM_NAME/ld.so.conf
    sudo cp $RANDOM_NAME/ld.so.conf /etc/ld.so.conf
    # The tmp file is owned by the script runner but the sudo cp preserves
    # the original 664 root root perms.
    # Cleanup.
    /bin/rm -f $RANDOM_NAME/ld.so.conf
    rmdir $RANDOM_NAME
  fi
  #
  # Configure dynamic linker run-time bindings (reload ld.so.conf).
  sudo ldconfig
  #
  sudo -v # keep sudo alive

  # *** ATLAS (Automatically Tuned Linear Algebra Soft)

  # http://math-atlas.sourceforge.net/

  # Needed by NumPy, SciPy, OOFramework.

  # Turn off CPU throttling when installing ATLAS.
  #   /usr/bin/cpufreq-selector -g performance
  # But, sudo /usr/bin/cpufreq-selector, says
  #   "No cpufreq support"
  # See also:
  #   ls -la /sys/devices/system/cpu
  # and you shouldn't find, e.g.,
  #   DNE: /sys/devices/system/cpu/cpu[0-9]+/cpufreq/scaling_governor
  #
  # For each processor:
  #   cpufreq-selector -c 0 -g performance
  #   cpufreq-selector -c 1 -g performance
  #   etc.

  # Find out my CPU speed.
  #   cat /proc/cpuinfo
  # says
  #    cpu MHz : 2632.143

  # To parse the whole number part:
  #  cpu_mhz=`cat /proc/cpuinfo | grep 'cpu MHz' | sed "s/[^0-9]*\([0-9]\+\)\..*/\1/g"`
  # To parse the whole floating point number:

  cd /ccp/opt/.downloads
  # # wget -N http://sourceforge.net/projects/math-atlas/files/latest/download?source=files
  #  wget -N http://sourceforge.net/projects/math-atlas/files/Stable/3.10.1/atlas3.10.1.tar.bz2/download
  # # On Ubuntu, the wget -N http...download?source=file leaves:
  # if [[ -e "download?source=files" ]]; then
  #   /bin/mv "download?source=files" atlas3.10.1.tar.bz2
  # fi
  # # On Ubuntu, the wget -N http...download leaves:
  # if [[ -e "download" ]]; then
  #   /bin/mv "download" atlas3.10.1.tar.bz2
  # fi
  # # and of course on Fedora wget saves to the correct file...
  #
  # So why don't we just use -O instead...
  wget -N http://sourceforge.net/projects/math-atlas/files/Stable/3.10.1/atlas3.10.1.tar.bz2/download \
    -O atlas3.10.1.tar.bz2

  # From "Basic Steps of an ATLAS install"
  #   http://math-atlas.sourceforge.net/atlas_install/node6.html
  #
  # create SRCdir
  bunzip2 -c atlas3.10.1.tar.bz2 | tar xfm -
  # get unique dir name
  mv ATLAS ATLAS3.10.1
  # enter SRCdir
  cd ATLAS3.10.1
  # create BLDdir
  mkdir Linux_C2D64SSE3
  # enter BLDdir
  cd Linux_C2D64SSE3

  # Get the machine's proc speed.
  # NOTE: If your machine has multiple processors, they each return a summary.
  # Not quite:
  #   cpu_mhz=`cat /proc/cpuinfo | grep 'cpu MHz' | sed "s/[^0-9]*\([.0-9]\+\).*/\1/g"`
  # This is better: Use -m 1 to just grep the first matching line.
  cpu_mhz=`cat /proc/cpuinfo | grep -m 1 'cpu MHz' | sed "s/[^0-9]*\([.0-9]\+\).*/\1/g"`
  if [[ -z ${cpu_mhz} ]]; then
    echo "Missing: cat /proc/cpuinfo missing 'cpu MHz'?:"
    echo "`cat /proc/cpuinfo`"
    exit 1
  fi

  # [lb] notes: see:
  #  ../configure -help
  # configure command
  #
  ../configure -b 64 -D c -DPentiumCPS=${cpu_mhz} \
    --prefix=/ccp/opt/atlas
    --with-netlib-lapack-tarfile=/ccp/opt/.downloads/lapack-3.4.2.tgz

  # tune & build lib
  make build
  # sanity check correct answer
  make check
  # sanity check parallel
  make ptcheck
  # check if lib is fast
  make time
  # copy libs to install dir
  make install

  # *** SciPy

  # 2013.05.08: SciPy is needed by OpenOPT... but OpenOPT seems to install it,
  # so we can skip this step. (OOFramework does exactly what we would do here:
  # wget the archive and compile from source.)
  #

  # 2013.05.09: Funnily, Yanjie just requested SciPy.

  # prereq: CBLAS, maybe ATLAS

  cd /ccp/opt/.downloads
  wget -N http://www.netlib.org/blas/blast-forum/cblas.tgz \
    -O CBLAS-2011_01_20-cblas.tgz
  /bin/rm -rf /ccp/opt/.downloads/CBLAS-2011_01_20-cblas
  tar -xvzf CBLAS-2011_01_20-cblas.tgz \
    > /dev/null
  /bin/mv CBLAS CBLAS-2011_01_20

  cd /ccp/opt/.downloads/CBLAS-2011_01_20

  # Per its README:
  #  /bin/ln -s Makefile.LINUX Makefile.in
  # Except Makefile.in already exists...

  # make help
  # I'm not sure... make all? There are lots of sub-makes.
  make all <-- fails

  # 2013.05.10: Argh. I just asked operator to install SciPy on all of our
  #             machines...
echo "lb cannot get CBLAS to make... I am giving up in the interest of time."
exit 1

  # ./testing/xscblat1
  # ./testing/xdcblat1
  # ./testing/xccblat1
  # ./testing/xzcblat1
  # ./testing/xscblat2 < testing/sin2
  # ./testing/xdcblat2 < testing/din2
  # ./testing/xccblat2 < testing/cin2
  # ./testing/xzcblat2 < testing/zin2
  # ./testing/xscblat3 < testing/sin3
  # ./testing/xdcblat3 < testing/din3
  # ./testing/xccblat3 < testing/cin3
  # ./testing/xzcblat3 < testing/zin3

  echo
  echo "Installing SciPy"

  cd /ccp/opt/.downloads
  wget -N https://pypi.python.org/packages/source/s/scipy/scipy-0.12.0.tar.gz#md5=8fb4da324649f655e8557ea92b998786 scipy-0.12.0.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/scipy-0.12.0
  tar -xvzf scipy-0.12.0.tar.gz \
    > /dev/null
  cd /ccp/opt/.downloads/scipy-0.12.0

  python setup.py install --prefix=/ccp/opt/usr

  numpy.distutils.system_info.BlasNotFoundError: 
      Blas (http://www.netlib.org/blas/) libraries not found.
      Directories to search for the libraries can be specified in the
      numpy/distutils/site.cfg file (section [blas]) or by setting
      the BLAS environment variable.

  __find_missing_dependencies='
  sci_py_dependencies=(\
    "python" "python-dev" "libatlas3-base-dev" "gcc" "gfortran" "g++")
  for package in ${sci_py_dependencies[*]}; do
    #aptitude show ${package}
    aptitude show ${package} | pcregrep -M "Package:.*\nState: not installed"
  done
  # Missing: libatlas3-base-dev
  # Avail: libatlas-base-dev

  Also, 
  BLAS (Basic Linear Algebra Subprograms)

  '

  # To test, run python:
  #
  #  import scipy
  #  scipy.test()
  #
  # also:
  #
  #  scipy.test('full')

  # *** OpenOPT Framework

  echo
  echo "Installing OpenOPT Framework"

  # http://openopt.org/OOFramework
  # http://openopt.org/TSP

  # There are four separate pacakges:
  #   http://openopt.org/images/3/33/OpenOpt.zip
  #   http://openopt.org/images/a/a6/FuncDesigner.zip
  #   http://openopt.org/images/6/6a/DerApproximator.zip
  #   http://openopt.org/images/4/4e/SpaceFuncs.zip
  # In one convenient download:
  #   http://openopt.org/images/f/f3/OOSuite.zip
  # Except there are some bug fixes checked into SVN...
  # The separate packages:
  #   svn co svn://openopt.org/PythonPackages/OpenOpt OpenOpt
  #   svn co svn://openopt.org/PythonPackages/DerApproximator DerApproximator
  #   svn co svn://openopt.org/PythonPackages/FuncDesigner FuncDesigner
  #   svn co svn://openopt.org/PythonPackages/SpaceFuncs SpaceFuncs
  cd /ccp/opt/.downloads
  svn co svn://openopt.org/PythonPackages OOSuite \
    > /dev/null
  #python setup.py install --prefix=/ccp/opt/usr

  cd /ccp/opt/.downloads/OOSuite/DerApproximator
  python setup.py install --prefix=/ccp/opt/usr

  cd /ccp/opt/.downloads/OOSuite/FuncDesigner
  python setup.py install --prefix=/ccp/opt/usr

  cd /ccp/opt/.downloads/OOSuite/OpenOpt
  python setup.py install --prefix=/ccp/opt/usr

  cd /ccp/opt/.downloads/OOSuite/SpaceFuncs
  python setup.py install --prefix=/ccp/opt/usr

  # Test:
  #
  # cd /ccp/opt/.downloads/OOSuite/OpenOpt/openopt/examples
  # python glp_1.py
  # python nlp_1.py

  # *** DSDP -- Software for Semidefinite Programming

  cd /ccp/opt/.downloads
  wget -N http://www.mcs.anl.gov/hs/software/DSDP/DSDP5.8.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/DSDP5.8
  tar -xvzf DSDP5.8.tar.gz \
    > /dev/null
  cd /ccp/opt/.downloads/DSDP5.8

  # *** CVXOPT -- Python Software for Convex Optimization

  # For OOFramework, otherwise you cannot use 'glpk' solver:
  #   oologfcn.OpenOptException: for solver glpk cvxopt is required,
  #                              but it was not found

  cd /ccp/opt/.downloads
  wget -N https://github.com/cvxopt/cvxopt/archive/1.1.6.tar.gz \
    -O cvxopt-1.1.6.tar.gz
  /bin/rm -rf /ccp/opt/.downloads/cvxopt-1.1.6
  tar -xvzf cvxopt-1.1.6.tar.gz \
    > /dev/null
  cd /ccp/opt/.downloads/cvxopt-1.1.6

  # NOTE: We have to add BLAS_LIB_DIR to setup.py.
  #       We could parse and recreate the config file, but storing an edited
  #       version and just copying it is easier.
  # I.e., set
  #   BLAS_LIB_DIR = '/ccp/opt/lapack/lib'
  #
  # FIXME/WHATEVER: The cvxopt-1.1.6/setup.py is not stored anywhere. You'll
  #                 have to recreate it, if you care.
  /bin/cp \
    ${SCRIPT_DIR}/../ao_templates/ubuntu10.04-target/ccp/opt/.downloads/cvxopt-1.1.6/setup.py \
    /ccp/opt/.downloads/cvxopt-1.1.6

  python setup.py install \
    --prefix=/ccp/opt/usr

  # Test:
  #  $ python
  #  > from cvxopt.glpk import ilp

  /ccp/opt/glpk/lib/

}

# *** Fix permissions and Grant ownerships

echo
echo "Fixing permissions on /ccp/opt/"

sudo ${SCRIPT_DIR}/../../util/fixperms.pl --public /ccp/opt/ \
  > /dev/null 2>&1
sudo chown -R $targetuser /ccp/opt
sudo chgrp -R $targetgroup /ccp/opt

# *** Restore our spot

cd $script_path

# *** Reset GCC

if [[ -n "$MODULESHOME" ]]; then
  module load soft/gcc/4.5.2
fi

# *** All done!

echo
echo "LP and TSP software installed and compiled!"

exit 0

