# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: In CcpV1, the data file was 'ratings.log'; now, count_ratings.dat.

set term png size 800,540
set output "ratings.png"
set timefmt "%Y%m%d:%H:%M:%S"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Real User Ratings per Day"
# When the generic rater ran, it generated 2e+06 ratings.
# Which we can fix if we only count real users' ratings.
#set yrange [0:1000]
set grid xtics ytics lw 0.3
set key right top
plot \
  "count_ratings.dat" using 1:3 with lines notitle
