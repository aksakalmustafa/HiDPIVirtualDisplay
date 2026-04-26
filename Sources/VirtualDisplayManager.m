// VirtualDisplayManager.m
// Implementation of virtual display creation using private CoreGraphics APIs

#import "VirtualDisplayManager.h"
#import "CGVirtualDisplayPrivate.h"
#import <AppKit/AppKit.h>

@interface VirtualDisplayManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *virtualDisplays;
// Keyed by virtual displayID -> physical displayID it is mirroring
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *mirrorMap;
// Last creation params so we can rebuild after wake
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *createParamMap;
@end

@implementation VirtualDisplayManager

+ (instancetype)sharedManager {
    static VirtualDisplayManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[VirtualDisplayManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _virtualDisplays = [NSMutableDictionary dictionary];
        _mirrorMap = [NSMutableDictionary dictionary];
        _createParamMap = [NSMutableDictionary dictionary];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                             selector:@selector(handleSystemSleep:)
                                                                 name:NSWorkspaceWillSleepNotification
                                                               object:nil];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                             selector:@selector(handleSystemWake:)
                                                                 name:NSWorkspaceDidWakeNotification
                                                               object:nil];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark - Power State Handling

- (void)handleSystemSleep:(NSNotification *)note {
    NSLog(@"System going to sleep — unmirroring then destroying virtual displays.");

    // Unmirror all before destroying so the physical display is left clean
    for (NSNumber *virtualIDNum in self.mirrorMap.allKeys) {
        CGDirectDisplayID virtualID = (CGDirectDisplayID)virtualIDNum.unsignedIntValue;
        [self _stopMirroringForDisplay:virtualID commit:NO];
    }
    // Commit the unmirror changes in one pass
    [self _commitUnmirrorAll];

    [self.mirrorMap removeAllObjects];
    [self.virtualDisplays removeAllObjects];
}

- (void)handleSystemWake:(NSNotification *)note {
    NSLog(@"System waking up — rebuilding virtual displays.");

    // Small delay so WindowServer finishes its own wake-up sequence
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"VirtualDisplayNeedsRebuild"
                          object:self
                        userInfo:[self.createParamMap copy]];
    });
}

#pragma mark - Internal mirror helpers

// Stage an unmirror for displayID without committing yet
- (void)_stopMirroringForDisplay:(CGDirectDisplayID)displayID commit:(BOOL)commit {
    CGDisplayConfigRef configRef;
    if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) return;
    CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
    if (commit) {
        CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    } else {
        CGCancelDisplayConfiguration(configRef);
    }
}

// Unmirror everything that was staged via individual CGBeginDisplayConfiguration calls
- (void)_commitUnmirrorAll {
    CGDisplayConfigRef configRef;
    if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) return;
    for (NSNumber *virtualIDNum in self.mirrorMap.allKeys) {
        CGDirectDisplayID virtualID = (CGDirectDisplayID)virtualIDNum.unsignedIntValue;
        CGConfigureDisplayMirrorOfDisplay(configRef, virtualID, kCGNullDirectDisplay);
    }
    CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
}

#pragma mark - Display Creation & Management

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate {

    NSLog(@"Creating virtual display: %ux%u @ %u PPI, HiDPI: %@, Refresh: %.0fHz",
          width, height, ppi, hiDPI ? @"YES" : @"NO", refreshRate);

    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;

    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    // Serial queue prevents CoreGraphics race conditions that crash WindowServer
    descriptor.queue = dispatch_queue_create("com.hidpivirtualdisplay.renderqueue", DISPATCH_QUEUE_SERIAL);
    descriptor.name = name;

    // Exact sRGB IEC 61966-2.1 primaries — lets ColorSync reuse a cached profile
    // instead of generating a custom one (custom ones caused colorsync.displayservices
    // to deadlock against colorsyncd, blocking WindowServer render threads)
    descriptor.whitePoint = CGPointMake(0.3127, 0.3290);   // D65
    descriptor.redPrimary = CGPointMake(0.6400, 0.3300);
    descriptor.greenPrimary = CGPointMake(0.3000, 0.6000);
    descriptor.bluePrimary = CGPointMake(0.1500, 0.0600);

    float widthInInches = (float)width / (float)ppi;
    float heightInInches = (float)height / (float)ppi;
    descriptor.sizeInMillimeters = CGSizeMake(widthInInches * 25.4f, heightInInches * 25.4f);

    NSLog(@"Physical size: %.1f x %.1f mm",
          descriptor.sizeInMillimeters.width,
          descriptor.sizeInMillimeters.height);

    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;

    descriptor.vendorID = 0x1234;
    descriptor.productID = 0x5678;
    descriptor.serialNum = 1;

    descriptor.terminationHandler = ^(id display, id reason) {
        NSLog(@"Virtual display terminated: %@", reason);
    };

    unsigned int modeWidth = hiDPI ? width / 2 : width;
    unsigned int modeHeight = hiDPI ? height / 2 : height;

    NSLog(@"Mode resolution: %ux%u (logical), Framebuffer: %ux%u",
          modeWidth, modeHeight, width, height);

    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                      height:modeHeight
                                                                 refreshRate:refreshRate];
    NSMutableArray *modes = [NSMutableArray arrayWithObject:mode];
    if (refreshRate != 60.0) {
        CGVirtualDisplayMode *fallbackMode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                                  height:modeHeight
                                                                             refreshRate:60.0];
        if (fallbackMode) {
            [modes addObject:fallbackMode];
        }
    }
    settings.modes = modes;

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (!display) {
        NSLog(@"Failed to create virtual display");
        return kCGNullDirectDisplay;
    }

    if (![display applySettings:settings]) {
        NSLog(@"Failed to apply settings to virtual display");
        return kCGNullDirectDisplay;
    }

    CGDirectDisplayID displayID = display.displayID;
    NSLog(@"Created virtual display with ID: %u", displayID);

    self.virtualDisplays[@(displayID)] = display;

    // Store params so wake handler can replay them
    self.createParamMap[@(displayID)] = @{
        @"width": @(width),
        @"height": @(height),
        @"ppi": @(ppi),
        @"hiDPI": @(hiDPI),
        @"name": name,
        @"refreshRate": @(refreshRate)
    };

    return displayID;
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID {

    NSLog(@"Setting up mirror: %u -> %u", sourceDisplayID, targetDisplayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to begin display configuration: %d", err);
        return NO;
    }

    err = CGConfigureDisplayMirrorOfDisplay(configRef, targetDisplayID, sourceDisplayID);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to configure mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    // kCGConfigurePermanently so the mirror survives sleep/wake within the session
    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to complete display configuration: %d", err);
        return NO;
    }

    // Track which physical display this virtual display is mirroring
    self.mirrorMap[@(sourceDisplayID)] = @(targetDisplayID);

    NSLog(@"Mirror configuration applied successfully");
    return YES;
}

- (BOOL)stopMirroringForDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"Stopping mirror for display: %u", displayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to begin display configuration: %d", err);
        return NO;
    }

    err = CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to stop mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to complete display configuration: %d", err);
        return NO;
    }

    [self.mirrorMap removeObjectForKey:@(displayID)];

    NSLog(@"Mirror stopped successfully");
    return YES;
}

- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"Destroying virtual display: %u", displayID);
    [self.mirrorMap removeObjectForKey:@(displayID)];
    [self.createParamMap removeObjectForKey:@(displayID)];
    [self.virtualDisplays removeObjectForKey:@(displayID)];
}

- (void)destroyAllVirtualDisplays {
    NSLog(@"Destroying all virtual displays (%lu total)",
          (unsigned long)self.virtualDisplays.count);
    [self.mirrorMap removeAllObjects];
    [self.createParamMap removeAllObjects];
    [self.virtualDisplays removeAllObjects];
}

- (NSArray<NSDictionary *> *)listAllDisplays {
    NSMutableArray *displays = [NSMutableArray array];

    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    CGError err = CGGetOnlineDisplayList(32, displayList, &displayCount);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to get display list: %d", err);
        return displays;
    }

    for (uint32_t i = 0; i < displayCount; i++) {
        CGDirectDisplayID displayID = displayList[i];

        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
        size_t width = CGDisplayModeGetWidth(mode);
        size_t height = CGDisplayModeGetHeight(mode);
        double refreshRate = CGDisplayModeGetRefreshRate(mode);
        CGDisplayModeRelease(mode);

        CGSize physicalSize = CGDisplayScreenSize(displayID);
        BOOL isMain = CGDisplayIsMain(displayID);
        BOOL isBuiltin = CGDisplayIsBuiltin(displayID);
        CGDirectDisplayID mirrorOf = CGDisplayMirrorsDisplay(displayID);
        BOOL isVirtual = [self isVirtualDisplay:displayID];

        [displays addObject:@{
            @"id": @(displayID),
            @"width": @(width),
            @"height": @(height),
            @"refreshRate": @(refreshRate),
            @"physicalWidth": @(physicalSize.width),
            @"physicalHeight": @(physicalSize.height),
            @"isMain": @(isMain),
            @"isBuiltin": @(isBuiltin),
            @"mirrorOf": @(mirrorOf),
            @"isVirtual": @(isVirtual)
        }];
    }

    return displays;
}

- (CGDirectDisplayID)mainDisplayID {
    return CGMainDisplayID();
}

- (BOOL)isVirtualDisplay:(CGDirectDisplayID)displayID {
    return self.virtualDisplays[@(displayID)] != nil;
}

@end
