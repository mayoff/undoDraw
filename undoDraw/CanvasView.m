//
//  CanvasView.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "CanvasView.h"
#import "Canvas.h"
#import <QuartzCore/QuartzCore.h>

@interface CanvasView () <CanvasObserver>
@end

@implementation CanvasView

#pragma mark - Public API

- (void)dealloc {
    [self disconnect];
}

@synthesize canvas = _canvas;

- (void)setCanvas:(Canvas *)canvas {
    [self disconnect];
    _canvas = canvas;
    [self connect];
}

#pragma mark - CanvasObserver protocol

- (void)canvasDidChangeContents:(Canvas *)canvas {
    // -[UIView setNeedsDisplay] is optimized to do nothing if the instance doesn't respond to `drawRect:`.  I have to send the message directly to my layer to bypass this optimization.
    [self.layer setNeedsDisplay];
}

#pragma mark - UIView overrides

- (void)displayLayer:(CALayer *)layer {
    layer.contents = (__bridge id)(self.canvas.contents);
}

#pragma mark - Implementation details

- (void)disconnect {
    [_canvas removeObserver:self];
}

- (void)connect {
    [_canvas addObserver:self];
}

@end
