/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Attribute_Control_One_Way extends Command_Scalar_Edit {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Attr_1W');

      // *** Constructor

      // The targets is a collection of Byways.
      public function Attribute_Control_One_Way(targets:Set_UUID)
         :void
      {
         // The one_way control is just a button that cycles through the
         // available one_way values (that is, the user can only progress
         // through the list of values in one direction). So take the existing
         // value for one_way, and choose the next value.
         // FIXME: here be magic number voodoo. Basically, what is going on is
         // that we add 1, but (a) wrap around to -1 if we exceed 1 and (b)
         // start with -1 if there's no consensus.
         // See also: 'one_way_str'.
         var i:int = Objutil.consensus(targets, 'one_way', -2);
         // EXPLAIN: Why adding 1, and why -1 is a good default.
         //          (I think -1 and 1 mean 1-way (opp. dirs.), and 0 is 2-way
         i += 1;
         if (i > 1) {
            i = -1;
         }
         m4_ASSERT((-1 <= i) && (i <= 1));
         super(targets, 'one_way', i);
      }

   }
}

