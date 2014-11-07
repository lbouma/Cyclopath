/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import org.cyclopath.android.items.Track;

/**
 * Interface for handling track deletion confirmation 
 * @author Phil Brown
 */
public interface TrackDeletionHandler {

   /** This method is called once the user confirms whether or not to
    * delete a track.
    * @param track Track object that has been selected
    */
   public void deleteTrack(Track track);
   
}//TrackDeletionHandler
