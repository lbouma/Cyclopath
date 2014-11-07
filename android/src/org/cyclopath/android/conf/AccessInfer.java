/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.conf;

/**
 * Part of class Access_Infer.as. Used for setting access permissions for
 * items.
 * @author Fernando
 */
public class AccessInfer {
   public static final int usr_arbiter       = 0x00000001;
   public static final int usr_editor        = 0x00000002;
   public static final int usr_viewer        = 0x00000004;
   public static final int usr_denied        = 0x00000008;
   //
   public static final int pub_arbiter       = 0x00000010;
   public static final int pub_editor        = 0x00000020;
   public static final int pub_viewer        = 0x00000040;
   public static final int pub_denied        = 0x00000080;
   //
   public static final int stealth_arbiter   = 0x00000100;
   public static final int stealth_editor    = 0x00000200;
   public static final int stealth_viewer    = 0x00000400;
   public static final int stealth_denied    = 0x00000800;
   //
   public static final int others_arbiter    = 0x00001000;
   public static final int others_editor     = 0x00002000;
   public static final int others_viewer     = 0x00004000;
   public static final int others_denied     = 0x00008000;
}
