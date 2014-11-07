# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME [aa] Rename geofeatures

set term png size 800,540
set output "tagged_points.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Number of points with tags"
set grid xtics ytics lw 0.3
set key left top
plot \
  "points_with_tags_count.out" using 1:2 with lines title "Number of points with at least 1 tag", \
  "points_with_tags_count.out" using 1:3 with lines title "Number of points with at least 2 tags", \
  "points_with_tags_count.out" using 1:4 with lines title "Number of points with at least 3 tags", \
  "points_with_tags_count.out" using 1:5 with lines title "Number of points with at least 5 tags"
