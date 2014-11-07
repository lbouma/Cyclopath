# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "revisions.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Events per day"
set grid xtics ytics lw 0.3
set key left top
plot \
  "revisions.daily.out" using 1:2 with lines lt 1 title "Revisions", \
  "revisions.daily.out" using 1:2 with lines lt 3 lw 2 smooth bezier title "Smoothed"
