
# ======================================================================

# Circa Winter 2013: When [lb] developed the CcpV2 tilecache_update
# script (the one with skins that updates coverage_area and generates
# the MapServer and TileCache config files).

"""

# FIXME: for tilecache_update, you'll want to not reload all link_values all
# the time -- so make an all-link_values cache.

./ccp.py -r -t branch -U landonb --no-password -b -1

./ccp.py -t byway -r -C 1 -f dont_load_feat_attcs 1
./ccp.py -t byway -r -C 1 -f dont_load_feat_attcs 1 -I 983982

./ccp.py -t byway -r -C 1 -f dont_load_feat_attcs 1 -I 983982 -b 2404832

./ccp.py -t byway -r -C 1 -I 983982 -b 2404832

# Zoom 10 (89504 items)
#May-03 20:58:20  INFO     grax.item_mgr  #  search_for_wrap: read 89504 byways at r:cur in 0.72 mins.
# Making the temp table of 89,000 stack IDs is slow.
#May-03 20:59:03  INFO     grax.item_mgr  #  load_feats_and_attcs: loaded temp table in 0.72 mins.
./ccp.py -t byway -r -b 2404832 -B 442368.0,4964352.0,491520.0,5013504.0 -U landonb --no-password --verbose

# Too big
./ccp.py -t waypoint -r -b 2404832 -B 442368.0,4964352.0,491520.0,5013504.0 --verbose
# less big
./ccp.py -t waypoint -r -b 2404832 -B 489472.0,4980736.0,491520.0,4982784.0 --verbose -U landonb --no-password -G
./ccp.py -t waypoint -r -b 2404832 -B 489472.0,4980736.0,491563.5,4982784.0 --verbose -U landonb --no-password -G

 
./ccp.py -t waypoint -s "lamplighter"
./ccp.py -t waypoint -r --stack_ids 1496281 -G


# Zoom 13 (303 items) / Huffy new code, incls. link_values, and is leafy query
./ccp.py -t byway -r -b 2404832 -B 489472.0,4980736.0,491520.0,4982784.0
#May-03 13:37:46  INFO      argparse_ccp  #  Script completed in 0.05 mins.
#May-03 13:37:46  INFO          ccp_tool  #  Found 302 items!
# Zoom 13 / Runic old code
./ccp.py -t byway -r -b 2405641 -B 489472.0,4980736.0,491520.0,4982784.0
#May-03 13:40:11  INFO      argparse_ccp  #  Script completed in 0.07 mins.
#May-03 13:40:11  INFO          ccp_tool  #  Found 308 items! (305 for raw sql)

# Zoom 13 / Huffy new code, incls. link_values, and is leafy query
./ccp.py -t byway -r -R hist 15844 -B 489472.0,4980736.0,491520.0,4982784.0
#May-03 13:37:46  INFO      argparse_ccp  #  Script completed in 0.02 mins.
#May-03 13:37:46  INFO          ccp_tool  #  Found 303 items!
# Zoom 13 / Runic old code
./ccp.py -t byway -r -R hist 15844 -B 489472.0,4980736.0,491520.0,4982784.0
#May-03 13:40:11  INFO      argparse_ccp  #  Script completed in 0.00 mins.
#May-03 13:40:11  INFO          ccp_tool  #  Found 303 items! (305 for raw sql)


./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R hist 15844 -b 2404832 --verbose

# FIXME: This is getting basemap items. I think that's okay...
./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R updated 14844 15844 -b 2404832 --verbose

# Added private watch regions
./ccp.py -t region -r -R updated 15744 15844 --verbose -U landonb --no-password



./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R diff 14844 15844 --verbose
./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R diff 14844 15844 -b 2404832 --verbose -U landonb --no-password
./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R diff 14844 15844 --verbose -G


./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R diff 14844 15844 --verbose -U landonb --no-password -I 1529618 -b 2404832 
./ccp.py -t byway -r -B 489472.0,4980736.0,491520.0,4982784.0 -R diff 14844 15844 --verbose -U landonb --no-password -I 1529618

no match for branch, since it was created after branch was
./ccp.py -t byway -r -R diff 14844 15844 --verbose -U landonb --no-password -I 1529618 -b 2404832 
./ccp.py -t byway -r -R diff 14844 15844 --verbose -U landonb --no-password -I 1529618

this item was created after last merge
./ccp.py -t byway -r -R hist 14844 --verbose -U landonb --no-password -I 1529618 -b 2404832 
./ccp.py -t byway -r -R hist 15844 --verbose -U landonb --no-password -I 1529618 -b 2404832 
./ccp.py -t byway -r -R hist 14844 --verbose -U landonb --no-password -I 1529618
./ccp.py -t byway -r -R hist 15844 --verbose -U landonb --no-password -I 1529618
./ccp.py -t byway -r -R hist 14517 --verbose -U landonb --no-password -I 1529618
./ccp.py -t byway -r -R hist 14519 --verbose -U landonb --no-password -I 1529618

./ccp.py -t byway -r -R diff 14517 14519 --verbose -U landonb --no-password -I 1529618

This works with the -U landonb --no-password because of ./ccp.py not same as gwis
./ccp.py -t byway -r -b 2404832 -B 489472.0,4980736.0,491520.0,4982784.0
This gives an insufficient priveleges error
./ccp.py -t byway -r -b 2404832 -B 489472.0,4980736.0,491520.0,4982784.0 -G
./ccp.py -t byway -r -b 2404832 -B 489472.0,4980736.0,491520.0,4982784.0 -G -U landonb --no-password

TEST: Query that returns just the leafiest geofeatures (you can still get non-leafy links?)
TEST: Do MetC geofeatures respek basemap link_values correctly? Try making tag on basemap 
item and make sure it doesn't affect branch.

BROKEN
POST /gwis?rqst=checkout&ityp=attribute&rev=15844&brid=2404832&gwv=3&browid=E9FCC615-9121-1720-EA6F-8F8BAAD59AC7&sessid=3BDB1FF3-B34B-24DE-E233-18A3071F7678&body=yes HTTP/1.1
./ccp.py -t attribute -r -b 2404832 -G -U landonb --no-password

./ccp.py -t terrain -r -b 2404832 -B 478350.095,4975088.58,479013.095,4975671.58 -G -U landonb --no-password
./ccp.py -t byway -r -b 2404832 -B 478350.095,4975088.58,479013.095,4975671.58 -G -U landonb --no-password
./ccp.py -t waypoint -r -b 2404832 -B 478350.095,4975088.58,479013.095,4975671.58 -G -U landonb --no-password
./ccp.py -t region -r -b 2404832 -B 478350.095,4975088.58,479013.095,4975671.58 -G -U landonb --no-password


POST /gwis?rqst=checkout&ityp=terrain&rev=15844&brid=2404832&bbxi=478350.095,4975088.58,479013.095,4975671.58&gwv=3&browid=E9FCC615-9121-1720-EA6F-8F8BAAD59AC7&sessid=3BDB1FF3-B34B-24DE-E233-18A3071F7678&body=yes HTTP/1.1


lval counts:
# This returns GWIS_Error... so can't checkout link_values by there ID?
./ccp.py -t link_value -r -b 2404832 -G -U landonb --no-password -I 1083351,1137386
./ccp.py -t link_value -r -b 2404832 -G -U landonb --no-password -f only_rhs_stack_ids 1083351,1137386

"""

# ======================================================================

