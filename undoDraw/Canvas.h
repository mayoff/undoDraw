//
//  Canvas.h
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CanvasObserver;

@interface Canvas : NSObject

// The size of my drawable area, in drawing units.  This is multiplied by my scale to determine my pixel dimensions.  When you set this, I send myself `reset`.
@property (nonatomic) CGSize size;

// I multiply this by my size to compute my pixel dimensions.  When you set this, I send myself `reset`.
@property (nonatomic) CGFloat scale;

// I throw away my existing contents and undo/redo stack.  I reset my pen point to `CGPointZero`.  I don't reset my `color`.
- (void)reset;

// The color I will paint with when you send me drawing messages.
@property (nonatomic, strong) UIColor *color;

// I move my pen to `point` without drawing a line from the prior pen point.
- (void)moveTo:(CGPoint)point;

// I move my pen to `point`, stroking a line from the prior pen point using my current `color`.
- (void)lineTo:(CGPoint)point;

// I return a CGImage of my current contents.  I cache this so it's cheap to call repeatedly.
- (CGImageRef)contents;

- (void)addObserver:(id<CanvasObserver>)observer;
- (void)removeObserver:(id<CanvasObserver>)observer;

@end

@protocol CanvasObserver <NSObject>

// I send this when I have modified my contents.
- (void)canvasDidChangeContents:(Canvas *)canvas;

@end
