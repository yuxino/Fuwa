// Fresh ScreenCaptureKit/Accessibility adapter for the MyGo rewrite.
// No Swift runtime, helper process, webview, private API, synthetic input, or disk frames.
#import "bridge_darwin.h"
#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

static char *JSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return strdup("null");
    char *out = malloc(data.length + 1);
    if (!out) return NULL;
    memcpy(out, data.bytes, data.length); out[data.length] = 0; return out;
}
static NSDictionary *FMRectJSON(CGRect r) {
    return @{ @"X":@(r.origin.x), @"Y":@(r.origin.y), @"Width":@(r.size.width), @"Height":@(r.size.height) };
}
static double Birth(NSRunningApplication *app) { return app.launchDate ? app.launchDate.timeIntervalSince1970 : 0; }
static void OnMain(void (^work)(void)) {
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(),work);
}
static void Layers(void (^work)(void)) {
    [CATransaction begin]; [CATransaction setDisableActions:YES]; work(); [CATransaction commit];
}
static NSDictionary *Descriptor(NSDictionary *entry) {
    NSNumber *pid = entry[(id)kCGWindowOwnerPID];
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid.intValue];
    CGRect bounds = CGRectZero;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[(id)kCGWindowBounds], &bounds);
    return @{ @"id":entry[(id)kCGWindowNumber] ?: @0, @"pid":pid ?: @0, @"birth":@(Birth(app)),
       @"app":app.localizedName ?: entry[(id)kCGWindowOwnerName] ?: @"App", @"bundle":app.bundleIdentifier ?: @"",
       @"title":entry[(id)kCGWindowName] ?: @"", @"bounds":FMRectJSON(bounds),
       @"alpha":entry[(id)kCGWindowAlpha] ?: @0, @"onscreen":entry[(id)kCGWindowIsOnscreen] ?: @NO };
}
static NSDictionary *Exact(uint32_t wid, int32_t pid, double birth) {
    NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
    for (NSDictionary *entry in list) {
        if ([entry[(id)kCGWindowNumber] unsignedIntValue] != wid || [entry[(id)kCGWindowOwnerPID] intValue] != pid) continue;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app && !app.terminated && Birth(app) == birth) return entry;
    }
    return nil;
}
char *fw_inventory(void) {
    @autoreleasepool {
        NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
        if (!list) return strdup("null");
        NSMutableArray *windows = [NSMutableArray array];
        for (NSDictionary *entry in list) [windows addObject:Descriptor(entry)];
        CGDirectDisplayID ids[32]; uint32_t count = 0;
        NSMutableArray *displays = [NSMutableArray array];
        if (CGGetActiveDisplayList(32, ids, &count) == kCGErrorSuccess)
            for (uint32_t i=0; i<count; i++) [displays addObject:FMRectJSON(CGDisplayBounds(ids[i]))];
        return JSON(@{ @"windows":windows, @"displays":displays, @"self":@(getpid()),
           @"front":@(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier) });
    }
}

static NSMutableArray<NSDictionary *> *events;
static NSMutableArray *observers;
@class FMCapture;
static NSMutableDictionary<NSNumber *, FMCapture *> *captures;
static void PrivacyBoundary(NSString *reason);
static void Emit(uint64_t token, uint64_t generation, NSString *kind, NSString *message) {
    if (!events) events = [NSMutableArray array];
    [events addObject:@{ @"token":@(token), @"generation":@(generation), @"kind":kind, @"message":message ?: @"" }];
}
char *fw_events(void) {
    // Frozen pins have no stream delegate to report revocation. Polling the
    // event queue must clear their pixels too, before Go can process old events.
    if (captures.count && !CGPreflightScreenCaptureAccess()) PrivacyBoundary(@"screen_permission");
    char *out = JSON(events ?: @[]); [events removeAllObjects]; return out;
}
int fw_screen_allowed(void) {
    BOOL allowed=CGPreflightScreenCaptureAccess();
    if (!allowed && captures.count) PrivacyBoundary(@"screen_permission");
    return allowed;
}
int fw_request_screen(void) { return CGRequestScreenCaptureAccess(); }
int fw_ax_allowed(void) { return AXIsProcessTrusted(); }

// MyGo exposes floating/normal, but management must sit one level above the
// floating mirrors while Fuwa is active. Hide/deactivate never reopens it.
void fw_management_active(uintptr_t host, int active) {
    NSWindow *window=(__bridge NSWindow *)(void *)host;
    window.level=active && window.visible ? NSFloatingWindowLevel+1 : NSNormalWindowLevel;
}

@interface FMSurface : NSView
@property(nonatomic,strong) AVSampleBufferDisplayLayer *video;
@property(nonatomic,strong) CALayer *still;
@end
@implementation FMSurface
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.layer.masksToBounds = YES;
        _video = [AVSampleBufferDisplayLayer layer]; _video.videoGravity = AVLayerVideoGravityResizeAspect;
        _still = [CALayer layer]; _still.contentsGravity = kCAGravityResizeAspect;
        _video.hidden=YES;_still.hidden=YES;
        _still.magnificationFilter=kCAFilterLinear;_still.minificationFilter=kCAFilterTrilinear;
        [self.layer addSublayer:_video]; [self.layer addSublayer:_still];
        _video.frame=self.bounds;_still.frame=self.bounds;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}
- (void)layout { [super layout]; [CATransaction begin]; [CATransaction setDisableActions:YES]; _video.frame=self.bounds; _still.frame=self.bounds; [CATransaction commit]; }
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

// All lifecycle mutations are on main. Detachment is synchronous; asynchronous
// start/configuration completions still own exactly one eventual stop. Keeping
// a separate output/delegate avoids a stream retaining an obsolete capture.
@interface FMStreamCycle : NSObject<SCStreamOutput,SCStreamDelegate>
@property(atomic,weak) FMCapture *owner;
@property(nonatomic,strong) SCStream *stream;
@property(nonatomic) uint64_t generation;
@property(nonatomic) BOOL starting;
@property(nonatomic) BOOL resizing;
@property(nonatomic) BOOL outputAttached;
@property(nonatomic) BOOL detached;
@property(nonatomic) BOOL stopSent;
- (void)start:(void (^)(NSError *))completion;
- (void)update:(SCStreamConfiguration *)configuration completion:(void (^)(NSError *))completion;
- (void)detach;
- (void)finishTeardown;
@end

static CGSize Pixels(double width,double height,double scale) {
    // Match the Swift implementation's 4 MP budget, including very wide or
    // malformed geometries. Flooring, then budgeting the second axis, prevents
    // rounding back above the memory ceiling.
    if (!isfinite(width)||!isfinite(height)||!isfinite(scale)||width<=0||height<=0) return CGSizeMake(2,2);
    scale=fmax(1,fmin(4,scale)); width=ceil(width*scale);height=ceil(height*scale);
    if (!isfinite(width)||!isfinite(height)) return CGSizeMake(2,2);
    const double budget=4000000;
    double ratio=fmin(1,fmin(8192/fmax(width,height),sqrt(budget/(width*height))));
    width=fmax(2,floor(width*ratio));height=fmax(2,floor(height*ratio));
    width=fmin(budget/2,width);height=fmin(floor(budget/width),height);
    return CGSizeMake(width,height);
}

static CGImageRef IndependentImage(CVPixelBufferRef buffer) CF_RETURNS_RETAINED {
    CGImageRef image=NULL;
    if (!buffer || VTCreateCGImageFromCVPixelBuffer(buffer,NULL,&image)!=noErr || !image) return NULL;
    CGSize size=Pixels(CGImageGetWidth(image),CGImageGetHeight(image),1);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context=color?CGBitmapContextCreate(NULL,(size_t)size.width,(size_t)size.height,8,0,color,
        kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst):NULL;
    if (color) CGColorSpaceRelease(color);
    if (!context) {CGImageRelease(image);return NULL;}
    CGContextSetBlendMode(context,kCGBlendModeCopy);
    CGContextSetInterpolationQuality(context,size.width==CGImageGetWidth(image)&&size.height==CGImageGetHeight(image)?kCGInterpolationNone:kCGInterpolationHigh);
    CGContextDrawImage(context,CGRectMake(0,0,size.width,size.height),image);
    CGImageRef independent=CGBitmapContextCreateImage(context);
    CGContextRelease(context);CGImageRelease(image);return independent;
}

@interface FMCapture : NSObject {
    CVPixelBufferRef _last;
    CMSampleBufferRef _pending;
    SCStream *_pendingStream;
    SCStream *_acceptingStream;
    NSLock *_mailbox;
    BOOL _deliveryQueued;
}
@property(nonatomic) uint64_t token;
@property(nonatomic) uint64_t generation;
@property(nonatomic) uint32_t wid;
@property(nonatomic) int32_t pid;
@property(nonatomic) double birth;
@property(nonatomic,weak) NSWindow *host;
@property(nonatomic,strong) FMSurface *surface;
@property(nonatomic,strong) FMStreamCycle *cycle;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL firstFrame;
@property(nonatomic) BOOL independentStill;
@property(nonatomic) BOOL presentationComplete;
@property(nonatomic) BOOL subsequentFrame;
@property(nonatomic) uint64_t resizeRevision;
@property(nonatomic) CGSize pointSize;
@property(nonatomic) double pointScale;
@property(nonatomic) CGSize wantedSize;
@property(nonatomic) CGSize configuredSize;
- (void)begin;
- (void)haltStream;
- (BOOL)freezeImage;
- (void)fail:(NSString *)code generation:(uint64_t)generation;
- (void)clear;
- (void)resize;
- (void)scheduleResize;
- (void)acceptStream:(SCStream *)stream;
- (void)receiveSample:(CMSampleBufferRef)sample stream:(SCStream *)stream;
- (void)deliverPendingFrame;
- (void)consumeFrame:(CMSampleBufferRef)frame;
- (void)finishFirstPresentation;
- (void)endedStream:(SCStream *)stream;
@end

@implementation FMStreamCycle
- (void)start:(void (^)(NSError *))completion {
    self.starting=YES;
    [self.stream startCaptureWithCompletionHandler:^(NSError *error) {
        OnMain(^{self.starting=NO;[self finishTeardown];completion(error);});
    }];
}
- (void)update:(SCStreamConfiguration *)configuration completion:(void (^)(NSError *))completion {
    self.resizing=YES;
    [self.stream updateConfiguration:configuration completionHandler:^(NSError *error) {
        OnMain(^{self.resizing=NO;[self finishTeardown];completion(error);});
    }];
}
- (void)detach {
    if (self.detached) return;
    self.detached=YES;self.owner=nil;
    if (self.outputAttached) {
        [self.stream removeStreamOutput:self type:SCStreamOutputTypeScreen error:nil];
        self.outputAttached=NO;
    }
    [self finishTeardown];
}
- (void)finishTeardown {
    if (!self.detached||self.starting||self.resizing||self.stopSent) return;
    self.stopSent=YES;
    [self.stream stopCaptureWithCompletionHandler:^(NSError *error) {
        OnMain(^{self.stream=nil;}); // No captured content or raw error is logged.
    }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if (type==SCStreamOutputTypeScreen) [self.owner receiveSample:sample stream:stream];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    OnMain(^{[self.owner endedStream:stream];});
}
- (void)streamDidBecomeInactive:(SCStream *)stream {
    OnMain(^{[self.owner endedStream:stream];});
}
@end

@implementation FMCapture
- (instancetype)init {
    if ((self=[super init])) { _mailbox=[NSLock new]; _queue=dispatch_queue_create("app.yuxino.fuwa.mygo.capture", DISPATCH_QUEUE_SERIAL); }
    return self;
}
- (void)dealloc { if (_last) CVPixelBufferRelease(_last); if (_pending) CFRelease(_pending); }
- (SCStreamConfiguration *)configuration {
    SCStreamConfiguration *c=[SCStreamConfiguration new];
    c.width=MAX(1,(size_t)self.wantedSize.width); c.height=MAX(1,(size_t)self.wantedSize.height);
    c.pixelFormat=kCVPixelFormatType_32BGRA; c.minimumFrameInterval=CMTimeMake(1,30);
    c.queueDepth=3; c.showsCursor=NO; c.capturesAudio=NO;
    c.ignoreShadowsSingleWindow=YES;c.scalesToFit=YES;c.colorSpaceName=kCGColorSpaceSRGB;
    return c;
}
- (void)begin {
    const uint64_t gen=self.generation;
    self.stopped=NO;self.firstFrame=NO;self.presentationComplete=NO;self.subsequentFrame=NO;
    if (!CGPreflightScreenCaptureAccess()) { [self fail:@"screen_permission" generation:gen]; return; }
    if (!Exact(self.wid,self.pid,self.birth)) { [self fail:@"source_closed" generation:gen]; return; }
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped || self.generation!=gen) return;
            if (error) { [self fail:CGPreflightScreenCaptureAccess()?@"capture_unavailable":@"screen_permission" generation:gen]; return; }
            SCWindow *target=nil;
            // Quartz remains authoritative for PID/process-birth checks above
            // and below. SCK can report a different owning PID for system-hosted
            // content such as Quick Look; its cross-framework key is windowID.
            for (SCWindow *window in content.windows)
                if (window.windowID==self.wid) {target=window;break;}
            if (!Exact(self.wid,self.pid,self.birth)) { [self fail:@"source_closed" generation:gen]; return; }
            if (!target) { [self fail:@"not_shareable" generation:gen]; return; }
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:target];
            // The capture source's scale can differ from the mirror's screen.
            // The filter is authoritative initially; complete frames update it
            // when the source crosses between Retina and non-Retina displays.
            double scale=filter.pointPixelScale;
            self.pointScale=isfinite(scale)&&scale>=1&&scale<=4?scale:1;
            CGSize contentSize=filter.contentRect.size;
            if (isfinite(contentSize.width)&&isfinite(contentSize.height)&&contentSize.width>0&&contentSize.height>0) self.pointSize=contentSize;
            self.wantedSize=Pixels(self.pointSize.width,self.pointSize.height,self.pointScale);
            FMStreamCycle *cycle=[FMStreamCycle new];cycle.owner=self;cycle.generation=gen;
            SCStream *stream=[[SCStream alloc] initWithFilter:filter configuration:[self configuration] delegate:cycle];
            cycle.stream=stream;self.cycle=cycle;self.configuredSize=self.wantedSize;
            NSError *addError=nil;
            if (![stream addStreamOutput:cycle type:SCStreamOutputTypeScreen sampleHandlerQueue:self.queue error:&addError]) {
                [self fail:@"capture_start_failed" generation:gen]; return;
            }
            cycle.outputAttached=YES;[self acceptStream:stream];
            [cycle start:^(NSError *startError) {
                if (self.stopped || self.generation!=gen || self.cycle!=cycle) return;
                if (startError) [self fail:CGPreflightScreenCaptureAccess()?@"capture_start_failed":@"screen_permission" generation:gen];
                else [self resize];
            }];
        });
    }];
    __weak FMCapture *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        FMCapture *capture=weakSelf;
        if (capture && !capture.stopped && capture.generation==gen && !capture.firstFrame) [capture fail:@"first_frame_timeout" generation:gen];
    });
}
- (void)acceptStream:(SCStream *)stream {
    [_mailbox lock];_acceptingStream=stream;[_mailbox unlock];
}
- (void)receiveSample:(CMSampleBufferRef)sample stream:(SCStream *)stream {
    if (!sample||!CMSampleBufferIsValid(sample)||!CMSampleBufferDataIsReady(sample)) return;
    NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,NO);
    NSNumber *status=attachments.firstObject[SCStreamFrameInfoStatus];
    if (!status || status.integerValue!=SCFrameStatusComplete || !CMSampleBufferGetImageBuffer(sample)) return;
    CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(sample);
    if (!CVPixelBufferGetWidth(buffer)||!CVPixelBufferGetHeight(buffer)) return;
    // Only the latest frame is queued. A slow main thread cannot accumulate pixels.
    [_mailbox lock];
    // Check under the same lock that privacy teardown uses to detach pixels.
    // Already queued callbacks may still execute after removeStreamOutput.
    if (!stream || _acceptingStream!=stream) {[_mailbox unlock];return;}
    if (_pending) CFRelease(_pending);
    _pending=(CMSampleBufferRef)CFRetain(sample); _pendingStream=stream;
    BOOL schedule=!_deliveryQueued; _deliveryQueued=YES;
    [_mailbox unlock];
    if (!schedule) return;
    __weak FMCapture *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{[weakSelf deliverPendingFrame];});
}
- (void)deliverPendingFrame {
    [_mailbox lock];
    CMSampleBufferRef frame=_pending;SCStream *owner=_pendingStream;
    _pending=NULL;_pendingStream=nil;_deliveryQueued=NO;
    [_mailbox unlock];
    if (!frame) return;
    if (!self.stopped && self.cycle.stream==owner && self.surface) [self consumeFrame:frame];
    CFRelease(frame);
}
- (void)consumeFrame:(CMSampleBufferRef)frame {
    CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(frame);
    if (_last) CVPixelBufferRelease(_last);
    _last=CVPixelBufferRetain(buffer);
    NSMutableArray *attrs=(__bridge NSMutableArray *)CMSampleBufferGetSampleAttachmentsArray(frame,YES);
    if (attrs.count) attrs[0][(__bridge NSString *)kCMSampleAttachmentKey_DisplayImmediately]=@YES;
    NSNumber *scale=attrs.firstObject[SCStreamFrameInfoScaleFactor];
    double pointScale=scale.doubleValue;
    if (isfinite(pointScale)&&pointScale>=1&&pointScale<=4&&fabs(pointScale-self.pointScale)>0.001) {
        self.pointScale=pointScale;self.wantedSize=Pixels(self.pointSize.width,self.pointSize.height,pointScale);
        [self scheduleResize];
    }
    if (self.surface.video.status==AVQueuedSampleBufferRenderingStatusFailed||self.surface.video.requiresFlushToResumeDecoding) [self.surface.video flush];
    [self.surface.video enqueueSampleBuffer:frame];
    if (!self.firstFrame) {
        self.firstFrame=YES;
        CGImageRef bridge=NULL;VTCreateCGImageFromCVPixelBuffer(buffer,NULL,&bridge);
        Layers(^{
            self.surface.video.hidden=NO;
            if (bridge) {self.surface.still.contents=(__bridge id)bridge;self.independentStill=NO;}
            self.surface.still.contentsScale=self.host.backingScaleFactor ?: 1;
            self.surface.still.hidden=self.surface.still.contents==nil;
        });
        if (bridge) CGImageRelease(bridge);
        Emit(self.token,self.generation,@"live",nil);
    } else {
        self.subsequentFrame=YES;[self finishFirstPresentation];
    }
}
- (void)finishFirstPresentation {
    // Enqueue is asynchronous. Keep the first-frame bridge until Go has shown
    // the host, another main-loop turn has elapsed, and a second complete frame
    // has arrived. A static source still has a complete visible bridge.
    if (!self.firstFrame||!self.presentationComplete||!self.subsequentFrame||self.stopped) return;
    Layers(^{self.surface.video.hidden=NO;self.surface.still.contents=nil;self.surface.still.hidden=YES;});
    self.independentStill=NO;
}
- (BOOL)freezeImage {
    if (!self.surface) return NO;
    if (!_last) return self.independentStill && self.surface.still.contents!=nil;
    CGImageRef image=IndependentImage(_last);
    if (!image) return NO;
    Layers(^{
        self.surface.still.contents=(__bridge id)image;self.surface.still.hidden=NO;
        self.surface.still.contentsScale=self.host.backingScaleFactor ?: 1;self.surface.video.hidden=YES;
    });
    self.independentStill=YES;CGImageRelease(image);return YES;
}
- (void)haltStream {
    self.stopped=YES;self.resizeRevision++;self.firstFrame=NO;self.subsequentFrame=NO;self.presentationComplete=NO;
    FMStreamCycle *old=self.cycle;self.cycle=nil;
    [_mailbox lock];_acceptingStream=nil;
    if (_pending) {CFRelease(_pending);_pending=NULL;}_pendingStream=nil;
    [_mailbox unlock];
    [old detach];
    [self.surface.video flushAndRemoveImage];
    Layers(^{
        self.surface.video.hidden=YES;
        if (!self.independentStill) {self.surface.still.contents=nil;self.surface.still.hidden=YES;}
    });
    if (_last) {CVPixelBufferRelease(_last);_last=NULL;}
}
- (void)fail:(NSString *)code generation:(uint64_t)gen {
    if (self.stopped || self.generation!=gen) return;
    if ([code isEqualToString:@"screen_permission"]) {PrivacyBoundary(code);return;}
    BOOL hasImage=[self freezeImage];
    [self haltStream]; self.stopped=YES;
    if (!hasImage) {self.surface.still.contents=nil;[self.surface.video flushAndRemoveImage];[self.host orderOut:nil];}
    Emit(self.token,gen,hasImage?@"frozen":@"failed",code);
}
- (void)endedStream:(SCStream *)stream {
    if (self.stopped || self.cycle.stream!=stream) return;
    NSString *reason=!CGPreflightScreenCaptureAccess()?@"screen_permission":
        (Exact(self.wid,self.pid,self.birth)?@"capture_interrupted":@"source_closed");
    [self fail:reason generation:self.generation];
}
- (void)scheduleResize {
    uint64_t revision=++self.resizeRevision,gen=self.generation;
    __weak FMCapture *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        FMCapture *capture=weakSelf;
        if (capture && capture.generation==gen && capture.resizeRevision==revision) [capture resize];
    });
}
- (void)resize {
    FMStreamCycle *cycle=self.cycle;
    if (self.stopped||!cycle||cycle.starting||cycle.resizing||CGSizeEqualToSize(self.wantedSize,self.configuredSize)) return;
    uint64_t gen=self.generation;CGSize size=self.wantedSize;
    [cycle update:[self configuration] completion:^(NSError *error) {
        if (self.generation!=gen || self.cycle!=cycle || self.stopped) return;
        if (error) {[self fail:@"capture_resize_failed" generation:gen];return;}
        self.configuredSize=size;[self resize];
    }];
}
- (void)clear {
    self.stopped=YES; self.generation++;
    for (NSWindow *child in self.host.childWindows) [child orderOut:nil];
    [self.host orderOut:nil];
    self.surface.still.contents=nil; [self.surface.video flushAndRemoveImage];
    self.independentStill=NO;
    if (_last) {CVPixelBufferRelease(_last);_last=NULL;}
    [self haltStream]; [self.surface removeFromSuperview]; self.surface=nil;
}
@end
static void PrivacyBoundary(NSString *reason) {
    for (FMCapture *capture in captures.allValues) [capture clear];
    [captures removeAllObjects];[events removeAllObjects];Emit(0,0,@"privacy",reason ?: @"privacy_cleared");
}
void fw_initialize(void) {
    if (captures) return;
    captures=[NSMutableDictionary dictionary]; events=[NSMutableArray array]; observers=[NSMutableArray array];
    for (NSString *name in @[NSWorkspaceWillSleepNotification,NSWorkspaceScreensDidSleepNotification,NSWorkspaceSessionDidResignActiveNotification]) {
        id observer=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){PrivacyBoundary(@"privacy_cleared");}];
        [observers addObject:observer];
    }
    id observer=[NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.apple.screenIsLocked" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){PrivacyBoundary(@"privacy_cleared");}];
    [observers addObject:observer];
    observer=[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){PrivacyBoundary(@"privacy_cleared");}];
    [observers addObject:observer];
}
void fw_start(uint64_t token,uint64_t gen,uint32_t wid,int32_t pid,double birth,uintptr_t host) {
    fw_initialize(); FMCapture *capture=captures[@(token)];
    if (!host) {Emit(token,gen,@"failed",@"capture_unavailable");return;}
    if (!capture) {
        capture=[FMCapture new];capture.token=token;
        capture.host=(__bridge NSWindow *)(void *)host;
        capture.surface=[[FMSurface alloc] initWithFrame:capture.host.contentView.bounds];
        [capture.host.contentView addSubview:capture.surface];
        capture.host.ignoresMouseEvents=YES;capture.host.sharingType=NSWindowSharingNone;
        capture.host.excludedFromWindowsMenu=YES;capture.host.hidesOnDeactivate=NO;
        capture.host.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorIgnoresCycle;
        captures[@(token)]=capture;
    }
    [capture haltStream]; capture.generation=gen;capture.wid=wid;capture.pid=pid;capture.birth=birth;
    NSDictionary *entry=Exact(wid,pid,birth);CGRect frame=CGRectZero;
    if (entry) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[(id)kCGWindowBounds],&frame);
    capture.pointSize=frame.size;capture.pointScale=0;
    capture.wantedSize=Pixels(frame.size.width,frame.size.height,capture.host.backingScaleFactor);
    [capture begin];
}
char *fw_freeze(uint64_t token) {
    if (!fw_screen_allowed()) return strdup("screen_permission");
    FMCapture *c=captures[@(token)];
    if (!c || ![c freezeImage]) return strdup("no_complete_frame");
    [c haltStream];c.stopped=YES;
    return NULL;
}
void fw_stop(uint64_t token) {FMCapture *c=captures[@(token)];[c clear];[captures removeObjectForKey:@(token)];}
void fw_resize(uint64_t token,double width,double height,double scale) {
    FMCapture *c=captures[@(token)];
    if (!isfinite(width)||!isfinite(height)||width<=0||height<=0) return;
    c.pointSize=CGSizeMake(width,height);
    CGSize size=Pixels(width,height,c.pointScale>0?c.pointScale:scale);
    if (!CGSizeEqualToSize(size,c.wantedSize)) {c.wantedSize=size;[c scheduleResize];}
}
void fw_presented(uint64_t token,uint64_t generation) {
    __weak FMCapture *weakCapture=captures[@(token)];
    dispatch_async(dispatch_get_main_queue(),^{
        FMCapture *capture=weakCapture;
        if (!capture||capture.stopped||capture.generation!=generation) return;
        capture.presentationComplete=YES;[capture finishFirstPresentation];
    });
}

// Match only public AX windows in the source process, with a strict unique
// title/geometry match. Ambiguity fails closed; no private AX window IDs.
static CFTypeRef AXCopy(AXUIElementRef element,CFStringRef attribute) {
    CFTypeRef result=NULL; if (AXUIElementCopyAttributeValue(element,attribute,&result)!=kAXErrorSuccess) return NULL; return result;
}
static NSString *Normalize(NSString *s) {return [[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByFoldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:nil];}
char *fw_reveal(uint32_t wid,int32_t pid,double birth) {
    if (!AXIsProcessTrusted()) { NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}; AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);return strdup("accessibility_permission"); }
    NSDictionary *entry=Exact(wid,pid,birth); if (!entry) return strdup("source_closed");
    CGRect target=CGRectZero;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[(id)kCGWindowBounds],&target);
    NSString *title=Normalize(entry[(id)kCGWindowName] ?: @"");
    AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.15);
    CFTypeRef raw=AXCopy(app,kAXWindowsAttribute);
    if (!raw || CFGetTypeID(raw)!=CFArrayGetTypeID()) {if(raw)CFRelease(raw);CFRelease(app);return strdup("source_uncontrollable");}
    NSArray *windows=(__bridge NSArray *)raw;AXUIElementRef match=NULL;NSUInteger matches=0;
    // A partial scan cannot prove uniqueness. Fail closed instead of raising
    // the first matching window when another candidate may remain unseen.
    if (windows.count>32) {CFRelease(raw);CFRelease(app);return strdup("ambiguous_source");}
    BOOL incomplete=NO;
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
    for (NSUInteger i=0;i<MIN(windows.count,32);i++) {
        if (CFAbsoluteTimeGetCurrent()>deadline) {incomplete=YES;break;}
        AXUIElementRef w=(__bridge AXUIElementRef)windows[i];pid_t owner=0;AXUIElementGetPid(w,&owner);if(owner!=pid)continue;
        AXUIElementSetMessagingTimeout(w,0.15);
        CFTypeRef pos=AXCopy(w,kAXPositionAttribute),size=AXCopy(w,kAXSizeAttribute),name=AXCopy(w,kAXTitleAttribute);
        CGPoint p=CGPointZero;CGSize s=CGSizeZero;BOOL usable=NO;
        if(pos&&size&&CFGetTypeID(pos)==AXValueGetTypeID()&&CFGetTypeID(size)==AXValueGetTypeID()) usable=AXValueGetValue((AXValueRef)pos,kAXValueCGPointType,&p)&&AXValueGetValue((AXValueRef)size,kAXValueCGSizeType,&s);
        NSString *candidate=(name&&CFGetTypeID(name)==CFStringGetTypeID())?Normalize((__bridge NSString *)name):@"";
        CGRect bounds=CGRectMake(p.x,p.y,s.width,s.height),inter=CGRectIntersection(target,bounds);
        double intersection=CGRectIsNull(inter)?0:inter.size.width*inter.size.height;
        double area=target.size.width*target.size.height+s.width*s.height-intersection;
        BOOL titleOK=title.length==0||candidate.length==0||[title isEqualToString:candidate];
        BOOL geometryOK=usable&&isfinite(area)&&area>0&&intersection/area>=0.80&&fabs(p.x-target.origin.x)<=40&&fabs(p.y-target.origin.y)<=40;
        if (titleOK&&geometryOK){matches++;match=w;}
        if(pos)CFRelease(pos);if(size)CFRelease(size);if(name)CFRelease(name);
    }
    char *error=NULL;
    if(incomplete || matches!=1 || !Exact(wid,pid,birth)) error=strdup((incomplete||matches>1)?"ambiguous_source":"source_uncontrollable");
    else {
        AXUIElementSetAttributeValue(match,kAXMinimizedAttribute,kCFBooleanFalse);
        if(AXUIElementPerformAction(match,kAXRaiseAction)!=kAXErrorSuccess) error=strdup("source_uncontrollable");
        else {
            AXUIElementSetAttributeValue(app,kAXFrontmostAttribute,kCFBooleanTrue);
            [[NSRunningApplication runningApplicationWithProcessIdentifier:pid] activateWithOptions:0];
        }
    }
    CFRelease(raw);CFRelease(app);return error;
}
int fw_login_state(void) {
    switch(SMAppService.mainAppService.status){case SMAppServiceStatusNotRegistered:return 0;case SMAppServiceStatusEnabled:return 1;case SMAppServiceStatusRequiresApproval:return 2;default:return 3;}
}
char *fw_set_login(int enabled) {
    NSError *error=nil;
    BOOL ok=enabled?[SMAppService.mainAppService registerAndReturnError:&error]:[SMAppService.mainAppService unregisterAndReturnError:&error];
    return ok?NULL:strdup("login_failed");
}

#ifdef FUWA_PARITY_QA
#include "capture_qa_darwin.h"
#endif
