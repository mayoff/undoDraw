//
//  ViewController.m
//  undoDraw
//
//  Created by Rob Mayoff on 2/6/13.
//  Copyright (c) 2013 Rob Mayoff. All rights reserved.
//

#import "ViewController.h"
#import "Canvas.h"
#import "CanvasControl.h"
#import "UIColor+contrastingColor.h"
#import <QuartzCore/QuartzCore.h>

@interface ViewController () <CanvasObserver>

@property (strong, nonatomic) IBOutletCollection(UIBarButtonItem) NSArray *colorButtonItems;
@property (nonatomic, strong) IBOutlet CanvasControl *canvasControl;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *undoItem;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *redoItem;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *saveItem;

@property (nonatomic, strong) Canvas *canvas;

@property (nonatomic, strong) UIImageView *snapshotView; // animated to indicate saving
@property (nonatomic) BOOL isSaving;

@end

@implementation ViewController {
    id _undoManagerCheckpointNotificationRegistration;
}

#pragma mark - Public API

- (void)dealloc {
    [self.canvas removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:_undoManagerCheckpointNotificationRegistration];
}

#pragma mark - UIResponder overrides

- (BOOL)canBecomeFirstResponder {
    return YES;
}

#pragma mark - UIViewController overrides

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initUndoManager];
    [self initCanvas];
    [self initColorButtonItems];
    [self updateColorButtonItemTitlesWithCurrentCanvasColor];
    [self initcanvasControl];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startObservingUndoCheckpoints];
    [self validateToolbarItems];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self resignFirstResponder];
    [self stopObservingUndoCheckpoints];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateCanvasSize];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return ((1 << toInterfaceOrientation) & [self supportedInterfaceOrientations]) != 0;
}

- (NSUInteger)supportedInterfaceOrientations {
    switch ([[UIDevice currentDevice] userInterfaceIdiom]) {
        case UIUserInterfaceIdiomPad:
            return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
        default:
            return UIInterfaceOrientationMaskPortrait;
    }
}

#pragma mark - Actions

- (IBAction)save:(id)sender {
    if (self.isSaving)
        return;
    self.isSaving = YES;
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    UIImage *snapshot = self.canvas.contentsForExport;
    [self showSavingStartedAnimationWithSnapshot:snapshot];
    UIImageWriteToSavedPhotosAlbum(snapshot, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (IBAction)colorButtonItemWasTapped:(UIBarButtonItem *)sender {
    UIColor *color = sender.tintColor;
    self.canvas.color = color;
    [self updateColorButtonItemTitlesWithCurrentCanvasColor];
}

#pragma mark - Toolbar item validation

- (void)validateToolbarItems {
    self.undoItem.enabled = self.undoManager.canUndo;
    self.redoItem.enabled = self.undoManager.canRedo;
    self.saveItem.enabled = self.undoManager.canUndo;
}

#pragma mark - Save implementation

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    self.isSaving = NO;
    [self showSavingFinishedAnimation];
    if (error) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"I couldn't save your drawing.  I received this error: %@", nil), error.localizedDescription];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Saving Failed", nil) message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"Keep Calm and Carry On", nil) otherButtonTitles:nil];
        [alert show];
    }
}

- (void)showSavingStartedAnimationWithSnapshot:(UIImage *)snapshot {
    UIImageView *view = [[UIImageView alloc] initWithImage:snapshot];
    self.snapshotView = view;
    view.center = [self.view convertPoint:self.canvasControl.center fromView:self.canvasControl.superview];
    [self.view addSubview:view];
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        CGAffineTransform transform = CGAffineTransformIdentity;
        transform = CGAffineTransformScale(transform, 1.1f, 1.1f);
        transform = CGAffineTransformRotate(transform, -M_PI / 16.0f);
        view.transform = transform;
    } completion:nil];
}

- (void)showSavingFinishedAnimation {
    UIView *view = self.snapshotView;
    self.snapshotView = nil;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        view.transform = CGAffineTransformScale(view.transform, 0.1, 0.1);
        view.alpha = 0;
    } completion:^(BOOL finished) {
        [view removeFromSuperview];
    }];
}

#pragma mark - Undo manager implementation

- (void)initUndoManager {
    // I want one undo action to cover an entire touch from begin to end, rather than each touch movement acting as a separate undoable action.  So I need to disable UIKit's automatic per-event undo grouping.
    self.undoManager.groupsByEvent = NO;
}

- (void)startObservingUndoCheckpoints {
    _undoManagerCheckpointNotificationRegistration = [[NSNotificationCenter defaultCenter] addObserverForName:NSUndoManagerCheckpointNotification object:self.undoManager queue:nil usingBlock:^(NSNotification *note) {
        [self validateToolbarItems];
    }];
}

- (void)stopObservingUndoCheckpoints {
    [[NSNotificationCenter defaultCenter] removeObserver:_undoManagerCheckpointNotificationRegistration];
}

#pragma mark - Canvas implementation

- (void)initCanvas {
    self.canvas = [[Canvas alloc] init];

    // [UIColor blackColor] returns a color in the UIDeviceWhiteColorSpace, but the black tint in the nib is in the UIDeviceRGBColorSpace.  Stupidly, -[UIColor isEqual:] does not recognize these as the same color.  So, to make the comparison in -updateColorButtonItemTitlesWithCurrentCanvasColor work, I carefully initialize the canvas color from a color button item.
    self.canvas.color = [self.colorButtonItems[0] tintColor];

    [self.canvas addObserver:self];
}

- (void)updateCanvasSize {
    self.canvas.size = self.canvasControl.bounds.size;
    self.canvas.scale = self.canvasControl.window.screen.scale;
    self.canvas.tileSize = 64.0f;
}

- (void)canvasDidResetContents:(Canvas *)canvas {
    [self.undoManager removeAllActions];
}

- (void)canvas:(Canvas *)canvas didChangeTileWithFrameValue:(NSValue *)frameValue {
    // Nothing to do.
}

#pragma mark - Canvas view implementation

- (void)initcanvasControl {
    self.canvasControl.canvas = self.canvas;
}

- (IBAction)touchDownInCanvasControl:(CanvasControl *)sender forEvent:(UIEvent *)event {
    [self.undoManager beginUndoGrouping];
    [self.canvas registerUndoWithUndoManager:self.undoManager];
    UITouch *touch = [event touchesForView:sender].anyObject;
    [self.canvas moveTo:[touch locationInView:self.canvasControl]];
}

- (IBAction)touchDragInCanvasControl:(CanvasControl *)sender forEvent:(UIEvent *)event {
    UITouch *touch = [event touchesForView:sender].anyObject;
    [self lineTo:[touch locationInView:sender]];
}

- (IBAction)touchUpInCanvasControl:(CanvasControl *)sender forEvent:(UIEvent *)event {
    UITouch *touch = [event touchesForView:sender].anyObject;
    [self lineTo:[touch locationInView:sender]];
    [self.undoManager endUndoGrouping];
}

- (IBAction)touchCancelInCanvasControl:(CanvasControl *)sender forEvent:(UIEvent *)event {
    [self.undoManager endUndoGrouping];
    [self.undoManager undo];

    // This should remove the redo action created by the undo manager when I just undid the effects of the cancelled touch.
    [self.undoManager beginUndoGrouping];
    [self.undoManager endUndoGrouping];
}

#pragma mark - Color button implementation

static NSString *const kSelectedColorTitle = @"✔";
static NSString *const kUnselectedColorTitle = @"   ";

- (void)initColorButtonItems {
    NSSet *possibleTitles = [NSSet setWithArray:@[ kSelectedColorTitle, kUnselectedColorTitle ]];
    for (UIBarButtonItem *item in self.colorButtonItems) {
        item.possibleTitles = possibleTitles;
        NSDictionary *tribs = @{
                 UITextAttributeFont: [UIFont systemFontOfSize:24],
                 UITextAttributeTextColor: [item.tintColor contrastingColor]
         };
        [item setTitleTextAttributes:tribs forState:UIControlStateNormal];
    }
}

- (void)updateColorButtonItemTitlesWithCurrentCanvasColor {
    UIColor *color = self.canvas.color;
    for (UIBarButtonItem *item in self.colorButtonItems) {
        item.title = [item.tintColor isEqual:color] ? kSelectedColorTitle : kUnselectedColorTitle;
    }
}

#pragma mark - Implementation details

- (void)lineTo:(CGPoint)point {
    // Prevent Core Animation from automatically animating the tile updates with a fade.
    [CATransaction begin]; {
        [CATransaction setDisableActions:YES];
        [self.canvas lineTo:point];
    } [CATransaction commit];
}

@end
