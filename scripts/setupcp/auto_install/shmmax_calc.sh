#!/bin/bash

# Output lines suitable for sysctl configuration based
# on total amount of RAM on the system.  The output
# will allow up to 50% of physical memory to be allocated
# into shared memory.

# On Linux, you can use it as follows (as root):
# 
# ./shmsetup >> /etc/sysctl.conf
# sysctl -p

# Early FreeBSD versions do not support the sysconf interface
# used here.  The exact version where this works hasn't
# been confirmed yet.

# 2012.06.02: Found by [lb] at 
#  http://postgresql.1045698.n5.nabble.com/The-right-SHMMAX-and-FILE-MAX-td4362375.html
# Link to post:
#  http://postgresql.1045698.n5.nabble.com/The-right-SHMMAX-and-FILE-MAX-tp4362375p4363380.html
# Thanks to Greg Smith-21. Posted 01 May 2011.

page_size=`getconf PAGE_SIZE`
phys_pages=`getconf _PHYS_PAGES`

if [[ -z "$page_size" ]]; then
  echo Error:  cannot determine page size
  exit 1
fi

if [[ -z "$phys_pages" ]]; then
  echo Error:  cannot determine number of memory pages
  exit 2
fi

shmall=`expr $phys_pages / 2`
shmmax=`expr $shmall \* $page_size` 

echo \# Maximum shared segment size in bytes
echo kernel.shmmax = $shmmax
echo \# Maximum number of shared memory segments in pages
echo kernel.shmall = $shmall
