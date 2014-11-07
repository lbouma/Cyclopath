#!/usr/bin/perl

# Copyright (c) 2010 Regents of the University of Minnesota
# This file is free software under the 3-clause BSD license.

# Last modified: 2010-02-24 22:29 CST
# See below for docs, or run with --help.

# NOTES:
#
#  - Files and directories which are not owned by the running user but which
#    have incorrect permissions cannot be fixed unless you sudo this script.
#
#  - Symbolic links are ignored (chmod spits a Warning,
#     "neither file nor directory, ignoring)
#
# FIXME:
#
#  - Implement real argument parsing.
#  - Take a --group argument to also chgrp.

# 2013.02.07: [lb] added --quiet to chmod if we're not --verbose.

# http://www.unixlore.net/articles/speeding-up-bulk-file-operations.html
# Expect [lb] finds the 2775 must come first.
# FIXME/MAYBE: Should fixperms --public really just do this instead??:
#  sudo find $target_dir -type d -print0 | xargs -0 chmod 2775
#  sudo find $target_dir -type f -print0 | xargs -0 chmod 664

use strict;
use warnings;
no warnings 'uninitialized';

use Fcntl;
use File::Find;
use File::stat;
use Getopt::Long;
use POSIX;

my $help_show = 0;
my $public_mode = 0;
my $verbose = 0;
my @dirs = '.';

if (not Getopt::Long::GetOptions('help'    => \$help_show,
                                 'public'  => \$public_mode,
                                 'verbose' => \$verbose)) {
  $help_show = 1;
}

if ($help_show) {
  print <<EOF;

Usage:

  \$ $0 [--public] [--verbose] [DIRS]

This program repairs UNIX permissions for filesystem areas which should be
group accessible. It can operate in two modes:

Normal mode:

  Set group permissions to match user permissions. Turn on sticky bit on
  directories. Leave world permissions alone.

Public mode:

  In addition to what's done for normal mode, set the world read bit, and set
  the world execute bit if the owner execute bit is set.

  Note that this makes all files and directories world-readable!

Email reid\@umn.edu with blame.

EOF
    exit 1;
  }

#if ($public_mode and -e '.svn') {
#  print "ERROR! Don't run me in WWW mode in your working directory.\n";
#  exit 1;
#}

if (@ARGV > 0) {
  @dirs = @ARGV;
}

# Use the find options so we can follow symbolic links easily.
# See: http://perldoc.perl.org/File/Find.html
my %find_opts = (wanted => \&wanted,
                 follow_fast => 1,
                 # follow_skip 0 and 1 die on infinite link loops.
                 follow_skip => 2);
# File::Find::find(\&wanted, @dirs);
File::Find::find(\%find_opts, @dirs);

### Functions

sub wanted {
  my ($dir, $name, $full) = ($File::Find::dir, $_, $File::Find::name);
  #if ($verbose) {
  #  # Note that $dir/$name ==> $full.
  #  # print "On file: $name / in dir: $dir / path: $full\n";
  #  print "On file: $full\n";
  #}
  # Perl's file tests are part of a group known as the -X operator.
  # http://perldoc.perl.org/functions/-X.html
  # NOTE: $name is not the full path, but Perl changes our cwd for each file.
  if (not (-d $name or -f $name)) {
    # See if the file is a symbolic link.
    if (-l $name) {
      # The way follow_fast and follow_skip work, we'll get symbolic links only
      # for infinite link loops.
      if ($verbose) {
        print "Symbolic link means infinite loop: $full\n";
      }
    } else {
      # This file type is unexpected.
      print STDERR "Warning: $full: not file, directory, or link\n";
    }
  }
  else {
    # Found a real file or directory.
    if ($verbose) {
      print "Found real dir or file: $name\n";
    }
    my $p_before = get_perms($name);
    my $p_user = $p_before & 0700;
    my $p_other = $p_before & 0007;
    my $p_group = $p_user >> 3;
    my $perms = $p_user | $p_group | $p_other;
    if (-d $name) {
      $perms |= 02000;
    }
    if ($public_mode) {
      $perms |= ($p_user >> 6) & 0005;
      if (-d $name) {
        $perms |= 0001;
      }
    }
    set_perms($name, $perms, $p_before, $full);
  }
}

sub get_group {
  my $s = stat($_[0]) or die "Can't stat $_[0]: $!";
  return $s->gid;
}

sub get_perms {
  my $s = stat($_[0]) or die "Can't stat $_[0]: $!";
  return Fcntl::S_IMODE($s->mode);
}

sub set_perms {
  my ($file, $perms, $p_before, $full) = @_;
  if ($p_before != $perms) {
    # Perms not what we want -- fix them
    if ($verbose) {
      print "  $full: " . p2s($p_before) . " -> " . p2s($perms) ." \n";
    }
    chmod($perms, $file) or print STDERR "Can't chmod($file): $!\n";
  }
}

sub owned_by_me {
  my $s = stat($_[0]) or die "Can't stat $_: $!";
  return ($s->uid == POSIX::getuid());
}

# Convert numeric permissions to their string representation
sub p2s {
  return sprintf('%o', $_[0]);
}

