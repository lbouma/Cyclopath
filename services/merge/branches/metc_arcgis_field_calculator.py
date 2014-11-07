# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: This code is one-off code used to configure the original conflated 
# Bikeways dataset. Henry Stroud used RoadMatcher in 2011. Landon Bouma 
# cleaned up the fields in 2012.
#
# This code is meant to be run from ArcPy, i.e., the Python interpreter
# inside ArcGIS/ArcMap.
#
# Instructions to Populate a New Column From an Existing Column: 
#  - Load ArcMap and load your Shapefile.
#  - Open the Layer's Attribute Table.
#  - Make sure nothing is selected (otherwise the only columns that get set
#    will be the selected columns').
#  - Right-click the column header and choose "Field Calculator...".
#  - Set Parser to Python.
#  - Enable "Show Codeblock"
#  - Copy the Pre-Logic Script Code from the below into the same-named widget.
#  - Find and copy just the command for the column you are setting.
#  - Repeat for each column.
#  - Hints: If you need to create a column first, the left-most toolbar icon 
#    above the Attribute Table has an "Add Field..." option.
#  - Hints: ArcMap 10 has a bug (since fixed in later service packs) that won't
#    let you right-click a column header and choose "Delete Field...": the
#    option is available but nothing happens.
#    Trick: Geoprocessing [menu] > ArcToolbox
#           ArcToolbox > Data Management Tools > Fields > Delete Fields

# *** Per-column commands.
#
# Copy each one of these for each column you're editing.

# *****************************************************************************

# Agency Type (basically, a cleaner version of the Bikeways' Type field)
set_field__BIKE_FACIL(!BIKE_FACIL!)

# *****************************************************************************

# Agency Paved (gleaned from Bikeways' Type field)
set_field__AGY_PAVED(!AGY_PAVED!, !TYPE!, !SURF_TYPE!)

# *****************************************************************************

# Agency One-Way (gleaned from Bikeways' Type field)
set_field__AGY_ONEWAY(!TYPE!)

# *****************************************************************************

# Agency Source (repairs truncated column and prefixes "Other - " to a few.
set_field__AGY_SOURCE(!AGY_SOURCE!)

# *****************************************************************************

# *** Pre-Logic Script Code.
#
# Copy all of this (until the end of the file); it defines everything needed by
# the Per-column commands.

# *** SIDE

# Someone truncated the column width in the RoadMatcher conflation... this
# repairs it. Not that SIDE is really all that valuable -- it's hardly used and
# not meaningful for Cyclopath, really... the 'side' is often the side of the
# road the bike trail from the Bikeways data set is on (meaning, the bike trail
# is the road centerline marked as trail, jeesh!).
field_val_map__side = {
   'Bo': 'Both',
   'Ea': 'North or East',  # We lost No and So, and just 16 of these.
   'NA': 'NA',
   'No': 'North or East',  # NOTE: A few were 'North', instead...
   'So': 'South or West',  # NOTE: A few were 'South', instead...
   'Un': 'Unknown',
   'We': 'South or West',   # We lost No and So, and just 31 of these.
   }

# *** SURF_TYPE

surf_type_domain_surf_paved = [
   'Asphalt', 
   'Concrete', 
   # Is Boardwalk considered paved or not? Technically, it is a type of
   # pavement, but colloquilally, would normal people consider it paved?
   'Boardwalk', 
   ]

surf_type_domain_surf_unpaved = [
   'Dirt', 
   'Gravel', 
   'Turf', 
   ]

# *** Jurisdiction

# This is just for reference; these are not translated.
field_val_map__jurisdiction = {
   'Municipal' : 'Municipal',
   'County'    : 'County',
   'Regional'  : 'Regional',
   'State'     : 'State',
   'Federal'   : 'Federal',
   'Other'     : 'Other',
   'Unknown'   : 'Unknown',
   }

# *** Class. UNUSED.

# This is just for reference; these are not translated.
field_val_map__class = {
   'GAP'          : 'GAP', # only 10 of these; really just Paved Trail
   'Paved Trail'  : 'Paved Trail', 
   'Road'         : 'Road', 
   'Trail'        : 'Trail', 
   }

# Shoulder Scale. UNUSED.

type_domain_shoulder_5plus = (
   "Shoulder >= 5'",
   "One-way Shoulder >= 5'",
   "US/State Road with Shoulder >= 5'",
   )
type_domain_shoulder_5less = (
   "Low Volume Road with Shoulder < 5'",
   )
type_domain_shoulder_unknown = (
   'Non-paved Trail',
   'Paved Trail',
   'Bike Lane',
   'One Way Paved Trail',
   'One-way Paved Trail',
   'One Way Bike Lane',
   #
   'Other',
   'Sub-Standard',
   )

# *** Paved (or Unpaved)

type_domain_surf_paved = (
   'Paved Trail',
   'Bike Lane',
   "Shoulder >= 5'",
   "Low Volume Road with Shoulder < 5'",
   'One Way Paved Trail',
   'One-way Paved Trail',
   'One Way Bike Lane',
   'One-way Bike Lane',
   "One-way Shoulder >= 5'",
   "US/State Road with Shoulder >= 5'",
   # Maybe not paved but default to paved.
   'Other',
   'Sub-Standard',
   )
type_domain_surf_unpaved = (
   'Non-paved Trail',
   )

# *** Source

# This map looks funny because our intern or RoadMatcher truncated this 
# field to just 11 chars. This restores the original entries and also converts
# a few of them, i.e., to "Other - *" for non-agencies.
field_val_map__source = {
   'Aerial photo' : 'Other - Aerial Photo',
   'Aerial Photo' : 'Other - Aerial Photo', 
   'Albertville'  : 'Albertville', 
   'Bloomington'  : 'Bloomington', 
   'Brooklyn Cent': 'Brooklyn Center', 
   'Brooklyn Park': 'Brooklyn Park', 
   'Buffalo'      : 'Buffalo', 
   'Burns Townshi': 'Burns Township', 
   'Carver Co'    : 'Carver Co', 
   'Chanhassen'   : 'Chanhassen', 
   'Chaska'       : 'Chaska', 
   'Chisago Co'   : 'Chisago Co', 
   'City of Clear': 'City of Clearwater', 
   'City of Corco': 'City of Corcoran', 
   'City of Delan': 'City of Delano', 
   'City of Hasti': 'City of Hastings', 
   'City of Hugo' : 'City of Hugo', 
   'City of Minne': 'City of Minneapolis', 
   'City of Mound': 'City of Mound', 
   'City of New P': 'City of New Prague', 
   'City of Rockf': 'City of Rockford', 
   'City of St. P': 'City of St. Paul', 
   'City of Wayza': 'City of Wayzata', 
   'Cottage Grove': 'Cottage Grove', 
   'Crystal'      : 'Crystal', 
   'Dakota County': 'Dakota County', 
   'DGN from Henn': 'Hennepin County (DGN)', 
   'Eden Prairie' : 'Eden Prairie', 
   'GAP MAP 04'   : 'Other - GAP MAP 04', 
   'Gateway Trail': 'Other - Gateway Trail Map', 
   'Hennepin Coun': 'Hennepin County', 
   'Hopkins'      : 'Hopkins', 
   'Howard Lake'  : 'Howard Lake', 
   'junk'         : 'Other - Junk', # 1 of these
   'MetCouncil 20': 'MetCouncil 2001 Map', 
   'MetCouncil Ma': 'MetCouncil 2001 Map', 
   'Minneapolis'  : 'Minneapolis', 
   'Minneapolis P': 'Minneapolis Parks', 
   'Minnetonka'   : 'Minnetonka', 
   'Mn/DOT'       : 'MnDOT', 
   'Mn/DOT Bike M': 'MnDOT Bike Map Book', 
   'Monticell'    : 'Monticello', 
   'Monticello'   : 'Monticello', 
   'Mpls Public W': 'Minneapolis Public Works', 
   'Oakdale'      : 'Oakdale', 
   'Plymouth'     : 'Plymouth', 
   'Published Map': 'Other - Published Map', 
   'Ramsey County': 'Ramsey County', 
   'Richfield'    : 'Richfield', 
   'Robbinsdale'  : 'Robbinsdale', 
   'Rogers'       : 'Rogers', 
   'Savage'       : 'Savage', 
   'Scott Co'     : 'Scott Co', 
   # SDEIS - Supplemental Draft Environmental Impact Statement
   'SDEIS St. Cro': 'Other - St. Croix River SDEIS', 
   'Shakopee'     : 'Shakopee', 
   'St. Louis Par': 'St. Louis Park', 
   'St. Paul'     : 'St. Paul', 
   'St. Paul Park': 'St. Paul Park', 
   'Stillwater'   : 'Stillwater', 
   'Stillwater En': 'Stillwater Engineering', 
   'Three Rivers' : 'Three Rivers Park District', 
   'ThreeRiversPa': 'Three Rivers Park District', 
   'Trunk Highway': 'Other - Trunk Highways', 
   'unknown'      : 'Other - Unknown', 
   'Village of De': 'Village of Deephaven', 
   'Waconia'      : 'Waconia', 
   'Washington Co': 'Washington Co', 
   'White Bear To': 'White Bear Township', 
   'Woodbury'     : 'Woodbury', 
   'Wright Co'    : 'Wright Co', 
   }

# *** Agency Type

# Bike Lane
type_domain_fac_bike_lane = (
   'Bike Lane',
   #
   'One Way Bike Lane',
   'One-way Bike Lane',
   )
# Bike Trail
type_domain_fac_bike_trail = (
   'Bike Trail',
   #
   'Paved Trail',
   'Non-paved Trail',
   'One Way Paved Trail',
   'One-way Paved Trail',
   )
# Bike Shoulder (on any Roadway)
type_domain_fac_bike_shoulder = (
   'Bike Shoulder',
   #
   "Shoulder >= 5'",
   "One-way Shoulder >= 5'",
   "US/State Road with Shoulder >= 5'",
   )
# Narrow Shoulder (Low Volume Highway)
type_domain_fac_small_should = (
   'Narrow Shoulder',
   #
   "Low Volume Road with Shoulder < 5'",
   )
# Unknown/Other (Shared or Agency-Suggested Roadway)
type_domain_fac_bike_none = (
   'Unknown/Other',
   #
   'Other', # A few thousand of these
   'Sub-Standard', # only 3 of these
   )

# *** Callback fcns.

# CAVEAT: (a/k/a ArcMap BUGBUG): ArcMap capitalizes *any* string (including
# substrings) that match field names. E.g., consider you have a field name
# "bike_facil". Well, if you have a function with a matching substring, e.g.,
#    def set_field__bike_facil
# when ArcMap sees this is the Pre-Logic block, it renames the fcn. to 
# set_field__BIKE_FACIL -- meaning, your references to the fcn. are now 
# broken because Python is case-sensitive... silly ArcMap!!

def set_field__BIKE_FACIL(agy_type):
   global type_domain_fac_bike_lane
   global type_domain_fac_bike_trail
   global type_domain_fac_bike_shoulder
   global type_domain_fac_small_should
   global type_domain_fac_bike_none
   the_val = 'ERROR'
   if agy_type in type_domain_fac_bike_lane:
      #the_val = 'Bike Lane'
      the_val = 'bike_lane'
   elif agy_type in type_domain_fac_bike_trail:
      #the_val = 'Bike Trail'
      the_val = 'paved_trail'
   elif agy_type in type_domain_fac_bike_shoulder:
      # 2013.09.03: NOTE: We do not know from the Shapefile if the road in
      #                   question is high volume or low volume.
      #the_val = 'Bike Shoulder'
      the_val = 'shld_lovol'
      #the_val = 'shld_hivol'
   elif agy_type in type_domain_fac_small_should:
      #the_val = 'Narrow Shoulder'
      the_val = 'hway_lovol'
   elif agy_type in type_domain_fac_bike_none:
      # Use the generic "shared roadway" value.
      #the_val = 'Unknown/Other'
      the_val = 'rdway_shared'
   # MAYBE: This code is run in ArcGIS. Does it have a log facility?
   # elif agy_type:
   #    log.warning('set_field__BIKE_FACIL: unknown agy_type: %s' % (agy_type,))
   return the_val

# *** Paved

def set_field__AGY_PAVED(agy_paved_, agy_type_, surf_type_):
   global type_domain_surf_paved
   global surf_type_domain_surf_paved
   the_val = 'N'
   if surf_type_ in surf_type_domain_surf_unpaved:
      the_val = 'N'
   elif surf_type_ in surf_type_domain_surf_paved:
      the_val = 'Y'
   elif agy_type_ in type_domain_surf_paved:
      the_val = 'Y'
   return the_val

# *** One-Way

def set_field__AGY_ONEWAY(agy_type):
   the_val = 'N'
   if agy_type[:7].lower() in ['One Way'.lower(),
                               'One-way'.lower(),]:
      the_val = 'Y'
   return the_val

# *** Source

def set_field__AGY_SOURCE(agy_source):
   global field_val_map__source
   the_val = ''
   for key, value in field_val_map__source.iteritems():
      if agy_source.lower().startswith(key.lower()):
         the_val = value
         break
   if not the_val:
      the_val = agy_source
   return the_val

# *****************************************************************************

