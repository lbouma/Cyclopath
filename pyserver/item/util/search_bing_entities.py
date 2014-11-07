# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('_bing_ents')

class Bing_Entity_Types(object):

   # For the list of entity names, see
   #  http://msdn.microsoft.com/en-us/library/ff728811.aspx

   # NOTE: This class is not used. Maybe someday.
   #       See: item.util.geocode.geocode_bing.entity_types.

   lookup = set([
      'Address', # A physical address of a location.
      'AdminDivision1', # A first-order, initial political subdivision of a [Sovereign], such as a state, a province, a department, a region, or a prefecture.
      'AdminDivision2', # A second-order political subdivision of a [CountryRegion], a division of an [AdminDivision1] or a [Dependent].
      'AdminDivision3', # A third-order political subdivision of a [CountryRegion], a division of an [AdminDivision2].
      # 'AdministrativeBuilding', # A building that contains governmental offices or facilities.
      'AdministrativeDivision', # An administrative division of a [CountryRegion], undifferentiated as to administrative level.
      #'AgriculturalStructure', # A [Structure] used for agricultural purposes.
      'Airport', # A place where aircraft regularly land and take off, with runways, navigational aids, and facilities for handling passengers and/or cargo.
      # 'AirportRunway', # An improved surface suitable for landing airplanes.
      #'AmusementPark', # A facility that contains rides and other attractions, such as a theme park.
      #'AncientSite', # A place where archeological remains, old structures, or cultural artifacts are located.
      # 'Aquarium', # A place where marine life is displayed to the public.
      #'Archipelago', # A logical grouping of [Island]s.
      # 'Autorail', # A [Railway] that carries automobiles.
      # 'Basin', # A low-lying area mostly or wholly surrounded by higher ground.
      #'Battlefield', # A site of a land battle of historical importance.
      # 'Bay', # An area of water partially enclosed by an indentation of shoreline.
      # 'Beach', # A [Coast] with a surface of sand, pebbles, or small rocks.
      # 'BorderPost', # A post or station at an international boundary for regulating the movement of people and goods.
      # 'Bridge', # A structure erected across an obstacle, such as a stream or road, that is used by vehicles and pedestrians.
      # 'BusinessCategory', # A category that identifies a kind of business.
      # 'BusinessCenter', # A place where a number of businesses are located.
      # 'BusinessName', # A name that identifies a business.
      # 'BusinessStructure', # A [Structure] used for commercial purposes.
      # 'BusStation', # A place where buses pick up and discharge passengers.
      # 'Camp', # A site occupied by tents, huts, or other shelters for temporary use.
      # 'Canal', # An artificially constructed watercourse.
      # 'Cave', # An underground passageway or chamber, or a cavity on the side of a cliff.
      # 'CelestialFeature', # A spherical body in space.
      # 'Cemetery', # A burial place or a burial ground.
      # 'Census1', # One of the set of the most detailed, lowest-level [CensusDistrict]s.
      # 'Census2', # One of the set of second-order [CensusDistrict]s composed by aggregating [Census1]s.
      # 'CensusDistrict', # A district defined by a national census bureau and used for statistical data collection.
      # 'Channel', # A body of water between two landmasses.
      # 'Church', # A building for public Christian worship.
      # 'CityHall', # A building that contains the administrative offices of a municipal government.
      # 'Cliff', # A high, steep-to-perpendicular slope that overlooks a lower area or a water body.
      # 'ClimateRegion', # An area of homogenous climactic conditions, as defined by modified Koeppen classes.
      # 'Coast', # An area of land adjacent to a [WaterFeature].
      # 'CommunityCenter', # A facility for community recreation and meetings.
      # 'Continent', # A very large landmass, surrounded by water and larger than an [Island], that forms one of the primary divisions of land on a [CelestialFeature].
      # 'ConventionCenter', # A large meeting hall for conventions and other meetings, and shows.
      # 'CountryRegion', # A primary [PoliticalUnit].
      # 'Courthouse', # A building in which courts of law are held.
      # 'Crater', # A generally circular, saucer-shaped, or bowl-shaped depression caused by volcanic or meteorite explosive action.
      # 'CulturalRegion', # An area of land with strong local identity, but no political status.
      # 'Current', # A large area of ocean where surface water flows in a certain constant general direction.
      # 'Dam', # A barrier constructed across a stream to impound water.
      # 'Delta', # An area where a [River] divides into many separate water channels as it enters a [Sea] or a [Lake].
      # 'Dependent', # A [PoliticalUnit] that is politically controlled by a [Sovereign], but separate geographically, and to some degree politically, such as a territory, a colony, or a dependency.
      # 'Desert', # A large area with low rainfall and little or no vegetation.
      # 'DisputedArea', # An area in political dispute that is not considered part of any [CountryRegion].
      # 'DrainageBasin', # A land region where all surface water drains into one specific [WaterFeature].
      # 'Dune', # A wave form, a ridge, or a star-shaped feature composed of sand.
      # 'EarthquakeEpicenter', # A place where the destructive force of a specific earthquake is centered.
      # 'Ecoregion', # A region with a homogeneous ecosystem, flora, and/or fauna.
      # 'EducationalStructure', # A place for providing instruction.
      # 'ElevationZone', # An area where the surface elevation of all land is within a defined range.
      # 'Factory', # A building or set of buildings where goods are manufactured, processed, or fabricated.
      # 'FerryRoute', # A route used by a boat, or by other floating conveyances regularly used to transport people and vehicles across a [WaterFeature].
      # 'FerryTerminal', # A structure and associated facilities where a ferry boat docks and takes on passengers, automobiles, and/or cargo.
      # 'FishHatchery', # A place for hatching fish eggs or raising fish.
      # 'Forest', # A large area of trees.
      # 'FormerAdministrativeDivision', # An [AdministrativeDivision] that no longer exists.
      # 'FormerPoliticalUnit', # A [PoliticalUnit] that no longer exists.
      # 'FormerSovereign', # A [Sovereign] that no longer exists.
      # 'Fort', # A defensive structure or earthwork.
      # 'Garden', # An enclosure for displaying selected plant life.
      # 'GeodeticFeature', # An invisible point, line, or area on the surface of a [CelestialFeature] that is used for geographic reference.
      # 'GeoEntity', # A single thing that has spatial extent and location.
      # 'GeographicPole', # One of the two points of intersection of the surface of a [CelestialFeature] and its axis of rotation.
      # 'Geyser', # A [HotSpring] that intermittently shoots water into the air.
      # 'Glacier', # A mass of ice, usually at high latitudes or high elevations, with sufficient thickness to flow away from the source area.
      # 'GolfCourse', # A recreational field where golf is played.
      # 'GovernmentStructure', # A [Structure] typically owned and operated by a governmental entity.
      # 'Heliport', # A place where helicopters land and take off.
      # 'Hemisphere', # A half of the surface of a [Celestial Feature], usually specified as northern, southern, eastern, or western.
      # 'HigherEducationFacility', # A place where students receive advanced or specialized education, such as a college or a university.
      # 'HistoricalSite', # A place of historical importance.
      # 'Hospital', # A building in which the sick or injured, especially those confined to bed, are medically treated.
      # 'HotSpring', # A place where hot water emerges from the ground.
      # 'Ice', # A large area covered with frozen water.
      # 'IndigenousPeoplesReserve', # An area of land set aside for aboriginal, tribal, or native populations.
      # 'IndustrialStructure', # A [Structure] used for industrial or extractive purposes.
      # 'InformationCenter', # A place where tourists and citizens can obtain information.
      # 'InternationalDateline', # The line running between geographic poles designated as the point where a calendar day begins.
      # 'InternationalOrganization', # An area of land composed of the member [PoliticalUnit]s of an official governmental organization composed of two or more [Sovereign]s.
      # 'Island', # An area of land completely surrounded by water and smaller than a [Continent].
      # 'Isthmus', # A narrow strip of land connecting two larger landmasses and bordered by water on two sides.
      # 'Junction', # A place where two or more roads join.
      # 'Lake', # An inland water body, usually fresh water.
      # 'LandArea', # A relatively small area of land exhibiting a common characteristic that distinguishes it from the surrounding land.
      # 'Landform', # A natural geographic feature on dry land.
      # 'LandmarkBuilding', # A [Structure] that is a well-known point of reference.
      # 'LatitudeLine', # An imaginary line of constant latitude that circles a [CelestialFeature], in which every point on the line is equidistant from a geographic pole.
      # 'Library', # A place where books and other media are stored and loaned out to the public or others.
      # 'Lighthouse', # A tall structure with a major navigation light.
      # 'LinguisticRegion', # An area of land where most of the population speaks the same language or speaks languages in the same linguistic family.
      # 'LongitudeLine', # An imaginary line of constant longitude on a [CelestialFeature] that runs from one geographic pole to the other.
      # 'MagneticPole', # A point on the surface of a [CelestialFeature] that is the origin for lines of magnetic force.
      # 'Marina', # A harbor facility for small boats.
      # 'Market', # A place where goods are bought and sold.
      # 'MedicalStructure', # A [Structure] in which the sick or injured are medically treated.
      # 'MetroStation', # A place where urban rapid transit trains pick up and drop off passengers, often underground or elevated.
      # 'MilitaryBase', # A place used by an armed service for storing arms and supplies, for accommodating and training troops, and as a base from which operations can be initiated.
      # 'Mine', # A place where mineral ores are extracted from the ground by excavating surface pits and subterranean passages.
      # 'Mission', # A place characterized by dwellings, school, church, hospital, and other facilities operated by a religious group for the purpose of providing charitable services and to propagate religion.
      # 'Monument', # A commemorative structure or statue.
      # 'Mosque', # A building for public Islamic worship.
      # 'Mountain', # An elevated landform that rises, often steeply, above surrounding land on most sides.
      # 'MountainRange', # A group of connected [Mountain]s.
      # 'Museum', # A building where objects of permanent interest in one or more of the arts and sciences are preserved and exhibited.
      # 'NauticalStructure', # A [Structure] used for nautical purposes.
      # 'NavigationalStructure', # A [Structure] used for navigational purposes.
      'Neighborhood', # A section of a [PopulatedPlace], usually homogenous and/or well-known, but often with indistinct boundaries.
      # 'Oasis', # An area in a [Desert] that contains water and plant life.
      # 'ObservationPoint', # A wildlife or scenic observation point.
      # 'Ocean', # A vast expanse of salt water, one of the major [Sea]s covering part of the earth.
      # 'OfficeBuilding', # A building that contains offices.
      # 'Park', # An area maintained as a place of scenic beauty, or for recreation.
      # 'ParkAndRide', # A parking lot reserved for mass transit commuters.
      # 'Pass', # A break in a [MountainRange] used for transportation from one side of the mountain range to the other.
      # 'Peninsula', # An elongated area of land projecting into a body of water and surrounded by water on three sides.
      # 'Plain', # An extensive area of comparatively level to gently undulating land, lacking surface irregularities.
      # 'Planet', # A [CelestialFeature] that orbits a star.
      # 'Plate', # A section of a planetary crust that is in motion relative to other tectonic plates.
      # 'Plateau', # An elevated plain with steep slopes on one or more sides.
      # 'PlayingField', # A tract of land used for playing team sports and/or other athletic events.
      # 'Pole', # A point on the surface of a [CelestialFeature] that marks an important geographical or astronomical location.
      # 'PoliceStation', # A building in which police are stationed or posted.
      # 'PoliticalUnit', # An area of land with well-defined borders that is subject to a specific political administration.
      'PopulatedPlace', # A concentrated area of human settlement, such as a city, a town, or a village.
      'Postcode', # A district used by a postal service as an aid in postal distribution and having a unique identifying code.
      'Postcode1', # One of the set of lowest-level and most detailed set of [PostCode]s in a [Sovereign].
      'Postcode2', # One of the set of second-order (one level up from the lowest level) [Postcode]s in a [Sovereign], composed by aggregating [Postcode1]s.
      'Postcode3', # One of the set of third-order [Postcode]s in a [Sovereign], composed by aggregating [Postcode2]s.
      'Postcode4', # One of the set of fourth-order [Postcode]s in a [Sovereign], composed by aggregating [Postcode3]s.
      # 'PostOffice', # A public building in which mail is received, sorted, and distributed.
      # 'PowerStation', # A facility for generating electric power.
      # 'Prison', # A facility for confining persons convicted or accused of crimes.
      # 'Promontory', # A small, usually pointed [Peninsula] that often marks the terminus of a landmass.
      # 'RaceTrack', # A track where races are held.
      # 'Railway', # A permanent twin steel-rail track on which trains move.
      # 'RailwayStation', # A place comprised of ticket offices, platforms, and other facilities for loading and unloading train passengers and freight.
      # 'RecreationalStructure', # A [Structure] used for watching or participating in sports or other athletic activities.
      # 'Reef', # A partly submerged feature, usually of coral, that projects upward near the water's surface and can be a navigational hazard.
      # 'Region', # A large area of land where a specific characteristic of the land or its people is relatively homogenous.
      # 'ReligiousRegion', # An area of land where the population holds relatively homogenous religious practices.
      # 'ReligiousStructure', # A structure where organized, public religious services are held.
      # 'ResearchStructure', # A [Structure] used for scientific purposes.
      # 'Reserve', # A tract of public land set aside for restricted use or reserved for future use.
      # 'ResidentialStructure', # A house, a hut, an apartment building, or another structure where people reside.
      # 'RestArea', # A designated area, usually along a major highway, where motorists can stop to relax.
      # 'River', # A stream of running water.
      # 'Road', # An open way with an improved surface for efficient transportation of vehicles.
      # 'RoadBlock', # A road.
      'RoadIntersection', # A junction where two or more roads meet or cross at the same grade.
      # 'Ruin', # A destroyed or decayed structure that is no longer functional.
      # 'Satellite', # A [CelestialFeature] that orbits a [Planet].
      # 'School', # A place where people, usually children, receive a basic education.
      # 'ScientificResearchBase', # A scientific facility used as a base from which research is carried out or monitored.
      # 'Sea', # A large area of salt water.
      # 'SeaplaneLandingArea', # A place on a water body where floatplanes land and take off.
      # 'ShipWreck', # A site of the remains of a wrecked vessel.
      # 'ShoppingCenter', # A collection of linked retail establishments.
      # 'Shrine', # A structure or place that memorializes a person or religious concept.
      # 'Site', # A place most notable because of an event that occurred in that location.
      'SkiArea', # A place developed for recreational Alpine or Nordic skiing.
      # 'Sovereign', # An independent nation-state, the highest level of political authority in that location.
      # 'SpotElevation', # A point on a [CelestialFeature]'s surface with a known elevation.
      # 'Spring', # A place where water emerges from the ground.
      # 'Stadium', # A structure with an enclosure for athletic games with tiers of seats for spectators.
      # 'StatisticalDistrict', # An area of land defined as a district to be used for statistical collection or service provision.
      # 'Structure', # A building, a facility, or a group of buildings and/or facilities used for a certain common purpose.
      # 'TectonicBoundary', # A line that forms the border between two [Plate]s.
      # 'TectonicFeature', # A [Landform] related to [Plate]s and their movement.
      # 'Temple', # An edifice dedicated to religious worship.
      # 'TimeZone', # A large area within which the same time standard is used.
      # 'TouristStructure', # A [Structure] typically used by tourists.
      # 'Trail', # A path, a track, or a route used by pedestrians, animals, or off-road vehicles.
      # 'TransportationStructure', # A [Structure] used for transportation purposes.
      # 'Tunnel', # A subterranean passageway for transportation.
      # 'UnderwaterFeature', # A feature on the floor of a [WaterFeature].
      # 'UrbanRegion', # An area of land with high population density and extensive urban development.
      # 'Valley', # A low area surrounded by higher ground on two or more sides.
      # 'Volcano', # A [Mountain] formed by volcanic action and composed of volcanic rock.
      # 'Wall', # An upright structure that encloses, divides, or protects an area.
      # 'Waterfall', # A vertical or very steep section of a [River].
      # 'WaterFeature', # A geographic feature that has water on its surface.
      # 'Well', # A cylindrical hole, pit, or tunnel drilled or dug down to a depth from which water, oil, or gas can be pumped or brought to the surface.
      # 'Wetland', # An area of high soil moisture, partially or intermittently covered with shallow water.
      # 'Zoo', # A zoological garden or park where wild animals are kept for exhibition.
      ])

   #
   def __init__(self):
      raise # does not instantiate.

   # ***

# ***



