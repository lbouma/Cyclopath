# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This class makes objects based on user- or otherwise-generated input.
#
# We only create classes that we say the user is allowed to create, which are
# mostly all of the classes that derive from item_base, but also some plain 
# classes we use for pickling.

import sys
import traceback

import conf
import g

log = g.log.getLogger('item_factory')

# SYNC_ME: Search items_packages. This is the list of Python packages to search
# for modules. This class loads any module it finds in these packages, so don't
# put modules in these packages if they could be exploited by hacked GML.

all_packages = (
   'item', 
   'item.attc', 
   'item.feat', 
   'item.grac', 
   'item.jobsq',
   'item.link',
   )

# A cache for the item modules, so we only have to look 'em up once.
item_modules = dict()

#
def is_item_valid(item_type, strict=False):
   '''Return True if item_type is a valid module in the item package, False 
      otherwise.'''
   success = False
   try:
      if (strict or (not strict and (item_type is not None))):
         import_item_module(item_type)
      success = True
   except Exception, e:
      pass
   if not success:
      log.warning('Item module import failed; module: "%s"; error: "%s".' 
                  % (item_type, str(e),))
      #log.verbose(' >> traceback: %s' % (traceback.format_exc(),))
   return success

#
def get_item_module(item_type, restrict_to=None):
   import_item_module(item_type)
   return item_modules[item_type]

#
def import_item_module(item_type, restrict_to=None):
   '''Import the item module named item_type from the item package.'''
   item_module = None
   if (item_type not in item_modules):
      if restrict_to is not None:
         pkg_list = restrict_to
      else:
         pkg_list = all_packages
      for pkg_name in pkg_list:
         log.verbose('import_item_module: pkg: %s' % (pkg_name,))
         item_module = import_item_module_from_package(pkg_name, item_type)
         if item_module:
            break
      if not item_module:
         raise Exception('Module import failed! Could not find: "%s".'
                         % (item_type,))
   return item_module

#
def import_item_module_from_package(package_name, item_type):
   '''Import the item module named item_type from the package named
      package_name.'''
   item_module = None
   try:
      log.verbose('import_item_module_from_package: pkg: %s / mod: %s'
                  % (package_name, item_type,))
      module = __import__(package_name, globals(), locals(), [item_type,], -1)
      # This might throw AttributeError:
      item_modules[item_type] = getattr(module, item_type)
      item_module = item_modules[item_type]
   except ImportError, e:
      # This shouldn't happen, because package_name should exist.
      log.warning('ImportError: %s' % (str(e),))
      g.assurt(False)
   except AttributeError, e:
      # Not found; just return None.
      pass
   return item_module

