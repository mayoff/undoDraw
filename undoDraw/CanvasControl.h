//
//  CanvasView.h
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Canvas;

@interface CanvasControl : UIControl

@property (nonatomic, strong) Canvas *canvas;

@end
