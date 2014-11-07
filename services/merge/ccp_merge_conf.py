# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import sys

# Test sandbox.
"""
import yaml
from merge.ccp_merge_conf import Ccp_Merge_Conf_Base
from merge.ccp_merge_conf import Ccp_Merge_Conf_Shim
s=file('ccp-EXAMPLE.yml', 'r')
a=yaml.load(s)
s=file('ccp.yml', 'r')
a=yaml.load(s)
"""

import conf
import g

log = g.log.getLogger('ccp_mrg_conf')

#from grax.access_level import Access_Level
from util_ import db_glue
from util_.log_progger import Debug_Progress_Logger

__all__ = (
   'Ccp_Merge_Conf',
   'Ccp_Merge_Conf_Shim', 
   'Ccp_Merge_Conf_Base',
   )

# ***

# This is used if not using ccp.yml but storing config in the Shapefile.
class Ccp_Merge_Conf(object):

   conf_map = {
      # 'Shpf Field Value':   (Python name, type,),
      # If the default value is None, the value is required.
      'Revision ID':          ('revision_id',   int,   None,),
      'Branch ID':            ('branch_id',     int,   None,),
      'Branch Name':          ('branch_name',   str,     '',),
      'Commit Message':       ('commit_msg',    str,     '',),
      'Find Missing Agency':  ('find_missing',  str,     '',),
      'Use _NEW_GEOM':        ('use__new_geom', bool, False,),
      # FIXME: Only devs should be allowed to use this setting:
      'Database Override':    ('db_override',   str,     '',),
      # This is another developer setting. Since new attrs can 
      # only be created by editing source code, this setting 
      # normally makes no sense, since attrs rarely change.
      'No New Attrs':         ('no_new_attrs',  bool, False,),
      }

   __slots__ = (tuple(
      [x[0] for x in conf_map.itervalues()] 
      + [
         'errs',
         'permissions',
         ]))

   def __init__(self):
      self.errs = []
      for conf_def in Ccp_Merge_Conf.conf_map.itervalues():
         setattr(self, conf_def[0], conf_def[2])
      self.permissions = []

   #
   def add_perms(self, group, access_level):
      new_perms = Ccp_Merge_Conf_Perms(group, access_level)
      self.permissions.append(new_perms)

   #
   def consume_friendly(self, handler, friendly_name, conf_value):
      err_s = ''
      try:
         attr_name = Ccp_Merge_Conf.conf_map[friendly_name][0]
         attr_type = Ccp_Merge_Conf.conf_map[friendly_name][1]
         if isinstance(attr_type, bool):
            conf_value = handler.defs.ogr_to_bool(conf_value)
         else:
            conf_value = attr_type(conf_value)
         setattr(self, attr_name, conf_value)
      except KeyError:
         err_s = 'Unknown CCP_ _CONTEXT: %s' % (friendly_name,)
      except ValueError:
         err_s = ('CCP_ _CONTEXT %s not type %s: %s' 
                  % (friendly_name, attr_type, conf_value,))
      if err_s:
         self.errs.append(err_s)

   #
   def check_errs(self):
      if not self.permissions:
         log.info('Setting default target permissions.')
         self.add_perms('Public', 'editor')
      for conf_name, conf_def in Ccp_Merge_Conf.conf_map.iteritems():
         conf_value = getattr(self, conf_def[0])
         # If a value is still None, complain.
         if conf_value is None:
            err_s = 'Missing CCP_ _CONTEXT: %s' % (conf_name,)
            self.errs.append(err_s)
      if self.errs:
         err_s = ('There was a problem with the Shapefile config: %s' 
                  % (', '.join(self.errs),))
         log.error(err_s) # Should probably be debug, but curious.
         raise Exception(err_s)

   #
   def record_as_feats(self, handler, layer):

      # Setup some default values, mayhaps.

      if not self.commit_msg:
         # Set to, e.g., "Import Cyclopath Export"
         # FIXME: Use the region name? E.g., "Import Hopkins"?
         self.commit_msg = 'Import %s' % (layer.GetName(),)

      # Write the spf_conf as geometry-less features to the Shapefile.

      branch_defs = handler.defs

      for conf_name, conf_def in Ccp_Merge_Conf.conf_map.iteritems():

         conf_value = getattr(self, conf_def[0])

         # MAYBE: For now, only include the conf_value if it's set or logically
         # True (otherwise we'll include all of the 'secret' or 'deprecated' or
         # 'just-plain-silly-developer-options' options.
         if conf_value:

            feat = ogr.Feature(layer.GetLayerDefn())

            # '_ACTION' is always 'CCP_' and 'CCP_ID' is always -1. (We only
            # care about 'CCP_'; the -1 is meaningless and can be anything,
            # but it helps when sorting your Attribute Table in ArcMap.)
            feat.SetField(branch_defs.confln_action, 
                          branch_defs.action_shpf_def)
            feat.SetField(branch_defs.confln_ccp_stack_id, -1)
            # '_CONTEXT' is friendly name and 'CCP_NAME' is the conf value.
            feat.SetField(branch_defs.confln_context, conf_name)
            feat.SetField(branch_defs.confln_ccp_name, conf_value)

            # Write + Cleanup.
            ogr_err = layer.CreateFeature(feat)
            g.assurt(not ogr_err)
            feat.Destroy()

   #
   def __str__(self):
      myself = ''
      for friendly_name, conf_def in Ccp_Merge_Conf.conf_map.iteritems():
         myattr = getattr(self, conf_def[0])
         if myattr:
            myself += ('%s%s=%s'
               % ((', ' if myself else ''), conf_def[0], myattr,))
      if not myself:
         myself = 'empty'
      myself = ('Ccp_Merge_Conf: %s' % (myself,))
      return myself

#
class Ccp_Merge_Conf_Perms(object):

   __slots__ = (
      'group',
      'access_level',
      )

   def __init__(self, group=None, access_level=None):
      self.group = group
      self.access_level = access_level

# ***

# This is used by ccp.yml.
class Ccp_Merge_Conf_Shim(object):

   # NOTE: We could use __slots__ to verify that the yaml does not contain
   # unknown keys, but that would burden developers, who would have to
   # maintain __slots__ and also create shim objects for each sub-container.
   # So let's keep it simple.

   # If you did want to use __slots__ to be stricter about the config file,
   # and if the yml contained an unknown attribute, the error you'd get is:
   # TypeError: can't set attributes of built-in/extension type 'object'
   #__slots__ = ('revision_id',...,)

   def __init__(self):
      pass

# ***

# This is used by ccp.yml.
class Ccp_Merge_Conf_Base(Ccp_Merge_Conf_Shim):

   # CAVEAT: In ccp.yml, the root of the document is declared
   #           !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Base
   #         and each sub-document is declared
   #           !!python/object:merge.ccp_merge_conf.Ccp_Merge_Conf_Shim
   #         but only the Shims' __init__s get called. Weird....
   def __init__(self):
      Ccp_Merge_Conf_Shim.__init__(self)
      # See CAVEAT, above: [lb] has never seen this fcn. called. Not that it
      # matters; these classes are just for show, er, for ccp.yml.
      g.assurt(False)

# ***

if (__name__ == '__main__'):
   pass

