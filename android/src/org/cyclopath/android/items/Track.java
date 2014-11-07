/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.text.DecimalFormat;
import java.text.NumberFormat;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.AccessInfer;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.DOMException;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import android.graphics.Color;
import android.graphics.Paint;
import android.os.Parcel;
import android.os.Parcelable;
import android.text.format.DateFormat;

/**
 * The Track Object contains a series of points and annotations.
 * Tracks are objects that can be drawn on the map.
 * @author Phil Brown
 * @author Fernando Torre
 */
public class Track extends Geofeature implements Parcelable {
   
   /** Owner for this track*/
   public String owner;
   /** Date this track was created.*/
   public Date date;
   /** Notes for this track.*/
   public String comments;
   /** track duration in milliseconds */
   public Long duration;
   /** Length of the track, in meters */
   public double length;
   
   public int trial_num;
   
   /** Format for displaying the date and time*/
   SimpleDateFormat dateFormat 
         = new SimpleDateFormat(Constants.TRACK_DATE_FORMAT);
   
   /** This is the data structure used to hold the points of the track.*/
   public ArrayList<TrackPoint> points;
   /** Whether this track is currently being recorded. */
   public boolean recording;
   
   // *** Constructors
   
   /**
    * Master constructor
    * @param name The name of the track
    * @param owner The owner of the track
    * @param point The first point of the track
    * @param notes The notes text associated with this track
    * @param date When the track was created
    */
   public Track(String name, String owner,
                TrackPoint point, String notes, Date date,
                boolean recording) {
      super(null);
      this.date = date;
      if (name == null || name.equals("")){
         name = this.getFormattedDate();
      }
      this.comments = notes;
      this.points = new ArrayList<TrackPoint>();
      if (point != null){
        this.points.add(point);
      }
      this.name = name;
      this.owner = owner;
      this.deleted = false;
      this.gfl_id = 106;
      this.length = 0;
      this.recording = recording;
      this.trial_num = -1;
   }//Track
   
   /** Constructs a new Track*/
   public Track(String owner) {
      this(null, owner, null, null, null, false);
   }//Track
   
   /**
    * Constructs a new track from a Document object.
    * @param data document containing track data.
    */
   public Track(Node root) {
      super(root);

      if (root != null) {
         this.gmlConsume(root);
      }
      this.recording = false;
      this.trial_num = -1;
   }
   
   /**
    * Constructor (for track list).
    */
   public Track(int stack_id,
                String name, String owner, Date date,
                long duration, double length) {
      super(null);
      this.stack_id = stack_id;
      this.name = name;
      this.owner = owner;
      this.date = date;
      this.duration = duration;
      this.length = length;
      this.recording = false;

      // Initialize track points
      this.points = new ArrayList<TrackPoint>();
   }
   
   /**
    * Constructor to use when re-constructing Track from a parcel.
    * @param in a parcel from which to read this track
    */
   public Track(Parcel in) {
      super(null);
      this.stack_id = in.readInt();
      this.name = in.readString();
      this.owner = in.readString();
      this.date = new Date(in.readLong());
      this.duration = in.readLong();
      this.length = in.readDouble();
      this.recording = in.readInt() == 1;
      this.trial_num = in.readInt();
   }

   // *** Getters and Setters
   
   /**
    * Returns the duration of the track in minutes.
    */
   public long getDuration() {
      if (this.points.size() < 2) {
         if (this.duration != null) {
            return this.duration.longValue();
         } else {
            return 0;
         }
      } else {
         return (this.points.get(this.points.size()-1).getTimestamp().getTime()
                  - this.points.get(0).getTimestamp().getTime());
      }
   }
   
   /**
    * Returns the formatted duration of this track in hh:mm:ss format
    */
   public String getFormattedDuration() {
      NumberFormat time = new DecimalFormat("00");
      int seconds = Math.round(this.getDuration() / 1000);
      int minutes = seconds / 60;
      seconds = seconds % 60;
      int hours = minutes / 60;
      minutes = minutes % 60;
      return hours + ":" + time.format(minutes) + ":" + time.format(seconds);
   }
   
   /**
    * Returns the formatted average spped of this track in mph.
    */
   public String getFormattedAvgSpeed() {
      double miles = this.length * Constants.MILES_PER_METER;
      double hours = this.getDuration() / 60f;
      DecimalFormat dformat = new DecimalFormat("0.0");
      dformat.setPositiveSuffix("mph");
      return dformat.format(miles/hours);
   }

   /**
    * Returns the point associated with this item.
    * @return point
    */
   public TrackPoint getTrackPoint(int index) {
      if (index < points.size() && index >= 0) {
         return points.get(index);
      } else {
         return null;
      }
   }//getPoint
   
   /**
    * Return points in track
    * @return {@link #points points}
    */
   public ArrayList<TrackPoint> getTrackPoints() {
      return points;
   }//getPoints
   
   /**
    * @return Date Object formatted in the form
    * yyyy/MM/dd HH:mm:ss if context is null, or in the form specified by the 
    * user if context is not null.
    */
   public String getFormattedDate() {
      if (date == null) {
         return null;
      }
      if (G.app_context == null) {
         return this.dateFormat.format(date);
      }
      String format = DateFormat.getDateFormat(G.app_context).format(date)
                      + " "
                      + DateFormat.getTimeFormat(G.app_context).format(date);
      return format;
   }//getFormattedDate
   
   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.TRACK;
   }

   /**
    * @return arraylist of points.
    */
   public synchronized ArrayList<PointD> getPointsArrayList() {
      ArrayList<PointD> results = new ArrayList<PointD>();
      for (TrackPoint tp : this.points) {
         results.add(new PointD(tp.x, tp.y));
      }
      return results;
   }

   /**
    * Returns the access style for this item.
    */
   @Override
   public int getStyleId() {
      return AccessInfer.usr_arbiter;
   }

   /**
    * Return z level of tracks.
    */
   @Override
   public float getZplus() {
      if (this.recording) {
         return Constants.TRACK_RECORDING_LAYER;
      } else {
         return Constants.TRACK_LAYER;
      }
   }
   
   // *** Other methods

   /**
    * This method is called to add a new Point to the track.
    * It is meant to be used instead of accessing 
    * {@link #points points} directly from another class.
    * This is because when adding a new point, this add
    * first recalculates the current {@link #rect rect's}
    * bounds and increases them if p is outside of the
    * Rect. Then the point is added to {@link #points points}.
    * @param p The new track point
    */
   public synchronized boolean add(TrackPoint p){
      if (points.size() > 0) {
         // Don't add a new point if its location is the same as the last
         // point.
         TrackPoint last = points.get(points.size() - 1);
         if (p.x == last.x && p.y == last.y) {
            return false;
         }
         // update track length
         if (this.fresh) {
            this.length = this.length + Math.sqrt((p.x-last.x)*(p.x-last.x)
                                                  + (p.y-last.y)*(p.y-last.y));
         }
      }
      points.add(p);
      this.xys.add(new PointD(p.x,p.y));
      this.calculateBbox();
      return true;
   }//add
   
   /**
    * Outputs this track as a GPX string.
    */
   public String asGPX() {
      StringBuilder gpx = new StringBuilder();
      
      // write header
      gpx.append("<?xml version=\"1.0\" encoding=\"ISO-8859-1\" " +
      		     "standalone=\"yes\"?>\n");
      gpx.append("<?xml-stylesheet type=\"text/xsl\" " +
      		     "href=\"details.xsl\"?>\n");
      gpx.append("<gpx" +
      		     " version=\"1.1\"" +
      		     " creator=\"Cyclopath for Android - http://cyclopath.org\"" +
      		     " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" +
      		     " xmlns=\"http://www.topografix.com/GPX/1/1\"" +
      		     " xmlns:topografix=" +
      		     "\"http://www.topografix.com/GPX/Private/TopoGrafix/0/1\"" +
      		     " xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 " +
      		     "http://www.topografix.com/GPX/1/1/gpx.xsd\">\n");

      // write metadata
      gpx.append("<metadata>");
      gpx.append("<author>");
      gpx.append("<name>Cyclopath</name>");
      gpx.append("<email id=\"info\" domain=\"cyclopath.org\" />");
      gpx.append("<link href=\"http://cyclopath.org\" />");
      gpx.append("</author>");
      gpx.append("</metadata>\n");

      // write track
      gpx.append("<trk>");
      gpx.append("<name>" + this.name + "</name>");
      gpx.append("<cmt>" + this.notes + "</cmt>");
      gpx.append("<trkseg>\n");
      for (TrackPoint tp:this.points) {
         gpx.append(tp.asGPX());
      }
      gpx.append("</trkseg>");
      gpx.append("</trk>");

      gpx.append("</gpx>");

      return gpx.toString();
   }

   /**
    * Draws the track, point by point, on the map.
    * @see org.cyclopath.android.Geopoint
    */
   @Override
   public void draw(){
      if (points.isEmpty()) {
         return;
      }
      TrackPoint startpoint = points.get(0);
      TrackPoint endpoint = points.get(points.size() - 1);
      
      int track_color = Constants.TRACK_COLOR;
      if (this.recording) {
         track_color = Constants.TRACK_RECORDING_COLOR;
      }
      // Draw border first (if the track has been saved)
      if (!this.recording) {
         G.map.drawLine(this.getPointsArrayList(),
                        Constants.TRACK_WIDTH + Constants.TRACK_BORDER_WIDTH,
                        Color.BLACK);
      }
      // Then draw the fill color
      G.map.drawLine(this.getPointsArrayList(),
                     Constants.TRACK_WIDTH,
                     track_color);
      
      // draw points
      if (points.size() > 1) {
         this.drawTrackPoint(startpoint, Constants.TRACK_START_COLOR);
      }
      if(!this.recording){
         this.drawTrackPoint(endpoint, Constants.TRACK_END_COLOR);
         // draw start/end labels if track has been saved.
         G.map.drawLabel(
            G.map.xform_x_map2cv(startpoint.x),
            G.map.xform_y_map2cv(startpoint.y) - 10,
            G.app_context.getResources().getString(R.string.route_start_label),
            Constants.ROUTE_LABEL_SIZE, Constants.ROUTE_LABEL_STROKE_WIDTH);
         G.map.drawLabel(
               G.map.xform_x_map2cv(endpoint.x),
               G.map.xform_y_map2cv(endpoint.y) - 10,
            G.app_context.getResources().getString(R.string.route_end_label),
            Constants.ROUTE_LABEL_SIZE, Constants.ROUTE_LABEL_STROKE_WIDTH);
      }
      
   }//draw
   
   /**
    * Draws a track point
    * @param point the location of the circle
    * @param color the inside color of the circle
    */
   public void drawTrackPoint(TrackPoint point, int color) {
      int x = G.map.xform_x_map2cv(point.x);
      int y = G.map.xform_y_map2cv(point.y);
      Paint p = new Paint();
      p.setColor(Constants.TRACK_POINT_BORDER_COLOR);
      G.map.map_canvas.drawCircle(x, y, Constants.TRACK_POINT_SHADOW_RADIUS, p);
      p.setColor(color);
      G.map.map_canvas.drawCircle(x, y, Constants.TRACK_POINT_RADIUS, p);
   }
   
   /**
    * Returns true if the given track has the same server id and version as
    * this track.
    */
   public boolean equals(Track track) {
      return (track.stack_id == this.stack_id
              && track.version == this.version);
   }
   
   @Override
   /**
    * Populates this Track from an XML
    * @param root
    */
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      NamedNodeMap atts = root.getAttributes();
      // Initialize general track information
      this.owner = XmlUtils.getString(atts, "crby", null);
      this.length = XmlUtils.getInt(atts, "length", 0);
      
      // Initialize track points
      this.points = new ArrayList<TrackPoint>();
      TrackPoint tp;
      NodeList child_nodes = root.getChildNodes();
      // Initialize track points
      for (int i = 0; i < child_nodes.getLength(); i++) {
         if (child_nodes.item(i).getNodeName().equals("tpoint")) {
            tp = new TrackPoint(child_nodes.item(i));
            this.add(tp);
         }
      }
      if (this.points.size() > 0) {
         this.date = this.points.get(this.points.size() -1).getTimestamp();
      } else {
         SimpleDateFormat sdf =
            new SimpleDateFormat(Constants.SERVER_DATE_FORMAT);
         Date d1;
         Date d2;
         try {
            d1 = sdf.parse(XmlUtils.getString(atts, "created", ""));
            d2 = sdf.parse(XmlUtils.getString(atts, "started", ""));
            this.date = d1;
            this.duration = d1.getTime() - d2.getTime();
         } catch (DOMException e) {
            this.date = null;
            this.duration = null;
            e.printStackTrace();
         } catch (ParseException e) {
            this.date = null;
            this.duration = null;
            e.printStackTrace();
         }
      }
   }

   @Override
   /**
    * Returns an XML String representing this Track.
    */
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "track");

      if (this.hasOwner()) {
         root.setAttribute("owner_name", this.owner);
      }
      Element point;
      for (TrackPoint tp : this.points) {
         point = document.createElement("track_point");
         point.setAttribute("x", Double.toString(tp.x));
         point.setAttribute("y", Double.toString(tp.y));
         point.setAttribute("timestamp",
                            Long.toString(tp.getTimestamp().getTime()));
         if (tp.temperature != null) {
            point.setAttribute("temperature", Float.toString(tp.temperature));
         }
         if (tp.orientation != null) {
            point.setAttribute("orientation", Float.toString(tp.orientation));
         }
         if (tp.altitude != null) {
            point.setAttribute("altitude", Double.toString(tp.altitude));
         }
         if (tp.bearing != null) {
            point.setAttribute("bearing", Float.toString(tp.bearing));
         }
         if (tp.speed != null) {
            point.setAttribute("speed", Float.toString(tp.speed));
         }
         root.appendChild(point);
      }
      return document;
   }

   /**
    * Returns true if this track has an owner.
    */
   public boolean hasOwner() {
      return this.owner != null && !this.owner.equals("");
   }
   
   /**
    * Returns false, since tracks have do be discarded manually.
    */
   @Override
   public boolean isDiscardable() {
      return false;
   }

   /**
    * Returns the name associated with this item.
    * @return name
    */
   @Override
   public String toString(){
      return name;
   }//toString

   /**
    * This method is not used for this class, but is required when implementing
    * the Parcelable interface.
    */
   @Override
   public int describeContents() {
      return 0;
   }

   @Override
   /**
    * Writes this track to a parcel.
    */
   public void writeToParcel(Parcel out, int flags) {
      out.writeInt(this.stack_id);
      out.writeString(this.name);
      out.writeString(this.owner);
      out.writeLong(this.date.getTime());
      out.writeLong(this.duration);
      out.writeDouble(this.length);
      out.writeInt(this.recording ? 1 : 0);
      out.writeInt(this.trial_num);
   }
   
   /**
    * A Creator object that generates instances of Parcelable Tracks.
    */
   public static final Parcelable.Creator<Track> CREATOR =
         new Parcelable.Creator<Track>() {
      /**
       * Creates new instance of Parcelable Track using given Parcel
       * @param in Parcel containing Track
       */
      @Override
      public Track createFromParcel(Parcel in) {
         return new Track(in);
      }

      /**
       * Creates a new array of Tracks
       */
      @Override
      public Track[] newArray(int size) {
         return new Track[size];
      }
   };
   
}//Track
