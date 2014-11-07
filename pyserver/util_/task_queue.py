# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A task queue implements the thread pool pattern, wherein a bunch of threads 
# complete a bunch of tasks.
#
# The task queue is comprised of one Producer and many Consumers. Objects that
# use a task_queue interact with the Producer, with in turn interacts with the
# Consumers. This is a Good Thing, as the Producer <-> Consumer communications
# are a very messy, intricate business. All clients of this class have to worry
# about is gaiting access to the Producer.

import os
import sys
import threading
import traceback

import conf
import g

log = g.log.getLogger('task_queue')

__all__ = [
   'Task_Queue_Error',
   'Task_Queue_At_Capacity_Error',
   'Task_Queue_Complete_Error',
   'Task_Queue',
   ]

# ***

class Task_Queue_Error(Exception):
   '''Base work queue error. All work queue errors derive from this.'''
   pass

class Task_Queue_At_Capacity_Error(Task_Queue_Error):
   '''The work queue is full. Clients should check that the work queue
      can accept more work items before trying to add to it.'''
   pass

class Task_Queue_Complete_Error(Task_Queue_Error):
   '''The work queue was explicitly stopped. It is done for.'''
   pass

# ***

# FIXME: This could/should be multiprocessor.Process...
class Task_Queue_Consumer(threading.Thread):
   '''
   Each of the consumers is really just a Python thread. They do work when
   work is available, and the work is just a Python function and arguments.
   '''

   def __init__(self, producer, **kwds):
      '''
      Initiliazes and starts the Consumer thread. The thread is set to
      daemonic so that it doesn't prevent Python from exiting when requested
      (though the Producer may catch the first exit event and try to
      graceful stop all the Consumer threads).

      producer
      A pointer to the producer object, which contains the work item lists,
      queues, and locks.

      kwds
      Keywords to pass to threading.Thread on initialization; generally not
      used.

      '''
      threading.Thread.__init__(self, **kwds)
      self.setDaemon(True) # So python can exit without us
      self.producer = producer
      self.started_event = threading.Event()
      self._stop_event = threading.Event()
      self.start()

   def run(self):
      '''
      The Consumer thread's run routine loops indefinitely, processing work
      items as they become available.

      It'd be nice to use the built-in Queue class, but there's no mechanism
      for detecting a stop event without busy waiting (since Python only
      supports one wait object at a time). Fortunately, we can use a list
      and a condition variable to achieve the same effect. All of these are
      part of the Producer so that each Consumer uses the same locks, lists,
      condition variables, events, and queues.

      NOTE See the Producer for how work items are packaged. This module
      uses tuples, which have less overhead than other containers.
      '''
      self.started_event.set()
      # Loop until told to stop
      while True:
         # Grab the lock before checking the stop event
         log.verbose('consumer.run: acquiring lock... [work_condit]')
         self.producer.work_condit.acquire()
         log.verbose('consumer.run:  acquired lock.')
         if (self.producer.stop_event.isSet() 
             or self._stop_event.isSet()):
            log.verbose('consumer.run: releasing lock. [work_condit]')
            self.producer.work_condit.release()
            break
         if not self.producer.task_queue:
            # Wait for a new job to arrive.
            log.verbose('consumer.run: waiting/releasing lock [work_condit]')
            self.producer.work_condit.wait(timeout=None)
         # else, there's a new job waiting for us.
         log.verbose('consumer.run: awoken/re-acquired lock. [work_condit]')
         if self.producer.task_queue:
            work_item = self.producer.task_queue.pop(0)
            if not self.producer.task_queue:
               self.producer.work_empty.set()
            self.producer.busy_count += 1
         else:
            # Some other thread got it, or we
            # were woken to detect the stop event
            work_item = None
         log.verbose('consumer.run: releasing lock. [work_condit]')
         self.producer.work_condit.release()
         if work_item:
            try:
               # Work Item => (processing function, its args, its keywords,
               #               successful function, exception function)
               # Process the work item
               log.debug('run: processing work item: %s' % (work_item[0],))
               result = work_item[0](*work_item[1], **work_item[2])
               # Post-process if successfully processed
               log.debug('run: processing result: %s / %s' 
                         % (result, work_item[0],))
               if work_item[3]:
                  work_item[3](result, *work_item[1], **work_item[2])
               # else, user doesn't care about result, or already handled it
            except Exception, e:
               # FIXME: AssertionError does not print anything?
               #conf.break_here('ccpv3')
               log.debug('run: processing exception: %s / %s' 
                         % (str(e), work_item[0],))

               # FIXME
               err_s, detail, trbk = sys.exc_info()
               log.warning('run: failed:')
               log.warning('%s' % (err_s,))
               log.warning('%s\n%s' 
                           % (detail, ''.join(traceback.format_tb(trbk)),))
               #
               stack_trace = traceback.format_exc()
               log.warning('Warning: Unexpected exception: %s' % stack_trace)

               if work_item[4]:
                  work_item[4](sys.exc_info(), *work_item[1], **work_item[2])
               else:
                  stack_trace = traceback.format_exc()
                  log.error('Warning: Unexpected exception: %s' % stack_trace)
            log.verbose('consumer.run: acquiring lock... [work_condit]')
            self.producer.work_condit.acquire()
            log.verbose('consumer.run:  acquired lock.')
            self.producer.busy_count -= 1
            log.verbose('consumer.run: releasing lock. [work_condit]')
            self.producer.work_condit.release()
            if work_item[5]:
               work_item[5](*work_item[1], **work_item[2])

      # All done!

   def stop(self):
      '''Tells the thread to exit when it's done with the current job.'''
      self._stop_event.set()

# ***

class Task_Queue:
   '''
   The Task_Queue maintains a collection of threads, i.e., a thread pool, and
   a collection of work items, i.e., requests, populated into a common list
   that the consumer threads share.
   '''

   def __init__(self, num_consumers, work_item_limit=None, wait_started=False):
      '''
      Sets up a thread pool and start the consumer threads. work_item_limit,   
      if non-zero, is the maximum number of pending work item requests that    
      will be accepted (if this limit would be exceeded when a new work item   
      is received, the Producer raises an exception); if zero, there is no     
      limit to the number of pending work items that can be queued             
      '''
      self._work_item_limit = 0
      self.set_work_item_limit(work_item_limit)
      self.stopping_event = threading.Event()
      self.stop_event = threading.Event()
      self.task_queue = []
      self.work_condit = threading.Condition()
      self.work_empty = threading.Event()
      self.work_empty.set()
      self._consumers = []
      self._consumers_lock = threading.RLock()
      self.add_consumers(num_consumers,
         wait_started=wait_started)
      self.busy_count = 0

   def set_work_item_limit(self, work_item_limit):
      self._work_item_limit = work_item_limit

   def add_consumers(self, num_consumers, wait_started=False):
      '''
      Adds the indicated number of new Consumer threads to the thread pool,
      optionally waiting for the threads to start.
      '''
      started_consumers = []
      try:
         log.verbose('consumer.run: acquiring lock... [_consumers_lock]')
         self._consumers_lock.acquire()
         log.verbose('consumer.run:  acquired lock.')
         if self.stopping_event.isSet():
            raise Task_Queue_Complete_Error
         for i in xrange(num_consumers):
            consumer = Task_Queue_Consumer(self)
            self._consumers.append(consumer)
            started_consumers.append(consumer)
      finally:
         log.verbose('consumer.run: releasing lock. [_consumers_lock]')
         self._consumers_lock.release()
      if wait_started:
         for consumer in started_consumers:
            log.verbose(
               'add_consumers: waiting/releasg lock... [started_event]')
            consumer.started_event.wait()

   def del_consumers(self, num_consumers=None, join_stopped=False):
      '''Removes the indicated number of new Consumer threads
      to the thread pool, optionally waiting for the threads
      to stop.
      '''
      stopped_consumers = []
      if num_consumers is None:
         num_consumers = len(self._consumers)
      try:
         log.verbose('del_consumers: acquiring lock... [_consumers_lock]')
         self._consumers_lock.acquire()
         log.verbose('del_consumers:  acquired lock.')
         if self.stopping_event.isSet():
            raise Task_Queue_Complete_Error
         for i in xrange(min(num_consumers, len(self._consumers))):
            consumer = self._consumers.pop()
            consumer.stop()
            stopped_consumers.append(consumer)
      finally:
         log.verbose('del_consumers: releasing lock. [_consumers_lock]')
         self._consumers_lock.release()
      log.verbose('del_consumers: acquiring lock... [work_condit]')
      self.work_condit.acquire()
      log.verbose('del_consumers:  acquired lock.')
      #log.debug('del_consumers: notifying threads, all')
      self.work_condit.notifyAll()
      log.verbose('del_consumers: releasing lock. [work_condit]')
      self.work_condit.release()
      # Signal all the consumers; the ones that are stopped will see
      # their stop_event asserted and will exit; the others will see
      # nothing and go back to waiting for work to do
      if join_stopped:
         #log.debug('joining stopped_consumers')
         for consumer in stopped_consumers:
            consumer.join()
         #log.debug('joined!')

   def add_work_item(self, f_process, 
                           process_args=None, 
                           process_kwds=None,
                           f_on_success=None, 
                           f_on_exception=None,
                           f_postprocess=None):
      '''
      Creates a work item, which consists of the fcn. to call to process the
      work request and two fcns. to call upon completion, one if the work
      request is successfully processed, the other if there's an error. Each
      callback can be passed the same args and keywords.
      '''
      g.assurt(callable(f_process))
      g.assurt(not process_args or isinstance(process_args, list))
      g.assurt(not process_kwds or isinstance(process_kwds, dict))
      g.assurt(not f_on_success or callable(f_on_success))
      g.assurt(not f_on_exception or callable(f_on_exception))
      g.assurt(not f_postprocess or callable(f_postprocess))
      if self.stopping_event.isSet():
         raise Task_Queue_Complete_Error
      try:
         log.verbose('add_work_item: acquiring lock... [work_condit]')
         self.work_condit.acquire()
         log.verbose('add_work_item:  acquired lock.')
         if ((self._work_item_limit is not None)
             and (len(self.task_queue) >= self._work_item_limit)):
            raise Task_Queue_At_Capacity_Error
         if f_on_exception is None:
            f_on_exception = self._handle_thread_exception
         # Create a work item tuple
         self.task_queue.append((f_process, 
                                 process_args or [], 
                                 process_kwds or {}, 
                                 f_on_success, 
                                 f_on_exception,
                                 f_postprocess,))
         self.work_empty.clear()
         # Notify the Consumer threads
         #log.debug('add_work_item: notifying threads')
         self.work_condit.notify()
      finally:
         log.verbose('add_work_item: releasing lock. [work_condit]')
         self.work_condit.release()

   #
   def busy(self):
      # Is this right?
      return (len(self._consumers) == self.busy_count)

   #
   def available(self):
      # Is this right?
      return (len(self._consumers) - self.busy_count)

   # FIXME: Can this fcn. be called twice or more?
   def stop_consumers(self, wait_empty=True, do_joins=False):
      '''
      Sets the stop event and wakes all Consumer threads so they exit. 
      Optionally waits for threads to complete.
      '''
      try:
         log.verbose('consumer.run: acquiring lock... [_consumers_lock]')
         self._consumers_lock.acquire()
         log.verbose('consumer.run:  acquired lock.')
         if self.stopping_event.isSet():
            # FIXME: Is this really necessary?
            #        Just allowing re-cycling?
            raise Task_Queue_Complete_Error
         self.stopping_event.set()
         stopped_consumers = self._consumers
         self._consumers = []
      finally:
         log.verbose('stop_consumers: releasing lock. [_consumers_lock]')
         self._consumers_lock.release()
      # Wait for it...
      if wait_empty:
         log.verbose('stop_consumers: waiting/releasing lock...')
         self.work_empty.wait()
      # Stop the threads
      self.stop_event.set()
      log.verbose('stop_consumers: acquiring lock... [work_condit]')
      self.work_condit.acquire()
      log.verbose('stop_consumers:  acquired lock.')
      #log.debug('stop_consumers: notifying threads, all')
      self.work_condit.notifyAll()
      log.verbose('stop_consumers: releasing lock. [work_condit]')
      self.work_condit.release()
      # Wait for it (again)
      if do_joins:
         for consumer in stopped_consumers:
            consumer.join()

# ***

if __name__ == '__main__':
   pass

