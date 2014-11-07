# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

MAP

   PROJECTION
      # The projection is required but may be overriden via the url using,
      # e.g., &map.projection=EPSG:26915
      "init=epsg:26915"
   END

   # MapServer docs indicate that only five INCLUDEs may be nested and
   # that, e.g., INCLUDE "wms_common.map", cannot easily be debugged
   # because MapServer won't tell you the included line numbers when
   # things fail. So we preprocess with m4, and we use m4's include.

include(wms_common.map)

END

