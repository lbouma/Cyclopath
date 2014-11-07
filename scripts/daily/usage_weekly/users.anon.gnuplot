# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "users.anon.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Unique IP's not used by logged-in users"
set grid xtics ytics lw 0.3
set key left top
plot \
  "users.daily_anon.out" using 1:2 with lines lt 2 title "Daily", \
  "users.weekly_anon.out" using 1:2 with lines lt 2 lw 2 title "Weekly"
