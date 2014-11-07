#!/usr/bin/perl

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Compare two Cyclopath databases and report any differences.
# Note that this does not provide the ability to make updates from the diff.
# Works by dumping each table out into temporary text files and then diffing.
# FIXME: | is the field delimiter, this could lead to false negatives if one 
#        record contains | while the other contains matching data split across
#        adjacent fields (very unlikely).
# FIXME: can this be re-written as a shell script?  There are a lot of direct
# calls to other programs.

use strict;

my $user = "cycling";

# Optional first argument forces comparison even if schemas differ
my $force = 0;
if ($ARGV[0] eq "-f"){
  $force = 1;
  shift @ARGV;
}

# Optional last argument specifies a single table to compare
my $one_table = pop @ARGV if (@ARGV == 5 or @ARGV == 3);

# Most important arguments: 2 hosts [can be omitted] and 2 databases
my ($host1, $db1, $host2, $db2);

# Output changes slightly if hosts are specified
my ($h_t1, $h_t2);

if (@ARGV == 4) {
  # Both hosts and both databases are specified
  ($host1, $db1, $host2, $db2) = @ARGV;

  $h_t1 = "$host1:";
  $h_t2 = "$host2:";

} elsif (@ARGV == 2) {
  # Connect to default host for both databases
  ($db1, $db2) = @ARGV;
} else {
  print <<MSG;
Usage:
  $0 [-f] HOST1 DB1 HOST2 DB2 [TABLE] 
  $0 [-f] DB1 DB2 [TABLE]

MSG
  exit;
}

# Make sure we can connect to databases; exit if psql returns non-zero status
my $cmd1 = "psql $db1 -A -U$user -c ''";
$cmd1 = qq(ssh $host1 "$cmd1") if $host1;
my $cmd2 = "psql $db2 -A -U$user -c ''";
$cmd2 = qq(ssh $host2 "$cmd2") if $host2;
not system($cmd1) or exit 1;
not system($cmd2) or exit 1;

# Create working directory (will remove at the end if all is well)
my $path = "/tmp/diff" . int(rand()*10000);
mkdir $path;

# Need to tell user location of above directory if they kill this script
$SIG{INT} = \&bail;

# Which tables to include?
my @tables;
if ($one_table) {
  # User specified a table
  @tables = ($one_table);
} else {
  # No table specified; compare all tables in schema

  # First compare table lists ("schemas") to ensure they match
  my $dump = "$path/schema"; 
  my $cmd1 = "psql $db1 -A -U$user -c '\\d'";
  $cmd1 = $host1 ? qq(ssh $host1 "$cmd1" > $dump.1) : "$cmd1 > $dump.1";
  my $cmd2 = "psql $db2 -A -U$user -c '\\d'";
  $cmd2 = $host2 ? qq(ssh $host2 "$cmd2" > $dump.2) : "$cmd2 > $dump.2";
  system($cmd1);
  system($cmd2);

  my $diff = `diff $dump.1 $dump.2`;
  if ($diff){
    print <<MSG;
SCHEMAS DON'T MATCH!
< $h_t1$db1
> $h_t2$db2

$diff
MSG
    &bail() unless $force;
  }

  #Then, load one of the lists and add tables to array
  open FILE, "$path/schema.1";
  foreach my $line (<FILE>) {
    if ($line =~ /public\|(.+)\|(.+)\|$user/) {
      my ($name, $type) = ($1, $2);
      if ($type eq "table" and $name ne "apache_event") {
        push @tables, $name;
      }
    }
  }
  close FILE;

  # Clean up
  system("rm $path/schema.1 $path/schema.2")
}

# Main loop - compare the contents of each table by dumping and diffing
foreach my $table (@tables) {

  # Grab primary key for sorting.
  my $orderby = "";
  my $cmd = "psql $db1 -U$user -c '\\d $table'";
  $cmd = qq(ssh $host1 "$cmd") if $host1;
  if (`$cmd` =~ /PRIMARY\ KEY.*\((.*)\)/) {
    $orderby = "ORDER BY $1";
  } else {
    print STDERR "Warning: no primary key on $table\n";
    # FIXME: tables without a primary key (e.g. ban, tiles_cache_byway, and
    # tilecache_lock) may incorrectly appear to differ if they are not dumped
    # with the same sort order!
  }
 
  my $dump = "$path/$table";
  my $cmd1 = "psql $db1 -A -U$user -c 'SELECT * FROM $table $orderby'";
  $cmd1 = $host1 ? qq(ssh $host1 "$cmd1" > $dump.1) : "$cmd1 > $dump.1";
  my $cmd2 = "psql $db2 -A -U$user -c 'SELECT * FROM $table $orderby'";
  $cmd2 = $host2 ? qq(ssh $host2 "$cmd2" > $dump.2) : "$cmd2 > $dump.2";
  system($cmd1);
  system($cmd2);

  # First line of each dump is the column names
  my $cols1 = `head -n 1 $dump.1`;
  my $cols2 = `head -n 1 $dump.2`;
  chomp($cols1);
  chomp($cols2);
  
  my $diff;
  if ($cols1 ne $cols2) {
    $diff = "< $cols1\n> $cols2\n(Not comparing rows since columns differ)";
  } else {
    # Run a system diff on the table dumps
    $diff = `diff $dump.1 $dump.2`;
  }

  # Show diff (and meta) if there is one, otherwise print nothing
  if ($diff) {
    my $title = uc($table) . " TABLES DIFFER";
    #FIXME: shouldn't print "Columns: $cols1" below when ($cols1 ne $cols2)
    print <<MSG;
$title
Columns: $cols1
< $h_t1$db1.$table
> $h_t2$db2.$table

$diff
-------------------------
MSG
  } else {
    # Clean up
    system("rm $dump.1 $dump.2");
  }
}

# Clean up - if the directory is non-empty then something was different
rmdir $path or &bail;

sub bail {
  print <<MSG;
Non-clean exit; dumps saved in $path
TIP: use an advanced diff tool (such as vimdiff) to examine dumps
MSG
  exit 1;
}
