//
//  Canvas.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "Canvas.h"
#import "DqdObserverSet.h"

@implementation Canvas {
    CGContextRef _context;
    CGImageRef _contents;
    CGPoint _penPoint;
    DqdObserverSet *_observers;
}

#pragma mark - Public API

- (void)dealloc {
    [self reset];
}

@synthesize size = _size;

- (void)setSize:(CGSize)size {
    _size = size;
    [self reset];
}

@synthesize scale = _scale;

- (void)setScale:(CGFloat)scale {
    _scale = scale;
    [self reset];
}

- (void)reset {
    CGContextRelease(_context);
    _context = NULL;
    [self flushCachedContents];
    _penPoint = CGPointZero;
}

@synthesize color = _color;

- (void)moveTo:(CGPoint)point {
    _penPoint = point;
}

- (void)lineTo:(CGPoint)point {
    CGContextRef const gc = [self context];
    CGContextSetStrokeColorWithColor(gc, self.color.CGColor);
    CGContextSetLineCap(gc, kCGLineCapRound);
    CGContextSetLineWidth(gc, 16);
    CGPoint const points[] = { _penPoint, point };
    CGContextStrokeLineSegments(gc, points, sizeof points / sizeof points[0]);
    _penPoint = point;
    [self didChangeContents];
}

- (CGImageRef)contents {
    if (_context && !_contents) {
        _contents = CGBitmapContextCreateImage(_context);
    }
    return _contents;
}

- (void)addObserver:(id<CanvasObserver>)observer {
    if (!_observers) {
        _observers = [[DqdObserverSet alloc] initWithProtocol:@protocol(CanvasObserver)];
    }
    [_observers addObserver:observer];
}

- (void)removeObserver:(id<CanvasObserver>)observer {
    [_observers removeObserver:observer];
}

#pragma mark - Implementation details

- (CGContextRef)context {
    if (!_context) {
        CGSize const size = self.size;
        CGFloat const scale = self.scale;
        size_t const width = (size_t)ceilf(size.width * scale);
        size_t const height = (size_t)ceilf(size.height * scale);
        CGColorSpaceRef const rgb = CGColorSpaceCreateDeviceRGB();
        _context = CGBitmapContextCreate(NULL, width, height, 8, 4 * width, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
        CGColorSpaceRelease(rgb);
        CGContextTranslateCTM(_context, 0, (CGFloat)height);
        CGContextScaleCTM(_context, 1.0f, -1.0f);
    }
    return _context;
}

- (void)didChangeContents {
    [self flushCachedContents];
    [_observers.proxy canvasDidChangeContents:self];
}

- (void)flushCachedContents {
    CGImageRelease(_contents);
    _contents = NULL;
}

@end
