#!/usr/bin/perl

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME: It'd be nice if this class also counted chars, since lines can be
#        blank. Also, counting just non-comment-lines would be nice.
# 2012.08.21: See the third-party Perl script, cloc.pl (Count Lines of Code).
print "This script is deprecated. Use cloc.pl."

use strict;
use warnings;

sub lines {
  my $suffix = shift(@_);
  # If find returns a blank, wc -l hangs, so check find first.
  if (`find . -name '*.$suffix'`) {
    my $cmd = "wc -l \`find . -name '*.$suffix' | grep -v '/dev2/' | grep -v '/build/' grep -v '/build-print/' | grep -v '/winpdb/' | grep -v norvig | grep -v '/rpy2/' | grep -v '/pychart/'\` | tail -1";
    `$cmd` =~ /(\d+)/;
    return int($1);
  }
  else {
     return 0;
  }
}

my $linect_total = 0;

print "Line counts:\n";

# FIXME: Tabs: should use %10s or something instead: not formatted well in
# email...
foreach my $suffix (('as', 'cgi', 'html', 'java', 'mxml', 'php', 'pl', 'py', 'sh', 'sql', 'vim')) {
  my $linect = lines($suffix);
  print "$suffix:\t$linect\n";
  $linect_total += $linect;
}

print "Total:\t$linect_total\n";

