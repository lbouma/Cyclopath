/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*
FIXME/BUGnnnn this is soooo easy:
                  do not draw labels whose text is longer
                     than the geometry.
this doesn't fix _all_ straight labels.
 we still need a curve algorithm that wraps our labels to the line geometry.
*/

package utils.misc {

   import flash.filters.GlowFilter;
   import flash.geom.Matrix;
   import flash.text.TextField;
   import flash.text.TextFormat;

   import items.Item_Versioned;

   public class Map_Label extends TextField {

      // Bring in the map label font. Copied from
      // /usr/share/fonts/truetype/ttf-bitstream-vera/
      // FIXME: move file to assets/ttf/
      [Embed(fontName='maplabelfont',
             source='/assets/ttf/VeraBd.ttf',
             fontWeight='bold')]
      // Unused variable required for the compiler to embed the font.
      public static var dummy_maplabelfont:Class;

      // Parallel array of the four corners of the labels rotated bbox
      // All coordinates are in canvas space
      public var xs:Array;
      public var ys:Array;

      // The extents of the box, used for hit testing since we pad the box size
      public var max_x:Number;
      public var min_x:Number;
      public var max_y:Number;
      public var min_y:Number;

      public var item_owner:Item_Versioned;

      // *** Constructor

      // x, y indicates _center_ of label
      public function Map_Label(text:String,
                                size:Number,
                                rotation:Number,
                                x:Number,
                                y:Number,
                                item_owner:Item_Versioned=null,
                                halo_color:*=null)
      {
         var m:Matrix;
         var tf:TextFormat;
         var halo:GlowFilter;

         // used to get the bounding box of the label
         var cos_t:Number = Math.cos(isNaN(rotation) ? 0 : rotation);
         var sin_t:Number = Math.sin(isNaN(rotation) ? 0 : rotation);
         var wpad:Number = Conf.map_label_width_padding / 2.0;
         var hpad:Number = Conf.map_label_height_padding / 2.0;

         super();

         this.mouseEnabled = false;
         this.selectable = false;

         // Configure me to use an embedded font, which is required for
         // rotation.
         tf = this.defaultTextFormat;
         tf.font = 'maplabelfont';
         tf.size = size;
         this.embedFonts = true;
         this.defaultTextFormat = tf;

         // Set a halo -- makes text legible regardless of background colors.
         if (halo_color === null) {
            halo_color = Conf.label_halo_color;
         }
         halo = new GlowFilter(halo_color,
                               /*alpha=*/1, // default: 1.0
                               /*blurX=*/3, // default: 6.0
                               /*blurY=*/3, // default: 6.0
                               /*strength=*/16, // default: 2
                               /*quality=*/1, // default: 1
                               /*inner=*/false, // default: false
                               /*knockout=*/false); // default: false
         this.filters = [halo,];
         // set text -- not sure why the corrections are needed
         this.text = text;
         this.width = this.textWidth + 4;
         this.height = this.textHeight;

         this.item_owner = item_owner;

         // Save and pad the dimensions. Pad by 2 so bottom edge has more room.
         var w:Number = this.width;
         var h:Number = this.height + 2;

         // move into position
         m = new Matrix();
         // FIXME: lame hack! If rotation is not NaN, that means don't center
         // the label text.
         if (!isNaN(rotation)) {
            // -2 corrects position, don't know why it's wrong
            m.translate(-this.textWidth/2, -this.textHeight/2 - 2);
            m.rotate(rotation);
         }
         m.translate(x, y);
         this.transform.matrix = m;

         // Calculate the four corner's of my rotated bbox
         // for xs/ys[2] and [3], we adjust by 2 to make top edge closer
         this.xs = [this.x + (hpad + 0) * sin_t - wpad * cos_t,
                    this.x + (hpad + 0) * sin_t + (w + wpad) * cos_t,
                    this.x - (h + hpad) * sin_t + (w + wpad) * cos_t,
                    this.x - (h + hpad) * sin_t - wpad * cos_t];

         this.ys = [this.y - (hpad + 0) * cos_t - wpad * sin_t,
                    this.y - (hpad + 0) * cos_t + (w + wpad) * sin_t,
                    this.y + (h + hpad) * cos_t + (w + wpad) * sin_t,
                    this.y + (h + hpad) * cos_t - wpad * sin_t];

         this.max_x = Math.max(this.xs[0], this.xs[1], this.xs[2], this.xs[3]);
         this.min_x = Math.min(this.xs[0], this.xs[1], this.xs[2], this.xs[3]);
         this.max_y = Math.max(this.ys[0], this.ys[1], this.ys[2], this.ys[3]);
         this.min_y = Math.min(this.ys[0], this.ys[1], this.ys[2], this.ys[3]);
      }

      // ***

      //
      override public function toString() :String
      {
         // Skipping super.toString(), which just returns '[object Map_Label]'.
         return (
            'Map_Label: "' + this.text
            + '" / owner: ' + this.item_owner
            + '" / visible: ' + this.visible);
      }

   }
}

