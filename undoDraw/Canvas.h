//
//  Canvas.h
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CanvasObserver;

// I am a drawing surface.  My coordinate system is UIKit-style, with the origin at the upper left and Y coordinates increasing down.  I make my contents available as square tiles.

@interface Canvas : NSObject

// The size of my drawable area, in drawing units.  This is multiplied by my scale to determine my pixel dimensions.  When you change this, I send myself `reset`.
@property (nonatomic) CGSize size;

// I multiply this by my size to compute my pixel dimensions.  When you change this, I send myself `reset`.
@property (nonatomic) CGFloat scale;

// I make my contents available as a two-dimensional array of square tiles.  This is the size of each tile, in pixels.  When you change this, I send myself `reset`.
@property (nonatomic) CGFloat tileSize;

// I set my existing contents to solid white.  I reset my pen point to `CGPointZero`.  I don't reset my `color`.
- (void)reset;

// The color I will paint with when you send me drawing messages.
@property (nonatomic, strong) UIColor *color;

// Register an undo action that will restore my current contents.
- (void)registerUndoWithUndoManager:(NSUndoManager *)undoManager;

// I move my pen to `point` without drawing a line from the prior pen point.
- (void)moveTo:(CGPoint)point;

// I move my pen to `point`, stroking a line from the prior pen point using my current `color`.
- (void)lineTo:(CGPoint)point;

// I return the contents of the tile with the given frame (wrapped in an `NSValue`).  I cache the returned image, so calling this repeatedly with the same frame is cheap (if the contents of the tile hasn't changed between calls).  If I return NULL, you should treat it as a solid white image.
- (CGImageRef)contentsOfTileWithFrameValue:(NSValue *)frameValue;

// I return my entire contents, suitable for export.
- (UIImage *)contentsForExport;

- (void)addObserver:(id<CanvasObserver>)observer;
- (void)removeObserver:(id<CanvasObserver>)observer;

@end

@protocol CanvasObserver <NSObject>

// I send this when I reset my contents.
- (void)canvasDidResetContents:(Canvas *)canvas;

// I send this when I have modified the contents of a tile.  I provide the frame of the tile in my coordinate system, wrapped in an `NSValue`.
- (void)canvas:(Canvas *)canvas didChangeTileWithFrameValue:(NSValue *)frameValue;

@end
