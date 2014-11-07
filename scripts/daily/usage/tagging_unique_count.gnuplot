# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "tagging_unique.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Unique tag applications"
set grid xtics ytics lw 0.3
set key left top
plot \
  "tags_unique_count.out" using 1:2 with lines title "Unique tags", \
  "tags_unique_byways_count.out" using 1:2 with lines title "Unique byway tags", \
  "tags_unique_points_count.out" using 1:2 with lines title "Unique point tags"
