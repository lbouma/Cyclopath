/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.difflib {

   public class SequenceMatcher {

      protected var a:Array;
      protected var b:Array;
      protected var isjunk:Function;

      protected var b2j:Object;
      protected var matching_blocks:Array;
      protected var opcodes:Array;
      protected var isbjunk:Function;
      protected var isbpopular:Function;
      protected var fullbcount:Array;

      public function SequenceMatcher(a:Array, b:Array, isjunk:Function) :void
      {
         this.isjunk = (isjunk !== null) ? isjunk : defaultJunkFunction;
         this.set_seqs(a, b);
      }

      // Return an HTML diff showing the differences between strings a and b.
      public static function diff_html(a:String, b:String) :String
      {
         // WARNING: split() behaves strangely in the face of grouping
         //          parentheses. Read the docs carefully!
         var delim:RegExp = /(\W)/;
         var a1:Array = a.split(delim);
         var b1:Array = b.split(delim);
         var sm:SequenceMatcher;
         var opcodes:Array;
         var op:Array;
         var chunks:Array = [];
         var tag:String;
         var i1:int;
         var i2:int;
         var j1:int;
         var j2:int;

         sm = new SequenceMatcher(a1, b1, null);
         opcodes = sm.get_opcodes();
         for each (op in opcodes) {
            tag = op[0];
            i1 = int(op[1]);
            i2 = int(op[2]);
            j1 = int(op[3]);
            j2 = int(op[4]);
            if (tag == 'delete' || tag == 'replace') {
               chunks.push('<u><font color="#ff0000">'
                           + postprocess(a1.slice(i1, i2).join(''))
                           + '</font></u>');
            }
            if (tag == 'insert' || tag == 'replace') {
               chunks.push('<u><font color="#0000ff">'
                           + postprocess(b1.slice(j1, j2).join(''))
                           + '</font></u>');
            }
            if (tag == 'equal') {
               chunks.push(postprocess(a1.slice(i1, i2).join('')));
            }
         }

         return chunks.join('');
      }

      //
      public static function postprocess(a:String) :String
      {
         // fromCharCode(182) gets us a pilcrow (paragraph sign)
         var table:Array = [['&', '&amp;'],
                            ['<', '&lt;'],
                            ['>', '&gt;'],
                            ['\r', String.fromCharCode(182) + '<br>']];
         var sub:Array;

         for each (sub in table) {
            a = a.split(sub[0]).join(sub[1]);
         }
         return a;
      }

      //
      public static function defaultJunkFunction(c:String) :Boolean
      {
         return c in {" ":true, "\t":true, "\n":true, "\f":true, "\r":true};
      }

      // iteration-based reduce implementation
      public static function __reduce(func:Function, list:Array,
                                      initial:Object) :Object
      {
         var value:Object;
         var idx:int;

         if (initial !== null) {
            value = initial;
            idx = 0;
         }
         else if (list) {
            value = list[0];
            idx = 1;
         }
         else {
            return null;
         }

         for ( ; idx < list.length; idx++) {
            value = func(value, list[idx]);
         }

         return value;
      }

      // comparison function for sorting lists of numeric tuples
      public static function __ntuplecomp(a:Array, b:Array) :int
      {
         var mlen:int = Math.max(a.length, b.length);
         for (var i:int = 0; i < mlen; i++) {
            if (a[i] < b[i]) return -1;
            if (a[i] > b[i]) return 1;
         }

         return a.length == b.length ? 0 : (a.length < b.length ? -1 : 1);
      }

      //
      public static function __calculate_ratio(matches:int,
                                               length:Number) :Number
      {
         return length ? 2.0 * matches / length : 1.0;
      }

      // returns a function that returns true if a key passed to the returned
      // function is in the dict (js object) provided to this function;
      // replaces being able to carry around dict.has_key in python...
      public static function __isindict(dict:Object) :Function
      {
         return function (key:*) :Boolean { return key in dict; };
      }

      // replacement for python's dict.get function -- need easy default values
      public static function __dictget(dict:Object, key:*, defaultValue:*) :*
      {
         return key in dict ? dict[key] : defaultValue;
      }

      //
      public function set_seqs(a:Array, b:Array) :void
      {
         this.set_seq1(a);
         this.set_seq2(b);
      }

      //
      public function set_seq1(a:Array) :void
      {
         if (a == this.a) return;
         this.a = a;
         this.matching_blocks = this.opcodes = null;
      }

      //
      public function set_seq2(b:Array) :void
      {
         if (b == this.b) {
            return;
         }
         this.b = b;
         this.matching_blocks = this.opcodes = this.fullbcount = null;
         this.__chain_b();
      }

      //
      public function __chain_b() :void
      {
         var b:Array = this.b;
         var n:int = b.length;
         var b2j:Object = this.b2j = {};
         var populardict:Object = {};
         var elt:String;

         for (var i:int = 0; i < b.length; i++) {
            elt = b[i];
            if (elt in b2j) {
               var indices:Array = b2j[elt];
               if (n >= 200 && indices.length * 100 > n) {
                  populardict[elt] = 1;
                  delete b2j[elt];
               }
               else {
                  indices.push(i);
               }
            }
            else {
               b2j[elt] = [i];
            }
         }

         for (elt in populardict) {
            delete b2j[elt];
         }

         var isjunk:Function = this.isjunk;
         var junkdict:Object = {};
         if (isjunk !== null) {
            for (elt in populardict) {
               if (isjunk(elt)) {
                  junkdict[elt] = 1;
                  delete populardict[elt];
               }
            }
            for (elt in b2j) {
               if (isjunk(elt)) {
                  junkdict[elt] = 1;
                  delete b2j[elt];
               }
            }
         }

         this.isbjunk = __isindict(junkdict);
         this.isbpopular = __isindict(populardict);
      }

      //
      public function find_longest_match(alo:int, ahi:int,
                                         blo:int, bhi:int) :Array
      {
         var a:Array = this.a;
         var b:Array = this.b;
         var b2j:Object = this.b2j;
         var isbjunk:Function = this.isbjunk;
         var besti:int = alo;
         var bestj:int = blo;
         var bestsize:int = 0;
         var j:int;
         var k:int;

         var j2len:Object = {};
         var nothing:Array = [];
         for (var i:int = alo; i < ahi; i++) {
            var newj2len:Object = {};
            var jdict:Array = __dictget(b2j, a[i], nothing);
            for (var jkey:String in jdict) {
               j = jdict[jkey];
               if (j < blo) continue;
               if (j >= bhi) break;
               newj2len[j] = k = __dictget(j2len, j - 1, 0) + 1;
               if (k > bestsize) {
                  besti = i - k + 1;
                  bestj = j - k + 1;
                  bestsize = k;
               }
            }
            j2len = newj2len;
         }

         while ((besti > alo)
                && (bestj > blo)
                && (!isbjunk(b[bestj - 1]))
                && (a[besti - 1] == b[bestj - 1])) {
            besti--;
            bestj--;
            bestsize++;
         }

         while ((besti + bestsize < ahi)
                && (bestj + bestsize < bhi)
                && (!isbjunk(b[bestj + bestsize]))
                && (a[besti + bestsize] == b[bestj + bestsize])) {
            bestsize++;
         }

         while ((besti > alo)
                && (bestj > blo)
                && (isbjunk(b[bestj - 1]))
                && (a[besti - 1] == b[bestj - 1])) {
            besti--;
            bestj--;
            bestsize++;
         }

         while ((besti + bestsize < ahi)
                && (bestj + bestsize < bhi)
                && (isbjunk(b[bestj + bestsize]))
                && (a[besti + bestsize] == b[bestj + bestsize])) {
            bestsize++;
         }

         return [besti, bestj, bestsize];
      }

      //
      public function get_matching_blocks() :Array
      {
         if (this.matching_blocks !== null) {
            return this.matching_blocks;
         }

         var la:int = this.a.length;
         var lb:int = this.b.length;

         var queue:Array = [[0, la, 0, lb]];
         var matching_blocks:Array = [];
         var alo:int;
         var ahi:int;
         var blo:int;
         var bhi:int;
         var qi:Array;
         var i:int;
         var j:int;
         var k:int;
         var x:Array;
         while (queue.length) {
            qi = queue.pop();
            alo = qi[0];
            ahi = qi[1];
            blo = qi[2];
            bhi = qi[3];
            x = this.find_longest_match(alo, ahi, blo, bhi);
            i = x[0];
            j = x[1];
            k = x[2];

            if (k) {
               matching_blocks.push(x);
               if (alo < i && blo < j) {
                  queue.push([alo, i, blo, j]);
               }
               if (i+k < ahi && j+k < bhi) {
                  queue.push([i + k, ahi, j + k, bhi]);
               }
            }
         }

         matching_blocks.sort(__ntuplecomp);

         var i1:int;
         var j1:int;
         var k1:int;
         var i2:int;
         var j2:int;
         var k2:int;
         var block:Array;
         i1 = j1 = k1 = 0;
         var non_adjacent:Array = [];
         for (var idx:int = 0; idx < matching_blocks.length; idx++) {
            block = matching_blocks[idx];
            i2 = block[0];
            j2 = block[1];
            k2 = block[2];
            if (i1 + k1 == i2 && j1 + k1 == j2) {
               k1 += k2;
            }
            else {
               if (k1) non_adjacent.push([i1, j1, k1]);
               i1 = i2;
               j1 = j2;
               k1 = k2;
            }
         }

         if (k1) {
            non_adjacent.push([i1, j1, k1]);
         }

         non_adjacent.push([la, lb, 0]);
         this.matching_blocks = non_adjacent;
         return this.matching_blocks;
      }

      //
      public function get_opcodes() :Array
      {
         if (this.opcodes !== null) {
            return this.opcodes;
         }
         var i:int = 0;
         var j:int = 0;
         var answer:Array = [];
         this.opcodes = answer;
         var block:Array;
         var ai:int;
         var bj:int;
         var size:int;
         var tag:String;
         var blocks:Array = this.get_matching_blocks();
         for (var idx:String in blocks) {
            block = blocks[idx];
            ai = block[0];
            bj = block[1];
            size = block[2];
            tag = '';
            if (i < ai && j < bj) {
               tag = 'replace';
            }
            else if (i < ai) {
               tag = 'delete';
            }
            else if (j < bj) {
               tag = 'insert';
            }
            if (tag) {
               answer.push([tag, i, ai, j, bj]);
            }
            i = ai + size;
            j = bj + size;

            if (size) {
               answer.push(['equal', ai, i, bj, j]);
            }
         }

         return answer;
      }

      // get_grouped_opcodes() not translated
      // ratio() not translated
      // quick_ratio() not translated
      // real_quick_ratio() not translated

   }
}

