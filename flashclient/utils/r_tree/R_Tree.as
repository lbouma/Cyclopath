/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This is an R-Tree implementation written according to Guttman's original
// 1984 paper.
// 
// The same PDF is available from:
// http://www.cse.iitb.ac.in/dbms/Data/Courses/CS631/rTreeGuttman.pdf
// https://dl.acm.org/citation.cfm?id=602266
// http://delivery.acm.org/10.1145/610000/602266/p47-guttman.pdf?ip=134.84.45.239&acc=ACTIVE%20SERVICE&key=C2716FEBFA981EF10E3E3FDDACD4380F38824B3B6824B841&CFID=344427999&CFTOKEN=65145633&__acm__=1372710049_c9e66f15e6935976dbb7137d43b3ff1e
// http://postgis.refractions.net/support/rtree.pdf

// [lb] I recategorized and alphabatized this class in 2013.
//      I'm not sure if this is a GroupLens original or if we
//      copied it from another source. Oh, and I added { }'s
//      to single-line blocks that were without.

package utils.r_tree {

   import flash.geom.Rectangle;
   import flash.display.Graphics;
   import mx.collections.ArrayCollection;

   import utils.geom.Geometry;
   import utils.geom.MOBRable;
   import utils.misc.Logging;

   public class R_Tree {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('R_Tree');

      // *** Instance variables

      // In Cyclopath, the two R_Tree usages use min 2 and max 4.
      // Guttman says m_min <= m_max / 2.
      protected var m_min:int;      // minimum number of items in a node
      protected var m_max:int;      // maximum number of items in a node
      protected var treated:Array;  // ???
      protected var root:_Node;
      protected var items_total:int;

      // Forced reinsertion parameters.
      // WARNING: forced reinsertion is not working ATM??? (Michael?)
      public static var do_force_reinserts:Boolean = false;
      protected var re_nx:Number; // x center of _Node to reinsert from
      protected var re_ny:Number; // y center of _Node to reinsert from

      // *** Constructor

      public function R_Tree(m_min:int, m_max:int)
      {
         m4_TALKY('R_Tree: ctor: m_min:', m_min, '/ m_max:', m_max);
         m4_ASSERT(m_min < m_max);
         m4_ASSERT(m_min >= 2);
         m4_ASSERT(m_min <= m_max / 2);
         this.m_min = m_min;
         this.m_max = m_max;
         this.clear();
      }

      // *** Getters

      //
      public function get depth() :int
      {
         return this.root.height;
      }

      // *** Public functions

      // Clears the R_Tree of all items.
      public function clear() :void
      {
         this.root = new _Node();
         this.treated = new Array();
         this.treated.push(false);
      }

      // Tests for collision against the rectangle
      public function collide(rect:Rectangle) :Boolean
      {
         var res:Boolean;
         var tstart:int = G.now();
         res = this.collide_helper(this.root, rect);
         m4_DEBUG_TIME('=TIME.IT= / collide');
         return res;
      }

      // Draws the R_Tree using the given transform function from the R_Tree's
      // coordinate space to the canvas space;
      public function draw_tree(gr:Graphics, tr:Function) :void
      {
         var tstart:int = G.now();
         this.draw_node(this.root, gr, tr);
         m4_DEBUG_TIME('=TIME.IT= / draw_tree/draw_node');
      }

      // Inserts the given item into the R_Tree. No change is made to the tree
      // if the passed item is null. Duplicate items are allowed.
      public function insert(item:MOBRable) :void
      {
         var tstart:int = G.now();
         var i:int;

         if (do_force_reinserts) {
            for (i = 0; i < this.treated.length; i++) {
               this.treated[i] = false;
            }
         }
         if (item !== null) {
            this.insert_real(item, 0);
            this.items_total++;
         }
         m4_DEBUG_TIME('=TIME.IT= / insert');
         m4_TALKY('insert: items_total:', this.items_total, '/ item', item);
      }

      // Returns all items that intersect with the given rectangle.
      public function query(rect:Rectangle) :Array
      {
         var res:Array;
         var tstart:int = G.now();
         res = this.query_real(this.root, rect);
         m4_DEBUG_TIME('=TIME.IT= / query');
         m4_TALKY('query: result size:', res.length);
         return res;
      }

      // Delete MOBRable item from the R_Tree. No change to the tree occurs
      // if the item isn't present or is null.
      public function remove(item:MOBRable) :void
      {
         var leaf:Array; // A _Node and an int representing the item's index
         var array:ArrayCollection;
         var tstart:int = G.now();
         var prev_total:int = this.items_total;

         if (item !== null) {
            leaf = this.find_leaf(this.root, item);

            if (leaf !== null) {
               // If the leaf that has the item is non-null, then remove
               // the item.
               array = new ArrayCollection((leaf[0] as _Node).items_arr);
               array.removeItemAt(leaf[1]);
               this.items_total--;
               m4_TALKY2('remove: items_total:', this.items_total,
                         '/ item', item);

               // Condense the tree.
               this.condense_tree(leaf[0], new Array());

               // If the root node only has one child and the root isn't a
               // leaf, then make the tree shorter.
               if (this.root.items_arr.length == 1 && !(this.root.is_leaf)) {
                  this.root = this.root.items_arr[0];
                  this.root.parent = null;
               }
            }
         }
         m4_DEBUG_TIME('=TIME.IT= / remove');
      }

      // *** Internal functions

      //
      protected function add_item(item:MOBRable, parent:_Node) :void
      {
         parent.items_arr.push(item);
         if (item is _Node) {
            (item as _Node).parent = parent;
            (item as _Node).height = parent.height - 1;
         }
      }

      // A sorting function to compare two items distance to the current
      // _Node to reinsert about. Smallest distance is first.
      protected function compare_items(a:MOBRable, b:MOBRable) :int
      {
         var cx:Number = a.mobr.left + a.mobr.width / 2;
         var cy:Number = a.mobr.top + a.mobr.height / 2;
         var da:Number = Geometry.distance(cx, cy, re_nx, re_ny);
         var db:Number;

         cx = b.mobr.left + b.mobr.width / 2;
         cy = b.mobr.top + b.mobr.height / 2;
         db = Geometry.distance(cx, cy, re_nx, re_ny);

         if (da < db) {
            return -1;
         }
         else if (da == db) {
            return 0;
         }
         else { // (da > db)
            return 1;
         }
      }

      // Finds the leaf node which holds the given item (or null if none do.
      // Return an array whose first element is the _Node, and second is the
      // index into that _Node's item array of the desired item.
      protected function find_leaf(t:_Node, item:MOBRable) :Array
      {
         var i:int;
         var pair:Array;

         if (t.is_leaf) {
            for (i = 0; i < t.items_arr.length; i++) {
               if (t.items_arr[i] == item) {
                  pair = new Array(t, i);
                  return pair;
               }
            }
            return null;
         }
         else {
            for (i = 0; i < t.items_arr.length; i++) {
               if (t.mobr.intersects(item.mobr)) {
                  pair = this.find_leaf(t.items_arr[i], item);
               }
               if (pair !== null) {
                  return pair;
               }
            }
            return null;
         }
      }

      // Inserts an item into the R_Tree so that the item has a parent
      // with the specified height value.
      protected function insert_real(item:MOBRable, height:int) :void
      {
         // Gets the node to add the item to.
         var node:_Node = this.choose_subtree(this.root, item.mobr, height);
         m4_ASSERT(node.height == height); // node must be at desired height

         // Adds the item to it.
         this.add_item(item, node);

         // Overflow treatment if need be.
         if (node.items_arr.length > this.m_max) {
            this.overflow_treatment(node);
         }

         // Update the tree's bounds.
         node.update_bounds();
         while (node.parent !== null) {
            node.parent.update_bounds();
            node = node.parent;
         }
      }

      // ***

      //
      protected function area_difference(n:Rectangle, o:Rectangle) :Number
      {
         return Math.abs(n.width * n.height - o.width * o.height);
      }

      //
      protected function calculate_pickseeds_d(r1:Rectangle,
                                               r2:Rectangle) :Number
      {
         var r:Rectangle = r1.union(r2);
         return (r.width * r.height
                 - r1.width * r1.height
                 - r2.width * r2.height);
      }

      // Selects a _Node at the given height that would best hold the given
      // rectangle.
      protected function choose_subtree(n:_Node, r:Rectangle,
                                        height:int) :_Node
      {
         var best:_Node;
         var rf1:Rectangle;
         var rf2:Rectangle;
         var i:int;

         if (n.height == height) {
            return n;
         }
         else {
            best = n.items_arr[0];
            rf1 = best.mobr.union(r);
            for (i = 1; i < n.items_arr.length; i++) {
               rf2 = n.items_arr[i].mobr.union(r);
               if (this.compare_nodes(n.items_arr[i], rf2, best, rf1)) {
                  rf1 = rf2;
                  best = n.items_arr[i];
               }
            }

            return this.choose_subtree(best, r, height);
         }
      }

      // Checks whether or not the rectangle intersects any items.
      protected function collide_helper(n:_Node, r:Rectangle) :Boolean
      {
         var i:int;
         if (n.is_leaf) {
            // Push all items that intersect with r onto the results array
            for (i = 0; i < n.items_arr.length; i++) {
               if (n.items_arr[i].mobr.intersects(r)) {
                  return true;
               }
            }
         }
         else {
            // Loop through the children and recurse down the tree if the
            // child intersects the query region(r).
            for (i = 0; i < n.items_arr.length; i++) {
               if (n.items_arr[i].mobr.intersects(r)) {
                  if (this.query_real(n.items_arr[i], r)) {
                     return true;
                  }
               }
            }
         }

         return false;
      }

      // Return true if n1 is better than n2. r1 and r2 are the bounding
      // rectangles of the nodes after the new item would have been added to
      // it.
      protected function compare_nodes(n1:_Node, r1:Rectangle,
                                       n2:_Node, r2:Rectangle) :Boolean
      {
         if (this.area_difference(r1, n1.mobr)
             < this.area_difference(r2, n2.mobr)) {
            return true;
         }
         else if (this.area_difference(r2, n2.mobr)
                    == this.area_difference(r1, n1.mobr)) {
            if (n1.mobr.width * n1.mobr.height
                < n2.mobr.width * n2.mobr.height) {
               return true;
            }
         }

         return false;
      }

      // Condense the R_Tree, removing nodes with too few items and making
      // bounding boxes small if possible. Start condensing at n and propagate
      // upward along n's parent chain.
      protected function condense_tree(n:_Node, q:Array) :void
      {
         var array:ArrayCollection;
         var r:_Node;
         var i:int;

         if (n.parent === null) {
            // at root, reinsert all items of nodes in set q
            for each (r in q) {
               for (i = 0; i < r.items_arr.length; i++) {
                  this.insert_real(r.items_arr[i], r.height);
               }
            }

            n.update_bounds();
         }
         else {
            if (n.items_arr.length < m_min) {
               // _Node has too few children, remove this node and redistribute
               // the children once the root has been reached.
               array = new ArrayCollection(n.parent.items_arr);
               array.removeItemAt(array.getItemIndex(n));

               q.push(n);
            }
            else {
               // Ensure that the bounds of this node are correct.
               n.update_bounds();
            }

            // Recurse up the tree.
            this.condense_tree(n.parent, q);
         }
      }

      //
      protected function draw_node(n:_Node, gr:Graphics, tr:Function) :void
      {
         var i:int;
         var tc:Rectangle;

         tc = tr.call(null, n.mobr);
         gr.lineStyle(3, 0x000000);
         gr.beginFill(0x000000, .3);
         gr.drawRect(tc.x, tc.y, tc.width, tc.height);

         if (n.is_leaf) {
            for (i = 0; i < n.items_arr.length; i++) {
               tc = tr.call(null, n.items_arr[i].mobr);
               gr.lineStyle(2, 0x3333cc);
               gr.beginFill(0x3333cc, .5);
               gr.drawRect(tc.x, tc.y, tc.width, tc.height);
            }
         }
         else {
            for (i = 0; i < n.items_arr.length; i++) {
               this.draw_node(n.items_arr[i], gr, tr);
            }
         }
      }

      // Either splits the given _Node, or reinserts the items of the _Node
      protected function overflow_treatment(n:_Node) :void
      {
         if (do_force_reinserts
             && n.parent !== null && !this.treated[n.height]) {
            //m4_TALKY('overflow_treatment: attempting reinsertion');
            this.treated[n.height] = true;
            this.reinsert(n);
         }
         else {
            //m4_TALKY('overflow_treatment: splitting node');
            this.split(n);
         }
      }

      // Perform a search operation on the R_Tree, starting at the given _Node
      // It returns an array of all non-_Node items that intersect the query
      // rectangle.
      protected function query_real(n:_Node, r:Rectangle) :Array
      {
         var i:int;
         var u:int;
         var results:Array = new Array();
         var search_res:Array;

         if (n.is_leaf) {
            m4_TALKY('query_real: is_leaf: n:', n, '/ r:', r);
            // Push all items that intersect with r onto the results array.
            for (i = 0; i < n.items_arr.length; i++) {
               if (n.items_arr[i].mobr.intersects(r)) {
                  m4_TALKY(' .. intersects: n.items_arr[i]:', n.items_arr[i]);
                  results.push(n.items_arr[i]);
               }
            }
         }
         else {
            m4_TALKY('query_real: not is_leaf: n:', n, '/ r:', r);
            // Loop through the children and recurse down the tree if the
            // child intersects the query region(r).
            for (i = 0; i < n.items_arr.length; i++) {
               if (n.items_arr[i].mobr.intersects(r)) {
                  search_res = this.query_real(n.items_arr[i], r);
                  for (u = 0; u < search_res.length; u++) {
                     results.push(search_res[u]);
                  }
               }
            }
         }

         m4_TALKY2('query_real: items_total:', this.items_total,
                   '/ intersects results.length:', results.length);

         return results;
      }

      // Reinserts a portion of the given _Node's items
      protected function reinsert(n:_Node) :void
      {
         // EXPLAIN: MAGIC_NUMBER: Why 0.3?
         var p:int = 0.3 * this.m_max;
         var rm_items:Array;

         this.re_nx = n.mobr.left + n.mobr.width / 2;
         this.re_ny = n.mobr.top + n.mobr.height / 2;
         n.items_arr.sort(this.compare_items);

         m4_ASSERT(n.items_arr.length == this.m_max + 1);

         // Split up the sorted items and reinsert the first p items.
         // The remaining ones stay in n.
         rm_items = n.items_arr.splice(0, p);
         n.update_bounds();

         m4_ASSERT(rm_items.length == p);
         m4_ASSERT(n.items_arr.length == this.m_max + 1 - p);
         m4_ASSERT(n.items_arr.length + rm_items.length == this.m_max + 1);

         for (p = 0; p < rm_items.length; p++) {
            this.insert_real(rm_items[p], n.height);
         }

         // just in case after the re-insertion, that n no longer has min
         // items
         this.condense_tree(n, new Array());
      }


      // Splits the given node, making one new node to hold excess items
      // from the original. If the given node is the root, then a new root is
      // made. The new node inserted to be at the same height as the given.
      protected function split(n:_Node) :void
      {
         var dstr:Array;
         var new_n:_Node = new _Node();
         var i:int;

         // Distributes the items of n into two arrays.
         dstr = this.distribute_items_gutmann(n);

         // If the root is split, make the tree taller
         if (n.parent === null) {
            this.root = new _Node();
            this.root.height = n.height + 1;
            this.add_item(n, root);
            this.treated.push(false);
         }

         // Add the new node to the parent as well.
         this.add_item(new_n, n.parent);

         // Set the current node to a smaller item list
         n.items_arr = dstr[0];
         // Add all of the items in the other array to the new node
         for (i = 0; i < dstr[1].length; i++) {
            this.add_item(dstr[1][i], new_n);
         }

         // Update everyone's bounds
         n.update_bounds();
         new_n.update_bounds();
         n.parent.update_bounds();

         // Potentially split the parent, as well
         if (n.parent.items_arr.length > this.m_max) {
            this.overflow_treatment(n.parent);
         }
      }

      // ***

      // Distribute the items of a given _Node into two new arrays. Return an
      // array of arrays. (This is the Gutmann R-Tree split.)
      protected function distribute_items_gutmann(n:_Node) :Array
      {
         // See the gutmann paper for the internals of each algorithm.
         // DistributeItems variables
         var split:Array = new Array(2);
         var i:int;
         var r1:Rectangle;
         var r2:Rectangle;
         var diff1:Number;
         var diff2:Number;
         var group:int;

         // PickSeeds variables
         var best_d:Number;
         var best_e1:int;
         var best_e2:int;
         var e1:int;
         var e2:int;
         var d:Number;

         // PickNext variables.
         var best_e:int;
         // We iterate over the nodes multiple times; this tracks which nodes
         // we've processed.
         var picked:Array = new Array(n.items_arr.length);

         m4_ASSERT(n.items_arr.length == this.m_max + 1);

         for (i = 0; i < picked.length; i++) {
            picked[i] = false;
         }

         split[0] = new Array();
         split[1] = new Array();

         // PickSeeds
         best_e1 = 0;
         best_e2 = 1;
         best_d = this.calculate_pickseeds_d(n.items_arr[best_e1].mobr,
                                             n.items_arr[best_e2].mobr);

         for (e1 = 2; e1 < n.items_arr.length; e1++) {
            for (e2 = 1; e2 < e1; e2++) {
               d = this.calculate_pickseeds_d(n.items_arr[e1].mobr,
                                              n.items_arr[e2].mobr);

               if (d > best_d) {
                  best_e1 = e1;
                  best_e2 = e2;
                  best_d = d;
               }
            }
         }

         // After the best starting seeds have been found, add them to
         // their respective lists.
         //m4_TALKY2('distr_itms_gtmn: best_e1:', best_e1,
         //          '/ best_e2:', best_e2);
         split[0].push(n.items_arr[best_e1]);
         split[1].push(n.items_arr[best_e2]);

         r1 = n.items_arr[best_e1].mobr;
         r2 = n.items_arr[best_e2].mobr;

         //m4_TALKY2('distr_itms_gtmn: picked: best_e1:', best_e1,
         //          '/ best_e2:', best_e2);
         picked[best_e1] = true;
         picked[best_e2] = true;

         // DistributeItems
         while (((split[0].length + split[1].length) < (this.m_max + 1))
                && (split[0].length < (this.m_max - this.m_min + 1))
                && (split[1].length < (this.m_max - this.m_min + 1))) {
            // PickNext -> assign an index to best_e
            best_e = -1;
            best_d = -1;
            for (i = 0; i < n.items_arr.length; i++) {
               if (!picked[i]) {
                  diff1 = this.area_difference(r1.union(n.items_arr[i].mobr),
                                               r1);
                  diff2 = this.area_difference(r2.union(n.items_arr[i].mobr),
                                               r2);

                  var area_diff:Number = Math.abs(diff1 - diff2);
                  if (area_diff > best_d) {
                     best_d = area_diff;
                     best_e = i;
                     //m4_TALKY3('distr_itms_gtmn: yes: area_diff:',
                     //          int(area_diff), '/ best_d:', int(best_d),
                     //          '/ best_e:', best_e);
                  }
                  else {
                     //m4_TALKY3('distr_itms_gtmn:  no: area_diff:',
                     //          int(area_diff), '/ best_d:', int(best_d),
                     //          '/ best_e:', best_e);
                  }
               }
            }

            if (best_e == -1) {
               //m4_TALKY('distr_itms_gtmn: bailing on no best_e');
               break;
            }
            else {

               //m4_TALKY('distr_itms_gtmn: set picked: best_e:', best_e);
               picked[best_e] = true;

               // The next best item to add has been found, so figure out
               // which list to add it to.
               diff1 = this.area_difference(r1.union(n.items_arr[best_e].mobr),
                                            r1);
               diff2 = this.area_difference(r2.union(n.items_arr[best_e].mobr),
                                            r2);

               if (diff1 < diff2) {
                  group = 0;
               }
               else if (diff1 == diff2) {
                  if (r1.width * r1.height < r2.width * r2.height) {
                     group = 0;
                  }
                  else if (r1.width * r1.height == r2.width * r2.height) {
                     if (split[0].length < split[1].length) {
                        group = 0;
                     }
                     else {
                        group = 1;
                     }
                  }
                  else {
                     group = 1;
                  }
               }
               else {
                  group = 1;
               }

               // Add it to the correct list.
               if (group == 0) {
                  //m4_TALKY('distr_itms_gtmn: split[0].push/best_e:', best_e);
                  split[0].push(n.items_arr[best_e]);
                  r1 = r1.union(n.items_arr[best_e].mobr);
               }
               else {
                  //m4_TALKY('distr_itms_gtmn: split[1].push/best_e:', best_e);
                  split[1].push(n.items_arr[best_e]);
                  r2 = r2.union(n.items_arr[best_e].mobr);
               }
            }
         } // end: While

         // Distribute any remaining items
         if (split[0].length == (this.m_max - this.m_min + 1)) {
            for (i = 0; i < n.items_arr.length; i++) {
               if (!picked[i]) {
                  //m4_TALKY('distr_itms_gtmn: split[1].push/i:', i);
                  split[1].push(n.items_arr[i]);
               }
            }
         }
         else if (split[1].length == (this.m_max - this.m_min + 1)) {
            for (i = 0; i < n.items_arr.length; i++) {
               if (!picked[i]) {
                  //m4_TALKY('distr_itms_gtmn: split[0].push/i:', i);
                  split[0].push(n.items_arr[i]);
               }
            }
         }
         else {
            m4_ERROR('distribute_items_gutmann: huh?');
            //m4_ERROR('FIXME');
            m4_ERROR2('split[0].length:', split[0].length,
                      '/ split[1].length:', split[1].length);
            m4_ERROR('this.m_max:', this.m_max, '/ m_min:', this.m_min);
            //m4_ASSERT(false);
            m4_ASSERT_SOFT(false);
         }

         // We added a new item to a full node, which means we split the full
         // node into two and added the item to one of them. Therefore, there
         // should be one more than the max number of items total.
         //m4_ASSERT((split[0].length + split[1].length) == (this.m_max + 1));
         if (!((split[0].length + split[1].length) == (this.m_max + 1))) {
            m4_ERROR('FIXME');
            m4_ERROR2('split[0].length:', split[0].length,
                      '/ split[1].length:', split[1].length);
            m4_ERROR('this.m_max:', this.m_max, '/ m_min:', this.m_min);
            m4_ASSERT(false);
         }

         return split;
      }

   }
}

// *** Alrighty, then, an inline class.

// EXPLAIN: Why is this allowed to live outside the package { }
//          definition? Is it because it's just local to this
//          module?

import flash.geom.Rectangle;

import utils.geom.MOBRable;

class _Node implements MOBRable
{

   public var parent:_Node;
   public var items_arr:Array;
   public var rect:Rectangle;
   public var height:int;

   public function _Node()
   {
      this.parent = null;
      this.items_arr = new Array();
      this.rect = new Rectangle();
      this.height = 0;
   }

   public function get is_leaf() :Boolean
   {
      return this.height == 0;
   }

   public function get mobr() :Rectangle
   {
      return this.rect;
   }

   public function set mobr(rect:Rectangle) :void
   {
      this.rect = rect;
   }

   public function update_bounds() :void
   {
      var i:int;
      if (this.items_arr.length > 0) {
         this.mobr = this.items_arr[0].mobr;
         for (i = 1; i < this.items_arr.length; i++) {
            this.mobr = this.mobr.union(this.items_arr[i].mobr);
         }
      }
      else {
         this.mobr = new Rectangle();
      }
   }

}

