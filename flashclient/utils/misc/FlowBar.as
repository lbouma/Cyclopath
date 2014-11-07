/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Modified version of the ToolBar class from Adobe.
// It can be found in the flex directory under the following path:
// flex/frameworks/projects/framework/src/mx/controls/richTextEditorClasses/

////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2005-2007 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

package utils.misc {

    import mx.controls.VRule;
    import mx.core.Container;
    import mx.core.EdgeMetrics;
    import mx.core.IUIComponent;
    
    //--------------------------------------
    //  Styles
    //--------------------------------------
    
    /**
     *  Number of pixels between children in the horizontal direction.
     *  The default value is 8.
     */
    [Style(name="horizontalGap", type="Number", format="Length", inherit="no")]
    
    /**
     *  Number of pixels between children in the vertical direction.
     *  The default value is 8.
     */
    [Style(name="verticalGap", type="Number", format="Length", inherit="no")]
    
    
    /**
     *  @private
     *  The FlowBar container lays out its children in a single horizontal row.
     *  If the width of the container is less than the measured width, the children 
     *  wrap to the next line.
     *  While wrapping, any VRule controls (separators) at the end of a row or the 
     *  beginning of a row are not drawn.
     * 
     *  <p><b>MXML Syntax</b></p>
     * 
     *  <p>The <code>&lt;mx:FlowBar&gt;</code> tag inherits all the properties
     *  of its parent classes but adds no new ones.</p>
     *
     *  <pre>
     *  &lt;mx:FlowBar
     *    ...
     *      <i>child tags</i>
     *    ...
     *  /&gt;
     *  </pre>
     */
    public class FlowBar extends Container {

        //include "../../core/Version.as";
    
        [Bindable] public var over_row_limit:Boolean;
        
        public var expanded:Boolean;
    
        //--------------------------------------------------------------------------
        //
        //  Constructor
        //
        //--------------------------------------------------------------------------
    
        /**
         *  Constructor.
         */
        public function FlowBar()
        {
            super();
        }
    
        //--------------------------------------------------------------------------
        //
        //  Overridden methods
        //
        //--------------------------------------------------------------------------
    
        /**
         *  @private
         */
        override protected function measure():void
        {
            super.measure();
    
            var minWidth:Number = 0;
            var minHeight:Number = 0;
    
            var preferredWidth:Number = 0;
            var preferredHeight:Number = 0;
    
            var n:int = numChildren;
            var numGaps:int = -1;
            for (var i:int = 0; i < n; i++)
            {
                var child:IUIComponent = IUIComponent(getChildAt(i));
                if (!child.includeInLayout)
                    continue;
    
                numGaps++;
                var wPref:Number = child.getExplicitOrMeasuredWidth();
                var hPref:Number = child.getExplicitOrMeasuredHeight();
    
                minWidth = Math.max(minWidth, wPref);
                minHeight = Math.max(minHeight, hPref);
                preferredWidth += wPref;
            }
    
            var vm:EdgeMetrics = viewMetricsAndPadding;
            var wPadding:Number = vm.left + vm.right +
                                                      numGaps * getStyle("horizontalGap");
            var hPadding:Number = vm.top + vm.bottom;
    
            measuredMinWidth = minWidth + wPadding;
            measuredMinHeight = minHeight + hPadding;
    
            measuredWidth = preferredWidth + wPadding;
            measuredHeight = minHeight + hPadding;
        }
    
        /**
         *  @private
         */
        override protected function updateDisplayList(unscaledWidth:Number,
                                                      unscaledHeight:Number):void
        {
            super.updateDisplayList(unscaledWidth, unscaledHeight);
            
            var vm:EdgeMetrics = viewMetricsAndPadding;
            
            var horizontalGap:Number = getStyle("horizontalGap");
            var verticalGap:Number = getStyle("verticalGap");
           
            var xPos:Number = vm.left;
            var yPos:Number = vm.top;
            var maxYPos:Number = 0;
            
            var n:int = numChildren;
            var child:IUIComponent;
            var lastChild:IUIComponent;
            var childWidth:int;
            var childHeight:int;
            // TODO: Maximum number of lines that display without "more" link
            // is currently hardcoded. Should we consider changing this?
            var maxLines:int = 3;
            var lines:int = 0;
            
            var xEnd:Number = unscaledWidth - vm.right;
    
            for (var i:int = 0; i < n; i++)
            {
                child = IUIComponent(getChildAt(i));
    
                if (!child.includeInLayout)
                    continue;
    
                childWidth = child.getExplicitOrMeasuredWidth();
                childHeight = child.getExplicitOrMeasuredHeight();
                    
                // Start a new row?
                if (xPos + childWidth > xEnd && xPos != vm.left)
                {
                    lines ++;
                    if (lines >= maxLines) {
                       this.over_row_limit = true;
                       if(!this.expanded)
                          break;
                    }
                    else {
                       this.over_row_limit = false;
                    }
                    yPos = maxYPos + verticalGap;
                    xPos = vm.left;
                    
                    if (child is VRule)
                    {
                        child.setActualSize(0, 0);
                        child.move(xPos, yPos);
                        continue;
                    }
                    else if (lastChild is VRule)
                        lastChild.setActualSize(0, 0);
                }
    
                child.setActualSize(childWidth, childHeight)
                child.move(xPos, yPos);
                lastChild = child;
    
                maxYPos = Math.max(maxYPos, yPos + childHeight);
                xPos += (childWidth + horizontalGap);
            }
            maxYPos += vm.bottom;
    
            if (height != maxYPos)
                height = maxYPos;
        }

    }
}

