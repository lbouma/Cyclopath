/* Copyright (c) 2006-2010 Regents of the University of Minnesota.
For licensing terms, see the file LICENSE. */

package org.cyclopath.android.util;

/* Visibility is an enum representing the 3 current levels of visibility
   of a feature when performing a bulk-query. These must match the int
   values stored within the database. */
public class Visibility {

   public static final int all = 1;
   public static final int owner = 2;
   public static final int noone = 3;

}
