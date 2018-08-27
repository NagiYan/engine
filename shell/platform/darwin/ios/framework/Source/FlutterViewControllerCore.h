// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_FLUTTERVIEWCONTROLLERCORE_H_
#define FLUTTER_FLUTTERVIEWCONTROLLERCORE_H_

#import <UIKit/UIKit.h>
#include <sys/cdefs.h>

#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterBinaryMessenger.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterDartProject.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterMacros.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterPlugin.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterTexture.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterView.h"

@interface FlutterViewControllerCore
    :NSObject <FlutterBinaryMessenger, FlutterTextureRegistry, FlutterPluginRegistry>

+ (instancetype)sharedInstance:(FlutterDartProject*)projectOrNil withFlutterViewController:(FlutterViewController*)viewController;

/**
 release the core
 */
+ (void)freeMemory;

- (instancetype)initWithProject:(FlutterDartProject*)projectOrNil andViewController:(FlutterViewController*)viewController;

- (void)handleStatusBarTouches:(UIEvent*)event;

/**
 Returns the file name for the given asset.
 The returned file name can be used to access the asset in the application's main bundle.

 - Parameter asset: The name of the asset. The name can be hierarchical.
 - Returns: the file name to be used for lookup in the main bundle.
 */
- (NSString*)lookupKeyForAsset:(NSString*)asset;

/**
 Returns the file name for the given asset which originates from the specified package.
 The returned file name can be used to access the asset in the application's main bundle.

 - Parameters:
   - asset: The name of the asset. The name can be hierarchical.
   - package: The name of the package from which the asset originates.
 - Returns: the file name to be used for lookup in the main bundle.
 */
- (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package;

/**
 Sets the first route that the Flutter app shows. The default is "/".

 - Parameter route: The name of the first route to show.
 */
- (void)setInitialRoute:(NSString*)route;

#pragma mark - proxy interface
- (id<FlutterPluginRegistry>)pluginRegistry;

- (void)performCommonViewControllerInitialization;

- (shell::Shell&)shell;

- (FlutterView*)flutterView;

- (void)installLaunchViewIfNecessary;

- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;
- (void)viewDidDisappear:(BOOL)animated;

- (void)viewDidLayoutSubviews;
- (void)viewSafeAreaInsetsDidChange;

- (void)dispatchTouches:(NSSet*)touches phase:(UITouchPhase)phase;
@end

#endif  // FLUTTER_FLUTTERVIEWCONTROLLERCORE_H_
