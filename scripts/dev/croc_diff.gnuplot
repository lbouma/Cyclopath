# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# With special thanks to http://gnuplot.sourceforge.net/demo/histograms.html

# Also, rowstacked historgrams do not support xdata time values, that is, your
# x-axis cannot be time values. Because of some technical reason I don't quite
# understand. You can read more about it here:
#   http://objectmix.com/graphics/756695-xdata-time-rowstacked-histogram.html
#set xdata time
#set timefmt x "%Y%m%d"
#set xrange [ "20080101" : "20120101" ] noreverse nowriteback
#set format x "%b %d"

set output "croc_diff.png"
#set terminal png transparent nocrop enhanced font arial 8 size 800,540
# Arial/arial not found...
# "Could not find/open font when opening font Arial, trying default"
#set terminal png nocrop enhanced font arial 8 size 800,540
#set terminal png nocrop enhanced size 1600,1200
#set terminal png nocrop enhanced size 800,540
set terminal png nocrop enhanced size 928,696
#set term png size 800,540

set boxwidth 0.75 absolute
set style fill solid 1.00 border -1

set key outside right top vertical Left reverse enhanced autotitles columnhead nobox
set key invert samplen 4 spacing 1 width 0 height 0
set style histogram rowstacked title offset character 0, 0, 0
set datafile missing '-'
set style data histograms
#set xtics border in scale 1,0.5 nomirror rotate by -45 offset character 0, 0, 0
#set xtics ("1000" 0.00000, "2000" 1.00000, "3000" 2.00000, "4000" 3.00000)
set title "Cyclopath V2 Source Code Checkin Diffs\nby Two-Week-Periods since May 2008" 
#set yrange [0:150000] noreverse nowriteback
# This is the same as the following line but doesn't work on Ubuntu:
##i = 1
#plot 'croc_diff.dat' using 2:xtic(1), for [i=3:4] '' using i
# This is the same as the previous line but works on both Fedora and Ubuntu:
plot 'croc_diff.dat' using 2:xtic(1), 'croc_diff.dat' using 3:xtic(1), 'croc_diff.dat' using 4:xtic(1)

#plot "weekly-hist.dat" using 2:xticlabels(1) lc rgb 'green', \
#	"" using 3 lc rgb 'yellow',  \
#	"" using 4 lc rgb 'red'

