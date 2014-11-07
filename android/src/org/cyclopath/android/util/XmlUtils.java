/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.util.Properties;

import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerConfigurationException;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.w3c.dom.DOMException;
import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;

/**
 * This class holds static functions useful for handling XML data.
 * @author Fernando Torre
 */
public class XmlUtils {

   /**
    * Transforms an XML Document into a String
    * @param document
    * @return
    */
   public static String documentToString(Document document) {
      TransformerFactory factory = TransformerFactory.newInstance();
      Transformer transformer;
      try {
         transformer = factory.newTransformer();
         Properties outFormat = new Properties();
         outFormat.setProperty(OutputKeys.METHOD, "xml");
         outFormat.setProperty(OutputKeys.OMIT_XML_DECLARATION, "yes");
         transformer.setOutputProperties(outFormat);
         DOMSource domSource = 
               new DOMSource(document.getDocumentElement());
         OutputStream output = new ByteArrayOutputStream();
         StreamResult result = new StreamResult(output);
         transformer.transform(domSource, result);
         return output.toString();
      } catch (TransformerConfigurationException e) {
         e.printStackTrace();
         return null;
      } catch (TransformerException e) {
         e.printStackTrace();
         return null;
      }
   }

   /**
    * Retrieves a Double from a node attribute, if the node exists.
    * @param atts nodemap of attributes
    * @param name name of attribute
    * @param default_int default value in case the attribute does not exist
    */
   public static Double getDouble(NamedNodeMap atts, String name,
                                  Double default_double) {
      return (atts.getNamedItem(name) == null) ? default_double :
         Double.valueOf(atts.getNamedItem(name).getNodeValue());
   }

   /**
    * Retrieves a Float from a node attribute, if the node exists.
    * @param atts nodemap of attributes
    * @param name name of attribute
    * @param default_int default value in case the attribute does not exist
    */
   public static Float getFloat(NamedNodeMap atts, String name,
                                Float default_float) {
      return (atts.getNamedItem(name) == null) ? default_float :
         Float.valueOf(atts.getNamedItem(name).getNodeValue());
   }

   /**
    * Retrieves an int from a node attribute, if the node exists.
    * @param atts nodemap of attributes
    * @param name name of attribute
    * @param default_int default value in case the attribute does not exist
    */
   public static int getInt(NamedNodeMap atts, String name, int default_int) {
      return (atts.getNamedItem(name) == null) ? default_int :
         Integer.parseInt(atts.getNamedItem(name).getNodeValue());
   }

   /**
    * Retrieves a String from a node attribute, if the node exists.
    * @param atts nodemap of attributes
    * @param name name of attribute
    * @param default_int default value in case the attribute does not exist
    */
   public static String getString(NamedNodeMap atts, String name,
                                  String default_str) {
      try {
         return (atts.getNamedItem(name) == null) ? default_str :
            URLDecoder.decode(atts.getNamedItem(name).getNodeValue(),"UTF-8");
      } catch (UnsupportedEncodingException e) {
         // TODO Auto-generated catch block
         e.printStackTrace();
      } catch (DOMException e) {
         e.printStackTrace();
      }
      return default_str;
   }
}
