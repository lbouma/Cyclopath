/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.util.ArrayList;
import java.util.Arrays;

import android.os.Parcel;
import android.os.Parcelable;

public class Address implements Parcelable {
   
   /** x map coordinate of address */
   public double x;
   /** y map coordiante of address */
   public double y;
   /** width of object that address refers to (for when routing to map
    * objects)*/
   public float width;
   /** height of object that address refers to (for when routing to map
    * objects)*/
   public float height;
   /** Whether this address is for a map object */
   public boolean is_map_object;
   /** The address text */
   public String text;
   /** If the number of possible matches for an address is higher than an amount
    * specified on the server this text will display a message describing the
    * situation. */
   public String hit_count_text;
   /** Possible geocoded addresses for this address. Used for address
    * disambiguation. */
   public ArrayList<Address> addr_choices;
   /** Whether this address has been geocoded already */
   public boolean geocoded;

   /** Default constructor */
   public Address() {
      this("");
   }

   /**
    * Constructor for an address using only the text for that address
    * @param text address text
    */
   public Address(String text) {
      this.x = 0;
      this.y = 0;
      this.width = 0;
      this.height = 0;
      this.is_map_object = false;
      this.text = text;
      this.hit_count_text = "";
      this.addr_choices = new ArrayList<Address>();
      this.geocoded = false;
   }
   
   /**
    * Constructor to use when re-constructing Address from a parcel.
    * @param in a parcel from which to read this address
    */
   public Address(Parcel in) {
      // NOTE: Each field must be read in the same order that it was written to
      // the parcel.
      this.x = in.readDouble();
      this.y = in.readDouble();
      this.width = in.readFloat();
      this.height = in.readFloat();
      this.is_map_object = Boolean.parseBoolean(in.readString());
      this.geocoded = Boolean.parseBoolean(in.readString());
      this.text = in.readString();
      this.hit_count_text = in.readString();
      Address[] addresses = in.createTypedArray(Address.CREATOR);
      this.addr_choices = new ArrayList<Address>(Arrays.asList(addresses));
   }
   
   /**
    * This method is not used for this class, but is required when implementing
    * the Parcelable interface.
    */
   @Override
   public int describeContents() {
      return 0;
   }
   
   /**
    * Writes this object to a Parcel.
    * @param out Parcel to write the object to.
    * @param flags Additional flags about how the object should be written.
    */
   @Override
   public void writeToParcel(Parcel out, int flags) {
      out.writeDouble(this.x);
      out.writeDouble(this.y);
      out.writeFloat(this.width);
      out.writeFloat(this.height);
      out.writeString(Boolean.toString(this.is_map_object));
      out.writeString(Boolean.toString(this.geocoded));
      out.writeString(this.text);
      out.writeString(this.hit_count_text);
      Address[] temp_array = new Address[this.addr_choices.size()];
      this.addr_choices.toArray(temp_array);
      out.writeTypedArray(temp_array, flags);
   }
 
   /**
    * A Creator object that generates instances of Parcelable Addresses.
    */
   public static final Parcelable.Creator<Address> CREATOR =
         new Parcelable.Creator<Address>() {
      /**
       * Creates new instance of Parcelable Address using given Parcel
       * @param in Parcel containing Address
       */
      @Override
      public Address createFromParcel(Parcel in) {
         return new Address(in);
      }

      /**
       * Creates a new array of Addresses
       */
      @Override
      public Address[] newArray(int size) {
         return new Address[size];
      }
   };

}
