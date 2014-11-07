/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.utils.Dictionary;

   import utils.misc.A_Star_Item;

   // The A* algorithm used in this code is modified from the C++ code
   // available at www.heys-jones.com/astar.html, copyright Justin Heyes-Jones
   //
   // Justin's license agreement:
   // ************************************
   // Permission is given by the author to freely redistribute and include
   // this code in any program as long as this credit is given where due.
   //
   // COVERED CODE IS PROVIDED UNDER THIS LICENSE ON AN "AS IS" BASIS,
   // WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
   // INCLUDING, WITHOUT LIMITATION, WARRANTIES THAT THE COVERED CODE
   // IS FREE OF DEFECTS, MERCHANTABLE, FIT FOR A PARTICULAR PURPOSE
   // OR NON-INFRINGING. THE ENTIRE RISK AS TO THE QUALITY AND
   // PERFORMANCE OF THE COVERED CODE IS WITH YOU. SHOULD ANY COVERED
   // CODE PROVE DEFECTIVE IN ANY RESPECT, YOU (NOT THE INITIAL
   // DEVELOPER OR ANY OTHER CONTRIBUTOR) ASSUME THE COST OF ANY
   // NECESSARY SERVICING, REPAIR OR CORRECTION. THIS DISCLAIMER OF
   // WARRANTY CONSTITUTES AN ESSENTIAL PART OF THIS LICENSE. NO USE
   // OF ANY COVERED CODE IS AUTHORIZED HEREUNDER EXCEPT UNDER
   // THIS DISCLAIMER.
   //
   // Use at your own risk!
   // ***********************************

   public class A_Star
   {

      // No instance methods are needed, the search can be done statically

      public static function search(start:A_Star_Item, goal:A_Star_Item) :Array
      {
         var all_nodes:Dictionary = new Dictionary(); // <item -> node>
         var open_set:Dictionary = new Dictionary(); // ""
         var closed_set:Dictionary = new Dictionary(); // ""
         var open_list:Array = new Array();

         var start_node:Node = new Node();
         var cur_node:Node;
         var successors:Array = new Array(); // neighbor data items
         var nNodes:Array = new Array(); // neighbor nodes wrapping successors
         var t:A_Star_Item;
         var n:Node;
         var newg:Number;

         var path:Array;

         start_node.data = start;
         start_node.g = 0;
         start_node.h = start.cost_estimate(goal);
         all_nodes[start] = start_node;

         open_set[start_node.data] = start_node;
         open_list.push(start_node);
         maintain_open_list(open_list);

         // loops forever, end conditions will break us out of the loop
         while (true) {
            if (open_list.length == 0) {
               return null; // FAILED SEARCH!
            }

            cur_node = open_list.pop();
            delete open_set[cur_node.data];

            // we've reached the goal
            if (cur_node.data === goal) {
               path = new Array();

               do {
                  path.push(cur_node.data);
                  cur_node = cur_node.parent;
               } while (cur_node !== null); // null means we're at the start

               path.reverse();

               return path; // SUCCESSFUL SEARCH!
            }

            successors = new Array();
            nNodes = new Array();
            if (cur_node.parent === null) {
               cur_node.data.neighbors(null, successors);
            }
            else {
               cur_node.data.neighbors(cur_node.parent.data, successors);
            }
            // build nNodes
            for each (t in successors) {
               if (t in all_nodes) { // old node
                  nNodes.push(all_nodes[t]);
               }
               else { // new node
                  n = new Node();
                  n.data = t;
                  //all_nodes[t] = n;
                  nNodes.push(n);
               }
            }

            for each (n in nNodes) {
               newg = cur_node.g + cur_node.data.cost(n.data); // new g value

               // Check if its on the open list
               if (n.data in open_set && open_set[n.data].g <= newg) {
                  // the current node in open is better than this one, so
                  // ignore this node
                  continue;
               }

               if (n.data in closed_set && closed_set[n.data].g <= newg) {
                  // the current node is closed is better than this one,
                  // so ignore this node
                  continue;
               }

               // This node is the best with this data so keep it
               n.parent = cur_node;
               n.g = newg;
               n.h = n.data.cost_estimate(goal);
               all_nodes[n.data] = n;

               // Remove n from closed if it was on it
               if (n.data in closed_set) {
                  delete closed_set[n.data];
               }

               // Add it to the open list
               open_list.push(n);
               open_set[n.data] = n;
            }

            // we've expanded cur_node, so add it to the closed set
            closed_set[cur_node.data] = cur_node;

            // sort the open set for the next iteration
            maintain_open_list(open_list);
         }

         m4_ASSERT(false); // Shouldn't reach this point, it should fail in
         // the loop or complete the search.
         return null;
      }

      protected static function maintain_open_list(list:Array) :void
      {
         list.sortOn('f', Array.NUMERIC | Array.DESCENDING);
      }

   }
}

import utils.misc.A_Star_Item;

class Node {

   public var data:A_Star_Item;// User data associated with this node
   public var h:Number; // estimate from this node to the goal
   public var g:Number; // cost from start to here
   public var parent:Node;// Parent node in the path, null means it's the start

   // Assumes h and g are properly set.
   public function get f() :Number
   {
      return h + g;
   }

}

