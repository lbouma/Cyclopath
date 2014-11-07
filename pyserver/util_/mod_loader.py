# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The mod_loader is a simple wrapper around Python's __import__.
# C.f. item/util/item_factory.py.

import conf
import g

# New in Python 2.7, importlib helps transition from 2.7 to 3.1.
try:
   import importlib
   use_importlib = True
except ImportError:
   use_importlib = False

import traceback

log = g.log.getLogger('mod_loader')

class Mod_Loader(object):

   # NOTE: This class doesn't use a cache like item_factory does. This class
   # isn't really a factory, is it? Like, it'll be called once or twice per 
   # session (e.g., to load the work item function) and so we don't need to
   # "optimize" -- if anything, parsing the string is probably the hardest
   # part. And maybe item_factory's use of a cache isn't even necessary, or
   # harmful. (And now I see that item_factory possibly uses a deprecated form
   # of __import__.)
   # Nope: item_modules = dict()

   def __init__(self):
      g.assurt(False) # Not instantiable

   #
   @staticmethod
   def get_callback_from_path(callback_path):
      callback_fcn = None
      if callback_path:
         try:
            log.verbose2('trying to load callback: %s' % (callback_path,))
            callback_fcn = Mod_Loader.get_mod_attr(callback_path)
         except Exception, e:
            err_s = str(e) + traceback.format_exc()
            log.warning('do_do_determine_handler: failed: %s' % (err_s,))
      else:
         log.warning('do_do_determine_handler: what callback_path?: %s'
                     % (callback_path,))

      return callback_fcn

   #
   @staticmethod
   def get_mod_attr(longform_name):
      '''
      The longform name is twice or more dotted and represents the attribute
      name, its module, and the package if not the root.
      '''
      the_attr = None
      # Parse the longform name. I [lb] define this to mean a dot-separated 
      # module path followed by a colon and then a module-level function name, 
      # or a Class name followed by a colon and then the class function name.
      # E.g., 'item.jobsq.job_action:Job_Action:process_me'
      #       or just, 'item.jobsq.job_action:process_me'
      try:
         module_path, class_name, attr_name = longform_name.rsplit(':', 2)
      except ValueError:
         try:
            class_name = None
            module_path, attr_name = longform_name.rsplit(':', 1)
         except ValueError:
            raise Exception('Mod_Loader: Unrecognized longform name: "%s"' 
                            % (longform_name,))

      # Import the package.
      the_module = Mod_Loader.load_package_module(module_path)

      # Get a handle to the class.
      if class_name:
         try:
            the_class = getattr(the_module, class_name)
         except AttributeError:
            raise Exception('Mod_Loader: Class not found: %s: "%s"' 
                            % (module_path, class_name,))
      else:
         the_class = the_module
      # Get a handle on the attribute.
      try:
         the_attr = getattr(the_class, attr_name)
      except AttributeError:
         raise Exception('Mod_Loader: Attribute not found: %s: %s: "%s"' 
                         % (module_path, class_name, attr_name,))
      # Return it!
      return the_attr

   #
   @staticmethod
   def load_package_module(module_path):
      # Load the module with the given module path, e.g., 'misc.mod_loader'.
      try:
         if use_importlib:
            the_module = importlib.import_module(module_path)
         else:
            try:
               package_path, module_name = module_path.rsplit('.', 1)
            except ValueError:
               raise Exception('Mod_Loader: Unrecognized pkg/mod: "%s"' 
                               % (module_path,))
            the_package = __import__(package_path, globals(), locals(), 
                                    [module_name,], -1)
            the_module = getattr(the_package, module_name)
      except ImportError, e:
         raise Exception('Mod_Loader: Module not found or error: "%s" (%s)' 
                         % (module_path, str(e),))
      return the_module

