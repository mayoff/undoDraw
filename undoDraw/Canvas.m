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

static CGFloat roundDownToMultiple(CGFloat x, CGFloat factor) {
    return factor * floorf(x / factor);
}

static CGFloat roundUpToMultiple(CGFloat x, CGFloat factor) {
    return factor * ceilf(x / factor);
}

static CGRect scaleRect(CGRect rect, CGFloat scale) {
    rect.origin.x *= scale;
    rect.origin.y *= scale;
    rect.size.width *= scale;
    rect.size.height *= scale;
    return rect;
}

static void dataProviderReleaseDataWithFree(void *info, void const *data, size_t size) {
    free((void *)data);
}

static CGImageRef createImageInBitmapContextRect(CGContextRef gc, CGRect rect) {
    // We can't just create a CGDataProvider that uses gc's bitmap data directly, because CGImage does not make a private copy of its data when you create it, or even when you draw it to a context!  Even though the Quartz 2D Programming Guide says a CGImage is immutable, I've found that changing the data that you originally passed to its CGDataProvider will change the contents of the image.  So I have to make a copy of the bitmap data here and use that copy to create the data provider.

    size_t const sourceBytesPerRow = CGBitmapContextGetBytesPerRow(gc);
    size_t const bytesPerPixel = CGBitmapContextGetBitsPerPixel(gc) / 8;
    size_t const offset = (size_t)rect.origin.x * bytesPerPixel + (size_t)rect.origin.y * sourceBytesPerRow;
    uint8_t const *const sourceData = (uint8_t const *)CGBitmapContextGetData(gc) + offset;

    size_t const copiedBytesPerRow = bytesPerPixel * (size_t)rect.size.width;
    size_t const copiedRowCount = (size_t)rect.size.height;
    size_t const copiedBytesLength = copiedBytesPerRow * copiedRowCount;
    uint8_t *const copiedData = malloc(copiedBytesLength);
    for (size_t row = 0; row < copiedRowCount; ++row) {
        memcpy(copiedData + row * copiedBytesPerRow, sourceData + row * sourceBytesPerRow, copiedBytesPerRow);
    }

    CGDataProviderRef const provider = CGDataProviderCreateWithData(NULL, copiedData, copiedBytesLength, &dataProviderReleaseDataWithFree);
    CGImageRef const image = CGImageCreate((size_t)rect.size.width, (size_t)rect.size.height,
        CGBitmapContextGetBitsPerComponent(gc),
        CGBitmapContextGetBitsPerPixel(gc),
        copiedBytesPerRow,
        CGBitmapContextGetColorSpace(gc),
        CGBitmapContextGetBitmapInfo(gc),
        provider, NULL, NO, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);

    return image;
}

static void copyImageToBitmapContextRect(CGImageRef image, CGContextRef gc, CGRect rect) {
    // There are two ways to get access to an image's pixel data using public APIs.
    // - You can use `CGImageGetDataProvider` and then `CGDataProviderCopyData`.  In my testing, this creates a new copy of the data every time.
    // - You can draw the image into a bitmap context.
    // I could get at the image's underlying data directly by storing a reference to the data in the cache, alongside the image (by using a custom wrapper object as the cache value).  Or I could attach the reference directly to the image using `objc_setAssociatedObject`.  For now, I'm just drawing the image into my existing bitmap context as that is easiest to implement.  Note that I need to unflip the CTM or the image will be drawn upside-down.
    CGContextSaveGState(gc); {
        CGContextTranslateCTM(gc, rect.origin.x, rect.origin.y + rect.size.height);
        CGContextScaleCTM(gc, 1, -1);
        CGContextDrawImage(gc, CGRectMake(0, 0, rect.size.width, rect.size.height), image);
    } CGContextRestoreGState(gc);
}

static void fillBitmapContextRectWithWhite(CGContextRef gc, CGRect rect) {
    CGContextSaveGState(gc); {
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
    if (contents == (__bridge CGImageRef)([NSNull null])) {
        // This tile was undone to an empty state.  Return nil instead of creating a solid white tile.
        contents = nil;
    } else if (!contents) {
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

- (CGContextRef)context {
    if (!_context) {
        CGSize const size = self.size;
        CGFloat const scale = self.scale;
        CGFloat const tileSize = self.tileSize;
        size_t const width = (size_t)roundUpToMultiple(size.width * scale, tileSize);
        size_t const height = (size_t)roundUpToMultiple(size.height * scale, tileSize);
        CGColorSpaceRef const rgb = CGColorSpaceCreateDeviceRGB();
        _context = CGBitmapContextCreate(NULL, width, height, 8, 4 * width, rgb, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Host);
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
    CGFloat const tileSizeInUnits = self.tileSize / self.scale;
    CGFloat const xMin = roundDownToMultiple(CGRectGetMinX(changedRect), tileSizeInUnits);
    CGFloat const xMax = roundUpToMultiple(CGRectGetMaxX(changedRect), tileSizeInUnits);
    CGFloat const yMin = roundDownToMultiple(CGRectGetMinY(changedRect), tileSizeInUnits);
    CGFloat const yMax = roundUpToMultiple(CGRectGetMaxY(changedRect), tileSizeInUnits);

    for (CGFloat y = yMin; y < yMax; y += tileSizeInUnits) {
        for (CGFloat x = xMin; x < xMax; x += tileSizeInUnits) {
            NSValue *frameValue = [NSValue valueWithCGRect:CGRectMake(x, y, tileSizeInUnits, tileSizeInUnits)];
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
        CGImageRef contents = (__bridge CGImageRef)dictionary[frameValue];
        if (contents == (__bridge CGImageRef)([NSNull null])) {
            contents = NULL;
        }
        [self restoreTileWithFrameValue:frameValue contents:contents];
    }
}

- (void)restoreTileWithFrameValue:(NSValue *)frameValue contents:(CGImageRef)contents {
    CGImageRef currentContents = (__bridge CGImageRef)(self.cachedTileContents[frameValue]);
    if (currentContents == (__bridge CGImageRef)([NSNull null]))
        currentContents = NULL;

    if (currentContents == contents)
        return;

    if (contents) {
        copyImageToBitmapContextRect(contents, _context, frameValue.CGRectValue);
    } else {
        fillBitmapContextRectWithWhite(_context, frameValue.CGRectValue);
        // Store NSNull instead of removing the object.  That way, `contentsOfTileWithFrameValue:` can just return `nil` instead of creating a solid white tile image.
        contents = (__bridge CGImageRef)([NSNull null]);
    }
    self.cachedTileContents[frameValue] = (__bridge id)(contents);
    [_observers.proxy canvas:self didChangeTileWithFrameValue:frameValue];
}

@end
