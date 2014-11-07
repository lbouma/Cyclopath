# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "tagging_daily.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Tag applications per day"
# BUG nnnn/FIXME: The Statewide import tagged a ton (350,000 byways)
#                 in Fall, 2013, so the graph is not very readable.
#                 We could/should fix tag_apps_byways_daily.out
#                 and tag_apps_points_daily.out to exclude system
#                 tag events (or any tag event by dont_study users
#                 or by any special system user, like _script).
#                 For now, using yrange; for later, fix the SQL.
set yrange [0:500]
set grid xtics ytics lw 0.3
set key left top
plot \
  "tag_apps_byways_daily.out" using 1:2 with lines title "Byway tag applications", \
  "tag_apps_points_daily.out" using 1:2 with lines title "Point tag applications"

  #"tag_apps_daily.out" using 1:2 with lines title "Tag applications", \
  #"tag_apps_nondefault_daily.out" using 1:2 with lines title "Tag applications excluding default tags", \
