/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* A note on code style: This file doesn't adhere to Cyclopath's variable and
 * function naming.  It instead follows conventions used in Javascript 
 * development, so that external developers can more easily read it. */

/* Public function that can be used to embed a route-finding widget
 * into the given divId.  The parameters color, to, from and autoFind
 * are optional.  color specifies the background color; to and from
 * can assign locked to/from locations of a route (if not null);
 * and autoFind determines the finding behavior in Cyclopath when the
 * go button is clicked by a user. */
function embedCyclopath(divId, color, to, from, autoFind) {
   // validate the input parameters (sort-of) and assign defaults
   // if needed
   if (divId == undefined)
      throw "divId is required";

   if (from == undefined || !(from instanceof Array))
      from = null;
   if (to == undefined || !(to instanceof Array))
      to = null;
   
   if (autoFind == undefined)
      autoFind = true;

   var colorSet = new Cyclopath.ColorSet(color);
   
   // create a function that will execute when everything is loaded
   var onLoad = function() { 
      if (!Cyclopath.inited) 
         Cyclopath.init();
      var divParent = document.getElementById(divId);
      if (!divParent)
         throw "divId is not contained in the document";
      Cyclopath.buildWidget(divParent, from, to, autoFind, colorSet); 
   };
   
   // set the load listener to execute when the body is completed
   if (document.addEventListener) {
      // mozilla browser
      window.addEventListener("load", onLoad, true);
   } else {
      // internet explorer
      window.attachEvent("onload", onLoad);
   }
}

/** Internal functions */

// After init(), will also contain geowikiUrl, buttonImage and headerImage
var Cyclopath = {
   inited: false,
   routeDeepLink: "?source=widget#route",
   headerImageUrl: "widget/widget_header.png", // relative url
   buttonImageUrl: "widget/find_route_button.png"
};

// To be called before first buildWidget() after onload event fires
Cyclopath.init = function() {
   Cyclopath.inited = true;

   var s = document.getElementById("cyclopath_script");
   if (s == undefined)
      throw "route_widget.js script must have an id of 'cyclopath_script'";
   
   var index = s.src.search("route_widget.js");
   if (index >= 0) {
      // found the script tag holding this script
      Cyclopath.geowikiUrl = s.src.substring(0, index);
      
      // pre-load the images
      Cyclopath.headerImage = new Image();
      Cyclopath.headerImage.src = Cyclopath.geowikiUrl
                                  + Cyclopath.headerImageUrl;

      Cyclopath.buttonImage = new Image();
      Cyclopath.buttonImage.src = Cyclopath.geowikiUrl
                                  + Cyclopath.buttonImageUrl;
   }
}

Cyclopath.ColorSet = function(color) {
   if (color == undefined)
      color = "#3a3a3c";
   
   /* Constants, for now */
   this.dfltTextColor = "#666666";
   this.warnTextColor = "#cc0000";
   this.userTextColor = "#000000";
   this.labelColor = "#000000";
   
   this.inputBorderColor = "#000000";
   this.addressBorderColor = "#000000";
   
   this.buttonBackgroundColor = "#eeeeee";
   
   /* Derived colors from main color*/
   var pColor = Cyclopath.hexstr2num(color);	
   var pBright = Cyclopath.brightness(pColor[0], pColor[1], pColor[2]);
   
   this.widgetBackgroundColor = color;
   if (pBright > 128) {
      // we're bright, so address_bg and bt_normal are darker
      this.addressBackgroundColor = Cyclopath.num2hexstr(pColor[0] - 
                                                         pBright / 3, 
							 pColor[1] - 
                                                         pBright / 3,
							 pColor[2] - 
                                                         pBright / 3);
   } else {
      // make internal components brighter		
      this.addressBackgroundColor = Cyclopath.num2hexstr(pColor[0] + 
                                                         (255 - pBright) / 3, 
							 pColor[1] + 
                                                         (255 - pBright) / 3,
							 pColor[2] + 
                                                         (255 - pBright) / 3);
   }
};


// expects an array of already converted values, returns 0-255
Cyclopath.brightness = function(red, green, blue) {
   return Math.sqrt(.241 * red * red + 
                    .691 * green * green +
                    .068 * blue * blue);
};

// split color string into array of int r/g/b values
Cyclopath.hexstr2num = function(color) {
   return [
      parseInt(color.substring(1, 3), 16), // red
      parseInt(color.substring(3, 5), 16), // green
      parseInt(color.substring(5, 7), 16), // blue
   ];
};

Cyclopath.num2hexstr = function(red, green, blue) {
   var hexAlphabet = "0123456789abcdef";
   var rgb = [Math.max(0, Math.min(red, 255)), 
              Math.max(0, Math.min(green, 255)), 
              Math.max(0, Math.min(blue, 255))];
   var hex = "#";
   
   var int1, int2;
   for (var i = 0; i < 3; i++) {
      int1 = rgb[i] / 16;
      int2 = rgb[i] % 16;
      
      hex += hexAlphabet.charAt(int1) + hexAlphabet.charAt(int2);
   }
   
   return hex;
};

Cyclopath.buildWidget = function(parent, from, to, autoFind, colorSet) {
   var mainDiv = document.createElement("div");
   mainDiv.style.backgroundColor = colorSet.widgetBackgroundColor;
   mainDiv.style.width = "193px";
   parent.appendChild(mainDiv);
   
   // header
   Cyclopath.buildHeader(mainDiv, colorSet);
   
   // from_address
   var fromForms;
   if (from == null) {
      fromForms = Cyclopath.buildInputAddress(mainDiv, "Go from:", colorSet);
   } else {
      fromForms = Cyclopath.buildLockedAddress(mainDiv, "Go from:", 
                                               from, colorSet);
   }
    
   // to_address
   var toForms;
   if (to == null) {
      toForms = Cyclopath.buildInputAddress(mainDiv, "To:", colorSet);
   } else {
      toForms = Cyclopath.buildLockedAddress(mainDiv, "To:", to, colorSet);
   }
      
   // buttons
   var buttonDiv = document.createElement("div");
   buttonDiv.setAttribute("align", "right");
   buttonDiv.style.paddingBottom = "4px";
   mainDiv.appendChild(buttonDiv);
   Cyclopath.buildImageButton(buttonDiv, "Find Route", fromForms, toForms, 
                              autoFind, colorSet);
   
   return mainDiv;
};

Cyclopath.buildHeader = function(parent, colorSet) {
   var div = document.createElement("div");
   
   div.style.backgroundColor = "transparent";
   div.style.backgroundImage = "url(" + Cyclopath.headerImage.src + ")";
   div.style.width = "193px";
   div.style.height = "51px";
   
   parent.appendChild(div);
};

/* Return an array of the address, city, and zip input fields. */
Cyclopath.buildLockedAddress = function(parent, label, values, colorSet) {
   var outerDiv = Cyclopath.buildAddressBox(parent, label, colorSet);
   var addr = Cyclopath.buildHiddenText(outerDiv, values[0]);
   var city = Cyclopath.buildHiddenText(outerDiv, values[1]);
   var zip = Cyclopath.buildHiddenText(outerDiv, values[2]);
   
   outerDiv.appendChild(document.createElement("br"));
   Cyclopath.buildTextSpan(outerDiv, values[0], "normal", "12px",
                           colorSet.labelColor);
                                                                               
   if (values.length == 2) {
      outerDiv.appendChild(document.createElement("br"));
      Cyclopath.buildTextSpan(outerDiv, values[1] + ", MN", "normal", "12px",
                              colorSet.labelColor);
   } else if (values.length == 3) {
      outerDiv.appendChild(document.createElement("br"));
      Cyclopath.buildTextSpan(outerDiv, values[1] + ", MN " + values[2], 
                              "normal", "12px", colorSet.labelColor);
   }
   
   return [addr, city, zip];
};

/* Return the created span. */
Cyclopath.buildTextSpan = function(parent, text, weight, size, color) {
   var span = document.createElement("span");
   span.style.fontWeight = weight;
   span.style.fontSize = size;
   span.style.fontFamily = "Verdana, Arial, Helvetica, sans-serif";
   span.style.color = color;

   if (span.textContent == undefined)
      span.innerText = text; // ie
   else
      span.textContent = text;
   
   parent.appendChild(span);
   return span;
};

/* Return the input form for later use. */
Cyclopath.buildHiddenText = function(parent, value) {
   var form = document.createElement("input");
   form.type = "text";
   form.value = value;
   form.style.display = "none";
   
   form.cyclopathIsDflt = false;
   
   parent.appendChild(form);
   return form;
};

/* Return an array of the address, city, and zip input fields. */
Cyclopath.buildInputAddress = function(parent, label, colorSet) {
   var outerDiv = Cyclopath.buildAddressBox(parent, label, colorSet);

   // HACK: This fixes some weird bugs in IE6 (further testing is
   // required for other IE versions).
   // See http://www.satzansatz.de/cssd/onhavinglayout.html
   if (document.all)
      outerDiv.style.display = "inline-block";

   var addrForm = Cyclopath.buildInputField(outerDiv, "Address (required)", 
                                            colorSet);
   addrForm.childNodes[0].style.width = "100%";
   addrForm.style.marginBottom = "2px";

   var cityForm = Cyclopath.buildInputField(outerDiv, "City", colorSet);
   cityForm.childNodes[0].style.width = "100%";

   var mnSpan = Cyclopath.buildTextSpan(outerDiv, ", MN", "normal", "12px",
                                        colorSet.labelColor);
   // move the text down slightly, so it looks centered with the fields
   mnSpan.style.paddingTop = Math.floor((cityForm.offsetHeight - 
                                         mnSpan.offsetHeight) / 2) + "px";
   
   var zipForm = Cyclopath.buildInputField(outerDiv, "Zip", colorSet, 5);
   
   // now make the city form take up as much space as possible, if it were
   // on the same line as the zip
   var cityWidth = Math.floor((outerDiv.offsetWidth - mnSpan.offsetWidth -
                               zipForm.childNodes[0].offsetWidth - 8.0));
   cityForm.style.width = cityWidth + "px";
   
   // now float both city and zip so that they are on one line
   // must set both styleFloat(IE) and cssFloat(everyone else)
   cityForm.style.styleFloat = "left";
   mnSpan.style.styleFloat = "left";
   zipForm.style.styleFloat = "right";
   cityForm.style.cssFloat = "left";
   mnSpan.style.cssFloat = "left";
   zipForm.style.cssFloat = "right";

   // empty div to clear the float style
   var clear = document.createElement("div");
   clear.style.clear = "both";
   outerDiv.appendChild(clear);
   
   // Resizing hack for netscape browsers that ignore the margin/padding
   // style when input fields don't have width = 'auto'
   if (navigator.appName.indexOf("Netscape") >= 0) {
      addrForm.childNodes[0].style.width = (addrForm.offsetWidth - 4.0) + "px";
      cityForm.childNodes[0].style.width = (cityForm.offsetWidth - 4.0) + "px";
   }

   return [addrForm.childNodes[0], cityForm.childNodes[0], 
           zipForm.childNodes[0]];
};

/* Return the div so that input fields and text can be added as needed. */
Cyclopath.buildAddressBox = function(parent, label, colorSet) {
   var outerDiv = document.createElement("div");
   outerDiv.style.backgroundColor = colorSet.addressBackgroundColor;
   outerDiv.style.margin = "0px 4px 4px 4px";

   outerDiv.style.padding = "0px 2px 2px 2px";

   outerDiv.style.border = "solid 1px " + colorSet.addressBorderColor;
   outerDiv.style.width = "auto";

   Cyclopath.buildTextSpan(outerDiv, label, "bold", "14px", 
                           colorSet.labelColor);

   parent.appendChild(outerDiv);
   return outerDiv;
};

/* Return a div containing the input field, for later use. */
Cyclopath.buildInputField = function(parent, dfltText, colorSet, maxLength) {
   // make the input text field
   var field = document.createElement("input");
   field.type = "text";
   
   field.onblur = function() { Cyclopath.inputBlur(field, 
                                                   colorSet.dfltTextColor); };
   field.onfocus = function() { Cyclopath.inputFocus(field, 
                                                     colorSet.userTextColor);};
   field.defaultValue = dfltText;
   if (maxLength) {
      field.size = maxLength;
      field.maxLength = maxLength;
   }

   field.style.fontSize = "12px";
   field.style.fontFamily = "Verdana, Arial, Helvetica, sans-serif";
   field.style.backgroundColor = "#ffffff";

   field.style.padding = "2px 0px 2px 2px";
   field.style.margin = "0px";
   field.style.width = "auto";

   field.style.borderStyle = "solid";
   field.style.borderWidth = "1px";
   field.style.borderColor = colorSet.inputBorderColor;
   
   field.hasLayout = true;
   Cyclopath.setDefaultText(field, dfltText, colorSet.dfltTextColor);
   
   // make a div that holds the text field
   var div = document.createElement("div");
   div.width = "auto";
   div.style.padding = "0px";
   div.style.margin = "0px";
   div.hasLayout = true;

   div.appendChild(field);
   parent.appendChild(div);
   
   // must be correctly sized, some browsers make the div larger vertically
   div.style.height = field.offsetHeight + "px";

   return div;
};

Cyclopath.inputFocus = function(field, textColor) {
   // clear the field and set the color to black
   if (field.cyclopathIsDflt) {
      field.value = "";
      field.style.color = textColor;
      field.cyclopathIsDflt = false;
   }
};

Cyclopath.inputBlur = function(field, textColor) {	
   // if they didn't enter text, then set it back to the default
   if (field.value.length == 0) {
      Cyclopath.setDefaultText(field, field.defaultValue, textColor);
   }
};

Cyclopath.setDefaultText = function(field, text, textColor) {
   field.value = text;
   field.style.color = textColor;
   field.cyclopathIsDflt = true;
};

Cyclopath.buildImageButton = function(parent, label, fromForms, toForms, 
                                      autoFind, colorSet) { 
   var anchor = document.createElement("a");
   anchor.style.borderStyle = "none";
   anchor.style.outline = "0";
   anchor.style.display = "block";
   anchor.style.width = "85px";
   anchor.style.height = "20px";

   var button = document.createElement("span");
   button.appendChild(anchor);

   button.style.display = "block";
   button.style.width = "85px";
   button.style.height = "20px";

   button.style.margin = "0px 4px 0px 4px";

   button.style.backgroundImage = "url(" + Cyclopath.buttonImage.src + ")";
   button.style.backgroundPosition = "0px 0px";

   button.onmouseover = function() { button.style.backgroundPosition = 
                                     "0px 40px"; };
   button.onmousedown = function() { button.style.backgroundPosition =
                                     "0px 20px"; };
   button.onmouseup = function() { button.style.backgroundPosition = 
                                   "0px 40px"; };
   button.onmouseout = function() { button.style.backgroundPosition = 
                                    "0px 0px"; };

   anchor.onclick = function() { return Cyclopath.getRoute(anchor, fromForms, 
                                                           toForms,
                                                           autoFind, colorSet);
                               };
   parent.appendChild(button);
};

Cyclopath.getRoute = function(anchor, from, to, autoFind, colorSet) {
   var fromAddr = from[0];
   var fromCity = from[1];
   var fromZip = from[2];
   
   var toAddr = to[0];
   var toCity = to[1];
   var toZip = to[2];
   
   // perform validation
   var valid = true;
   if (fromAddr.cyclopathIsDflt == undefined || fromAddr.cyclopathIsDflt) {
      valid = false;
      Cyclopath.setDefaultText(fromAddr, "Address is required", 
			       colorSet.warnTextColor);
   }
   
   if (toAddr.cyclopathIsDflt == undefined || toAddr.cyclopathIsDflt) {
      valid = false;
      Cyclopath.setDefaultText(toAddr, "Address is required", 
			       colorSet.warnTextColor);
   }
   
   // if we're valid, build up the deep-link url and then link there
   if (valid) {
      var params = (autoFind ? "auto_find=true" : "auto_find=false");
      var from = fromAddr.value;
      if (fromCity.cyclopathIsDflt == false && fromCity.value 
          && fromCity.value.length > 0)
	 from += ", " + fromCity.value;
      if ((fromCity.cyclopathIsDflt == false && fromCity.value 
           && fromCity.value.length > 0) || (fromZip.cyclopathIsDflt == false
                                             && fromZip.value 
                                             && fromZip.value.length > 0))
         from += ", MN";
      if (fromZip.cyclopathIsDflt == false && fromZip.value 
          && fromZip.value.length > 0)
	 from += " " + fromZip.value;
      
      var to = toAddr.value;
      if (toCity.cyclopathIsDflt == false && toCity.value 
          && toCity.value.length > 0)
	 to += ", " + toCity.value;
      if ((toCity.cyclopathIsDflt == false && toCity.value 
           && toCity.value.length > 0) || (toZip.cyclopathIsDflt == false
                                           && toZip.value 
                                           && toZip.value.length > 0))
         to += ", MN";
      if (toZip.cyclopathIsDflt == false && toZip.value 
          && toZip.value.length > 0)
	 to += " " + toZip.value;

      params = params + "&from_addr=" + from + "&to_addr=" + to;
      anchor.href = Cyclopath.geowikiUrl + Cyclopath.routeDeepLink 
                    + "?" + params;
      return true;
   } else {
      anchor.href = "";
      return false;
   }
};
