#!/bin/bash  

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Use this script to simulate slow/lossy connections for debugging.
# It's a wrapper for the netem options in /sbin/tc (and needs sudo access).
# See http://www.linuxfoundation.org/en/Net:Netem for more info about netem.

PROGRAM="tc qdisc"
#FIXME: change dev to eth0 and allow use with traffic to non-local hosts.
DEVICE="dev lo"
USAGE="Usage: $0 [args...] 

Requires sudo access to /sbin/tc.

Examples:
   Corrupt 28% of packets:   $0 corrupt 15%
   Drop 28% of packets:      $0 loss 15%
   Slow traffic by about 1s: $0 delay 500ms 100ms
   Test (ping localhost):    $0 test
   Reset to normal:          $0 reset
   
Notes:

  1. This program disrupts the loopback interface, so disruption happens on
     both send and receive: this is why the arguments have odd values. For
     example, disrupting 15% of packets = leaving 85% of send packets and 85%
     of received packet alone; 1 - (0.85 * 0.85) = 27.75 of packets disrupted
     on send, receive, or both.

  2. TCP will automatically resend lost packets, so 'loss' is effectively the
     same as 'delay'."

#FIXME: only apply filters once.

case "$1" in
   reset)
      echo Resetting $DEVICE
      sudo $PROGRAM delete $DEVICE root ;;
   corrupt) 
      amount=${2:-"15%"}
      echo Corrupting $amount of packets.
      sudo $PROGRAM replace $DEVICE root netem corrupt $amount ;;
   delay)
      latency=${2:-"500ms"}
      jitter=${3:-"100ms"}
      echo Adding $latency latency with $jitter jitter.
      sudo $PROGRAM replace $DEVICE root netem delay $latency $jitter distribution normal ;;
   loss)
      amount=${2:-"15%"}
      echo Dropping $amount of packets.
      sudo $PROGRAM replace $DEVICE root netem loss $amount ;;
   test)
      ping -c 10 localhost ;;
   *) echo "$USAGE" ;;
esac

echo
echo Current filters on $DEVICE: 
$PROGRAM show $DEVICE
