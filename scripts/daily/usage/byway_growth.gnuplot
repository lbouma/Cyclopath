# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "byway_growth.png"
set timefmt "%Y%m%d:%H:%M:%S"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Count"
set y2label "Percent of blocks"
set y2tics ("0%%" 0, "2%%" 3000, "5%%" 7500, "10%%" 15000, "15%%" 22500)
set grid xtics ytics lw 0.3
set key left top
plot \
  "count_ratings.dat" using 1:2 with lines title "Ratings", \
  "count_ratings.dat" using 1:5 with lines title "Blocks with >= 1 rating", \
  "count_ratings.dat" using 1:7 with lines lw 3title "Blocks with >= 3 ratings", \
  "count_ratings.dat" using 1:9 with lines title "Blocks with >= 10 ratings"
