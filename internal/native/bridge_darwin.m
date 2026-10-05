// Fresh ScreenCaptureKit/Accessibility adapter for the MyGo rewrite.
// No Swift runtime, helper process, webview, private API, synthetic input, or disk frames.
#import "bridge_darwin.h"
#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <QuartzCore/QuartzCore.h>
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
static NSDictionary *Rect(CGRect r) {
    return @{ @"X":@(r.origin.x), @"Y":@(r.origin.y), @"Width":@(r.size.width), @"Height":@(r.size.height) };
}
static double Birth(NSRunningApplication *app) { return app.launchDate ? app.launchDate.timeIntervalSince1970 : 0; }
static NSDictionary *Descriptor(NSDictionary *entry) {
    NSNumber *pid = entry[(id)kCGWindowOwnerPID];
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid.intValue];
    CGRect bounds = CGRectZero;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[(id)kCGWindowBounds], &bounds);
    return @{ @"id":entry[(id)kCGWindowNumber] ?: @0, @"pid":pid ?: @0, @"birth":@(Birth(app)),
       @"app":app.localizedName ?: entry[(id)kCGWindowOwnerName] ?: @"App", @"bundle":app.bundleIdentifier ?: @"",
       @"title":entry[(id)kCGWindowName] ?: @"", @"bounds":Rect(bounds),
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
            for (uint32_t i=0; i<count; i++) [displays addObject:Rect(CGDisplayBounds(ids[i]))];
        return JSON(@{ @"windows":windows, @"displays":displays, @"self":@(getpid()),
           @"front":@(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier) });
    }
}

static NSMutableArray<NSDictionary *> *events;
static NSMutableArray *observers;
@class FMCapture;
static NSMutableDictionary<NSNumber *, FMCapture *> *captures;
static void Emit(uint64_t token, uint64_t generation, NSString *kind, NSString *message) {
    if (!events) events = [NSMutableArray array];
    [events addObject:@{ @"token":@(token), @"generation":@(generation), @"kind":kind, @"message":message ?: @"" }];
}
char *fw_events(void) { char *out = JSON(events ?: @[]); [events removeAllObjects]; return out; }
int fw_screen_allowed(void) { return CGPreflightScreenCaptureAccess(); }
int fw_request_screen(void) { return CGRequestScreenCaptureAccess(); }
int fw_ax_allowed(void) { return AXIsProcessTrusted(); }

@interface FMSurface : NSView
@property(nonatomic,strong) AVSampleBufferDisplayLayer *video;
@property(nonatomic,strong) CALayer *still;
@end
@implementation FMSurface
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        _video = [AVSampleBufferDisplayLayer layer]; _video.videoGravity = AVLayerVideoGravityResizeAspect;
        _still = [CALayer layer]; _still.contentsGravity = kCAGravityResizeAspect;
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

@interface FMCapture : NSObject<SCStreamOutput,SCStreamDelegate> {
    CVPixelBufferRef _last;
    CMSampleBufferRef _pending;
    SCStream *_pendingStream;
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
@property(nonatomic,strong) SCStream *stream;
@property(nonatomic,strong) SCContentFilter *filter;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL firstFrame;
@property(nonatomic) BOOL resizing;
@property(nonatomic) CGSize wantedSize;
@property(nonatomic) CGSize configuredSize;
- (void)begin;
- (void)haltStream;
- (BOOL)freezeImage;
- (void)fail:(NSString *)code generation:(uint64_t)generation;
- (void)clear;
- (void)resize;
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
    c.ignoreShadowsSingleWindow=YES;
    return c;
}
- (void)begin {
    const uint64_t gen=self.generation;
    self.stopped=NO; self.firstFrame=NO;
    if (!CGPreflightScreenCaptureAccess()) { [self fail:@"screen_permission" generation:gen]; return; }
    if (!Exact(self.wid,self.pid,self.birth)) { [self fail:@"source_closed" generation:gen]; return; }
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped || self.generation!=gen) return;
            if (error) { [self fail:CGPreflightScreenCaptureAccess()?@"capture_unavailable":@"screen_permission" generation:gen]; return; }
            SCWindow *target=nil;
            for (SCWindow *window in content.windows) if (window.windowID==self.wid) {target=window;break;}
            if (!Exact(self.wid,self.pid,self.birth)) { [self fail:@"source_closed" generation:gen]; return; }
            if (!target) { [self fail:@"not_shareable" generation:gen]; return; }
            self.filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:target];
            SCStream *stream=[[SCStream alloc] initWithFilter:self.filter configuration:[self configuration] delegate:self];
            self.stream=stream; self.configuredSize=self.wantedSize;
            NSError *addError=nil;
            if (![stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self.queue error:&addError]) {
                [self fail:@"capture_start_failed" generation:gen]; return;
            }
            [stream startCaptureWithCompletionHandler:^(NSError *startError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.stopped || self.generation!=gen || self.stream!=stream) return;
                    if (startError) [self fail:CGPreflightScreenCaptureAccess()?@"capture_start_failed":@"screen_permission" generation:gen];
                });
            }];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (!self.stopped && self.generation==gen && !self.firstFrame) [self fail:@"first_frame_timeout" generation:gen];
    });
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if (type!=SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,NO);
    NSNumber *status=attachments.firstObject[SCStreamFrameInfoStatus];
    if (!status || status.integerValue!=SCFrameStatusComplete || !CMSampleBufferGetImageBuffer(sample)) return;
    // Only the latest frame is queued. A slow main thread cannot accumulate pixels.
    [_mailbox lock];
    if (_pending) CFRelease(_pending);
    _pending=(CMSampleBufferRef)CFRetain(sample); _pendingStream=stream;
    BOOL schedule=!_deliveryQueued; _deliveryQueued=YES;
    [_mailbox unlock];
    if (!schedule) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_mailbox lock];
        CMSampleBufferRef frame=self->_pending; SCStream *owner=self->_pendingStream;
        self->_pending=NULL; self->_pendingStream=nil; self->_deliveryQueued=NO;
        [self->_mailbox unlock];
        if (!frame) return;
        if (!self.stopped && self.stream==owner && self.surface) {
            CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(frame);
            if (self->_last) CVPixelBufferRelease(self->_last);
            self->_last=CVPixelBufferRetain(buffer);
            NSMutableArray *attrs=(__bridge NSMutableArray *)CMSampleBufferGetSampleAttachmentsArray(frame,YES);
            if (attrs.count) attrs[0][(__bridge NSString *)kCMSampleAttachmentKey_DisplayImmediately]=@YES;
            if (self.surface.video.status==AVQueuedSampleBufferRenderingStatusFailed) [self.surface.video flush];
            [self.surface.video enqueueSampleBuffer:frame];
            // The independent still remains until a complete frame of the new stream.
            self.surface.still.contents=nil;
            if (!self.firstFrame) {self.firstFrame=YES;Emit(self.token,self.generation,@"live",nil);}
        }
        CFRelease(frame);
    });
}
- (BOOL)freezeImage {
    if (self.surface.still.contents) return YES;
    if (!_last || !self.surface) return NO;
    CVPixelBufferLockBaseAddress(_last,kCVPixelBufferLock_ReadOnly);
    const size_t width=CVPixelBufferGetWidth(_last),height=CVPixelBufferGetHeight(_last),stride=CVPixelBufferGetBytesPerRow(_last);
    void *base=CVPixelBufferGetBaseAddress(_last);
    CFDataRef data=base?CFDataCreate(kCFAllocatorDefault,base,(CFIndex)(stride*height)):NULL;
    CVPixelBufferUnlockBaseAddress(_last,kCVPixelBufferLock_ReadOnly);
    if (!data) return NO;
    CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image=CGImageCreate(width,height,8,32,stride,color,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst,provider,NULL,NO,kCGRenderingIntentDefault);
    if (image) {self.surface.still.contents=(__bridge id)image;CGImageRelease(image);}
    CGColorSpaceRelease(color); CGDataProviderRelease(provider); CFRelease(data);
    return self.surface.still.contents!=nil;
}
- (void)haltStream {
    SCStream *old=self.stream; self.stream=nil; self.filter=nil; self.resizing=NO;
    [self.surface.video flushAndRemoveImage];
    if (_last) {CVPixelBufferRelease(_last);_last=NULL;}
    [_mailbox lock]; if (_pending) {CFRelease(_pending);_pending=NULL;} _pendingStream=nil; [_mailbox unlock];
    if (old) [old stopCaptureWithCompletionHandler:^(NSError *error) { /* No frame or error content is logged. */ }];
}
- (void)fail:(NSString *)code generation:(uint64_t)gen {
    if (self.stopped || self.generation!=gen) return;
    BOOL hasImage=[self freezeImage];
    [self haltStream]; self.stopped=YES;
    if (!hasImage) {self.surface.still.contents=nil;[self.surface.video flushAndRemoveImage];[self.host orderOut:nil];}
    Emit(self.token,gen,hasImage?@"frozen":@"failed",code);
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.stopped && self.stream==stream) [self fail:CGPreflightScreenCaptureAccess()?@"capture_interrupted":@"screen_permission" generation:self.generation];
    });
}
- (void)resize {
    if (self.stopped || !self.stream || self.resizing || CGSizeEqualToSize(self.wantedSize,self.configuredSize)) return;
    self.resizing=YES; SCStream *stream=self.stream; uint64_t gen=self.generation; CGSize size=self.wantedSize;
    [stream updateConfiguration:[self configuration] completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation!=gen || self.stream!=stream || self.stopped) return;
            self.resizing=NO;
            if (error) {[self fail:@"capture_resize_failed" generation:gen];return;}
            self.configuredSize=size; [self resize];
        });
    }];
}
- (void)clear {
    self.stopped=YES; self.generation++;
    [self.host orderOut:nil];
    self.surface.still.contents=nil; [self.surface.video flushAndRemoveImage];
    if (_last) {CVPixelBufferRelease(_last);_last=NULL;}
    [self haltStream]; [self.surface removeFromSuperview]; self.surface=nil;
}
@end

static CGSize Pixels(double width,double height,double scale) {
    scale=fmax(1,fmin(3,scale)); width=fmax(1,width*scale);height=fmax(1,height*scale);
    double ratio=fmin(1,fmin(8192/fmax(width,height),sqrt((16.0*1024*1024)/(width*height))));
    return CGSizeMake(ceil(width*ratio),ceil(height*ratio));
}
static void PrivacyBoundary(void) {
    for (FMCapture *capture in captures.allValues) [capture clear];
    [captures removeAllObjects]; Emit(0,0,@"privacy",@"privacy_cleared");
}
void fw_initialize(void) {
    if (captures) return;
    captures=[NSMutableDictionary dictionary]; events=[NSMutableArray array]; observers=[NSMutableArray array];
    for (NSString *name in @[NSWorkspaceWillSleepNotification,NSWorkspaceSessionDidResignActiveNotification]) {
        id observer=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){PrivacyBoundary();}];
        [observers addObject:observer];
    }
    id observer=[NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.apple.screenIsLocked" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){PrivacyBoundary();}];
    [observers addObject:observer];
}
void fw_start(uint64_t token,uint64_t gen,uint32_t wid,int32_t pid,double birth,uintptr_t host) {
    fw_initialize(); FMCapture *capture=captures[@(token)];
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
    capture.wantedSize=Pixels(frame.size.width,frame.size.height,capture.host.backingScaleFactor);
    [capture begin];
}
char *fw_freeze(uint64_t token) {
    FMCapture *c=captures[@(token)];
    if (!c || ![c freezeImage]) return strdup("no_complete_frame");
    [c haltStream];c.stopped=YES;
    return NULL;
}
void fw_stop(uint64_t token) {FMCapture *c=captures[@(token)];[c clear];[captures removeObjectForKey:@(token)];}
void fw_resize(uint64_t token,double width,double height,double scale) {FMCapture *c=captures[@(token)];c.wantedSize=Pixels(width,height,scale);[c resize];}

// Match only public AX windows in the source process, with a strict unique
// title/geometry match. Ambiguity fails closed; no private AX window IDs.
static CFTypeRef AXCopy(AXUIElementRef element,CFStringRef attribute) {
    CFTypeRef result=NULL; if (AXUIElementCopyAttributeValue(element,attribute,&result)!=kAXErrorSuccess) return NULL; return result;
}
static NSString *Normalize(NSString *s) {return [[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] foldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:nil];}
char *fw_reveal(uint32_t wid,int32_t pid,double birth) {
    if (!AXIsProcessTrusted()) { NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}; AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);return strdup("accessibility_permission"); }
    NSDictionary *entry=Exact(wid,pid,birth); if (!entry) return strdup("source_closed");
    CGRect target=CGRectZero;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[(id)kCGWindowBounds],&target);
    NSString *title=Normalize(entry[(id)kCGWindowName] ?: @"");
    AXUIElementRef app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.15);
    CFTypeRef raw=AXCopy(app,kAXWindowsAttribute);
    if (!raw || CFGetTypeID(raw)!=CFArrayGetTypeID()) {if(raw)CFRelease(raw);CFRelease(app);return strdup("source_uncontrollable");}
    NSArray *windows=(__bridge NSArray *)raw;AXUIElementRef match=NULL;NSUInteger matches=0;
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
    for (NSUInteger i=0;i<MIN(windows.count,32);i++) {
        if (CFAbsoluteTimeGetCurrent()>deadline) break;
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
    if(matches!=1 || !Exact(wid,pid,birth)) error=strdup(matches>1?"ambiguous_source":"source_uncontrollable");
    else {
        AXUIElementSetAttributeValue(match,kAXMinimizedAttribute,kCFBooleanFalse);
        if(AXUIElementPerformAction(match,kAXRaiseAction)!=kAXErrorSuccess) error=strdup("source_uncontrollable");
        else {
            AXUIElementSetAttributeValue(app,kAXFrontmostAttribute,kCFBooleanTrue);
            [[NSRunningApplication runningApplicationWithProcessIdentifier:pid] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
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
