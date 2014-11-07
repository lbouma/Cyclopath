# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "tagged_byways.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Number of byways with tags"
set yrange [0:2000]
set grid xtics ytics lw 0.3
set key left top
set multiplot
set size 1,0.5
set origin 0.0,0.0
set lmargin 10
set tmargin 0
plot \
  "byways_with_tags_count.out" using 1:3 with lines title "Number of byways with at least 2 tags", \
  "byways_with_tags_count.out" using 1:4 with lines title "Number of byways with at least 3 tags", \
  "byways_with_tags_count.out" using 1:5 with lines title "Number of byways with at least 5 tags"
set origin 0.0,0.5
set format x ""
set bmargin 0
set lmargin 10
set tmargin 1
set yrange [2000:*]
plot \
  "byways_with_tags_count.out" using 1:2 with lines title "Number of byways with at least 1 tag"
