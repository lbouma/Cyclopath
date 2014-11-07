# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

set term png size 800,540
set output "fetching.png"
set timefmt "%Y%m%d"
set xdata time
set xlabel "Date"
set format x "%b%Y"
set ylabel "Events per day"
# There's a jump to 280,000 tiles when we recreated tiles
# when going statewide, so clip the ymax.
set yrange [0:25000]
set grid xtics ytics lw 0.3
set key left top
plot \
  "tiles.daily.out" using 1:2 with lines lt 1 title "Tiles served", \
  "getfeature.daily.out" using 1:2 with lines lt 2 title "Vector mode pan/zooms"
