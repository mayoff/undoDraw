//
//  CanvasView.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "CanvasControl.h"
#import "Canvas.h"
#import <QuartzCore/QuartzCore.h>

@interface CanvasControl () <CanvasObserver>

// Each key is an NSValue wrapping a CGRect.  Each value is the corresponding layer.
@property (nonatomic, strong) NSMutableDictionary *tileLayers;

// Layers that are not currently being used to display a tile.
@property (nonatomic, strong) NSMutableArray *spareTileLayers;

@end

@implementation CanvasControl

#pragma mark - Public API

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self commonInit];
    }
    return self;
}

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

- (void)canvasDidResetContents:(Canvas *)canvas {
    [self removeAllTileLayers];

    // Canvas is documented to reset itself to solid white.
    self.backgroundColor = [UIColor whiteColor];
}

- (void)canvas:(Canvas *)canvas didChangeTileWithFrameValue:(NSValue *)frameValue {
    CALayer *const layer = [self tileLayerWithFrameValue:frameValue];
    layer.contents = (__bridge id)([canvas contentsOfTileWithFrameValue:frameValue]);
}

#pragma mark - Implementation details

- (void)commonInit {
    self.tileLayers = [NSMutableDictionary dictionary];
    self.spareTileLayers = [NSMutableArray array];
    // Canvas allows tiles to extend outside of its size.  I need to make sure the layers for those tiles get clipped.
    self.clipsToBounds = YES;
}

- (void)disconnect {
    [_canvas removeObserver:self];
}

- (void)connect {
    [_canvas addObserver:self];
    // Really I should be asking the canvas for each of its tile's contents, in case the canvas is not in its reset state.  But this is just a toy project, so fuck it.
    [self canvasDidResetContents:_canvas];
}

- (void)removeAllTileLayers {
    [self.tileLayers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        CALayer *const layer = obj;
        [layer removeFromSuperlayer];
        [self.spareTileLayers addObject:layer];
    }];
    [self.tileLayers removeAllObjects];
}

- (CALayer *)tileLayerWithFrameValue:(NSValue *)frameValue {
    CALayer *layer = self.tileLayers[frameValue];
    if (!layer) {
        layer = [CALayer layer];
        layer.backgroundColor = self.layer.backgroundColor;
        layer.frame = frameValue.CGRectValue;
        [self.layer addSublayer:layer];
        self.tileLayers[frameValue] = layer;
    }
    return layer;
}

@end
