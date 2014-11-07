/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.conf;

/**
 * Draw classes for map objects. This class is based on
 * flashclient/Draw_Class.as
 * @author Fernando Torre
 */
public class DrawClass {
   // NOTE: This must be kept up to date with the draw_class database table!

   public static final int SMALL = 11;
   public static final int BIKETRAIL = 12;
   public static final int MEDIUM = 21;
   public static final int LARGE = 31;
   public static final int SUPER = 41;

   public static final int OPENSPACE = 2;
   public static final int WATER = 3;

   public static final int BACKGROUND = 4;
   public static final int SHADOW = 1;

   public static final int POINT = 5;
   public static final int WATCHREGION = 6;
   public static final int REGION = 9;
   public static final int WORKHINT = 7;
   public static final int ROUTE = 8;
   public static final int TRACK = 10;
}
