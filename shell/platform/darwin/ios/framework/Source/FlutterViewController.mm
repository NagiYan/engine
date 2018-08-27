// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define FML_USED_ON_EMBEDDER

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController_Internal.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerCore.h"

#pragma mark -

@interface FlutterViewController ()
@property (nonatomic, retain) UIImageView *fakeSnapImgView;
@property (nonatomic, retain) UIImage *snapImage;
@property(nonatomic,retain) NSString *routeUrl;
@end

@implementation FlutterViewController {
    
}

#pragma mark - Manage and override all designated initializers

- (FlutterViewControllerCore*)flutterViewControllerCore {
    return [FlutterViewControllerCore sharedInstance:nil withFlutterViewController:nil];
}

- (instancetype)initWithProject:(FlutterDartProject*)projectOrNil
                        nibName:(NSString*)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
      // the projectOrNil param only set in the first FlutterViewController Instance
      [FlutterViewControllerCore sharedInstance:projectOrNil withFlutterViewController:self];
      [self performCommonViewControllerInitialization];
  }

  return self;
}

- (instancetype)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil {
  return [self initWithProject:nil nibName:nil bundle:nil];
}

- (instancetype)initWithCoder:(NSCoder*)aDecoder {
  return [self initWithProject:nil nibName:nil bundle:nil];
}

- (instancetype)init {
  return [self initWithProject:nil nibName:nil bundle:nil];
}

- (void)dealloc {
    NSLog(@"ASCFlutter FlutterViewController dealloc %@", self);
    [_fakeSnapImgView release];
    [_routeUrl release];
    [_snapImage release];
    [super dealloc];
}

#pragma mark - Common view controller initialization tasks

- (void)performCommonViewControllerInitialization {
  [[self flutterViewControllerCore] performCommonViewControllerInitialization];
}

- (shell::Shell&)shell {
    return [[self flutterViewControllerCore] shell];
}

- (void)setInitialRoute:(NSString*)route {
    self.routeUrl = route;
    [[self flutterViewControllerCore] setInitialRoute:self.routeUrl];
}

#pragma mark - Loading the view

- (void)loadView {
    self.view = self.fakeSnapImgView;
    [[self flutterViewControllerCore] installLaunchViewIfNecessary];
}

- (UIImageView*)fakeSnapImgView {
    if (!_fakeSnapImgView) {
        _fakeSnapImgView = [[[UIImageView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
        _fakeSnapImgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_fakeSnapImgView setBackgroundColor:[UIColor clearColor]];
    }
    return _fakeSnapImgView;
}

#pragma mark - UIViewController lifecycle notifications

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showFlutterView];
    [[self flutterViewControllerCore] viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self showFlutterView];
    [[self flutterViewControllerCore] viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self takeSnapShot];
    [self showSnapView];
    [super viewWillDisappear:animated];
    [[self flutterViewControllerCore] viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[self flutterViewControllerCore] viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning {
    // load and not visible
    if (self.isViewLoaded && !self.view.window) {
        // set the blank view
        self.view = nil;
        // free the core
        [FlutterViewControllerCore freeMemory];
    }
}

#pragma mark - Touch event handling
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches phase:UITouchPhaseBegan];
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches phase:UITouchPhaseMoved];
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches phase:UITouchPhaseEnded];
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches phase:UITouchPhaseCancelled];
}

#pragma mark - Handle view resizing
- (void)viewDidLayoutSubviews {
    [[self flutterViewControllerCore] viewDidLayoutSubviews];
}

- (void)viewSafeAreaInsetsDidChange {
    [[self flutterViewControllerCore] viewSafeAreaInsetsDidChange];
    [super viewSafeAreaInsetsDidChange];
}

#pragma mark - Status Bar touch event handling
- (void)handleStatusBarTouches:(UIEvent*)event {
    [[self flutterViewControllerCore] handleStatusBarTouches:event];
}

#pragma mark - FlutterBinaryMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {
    [[self flutterViewControllerCore] sendOnChannel:channel message:message];
}

- (void)sendOnChannel:(NSString*)channel
              message:(NSData*)message
          binaryReply:(FlutterBinaryReply)callback {
    [[self flutterViewControllerCore] sendOnChannel:channel message:message binaryReply:callback];
}

- (void)setMessageHandlerOnChannel:(NSString*)channel
              binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
    [[self flutterViewControllerCore] setMessageHandlerOnChannel:channel binaryMessageHandler:handler];
}

#pragma mark - FlutterTextureRegistry

- (int64_t)registerTexture:(NSObject<FlutterTexture>*)texture {
    return [[self flutterViewControllerCore] registerTexture:texture];
}

- (void)unregisterTexture:(int64_t)textureId {
    [[self flutterViewControllerCore] unregisterTexture:textureId];
}

- (void)textureFrameAvailable:(int64_t)textureId {
    [[self flutterViewControllerCore] textureFrameAvailable:textureId];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset {
    return [[self flutterViewControllerCore] lookupKeyForAsset:asset];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package {
    return [[self flutterViewControllerCore] lookupKeyForAsset:asset fromPackage:package];
}

- (id<FlutterPluginRegistry>)pluginRegistry {
    return self;
}

#pragma mark - FlutterPluginRegistry

- (NSObject<FlutterPluginRegistrar>*)registrarForPlugin:(NSString*)pluginKey {
    return [[self flutterViewControllerCore] registrarForPlugin:pluginKey];
}

- (BOOL)hasPlugin:(NSString*)pluginKey {
    return [[self flutterViewControllerCore] hasPlugin:pluginKey];
}

- (NSObject*)valuePublishedByPlugin:(NSString*)pluginKey {
    return [[self flutterViewControllerCore] valuePublishedByPlugin:pluginKey];
}

#pragma mark - tools

- (void)showFlutterView {
    // imageView -> flutterView
    if (![[[self flutterViewControllerCore] flutterView] nextResponder]) {
        NSLog(@"ASCFlutter FlutterViewController showFlutterView %@", self);
        self.view = [[self flutterViewControllerCore] flutterView];
        
        [[self flutterViewControllerCore] installLaunchViewIfNecessary];
        [self.navigationController setNavigationBarHidden:YES animated:NO];
        // flutterView
        [self.view setUserInteractionEnabled:YES];
        [[self flutterViewControllerCore] setInitialRoute:self.routeUrl];
    }
    else {
        NSLog(@"ASCFlutter FlutterViewController already showFlutterView %@", self);
    }
}

- (void)showSnapView {
    NSLog(@"ASCFlutter FlutterViewController showSnapView %@", self);
    // flutterView
    [self.view setUserInteractionEnabled:FALSE];
    [self.fakeSnapImgView setImage:self.snapImage];
    // flutterView -> imageView
    self.view = self.fakeSnapImgView;
    self.snapImage = NULL;
}

- (void)takeSnapShot {
    UIGraphicsBeginImageContextWithOptions([UIScreen mainScreen].bounds.size, YES, 0);
    [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:NO];
    self.snapImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
}

- (FlutterViewController*)flutterViewController:(UIView*)view {
    // Find the first view controller in the responder chain and see if it is a FlutterViewController.
    for (UIResponder* responder = view.nextResponder; responder != nil;
         responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            if ([responder isKindOfClass:[FlutterViewController class]]) {
                return reinterpret_cast<FlutterViewController*>(responder);
            } else {
                // Should only happen if a non-FlutterViewController tries to somehow (via dynamic class
                // resolution or reparenting) set a FlutterView as its view.
                return nil;
            }
        }
    }
    return nil;
}

@end
