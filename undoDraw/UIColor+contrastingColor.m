//
//  UIColor+contrastingColor.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "UIColor+contrastingColor.h"

@implementation UIColor (contrastingColor)

- (UIColor *)contrastingColor {
    CGFloat hue, saturation, brightness, alpha;
    if (![self getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        NSLog(@"%s unable to handle %@", __func__, self);
        return [UIColor blackColor];
    }

    return (brightness > 0.5f && saturation < 0.7f) ? [UIColor blackColor] : [UIColor whiteColor];
}

@end
