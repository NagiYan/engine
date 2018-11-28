// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define FML_USED_ON_EMBEDDER

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController_Internal.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerCore.h"

#pragma mark -

@interface FlutterViewController ()
@property (nonatomic, retain) UIView *snapView;
@end

@implementation FlutterViewController

#pragma mark - Manage and override all designated initializers

- (FlutterViewControllerCore*)flutterViewControllerCore {
    return [FlutterViewControllerCore sharedInstance:nil withFlutterViewController:nil];
}

- (instancetype)initWithProject:(FlutterDartProject*)projectOrNil
                        nibName:(NSString*)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
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
    //NSLog(@"ASCFlutter FlutterViewController dealloc %@", self);
    [_snapView release];
    
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
    [[self flutterViewControllerCore] setInitialRoute:route];
}

- (void)popRoute {
    [[self flutterViewControllerCore] popRoute];
}

- (void)pushRoute:(NSString*)route {
    [[self flutterViewControllerCore] pushRoute:route];
}

#pragma mark - Loading the view

- (void)loadView {
    self.view = self.snapView;
}

- (UIView*)snapView {
    if (!_snapView) {
        _snapView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _snapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_snapView setBackgroundColor:[UIColor whiteColor]];
        _snapView.tag = 19999;
    }
    return _snapView;
}

#pragma mark - UIViewController lifecycle notifications

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showFlutterView];
    [[self flutterViewControllerCore] viewWillAppear:animated];
    NSLog(@"[ASCFlutter] viewWillAppear %@", self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self showFlutterView];
    [[self flutterViewControllerCore] viewDidAppear:animated];
    NSLog(@"[ASCFlutter] viewDidAppear %@", self);
}

- (void)viewWillDisappear:(BOOL)animated {
    [self showSnapView];
    [super viewWillDisappear:animated];
    [[self flutterViewControllerCore] viewWillDisappear:animated];
    NSLog(@"[ASCFlutter] viewWillDisappear %@", self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[self flutterViewControllerCore] viewDidDisappear:animated];
    NSLog(@"[ASCFlutter] viewDidDisappear %@", self);
}

- (void)didReceiveMemoryWarning {
//    // load and not visible
//    if (self.isViewLoaded && !self.view.window) {
//        // set the blank view
//        self.view = nil;
//        // free the core
//        [FlutterViewControllerCore freeMemory];
//    }
    [super didReceiveMemoryWarning];
}
  
#pragma mark - Touch event handling
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches pointerDataChangeOverride:nullptr];
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches pointerDataChangeOverride:nullptr];
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches pointerDataChangeOverride:nullptr];
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
    [[self flutterViewControllerCore] dispatchTouches:touches pointerDataChangeOverride:nullptr];
}

#pragma mark - Handle view resizing
- (void)viewDidLayoutSubviews {
    [[self flutterViewControllerCore] viewDidLayoutSubviews];
    [super viewDidLayoutSubviews];
}

- (void)viewSafeAreaInsetsDidChange {
    [[self flutterViewControllerCore] viewSafeAreaInsetsDidChange];
    [super viewSafeAreaInsetsDidChange];
}

- (void)setFlutterViewDidRenderCallback:(void (^)(void))callback {
    [[self flutterViewControllerCore] setFlutterViewDidRenderCallback:callback];
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

- (void)didMoveToParentViewController:(UIViewController*)parent {
    if ([[[self flutterViewControllerCore] flutterView] superview]) {
        UIView* snap = [[[self flutterViewControllerCore] flutterView] viewWithTag:19999];
        snap.tag = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [snap removeFromSuperview];
        });
    }
}

- (void)showFlutterView {
    if (![[[self flutterViewControllerCore] flutterView] nextResponder]) {
        self.view = [[self flutterViewControllerCore] flutterView];
        [[self flutterViewControllerCore] updateHolder:self];
        [self.view setUserInteractionEnabled:YES];
        
        // 显示部分还是维持缩略图
        if (self.snapView) {
            [self.view addSubview:self.snapView];
            self.snapView.tag = 19999;
        }
    }
    else {
        // 移除缩略图
        if ([self.snapView superview] && self.snapView.tag  != 0) {
            [self.snapView removeFromSuperview];
        }
    }
}

- (void)showSnapView {
    // 移除缩略图
    if ([self.snapView superview]) {
        [self.snapView removeFromSuperview];
        self.view = self.snapView;
    }
    else {
        self.snapView = [self.view snapshotViewAfterScreenUpdates:NO];
        self.snapView.tag = 19999;
        [self.view setUserInteractionEnabled:FALSE];
        self.view = self.snapView;
    }
}

@end
