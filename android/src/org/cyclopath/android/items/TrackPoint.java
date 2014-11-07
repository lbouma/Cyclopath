/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.DOMException;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

import android.location.Location;

/**
 * Class that represents points in a track.
 * @author Fernando Torre
 */
public class TrackPoint {
   
   /** x location of point */
   public double x;
   /** y location of point */
   public double y;
   /** when the point was recorded */
   private Date timestamp;
   /** altitude of this point */
   public Double altitude;
   /** direction of travel in degrees East of true North */
   public Float bearing;
   /** speed of the device over ground in meters/second */
   public Float speed;
   /** device orientation (can be null) */
   public Float orientation;
   /** temperature (can be null) */
   public Float temperature;
   
   /**
    * Constructor
    * @param x
    * @param y
    * @param time
    */
   public TrackPoint(double x, double y, Date time) {
      this.x = x;
      this.y = y;
      this.setTimestamp(time);
   }
   
   /**
    * Constructor that accepts a Point as a parameter.
    * @param p
    * @param time
    */
   public TrackPoint(PointD p, Date time) {
      this(p.x, p.y, time);
   }
   
   /**
    * Constructor that uses a location to build the track point.
    * @param loc
    */
   public TrackPoint(Location loc, Float orientation, Float temperature) {
      PointD p = G.latlonToMap(loc);
      this.setTimestamp(new Date());
      this.x = Math.round(p.x*10)/10f;
      this.y = Math.round(p.y*10)/10f;
      if (loc.getAltitude() != 0.0f) {
         this.altitude = loc.getAltitude();
      }
      if (loc.getBearing() != 0.0) {
         this.bearing = loc.getBearing();
      }
      if (loc.getSpeed() != 0.0f) {
         this.speed = loc.getSpeed();
      }
      if (orientation != null) {
         this.orientation = orientation;
      }
      if (temperature != null) {
         this.temperature = temperature;
      }
   }

   /**
    * Constructor that uses a node element to construct the track point.
    * @param data node containing track point data.
    */
   public TrackPoint(Node data) {
      if (data != null) {
         SimpleDateFormat sdf =
            new SimpleDateFormat(Constants.SERVER_DATE_FORMAT);
         NamedNodeMap atts = data.getAttributes();
         this.x = XmlUtils.getFloat(atts, "x", 0f);
         this.y = XmlUtils.getFloat(atts, "y", 0f);
         try {
            this.timestamp =
               sdf.parse(XmlUtils.getString(atts, "timestamp", ""));
         } catch (DOMException e) {
            this.timestamp = new Date();
            e.printStackTrace();
         } catch (ParseException e) {
            this.timestamp = new Date();
            e.printStackTrace();
         }
         this.altitude = XmlUtils.getDouble(atts, "altitude", null);
         this.bearing = XmlUtils.getFloat(atts, "bearing", null);
         this.speed = XmlUtils.getFloat(atts, "speed", null);
         this.orientation = XmlUtils.getFloat(atts, "orientation", null);
         this.temperature = XmlUtils.getFloat(atts, "temperature", null);
      }
   }

   /**
    * Outputs this track point as a GPX string.
    */
   public String asGPX() {
      StringBuilder gpx = new StringBuilder();
      double[] latlon = G.mapToLatLon(new PointD(this.x, this.y));

      gpx.append("<trkpt lat=\"" + latlon[0]
                   + "\" lon=\"" + latlon[1] + "\">");
      if (this.altitude != null) {
         gpx.append("<ele>" + this.altitude + "</ele>");
      }
      gpx.append("<time>"
                 + Constants.GPX_TIMESTAMP_FORMAT.format(this.timestamp)
                 + "</time>");
      gpx.append("</trkpt>\n");

      return gpx.toString();
   }

   /**
    * Sets the timestamp for this point.
    * @param timestamp
    */
   public void setTimestamp(Date timestamp) {
      this.timestamp = timestamp;
   }

   /**
    * Gets the timestamp for this point.
    * @return
    */
   public Date getTimestamp() {
      return timestamp;
   }
}
