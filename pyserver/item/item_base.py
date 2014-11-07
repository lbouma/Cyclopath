# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A versioned feature is one that follows the valid-start/valid-until
# revisioning model.

import hashlib
from lxml import etree
import sys
import traceback

import conf
import g

from grax.access_level import Access_Level
from grax.access_style import Access_Style
from gwis.exception.gwis_error import GWIS_Error
from item.util.item_type import Item_Type
from util_ import misc

log = g.log.getLogger('item_base')

class One(object):
   '''
   Represents a single database row, sometimes with additional (calculated)
   values of interest to the client. For instance, byway items also include
   interesting ratings values and also indicate if there are attachments 
   associated with the byway.
   '''

   item_type_id = None # Abstract
   item_type_table = None
   item_gwis_abbrev = None
   child_item_types = None

   # NOTE: The numbering here is deliberate; user > auto > none
   dirty_reason_none = 0x0000
   dirty_reason_item_auto = 0x0001
   dirty_reason_item_user = 0x0002
   dirty_reason_stlh = 0x0004
   dirty_reason_infr = 0x0008
   dirty_reason_grac_user = 0x0010
   dirty_reason_grac_auto = 0x0020

   # The attr_defns collection defines the class's attributes for the three 
   # domains -- database tables, python classes, and GWIS XML -- as well as for
   # both incoming and outgoing data (e.g., reading from XML vs. sending XML, 
   # because the set of attributes we receive may not be the same set of
   # attributes that we send).
   # 
   # Each object in the attr_defns collections defines the Python object's
   # member name (which we use to setup __slots__). If also defines a default
   # value for the attribute, the name and type of the attribute if we should 
   # look for it in incoming XML, and a flag indicating if we should include
   # the attribute in outgoing XML (if the attribute is not None).
   # 
   # The definition tuple, e.g., 
   #   (pyname, dfault, out_ok, ispkey, intype, inreqd, inname,)
   #
   #    [0]: Postgres column and Python attribute name
   #    [1]: Default Python Value
   #    [2]: True if we send it and its value to the client on xml output
   #    [3]: A bool if we save the attr to the db; True if a pkey, else False.
   #    [4]: Python type for type-casting XML input
   #    [5]: Whether or not the attribute is required in XML input.
   #         None - raise error if in input
   #            0 - allowed in input but not required
   #            1 - required only for new items
   #            2 - always required, for both new and existing items
   #            3 - only allowed from local script
   #    [6]: Attribute name in GWIS/XML input, if different from [0]
   #
   scol_pyname = 0
   scol_dfault = 1
   scol_out_ok = 2
   scol_ispkey = 3
   scol_intype = 4
   scol_inreqd = 5
   scol_abbrev = 6
   scol_precision = 7
   # Define empty boilerplate code for derived class to copy and extend.
   attr_defns = []
   psql_defns = []
   #gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   gwis_defns = [[], [],]
   #
   cols_copy_nok = []

   inreqd_illegal = None
   inreqd_optional = 0
   inreqd_required_on_create = 1
   inreqd_required_always = 2
   # FIXME: inreqd_local_only is not enforced.
   inreqd_local_only = 3
   inreqd_optional_on_create = 4

#FIXME: BUG 2641: route_step should not derive from item_base, because of these
#attrs that waste memory... ?

   __slots__ = [
      'dirty',
      'fresh',
      'valid',
      'req',
      # Grumble... these are for two separate derived classes,
      #            item_helper and geofeature
      'attrs',        # lightweight
      'tagged',       # lightweight
      'link_values',  # heavyweight
      'lvals_wired_', # set by item_mgr if attrs/tags/lvals setup.
      'lvals_inclusive_', # if lvals are for userless (i.e., all lvals loaded).
      ]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      # 
      self.assurt_on_init(qb, row, req, copy_from)
      # 
      self.dirty = One.dirty_reason_none
      # An item object is fresh once we set its stack ID if its version=0 (and
      # the current stack ID is negative, i.e., set to a client ID). 
      # The takeaway: self.fresh is only True during a save sequence, from 
      # stack_id_lookup_cached() through save().
      self.fresh = False
      # An item is valid once we start a save sequence and prepare it for 
      # saving (see prepare_and_save_item() and validize()). This, e.g., 
      # sets an item's valid_start/until_rid, hydrates missings columns, etc.
      self.valid = False
      # The req is our Apache request wrapper. Much of the data can be found
      # in qb, since we don't require a request to make an item (just a qb).
      self.req = req
      # Setup the column members
      g.assurt(not ((row is not None) and (copy_from is not None)))
      for attr_defn in self.attr_defns:
         self.col_to_attr(row, attr_defn, copy_from)
         # FIXME: We should complain about keys in row that we don't recognize.
      # BUG 2641: Is it costly to define these for all items?
      # 
      self.attrs = {}
      self.tagged = set()
      # Skipping: self.link_values = {}
      #           self.link_values_reset()
      # Skipping: self.lvals_wired_ = False
      #           self.lvals_inclusive_ = False

   #
   def assurt_on_init(self, qb, row, req, copy_from):
      # Not for grac_record, e.g., group_item_access.One(): 
      #  g.assurt(isinstance(qb, Item_Query_Builder))
      if row is not None:
         g.assurt(isinstance(row, dict))
         g.assurt(req is None)
         g.assurt(copy_from is None)
      if req is not None:
         g.assurt(row is None)
         g.assurt(copy_from is None)
      if copy_from is not None:
         g.assurt(row is None)
         g.assurt(req is None)

   #
   def copy_self(self, qb):
      return self.__class__(qb=qb, row=None, req=None, copy_from=self)

   # *** Built-in Function definitions

   #
   def __cmp__(self, other):
      # See: diff_compare, which compares just a few attrs.
      return NotImplemented

   #
   def __eq__(self, other):

      attrs_equal = True
      # MAYBE: We only compare item_base.One's __slots__.
      #        Derived classes should really override this fcn.
      #        and compare whatever __slots__ they use and care about.
      if attrs_equal:
         # NOTE: self.__slots__ is the derived class's.
         #       MAYBE: If derived classes care, override this fcn. and check
         #       their own One.__slots__
         #for key in self.__slots__:
         for key in One.__slots__:
            if (getattr(self, key, None)
                != getattr(other, key, None)):
               #import rpdb2;rpdb2.start_embedded_debugger('password',
               #                                           fAllowRemote=True)
               attrs_equal = False
               break
      if attrs_equal:
         for attr_defn in self.attr_defns:
            attr_name = attr_defn[One.scol_pyname]
            try:
               # If this is a floating point number, round it,
               # otherwise __eq__ is liable to be not.
               self_value = round(getattr(self, attr_name, None),
                                  attr_defn[One.scol_precision])
               other_value = round(getattr(other, attr_name, None),
                                   attr_defn[One.scol_precision])
               if self_value != other_value:
                  attrs_equal = False
                  break
               else:
                  continue
            except IndexError:
               pass
            except TypeError:
               g.assurt_soft(False)
               pass
            if (getattr(self, attr_name, None)
                != getattr(other, attr_name, None)):
               attrs_equal = False
               break

      return attrs_equal

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   # *** GML/XML Processing

   #
   def append_gml(self, elem, need_digest, new=None, extra_attrs=None, 
                        include_input_only_attrs=False):
      '''Adds a GML child representing myself to elem. Subclasses should call
         supermethod _after_ doing their stuff. Note that the last subclass 
         methods in the class hierarchy (leaves in the tree) do not take the 
         'new' parameter, and if a 'new' object is not provided, one will be 
         created based on the item_type. The same goes for 'extra_attrs'.'''
      if new is None:
         #log.debug('append_gml: item_type_id: %s' % (self.item_type_id,))
         g.assurt(self.item_type_id)
         new = etree.Element(Item_Type.id_to_str(self.item_type_id))
      self.attrs_to_xml(new, need_digest, extra_attrs, 
                        include_input_only_attrs)
      elem.append(new)
      return new

   #
   def attrs_to_dict(self, extra_attrs=None):
      one_dict = {}
      # When classes indicate their schema, they also indicate which columns
      # should be sent to the client using the [2] slot. We ignore that for
      # this method.
      g.assurt(False) # Delete this fcn.?
      attrs = [col_tuple[One.scol_pyname] for col_tuple in self.attr_defns]
      if (extra_attrs is not None):
         attrs = attrs + extra_attrs
      for attr in attrs:
         if (getattr(self, attr) is not None):
            one_dict[attr] = getattr(self, attr)
      return one_dict

   #
   def attrs_to_xml(self, elem, need_digest, extra_attrs=None, 
                          include_input_only_attrs=False):
      '''Add my attributes named in attrs as XML attributes of element elem.'''

      # The route finder uses extra_attrs, e.g.,
      #   [b'bonus_tagged', b'penalty_tagged', b'rating']

      if need_digest:
         md5sum = hashlib.md5()

      # Only send attributes whose definition says it should be sent to client.
      if not include_input_only_attrs:
         attrs = self.gwis_defns[0]
      else:
         attrs = self.gwis_defns[1]
      if extra_attrs:
         for extra_attr in extra_attrs:
            attrs += (extra_attr, extra_attr,)

      #log.debug('attrs_to_xml: attrs: %s' % (str(attrs),))

      # EXPLAIN: Not sure why we sort here....
      #for attr in sorted(attrs):
      for attr in attrs:
         #log.debug(' >> attr: %s / %s' % (attr, getattr(self, attr),))
         attr_val = getattr(self, attr[0], None)
         if attr_val is not None:
            misc.xa_set(elem, attr[1], attr_val)

# FIXME: This code is probably obsolete, since Diff now does the checking when
# the byways are checked out.
            # If we need a digest, we build an md5 hash based on the
            # non-geometric properties of the item. The digest is used when
            # diffing in the client to quickly tell if anything has changed.
            # - Certain property changes are meaningless, so we exclude them
   # FIXME I think this is broken... needs to be tested...
   #       (okay i no longer think it's broken)
   # FIXME Move some of these to geofeature.py and make a class array
            # MAGIC_NUMBER: 0 is col_tuple[One.scol_pyname]
            if (need_digest and attr[0] not in (
#'system_id',
#'branch_id',
               'stack_id',
               'version',
               'geometry_len',
               'beg_node_id',
               'fin_node_id',
   # I missing a bunch of generated cols that probably should be excluded...
               'node_lhs_elevation_m',
               'node_rhs_elevation_m',
               'split_from_stack_id',)):
               md5sum.update(attr[0] + str(getattr(self, attr[0])))
      if (need_digest):
         # NOTE The GML elem 'dng' is called digest_nongeo in flashclient
         # FIXME Rename to rev_digest?
         misc.xa_set(elem, 'dng', md5sum.hexdigest())

   #
   def attrs_to_xml_confirm(self, col_tuple):
      return True

   #
   def col_to_attr(self, row, attr_defn, copy_from):
      attr_name = attr_defn[One.scol_pyname]
      default = attr_defn[One.scol_dfault]
      try:
         ispkey = attr_defn[One.scol_ispkey]
      except IndexError:
         ispkey = None
      if copy_from is not None:
         # NOTE: copy_from only copies columns, and not all object members.
         #       I.e., attrs, tagged, and link_values are not copied.
         if attr_name not in self.cols_copy_nok:
            value = getattr(copy_from, attr_name, default)
            setattr(self, attr_name, value)
         else:
            setattr(self, attr_name, default)
      elif (row is None) or (row.get(attr_name, None) is None):
         setattr(self, attr_name, default)
      else:
         # NOTE: psycopg2 should have made the appropriate Python type.
         try:
            value = row[attr_name]
         except KeyError:
            # This is a programmer error.
            g.assurt(False)
         # Coerce the fetched type to match the type of the default, unless
         # the default is None, in which case accept the type of the fetched
         # object. This is to account for bizarre types such as 
         # <type 'libpq.PgBoolean'> which the DBMS glue might cough up that we 
         # don't want contaminating our environment.
         # 2012.07.12: [lb] isn't sure the above comment is correct, at least
         # not with psycopg2: testing on the py prompt shows that a bool is a
         # bool.
         type_ = type(default)
         if type_ != type(None):
            try:
               value = type_(value)
            except:
               # FIXME: only if not apache... or use conf debug switch
               #conf.break_here('ccpv3')
               raise
         setattr(self, attr_name, value)

   #
   def from_gml(self, qb, elem):
      # Go through the schema cols and see which ones have input XML
      # configured. We have to go through the list twice, the second time
      # checking for attributes required only when creating a new item.
      pass_number = 1
      while pass_number and (pass_number <= 2):
         for defn in self.attr_defns:
            # The XML can be tagged either with the complete class attribute 
            # name, or it can use an abbreviation.
            attr_synonyms = set()
            # The abbrev index is not defined for all defn tuples.
            try:
               attr_name = defn[One.scol_abbrev] or defn[One.scol_pyname]
               attr_synonyms.add(attr_name)
            except IndexError:
               pass
            # The pyname index is always defined all each defn tuple.
            attr_synonyms.add(defn[One.scol_pyname])
            # Decide if we should look for this attribute in the input.
            try:
               req_code = defn[One.scol_inreqd]
               g.assurt(req_code in (One.inreqd_illegal,
                                     One.inreqd_optional,
                                     One.inreqd_required_on_create,
                                     One.inreqd_required_always,
                                     # FIXME: Verify IP if inreqd_local_only
                                     One.inreqd_local_only,
                                     One.inreqd_optional_on_create,
                                     ))
            except IndexError:
               req_code = None
            # Try each of the GML names.
            found_attr = self.from_gml_defn(elem, defn, attr_synonyms, 
                                            req_code, pass_number)
            # If required but not found, raise.
            if not found_attr:
               if pass_number == 1:
                  required = (req_code == One.inreqd_required_always)
               else:
                  g.assurt(pass_number == 2)
                  required = (req_code == One.inreqd_required_on_create)
               if required:
                  # C.f. One.from_gml_required
                  raise GWIS_Error('Missing mandatory attr: one of "%s".' 
                                   % (attr_synonyms,))
         # end for
         # EXPLAIN: When is stack_id not set? For routes being analyzed?
         #          (For 'analysis', isn't stack_id == 0?)
         if ((pass_number == 1)
             and (hasattr(self, 'stack_id') and (self.stack_id < 0))):
            g.assurt(self.stack_id is not None)
            # Do a second pass and verify creation attrs are avail.
            pass_number = 2
         else:
            # MAYBE: inreqd_optional_on_create. Loop again and check that
            # optional creation arguments are *not* set...
            pass_number = 0

   #
   def from_gml_defn(self, elem, defn, attr_synonyms, req_code, pass_number):
      found_attr = False
      attr_value = None
      for attr_name in attr_synonyms:
         # If required is None or not set, it means we shouldn't expect this
         # attribute. In fact, if it's set, kvetch.
         if req_code is None:
            if pass_number == 1:
               attr_value = elem.get(attr_name, None)
               if attr_value is not None:
                  found_attr = True # A no-op, since we're about to raise...
                  raise GWIS_Error('Illegal input attr: "%s".' 
                                   % (attr_name,))
            # else, pass_number is 2, so we're just checking for missing
            #       mandatory create attrs.
         else:
            # Otherwise, look for the attribute.
            attr_value = elem.get(attr_name, None)
            if pass_number == 1:
               if attr_value is not None:
                  if defn[One.scol_intype] == bool:
                     attr_value = bool(int(attr_value))
                  else:
                     try:
                        g.assurt(defn[One.scol_intype] is not None)
                        attr_value = defn[One.scol_intype](attr_value)
                     except ValueError:
                        # Is this a programmer error or could malformed XML
                        # cause this? I'm think malformed XML could... so we
                        # should raise an error.
                        raise GWIS_Error(
                           'Bad Attr Type: attr: %s / value: %s / type: %s' 
                           % (attr_name, attr_value, defn[One.scol_intype],))
                  found_attr = True
               else:
                  # We could leave whatever value is already set, but this
                  # fcn. is destructive (i.e., it's not an update).
                  attr_value = defn[One.scol_dfault]
               setattr(self, defn[One.scol_pyname], attr_value)
            else:
               g.assurt(pass_number == 2)
               # Just see if the attr exists.
               if attr_value is not None:
                  found_attr = True
            if found_attr:
               break
      return found_attr

   #
   @staticmethod
   def from_gml_required(elem, attr_name, required=True):
      attr_value = elem.get(attr_name, None)
      if required and (attr_value is None):
         # NOTE: This is just a programmer error, so don't worry about if
         # this msg is useful (i.e., don't bother helping troubleshoot).
         raise GWIS_Error('Missing mandatory attr: "%s".' % (attr_name,))
      return attr_value

   #
   @staticmethod
   def attr_defns_assemble(base_class, addlocal_defns):
      add_py_names = [col_tuple[0] for col_tuple in addlocal_defns]
      n_names = len(add_py_names)
      add_py_names = set(add_py_names)
      # Don't let a class use the same name twice in its own local_defns.
      g.assurt(n_names == len(add_py_names))
      # But if a class specifies the same name as a parent class, use the
      # descendant's tuple.
      attr_defns = []
      for col_tuple in base_class.One.attr_defns:
         if col_tuple[0] not in add_py_names:
            attr_defns.append(col_tuple)
      # Finally, add the descendant's tuples.
      attr_defns += addlocal_defns
      return attr_defns

   #
   @staticmethod
   def attr_defns_reduce_for_gwis(attr_defns):
      # Go through schema cols in order, since derived classes can override the
      # definition (see link_value's redefinition of 'name', so it's not sent
      # to the client).
      lookup = {}
      for col_tuple in attr_defns:
         lookup[col_tuple[One.scol_pyname]] = col_tuple
      # In the first slot, only put attrs we mark as okay to send to the client
      # In the second slot, put all attrs that are okay for input -- this is so
      # ccp.py can make GML to send to pyserver.
      gwis_defns = [[], [],]
      for col_tuple in lookup.itervalues():
         try:
            name = col_tuple[One.scol_abbrev] or col_tuple[One.scol_pyname]
         except IndexError:
            name = col_tuple[One.scol_pyname]
         if col_tuple[One.scol_out_ok]:
            gwis_defns[0].append((col_tuple[One.scol_pyname], name,))
         try:
            if col_tuple[One.scol_inreqd] != One.inreqd_illegal:
               gwis_defns[1].append((col_tuple[One.scol_pyname], name,))
         except IndexError:
            pass
      #log.debug('attr_defns_reduce_for_gwis: %s' % (gwis_defns,))
      return gwis_defns

#   #
#   def xa_set_cols(doc_item, attr_dict):
#      self.gwis_defns
#      for k,v in attr_dict.iteritems():
#         misc.xa_set(doc_item, k, v)

   # *** Dirty/Fresh/Valid Routines

   # 
   def dirty_reason_add(self, dirty_reason):
      # We don't maintain a set of dirty reasons, which right now is just
      # 'auto' or 'user'; we maintain the 'greatest' or 'trump' reason. If the 
      # item is dirty 'auto', then we can save it without caring about
      # permissions; if the item is dirty 'user', we have to verify that the
      # user has permissions to save it, regardless of 'auto'.
      self.dirty |= dirty_reason

   #
   def is_dirty(self):
      is_dirty = False
      if self.dirty != One.dirty_reason_none:
         is_dirty = True
      return is_dirty

   #
   def newly_split(self):
      return False

   # Items from the client must be 'validized'. This involves hydrating the
   # item, specifically setting values the client did not send. We might also
   # mark the item not-dirty if the client's item is no different than what's
   # in the database.
   def validize(self, qb, is_new_item, dirty_reason, ref_item):

      g.assurt(not self.valid)

      # Note the clobbery of dirty, which is okay: this is the first time we'll
      # set dirty on an item. After this, callers will use dirty_reason_add so
      # that the dirty reasons are |ored together.
      g.assurt(self.dirty == One.dirty_reason_none)
      # This is now okay: g.assurt(dirty_reason != One.dirty_reason_none)
      #self.dirty = dirty_reason
      self.dirty_reason_add(dirty_reason)

      # NOTE: Python's id() returns an object's ID... akin to &object in C.
      if (not is_new_item) and (ref_item is not None):
         # This item exists. For values the client does not indicate in GWIS, 
         # copy the value from the database.
         comparable = self.validize_consume_item(ref_item)
         #if comparable:
         #   #log.debug('validize: user item comparable to db item')
         #   # 2011.08.18: Curious if this'll happen much
         #   # FIXME: validize_compare ignores self.groups_access
         #   # NOTE: mark_deleted comes through here.
         #   # NOTE: MetC import comes through here.
         #   log.debug('validize: user item comparable to db item')

      # else, is_new_item, meaning (a) this item was not found in the 
      #       database, or (b) it was found in the database, and the user
      self.valid = True

   #
   def validize_consume_item(self, other):
      # This fcn. fills in item attributes that the client did not specify,
      # i.e., it copies from the previous item version.
      log.verbose('validize_consume_item: us: %s / them: %s' % (self, other,))
      comparable = True
      g.assurt(type(self) == type(other))
      for attr_defn in self.attr_defns:
         # If the self object does not specify a column, that's fine; 
         # if the other object does not specify a column, that's bad, 
         # because it should have been fetched from the database.
         attr_name = attr_defn[One.scol_pyname]
         try:
            other_value = getattr(other, attr_name)
         except AttributeError, e:
            log.warning('is_same_as_or_subset_of: programming error')
            comparable = False            
            g.assurt(False)
         try:
            our_value = getattr(self, attr_name)
            log.verbose(
               'validize_consume_item: %s / our value: %s / theirs: %s' 
               % (attr_name, our_value, other_value,))
            if (other_value != our_value):
               comparable = False
               if our_value is None:
                  # Pick up things the client did not specify.
                  setattr(self, attr_name, other_value)
            # else, the values match, so look at the next column
         except AttributeError, e:
            # The value isn't specified in self. Set the value in the new item,
            # but leave comparable untouched, since we let the new item be a
            # subset of the existing item.
            g.assurt(False) # I think self always use None
            log.verbose('validize_consume_item: %s / their value: %s' 
                        % (attr_name, other_value,))
            setattr(self, attr_name, other_value)
      return comparable

   # *** Saving to the Database

   #
   def save(self, qb, rid):
      g.assurt(self.valid)
      g.assurt((rid == 1) or (rid == qb.item_mgr.rid_new))
      # Don't save unless dirty...
      # but ignore some dirty reasons, like One.dirty_reason_stlh.
      # And One.dirty_reason_grac_auto/dirty_reason_grac_user.
      if (((self.dirty & One.dirty_reason_item_auto)
           or (self.dirty & One.dirty_reason_item_user))
          # If acl_grouping > 1, it means we're just updating GIA records.
          and ((self.acl_grouping == 1))):
          # i.e., ((self.dirty != One.dirty_reason_none)
          #        and not (self.dirty == One.dirty_reason_stlh)):
         #self.save_core_shim(qb)
         self.save_core(qb)
         # MAYBE: Most fcns. that call sql() that care about catching duplicate
         # row exceptions will set integrity_errs_okay first, then call sql(),
         # and then clear integrity_errs_okay. So clearing it here probably
         # isn't necessary.
         qb.db.integrity_errs_okay = False
      else:
         log.debug('save: skipping clean item')
         # This should be true:
         # g.assurt(self.dirty & (One.dirty_reason_stlh
         #                        | One.dirty_reason_infr
         #                        | One.dirty_reason_grac_user
         #                        | One.dirty_reason_grac_auto))
         g.assurt(not self.fresh)
         g.assurt(self.acl_grouping > 1)
      # Save peripheral things, like watchers, group accesses, etc.
      # These can be dirty independent of the item, so we always call this.
      self.save_related_maybe(qb, rid)
      # All done. Mark the item as neither fresh nor dirty.
      self.fresh = False
      self.dirty = One.dirty_reason_none
      # Reset valid, so the user cannot accidentally save this item again
      # without calling validize again.
      self.valid = False

   #
   def save_core_shim(self, qb):
      self.save_core(qb)

   #
   def save_core(self, qb):
      g.assurt(False) # Abstract fcn.

   #
   # HRM: do_update doesn't mean we UPDATE the row(s) in the database, but that
   #      we clobber them: DELETE, then INSERT, so we expect a fully hydrated
   #      item whether updating or not (if you want to update specific columns,
   #      override one of the save fcns.).
   def save_insert(self, qb, table, psql_defns, do_update=False):
      id_cols = {}
      nonid_cols = {}
      for defn in psql_defns:
         try:
            ispkey = defn[One.scol_ispkey]
         except IndexError:
            ispkey = None
         if ispkey is not None:
            # Get the Python/Postgres attribute/column name.
            cname = defn[One.scol_pyname]
            log.verbose('save_insert: cname: %s' % (cname,))
            # We used to check that cname isn't yet in id_cols or nonid_cols,
            # but derived classes are now allowed to redefine attributes. Which
            # means we have to make sure to whack the earlier copy, since the
            # redefinition might change ispkey.
            id_cols.pop(cname, None)
            nonid_cols.pop(cname, None)
            if ispkey:
               id_cols[cname] = getattr(self, cname)
            else:
               nonid_cols[cname] = getattr(self, cname, None)
      # MAYBE: The meaning of do_update seems backwards.
      #        It's not SQL's UPDATE but DELETE and INSERT.
      if not do_update:
         #log.debug('save_insert: table: %s / insert: %s' % (table, self,))
         qb.db.insert(table, id_cols, nonid_cols)
      else:
         #log.debug('save_insert: table: %s / clobber: %s' % (table, self,))
         qb.db.insert_clobber(table, id_cols, nonid_cols)

   #
   def save_related_maybe(self, qb, rid):
      g.assurt(False) # Abstract fcn.

   # ***

   #
   def load_all_link_values(self, qb):
      pass # Only Attachment and Geofeature implement this;
           # not Link_Value or Nonwiki_Item/Work_Item.

   #
   def load_all_link_values_(self, qb, links, lhs, rhs, heavywt):

      if not self.lvals_inclusive():
         self.load_all_link_values__(qb, links, lhs, rhs, heavywt)
      #else:
      #   log.debug('load_all_link_values_: already lvals_inclusive: %s'
      #             % (str(self),))

   #
   def load_all_link_values__(self, qb, links, lhs, rhs, heavywt):

      userless_qb = qb.get_userless_qb()
      userless_qb.filters.include_item_stack = True

      g.assurt(lhs ^ rhs)
      if lhs:
         links.search_by_stack_id_lhs(self.stack_id, userless_qb)
      elif rhs:
         links.search_by_stack_id_rhs(self.stack_id, userless_qb)

      try:
         if self.link_values is not None:
            log.verbose(
               'load_all_link_values_: overwriting link_values: self: %s'
               % (self,))
      except AttributeError:
         # self.link_values has not been set yet.
         pass

      self.link_values_reset(qb)
      for lval in links:
         lval.groups_access_load_from_db(qb)
         self.wire_lval(qb, lval, heavywt)
      self.lvals_wired_ = True
      self.lvals_inclusive_ = True

   # This fcn. is called from commit and from the import script to delete
   # items. Clients are responsible for copying items to the leafy branch
   # if they're not leafy, because this fcn. just UPDATEs database rows
   # and sets deleted to false.
   def mark_deleted(self, qb, f_process_item_hydrated=None):

      if self.deleted:
         log.error('mark_deleted: already deleted: %s' % (self,))
      else:
         self.mark_deleted_(qb, f_process_item_hydrated)

   #
   def mark_deleted_(self, qb, f_process_item_hydrated):

      # The caller should should set deleted -- we do that once we're done.
      g.assurt(not self.deleted)

      # Start with link_values first, otherwise we'd have to allow_deleted
      # because we delete the byway... but allow_deleted just adds complexity.
      # So delete link_values before the item.
      # 2013.10.02: On Shapefile import, when we delete a split-from byway,
      # we've already loaded its link_values... meaning, this call may be
      # a no-op.
      # MAYBE: Similar to lvals_wired_, maybe indicated if
      # lvals_wired_user or lvals_wired_userless
      self.load_all_link_values(qb)

      # We're done with the split-from byway's link_values and now it's time
      # to tackle the split-from itself. If the split-from byway is on a
      # parent branch, we need to copy ourselves to the leafy branch before
      # we can mark it deleted.
      if self.branch_id != qb.branch_hier[0][0]:
         log.verbose('mark_deleted:   copy-to/delete-from br: %s' % (self,))
      else:
         log.verbose('mark_deleted:         deleting from br: %s' % (self,))

      okay_to_delete = True
      if f_process_item_hydrated is not None:
         self.groups_access = None
         self.access_level_id = Access_Level.invalid
         self.access_style_id = Access_Style.nothingset
         g.assurt(not self.valid)
         okay_to_delete = f_process_item_hydrated(qb, self)
      else:
         # Else, client will have saved item before calling us.
         # 2013.08.05: Is this a valid assumption?
         g.assurt(self.groups_access is not None)

      # FIXME/CONFIRM: On split-byway, we also need all link_values without
      # regard for GIA permissions, but they are loaded differently.
      # Here, when deleting items (geofeatures and attachments), we need all
      # link_values.

      if okay_to_delete:

         # Do the link_values after hydrating the rhs item, otherwise
         # commit (well, grac_mgr) will hydrate its own copy.
         self.mark_deleted_link_values(qb, f_process_item_hydrated)

# TEST: Item watching: Watch a byway, then split it, also test deleting it.

         # NOTE: mark_deleted runs SQL immediately, so no need to save().
         g.assurt((not self.fresh) and (self.stack_id > 0))
         self.deleted = True
         self.mark_deleted_update_sql(qb.db)

      # else, not okay_delete, and f_process_item_hydrated will have processed
      #                            the error.

   #
   def mark_deleted_link_values(self, qb, f_process_item_hydrated):
      # 2013.07.15: [lb] moved this from byway.One because really any item
      # with link_values should probably mark its link_values deleted, so
      # that we don't ever bother loading links for deleted items. Here's
      # an old comment of mine:
      # [lb says]: Technically, or logically, I suppose, only the
      #  byway should be deleted. But both the route finder and the
      #  import scripts bulk-load undeleted lvals when loading the item
      #  manager. So we delete the old links (and revert has to go
      #  through the trouble of undeleting them, too).
      try:
         g.assurt(self.link_values is not None)
      except AttributeError:
         g.assurt(False)

      for lhs_stack_id, lval in self.link_values.iteritems():

         g.assurt(not lval.deleted)

         # If the link is from a parent branch, copy it first. This seems 
         # counter-intuitive -- it seems like we're just wasting space, 
         # but really we want to block the parent's link_value when the
         # route finder or import bulk-loads link_values for the branch.
         if lval.branch_id != qb.branch_hier[0][0]:
            lval.branch_id = qb.branch_hier[0][0]
            log.verbose('mark_del_lvals: copy-to/delete-from br: %s' % (lval,))
         else:
            log.verbose('mark_del_lvals: deleting from branch: %s' % (lval,))

         okay_to_delete = True
         if f_process_item_hydrated is not None:
            # The commit cmd. doesn't like it when the 'user' specifies his/her
            # access level, so clear them, or make sure they're cleared.
            lval.groups_access = None
            lval.access_level_id = Access_Level.invalid
            lval.access_style_id = Access_Style.nothingset
            g.assurt(not lval.valid)
            okay_to_delete = f_process_item_hydrated(qb, lval)
         else:
            # NOTE: This is the code path maybe import will eventually follow
            #       if/when it honors the _DELETE Shapefile command.
            #
            # 2013.11.22: Import comes through here on MetC import...
            #log.warning('mark_del_lvals: untestd: calling prep_and_save_item')

            # MAYBE: In commit, we remember the group IDs of groups_access
            # records to make appropriate group_revision records, which we
            # don't do here.

            # 2013.08.05: Is this a valid assumption?
            # See: Item_Manager.load_groups_access
            g.assurt(lval.groups_access is not None)
            g.assurt(Access_Level.is_valid(lval.access_level_id))

            # [lb] notes that this is a little weird: copy the groups_access,
            # which prepare_and_save_item uses.
            # FIXME: prepare_and_save_item assumes using target_groups means
            #        this is a new item... but it's not.
            target_groups = {}
            for gia in lval.groups_access.itervalues():
               target_groups[gia.group_id] = gia.access_level_id
            lval.prepare_and_save_item(qb, 
               target_groups=target_groups,
               rid_new=qb.item_mgr.rid_new,
               ref_item=None)

         if okay_to_delete:

            # Mark the old link_value deleted.
            g.assurt((not lval.fresh) and (lval.stack_id > 0))
            lval.deleted = True
            lval.mark_deleted_update_sql(qb.db)

   # *** Miscellaneous

   #
   def item_type_str(self):
      item_type_str = 'N/a'
      if self.item_type_id:
         item_type_str = Item_Type.id_to_str(self.item_type_id)
      else:
         g.assurt(False) # I think all classes set the item_type_id, right?
      return item_type_str

   # *** Link_Value helpers

   # NOTE: These don't really belong in item_base, but this is the LCD base
   # class for both geofeature and route_step....

   # Helpers for the lightweight lookups.

   #
   def attr_integer(self, attr_internal_name):
      g.assurt(self.attrs is not None)
      val = None
      try:
         the_val = self.attr_val(attr_internal_name)
         if the_val is not None:
            try:
               val = int(the_val)
            except ValueError, e:
               log.error('attr_integer: unexpected: not int: %s / %s / %s'
                  % (attr_internal_name, str(e), traceback.format_exc(),))
         # else, the lval for this attr is not set.
      except Exception, e:
         log.error(
            'attr_integer: unexpected: expection: %s / %s / %s' 
            % (attr_internal_name, str(e), traceback.format_exc(),))
      return val

   #
   def attr_val(self, attr_name):
      try:
         the_val = self.attrs[attr_name]
      except KeyError:
         the_val = None
      return the_val

   #
   def has_tag(self, tag_name):
      tagged = True if tag_name in self.tagged else False
      return tagged

   # RESOURCES: Keeping refs of the link_values (all 500,000 of them) 
   # bloats the MSP p1 route finder to 3 GB memory usage. So we use 
   # lightweight lookups whenever possible -- that is, self.attrs and
   # self.tagged are simple lookups. If you want the link_values themselves,
   # see the self.link_values attribute, which is only populated when needed.

   #
   def link_values_reset(self, qb):
      if hasattr(self, 'link_values') and (self.link_values is not None):
         log.verbose('link_values_reset: whacking %d lvals: %s'
                     % (len(self.link_values), str(self),))
         for lval in self.link_values.itervalues():
            log.verbose('link_values_reset: de-item_caching: %s' % (lval,))
            qb.item_mgr.item_cache_del(lval)
      self.link_values = {}
      self.attrs = {}
      self.tagged = set()
      # All callers end up resetting link_values, so we can safely say we're
      # not wired.
      self.lvals_wired_ = False
      self.lvals_inclusive_ = False

   #
   def wire_link_attribute(self, qb, lval_attr):

      g.assurt(qb.item_mgr.cache_attrs is not None)

      try:
         the_attr = qb.item_mgr.cache_attrs[lval_attr.lhs_stack_id]
      except KeyError:
         the_attr = None
         log.warning(
            'wire_link_attr: missing attr: item_mgr: %s / lhs_stack_id: %d'
            % (qb.item_mgr, lval_attr.lhs_stack_id,))

      if the_attr is not None:
         attr_name = the_attr.value_internal_name
         if not lval_attr.deleted:
            lval_val = lval_attr.get_value(the_attr)
            if not the_attr.multiple_allowed:
               self.attrs[attr_name] = lval_val
            else:
               # 2014.06.30: [lb] will find out if these old comments hold h20:
               # EXPLAIN: How is this path not followed for items w/ watchers?
               # FIXME: ??? Test this, I bet you this code path can be followed...
               g.assurt(False) # Not applicable to user-context item.
               try:
                  self.attrs[attr_name]
               except KeyError:
                  self.attrs[attr_name] = {}
               self.attrs[attr_name][lval_val.stack_id] = lval_val
         else:
            try:
               if not the_attr.multiple_allowed:
                  del self.attrs[attr_name]
               else:
                  # 2014.06.30: FIXME: ??? Is this path followed by item
                  # watchers? We'll find out when watchers are reimplemented.
                  g.assurt(False) # Not applicable to user-context item.
                  del self.attrs[attr_name][lval_val.stack_id]
            except KeyError:
               pass

   #
   def wire_link_tag(self, qb, lval_tag):
      g.assurt(qb.item_mgr.cache_tags is not None)
      try:
         the_tag = qb.item_mgr.cache_tags[lval_tag.lhs_stack_id]
         if the_tag.name:
            if not lval_tag.deleted:
               self.tagged.add(the_tag.name)
            else:
               try:
                  self.tagged.remove(the_tag.name)
               except KeyError:
                  pass
         else:
            g.assurt_soft(False)
      except KeyError:
         log.warning('wire_link_tag: missing tag! item_mgr: %s / stack_id: %d'
                     % (qb.item_mgr, lval_tag.lhs_stack_id,))

   #
   def wire_lval(self, qb, lval, heavywt=False):
      if lval.link_lhs_type_id == Item_Type.TAG:
         self.wire_link_tag(qb, lval)
      elif lval.link_lhs_type_id == Item_Type.ATTRIBUTE:
         self.wire_link_attribute(qb, lval)
      else:
         # This is, e.g., annotation.
         log.verbose2(
            'wire_lval: skipping link to other item type: item_type_id: %s'
            % (lval.link_lhs_type_id,))
      if heavywt:
         if not lval.deleted:
            if lval.lhs_stack_id in self.link_values:
               log.warning(
                     'wire_lval: overwriting lval: %d : %d / old: %s / new: %s'
                           % (id(self.link_values[lval.lhs_stack_id]),
                              id(lval),
                              self.link_values[lval.lhs_stack_id],
                              lval,))
            self.link_values[lval.lhs_stack_id] = lval
            log.verbose('wire_lval: added lval: %s' % (lval,))
         else:
            try:
               del self.link_values[lval.lhs_stack_id]
            except KeyError:
               pass

   #
   def lvals_inclusive(self):
      try:
         lvals_inclusive = self.lvals_inclusive_
      except AttributeError:
         lvals_inclusive = False
      return lvals_inclusive

   #
   def lvals_wired(self):
      try:
         lvals_wired = self.lvals_wired_
      except AttributeError:
         lvals_wired = False
      return lvals_wired

   # *** Deprecated fcns.

   # I [lb] was tempted to delete these but I wonder if they'll be useful for
   # developers, i.e., from ccp.py.

   # Attribute helpers

   #
   def attr_val_slow(self, qb, attr_name):
      attr_value = None
      log.warning('attr_val_slow: This fcn. is deprecated because it is slow.')
      links = link_attribute.Many(attr_name)
      links.search_by_stack_id_rhs(self.stack_id, qb)
      if len(links):
         # NOTE: This doesn't support multiple_allowed.
         g.assurt(len(links) == 1)
         lval_attr = links[0]
         try:
            the_attr = qb.item_mgr.cache_attrs[lval_attr.lhs_stack_id]
            if not lval_attr.deleted:
               attr_value = lval_attr.get_value(the_attr)
         except KeyError:
            log.warning(
               'wire_link_attr: missing attr: item_mgr: %s / lhs_stack_id: %d'
               % (qb.item_mgr, lval_attr.lhs_stack_id,))
      return attr_value

   # Tag helpers

   #
   def has_tag_slow(self, qb, tag_name):
      log.warning('has_tag_slow: This fcn. is deprecated because it is slow.')
      tags = link_tag.Many(tag_name, One.item_type_id)
      tags.search_by_stack_id_rhs(self.stack_id, qb)
      g.assurt(len(tags) <= 1)
      return True if len(tags) == 1 else False

class Many(list):
   '''
   Represents multiple item rows from the database, implemented as a list of
   One() objects. 

   NOTE Is Many really a set? A list seems more "correct", but it may 
        introduce oddities in ordering from the user perspective. For now, 
        we'll leave it as a list, but we'll use wrapper methods for the set
        methods. Subclasses should only use the set methods.
   '''

   # Reference to the One for this Many; subclasses must set define and 
   # declare their own instances of this class variable. Clients use it 
   # to instantiate the One class equivalent of this Many.
   one_class = One

   __slots__ = (
      'grand_total',
      )

   ## Constructor

   def __init__(self):
      self.grand_total = None

   ## Public Interface

   #
   def add(self, item):
      self.append(item)

   #
   def clear(self):
      del self[:]

   #
   def sql_search(self, qb, sql):
      res = qb.db.sql(sql)
      for row in res:
         item = self.get_one(qb, row)
         self.append(item)

   ## Protected Interface

   #
   def append_gml(self, elem, need_digest):
      '''Add a GML child representing myself to elem.'''
      for o in self:
         if isinstance(o, self.one_class):
            o.append_gml(elem, need_digest)
         else:
            g.assurt(isinstance(o, etree._Element))
            elem.append(o)

   #
   # FIXME: Replace this call w/ just self.one_class?
   def get_one(self, qb=None, row=None):
      return self.one_class(qb=qb, row=row)

   #
   def postpare_response(self, doc, elem, extras):
      pass # For most classes, a no-op

   #
   def prepare_resp_doc(self, the_doc, item_type):
      sub_doc = etree.Element('items')
      misc.xa_set(sub_doc, 'ityp', item_type)
      if self.grand_total is not None:
         # Tell the user the complete number of items that match their query.
         misc.xa_set(sub_doc, 'grand_total', self.grand_total)
      the_doc.append(sub_doc)
      return sub_doc

   # ***

# ***

