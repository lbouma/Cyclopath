#!/usr/bin/python

# Generates a random sequence of passwordy characters.
#
# The core code is by:
# http://stackoverflow.com/questions/7479442/high-quality-simple-random-password-generator
#
# and [lb] made it useable from a Bash script, Jan 2014, e.g.,
#   $ randpwd=$(./random_password.py)

# SyntaxError: from __future__ imports must occur at the beginning of the file
from __future__ import print_function

try:
   import argparse
except ImportError:
   # This is argparse back-ported for Python < 2.7.
   from util_ import argparse

import os
import random
import string
import sys


# In lieu of something more robust and complicated, like
# argparse.ArgumentParser, we just read the one arg.
target_len = 13 # A default.
bail = False
try:
   target_len = int(sys.argv[1])
except IndexError:
   print('No length specified; using: %d' % (target_len,),
         #*objs, end='\n', file=sys.stderr)
         end='\n', file=sys.stderr)
except TypeError:
   bail = True
except ValueError:
   bail = True
finally:
   if bail:
      print('Specified length is not an int: %s' % (sys.argv[1],),
            #*objs, end='\n', file=sys.stderr)
            end='\n', file=sys.stderr)
      sys.exit(1)

# MAYBE: What about the rest: `~-_=+[{]}\|;:'",<.>/?
punctuation = '!@#$%^&*()'

# Here's how the symbols are distributed:
#  len(string.ascii_letters): 52
#   len(string.ascii_lowercase): 26
#   len(string.ascii_uppercase): 26
#  len(string.digits): 10
#  len(punctuation): 10

# Make a big collection of possible symbols to use.
chars = string.ascii_letters + string.digits + punctuation

# This is probably not a good seed for RSA certificates, but for our purposes
# it's fine.
random.seed = (os.urandom(1024))

# The easiest and most completely random solution is the simple approach,
# where each character has the same chance of being selected.
pwd_symbols = [random.choice(chars) for i in range(target_len)]

# With the simple approach, the generated password is not guaranteed to
# continue at least one of each type of symbol, and some systems require
# password that contain, e.g., letters, numbers, and punctuation.
# Here we correct our random data to satisfy this policy.

symbol_categories = [
   string.ascii_lowercase,
   string.ascii_uppercase,
   string.digits,
   punctuation,
   ]

num_categories = len(symbol_categories)

if target_len >= (num_categories * 2):
   # Our replacement algorithm might overwrite what we already wrote.
   double_check = True
   while double_check:
      double_check = False
      for subcat in symbol_categories:
         occurances = 0
         for symbol in pwd_symbols:
            if symbol in subcat:
               occurances += 1
               if occurances >= 2:
                  break
         while occurances < 2:
            replacement = random.choice(subcat)
            position = random.randint(0, len(pwd_symbols)-1)
            if pwd_symbols[position] not in subcat:
               pwd_symbols[position] = replacement
               occurances += 1
               # We overwrote a symbol from another sub-category,
               # so we have to go through this whole process again.
               # Haha, this algorithm is so unpredictable... it
               # could run indefinitely!
               double_check = True
else:
   print('Desired password length too short for tweaking',
         end='\n', file=sys.stderr)

# Assemble the final password.
random_pwd = ''.join(pwd_symbols)

# Spit the password to stdout.
print(random_pwd)

# And we're done.
sys.exit(0)

