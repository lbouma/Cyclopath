# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('access_infer')

class Access_Infer(object):

   # SYNC_ME: Search: Access Infer IDs.

   #
   not_determined    = 0x00000000
   #
   # This is what's sensible for a client to be using for style change.
   acl_choice_mask   = 0x00000022
   restricted_mask   = 0x00090EE9
   permissive_mask   = 0x00000000 # Not used for permissible.
   # This is what's acceptible the server to calculate as an access scope.
   acceptable_mask   = 0x0000FEEB
   #
   all_arbiter_mask  = 0x00001111
   all_denied_mask   = 0x00008888
   not_private_mask  = 0x00007770
   not_public_mask   = 0x00007707
   pub_stealth_mask  = 0x00000770
   #
   usr_mask          = 0x0000000F
   usr_arbiter       = 0x00000001
   usr_editor        = 0x00000002
   usr_viewer        = 0x00000004 # What, private to user but they cannot edit?
   usr_denied        = 0x00000008
   #
   pub_mask          = 0x000000F0
   pub_arbiter       = 0x00000010
   pub_editor        = 0x00000020 # hex(32) == 0x20
   pub_viewer        = 0x00000040 # hex(64) == 0x20
   pub_denied        = 0x00000080
   #
   stealth_mask      = 0x00000F00
   stealth_arbiter   = 0x00000100
   stealth_editor    = 0x00000200 # hex(66048) == 0x10200
   stealth_viewer    = 0x00000400
   stealth_denied    = 0x00000800
   #
   others_mask       = 0x0000F000
   others_arbiter    = 0x00001000
   others_editor     = 0x00002000
   others_viewer     = 0x00004000
   others_denied     = 0x00008000
   #
   sessid_mask       = 0x000F0000
   sessid_arbiter    = 0x00010000 # hex(65536) == 0x10000
   sessid_editor     = 0x00020000
   sessid_viewer     = 0x00040000
   sessid_denied     = 0x00080000

   #
# make_public = 10 # use: usr_denied and pub_editor.
# FIXME: Should make_public really be delete and create (clone)?

   # ***

   lookup = {
      # NOTE: Cannot use Access_Infer.* (not defined yet).
      'not_determined': not_determined,
      'acl_choice_mask': acl_choice_mask,
      'restricted_mask': restricted_mask,
      'acceptable_mask': acceptable_mask,
      'all_arbiter_mask': all_arbiter_mask,
      'not_private_mask': not_private_mask,
      'usr_mask': usr_mask,
      'usr_arbiter': usr_arbiter,
      'usr_editor': usr_editor,
      'usr_viewer': usr_viewer,
      'usr_denied': usr_denied,
      'pub_mask': pub_mask,
      'pub_arbiter': pub_arbiter,
      'pub_editor': pub_editor,
      'pub_viewer': pub_viewer,
      'pub_denied': pub_denied,
      'stealth_mask': stealth_mask,
      'stealth_arbiter': stealth_arbiter,
      'stealth_editor': stealth_editor,
      'stealth_viewer': stealth_viewer,
      'stealth_denied': stealth_denied,
      'others_mask': others_mask,
      'others_arbiter': others_arbiter,
      'others_editor': others_editor,
      'others_viewer': others_viewer,
      'others_denied': others_denied,
      }

   lookup_by_str = lookup

   lookup_by_id = {}
   for k,v in lookup_by_str.iteritems():
      lookup_by_id[v] = k

   #
   def __init__(self):
      raise # do not instantiate.

   #
   @staticmethod
   def get_access_infer_id(as_name_or_id):
      try:
         asid = int(as_name_or_id)
      except ValueError:
         g.assurt(as_name_or_id in Access_Infer.lookup_by_str)
         g.assurt(as_name_or_id != 'not_determined')
         asid = Access_Infer.lookup_by_str[as_name_or_id]
      g.assurt(Access_Infer.is_valid(asid))
      return asid

   #
   @staticmethod
   def get_access_infer_name(access_infer_id):
      g.assurt(Access_Infer.is_valid(access_infer_id))
      return Access_Infer.lookup_by_id[access_infer_id]

#   #
#   @staticmethod
#   def is_valid(access_infer_id):
#      valid = ((access_infer_id in Access_Infer.lookup_by_id)
#               and (access_infer_id != Access_Infer.not_determined))
#      return valid

# ***

