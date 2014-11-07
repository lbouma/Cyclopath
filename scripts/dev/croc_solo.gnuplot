# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# With special thanks to http://gnuplot.sourceforge.net/demo/histograms.html

# USAGE: gnuplot croc_solo.gnuplot
#  ALSO: gnuplot, and then run from its command line.
#
# UBUNTU: You need the fonts directory for arial:
#
#  GDFONTPATH=/usr/share/fonts/truetype/msttcorefonts/ croc_solo.gnuplot 

# FIXME: At the U,
#          gnuplot --version / gnuplot 4.2 patchlevel 6
#        At home,
#          gnuplot --version / gnuplot 4.4 patchlevel 0
#        The earlier gnuplot does not get the for [i=3:6] syntax of plot.

# Also, rowstacked historgrams do not support xdata time values, that is, your
# x-axis cannot be time values. Because of some technical reason I don't quite
# understand. You can read more about it here:
#   http://objectmix.com/graphics/756695-xdata-time-rowstacked-histogram.html
#set xdata time
#set timefmt x "%Y%m%d"
#set xrange [ "20080101" : "20120101" ] noreverse nowriteback
#set format x "%b %d"

set output "croc_solo.png"
#set terminal png transparent nocrop enhanced font arial 8 size 800,540
# Arial/arial not found...
# "Could not find/open font when opening font Arial, trying default"
#set terminal png nocrop enhanced font arial 8 size 800,540
#set terminal png nocrop enhanced size 1600,1200 font arial 11
#set terminal png nocrop enhanced size 800,540 font arial 11
set terminal png nocrop enhanced size 928,696 font arial 11

#set term png size 800,540

set boxwidth 0.75 absolute
set style fill solid 1.00 border -1
#set style fill border -1

set key outside right top vertical Left reverse enhanced autotitles columnhead nobox
set key invert samplen 4 spacing 1 width 0 height 0

set style histogram rowstacked title offset character 0, 0, 0

set datafile missing '-'
set style data histograms
#set xtics border in scale 1,0.5 nomirror rotate by -45 offset character 0, 0, 0
set xtics border in scale 1,0.5 nomirror rotate by -90 offset character 0, 0, 0
#set xtics border in scale 1,0.5 nomirror rotate by -45 offset character 1, 10, 1334
#set xtics 1,100,1334
#set xtics (1,2)
#set xtics ("" 21, "" 28, "" 35, "" 42, "" 49, "" 56, "" 63, "" 70)
#set xtics ("" 0.00000, "" 1.00000, "" 2.00000, "" 3.00000, "" 4.00000, "" 5.00000, "" 6.00000, "" 21, "" 28, "" 35, "" 42, "" 49, "" 56, "" 63, "" 70)

#set xtics scale 10 # I think scale is the height of the tick?
# Hide ticks:
#set xtics scale 0
#set xtics 10
#set xtics add ("Pi" 3.14159)
#set title "Cyclopath V2 Source Code Lines\nby Weeks since May 2008" 
set title "Cyclopath V2 Source Code Lines\nby Two-Week-Periods since May 2008" 
#set yrange [0:123000] noreverse nowriteback
# This is the same as the following line but doesn't work on Ubuntu:
##i = 1
#plot 'croc_solo.dat' using 2:xtic(1), for [i=3:6] '' using i
# Same as:
# This is the same as the previous line but works on both Fedora and Ubuntu:
plot 'croc_solo.dat' using 2:xtic(1), 'croc_solo.dat' using 3:xtic(1), 'croc_solo.dat' using 4:xtic(1), 'croc_solo.dat' using 5:xtic(1), 'croc_solo.dat' using 6:xtic(1)

#plot "weekly-hist.dat" using 2:xticlabels(1) lc rgb 'green', \
#	"" using 3 lc rgb 'yellow',  \
#	"" using 4 lc rgb 'red'

