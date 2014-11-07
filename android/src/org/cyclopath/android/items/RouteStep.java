/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;
import java.util.List;

import org.cyclopath.android.G;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * Class that represents a step in a route.
 * @author Fernando Torre
 */
public class RouteStep {
   
   /** type of byway */
   public int gfl_id;
   /** name of byway */
   public String byway_name;
   /** id of byway */
   public int byway_segment_id;
   /** version of byway */
   public int byway_segment_version;

   /** whether we are traversing the coordinates forward or in reverse */
   public boolean forward;
   /** id of the start node */
   public int start_node_id;
   /** elevation at the start node */
   public float start_node_elevation;
   /** id of the end node */
   public int end_node_id;
   /** elevation at the end node */
   public float end_node_elevation;
   /** distance for this step */
   public float step_length;
   /** rating for this byway */
   public float rating;
   /** whether this byway is tagged with tags that are given a bonus by the
    * user */
   public boolean bonus_tagged;
   /** whether this byway is tagged with tags that are given a penalty by the
    * user */
   public boolean penalty_tagged;
   /** For rides, whether a new block was split from an existing block */
   public int split_from_id;

   /**
    * start index used to access this RouteStep's xs and ys from its
    * owning Route. (inclusive)
    */
   public int start_index;
   /**
    * end index used to access this RouteStep's xs and ys from its
    * owning Route. (exclusive)
    */
   public int end_index;
   /** possible landmarks sent from the server */
   public ArrayList<Geopoint> landmarks;

   /**
    * Constructor
    * @param data Node with route step information
    */
   public RouteStep(Node data) {
      if (data != null) {
         NamedNodeMap atts = data.getAttributes();
         this.byway_name = XmlUtils.getString(atts, "step_name", "");
         if (this.byway_name.equals("None")) {
            this.byway_name = "";
         }
         this.byway_segment_id = XmlUtils.getInt(atts, "byway_stack_id", 0);
         this.byway_segment_version =
            XmlUtils.getInt(atts, "byway_version", 0);
         this.gfl_id = XmlUtils.getInt(atts, "gflid", 0);
         this.forward = XmlUtils.getString(atts, "forward", "").equals("1");
         this.start_node_id = XmlUtils.getInt(atts, "nid1", 0);
         this.start_node_elevation =
            XmlUtils.getFloat(atts, "nel1", -1f);
         this.end_node_id = XmlUtils.getInt(atts, "nid2", 0);
         this.end_node_elevation =
            XmlUtils.getFloat(atts, "nel2", -1f);
         this.rating = XmlUtils.getFloat(atts, "rating", -1f);
         this.bonus_tagged =
            XmlUtils.getString(atts, "bonus_tagged", "").equals("1");
         this.penalty_tagged =
            XmlUtils.getString(atts, "penalty_tagged", "").equals("1");
         this.split_from_id = XmlUtils.getInt(atts, "split_from_stack_id", -1);
         
         this.landmarks = new ArrayList<Geopoint>();
         NodeList child_nodes = data.getChildNodes();
         for (int i = 0; i < child_nodes.getLength(); i++) {
            if (child_nodes.item(i).getNodeName().equals("waypoint")) {
               this.landmarks.add(new Geopoint(child_nodes.item(i)));
            }
         }
      }
   }
   

   /**
    * Compute and set the step length for this RouteStep from the given list of
    * points in the step's geometry.
    * 
    * @param step_xys
    */
  public void setLength(List<PointD> step_xys) {
     float len = 0;
     for (int i = 1; i < step_xys.size(); i++) {
        len += G.distance(step_xys.get(i - 1).x,
                          step_xys.get(i - 1).y,
                          step_xys.get(i).x,
                          step_xys.get(i).y);
     }
     step_length = len;
     // 93.066, 44.95
  }
   
   /**
    * Returns the inclination for this step.
    * @return inclination
    */
   public float getGrade() {
      float grade_direction = (this.forward) ? 1 : -1;
      float grade = (end_node_elevation - start_node_elevation)
                     * grade_direction / step_length;
      return grade;
   }
   
   /**
    * Returns true if i is an endpoint.
    */
   public boolean isEndpoint(int i) {
      return (i == this.start_index || i == (this.end_index - 1));
   }
}
