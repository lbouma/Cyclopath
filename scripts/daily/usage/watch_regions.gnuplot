# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: In CcpV1, the data file was 'watch.log'; now, count_watch_regions.dat.

set term png size 800,540
set output "watch_regions.png"
set timefmt "%Y%m%d:%H:%M:%S"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Count"
set grid xtics ytics lw 0.3
set key left top
plot \
  "count_watch_regions.dat" using 1:2 with lines title "Watch regions", \
  "count_watch_regions.dat" using 1:3 with lines title "Users w/ >= 1 WR", \
  "count_watch_regions.dat" using 1:4 with lines title "Users w/ >= 2 WRs", \
  "count_watch_regions.dat" using 1:5 with lines title "Users w/ >= 3 WRs"
