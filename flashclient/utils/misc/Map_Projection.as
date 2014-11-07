/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class is a utility used for converting to and from different
// map projections.  It has functions for WGS84(wgs), Transverse Mercator(tm),
// and Universal Transverse Mercator(UTM).
//
// For UTM, Cyclopath uses zone 15 and is in the northern hemisphere.
//
// The implementations of wgs_to_tm, tm_to_wgs, wgs_to_utm, and utm_to_wgs
// are based off of the javascript code presented at:
//   http://home.hiwaay.net/~taylorc/toolbox/geography/geoutm.html
//
// NOTE: This class isn't being used at the moment, but it could prove useful.

package utils.misc {

   public class Map_Projection {

      m4_ASSERT(false); // This class is not used... at the moment.

      // MAGIC_NUMBERs: Ellipsoid model constants.
      //                The values here are for WGS84.
      protected static const sm_a:Number = 6378137.0;
      protected static const sm_b:Number = 6356752.314;
      protected static const sm_eec_squared:Number = 6.69437999013e-03;

      protected static const utm_scale_factor:Number = 0.996;

      // Computes the footpoint latitude for use in converting
      // transverse mercator coordinates to ellipsoidal coordinates.
      //
      // Inputs:
      // y - The northing coordinate, in meters
      //
      // Return the footpoint latitude, in radians
      protected static function footpoint_latitude(y:Number) :Number
      {
         var n:Number = (sm_a - sm_b) / (sm_a + sm_b);
         // cache powers of n
         var n2:Number = n * n;
         var n3:Number = n2 * n;
         var n4:Number = n3 * n;
         var n5:Number = n4 * n;

         var alpha:Number = .5 * (sm_a + sm_b) * (1 + n2 / 4) + n4 / 64;
         var yp:Number = y / alpha;
         var beta:Number = 1.5 * n - 27.0 / 32.0 * n3 + 269.0 / 512.0 * n5;
         var gamma:Number = 21.0 / 16.0 * n2 - 55.0 / 32.0 * n4;
         var delta:Number = 151.0 / 96.0 * n3 - 417.0 / 128.0 * n5;
         var epsilon:Number = 1097.0 / 512.0 * n4;

         // calculate and return the result
         return yp + (beta * Math.sin(2 * yp))
                   + (gamma * Math.sin(4 * yp))
                   + (delta * Math.sin(6 * yp))
                   + (epsilon * Math.sin(8 * yp));
      }

      // Computes the ellipsoidal distance from the equator to a point at
      // the given latitude.
      //
      // Inputs:
      // phi - Latitude of the point, in radians
      //
      // Return computed ellipsoid distance from equator, in meters
      protected static function meridian_arc_length(phi:Number) :Number
      {
         var n:Number = (sm_a - sm_b) / (sm_a + sm_b);
         // cache powers of n
         var n2:Number = n * n;
         var n3:Number = n2 * n;
         var n4:Number = n3 * n;
         var n5:Number = n4 * n;

         var alpha:Number = .5 * (sm_a + sm_b) * (1 + n2 / 4) + n4 / 64;
         var beta:Number = -1.5 * n + 9.0 / 16.0 * n3 - 3.0 / 32.0 * n5;
         var gamma:Number = 15.0 / 16.0 * n2 - 15.0 / 32.0 * n4;
         var delta:Number = -35.0 / 48.0 * n3 + 105.0 / 256.0 * n5;
         var epsilon:Number = 315.0 / 512.0 * n4;

         // calcuate and return the distance
         return alpha * (phi + (beta * Math.sin(2 * phi))
                             + (gamma * Math.sin(4  * phi))
                             + (delta * Math.sin(6 * phi))
                             + (epsilon * Math.sin(8 * phi)));
      }

      // Converts x, y coordinates in the transverse mercator projection to
      // a latitude/longitude pair in WGS84.  (T-M is not the same as UTM).
      //
      // Inputs:
      // x - The x or easting of the point, in meters
      // y - The y or northing of the point, in meters
      // lambda0 - Longitude of the central meridian to use, in radians
      //
      // Return 2-element array containing [lat, lon] of WGS84 point
      public static function tm_to_wgs(x:Number, y:Number,
                                       lambda0:Number) :Array
      {
         // precalculate phi_f, ep2, cos_pf, nuf2 and nf
         var phi_f:Number = footpoint_latitude(y);
         var ep2:Number = (sm_a * sm_a - sm_b * sm_b) / (sm_b * sm_b);
         var cos_pf:Number = Math.cos(phi_f);
         var nuf2:Number = ep2 * cos_pf * cos_pf;
         var nf:Number = sm_a * sm_a / (sm_b * Math.sqrt(1 + nuf2));
         // precalculate t values
         var tf:Number = Math.tan(phi_f);
         var tf2:Number = tf * tf;
         var tf4:Number = tf2 * tf2;

         // misc
         var x_frac:Array = new Array(8); // [i] is xfrac(i+1)
         var x_poly:Array = new Array(8); // [i] is xpoly(i+1)
         var latlon:Array;
         var tmp:Number;

         // value holds increasing powers of nf and x
         var pow_nf:Number = nf;
         var pow_x:Number = x;

         // calculate fractional coefficients for x**n to simplify expressions
         x_frac[0] = 1 / (pow_nf * cos_pf);
         pow_nf *= nf;
         x_frac[1] = tf / (2 * pow_nf);
         pow_nf *= nf;
         x_frac[2] = 1 / (6 * pow_nf * cos_pf);
         pow_nf *= nf;
         x_frac[3] = tf / (24 * pow_nf);
         pow_nf *= nf;
         x_frac[4] = 1 / (120 * pow_nf * cos_pf);
         pow_nf *= nf;
         x_frac[5] = tf / (720 * pow_nf);
         pow_nf *= nf;
         x_frac[6] = 1 / (5040 * pow_nf * cos_pf);
         pow_nf *= nf;
         x_frac[7] = tf / (40320 * pow_nf);

         // calculate polynomical coefficients for x**n
         // -- x**1 uses a poly value of 1
         x_poly[0] = 1;
         x_poly[1] = -1 - nuf2;
         x_poly[2] = -1 - 2 * tf2 - nuf2;
         x_poly[3] = 5 + 3 * tf2 + 6 * nuf2 - 6 * (tf2 * nuf2)
                     - 3 * (nuf2 * nuf2) - 9 * tf2 * (nuf2 * nuf2);
         x_poly[4] = 5 + 28 * tf2 + 24 * tf4 + 6 * nuf2 + 8 * (tf2 * nuf2);
         x_poly[5] = -61 - 90 * tf2 - 45 * tf4 - 107 * nuf2
                     + 162 * (tf2 * nuf2);
         x_poly[6] = -61 - 662 * tf2 - 1320 * tf4 - 720 * (tf4 * tf2);
         x_poly[7] = 1385 + 3633 * tf2 + 4095 * tf4 + 1575 * (tf4 + tf2);

         latlon = [phi_f, lambda0];
         // calculate lat/lon, for efficiency it's converted to a loop
         for (var i:int = 0; i < 8; i++) {
            tmp = x_frac[i] * x_poly[i] * pow_x;
            if (i % 2 == 0) {
               // y coordinate
               latlon[1] += tmp;
            }
            else {
               // x coordinate
               latlon[0] += tmp;
            }

            pow_x *= x;
         }

         return latlon;
      }

      // Determine the central meridan for the given UTM zone
      //
      // Inputs:
      // zone - An integer value designating the UTM zone, in [1, 60]
      //
      // Return the central meridian in radians (will be in radian equivalent
      //   of [-177, 177])
      public static function utm_central_meridian(zone:int) :Number
      {
         return Geometry.degree_to_rad(-183.0 + zone * 6.0);
      }

      // Converts x, y coordinates in the UTM projection to a lat/lon
      // pair in WGS84.
      //
      // Inputs:
      // x - The x or easting of the point, in meters
      // y - The y or northing of the point, in meters
      // south_hemisphere - True if the point is in the southern hemisphere.
      //
      // Return 2-element array containing [lat, lon] of converted point
      public static function utm_to_wgs(x:Number, y:Number, zone:int,
                                        south_hemisphere:Boolean) :Array
      {
         x -= 500000.0;
         x /= utm_scale_factor;

         if (south_hemisphere) {
            y -= 10000000.0;
         }
         y /= utm_scale_factor;

         return tm_to_wgs(x, y, utm_central_meridian(zone));
      }

      // Converts latitude/longitude pair to x and y coordinates in the
      // transverse mercator projection (this is not UTM).
      //
      // Input:
      // phi - Latitude of point, in radians
      // lambda - Longitude of point, in radians
      // lambda0 - Longitude of the central meridian used, in radians
      //
      // Return 2-element array [x, y] of computed T-M point
      public static function wgs_to_tm(phi:Number, lambda:Number,
                                       lambda0:Number) :Array
      {
         var c_phi = Math.cos(phi);

         // precalculate ep2, nu2, and n
         var ep2:Number = (sm_a * sm_a - sm_b * sm_b) / (sm_b * sm_b);
         var nu2:Number = ep2 * c_phi * c_phi;
         var n:Number = sm_a * sm_a / (sm_b * Math.sqrt(1 + nu2));

         // precalculate t values
         var t:Number = Math.tan(phi);
         var t2:Number = t * t;

         // misc
         var l:Number = lambda - lambda0;
         var ln_coef:Array = new Array(8); // [i] corresponds to l**(i+1)
         var ln_div:Array;
         var xy:Array;
         var tmp:Number;

         // values that take on subsequent powers of l and c_phi
         var pow_l:Number = l;
         var pow_cphi:Number = c_phi;

         // precalculate coefficients for the l**n in the equations below
         // so a the expressions for easting and northing are readable
         // -- l**1 and l**2 have coefficient values of 1
         ln_coef[0] = 1;
         ln_coef[1] = 1;

         ln_coef[2] = 1 - t2 + nu2;
         ln_coef[3] = 5 - t2 + 9 * nu2 + 4 * (nu2 * nu2);
         ln_coef[4] = 5 - 18 * t2 + (t2 * t2) + 14 * nu2 - 58 * (t2 * nu2);
         ln_coef[5] = 61 - 58 * t2 + (t2 * t2) + 270 * nu2 - 330 * (t2 * nu2);
         ln_coef[6] = 61 - 479 * t2 + 179 * (t2 * t2) - (t2 * t2 * t2);
         ln_coef[7] = 1385 - 3111 * t2 + 543 * (t2 * t2) - (t2 * t2 * t2);

         // values alternate between x and y, starting with 0 -> x
         ln_div = [1.0, 2.0, 6.0, 24.0, 120.0, 720.0, 5040.0, 40320.0];

         xy = [0.0, meridian_arc_length(phi)];
         // for efficiency purposes, this has been converted into a loop
         for (var i:int = 0; i < 8; i++) {
            tmp = n / ln_div[i] * ln_coef[i] * pow_cphi * pow_l;
            if (i % 2 == 0) {
               // x value update
               xy[0] += tmp;
            }
            else {
               // y value update
               xy[1] += t * tmp;
            }

            pow_l *= l;
            pow_cphi *= c_phi;
         }

         return xy;
      }

      // Convert a latitude/longitude pair to x, y coordinates in the UTM
      // projection for the given zone.
      //
      // lat - Latitude of the point, in radians
      // lon - Longitude of the point, in radians
      // zone - UTM zone to be used, assumed to be in [1, 60]
      //
      // Return 2-element array of [x, y] in the UTM zone of converted point
      public static function wgs_to_utm(lat:Number, lon:Number,
                                        zone:int) :Array
      {
         var xy = wgs_to_tm(lat, lon, utm_central_meridian(zone));

         xy[0] = xy[0] * utm_scale_factor + 500000.0;
         xy[1] = xy[1] * utm_scale_factor;
         if (xy[1] < 0) {
            xy[1] = xy[1] + 10000000.0;
         }

         return xy;
      }

   }
}

