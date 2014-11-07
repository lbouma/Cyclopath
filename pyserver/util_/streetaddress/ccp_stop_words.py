# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('ccp_stp_wrds')

# This isn't a perfect implementation, but we can use different stop words
# depending on what we're searching.
# 
# Addy_Stop_Words__Annotation
# Addy_Stop_Words__Tag
# Addy_Stop_Words__Thread
# Addy_Stop_Words__Byway
# Addy_Stop_Words__Region
# Addy_Stop_Words__Waypoint

class Addy_Stop_Words__Item_Versioned(object):

   # Here's the vim command to convert debug output to this table.
   #
   # See the script: statewide_munis_lookup.py
   # which writes lines like:
   # Oct-25 01:35:19  DEBG      stwd_munis_l  #  cnt:    50280 / ['ve']
   #
   # .,$s/^[-:_a-zA-Z0-9 ]\+#  cnt: \+\(\d\+\) \/ \['\([^']\+\)']/      '\2', # in \1 names/gc

   # NOTE: The search fcn. uses this table, which is important for longer
   #       words: that is, the search fcn. should consider 1-, 2-, and maybe
   #       even 3-letter words as stop words, unless they're &'ed to a street
   #       name (e.g., searching just 'ave' returns 0 results, but searching
   #       'washington&ave' is ok (but not 'washington|ave')).
   #

   lookup = set([
      'ave', # in 50280 names
      'st', # in 34568 names
      'via', # in 21863 names
      'hwy', # in 17991 names
      'rd', # in 16318 names
      'trail', # in 11017 names
      'dr', # in 10541 names
      'la', # in 9952 names
      'lake', # in 6754 names
      'blvd', # in 5981 names
      'park', # in 5642 names
      'route', # in 5009 names
      'ct', # in 3554 names
      'tr', # in 2843 names
      'cir', # in 2565 names
      'pkwy', # in 2487 names

      # BUG nnnn: What if someone really is looking for a nearby river or
      #           creek? Instead of stop words, can we also search for
      #           river and creek in the user's viewport? Like, rather
      #           than consider common words in road names as stop words,
      #           instead just restrict the bbox: so, do two searches.
      #           E.g., if I search 'mississippi river', pyserver looks
      #           for 'mississippi&river', 'mississippi' (since in Minnesota
      #           it's probably not a common word), and then searches
      #           for 'river' just encompassing the user's viewport (otherwise
      #           we'd return way too many results).
      #           As it stands, not doing bbox searches in general is probably
      #           bad news for Statewide... not only will we get too many hits,
      #           those hits will be all over the map...
      #
      #           Argh, maybe what we really need is a LIMIT on the inner
      #           SQL... meaning we need a way to rank results in the inner...
      'river', # in 2462 names
      'creek', # in 1892 names

      'pl', # in 1672 names
      'way', # in 1447 names
      'path', # in 1196 names
      'road', # in 1099 names
      'gateway', # in 844 names
      'view', # in 706 names
      'ridge', # in 700 names
      'summit', # in 663 names
      'center', # in 568 names
      'ter', # in 487 names
      'bluffs', # in 436 names
      'hills', # in 420 names
      'valley', # in 380 names
      'hill', # in 372 names
      'bridge', # in 356 names
      'street', # in 336 names
      'point', # in 280 names
      'avenue', # in 276 names
      'heights', # in 267 names
      'highway', # in 248 names
      #'cv', # in 233 names
      #'shore', # in 230 names
      #'lane', # in 223 names
      #'grove', # in 200 names
      #'lk', # in 190 names
      #'rapids', # in 178 names
      #'prairie', # in 171 names
      #'ferry', # in 166 names
      #'lakes', # in 161 names
      #'drive', # in 158 names
      #'island', # in 158 names
      #'extension', # in 157 names
      #'dale', # in 155 names
      #'pine', # in 152 names
      #'parkway', # in 139 names
      #'curve', # in 121 names
      #'crossing', # in 120 names
      #'meadow', # in 120 names
      #'crossroad', # in 107 names
      #'fort', # in 104 names
      #'loop', # in 102 names
      #'ln', # in 101 names
      ])

   # MAYBE: analyze all item names are make stop words out of common words

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Annotation(object):

# BUG nnnn: The searched words are the street type search words.
#           What we really want to do is to ignore other popular
#           words that occur hundreds of times, i.e., by analyzing
#           all notes and tallying all word usages.

   lookup = set([
      'is', # in 907 names
      'road', # in 490 names
      'path', # in 391 names
      'trail', # in 360 names
      'bridge', # in 299 names
      'lane', # in 297 names
      'ave', # in 220 names
      'street', # in 220 names
      'way', # in 201 names
      'park', # in 193 names
      'route', # in 193 names
      'hill', # in 170 names
      'st', # in 164 names
      'lanes', # in 154 names
      'lake', # in 147 names



      # ???
      'minneapolis',
      'mpls',
      'minnesota',
      'mn',

      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Tag(object):

   # Rather than use the street type stop words, we need tag counts.

# BUG nnnn: Analyze Tag application counts and make this lookup table.

   lookup = set([
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Thread(object):

   # MAYBE: Thread stop words? Probably not necessary... yet.
   #        We could just do the same word-counting as proposed
   #        for figuring out annotation stop words.

   lookup = set([
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Byway(object):

   # BUG nnnn: Instead of just searching street types (from
   # addressconf.Streets.STREET_TYPES_LIST: see the dev script,
   # scripts/setupcp/greatermn/statewide_munis_lookup.py),
   # we could count all word usages in byway names.

   lookup = set([
      'ave', # in 43253 names
      'st', # in 32850 names
      'hwy', # in 16125 names
      'rd', # in 14743 names
      'dr', # in 10354 names
      'la', # in 9894 names
      'park', # in 5474 names
      'blvd', # in 5350 names
      'lake', # in 4884 names
      'trail', # in 4361 names
      'ct', # in 3557 names
      'tr', # in 2758 names
      'cir', # in 2566 names
      'pkwy', # in 2102 names
      'creek', # in 2043 names
      'pl', # in 1671 names
      'way', # in 1417 names
      'path', # in 1100 names
      'river', # in 971 names
      'road', # in 958 names
      'ridge', # in 773 names
      'valley', # in 673 names
      'view', # in 652 names
      'ter', # in 487 names
      'center', # in 477 names
      'hill', # in 396 names
      'hills', # in 394 names
      'highway', # in 379 names
      'island', # in 344 names
      'street', # in 309 names
      #'prairie', # in 284 names
      'point', # in 261 names
      'pine', # in 249 names
      'grove', # in 245 names
      'forest', # in 244 names
      'shore', # in 236 names
      'heights', # in 234 names
      'cv', # in 233 names
      'bridge', # in 229 names
      #'dale', # in 212 names
      #'summit', # in 209 names
      #'avenue', # in 199 names
      #'meadow', # in 182 names
      #'orchard', # in 180 names
      #'lane', # in 167 names
      #'cliff', # in 160 names
      #'terrace', # in 157 names
      #'curve', # in 147 names
      #'lk', # in 144 names
      #'parkway', # in 141 names
      #'drive', # in 137 names
      #'spring', # in 136 names
      #'lakes', # in 135 names
      #'glen', # in 134 names
      #'rapids', # in 129 names
      #'bluff', # in 120 names
      #'circle', # in 114 names
      #'garden', # in 105 names
      #'mill', # in 105 names
      #'ln', # in 102 names
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Region(object):

   # BUG nnnn: See earlier Bug nnnns in this file. We could word-count all
   # region names to make this lookup... but so far there aren't many regions
   # to begin with, so until there are, this isn't that big of a deal.

   lookup = set([
      #'park', # in 45 names
      #'st', # in 34 names
      #'lake', # in 29 names
      #'river', # in 11 names
      #'creek', # in 10 names
      #'trail', # in 10 names
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__In_Region(object):

   # FIXME: The original CcpV1 search method finds points within regions whose
   #        names match part of the query. Which is... okay for neighborhoods,
   #        but pretty ridiculous for large cities.

   lookup = set([
      'minnesota',
      #'minn',
      #'mn',
      'minneapolis',
      'saint paul',
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class Addy_Stop_Words__Waypoint(object):

   lookup = set([
      'park', # in 302 names
      'lake', # in 228 names
      'center', # in 123 names
      'st', # in 104 names
      #'trail', # in 75 names
      #'station', # in 71 names
      #'ave', # in 49 names
      #'point', # in 43 names
      #'bridge', # in 39 names
      #'garden', # in 39 names
      #'hwy', # in 11 names
      #'island', # in 11 names
      #'prairie', # in 11 names
      #'course', # in 10 names
      #'falls', # in 10 names
      #'gateway', # in 10 names
      #'green', # in 10 names
      #'place', # in 10 names
      #'rapids', # in 10 names
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class U_S_State_Nicknames(object):

   # select state_name, state_abbrev from state_name_abbrev;
   # .,$s/\s*\(\w\+\)\s*|\s*\(.*\)/      '\2': '\1',/gc

   by_synonym = {
      #'minnesota': 'minnesota',
      'minn': 'minnesota',
      #'gopher state': 'minnesota',
      #'land of lakes': 'minnesota',
      #'land of 10,000 lakes': 'minnesota',
      #'land of 10000 lakes': 'minnesota',
      #'land of sky-blue waters': 'minnesota',
      #'north star state': 'minnesota',
      #'hawkeye state': 'iowa',
      #'rough rider state': 'north dakota',
      #'mount rushmore state': 'south dakota',
      #'sunshine state': 'south dakota',
      'wis': 'wisconsin',
      #'cheese state': 'wisconsin',
      #'badger state': 'wisconsin',
      }

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

class City_Names_MN(object):

   # See the table: state_city_abbrev.
   # This table is the exact same...

   by_nick_name = {
      'alex': 'alexandria',
      'app': 'appleton',
      'a hills': 'arden hills',
      'spamtown': 'austin',
      'spamtown usa': 'austin',
      'cann': 'cannon falls',
      'troit': 'detroit lakes',
      'eb': 'east bethel',
      'ep': 'eden prairie',
      'e.p.': 'eden prairie',
      'bubble': 'edina',
      'gv': 'golden valley',
      'marine': 'marine on saint croix',
      'mosc': 'marine on saint croix',
      'city of lakes': 'minneapolis',
      'mill city': 'minneapolis',
      'mini apple': 'minneapolis',
      'mpls': 'minneapolis',
      'mn city': 'minnesota city',
      'mn lake': 'minnesota lake',
      'mtka': 'minnetonka',
      'mtka beach': 'minnetonka beach',
      'mtn iron': 'mountain iron',
      'mtn lake': 'mountain lake',
      'north stp': 'north saint paul',
      'nstp': 'north saint paul',
      'nsp': 'north saint paul',
      'norwood': 'norwood young america',
      'young america': 'norwood young america',
      'ny mills': 'new york mills',
      'prap': 'park rapids',
      'birdtown': 'robbinsdale',
      'med town': 'rochester',
      'slp': 'saint louis park',
      'pigs eye': 'saint paul',
      'stp': 'saint paul',
      'st p': 'saint paul',
      '2harb': 'two harbors',
      'hockeytown': 'warroad',
      'west stp': 'west saint paul',
      'wstp': 'west saint paul',
      'wsp': 'west saint paul',
      # If we want this silly syn., we'd have to raise n_words_in_longest_name.
      'turkey capital of the world': 'worthington',
      }

   # MAGIC_NUMBER: MN City names follow a nice set of rules: only characters
   #               (no numbers, punctuation, or symbols), and the longest city
   #               names are four words long. These facts help us parse a user
   #               query for the city names.
   # 'lake saint croix beach'
   # 'marine on saint croix',
   #n_words_in_longest_name = 4
   # 'turkey capital of the world'
   n_words_in_longest_name = 5

   # In Python, searching a list is O(n), but a set should be amortized O(1)
   # (though worst case O(n)?).

   # SELECT municipal_name INTO TEMPORARY TABLE mn_cities
   #  FROM state_cities ORDER BY municipal_name;
   # COPY mn_cities to STDOUT;

   city_names = set([
      'ada',
      'adams',
      'adrian',
      'afton',
      'aitkin',
      'akeley',
      'albany',
      'alberta',
      'albert lea',
      'albertville',
      'alden',
      'aldrich',
      'alexandria',
      'alpha',
      'altura',
      'alvarado',
      'amboy',
      'andover',
      'annandale',
      'anoka',
      'appleton',
      'apple valley',
      'arco',
      'arden hills',
      'argyle',
      'arlington',
      'ashby',
      'askov',
      'atwater',
      'audubon',
      'aurora',
      'austin',
      'avoca',
      'avon',
      'babbitt',
      'backus',
      'badger',
      'bagley',
      'balaton',
      'barnesville',
      'barnum',
      'barrett',
      'barry',
      'battle lake',
      'baudette',
      'baxter',
      'bayport',
      'beardsley',
      'beaver bay',
      'beaver creek',
      'becker',
      'bejou',
      'belgrade',
      'bellechester',
      'belle plaine',
      'bellingham',
      'beltrami',
      'belview',
      'bemidji',
      'bena',
      'benson',
      'bertha',
      'bethel',
      'bigelow',
      'big falls',
      'bigfork',
      'big lake',
      'bingham lake',
      'birchwood village',
      'bird island',
      'biscay',
      'biwabik',
      'blackduck',
      'blaine',
      'blomkest',
      'blooming prairie',
      'bloomington',
      'blue earth',
      'bluffton',
      'bock',
      'borup',
      'bovey',
      'bowlus',
      'boyd',
      'boy river',
      'braham',
      'brainerd',
      'brandon',
      'breckenridge',
      'breezy point',
      'brewster',
      'bricelyn',
      'brooklyn center',
      'brooklyn park',
      'brook park',
      'brooks',
      'brookston',
      'brooten',
      'browerville',
      'brownsdale',
      'browns valley',
      'brownsville',
      'brownton',
      'bruno',
      'buckman',
      'buffalo',
      'buffalo lake',
      'buhl',
      'burnsville',
      'burtrum',
      'butterfield',
      'byron',
      'caledonia',
      'callaway',
      'calumet',
      'cambridge',
      'campbell',
      'canby',
      'cannon falls',
      'canton',
      'carlos',
      'carlton',
      'carver',
      'cass lake',
      'cedar mills',
      'center city',
      'centerville',
      'ceylon',
      'champlin',
      'chandler',
      'chanhassen',
      'chaska',
      'chatfield',
      'chickamaw beach',
      'chisago city',
      'chisholm',
      'chokio',
      'circle pines',
      'clara city',
      'claremont',
      'clarissa',
      'clarkfield',
      'clarks grove',
      'clearbrook',
      'clear lake',
      'clearwater',
      'clements',
      'cleveland',
      'climax',
      'clinton',
      'clitherall',
      'clontarf',
      'cloquet',
      'coates',
      'cobden',
      'cohasset',
      'cokato',
      'cold spring',
      'coleraine',
      'cologne',
      'columbia heights',
      'comfrey',
      'comstock',
      'conger',
      'cook',
      'coon rapids',
      'corcoran',
      'correll',
      'cosmos',
      'cottage grove',
      'cottonwood',
      'courtland',
      'cromwell',
      'crookston',
      'crosby',
      'crosslake',
      'crystal',
      'currie',
      'cuyuna',
      'cyrus',
      'dakota',
      'dalton',
      'danube',
      'danvers',
      'darfur',
      'darwin',
      'dassel',
      'dawson',
      'dayton',
      'deephaven',
      'deer creek',
      'deer river',
      'deerwood',
      'de graff',
      'delano',
      'delavan',
      'delhi',
      'dellwood',
      'denham',
      'dennison',
      'dent',
      'detroit lakes',
      'dexter',
      'dilworth',
      'dodge center',
      'donaldson',
      'donnelly',
      'doran',
      'dover',
      'dovray',
      'duluth',
      'dumont',
      'dundas',
      'dundee',
      'dunnell',
      'eagan',
      'eagle bend',
      'eagle lake',
      'east bethel',
      'east grand forks',
      'east gull lake',
      'easton',
      'echo',
      'eden prairie',
      'eden valley',
      'edgerton',
      'edina',
      'effie',
      'eitzen',
      'elba',
      'elbow lake',
      'elgin',
      'elizabeth',
      'elko',
      'elk river',
      'elkton',
      'ellendale',
      'ellsworth',
      'elmdale',
      'elmore',
      'elrosa',
      'ely',
      'elysian',
      'emily',
      'emmons',
      'erhard',
      'erskine',
      'evan',
      'evansville',
      'eveleth',
      'excelsior',
      'eyota',
      'fairfax',
      'fairmont',
      'falcon heights',
      'faribault',
      'farmington',
      'farwell',
      'federal dam',
      'felton',
      'fergus falls',
      'fertile',
      'fifty lakes',
      'finlayson',
      'fisher',
      'flensburg',
      'floodwood',
      'florence',
      'foley',
      'forada',
      'forest lake',
      'foreston',
      'fort ripley',
      'fosston',
      'fountain',
      'foxhome',
      'franklin',
      'frazee',
      'freeborn',
      'freeport',
      'fridley',
      'frost',
      'fulda',
      'funkley',
      'garfield',
      'garrison',
      'garvin',
      'gary',
      'gaylord',
      'gem lake',
      'geneva',
      'genola',
      'georgetown',
      'ghent',
      'gibbon',
      'gilbert',
      'gilman',
      'glencoe',
      'glenville',
      'glenwood',
      'glyndon',
      'golden valley',
      'gonvick',
      'goodhue',
      'goodridge',
      'good thunder',
      'goodview',
      'graceville',
      'granada',
      'grand marais',
      'grand meadow',
      'grand rapids',
      'granite falls',
      'grant',
      'grasston',
      'greenbush',
      'greenfield',
      'green isle',
      'greenwald',
      'greenwood',
      'grey eagle',
      'grove city',
      'grygla',
      'gully',
      'hackensack',
      'hadley',
      'hallock',
      'halma',
      'halstad',
      'hamburg',
      'ham lake',
      'hammond',
      'hampton',
      'hancock',
      'hanley falls',
      'hanover',
      'hanska',
      'harding',
      'hardwick',
      'harmony',
      'harris',
      'hartland',
      'hastings',
      'hatfield',
      'hawley',
      'hayfield',
      'hayward',
      'hazel run',
      'hector',
      'heidelberg',
      'henderson',
      'hendricks',
      'hendrum',
      'henning',
      'henriette',
      'herman',
      'hermantown',
      'heron lake',
      'hewitt',
      'hibbing',
      'hill city',
      'hillman',
      'hills',
      'hilltop',
      'hinckley',
      'hitterdal',
      'hoffman',
      'hokah',
      'holdingford',
      'holland',
      'hollandale',
      'holloway',
      'holt',
      'hopkins',
      'houston',
      'howard lake',
      'hoyt lakes',
      'hugo',
      'humboldt',
      'hutchinson',
      'ihlen',
      'independence',
      'international falls',
      'inver grove heights',
      'iona',
      'iron junction',
      'ironton',
      'isanti',
      'isle',
      'ivanhoe',
      'jackson',
      'janesville',
      'jasper',
      'jeffers',
      'jenkins',
      'johnson',
      'jordan',
      'kandiyohi',
      'karlstad',
      'kasota',
      'kasson',
      'keewatin',
      'kelliher',
      'kellogg',
      'kennedy',
      'kenneth',
      'kensington',
      'kent',
      'kenyon',
      'kerkhoven',
      'kerrick',
      'kettle river',
      'kiester',
      'kilkenny',
      'kimball',
      'kinbrae',
      'kingston',
      'kinney',
      'la crescent',
      'lafayette',
      'lake benton',
      'lake bronson',
      'lake city',
      'lake crystal',
      'lake elmo',
      'lakefield',
      'lake henry',
      'lakeland',
      'lakeland shores',
      'lake lillian',
      'lake park',
      'lake saint croix beach',
      'lake shore',
      'lakeville',
      'lake wilson',
      'lamberton',
      'lancaster',
      'landfall',
      'lanesboro',
      'laporte',
      'la prairie',
      'la salle',
      'lastrup',
      'lauderdale',
      'le center',
      'lengby',
      'leonard',
      'leonidas',
      'le roy',
      'lester prairie',
      'le sueur',
      'lewiston',
      'lewisville',
      'lexington',
      'lilydale',
      'lindstrom',
      'lino lakes',
      'lismore',
      'litchfield',
      'little canada',
      'little falls',
      'littlefork',
      'long beach',
      'long lake',
      'long prairie',
      'longville',
      'lonsdale',
      'loretto',
      'louisburg',
      'lowry',
      'lucan',
      'luverne',
      'lyle',
      'lynd',
      'mabel',
      'madelia',
      'madison',
      'madison lake',
      'magnolia',
      'mahnomen',
      'mahtomedi',
      'manchester',
      'manhattan beach',
      'mankato',
      'mantorville',
      'maple grove',
      'maple lake',
      'maple plain',
      'mapleton',
      'mapleview',
      'maplewood',
      'marble',
      'marietta',
      'marine on saint croix',
      'marshall',
      'mayer',
      'maynard',
      'mazeppa',
      'mcgrath',
      'mcgregor',
      'mcintosh',
      'mckinley',
      'meadowlands',
      'medford',
      'medicine lake',
      'medina',
      'meire grove',
      'melrose',
      'menahga',
      'mendota',
      'mendota heights',
      'mentor',
      'middle river',
      'miesville',
      'milaca',
      'milan',
      'millerville',
      'millville',
      'milroy',
      'miltona',
      'minneapolis',
      'minneiska',
      'minneota',
      'minnesota city',
      'minnesota lake',
      'minnetonka',
      'minnetonka beach',
      'minnetrista',
      'mizpah',
      'montevideo',
      'montgomery',
      'monticello',
      'montrose',
      'moorhead',
      'moose lake',
      'mora',
      'morgan',
      'morris',
      'morristown',
      'morton',
      'motley',
      'mound',
      'mounds view',
      'mountain iron',
      'mountain lake',
      'murdock',
      'myrtle',
      'nashua',
      'nashwauk',
      'nassau',
      'nelson',
      'nerstrand',
      'nevis',
      'new auburn',
      'new brighton',
      'newfolden',
      'new germany',
      'new hope',
      'new london',
      'new market',
      'new munich',
      'newport',
      'new prague',
      'new richland',
      'new trier',
      'new ulm',
      'new york mills',
      'nicollet',
      'nielsville',
      'nimrod',
      'nisswa',
      'norcross',
      'north branch',
      'northfield',
      'north mankato',
      'north oaks',
      'northome',
      'northrop',
      'north saint paul',
      'norwood young america',
      'oakdale',
      'oak grove',
      'oak park heights',
      'odessa',
      'odin',
      'ogema',
      'ogilvie',
      'okabena',
      'oklee',
      'olivia',
      'onamia',
      'ormsby',
      'orono',
      'oronoco',
      'orr',
      'ortonville',
      'osakis',
      'oslo',
      'osseo',
      'ostrander',
      'otsego',
      'ottertail',
      'owatonna',
      'palisade',
      'parkers prairie',
      'park rapids',
      'paynesville',
      'pease',
      'pelican rapids',
      'pemberton',
      'pennock',
      'pequot lakes',
      'perham',
      'perley',
      'peterson',
      'pierz',
      'pillager',
      'pine city',
      'pine island',
      'pine river',
      'pine springs',
      'pipestone',
      'plainview',
      'plato',
      'pleasant lake',
      'plummer',
      'plymouth',
      'porter',
      'preston',
      'princeton',
      'prinsburg',
      'prior lake',
      'proctor',
      'quamba',
      'racine',
      'ramsey',
      'randall',
      'randolph',
      'ranier',
      'raymond',
      'red lake falls',
      'red wing',
      'redwood falls',
      'regal',
      'remer',
      'renville',
      'revere',
      'rice',
      'richfield',
      'richmond',
      'richville',
      'riverton',
      'robbinsdale',
      'rochester',
      'rock creek',
      'rockford',
      'rockville',
      'rogers',
      'rollingstone',
      'ronneby',
      'roosevelt',
      'roscoe',
      'roseau',
      'rose creek',
      'rosemount',
      'roseville',
      'rothsay',
      'round lake',
      'royalton',
      'rush city',
      'rushford',
      'rushford village',
      'rushmore',
      'russell',
      'ruthton',
      'rutledge',
      'sabin',
      'sacred heart',
      'saint anthony',
      'saint anthony',
      'saint augusta',
      'saint bonifacius',
      'saint charles',
      'saint clair',
      'saint cloud',
      'saint francis',
      'saint hilaire',
      'saint james',
      'saint joseph',
      'saint leo',
      'saint louis park',
      'saint martin',
      'saint marys point',
      'saint michael',
      'saint paul',
      'saint paul park',
      'saint peter',
      'saint rosa',
      'saint stephen',
      'saint vincent',
      'sanborn',
      'sandstone',
      'sargeant',
      'sartell',
      'sauk centre',
      'sauk rapids',
      'savage',
      'scanlon',
      'seaforth',
      'sebeka',
      'sedan',
      'shafer',
      'shakopee',
      'shelly',
      'sherburn',
      'shevlin',
      'shoreview',
      'shorewood',
      'silver bay',
      'silver lake',
      'skyline',
      'slayton',
      'sleepy eye',
      'sobieski',
      'solway',
      'south haven',
      'south saint paul',
      'spicer',
      'springfield',
      'spring grove',
      'spring hill',
      'spring lake park',
      'spring park',
      'spring valley',
      'squaw lake',
      'stacy',
      'staples',
      'starbuck',
      'steen',
      'stephen',
      'stewart',
      'stewartville',
      'stillwater',
      'stockton',
      'storden',
      'strandquist',
      'strathcona',
      'sturgeon lake',
      'sunburg',
      'sunfish lake',
      'swanville',
      'taconite',
      'tamarack',
      'taopi',
      'taunton',
      'taylors falls',
      'tenney',
      'tenstrike',
      'thief river falls',
      'thomson',
      'tintah',
      'tonka bay',
      'tower',
      'tracy',
      'trail',
      'trimont',
      'trommald',
      'trosky',
      'truman',
      'turtle river',
      'twin lakes',
      'twin valley',
      'two harbors',
      'tyler',
      'ulen',
      'underwood',
      'upsala',
      'urbank',
      'utica',
      'vadnais heights',
      'vergas',
      'vermillion',
      'verndale',
      'vernon center',
      'vesta',
      'victoria',
      'viking',
      'villard',
      'vining',
      'virginia',
      'wabasha',
      'wabasso',
      'waconia',
      'wadena',
      'wahkon',
      'waite park',
      'waldorf',
      'walker',
      'walnut grove',
      'walters',
      'waltham',
      'wanamingo',
      'wanda',
      'warba',
      'warren',
      'warroad',
      'waseca',
      'watertown',
      'waterville',
      'watkins',
      'watson',
      'waubun',
      'waverly',
      'wayzata',
      'welcome',
      'wells',
      'wendell',
      'westbrook',
      'west concord',
      'westport',
      'west saint paul',
      'west union',
      'whalan',
      'wheaton',
      'white bear lake',
      'wilder',
      'willernie',
      'williams',
      'willmar',
      'willow river',
      'wilmont',
      'wilton',
      'windom',
      'winger',
      'winnebago',
      'winona',
      'winsted',
      'winthrop',
      'winton',
      'wolf lake',
      'wolverton',
      'woodbury',
      'wood lake',
      'woodland',
      'woodstock',
      'worthington',
      'wrenshall',
      'wright',
      'wykoff',
      'wyoming',
      'zemple',
      'zimmerman',
      'zumbro falls',
      'zumbrota',
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

# ***

