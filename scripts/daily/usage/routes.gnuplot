# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "routes.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
#set ylabel "Routes computed per day"
set grid xtics ytics lw 0.3
set key left top
plot \
  "routes_new.daily.out" using 1:2 with lines lt 6 title "New routes computed per day", \
  "routes_old.daily.out" using 1:2 with lines lt 5 title "Existing routes retrieved per day"

