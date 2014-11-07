# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('job_action')

class Job_Action(object):

   # SYNC_ME: tables: public.job_action
   #                  public.enum_definition
   #         sources: flashclient/items/jobsq/Job_Action.as
   #                  pyserver/item/jobsq/job_action.py

   # *** Class attributes

   lookup_obj = (
      [
      # Out of bounds.
      { 'e_key':  -1, 'e_val':  'invalid' },
      { 'e_key':   0, 'e_val':   'notset' },
      # Universal actions.
      { 'e_key':   1, 'e_val':   'create' },
      { 'e_key':   2, 'e_val':   'cancel' },
      { 'e_key':   3, 'e_val':   'delist' },
      { 'e_key':   4, 'e_val':  'suspend' },
      { 'e_key':   5, 'e_val':  'restart' },
      { 'e_key':   6, 'e_val':   'resume' },
      # Custom actions: file actions.
      { 'e_key':   7, 'e_val': 'download' },
      { 'e_key':   8, 'e_val':   'upload' },
      { 'e_key':   9, 'e_val':   'delete' },
      #
      ])

   lookup_key = {}
   lookup_val = {}
   # hack_attack
   for o in lookup_obj:
      lookup_key[o['e_key']] = o['e_val']
      lookup_val[o['e_val']] = o['e_key']

   # *** Constructor

   def __init__(self):
      raise # do not instantiate an object of this class

   #
   @staticmethod
   def get_job_action_code(job_action_name):
      g.assurt(job_action_name in Job_Action.lookup_val)
      return Job_Action.lookup_val[job_action_name]

   #
   @staticmethod
   def get_job_action_name(job_action_code):
      g.assurt(job_action_code in Job_Action.lookup_key)
      return Job_Action.lookup_key[job_action_code]

