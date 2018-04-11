//	MIT License
//	Copyright (c) 2017 William W. Dickinson
//
//  Invert Mountain tool
//	An ImageJ macro that finds local brightness maxima within an image,
// 	determines the maximal area around each in which brightness decreases,
//	then inverts the brightness in those regions about a pre-determined
//	inflection point.
//
//	Tested with ImageJ 1.50b
//
//	===========
//
//	Instructions
//	-----------
//	First, install the macro through use of the Plugins>Macros>Install… menu
//	option.
//
//	Second, select the image to be processed. The macro will act on the current
//	selection within the image, or the entire image if no selection is made.
//
//	Third, execute the macro through the Plugins>Macros>Invert Mountain Tool
//	menu option. This will generate a window with several parameters available
//	for modification (see below for descriptions).
//
//	Finally, after adjusting all parameters to the desired values, press the OK
//	button, and the macro will act on the image.
//	
//	===========
//
//	Parameters
//	-----------
//	
//	Inflection Point:
//	The brightness value that the inversion occurs about. Correlates with the
//	value at which the brightness-vs-layer number relationship inverts.
//
//	Maxima Noise Tolerance:
//	Minimum amount by which the brightness of a maxima must exceed the
//	surrounding area. Must be >= 0.
//
//	Exclude Edge Maxima:
//	If 'true', a peak is only accepted if it is separated by two qualified
//	valleys. If 'false', a peak is also accepted if separated by one qualified
//	valley and by a border.
//
//	Flood Noise Tolerance:
//	Maximum value by which the brightness of neighboring pixels may exceed the
//	brightness of the pixel being examined. Prevents noise in the image from
//	prematurely terminating the mountain.
//
//	Sanity Threshold:
//	Pixels above this brightness value are automatically included in the mask.
//	Prevents exclusion of "obviously inverted" points due to greater noise
//	than expected. For analysis of layered materials, this should be above
//	substrate value by a brightness corresponding to at least one layer.
//
//	Fill Holes:
//	If 'true', areas fully enclosed within a region that has been identified as
//	part of a mountain will be added to the region before inversion occurs.

//	===========

var stack = newArray(100000);	//	Array of pixels to be evaluated
var stackSize;			//	Current pixel in the stack being looked at
var mask;			//	Array showing which pixels are within a mountain
var width;			//	Pixel width of the image
var height;			//	Pixel height of image

macro "Invert Mountain Tool" {
	Dialog.create("Invert Mountains");
	Dialog.addNumber("Inflection Point:", 70.0);
	Dialog.addNumber("Maxima Noise Tolerance:", 10);
	Dialog.addCheckbox("Exclude Edge Maxima", true);
	Dialog.addNumber("Flood Noise Tolerance:", 0.0);
	Dialog.addNumber("Sanity Threshold:", 110.0);
	Dialog.addCheckbox("Fill Holes", true);
	Dialog.show();

	inflectionPoint = Dialog.getNumber();
	maximaTolerance = Dialog.getNumber();
	exclude = Dialog.getCheckbox();
	floodTolerance = Dialog.getNumber();
	sanityThreshold = Dialog.getNumber();
	fillHoles = Dialog.getCheckbox();
	options = "";
	if (exclude) options = options + " exclude";

	currentImage = getImageID;
	width = getWidth;
	height = getHeight;
	mask = newArray(width * height);
	Array.fill(mask, 0);
  
	run("Find Maxima...", "noise="+ maximaTolerance +" output=List"+options);
	  
	setBatchMode(true);
	roiManager("reset");

	stackSize = 0;
	for(j=0; j < nResults; j++) {
	    x = getResult("X", j);
		y = getResult("Y", j);
		push(x,y);
	}
	
	findMountains(floodTolerance, sanityThreshold);
	
	newImage("MountainAreas", "8-bit", width, height, 1);
	selectImage("MountainAreas");

	for(i=0; i<width; i++){
		for(j=0; j<height; j++){
			if (mask[i+j*width]==1){
				setPixel(i,j,1);
			}				
		}
	}
	
	run("Make Binary");
	if (fillHoles)
		run("Fill Holes");
	run("Create Selection");
	roiManager("add");
	selectImage(currentImage);
	roiManager("select", 0);

	invertMountains(inflectionPoint);

	if (isOpen("Results")) { 
		selectWindow("Results"); 
		run("Close"); 
	}	 
	
}

//	Determines the extent of the region around each of a list of pixels where
//	brightness decreases from that pixel. It checks each pixel to the left,
//	sequentially, for lower brightness than its neighbor and adds them to the
//	mask if this is true. It then checks those to the right, repeating the
//	process. It then checks pixels above, below, and diagonally adjacent to
//	each of the pixels on the line and adds them to the list of pixels to be
//	examined in this fashion.
//
//	Parameters:
//	------------
//
//	floodTolerance:
//	Amount of variation above the threshold value allowed before determining
//	that an inflection point has been reached.
//
//	sanityThreshold:
//	Any pixel above this brightness value is always included in the mask.
//	Prevents exclusion of "obviously inverted" points due to greater noise
//	than expected. Should be at least 1 layer step above substrate value.

function findMountains(floodTolerance, sanityThreshold) {
	autoUpdate(false);
	numScanned = 0;
	while(true) {   
		coordinates = pop();
		if (coordinates ==-1) return;
		numScanned++;
		x = coordinates&0xffff;
		y = coordinates>>16;
		x1 = x;
		x2 = x;
		
		mask[x+y*width] = true;
		
		limit = getPixel(x,y) + floodTolerance;
		
		// prevent tolerance from creeping upward during scan-line changes
		if (inMask(x,y-1)) 
			limit = minOf(limit, getPixel(x,y-1) + floodTolerance);
		if (inMask(x+1,y-1))
			limit = minOf(limit, getPixel(x+1,y-1) + floodTolerance);
		if (inMask(x-1,y-1))
			limit = minOf(limit, getPixel(x-1,y-1) + floodTolerance);
		if (inMask(x,y+1))
			limit = minOf(limit, getPixel(x,y+1) + floodTolerance);
		if (inMask(x+1,y+1))
			limit = minOf(limit, getPixel(x+1,y+1) + floodTolerance);
		if (inMask(x-1,y+1))
			limit = minOf(limit, getPixel(x-1,y+1) + floodTolerance);
			
		// Checks pixels to left of the this one
		i = x-1;
		while (!inMask(i,y) && (getPixel(i,y)<=limit || getPixel(i,y)>sanityThreshold) && i>1) {
			mask[i+y*width] = true;
			x1 = i;
			i--;
			limit = minOf(getPixel(i,y) + floodTolerance, limit);
		}
		
		//Checks pixels to the right of this one
		limit = getPixel(x,y) + floodTolerance;
		i = x+1;
		while(!inMask(i,y) && (getPixel(i,y)<=limit || getPixel(i,y)>sanityThreshold) && i<(width-1)) {
			mask[i+y*width] = true;
			x2 = i;
			i++;
			limit = minOf(getPixel(i,y) + floodTolerance, limit);
		}

		// find pixels above this line
		if (y>1){
			for (i=x1; i<=x2; i++) { 
				limit = getPixel(i,y) + floodTolerance;
				if (!inMask(i,y-1) && getPixel(i,y-1)<=limit) {
					push(i, y-1);}
				if (i>1 && !inMask(i+1,y-1) && getPixel(i+1,y-1)<=limit) {
					push(i+1, y-1);}
				if (i<(width-1) && !inMask(i-1,y-1) && getPixel(i-1,y-1)<=limit) {
					push(i-1, y-1);}
			}
		}

		// find pixels below this line
		if (y<(height-1)){
			for (i=x1; i<=x2; i++) { 
				limit = getPixel(i,y) + floodTolerance;
				if (!inMask(i,y+1) && getPixel(i,y+1)<=limit) {
					push(i, y+1);}
				if (i>1 && !inMask(i+1,y+1) && getPixel(i+1,y+1)<=limit) {
					push(i+1, y+1);}
				if (i<(width-1) && !inMask(i-1,y+1) && getPixel(i-1,y+1)<=limit) {
					push(i-1, y+1);}
			}
		}
	}
}        

//	Adds pixel to stack
function push(x, y) {
	if (x>0 && x<(width-1) && y>0 && y<(height-1)){
		stackSize++;
		stack[stackSize-1] = x + y<<16;
	}
}

//	Removes pixel from stack
function pop() {
	if (stackSize==0)
		return -1;
	else {
		value = stack[stackSize-1];
		stackSize--;
		return value;
	}
}

//	Checks if a pixel is in the mask. Returns false if outside the image border
function inMask(x,y) {
	if (x>0 && x<width && y>0 && y<height)
		value = mask[x+y*width];
	else
		value = false;
	return value;
}

//	Inverts selected region about the given inflection point. The "Invert" tool
//	will not make values below 0, instead shifting them higher until the lowest
//	is above 0. The offset value determined below accounts for this and permits
//	negative brightness values.
function invertMountains(inflectionPoint) {
	getStatistics(area, mean, min, max, std, hist1);

	run("Invert");
	getStatistics(area, mean, min2, max2, std, hist1);
	
	offset = (min - min2) + (2*inflectionPoint - (max+min));

	run("Add...", "value="+offset);
}