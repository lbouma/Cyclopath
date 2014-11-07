# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('mndot_helper')

class MnDOT_Helper(object):

   #
   def __init__(self):
      g.assurt(False)

   #
   @staticmethod
   def resolve_to_county_ids(qb, county_keys):

      the_counties = {}

      county_names = []
      county_ids = []
      for name_or_id in county_keys:
         try:
            county_ids.append(int(name_or_id))
         except ValueError:
            county_names.append(str(name_or_id).lower())

      where_clause = ""
      conjunction = ""
      if county_ids:
         if len(county_ids) == 1:
            where_clause += (
               "%s(county_num = %d)"
               % (conjunction, county_ids[0],))
         else:
            where_clause += (
               "%s(county_num IN (%s))"
               % (conjunction, ",".join([str(x) for x in county_ids]),))
         conjunction = " OR "
      if county_names:
         if len(county_names) == 1:
            where_clause += (
               "%s(county_name = '%s')"
               % (conjunction, county_names[0],))
         else:
            where_clause += (
               "%s(county_name IN ('%s'))"
               % (conjunction, "','".join([str(x) for x in county_names]),))
         conjunction = " OR "
      g.assurt(where_clause)

      county_nums_sql = (
         "SELECT county_num, county_name FROM state_counties WHERE %s"
         % (where_clause,))

      rows = qb.db.sql(county_nums_sql)
      if not rows:
         raise Exception('Counties not found: %s' % (county_keys,))
      for row in rows:
         the_counties[row['county_num']] = row['county_name']

      return the_counties

   # ***

# ***

