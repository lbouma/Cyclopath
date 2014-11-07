# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('job_status')

class Job_Status(object):

   # SYNC_ME: tables: public.job_status
   #                  public.enum_definition.
   #         sources: flashclient/items/jobsq/Job_Status.py
   #                  pyserver/item/jobsq/job_status.py

   # *** Class attributes

   # Cmp.: Job_Status.statuses_complete / work_item.One.finished_statuses
   # FIXME: Why is/was queued in this list? 2012.05.10: [lb] removed it.
   incancellable_statuses = ('complete', 'failed', 'canceled', 'aborted',)
   finished_statuses = incancellable_statuses + ('suspended',)

   lookup_obj = (
      [
      # Out of bounds.
      { 'e_key':  -1, 'e_val':    'invalid' },
      { 'e_key':   0, 'e_val':     'notset' },
      # Universal statuses.
      { 'e_key':   1, 'e_val':   'complete' },
      { 'e_key':   2, 'e_val':     'failed' },
      { 'e_key':   3, 'e_val':     'queued' },
      { 'e_key':   4, 'e_val':   'starting' },
      { 'e_key':   5, 'e_val':    'working' },
      { 'e_key':   6, 'e_val':    'aborted' },
      { 'e_key':   7, 'e_val':  'canceling' },
      { 'e_key':   8, 'e_val': 'suspending' },
      { 'e_key':   9, 'e_val':   'canceled' },
      { 'e_key':  10, 'e_val':  'suspended' },
      #
      ])

   lookup_key = {}
   lookup_val = {}
   # hack_attack
   for o in lookup_obj:
      lookup_key[o['e_key']] = o['e_val']
      lookup_val[o['e_val']] = o['e_key']

   # ***

   state_changes = (
      {
      'invalid':   ('queued', ),
      'notset':    ('queued', ),
      'queued':    ('starting', 'canceling',),
      'starting':  ('working',  'complete', 'failed', 'canceling',),
      'working':   ('working',  'complete', 'failed', 'canceling',),
      'canceling': ('canceled', 'complete', 'failed',),
      })

   # *** Constructor

   def __init__(self):
      raise # do not instantiate an object of this class

   #
   @staticmethod
   def get_job_status_code(job_status_name):
      g.assurt(job_status_name in Job_Status.lookup_val)
      return Job_Status.lookup_val[job_status_name]

   #
   @staticmethod
   def get_job_status_name(job_status_code):
      g.assurt(job_status_code in Job_Status.lookup_key)
      return Job_Status.lookup_key[job_status_code]

