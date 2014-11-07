# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "tagging_count.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Total tag applications"
set grid xtics ytics lw 0.3
set key left top
plot \
  "tag_apps_count.out" \
      using 1:2 with lines title "Tag applications", \
  "tag_apps_byways_count.out" \
      using 1:2 with lines title "Byway tag applications", \
  "tag_apps_nondefault_byways_count.out" \
      using 1:2 with lines title "Nondefault byway tag applications", \
  "tag_apps_points_count.out" \
      using 1:2 with lines title "Point tag applications"

