package org.cyclopath.android.conf;

/**
 * This class has values that are specific to development instances and
 * testing. All values are pointed to from Constants.java.
 * 
 * To use, copy this file, remove '_TEMPLATE' from the file name and from the
 * class name, and insert the desired values. As long
 * as this file doesn't change developers can just keep a copy of the file
 * with the values filled in and copy it in every time they check out a branch.
 * 
 * IMPORTANT:
 * NEVER check into svn the CONFIG file, only the template file.
 * @author Fernando Torre
 *
 */
public class CONFIG_TEMPLATE {

   /** server url */
   public static final String SERVER_URL = "http://magic.cyclopath.org";
   /** login for making bit.ly requests*/
   public static String BITLY_LOGIN = "login=";
   /** api key for making bit.ly requests*/
   public static String BITLY_APIKEY = "&apiKey=";
   /** Debugging */
   public static final boolean DEBUG = false;
}
