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

// The size of my drawable area, in drawing units.  This is multiplied by my scale to determine my pixel dimensions.  When you set this, I send myself `reset`.
@property (nonatomic) CGSize size;

// I multiply this by my size to compute my pixel dimensions.  When you set this, I send myself `reset`.
@property (nonatomic) CGFloat scale;

// I make my contents available as a two-dimensional array of square tiles.  This is the size of each tile, in pixels.
@property (nonatomic) CGFloat tileSize;

// I throw away my existing contents and undo/redo stack, and set my contents to solid white.  I reset my pen point to `CGPointZero`.  I don't reset my `color`.
- (void)reset;

// The color I will paint with when you send me drawing messages.
@property (nonatomic, strong) UIColor *color;

// I move my pen to `point` without drawing a line from the prior pen point.
- (void)moveTo:(CGPoint)point;

// I move my pen to `point`, stroking a line from the prior pen point using my current `color`.
- (void)lineTo:(CGPoint)point;

// I return the contents of the tile with the give frame.  I cache the returned image, so calling this repeatedly with the same frame is cheap (if the contents of the tile hasn't changed between calls).
- (CGImageRef)contentsOfTileWithFrame:(CGRect)frame;

- (void)addObserver:(id<CanvasObserver>)observer;
- (void)removeObserver:(id<CanvasObserver>)observer;

@end

@protocol CanvasObserver <NSObject>

// I send this when I reset my contents.
- (void)canvasDidResetContents:(Canvas *)canvas;

// I send this when I have modified the contents of a tile.  I provide the frame of the tile in my coordinate system.
- (void)canvas:(Canvas *)canvas didChangeTileWithFrame:(CGRect)frame;

@end
