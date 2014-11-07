/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.conf;

import java.util.HashMap;

import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import android.util.Log;
import android.util.SparseArray;

/**
 * This class imports and stores some configuration variables from the server.
 * @author Fernando Torre
 */
public class Conf {
   
   /** True if the config variables have been fetched already */
   public static boolean config_fetched = false;
   
   /** dictionary of byway types */
   //public static HashMap<String,String> byway_type;
   /** dictionary of byway draw classes */
   //public static HashMap<String,String> byway_draw_class_map;
   /** dictionary of point types */
   //public static HashMap<String,String> point_type;
   /** dictionary of point draw classes */
   //public static HashMap<String,String> point_draw_class_map;
   /** dictionary of draw params */
   public static SparseArray<DrawParam> draw_param;
   /** dictionary of layer names (geofeature layer ids are the keys)*/
   public static SparseArray<String> geofeature_layer_by_id;
   /** dictionary of draw class ids (geofeature layer ids are the keys)*/
   public static SparseArray<Integer> draw_class_by_gfl;
   
   /**
    * Imports the XML config information retrieved from the server.
    * @param data Node with config information.
    */
   public static void importXml(Document data) {
      importXMLDrawParam(
            data.getElementsByTagName("draw_param_joined").item(0));
      importXMLGeofeatureLayer(
            data.getElementsByTagName("geofeature_layer").item(0));

      if (Constants.DEBUG) {
         Log.d("debug", "Imported XML config data.");
      }
      config_fetched = true;
   }
   
   /**
    * Imports drawing parameters.
    * @param data
    */
   public static void importXMLDrawParam(Node data) {
      
      draw_param = new SparseArray<DrawParam>();
      
      NodeList children = data.getChildNodes();
      for (int j = 0; j < children.getLength(); j++) {
         Node draw_param_node = children.item(j);
         if (!draw_param_node.getNodeName().equals("row"))
            continue;
         NamedNodeMap map = draw_param_node.getAttributes();
         Integer dc_id =
            Integer.valueOf(map.getNamedItem("draw_class_id").getNodeValue());
         if (draw_param.get(dc_id) == null) {
            draw_param.put(dc_id, new DrawParam());
         }
         DrawParam param = draw_param.get(dc_id);
         Node zoom_node = map.getNamedItem("zoom");
         // color
         Node value = map.getNamedItem("color");
         // We add 0xFF000000 because Android uses two extra hex digits
         // to specify the alpha value of the color. Adding this value
         // ensures that we get a solid color.
         param.color = (value == null) ? param.color :
                       ((Integer.parseInt(value.getNodeValue())
                         | 0xFF000000));
         
         if (zoom_node != null) {
            Integer zoom = Integer.valueOf(zoom_node.getNodeValue());
            param.zoom_params.put(zoom, new ZoomParam());
            
            // width
            value = map.getNamedItem("width");
            if (value != null) {
               param.zoom_params.get(zoom).width =
                  Float.parseFloat(value.getNodeValue());
            }
            // label?
            value = map.getNamedItem("label");
            if (value != null) {
               param.zoom_params.get(zoom).label =
                  value.getNodeValue().equals("1");
            }
            // label size?
            value = map.getNamedItem("label_size");
            if (value != null) {
               param.zoom_params.get(zoom).label_size =
                  Float.parseFloat(value.getNodeValue());
            }
         }
      }
   }

   /**
    * Imports geofeature layer information.
    * @param data
    */
   public static void importXMLGeofeatureLayer(Node data) {
      
      geofeature_layer_by_id = new SparseArray<String>();
      draw_class_by_gfl = new SparseArray<Integer>();
      
      NodeList children = data.getChildNodes();
      for (int j = 0; j < children.getLength(); j++) {
         Node draw_param_node = children.item(j);
         if (!draw_param_node.getNodeName().equals("row"))
            continue;
         NamedNodeMap map = draw_param_node.getAttributes();
         Integer gfl_id =
               Integer.valueOf(map.getNamedItem("gfl_id").getNodeValue());
         
         geofeature_layer_by_id.put(
               gfl_id, map.getNamedItem("layer_name").getNodeValue());
         draw_class_by_gfl.put(gfl_id,
             Integer.valueOf(map.getNamedItem("draw_class_viewer")
                                .getNodeValue()));
      }
      
   }
   
   /**
    * Helper function that creates a dictionary from a node given the key and
    * value field names.
    * @param data Node with dictionary information
    * @param key field name for the key
    * @param value field name for the value
    * @return HashMap containing dictionary generated form node.
    */
   public static HashMap<String,String> map_from_node(Node data,
                                                      String key,
                                                      String value) {
      HashMap<String,String> map = new HashMap<String,String>();
      NodeList list = data.getChildNodes();
      for (int i = 0; i < list.getLength(); i++) {
         Node n = list.item(i);
         if (n.getNodeType() == Node.ELEMENT_NODE) {
            NamedNodeMap atts = n.getAttributes();
            if (atts.getNamedItem(key) != null
                  && atts.getNamedItem(value) != null) {
               map.put(atts.getNamedItem(key).getNodeValue(),
                     atts.getNamedItem(value).getNodeValue());
            }
         }
      }
      return map;
   }
}
