#!/usr/bin/python

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME: Delete this file...
#print 'This script is deprecated.'
#assert(False)

# Example usage:
"""
./aliases.py 10000 10000 > 2012.10.16.aliases.sql
psql -U cycling ccpv1_lite < 2012.10.16.aliases.sql
"""

# This script generates first and last names randomly. Usage:
#
#   $ aliases.py OFFSET COUNT | psql
#
# where OFFSET is the number of aliases already in alias_source and COUNT is
# the number of additional aliases to add.
#
# The random seed is the same each run, so the list of names is predictable.
# Output is a SQL script.
#
# Names are filtered through the Caverphone II phonetic algorithm, so e.g.
# only one of Chris and Kris will appear.
#
# Names from US Census: http://www.census.gov/genealogy/names/names_files.html
#
# Note that this script takes ~1 minute to run and requires ~1.2GB memory.
# See notes below: this is because we make an array with 18 million elements.

import string
import sys
import random
import re

MAC_RE = re.compile(r'^(mc|mac|de|van)(.)(.*)')

def main():
   offset = int(sys.argv[1])
   count = int(sys.argv[2])

   # Bug 1572: This file needs an instance-specific seed, but scripts in CcpV1
   #           don't have access to conf. But in CcpV2 it's easy, so for this
   #           *deprecated* CcpV1 script we'll just embed the seed for CcpV1
   #           on itamae.cs.umn.edu.
   name_aliases_random_seed = 8675309
   random.seed(name_aliases_random_seed)

   print '-- reading first names'
   firsts = phonetic_crush(open('../census/names.first.txt').readlines())
   print '-- reading last names'
   lasts = phonetic_crush(open('../census/names.last.txt').readlines())
   print '-- %d first names, %d last names' % (len(firsts), len(lasts))
   print '-- generating combined names'
   names = list()
   for first_name in firsts:
      for last_name in lasts:
         alias_name = ('%s_%s' % (first_name, last_name,))
         names.append(alias_name)
   print '-- created %d names pairs' % (len(names),)
   print '-- shuffling'
   # MAYBE: This is memory intensive... dev machines watch out.
   random.shuffle(names)
   print '-- output'
   print 'BEGIN;'
   print 'COPY public.alias_source (id, text) FROM STDIN;'
   # Bug 2735: The range gots to offset plus count, not just count.
   assert(len(names) > (offset + count))
   for i in xrange(offset, offset + count):
      # NOTE: We're adding one to i because i is 0-based but offset is 1-based.
      # NOTE: We using names[i] and not names[i - offset] so that we pick
      #       up in the names array where we left off the last time we used
      #       this script (we is why we used the same seed for random).
      print '%d\t%s' % (i + 1, names[i])
   print '\\.'
   print 'COMMIT;'

# def capitalize(name):
#    '''Return a semi-intelligently capitalized version of name.'''
#    name = name.lower()
#    # capitalize letter after Mac/Mc/etc
#    m = re.search(MAC_RE, name)
#    if (m is not None):
#       name = m.group(1) + m.group(2).upper() + m.group(3)
#    # capitalize first letter, leave others alone
#    return (name[:1].upper() + name[1:])


def phonetic_crush(names):
   '''Given a list of names: for each name foo, remove all following
      phonetically similar names. Return the new list, in arbitrary order.'''
   d = dict()
   for name in reversed(names):
      name = name[:-1]   # strip trailing newline
      d[caverphone(name)] = name.lower()
   return d.values()
   

####
#
# This function is taken from the AdvaS library http://advas.sourceforge.net/
# by Frank Hofmann et al. and is GPL2.
#
####
def caverphone (term):
	"returns the language key using the caverphone algorithm 2.0"

	# Developed at the University of Otago, New Zealand.
	# Project: Caversham Project (http://caversham.otago.ac.nz)
	# Developer: David Hood, University of Otago, New Zealand
	# Contact: caversham@otago.ac.nz
	# Project Technical Paper: http://caversham.otago.ac.nz/files/working/ctp150804.pdf
	# Version 2.0 (2004-08-15)

	code = ""

	i = 0
	term_length = len(term)

	if (term_length == 0):
		# empty string ?
		return code
	# end if

	# convert to lowercase
	code = string.lower(term)

	# remove anything not in the standard alphabet (a-z)
	code = re.sub(r'[^a-z]', '', code)

	# remove final e
	if code.endswith("e"):
		code = code[:-1]

	# if the name starts with cough, rough, tough, enough or trough -> cou2f (rou2f, tou2f, enou2f, trough)
	code = re.sub(r'^([crt]|(en)|(tr))ough', r'\1ou2f', code)

	# if the name starts with gn -> 2n
	code = re.sub(r'^gn', r'2n', code)

	# if the name ends with mb -> m2
	code = re.sub(r'mb$', r'm2', code)

	# replace cq -> 2q
	code = re.sub(r'cq', r'2q', code)
	
	# replace c[i,e,y] -> s[i,e,y]
	code = re.sub(r'c([iey])', r's\1', code)
	
	# replace tch -> 2ch
	code = re.sub(r'tch', r'2ch', code)
	
	# replace c,q,x -> k
	code = re.sub(r'[cqx]', r'k', code)
	
	# replace v -> f
	code = re.sub(r'v', r'f', code)
	
	# replace dg -> 2g
	code = re.sub(r'dg', r'2g', code)
	
	# replace ti[o,a] -> si[o,a]
	code = re.sub(r'ti([oa])', r'si\1', code)
	
	# replace d -> t
	code = re.sub(r'd', r't', code)
	
	# replace ph -> fh
	code = re.sub(r'ph', r'fh', code)

	# replace b -> p
	code = re.sub(r'b', r'p', code)
	
	# replace sh -> s2
	code = re.sub(r'sh', r's2', code)
	
	# replace z -> s
	code = re.sub(r'z', r's', code)

	# replace initial vowel [aeiou] -> A
	code = re.sub(r'^[aeiou]', r'A', code)

	# replace all other vowels [aeiou] -> 3
	code = re.sub(r'[aeiou]', r'3', code)

	# replace j -> y
	code = re.sub(r'j', r'y', code)

	# replace an initial y3 -> Y3
	code = re.sub(r'^y3', r'Y3', code)
	
	# replace an initial y -> A
	code = re.sub(r'^y', r'A', code)

	# replace y -> 3
	code = re.sub(r'y', r'3', code)
	
	# replace 3gh3 -> 3kh3
	code = re.sub(r'3gh3', r'3kh3', code)
	
	# replace gh -> 22
	code = re.sub(r'gh', r'22', code)

	# replace g -> k
	code = re.sub(r'g', r'k', code)

	# replace groups of s,t,p,k,f,m,n by its single, upper-case equivalent
	for single_letter in ["s", "t", "p", "k", "f", "m", "n"]:
		otherParts = re.split(single_letter + "+", code)
		code = string.join(otherParts, string.upper(single_letter))
	
	# replace w[3,h3] by W[3,h3]
	code = re.sub(r'w(h?3)', r'W\1', code)

	# replace final w with 3
	code = re.sub(r'w$', r'3', code)

	# replace w -> 2
	code = re.sub(r'w', r'2', code)

	# replace h at the beginning with an A
	code = re.sub(r'^h', r'A', code)

	# replace all other occurrences of h with a 2
	code = re.sub(r'h', r'2', code)

	# replace r3 with R3
	code = re.sub(r'r3', r'R3', code)

	# replace final r -> 3
	code = re.sub(r'r$', r'3', code)

	# replace r with 2
	code = re.sub(r'r', r'2', code)

	# replace l3 with L3
	code = re.sub(r'l3', r'L3', code)
	
	# replace final l -> 3
	code = re.sub(r'l$', r'3', code)
	
	# replace l with 2
	code = re.sub(r'l', r'2', code)

	# remove all 2's
	code = re.sub(r'2', r'', code)

	# replace the final 3 -> A
	code = re.sub(r'3$', r'A', code)
	
	# remove all 3's
	code = re.sub(r'3', r'', code)

	# extend the code by 10 '1' (one)
	code += '1' * 10
	
	# take the first 10 characters
	caverphoneCode = code[:10]
	
	# return caverphone code
	return caverphoneCode


if (__name__ == '__main__'):
   main()
