/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;
import java.util.Collections;

import junit.framework.Assert;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.net.LinkShortener;
import org.cyclopath.android.net.LinkShortenerCallback;
import org.cyclopath.android.util.Permission;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.Visibility;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import android.graphics.Color;
import android.os.Bundle;
import android.os.Message;

/**
 * Class that represents a route object.
 * @author Fernando Torre
 * @author Phil Brown
 * @author Yanjie Liu
 */
public class Route extends Geofeature implements LinkShortenerCallback {
   
   // *** Static variables
   
   /** Counter used for naming generic routes */
   protected static int rt_counter = 0;
   
   // *** Instance variables
   
   /** Owner of the route. */
   public String owner;
   /** Server hashcode of this route*/
   public String link_hash_id;
   /** Shortened url for sharing this route*/
   public String shortened_URL;
   /** Starting address */
   public String from_canaddr;
   /** Destination address */
   public String to_canaddr;
   /** Length of route in meters? TODO: Verify if it is fact in meters */
   public float length;
   /** steps (byways) in a route */
   public ArrayList<RouteStep> steps;
   /** route directions */
   public ArrayList<DirectionStep> directions;
   /** direction currently selected in DirectionsActivity */
   public int selected_direction = -1;
   /** visibility of this route */
   protected int vis_;
   /** permissions for this route */
   protected int perms_;
   /** whether the route matches the session (its value is immutable) */
   protected boolean session_match;

   /**
    * Constructor
    * @param root Document object containing route data
    */
   public Route(Node root) {
      super(root);

      this.owner = G.user.getName();
      this.link_hash_id = null;
      this.setPermission(Permission.private_);
      this.setVisibility(Visibility.noone);
      this.session_match = true;
      this.length = 0;

      if (root != null) {
         this.gmlConsume(root);
      } else {
         this.gfl_id = 105;
      }
      this.z = (int) Constants.ROUTE_LAYER;
   }//Route
   
   // *** Setters and Getters

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.ROUTE;
   }

   /**
    * Returns the last direction in the list of directions.
    */
   protected DirectionStep getLastDir() {
      if (this.directions.size() > 0)
         return this.directions.get(this.directions.size() - 1);
      else
         return null;
   }//getLastDir

   /**
    * Returns the permissions for this route.
    */
   public int getPermission() {
      return this.perms_;
   }

   /**
    * Returns the visibility for this route.
    */
   public int getVisibility() {
      return this.vis_;
   }

   /**
    * Sets the permissions for this route.
    * @param p permission code as given by Permission.java
    */
   public void setPermission(int p) {
      Assert.assertTrue(p == Permission.public_
                        || p == Permission.shared 
                        || p == Permission.private_);
      this.perms_ = p;
   }

   /**
    * Sets the visibility for this route.
    * @param p visibility code as given by Visibility.java
    */
   public void setVisibility(int v) {
      Assert.assertTrue(v == Visibility.all
                        || v == Visibility.owner 
                        || v == Visibility.noone);
      this.vis_ = v;
   }
   
   // *** Other methods

   /**
    *  Builds the direction steps array.
    */
   protected void buildDirections() {
      DirectionStep dir_step;
      int classify;
      double rel_angle;
      
      PointD start_v = null;
      PointD end_v = null;
      Geopoint landmark = null;
   
      this.directions = new ArrayList<DirectionStep>();
      for (RouteStep step : this.steps) {
         // Compute the direction vector for the start of the current 
         // step
         start_v = this.compute_step_dir(step, false);
         classify = G.angle_class_idx(start_v);
         
         // We consider a step to be the same if it has the same name,
         // AND (its going in the same direction OR its relative angle
         // is too large)
         if (this.getLastDir() == null) {
            // The very first step, so it has a special relative class
            dir_step = new DirectionStep(Constants.BEARINGS.length - 2,
                                          classify,
                                          step.step_length,
                                          step.byway_name,
                                          null,
                                          this.xys.get(step.start_index),
                                          null, 0);
            this.directions.add(dir_step);
         } else {
            rel_angle = G.ang_rel(end_v, start_v);
            String rel_direction =
                  Constants.BEARINGS[G.angle_class_id(rel_angle)]
                           .getRelativeDirection();
            if ((!step.byway_name.equalsIgnoreCase(this.getLastDir().name)
                 || (step.byway_name.equals("")
                     && step.gfl_id != this.getLastDir().type))
                 || (Math.abs(rel_angle - 90) > Constants.DIR_MERGE_ANGLE
                     && step.step_length > Constants.DIR_MERGE_LENGTH)
                 || rel_direction.equals(
                       G.app_context.getString(R.string.bearing_backward))) {
               // We need a new step, use the precomputed rel_angle,
               // since it's meaningful
               
               double landmark_angle = 0;
               // get the relative angle between the direction we were
               // traveling and the landmark
               if (landmark != null) {
                  PointD end = this.xys.get(step.start_index);
                  landmark_angle = G.ang_rel(end_v,
                        new PointD((landmark.xys.get(0).x - end.x),
                                   (landmark.xys.get(0).y - end.y)));
               }
               
               dir_step = new DirectionStep(G.angle_class_id(rel_angle),
                                            classify, step.step_length, 
                                            step.byway_name, 
                                            this.getLastDir(),
                                            this.xys.get(step.start_index),
                                            landmark, landmark_angle);
               this.directions.add(dir_step);
            } else {
               this.getLastDir().rel_distance += step.step_length;
            }
         }
         
         this.getLastDir().type = step.gfl_id;
         
         // Compute the direction vector for the end of the current 
         // step (used potentially for the next step to get the
         // relative turn angle)
         end_v = this.compute_step_dir(step, true);

         if (!step.landmarks.isEmpty()) {
            landmark = step.landmarks.get(0);
            if (step.landmarks.size() > 1) {
               PointD end = this.xys.get(step.start_index);
               double dist = G.distance(landmark.xys.get(0), end);
               for (int i = 1; i < step.landmarks.size(); i++) {
                  PointD coords = step.landmarks.get(i).xys.get(0);
                  double new_dist = G.distance(coords, end);
                  if (new_dist < dist) {
                     dist = new_dist;
                     landmark = step.landmarks.get(i);
                  }
               }
            }
         } else {
            landmark = null;
         }
      }
      dir_step = new DirectionStep(Constants.BEARINGS.length - 1, 
                                   Constants.BEARINGS.length - 1,
                                   0,
                                   this.to_canaddr, 
                                   this.getLastDir(),
                                   this.xys.get(this.xys.size() - 1),
                                   null, 0);
      this.directions.add(dir_step);
   }//build_directions

   /**
    * Computes the direction vector for a route step
    * @param step
    * @param leaving_step
    */
   protected PointD compute_step_dir(RouteStep step, 
                                      boolean leaving_step) {
      boolean start_at_zero = !leaving_step;
      
      int i = (start_at_zero ? step.start_index : step.end_index - 1);
      int dir = (start_at_zero ? 1 : -1);
      int mul = (leaving_step ? 1 : -1);
      
      double vec_len = 0;
      PointD result = new PointD(this.xys.get(i).x, this.xys.get(i).y);
   
      while (vec_len < Constants.ROUTE_STEP_DIR_LENGTH) {
         vec_len +=
            G.distance((this.xys.get(i).x - this.xys.get(i + dir).x) * mul,
                       (this.xys.get(i).y - this.xys.get(i + dir).y) * mul,
                       0, 0);
         i += dir;
         if (step.isEndpoint(i))
            break;
      }
      result.x = (result.x - this.xys.get(i).x) * mul;
      result.y = (result.y - this.xys.get(i).y) * mul;
   
      return result;
   }//compute_step_dir

   /**
    * Draws the route.
    */
   @Override
   public void draw() {
   
      int startx = G.map.xform_x_map2cv(this.xys.get(0).x);
      int starty = G.map.xform_y_map2cv(this.xys.get(0).y);
      int endx = G.map.xform_x_map2cv(this.xys.get(this.xys.size() - 1).x);
      int endy = G.map.xform_y_map2cv(this.xys.get(this.xys.size() - 1).y);
      
      // draw route lines (border first)
      // NOTE1: I wonder if there is an easy way to draw the border and the
      // line at the same time... Paths don't work for that.
      // NOTE2: The width fetched into Conf.draw_param makes the route look too
      // fat on a phone. Therefore, I defined new widths in the client.
      G.map.drawLine(this.xys,
                     Constants.ROUTE_BORDER_WIDTH + Constants.ROUTE_WIDTH,
                     Constants.ROUTE_BORDER_COLOR);
      G.map.drawLine(this.xys,
                     Constants.ROUTE_WIDTH,
                     Constants.ROUTE_COLOR);
      // Draw new and modified blocks
      for (RouteStep rs : this.steps) {
         ArrayList<PointD> rs_xys = new ArrayList<PointD>();
         for (int i = rs.start_index; i < rs.end_index; i++) {
            rs_xys.add(this.xys.get(i));
         }
         if (rs.byway_segment_id <= 0 && rs.split_from_id <= 0) {
            // Draw new block
            G.map.drawLine(rs_xys,
                     Constants.ROUTE_WIDTH,
                     Color.BLUE);
         } else if ((rs.byway_segment_id <= 0)
                    || rs.start_node_id < 0
                    || rs.end_node_id < 0) {
            // Draw modified block
            G.map.drawLine(rs_xys,
                     Constants.ROUTE_WIDTH,
                     Color.GRAY);
         }
      }
      
      // draw start/end markers
      G.map.drawCircle(startx, starty,
                       Constants.ROUTE_CIRCLE_RADIUS,
                       Constants.ROUTE_CIRCLE_STROKE_WIDTH,
                       Constants.ROUTE_START_COLOR,
                       Color.BLACK);
      G.map.drawCircle(endx, endy,
                       Constants.ROUTE_CIRCLE_RADIUS,
                       Constants.ROUTE_CIRCLE_STROKE_WIDTH,
                       Constants.ROUTE_END_COLOR,
                       Color.BLACK);
   
      // draw start/end labels
      G.map.drawLabel(
            startx, starty - 10,
            G.app_context.getResources().getString(R.string.route_start_label),
            Constants.ROUTE_LABEL_SIZE, Constants.ROUTE_LABEL_STROKE_WIDTH);
      G.map.drawLabel(
            endx, endy - 10,
            G.app_context.getResources().getString(R.string.route_end_label),
            Constants.ROUTE_LABEL_SIZE, Constants.ROUTE_LABEL_STROKE_WIDTH);
      
      // draw direction arrows
      if(G.zoom_level >= Constants.DIRECTION_ARROWS_ZOOM_LEVEL) {
         G.map.drawDirections(this.xys,
                              this.directions,
                              this.selected_direction);
      }

      // draw direction circle if too far
      if (this.selected_direction >= 0
          && G.zoom_level < Constants.DIRECTION_ARROWS_ZOOM_LEVEL) {
         int x = G.map.xform_x_map2cv(
               this.directions.get(this.selected_direction).start_point.x);
         int y = G.map.xform_y_map2cv(
               this.directions.get(this.selected_direction).start_point.y);
         G.map.drawCircle(x, y,
                          Constants.ROUTE_CIRCLE_RADIUS,
                          Constants.ROUTE_CIRCLE_STROKE_WIDTH,
                          Constants.ROUTE_DIRECTION_COLOR,
                          Color.BLACK);
      }
   }//draw
   
   @Override
   /**
    * Populates this Route from an XML
    * @param root
    */
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      RouteStep step;
      RouteStep prev_step = null;
      ArrayList<PointD> step_xys;
      NamedNodeMap atts = root.getAttributes();
      // Initialize general route information
      this.owner = XmlUtils.getString(atts, "created_by", this.owner);
      this.gfl_id = XmlUtils.getInt(atts, "gflid", 105);
      this.link_hash_id =
         XmlUtils.getString(atts, "stlh", this.link_hash_id);
      this.name = XmlUtils.getString(atts, "name",
            G.app_context.getResources().getString(
                  R.string.generic_route_name) + " " + (++rt_counter));
      this.from_canaddr = XmlUtils.getString(atts, "beg_addr",
            G.app_context.getResources().getString(
                  R.string.route_waypoint_map_name));
      this.to_canaddr = XmlUtils.getString(atts, "fin_addr",
            G.app_context.getResources().getString(
                  R.string.route_waypoint_map_name));
      this.length = XmlUtils.getFloat(atts, "rsn_len", 0f);
            
      NodeList child_nodes = root.getChildNodes();
            
      this.steps = new ArrayList<RouteStep>();
      float alt_len = 0;
      
      // Initialize route steps
      for (int i = 0; i < child_nodes.getLength(); i++) {
         // filter out waypoints from the child node list
         if (child_nodes.item(i).getNodeName().equals("step")) {
            step = new RouteStep(child_nodes.item(i));
            this.steps.add(step);

            // update coordinates for the route
            step_xys = G.coordsStringToPoint(child_nodes.item(i)
                                             .getFirstChild()
                                             .getNodeValue());
            step.setLength(step_xys);
            alt_len += step.step_length;

            step.start_index = this.xys.size();
            if (!step.forward) {
                Collections.reverse(step_xys);
            }

            for (int n = 0; n < step_xys.size(); n++) {
                // don't push 1st coord of intermediate steps
                if (n == 0 && prev_step != null) {
                    step.start_index--;
                    continue;
                }
                this.xys.add(step_xys.get(n));
            }
            step.end_index = this.xys.size();
            prev_step = step;
         }
      }

      // build the directions
      if (this.steps.size() > 0) {
         if (this.length == 0) {
            this.length = alt_len;
         }
         this.buildDirections();
         this.calculateBbox();
      }
   }

   @Override
   /**
    * Returns an XML String representing this Route.
    */
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      
      document.renameNode(root, null, "route");

      if (this.owner != null) {
         root.setAttribute("owner_name", this.owner);
      }
      
      if (this.link_hash_id != null){
         root.setAttribute("stlh", this.link_hash_id);
      }

      root.setAttribute("beg_addr", this.from_canaddr);
      root.setAttribute("fin_addr", this.to_canaddr);
      Element step;
      for (RouteStep r : this.steps) {
         step = document.createElement("step");
         step.setAttribute("step_name", r.byway_name);
         step.setAttribute("byway_id", Integer.toString(r.byway_segment_id));
         step.setAttribute("byway_version",
                           Integer.toString(r.byway_segment_version));
         step.setAttribute("step_name", r.byway_name);
         step.setAttribute("forward", (r.forward == true ? "1" : "0"));
         root.appendChild(step);
      }
      return document;
   }

   /**
    * Callback for the link shortener
    * This method creates the intent for sharing the route, attaches the 
    * message subject, body, and a graphic
    */
   @Override
   public void handleLinkShortenerComplete(String newURL) {
      if (G.base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_SHOW_SHARE_ROUTE_CHOOSER;
         Bundle b = new Bundle();
         b.putString(Constants.ROUTE_URL, newURL);
         msg.setData(b);
         msg.setTarget(G.base_handler);
         msg.sendToTarget();
      }
   }//handleLinkShortener

   /**
    * Returns true if the route has already generated a shortened URL.
    */
   public boolean hasShortenedURL() {
      if (this.shortened_URL == null) {
         return false;
      }
      return true;
   }//hasShortenedURL

   /**
    * Routes are not discardable by default.
    */
   @Override
   public boolean isDiscardable() {
      return false;
   }//isDiscardable
   
   /** Return whether or not this route is owned by the current user.
    * A public route is owned by everyone. A private or shared route is
    * owned by the user who created it.  
    * 
    * Additionally, when the route was first created in this session by 
    * an anonymous user, any user in the client is considered to own 
    * the route. This special case matches based on the session id of
    * the client.  Users in other clients cannot own the anonymously
    * created route in this client.
    *
    * This matches the logic within route.is_owned in the pyserver.
    * FIXME
    */
   public boolean isOwned() {
      return this.isPublic() || (G.user.isLoggedIn()
                                && G.user.getName() == this.owner) 
             || (this.getVisibility() == Visibility.noone && this.session_match 
                 && this.owner == null);
   }

   /**
    * Whether this route is private
    */
   public boolean isPrivate() {
      return this.getPermission() == Permission.private_;
   }

   /**
    * Whether this route is public
    */
   public boolean isPublic() {
      return this.getPermission() == Permission.public_;
   }

   /**
    * Whether this route is shared
    */
   public boolean isShared() {
      return this.getPermission() == Permission.shared;
   }

   /**
    * Shares a link to a route via email or other social applications.
    */
   public void shareRoute() {
      if (G.active_route.link_hash_id != null && 
          !G.active_route.link_hash_id.equals("")){
         String link_url = Constants.SERVER_URL 
                           + "#route_shared?id=" 
                           + G.active_route.link_hash_id;
         if (this.hasShortenedURL()) {
        	   handleLinkShortenerComplete(this.shortened_URL);
         }
         else {
            new LinkShortener(link_url, this).fetch();
         }
      }
   }//shareRoute
}//Route