// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define FML_USED_ON_EMBEDDER

#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController_Internal.h"

#include <memory>

#include "flutter/fml/memory/weak_ptr.h"
#include "flutter/fml/message_loop.h"
#include "flutter/fml/platform/darwin/platform_version.h"
#include "flutter/fml/platform/darwin/scoped_nsobject.h"
#include "flutter/shell/common/thread_host.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterDartProject_Internal.h"
//#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterObservatoryPublisher.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformPlugin.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputDelegate.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/platform_message_response_darwin.h"
#include "flutter/shell/platform/darwin/ios/platform_view_ios.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerCore.h"

#pragma mark - FlutterViewControllerCore

@interface FlutterViewControllerCore () <FlutterTextInputDelegate>
@property(nonatomic, readonly) NSMutableDictionary* pluginPublications;
@property(nonatomic, retain) FlutterViewController *viewController;
@end

@interface FlutterViewControllerRegistrar : NSObject <FlutterPluginRegistrar>
- (instancetype)initWithPlugin:(NSString*)pluginKey
     flutterViewControllerCore:(FlutterViewControllerCore*)flutterViewControllerCore;
@end

@implementation FlutterViewControllerCore {
    fml::scoped_nsobject<FlutterDartProject> _dartProject;
    shell::ThreadHost _threadHost;
    std::unique_ptr<shell::Shell> _shell;
    std::unique_ptr<fml::WeakPtrFactory<FlutterViewController>> _weakFactory;
    
    // Channels
    fml::scoped_nsobject<FlutterPlatformPlugin> _platformPlugin;
    fml::scoped_nsobject<FlutterTextInputPlugin> _textInputPlugin;
    fml::scoped_nsobject<FlutterMethodChannel> _localizationChannel;
    fml::scoped_nsobject<FlutterMethodChannel> _navigationChannel;
    fml::scoped_nsobject<FlutterMethodChannel> _platformChannel;
    fml::scoped_nsobject<FlutterMethodChannel> _textInputChannel;
    fml::scoped_nsobject<FlutterBasicMessageChannel> _lifecycleChannel;
    fml::scoped_nsobject<FlutterBasicMessageChannel> _systemChannel;
    fml::scoped_nsobject<FlutterBasicMessageChannel> _settingsChannel;
    
    // We keep a separate reference to this and create it ahead of time because we want to be able to
    // setup a shell along with its platform view before the view has to appear.
    fml::scoped_nsobject<FlutterView> _flutterView;
    fml::scoped_nsobject<UIView> _launchView;
    fml::ScopedBlock<void (^)(void)> _flutterViewRenderedCallback;
    UIInterfaceOrientationMask _orientationPreferences;
    UIStatusBarStyle _statusBarStyle;
    blink::ViewportMetrics _viewportMetrics;
    int64_t _nextTextureId;
    BOOL _initialized;
    BOOL _gpuOperationDisabled;
    
//    fml::scoped_nsobject<FlutterObservatoryPublisher> _publisher;
}

#pragma mark - Manage and override all designated initializers

static FlutterViewControllerCore *_flutterViewControllerCore;
static dispatch_once_t onceToken;
static dispatch_once_t onceTokenEngine;

+ (instancetype)sharedInstance:(FlutterDartProject*)projectOrNil withFlutterViewController:(FlutterViewController*)viewController {
    if(_flutterViewControllerCore) {
        if (viewController)
            _flutterViewControllerCore.viewController = viewController;
        return _flutterViewControllerCore;
    }
    
    dispatch_once(&onceToken, ^{
        _flutterViewControllerCore = [[FlutterViewControllerCore alloc] initWithProject:projectOrNil andViewController:viewController];
    });
    
    return _flutterViewControllerCore;
}

- (instancetype)initWithProject:(FlutterDartProject*)projectOrNil andViewController:(FlutterViewController*)viewController {
    self = [super init];
    if (self) {
        _weakFactory = std::make_unique<fml::WeakPtrFactory<FlutterViewController>>(viewController);
        if (projectOrNil == nil)
            _dartProject.reset([[FlutterDartProject alloc] init]);
        else
            _dartProject.reset([projectOrNil retain]);
        self.viewController = viewController;
        [self performCommonViewControllerInitialization];
    }
    return self;
}

- (FlutterView*)flutterView {
    return _flutterView.get();
}

- (void)updateHolder:(FlutterViewController*)viewController {
    self.viewController = viewController;
}

+ (void)freeMemory {
    if (_flutterViewControllerCore) {
        [[FlutterViewControllerCore sharedInstance:nil withFlutterViewController:nil] clean];
        onceToken = 0;
        onceTokenEngine = 0;
        [_flutterViewControllerCore release];
        _flutterViewControllerCore = nil;
    }
}

- (void)clean {
    _localizationChannel.reset();
    _platformChannel.reset();
    _textInputChannel.reset();
    _lifecycleChannel.reset();
    _systemChannel.reset();
    _settingsChannel.reset();
    _navigationChannel.reset();
    self.viewController = nil;
    [self iosPlatformView]->GetTextInputPlugin().get().textInputDelegate = nil;
    _shell = nil;
}

#pragma mark - Common view controller initialization tasks

- (void)performCommonViewControllerInitialization {
    if (_initialized)
        return;
    
    _initialized = YES;
    
//    _publisher.reset([[FlutterObservatoryPublisher alloc] init]);
    _orientationPreferences = UIInterfaceOrientationMaskAll;
    _statusBarStyle = UIStatusBarStyleDefault;
    
    if ([self setupShell]) {
        [self setupChannels];
        [self setupNotificationCenterObservers];
        
        _pluginPublications = [NSMutableDictionary new];
    }
}

- (shell::Shell&)shell {
    FML_DCHECK(_shell);
    return *_shell;
}

- (fml::WeakPtr<shell::PlatformViewIOS>)iosPlatformView {
    FML_DCHECK(_shell);
    return _shell->GetPlatformView();
}

- (BOOL)setupShell {
    FML_DCHECK(_shell == nullptr);
    
    static size_t shell_count = 1;
    
    auto threadLabel = [NSString stringWithFormat:@"io.flutter.%zu", shell_count++];
    
    _threadHost = {
        threadLabel.UTF8String,  // label
        shell::ThreadHost::Type::UI | shell::ThreadHost::Type::GPU | shell::ThreadHost::Type::IO};
    
    // The current thread will be used as the platform thread. Ensure that the message loop is
    // initialized.
    fml::MessageLoop::EnsureInitializedForCurrentThread();
    
    blink::TaskRunners task_runners(threadLabel.UTF8String,                          // label
                                    fml::MessageLoop::GetCurrent().GetTaskRunner(),  // platform
                                    _threadHost.gpu_thread->GetTaskRunner(),         // gpu
                                    _threadHost.ui_thread->GetTaskRunner(),          // ui
                                    _threadHost.io_thread->GetTaskRunner()           // io
                                    );
    
    FlutterView* fv = [[FlutterView alloc] init];
    fv.multipleTouchEnabled = YES;
    fv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _flutterView.reset(fv);
    
    // Lambda captures by pointers to ObjC objects are fine here because the create call is
    // synchronous.
    shell::Shell::CreateCallback<shell::PlatformView> on_create_platform_view =
    [flutter_view_controller = self.viewController, flutter_view = _flutterView.get()](shell::Shell& shell) {
        auto platform_view_ios = std::make_unique<shell::PlatformViewIOS>(
                                                                          shell,                    // delegate
                                                                          shell.GetTaskRunners(),   // task runners
                                                                          flutter_view_controller,  // flutter view controller owner
                                                                          flutter_view              // flutter view owner
                                                                          );
        return platform_view_ios;
    };
    
    shell::Shell::CreateCallback<shell::Rasterizer> on_create_rasterizer = [](shell::Shell& shell) {
        return std::make_unique<shell::Rasterizer>(shell.GetTaskRunners());
    };
    
    // Create the shell.
    _shell = shell::Shell::Create(std::move(task_runners),  //
                                  [_dartProject settings],  //
                                  on_create_platform_view,  //
                                  on_create_rasterizer      //
                                  );
    
    if (!_shell) {
        FML_LOG(ERROR) << "Could not setup a shell to run the Dart application.";
        return false;
    }
    
    return true;
}

- (void)setupChannels {
    _localizationChannel.reset([[FlutterMethodChannel alloc]
                                initWithName:@"flutter/localization"
                                binaryMessenger:self
                                codec:[FlutterJSONMethodCodec sharedInstance]]);
    
    _navigationChannel.reset([[FlutterMethodChannel alloc]
                              initWithName:@"flutter/navigation"
                              binaryMessenger:self
                              codec:[FlutterJSONMethodCodec sharedInstance]]);
    
    _platformChannel.reset([[FlutterMethodChannel alloc]
                            initWithName:@"flutter/platform"
                            binaryMessenger:self
                            codec:[FlutterJSONMethodCodec sharedInstance]]);
    
    _textInputChannel.reset([[FlutterMethodChannel alloc]
                             initWithName:@"flutter/textinput"
                             binaryMessenger:self
                             codec:[FlutterJSONMethodCodec sharedInstance]]);
    
    _lifecycleChannel.reset([[FlutterBasicMessageChannel alloc]
                             initWithName:@"flutter/lifecycle"
                             binaryMessenger:self
                             codec:[FlutterStringCodec sharedInstance]]);
    
    _systemChannel.reset([[FlutterBasicMessageChannel alloc]
                          initWithName:@"flutter/system"
                          binaryMessenger:self
                          codec:[FlutterJSONMessageCodec sharedInstance]]);
    
    _settingsChannel.reset([[FlutterBasicMessageChannel alloc]
                            initWithName:@"flutter/settings"
                            binaryMessenger:self
                            codec:[FlutterJSONMessageCodec sharedInstance]]);
    
    _platformPlugin.reset([[FlutterPlatformPlugin alloc] initWithViewController:_weakFactory->GetWeakPtr()]);
    
    [_platformChannel.get() setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [_platformPlugin.get() handleMethodCall:call result:result];
    }];
    
    _textInputPlugin.reset([[FlutterTextInputPlugin alloc] init]);
    _textInputPlugin.get().textInputDelegate = self;
    [_textInputChannel.get() setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [_textInputPlugin.get() handleMethodCall:call result:result];
    }];
    static_cast<shell::PlatformViewIOS*>(_shell->GetPlatformView().get())
    ->SetTextInputPlugin(_textInputPlugin);
}

- (void)setupNotificationCenterObservers {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(onOrientationPreferencesUpdated:)
                   name:@(shell::kOrientationUpdateNotificationName)
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onPreferredStatusBarStyleUpdated:)
                   name:@(shell::kOverlayStyleUpdateNotificationName)
                 object:nil];
    
    [center addObserver:self
               selector:@selector(applicationBecameActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(applicationWillResignActive:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(applicationDidEnterBackground:)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(applicationWillEnterForeground:)
                   name:UIApplicationWillEnterForegroundNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(keyboardWillChangeFrame:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(keyboardWillBeHidden:)
                   name:UIKeyboardWillHideNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onLocaleUpdated:)
                   name:NSCurrentLocaleDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilityVoiceOverStatusChanged
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilitySwitchControlStatusDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilitySpeakScreenStatusDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilityInvertColorsStatusDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilityReduceMotionStatusDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onAccessibilityStatusChanged:)
                   name:UIAccessibilityBoldTextStatusDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onMemoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onUserSettingsChanged:)
                   name:UIContentSizeCategoryDidChangeNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(onLocaleChange:)
                   name:@"kASCLocalChangeNotification"
                 object:nil];
    
    [center addObserver:self
               selector:@selector(keyboardWillBeHidden:)
                   name:@"kASCKeyboardHideNotification"
                 object:nil];
}

- (void)setInitialRoute:(NSString*)route {
    [_navigationChannel.get() invokeMethod:@"setInitialRoute" arguments:route];
}

- (void)popRoute {
    [_navigationChannel.get() invokeMethod:@"popRoute" arguments:nil];
}

- (void)pushRoute:(NSString*)route {
    [_navigationChannel.get() invokeMethod:@"pushRoute" arguments:route];
}

#pragma mark - Managing launch views
- (void)installLaunchViewIfNecessary {
    // Show the launch screen view again on top of the FlutterView if available.
    // This launch screen view will be removed once the first Flutter frame is rendered.
    [_launchView.get() removeFromSuperview];
    _launchView.reset();
    NSString* launchStoryboardName =
    [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UILaunchStoryboardName"];
    if (launchStoryboardName && !self.viewController.isBeingPresented && !self.viewController.isMovingToParentViewController) {
        UIViewController* launchViewController =
        [[UIStoryboard storyboardWithName:launchStoryboardName bundle:nil]
         instantiateInitialViewController];
        _launchView.reset([launchViewController.view retain]);
        _launchView.get().frame = self.flutterView.bounds;
        _launchView.get().autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.flutterView addSubview:_launchView.get()];
    }
}

- (void)removeLaunchViewIfPresent {
    if (!_launchView) {
        return;
    }
    
    [UIView animateWithDuration:0.2
                     animations:^{
                         _launchView.get().alpha = 0;
                     }
                     completion:^(BOOL finished) {
                         [_launchView.get() removeFromSuperview];
                         _launchView.reset();
                     }];
}

- (void)installLaunchViewCallback {
    if (!_shell || !_launchView) {
        return;
    }
    auto weak_platform_view = _shell->GetPlatformView();
    if (!weak_platform_view) {
        return;
    }
    __unsafe_unretained auto weak_flutter_view_controller = self;
    // This is on the platform thread.
    weak_platform_view->SetNextFrameCallback(
                                             [weak_platform_view, weak_flutter_view_controller,
                                              task_runner = _shell->GetTaskRunners().GetPlatformTaskRunner()]() {
                                                 // This is on the GPU thread.
                                                 task_runner->PostTask([weak_platform_view, weak_flutter_view_controller]() {
                                                     // We check if the weak platform view is alive. If it is alive, then the view controller
                                                     // also has to be alive since the view controller owns the platform view via the shell
                                                     // association. Thus, we are not convinced that the unsafe unretained weak object is in
                                                     // fact alive.
                                                     if (weak_platform_view) {
                                                         [weak_flutter_view_controller removeLaunchViewIfPresent];
                                                     }
                                                 });
                                             });
}

- (void)setFlutterViewDidRenderCallback:(void (^)(void))callback {
    _flutterViewRenderedCallback.reset(callback, fml::OwnershipPolicy::Retain);
}

#pragma mark - Surface creation and teardown updates

- (void)surfaceUpdated:(BOOL)appeared {
    // NotifyCreated/NotifyDestroyed are synchronous and require hops between the UI and GPU thread.
    if (appeared) {
        //    [self installLaunchViewCallback];
        _shell->GetPlatformView()->NotifyCreated();
        
    } else {
        _shell->GetPlatformView()->NotifyDestroyed();
    }
}

#pragma mark - UIViewController lifecycle notifications

- (void)viewWillAppear:(BOOL)animated {
    TRACE_EVENT0("flutter", "viewWillAppear");
    
    dispatch_once(&onceTokenEngine, ^{
        // Launch the Dart application with the inferred run configuration.
        _shell->GetTaskRunners().GetUITaskRunner()->PostTask(
                                                             fml::MakeCopyable([engine = _shell->GetEngine(),                   //
                                                                                config = [_dartProject.get() runConfiguration]  //
                                                                                ]() mutable {
            if (engine) {
                auto result = engine->Run(std::move(config));
                if (result == shell::Engine::RunStatus::Failure) {
                    FML_LOG(ERROR) << "Could not launch engine with configuration.";
                }
            }
        }));
    });
    
    // Only recreate surface on subsequent appearances when viewport metrics are known.
    // First time surface creation is done on viewDidLayoutSubviews.
    
    if (_viewportMetrics.physical_width)
        [self surfaceUpdated:YES];
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.inactive"];
}

- (void)viewDidAppear:(BOOL)animated {
    TRACE_EVENT0("flutter", "viewDidAppear");
//      [self onLocaleUpdated:nil];
    [self onUserSettingsChanged:nil];
    [self onAccessibilityStatusChanged:nil];
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.resumed"];
}

- (void)viewWillDisappear:(BOOL)animated {
    TRACE_EVENT0("flutter", "viewWillDisappear");
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.inactive"];
}

- (void)viewDidDisappear:(BOOL)animated {
    TRACE_EVENT0("flutter", "viewDidDisappear");
    if (![_flutterView nextResponder]) {
        [self surfaceUpdated:NO];
        [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.paused"];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pluginPublications release];
    [super dealloc];
}

#pragma mark - Application lifecycle notifications

- (void)applicationBecameActive:(NSNotification*)notification {
    TRACE_EVENT0("flutter", "applicationBecameActive");
    [self enableMessageLoop:true forTaskRunner:@"io.flutter.gpu"];
    [self enableMessageLoop:true forTaskRunner:@"io.flutter.io"];
    if (_viewportMetrics.physical_width)
        [self surfaceUpdated:YES];
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.resumed"];
    _gpuOperationDisabled = FALSE;
}

- (void)applicationWillResignActive:(NSNotification*)notification {
    TRACE_EVENT0("flutter", "applicationWillResignActive");
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.inactive"];
    [self disableGPUOperation];
}

- (void)applicationDidEnterBackground:(NSNotification*)notification {
    TRACE_EVENT0("flutter", "applicationDidEnterBackground");
    [self disableGPUOperation];
}

- (void)applicationWillEnterForeground:(NSNotification*)notification {
    TRACE_EVENT0("flutter", "applicationWillEnterForeground");
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.inactive"];
}

- (void)disableGPUOperation{
    if(_gpuOperationDisabled == TRUE)
        return;
    [self surfaceUpdated:NO];
    [_lifecycleChannel.get() sendMessage:@"AppLifecycleState.paused"];
    [self enableMessageLoop:false forTaskRunner:@"io.flutter.io"];
    [self enableMessageLoop:false forTaskRunner:@"io.flutter.gpu"];
    _gpuOperationDisabled = TRUE;
    //暂时通过延时来等待GL操作结束(否则进入后台后的GL操作会闪退)
    int i = 0;
    while(i++ < 6){
        NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
        [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
}

- (void)enableMessageLoop:(bool)isEnable forTaskRunner:(NSString *)aTaskRunnerId{
    if( [@"io.flutter.io" caseInsensitiveCompare:aTaskRunnerId] == NSOrderedSame ) {
        fml::TaskRunner *taskRunner = (fml::TaskRunner *)_shell->GetTaskRunners().GetIOTaskRunner().get();
        taskRunner->EnableMessageLoop(isEnable);
    }
    if( [@"io.flutter.ui" caseInsensitiveCompare:aTaskRunnerId] == NSOrderedSame ) {
        fml::TaskRunner *taskRunner = (fml::TaskRunner *)_shell->GetTaskRunners().GetUITaskRunner().get();
        taskRunner->EnableMessageLoop(isEnable);
    }
    if( [@"io.flutter.gpu" caseInsensitiveCompare:aTaskRunnerId] == NSOrderedSame ) {
        fml::TaskRunner *taskRunner = (fml::TaskRunner *)_shell->GetTaskRunners().GetGPUTaskRunner().get();
        taskRunner->EnableMessageLoop(isEnable);
    }
    if( [@"io.flutter.platform" caseInsensitiveCompare:aTaskRunnerId] == NSOrderedSame ) {
        fml::TaskRunner *taskRunner = (fml::TaskRunner *)_shell->GetTaskRunners().GetPlatformTaskRunner().get();
        taskRunner->EnableMessageLoop(isEnable);
    }
}

#pragma mark - Touch event handling
static blink::PointerData::Change PointerDataChangeFromUITouchPhase(UITouchPhase phase) {
    switch (phase) {
        case UITouchPhaseBegan:
            return blink::PointerData::Change::kDown;
        case UITouchPhaseMoved:
        case UITouchPhaseStationary:
            // There is no EVENT_TYPE_POINTER_STATIONARY. So we just pass a move type
            // with the same coordinates
            return blink::PointerData::Change::kMove;
        case UITouchPhaseEnded:
            return blink::PointerData::Change::kUp;
        case UITouchPhaseCancelled:
            return blink::PointerData::Change::kCancel;
    }
    
    return blink::PointerData::Change::kCancel;
}

static blink::PointerData::DeviceKind DeviceKindFromTouchType(UITouch* touch) {
    if (@available(iOS 9, *)) {
        switch (touch.type) {
            case UITouchTypeDirect:
            case UITouchTypeIndirect:
                return blink::PointerData::DeviceKind::kTouch;
            case UITouchTypeStylus:
                return blink::PointerData::DeviceKind::kStylus;
        }
    } else {
        return blink::PointerData::DeviceKind::kTouch;
    }
    
    return blink::PointerData::DeviceKind::kTouch;
}

- (void)dispatchTouches:(NSSet*)touches pointerDataChangeOverride:(blink::PointerData::Change*)overridden_change {

    if (![_flutterView nextResponder])
        return;
    
    // Note: we cannot rely on touch.phase, since in some cases, e.g.,
    // handleStatusBarTouches, we synthesize touches from existing events.
    //
    // TODO(cbracken) consider creating out own class with the touch fields we
    // need.
    const CGFloat scale = [UIScreen mainScreen].scale;
    auto packet = std::make_unique<blink::PointerDataPacket>(touches.count);
    
    size_t pointer_index = 0;

    for (UITouch* touch in touches) {
        CGPoint windowCoordinates = [touch locationInView:self.flutterView];
        
        blink::PointerData pointer_data;
        pointer_data.Clear();
        
        constexpr int kMicrosecondsPerSecond = 1000 * 1000;
        pointer_data.time_stamp = touch.timestamp * kMicrosecondsPerSecond;
        
        pointer_data.change = overridden_change != nullptr
        ? *overridden_change
        : PointerDataChangeFromUITouchPhase(touch.phase);

        
        pointer_data.kind = DeviceKindFromTouchType(touch);
        
        pointer_data.device = reinterpret_cast<int64_t>(touch);
        
        pointer_data.physical_x = windowCoordinates.x * scale;
        pointer_data.physical_y = windowCoordinates.y * scale;
        
        // pressure_min is always 0.0
        if (@available(iOS 9, *)) {
            // These properties were introduced in iOS 9.0.
            pointer_data.pressure = touch.force;
            pointer_data.pressure_max = touch.maximumPossibleForce;
        } else {
            pointer_data.pressure = 1.0;
            pointer_data.pressure_max = 1.0;
        }
        
        // These properties were introduced in iOS 8.0
        pointer_data.radius_major = touch.majorRadius;
        pointer_data.radius_min = touch.majorRadius - touch.majorRadiusTolerance;
        pointer_data.radius_max = touch.majorRadius + touch.majorRadiusTolerance;
        
        // These properties were introduced in iOS 9.1
        if (@available(iOS 9.1, *)) {
            // iOS Documentation: altitudeAngle
            // A value of 0 radians indicates that the stylus is parallel to the surface. The value of
            // this property is Pi/2 when the stylus is perpendicular to the surface.
            //
            // PointerData Documentation: tilt
            // The angle of the stylus, in radians in the range:
            //    0 <= tilt <= pi/2
            // giving the angle of the axis of the stylus, relative to the axis perpendicular to the input
            // surface (thus 0.0 indicates the stylus is orthogonal to the plane of the input surface,
            // while pi/2 indicates that the stylus is flat on that surface).
            //
            // Discussion:
            // The ranges are the same. Origins are swapped.
            pointer_data.tilt = M_PI_2 - touch.altitudeAngle;
            
            // iOS Documentation: azimuthAngleInView:
            // With the tip of the stylus touching the screen, the value of this property is 0 radians
            // when the cap end of the stylus (that is, the end opposite of the tip) points along the
            // positive x axis of the device's screen. The azimuth angle increases as the user swings the
            // cap end of the stylus in a clockwise direction around the tip.
            //
            // PointerData Documentation: orientation
            // The angle of the stylus, in radians in the range:
            //    -pi < orientation <= pi
            // giving the angle of the axis of the stylus projected onto the input surface, relative to
            // the positive y-axis of that surface (thus 0.0 indicates the stylus, if projected onto that
            // surface, would go from the contact point vertically up in the positive y-axis direction, pi
            // would indicate that the stylus would go down in the negative y-axis direction; pi/4 would
            // indicate that the stylus goes up and to the right, -pi/2 would indicate that the stylus
            // goes to the left, etc).
            //
            // Discussion:
            // Sweep direction is the same. Phase of M_PI_2.
            pointer_data.orientation = [touch azimuthAngleInView:nil] - M_PI_2;
        }
        
        packet->SetPointerData(pointer_index++, pointer_data);
    }
    
    _shell->GetTaskRunners().GetUITaskRunner()->PostTask(
                                                         fml::MakeCopyable([engine = _shell->GetEngine(), packet = std::move(packet)] {
        if (engine) {
            engine->DispatchPointerDataPacket(*packet);
        }
    }));
}

#pragma mark - Handle view resizing

- (void)updateViewportMetrics {
    _shell->GetTaskRunners().GetUITaskRunner()->PostTask(
                                                         [engine = _shell->GetEngine(), metrics = _viewportMetrics]() {
                                                             if (engine) {
                                                                 engine->SetViewportMetrics(std::move(metrics));
                                                             }
                                                         });
}

- (CGFloat)statusBarPadding {
    UIScreen* screen = self.flutterView.window.screen;
    CGRect statusFrame = [UIApplication sharedApplication].statusBarFrame;
    CGRect viewFrame = [self.flutterView convertRect:self.flutterView.bounds toCoordinateSpace:screen.coordinateSpace];
    CGRect intersection = CGRectIntersection(statusFrame, viewFrame);
    return CGRectIsNull(intersection) ? 0.0 : intersection.size.height;
}

- (void)viewDidLayoutSubviews {
    
    if (![_flutterView nextResponder])
        return;
    
    CGSize viewSize = self.flutterView.bounds.size;
    CGFloat scale = [UIScreen mainScreen].scale;
    
    // First time since creation that the dimensions of its view is known.
    bool firstViewBoundsUpdate = !_viewportMetrics.physical_width;
    _viewportMetrics.device_pixel_ratio = scale;
    _viewportMetrics.physical_width = viewSize.width * scale;
    _viewportMetrics.physical_height = viewSize.height * scale;
    
    [self updateViewportPadding:NO];
    [self updateViewportMetrics];
    
    // This must run after updateViewportMetrics so that the surface creation tasks are queued after
    // the viewport metrics update tasks.
    if (firstViewBoundsUpdate)
        [self surfaceUpdated:YES];
}

- (void)viewSafeAreaInsetsDidChange {
    [self updateViewportPadding:YES];
    [self updateViewportMetrics];
}

// Updates _viewportMetrics physical padding.
//
// Viewport padding represents the iOS safe area insets.
- (void)updateViewportPadding:(BOOL)filter {
    
    if (![_flutterView nextResponder])
        return;
    
    CGFloat scale = [UIScreen mainScreen].scale;
    if (@available(iOS 11, *)) {
        // 解决从后台进入前台导致错误下移 横屏可能会有问题
        if (!filter) {
            CGFloat change = self.flutterView.safeAreaInsets.top * scale - _viewportMetrics.physical_padding_top;
            if (_viewportMetrics.physical_padding_top == 0 || (change != 88 && change != 132)) {
                _viewportMetrics.physical_padding_top = self.flutterView.safeAreaInsets.top * scale;
            }
        }
        _viewportMetrics.physical_padding_left = self.flutterView.safeAreaInsets.left * scale;
        _viewportMetrics.physical_padding_right = self.flutterView.safeAreaInsets.right * scale;
        _viewportMetrics.physical_padding_bottom = self.flutterView.safeAreaInsets.bottom * scale;
    } else {
        _viewportMetrics.physical_padding_top = [self statusBarPadding] * scale;
    }
}

#pragma mark - Keyboard events

- (void)keyboardWillChangeFrame:(NSNotification*)notification {
    if (![_flutterView nextResponder])
        return;
    
    NSDictionary* info = [notification userInfo];
    CGFloat bottom = CGRectGetHeight([[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue]);
    CGFloat scale = [UIScreen mainScreen].scale;
    
    // The keyboard is treated as an inset since we want to effectively reduce the window size by the
    // keyboard height. We also eliminate any bottom safe-area padding since they keyboard 'consumes'
    // the home indicator widget.
    _viewportMetrics.physical_view_inset_bottom = bottom * scale;
    _viewportMetrics.physical_padding_bottom = 0;
    [self updateViewportMetrics];
}

- (void)keyboardWillBeHidden:(NSNotification*)notification {
    if (![_flutterView nextResponder])
        return;
    
    CGFloat scale = [UIScreen mainScreen].scale;
    _viewportMetrics.physical_view_inset_bottom = 0;
    
    // Restore any safe area padding that the keyboard had consumed.
    if (@available(iOS 11, *)) {
        _viewportMetrics.physical_padding_bottom = self.flutterView.safeAreaInsets.bottom * scale;
    } else {
        _viewportMetrics.physical_padding_top = [self statusBarPadding] * scale;
    }
    [self updateViewportMetrics];
}

#pragma mark - Text input delegate

- (void)updateEditingClient:(int)client withState:(NSDictionary*)state {
    if (![_flutterView nextResponder])
        return;
    
    [_textInputChannel.get() invokeMethod:@"TextInputClient.updateEditingState"
                                arguments:@[ @(client), state ]];
}

- (void)performAction:(FlutterTextInputAction)action withClient:(int)client {
    NSString* actionString;
    switch (action) {
        case FlutterTextInputActionUnspecified:
            // Where did the term "unspecified" come from? iOS has a "default" and Android
            // has "unspecified." These 2 terms seem to mean the same thing but we need
            // to pick just one. "unspecified" was chosen because "default" is often a
            // reserved word in languages with switch statements (dart, java, etc).
            actionString = @"TextInputAction.unspecified";
            break;
        case FlutterTextInputActionDone:
            actionString = @"TextInputAction.done";
            break;
        case FlutterTextInputActionGo:
            actionString = @"TextInputAction.go";
            break;
        case FlutterTextInputActionSend:
            actionString = @"TextInputAction.send";
            break;
        case FlutterTextInputActionSearch:
            actionString = @"TextInputAction.search";
            break;
        case FlutterTextInputActionNext:
            actionString = @"TextInputAction.next";
            break;
        case FlutterTextInputActionContinue:
            actionString = @"TextInputAction.continue";
            break;
        case FlutterTextInputActionJoin:
            actionString = @"TextInputAction.join";
            break;
        case FlutterTextInputActionRoute:
            actionString = @"TextInputAction.route";
            break;
        case FlutterTextInputActionEmergencyCall:
            actionString = @"TextInputAction.emergencyCall";
            break;
        case FlutterTextInputActionNewline:
            actionString = @"TextInputAction.newline";
            break;
    }
    [_textInputChannel.get() invokeMethod:@"TextInputClient.performAction"
                                arguments:@[ @(client), actionString ]];
}

#pragma mark - Orientation updates

- (void)onOrientationPreferencesUpdated:(NSNotification*)notification {
    // Notifications may not be on the iOS UI thread
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary* info = notification.userInfo;
        
        NSNumber* update = info[@(shell::kOrientationUpdateNotificationKey)];
        
        if (update == nil) {
            return;
        }
        
        NSUInteger new_preferences = update.unsignedIntegerValue;
        
        if (new_preferences != _orientationPreferences) {
            _orientationPreferences = new_preferences;
            [UIViewController attemptRotationToDeviceOrientation];
        }
    });
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return _orientationPreferences;
}

#pragma mark - Accessibility

- (void)onAccessibilityStatusChanged:(NSNotification*)notification {
    auto platformView = _shell->GetPlatformView();
    int32_t flags = 0;
    if (UIAccessibilityIsInvertColorsEnabled())
        flags ^= static_cast<int32_t>(blink::AccessibilityFeatureFlag::kInvertColors);
    if (UIAccessibilityIsReduceMotionEnabled())
        flags ^= static_cast<int32_t>(blink::AccessibilityFeatureFlag::kReduceMotion);
    if (UIAccessibilityIsBoldTextEnabled())
        flags ^= static_cast<int32_t>(blink::AccessibilityFeatureFlag::kBoldText);
    
#if TARGET_OS_SIMULATOR
    // There doesn't appear to be any way to determine whether the accessibility
    // inspector is enabled on the simulator. We conservatively always turn on the
    // accessibility bridge in the simulator, but never assistive technology.
    platformView->SetSemanticsEnabled(true);
    platformView->SetAccessibilityFeatures(flags);
#else
    bool enabled = UIAccessibilityIsVoiceOverRunning() || UIAccessibilityIsSwitchControlRunning();
    if (UIAccessibilityIsVoiceOverRunning() || UIAccessibilityIsSwitchControlRunning())
        flags ^= static_cast<int32_t>(blink::AccessibilityFeatureFlag::kAccessibleNavigation);
    platformView->SetSemanticsEnabled(enabled || UIAccessibilityIsSpeakScreenEnabled());
    platformView->SetAccessibilityFeatures(flags);
#endif
}

#pragma mark - Memory Notifications

- (void)onMemoryWarning:(NSNotification*)notification {
    [_systemChannel.get() sendMessage:@{@"type" : @"memoryPressure"}];
}

#pragma mark - Locale updates

- (void)onLocaleUpdated:(NSNotification*)notification {
    NSArray<NSString*>* preferredLocales = [NSLocale preferredLanguages];
    NSMutableArray<NSString*>* data = [NSMutableArray new];
    for (NSString* localeID in preferredLocales) {
        NSLocale* currentLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeID];
        NSString* languageCode = [currentLocale objectForKey:NSLocaleLanguageCode];
        NSString* countryCode = [currentLocale objectForKey:NSLocaleCountryCode];
        NSString* scriptCode = [currentLocale objectForKey:NSLocaleScriptCode];
        NSString* variantCode = [currentLocale objectForKey:NSLocaleVariantCode];
        if (!languageCode || !countryCode) {
            continue;
        }
        [data addObject:languageCode];
        [data addObject:countryCode];
        [data addObject:(scriptCode ? scriptCode : @"")];
        [data addObject:(variantCode ? variantCode : @"")];
    }
    if (data.count == 0) {
        return;
    }
    [_localizationChannel.get() invokeMethod:@"setLocale" arguments:data];
}

- (void)onLocaleChange:(NSNotification*)notification {
    NSString* languageCode =  notification.userInfo[@"languageCode"];
    if ([languageCode hasPrefix:@"zh"])
        languageCode = @"zh";
    NSString* countryCode = notification.userInfo[@"countryCode"];
    if (!countryCode) {
        countryCode = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    }
    if (languageCode && countryCode)
        [_localizationChannel.get() invokeMethod:@"setLocale" arguments:@[languageCode, countryCode, @"", @""]];
}

#pragma mark - Set user settings

- (void)onUserSettingsChanged:(NSNotification*)notification {
    if (![_flutterView nextResponder])
        return;
    
    [_settingsChannel.get() sendMessage:@{
                                          @"textScaleFactor" : @([self textScaleFactor]),
                                          @"alwaysUse24HourFormat" : @([self isAlwaysUse24HourFormat]),
                                          }];
}

- (CGFloat)textScaleFactor {
    UIContentSizeCategory category = [UIApplication sharedApplication].preferredContentSizeCategory;
    // The delta is computed by approximating Apple's typography guidelines:
    // https://developer.apple.com/ios/human-interface-guidelines/visual-design/typography/
    //
    // Specifically:
    // Non-accessibility sizes for "body" text are:
    const CGFloat xs = 14;
    const CGFloat s = 15;
    const CGFloat m = 16;
    const CGFloat l = 17;
    const CGFloat xl = 19;
    const CGFloat xxl = 21;
    const CGFloat xxxl = 23;
    
    // Accessibility sizes for "body" text are:
    const CGFloat ax1 = 28;
    const CGFloat ax2 = 33;
    const CGFloat ax3 = 40;
    const CGFloat ax4 = 47;
    const CGFloat ax5 = 53;
    
    // We compute the scale as relative difference from size L (large, the default size), where
    // L is assumed to have scale 1.0.
    if ([category isEqualToString:UIContentSizeCategoryExtraSmall])
        return xs / l;
    else if ([category isEqualToString:UIContentSizeCategorySmall])
        return s / l;
    else if ([category isEqualToString:UIContentSizeCategoryMedium])
        return m / l;
    else if ([category isEqualToString:UIContentSizeCategoryLarge])
        return 1.0;
    else if ([category isEqualToString:UIContentSizeCategoryExtraLarge])
        return xl / l;
    else if ([category isEqualToString:UIContentSizeCategoryExtraExtraLarge])
        return xxl / l;
    else if ([category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge])
        return xxxl / l;
    else if ([category isEqualToString:UIContentSizeCategoryAccessibilityMedium])
        return ax1 / l;
    else if ([category isEqualToString:UIContentSizeCategoryAccessibilityLarge])
        return ax2 / l;
    else if ([category isEqualToString:UIContentSizeCategoryAccessibilityExtraLarge])
        return ax3 / l;
    else if ([category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraLarge])
        return ax4 / l;
    else if ([category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge])
        return ax5 / l;
    else
        return 1.0;
}

- (BOOL)isAlwaysUse24HourFormat {
    // iOS does not report its "24-Hour Time" user setting in the API. Instead, it applies
    // it automatically to NSDateFormatter when used with [NSLocale currentLocale]. It is
    // essential that [NSLocale currentLocale] is used. Any custom locale, even the one
    // that's the same as [NSLocale currentLocale] will ignore the 24-hour option (there
    // must be some internal field that's not exposed to developers).
    //
    // Therefore this option behaves differently across Android and iOS. On Android this
    // setting is exposed standalone, and can therefore be applied to all locales, whether
    // the "current system locale" or a custom one. On iOS it only applies to the current
    // system locale. Widget implementors must take this into account in order to provide
    // platform-idiomatic behavior in their widgets.
    NSString* dateFormat =
    [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
    return [dateFormat rangeOfString:@"a"].location == NSNotFound;
}

#pragma mark - Status Bar touch event handling

// Standard iOS status bar height in pixels.
constexpr CGFloat kStandardStatusBarHeight = 20.0;

- (void)handleStatusBarTouches:(UIEvent*)event {
    
    if (![_flutterView nextResponder])
        return;
    
    CGFloat standardStatusBarHeight = kStandardStatusBarHeight;
    if (@available(iOS 11, *)) {
        standardStatusBarHeight = self.flutterView.safeAreaInsets.top;
    }
    
    // If the status bar is double-height, don't handle status bar taps. iOS
    // should open the app associated with the status bar.
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    if (statusBarFrame.size.height != standardStatusBarHeight) {
        return;
    }
    
    // If we detect a touch in the status bar, synthesize a fake touch begin/end.
    for (UITouch* touch in event.allTouches) {
        if (touch.phase == UITouchPhaseBegan && touch.tapCount > 0) {
            CGPoint windowLoc = [touch locationInView:nil];
            CGPoint screenLoc = [touch.window convertPoint:windowLoc toWindow:nil];
            if (CGRectContainsPoint(statusBarFrame, screenLoc)) {
                NSSet* statusbarTouches = [NSSet setWithObject:touch];

                blink::PointerData::Change change = blink::PointerData::Change::kDown;
                [self dispatchTouches:statusbarTouches pointerDataChangeOverride:&change];
                change = blink::PointerData::Change::kUp;
                [self dispatchTouches:statusbarTouches pointerDataChangeOverride:&change];

                return;
            }
        }
    }
}

#pragma mark - Status bar style

- (UIStatusBarStyle)preferredStatusBarStyle {
    return _statusBarStyle;
}

- (void)onPreferredStatusBarStyleUpdated:(NSNotification*)notification {
    if (![_flutterView nextResponder])
        return;
    
    // Notifications may not be on the iOS UI thread
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary* info = notification.userInfo;
        
        NSNumber* update = info[@(shell::kOverlayStyleUpdateNotificationKey)];
        
        if (update == nil) {
            return;
        }
        
        NSInteger style = update.integerValue;
        
        if (style != _statusBarStyle) {
            _statusBarStyle = static_cast<UIStatusBarStyle>(style);
            [self.viewController  setNeedsStatusBarAppearanceUpdate];
        }
    });
}

#pragma mark - FlutterBinaryMessenger

- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {
    [self sendOnChannel:channel message:message binaryReply:nil];
}

- (void)sendOnChannel:(NSString*)channel
              message:(NSData*)message
          binaryReply:(FlutterBinaryReply)callback {
    NSAssert(channel, @"The channel must not be null");
    fml::RefPtr<shell::PlatformMessageResponseDarwin> response =
    (callback == nil) ? nullptr
    : fml::MakeRefCounted<shell::PlatformMessageResponseDarwin>(
                                                                ^(NSData* reply) {
                                                                    callback(reply);
                                                                },
                                                                _shell->GetTaskRunners().GetPlatformTaskRunner());
    fml::RefPtr<blink::PlatformMessage> platformMessage =
    (message == nil) ? fml::MakeRefCounted<blink::PlatformMessage>(channel.UTF8String, response)
    : fml::MakeRefCounted<blink::PlatformMessage>(
                                                  channel.UTF8String, shell::GetVectorFromNSData(message), response);
    
    _shell->GetPlatformView()->DispatchPlatformMessage(platformMessage);
}

- (void)setMessageHandlerOnChannel:(NSString*)channel
              binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
    NSAssert(channel, @"The channel must not be null");
    if (_shell != NULL) {
        [self iosPlatformView] -> GetPlatformMessageRouter().SetMessageHandler(channel.UTF8String,
                                                                               handler);
    }
}

#pragma mark - FlutterTextureRegistry

- (int64_t)registerTexture:(NSObject<FlutterTexture>*)texture {
    int64_t textureId = _nextTextureId++;
    [self iosPlatformView] -> RegisterExternalTexture(textureId, texture);
    return textureId;
}

- (void)unregisterTexture:(int64_t)textureId {
    _shell->GetPlatformView()->UnregisterTexture(textureId);
}

- (void)textureFrameAvailable:(int64_t)textureId {
    _shell->GetPlatformView()->MarkTextureFrameAvailable(textureId);
}

- (NSString*)lookupKeyForAsset:(NSString*)asset {
    return [FlutterDartProject lookupKeyForAsset:asset];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package {
    return [FlutterDartProject lookupKeyForAsset:asset fromPackage:package];
}

- (id<FlutterPluginRegistry>)pluginRegistry {
    return self;
}

#pragma mark - FlutterPluginRegistry

- (NSObject<FlutterPluginRegistrar>*)registrarForPlugin:(NSString*)pluginKey {
    NSAssert(self.pluginPublications[pluginKey] == nil, @"Duplicate plugin key: %@", pluginKey);
    self.pluginPublications[pluginKey] = [NSNull null];
    return [[[FlutterViewControllerRegistrar alloc] initWithPlugin:pluginKey flutterViewControllerCore:self] autorelease];
}

- (BOOL)hasPlugin:(NSString*)pluginKey {
    return _pluginPublications[pluginKey] != nil;
}

- (NSObject*)valuePublishedByPlugin:(NSString*)pluginKey {
    return _pluginPublications[pluginKey];
}
@end

@implementation FlutterViewControllerRegistrar {
    NSString* _pluginKey;
    FlutterViewControllerCore* _flutterViewControllerCore;
}

- (instancetype)initWithPlugin:(NSString*)pluginKey
     flutterViewControllerCore:(FlutterViewControllerCore*)flutterViewControllerCore {
    self = [super init];
    NSAssert(self, @"Super init cannot be nil");
    _pluginKey = [pluginKey retain];
    _flutterViewControllerCore = [flutterViewControllerCore retain];
    return self;
}

- (void)dealloc {
    [_pluginKey release];
    [_flutterViewControllerCore release];
    [super dealloc];
}

- (NSObject<FlutterBinaryMessenger>*)messenger {
    return _flutterViewControllerCore;
}

- (NSObject<FlutterTextureRegistry>*)textures {
    return _flutterViewControllerCore;
}

- (void)publish:(NSObject*)value {
    _flutterViewControllerCore.pluginPublications[_pluginKey] = value;
}

- (void)addMethodCallDelegate:(NSObject<FlutterPlugin>*)delegate
                      channel:(FlutterMethodChannel*)channel {
    [channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [delegate handleMethodCall:call result:result];
    }];
}

- (void)addApplicationDelegate:(NSObject<FlutterPlugin>*)delegate {
    id<UIApplicationDelegate> appDelegate = [[UIApplication sharedApplication] delegate];
    if ([appDelegate conformsToProtocol:@protocol(FlutterAppLifeCycleProvider)]) {
        id<FlutterAppLifeCycleProvider> lifeCycleProvider =
        (id<FlutterAppLifeCycleProvider>)appDelegate;
        [lifeCycleProvider addApplicationLifeCycleDelegate:delegate];
    }
}

- (NSString*)lookupKeyForAsset:(NSString*)asset {
    return [_flutterViewControllerCore lookupKeyForAsset:asset];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package {
    return [_flutterViewControllerCore lookupKeyForAsset:asset fromPackage:package];
}

@end

