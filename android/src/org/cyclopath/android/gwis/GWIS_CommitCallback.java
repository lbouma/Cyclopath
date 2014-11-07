/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import android.util.SparseIntArray;

/**
 * A callback interface for commits
 * @author Fernando Torre
 */
public interface GWIS_CommitCallback {

   /**
    * This method handles the id map sent back after a commit.
    */
   public void handleGWIS_CommitCallback(SparseIntArray id_map);
   
}
