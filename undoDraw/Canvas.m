//
//  Canvas.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "Canvas.h"
#import "DqdObserverSet.h"

@interface Canvas ()

@property (nonatomic, strong) NSMutableDictionary *cachedTileContents;

@end

static CGRect scaleRect(CGRect rect, CGFloat scale) {
    rect.origin.x *= scale;
    rect.origin.y *= scale;
    rect.size.width *= scale;
    rect.size.height *= scale;
    return rect;
}

static CGImageRef createImageInBitmapContextRect(CGContextRef gc, CGRect rect) {
    uint8_t *data = CGBitmapContextGetData(gc);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(gc);
    size_t bytesPerPixel = CGBitmapContextGetBitsPerPixel(gc) / 8;
    data += (size_t)rect.origin.x * bytesPerPixel + (size_t)rect.origin.y * bytesPerRow;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data,
        (size_t)rect.size.height * bytesPerRow, NULL);
    CGImageRef image = CGImageCreate((size_t)rect.size.width, (size_t)rect.size.height,
        CGBitmapContextGetBitsPerComponent(gc),
        CGBitmapContextGetBitsPerPixel(gc),
        CGBitmapContextGetBytesPerRow(gc),
        CGBitmapContextGetColorSpace(gc),
        CGBitmapContextGetBitmapInfo(gc),
        provider, NULL, NO, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    return image;
}

static void copyImageToBitmapContextRect(CGImageRef image, CGContextRef gc, CGRect rect) {
    CGContextSaveGState(gc); {
        CGContextConcatCTM(gc, CGAffineTransformInvert(CGContextGetCTM(gc)));
        CGContextDrawImage(gc, rect, image);
    } CGContextRestoreGState(gc);
}

static void fillBitmapContextRectWithWhite(CGContextRef gc, CGRect rect) {
    CGContextSaveGState(gc); {
        CGContextConcatCTM(gc, CGAffineTransformInvert(CGContextGetCTM(gc)));
        CGContextSetFillColorWithColor(gc, [UIColor whiteColor].CGColor);
        CGContextFillRect(gc, rect);
    } CGContextRestoreGState(gc);
}

@implementation Canvas {
    CGContextRef _context;
    CGPoint _penPoint;
    DqdObserverSet *_observers;
}

#pragma mark - Public API

- (id)init {
    if ((self = [super init])) {
        self.cachedTileContents = [NSMutableDictionary dictionary];
    }
    return self;
}

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

@synthesize tileSize = _tileSize;

- (void)setTileSize:(CGFloat)tileSize {
    _tileSize = tileSize;
    [self reset];
}

- (void)reset {
    if (_context) {
        CGContextRelease(_context);
        _context = NULL;
        [self.cachedTileContents removeAllObjects];
        _penPoint = CGPointZero;
        [_observers.proxy canvasDidResetContents:self];
    }
}

@synthesize color = _color;

- (void)moveTo:(CGPoint)point {
    _penPoint = point;
}

- (void)lineTo:(CGPoint)point {
    static CGFloat const kLineWidth = 16.0f;
    
    CGContextRef const gc = [self context];
    CGContextSetStrokeColorWithColor(gc, self.color.CGColor);
    CGContextSetLineCap(gc, kCGLineCapRound);
    CGContextSetLineWidth(gc, kLineWidth);
    CGPoint const points[] = { _penPoint, point };
    CGContextStrokeLineSegments(gc, points, sizeof points / sizeof points[0]);

    CGRect changedRect = CGRectMake(_penPoint.x, _penPoint.y, point.x - _penPoint.x, point.y - _penPoint.y);
    changedRect = CGRectInset(changedRect, -kLineWidth / 2, -kLineWidth / 2);
    changedRect = CGRectIntersection(changedRect, (CGRect){ CGPointZero, self.size });

    _penPoint = point;

    [self didChangeContentsInRect:changedRect];
}

- (CGImageRef)contentsOfTileWithFrameValue:(NSValue *)frameValue {
    CGImageRef contents = (__bridge CGImageRef)(self.cachedTileContents[frameValue]);
    if (!contents) {
        CGRect const scaledFrame = scaleRect(frameValue.CGRectValue, self.scale);
        contents = createImageInBitmapContextRect(_context, scaledFrame);
        self.cachedTileContents[frameValue] = (__bridge id)(contents);
        CGImageRelease(contents);
    }
    return contents;
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

- (void)registerUndoWithUndoManager:(NSUndoManager *)undoManager {
    __weak NSUndoManager *weakUndoManager = undoManager;
    NSDictionary *tileContentsDictionary = [self.cachedTileContents copy];
    [undoManager registerUndoWithTarget:self selector:@selector(undoByPerformingBlock:) object:^(Canvas *self){
        NSUndoManager *undoManager = weakUndoManager;
        [self registerUndoWithUndoManager:undoManager];
        [self restoreContentsWithTileContentsDictionary:tileContentsDictionary];
    }];
}

#pragma mark - Implementation details

static CGFloat roundDownToMultiple(CGFloat x, CGFloat factor) {
    return factor * floorf(x / factor);
}

static CGFloat roundUpToMultiple(CGFloat x, CGFloat factor) {
    return factor * ceilf(x / factor);
}

- (CGContextRef)context {
    if (!_context) {
        CGSize const size = self.size;
        CGFloat const scale = self.scale;
        CGFloat const tileSize = self.tileSize;
        size_t const width = (size_t)roundUpToMultiple(size.width * scale, tileSize);
        size_t const height = (size_t)roundUpToMultiple(size.height * scale, tileSize);
        CGColorSpaceRef const rgb = CGColorSpaceCreateDeviceRGB();
        _context = CGBitmapContextCreate(NULL, width, height, 8, 4 * width, rgb, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
        CGColorSpaceRelease(rgb);
        CGContextSetFillColorWithColor(_context, [UIColor whiteColor].CGColor);
        CGContextFillRect(_context, CGRectInfinite);
        CGContextTranslateCTM(_context, 0, (CGFloat)height);
        CGContextScaleCTM(_context, 1.0f, -1.0f);
        CGContextScaleCTM(_context, scale, scale);
    }
    return _context;
}

- (void)didChangeContentsInRect:(CGRect)changedRect {
    CGFloat const tileSize = self.tileSize;
    CGFloat const xMin = roundDownToMultiple(CGRectGetMinX(changedRect), tileSize);
    CGFloat const xMax = roundUpToMultiple(CGRectGetMaxX(changedRect), tileSize);
    CGFloat const yMin = roundDownToMultiple(CGRectGetMinY(changedRect), tileSize);
    CGFloat const yMax = roundUpToMultiple(CGRectGetMaxY(changedRect), tileSize);

    for (CGFloat y = yMin; y < yMax; y += tileSize) {
        for (CGFloat x = xMin; x < xMax; x += tileSize) {
            NSValue *frameValue = [NSValue valueWithCGRect:CGRectMake(x, y, tileSize, tileSize)];
            [self didChangeTileWithFrameValue:frameValue];
        }
    }
}

- (void)didChangeTileWithFrameValue:(NSValue *)frameValue {
    [self flushCachedContentsOfTileWithFrameValue:frameValue];
    [_observers.proxy canvas:self didChangeTileWithFrameValue:frameValue];
}

- (void)flushCachedContentsOfTileWithFrameValue:(NSValue *)frameValue {
    [self.cachedTileContents removeObjectForKey:frameValue];
}

- (void)undoByPerformingBlock:(void (^)(Canvas *self))block {
    block(self);
}

- (void)restoreContentsWithTileContentsDictionary:(NSDictionary *)dictionary {
    // There might be tiles in cachedTileContents that are not in dictionary.  Those need to be removed from cachedTileContents to "restore" them.  So I need to iterate over every key in either dictionary.
    NSMutableSet *keys = [NSMutableSet setWithArray:dictionary.allKeys];
    [keys addObjectsFromArray:self.cachedTileContents.allKeys];
    for (NSValue *frameValue in keys) {
        [self restoreTileWithFrameValue:frameValue contents:(__bridge CGImageRef)(dictionary[frameValue])];
    }
}

- (void)restoreTileWithFrameValue:(NSValue *)frameValue contents:(CGImageRef)contents {
    CGImageRef currentContents = (__bridge CGImageRef)(self.cachedTileContents[frameValue]);
    if (currentContents == contents)
        return;

    CGRect const scaledFrame = scaleRect(frameValue.CGRectValue, self.scale);
    if (contents) {
        copyImageToBitmapContextRect(contents, _context, scaledFrame);
        self.cachedTileContents[frameValue] = (__bridge id)(contents);
    } else {
        fillBitmapContextRectWithWhite(_context, scaledFrame);
        [self.cachedTileContents removeObjectForKey:frameValue];
    }
    [_observers.proxy canvas:self didChangeTileWithFrameValue:frameValue];
}

@end
