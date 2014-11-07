#!/usr/bin/perl

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script analyzes a Cyclopath Apache error log on standard input and
# complains if there seem to be too many authentication failures coming from
# particular IPs or if there seem to be too many total authentication
# failures.

use strict;
use warnings;

# Complain about IPs that have this many or more auth failures.
my $THRESHOLD_IP = 200;

# Complain if this many total auth failures.
my $THRESHOLD_TOTAL = 2000;

# These IPs are exempt from complaining (to work around bugs, like bug 1562).
# This list should normally be empty.
my %IPS_EXEMPT = (
                    # 2014.01.30: [lb] is curious if we can disable these.
                    #'71.63.158.162' => 1,  # added 3/3/2010 by Reid
                    #'198.175.197.100' => 1, # added 3/12/2010 by Reid
                 );

my %ips;

# Use of uninitialized value in numeric gt (>) at .../analyze/authfail_audit.pl
#                                                 line 41, <STDIN> line 67.
$ips{ALL} = 0;

# extract IPs with failed auth and warnings about autobans
foreach my $line (<STDIN>) {
  # 2014.01.30: We keep warning about the same failures because the log file
  # doesn't rotate every day. We need to parse the date of the log message
  # (or we need to tail the file and send just that...). This seems easier
  # for me to do from Bash, so, for an example, see the nightly cron job
  # script, /ccp/bin/ccpdev/daily/daily.runic.sh. It uses `wc` and touch
  # files so that it only sends to this script data that this script has
  # not yet analyzed (and complained about).
  if ($line =~ /\[client (.+?)\].*auth failed/) {
    $ips{ALL} += 1;
    $ips{$1} += 1;
  }
  if ($line =~ /banned/) {
    print $line;
  }
}

# too many failures total?
if ($ips{ALL} > $THRESHOLD_TOTAL) {
  print "WARNING: too many auth failures total: $ips{ALL}\n";
}

# too many failures for individual IPs?
# FIXME: could be better written with each() and grep(), but I can't figure it
# out and I'm in a hurry.
foreach my $ip (keys %ips) {
  if ($ip ne 'ALL'
      and $ips{$ip} > $THRESHOLD_IP
      and not exists $IPS_EXEMPT{$ip}) {
    print "WARNING: too many auth failures from $ip: $ips{$ip}\n";
  }
}

