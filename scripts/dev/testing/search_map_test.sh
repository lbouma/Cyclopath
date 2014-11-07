#!/bin/bash

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Some test commands. Note that ccp.py wants -t {item_type} to be
# specified, by search returns all search results.

# BUG_FALL_2013
# FIXME: Is there an easy way to implement this and other ccp.py tests?
#        How about dumping the output to a test file and then always
#        just checking new test output against the verified first output.
#        The only problem with this is that whenever you log messages, you
#        have to rerun the tests and regenerate the verified output file.

#
# Byways
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "martin way"

#
# Waypoints
# Awesome! It's first: "First Avenue & 7th Street Entry"
#
# EXPLAIN: Compare to CcpV1... compare all these searches to CcpV1.
#
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "First Avenue"

#
# Notes
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "nice stretch"

# A tag in [lb]'s test database.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "bubbler"

# Hrm. Not sure people would use quotes, but this works:
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '222 "washington ave n" "mpls mn" 55401'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '222 washington ave n mpls mn 55401'

#
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '12500 Dupont Avenue South Burnsville MN 55337'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'Burnsville 55337'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '55337'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '12500 Dupont Ave. So.  ,  Burnsville*, MN. , 55337'

# This one finds two addresses (via geocoder), which is a rare find and
# tests a rarely used portion of code. (E.g., [lb] found the bug that
# Search_Result_Geofeature.center was not being set for geocoder results,
# and the sort fcn. threw AttributeError when comparing two such results.)
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '222 hennepin mpls'

# This tests that we find long-named cities
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'turkey capital of the world'

./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'cowboy jacks, woodbury'

# See that similarly named cities are ranked properly.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'medina'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'edina'

# This works good well, but only find Dupont Ave S byways.
# BUG nnnn (if we cared): Use street names returned by geocoder to
#                         search for byways.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '50th & Dupont Ave S., Mpls., MN'
# These work well: shows the geocoded address first and then the sets of both
# streets' byways.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'W 50th St & Dupont Ave S., Mpls., MN'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'W 50th St & Dupont Ave S Mpls'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'W 50th St & Dupont Ave S . , Mpls . , MN'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'Dupont Ave S and W 50th St, Mpls'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'W 50th St and Dupont Ave S, Mpls'

# Fortunately, this query works.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q 'W 50th St'

# Make sure 'st paul' works. We try substituting 'saint' for 'st' when checking
# city names, but we shouldn't accidentally change 'st' when it means 'street'.
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 rice st stp'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 rice st st paul'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 rice st, st paul'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 rice st . , st paul'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 rice st , st paul'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q '538 Rice St, St Paul, MN 55103'
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "538 rice st pig's eye"

# MAYBE: Try synonyms for other common word variations?
#        theatre/theater; realize/realise; etc/etc.
# With this query, the guthrie theatre is the first result:
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "guthrie theatre"
# But this query only hits because the point has a note w/ the word "theater":
./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "guthrie theater"



./ccp.py -U landonb --no-password -b "Metc Bikeways 2012" -s -t byway -q "gateway"


# This is the streetaddress.py library:
#
# >>> parse('222 "washington ave n" "mpls mn" 55401')
# {'suffix': 'N', 'unit_prefix': None, 'postal_code_ext': None,
#  'prefix2': None, 'street2': None, 'number': '222', 'prefix': None,
#  'street': 'WASHINGTON', 'postal_code': '55401', 'unit': None,
#  'city': 'MPLS', 'state': 'MN', 'street_type': 'AVE', 'street_type2': None,
#  'suffix2': None}
# >>> parse('222 washington ave mpls')
# >>> parse('222 washington ave, mpls')
# >>> parse('222 washington ave mpls ')
# {'suffix': None, 'unit_prefix': None, 'postal_code_ext': None,
#  'prefix2': None, 'street2': None, 'number': '222', 'prefix': None,
#  'street': 'WASHINGTON AVE MPLS', 'postal_code': None, 'unit': None,
#  'city': None, 'state': None, 'street_type': None, 'street_type2': None,
#  'suffix2': None}
# >>> parse('really big rocks, mpls, mn')
# >>> parse('1 really big rocks, mpls, mn')
# {'suffix': None, 'unit_prefix': None, 'postal_code_ext': None,
#  'prefix2': None, 'street2': None, 'number': '1', 'prefix': None,
#  'street': 'REALLY BIG ROCKS', 'postal_code': None, 'unit': None,
#  'city': 'MPLS', 'state': 'MN', 'street_type': None, 'street_type2': None,
#  'suffix2': None}
# >>> parse('s 1st st at washington ave n, mpls, mn')
# {'suffix': None, 'unit_prefix': None, 'prefix2': None,
#  'street2': 'WASHINGTON', 'prefix': 'S', 'street': '1ST',
#  'postal_code': None, 'city': 'MPLS', 'state': 'MN', 'street_type': 'ST',
#  'street_type2': 'AVE', 'suffix2': 'N'}

