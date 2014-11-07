/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

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

   public interface A_Star_Item
   {
      function neighbors(parent:A_Star_Item, array_out:Array) :void;
      function cost(neighbor:A_Star_Item) :Number;
      function cost_estimate(goal:A_Star_Item) :Number;
   }

}

