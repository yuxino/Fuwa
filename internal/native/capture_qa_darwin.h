// Included only by bridge_darwin.m in a fuwa_parity_qa build. All pixels below
// are allocated here; no desktop capture, TCC request or third-party window is
// involved. Delayed fake stream completions exercise the production teardown.
#ifndef FUWA_CAPTURE_QA_H
#define FUWA_CAPTURE_QA_H

@interface FMQAMockStream : NSObject
@property(nonatomic) NSUInteger stops;
@property(nonatomic) NSUInteger removes;
@property(nonatomic) NSUInteger updates;
@property(nonatomic,copy) void (^startCompletion)(NSError *);
@property(nonatomic,copy) void (^updateCompletion)(NSError *);
- (void)finishStart;
- (void)finishUpdate;
@end
@implementation FMQAMockStream
- (void)startCaptureWithCompletionHandler:(void (^)(NSError *))completion {self.startCompletion=completion;}
- (void)updateConfiguration:(SCStreamConfiguration *)configuration completionHandler:(void (^)(NSError *))completion {
    self.updates++;self.updateCompletion=completion;
}
- (BOOL)removeStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type error:(NSError **)error {
    self.removes++;return YES;
}
- (void)stopCaptureWithCompletionHandler:(void (^)(NSError *))completion {self.stops++;completion(nil);}
- (void)finishStart {void (^completion)(NSError *)=self.startCompletion;self.startCompletion=nil;if(completion)completion(nil);}
- (void)finishUpdate {void (^completion)(NSError *)=self.updateCompletion;self.updateCompletion=nil;if(completion)completion(nil);}
@end

@interface FMCapture (ParityQA)
- (BOOL)qaHasPixels;
- (BOOL)qaHasStreamPixels;
- (BOOL)qaHasLastFrame;
- (BOOL)qaPendingIs:(CMSampleBufferRef)sample;
@end
@implementation FMCapture (ParityQA)
- (BOOL)qaHasPixels {
    [_mailbox lock];BOOL pending=_pending!=NULL;[_mailbox unlock];
    return _last!=NULL||pending||self.surface.still.contents!=nil;
}
- (BOOL)qaHasStreamPixels {
    [_mailbox lock];BOOL retained=_pending!=NULL||_acceptingStream!=nil;[_mailbox unlock];
    return _last!=NULL||retained;
}
- (BOOL)qaHasLastFrame {return _last!=NULL;}
- (BOOL)qaPendingIs:(CMSampleBufferRef)sample {
    [_mailbox lock];BOOL matches=_pending==sample;[_mailbox unlock];return matches;
}
@end

static void FMQAResult(NSMutableArray *results,NSString *name,BOOL passed) {
    [results addObject:@{@"name":name,@"ok":@(passed)}];
}
static void FMQAFill(CVPixelBufferRef buffer,uint32_t pixel) {
    CVPixelBufferLockBaseAddress(buffer,0);
    uint8_t *base=CVPixelBufferGetBaseAddress(buffer);
    for (size_t y=0;y<CVPixelBufferGetHeight(buffer);y++) {
        uint8_t *row=base+y*CVPixelBufferGetBytesPerRow(buffer);
        for (size_t x=0;x<CVPixelBufferGetWidth(buffer);x++) memcpy(row+x*4,&pixel,4);
    }
    CVPixelBufferUnlockBaseAddress(buffer,0);
}
static CMSampleBufferRef FMQASample(uint32_t pixel,SCFrameStatus status,double scale) CF_RETURNS_RETAINED {
    CVPixelBufferRef buffer=NULL;
    NSDictionary *attributes=@{(__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey:@YES,
        (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES,(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}};
    if (CVPixelBufferCreate(kCFAllocatorDefault,64,48,kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attributes,&buffer)!=kCVReturnSuccess) return NULL;
    FMQAFill(buffer,pixel);
    CMVideoFormatDescriptionRef format=NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,buffer,&format)!=noErr) {
        CVPixelBufferRelease(buffer);return NULL;
    }
    CMSampleTimingInfo timing={CMTimeMake(1,30),CMClockGetTime(CMClockGetHostTimeClock()),kCMTimeInvalid};
    CMSampleBufferRef sample=NULL;
    OSStatus result=CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,buffer,format,&timing,&sample);
    CFRelease(format);CVPixelBufferRelease(buffer);
    if (result!=noErr) return NULL;
    NSMutableArray *attachments=(__bridge NSMutableArray *)CMSampleBufferGetSampleAttachmentsArray(sample,YES);
    attachments[0][SCStreamFrameInfoStatus]=@(status);attachments[0][SCStreamFrameInfoScaleFactor]=@(scale);
    return sample;
}
static NSData *FMQAImageData(id contents) {
    if (!contents) return nil;
    CGImageRef image=(__bridge CGImageRef)contents;
    return CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image)));
}
static FMCapture *FMQACapture(uint64_t token) {
    FMCapture *capture=[FMCapture new];capture.token=token;capture.generation=1;
    capture.surface=[[FMSurface alloc] initWithFrame:NSMakeRect(0,0,64,48)];
    capture.pointSize=CGSizeMake(64,48);capture.pointScale=1;
    capture.wantedSize=CGSizeMake(64,48);capture.configuredSize=capture.wantedSize;
    return capture;
}
static FMQAMockStream *FMQACycle(FMCapture *capture) {
    FMQAMockStream *mock=[FMQAMockStream new];
    FMStreamCycle *cycle=[FMStreamCycle new];cycle.stream=(SCStream *)mock;cycle.owner=capture;
    cycle.generation=capture.generation;cycle.outputAttached=YES;capture.cycle=cycle;
    capture.stopped=NO;capture.firstFrame=NO;capture.presentationComplete=NO;capture.subsequentFrame=NO;
    [capture acceptStream:(SCStream *)mock];return mock;
}
static void FMQADeliver(FMCapture *capture,FMQAMockStream *stream,CMSampleBufferRef sample) {
    [capture receiveSample:sample stream:(SCStream *)stream];[capture deliverPendingFrame];
}

char *fw_qa_capture_lifecycle(void) {
    @autoreleasepool {
        NSMutableArray *results=[NSMutableArray array];
        FMQAResult(results,@"capture fixtures run on the AppKit main thread",NSThread.isMainThread);
        if (!NSThread.isMainThread) return JSON(results);
        fw_initialize();
        FMQAResult(results,@"capture fixtures require an empty native capture registry",captures.count==0);
        if (captures.count) return JSON(results);
        NSArray *savedEvents=events.copy;[events removeAllObjects];

        CMSampleBufferRef red=FMQASample(0xFFFF0000,SCFrameStatusComplete,1);
        CMSampleBufferRef blue=FMQASample(0xFF0000FF,SCFrameStatusComplete,2);
        CMSampleBufferRef idle=FMQASample(0xFF00FF00,SCFrameStatusIdle,1);
        FMQAResult(results,@"allocate only QA-owned BGRA sample buffers",red&&blue&&idle);
        if (!red||!blue||!idle) {
            if(red)CFRelease(red);if(blue)CFRelease(blue);if(idle)CFRelease(idle);
            [events setArray:savedEvents];return JSON(results);
        }

        FMCapture *capture=FMQACapture(UINT64_MAX-1);captures[@(capture.token)]=capture;
        FMQAMockStream *stream=FMQACycle(capture);
        FMQADeliver(capture,stream,idle);
        FMQAResult(results,@"incomplete frames cannot become live or retain pixels",!capture.firstFrame&&![capture qaHasPixels]&&events.count==0);
        [capture receiveSample:red stream:(SCStream *)stream];
        [capture receiveSample:blue stream:(SCStream *)stream];
        FMQAResult(results,@"the mailbox retains only the newest complete frame",[capture qaPendingIs:blue]);
        [capture deliverPendingFrame];
        FMQAResult(results,@"first complete frame creates a visible bridge and one live event",
            capture.firstFrame&&capture.surface.still.contents&&!capture.surface.still.hidden&&events.count==1&&[events[0][@"kind"] isEqual:@"live"]);
        FMQAResult(results,@"frame metadata changes source scale and capture dimensions",
            capture.pointScale==2&&CGSizeEqualToSize(capture.wantedSize,CGSizeMake(128,96)));
        fw_resize(capture.token,80,60,1);
        FMQAResult(results,@"mirror backing scale cannot override the source Retina scale",
            CGSizeEqualToSize(capture.wantedSize,CGSizeMake(160,120)));
        uint64_t pendingResize=capture.resizeRevision;
        fw_resize(capture.token,80,60,1);
        FMQAResult(results,@"position-only tracking cannot postpone a pending capture resize",capture.resizeRevision==pendingResize);
        fw_presented(capture.token,capture.generation);
        FMQAResult(results,@"presentation acknowledgement is deferred beyond the current main callback",!capture.presentationComplete);
        // Simulate the deferred turn without spinning a nested AppKit run loop.
        capture.presentationComplete=YES;[capture finishFirstPresentation];
        FMQAResult(results,@"presentation alone does not drop the first-frame bridge",capture.surface.still.contents!=nil);
        FMQADeliver(capture,stream,blue);
        FMQAResult(results,@"a subsequent complete frame completes the presentation bridge",capture.surface.still.contents==nil&&!capture.surface.video.hidden&&events.count==1);

        [capture haltStream];capture.generation++;
        stream=FMQACycle(capture);FMQADeliver(capture,stream,red);
        FMQAResult(results,@"freeze while the first-frame bridge is visible makes an independent image",[capture freezeImage]&&capture.independentStill);
        NSData *frozenBefore=FMQAImageData(capture.surface.still.contents);
        [capture haltStream];
        FMQAFill(CMSampleBufferGetImageBuffer(red),0xFF00FF00);
        NSData *frozenAfter=FMQAImageData(capture.surface.still.contents);
        FMQAResult(results,@"frozen pixels survive source buffer mutation and release of stream pixels",
            frozenBefore.length>0&&[frozenBefore isEqual:frozenAfter]&&![capture qaHasStreamPixels]&&capture.surface.still.contents!=nil);
        NSUInteger before=events.count;
        FMQADeliver(capture,stream,blue);
        FMQAResult(results,@"late frame callbacks cannot overwrite a frozen image",events.count==before&&![capture qaHasStreamPixels]&&[frozenBefore isEqual:FMQAImageData(capture.surface.still.contents)]);

        capture.generation++;stream=FMQACycle(capture);
        [capture fail:@"first_frame_timeout" generation:capture.generation];
        FMQAResult(results,@"resume timeout preserves the independent frozen image",
            capture.stopped&&[frozenBefore isEqual:FMQAImageData(capture.surface.still.contents)]&&[events.lastObject[@"kind"] isEqual:@"frozen"]);
        capture.generation++;stream=FMQACycle(capture);
        [capture fail:@"capture_start_failed" generation:capture.generation-1];
        FMQAResult(results,@"an obsolete generation cannot fail a new capture cycle",!capture.stopped&&capture.cycle!=nil);

        // Start/stop and resize/stop races use the real FMStreamCycle code with
        // completions explicitly released only after synchronous detachment.
        __block NSUInteger completed=0;
        FMStreamCycle *starting=capture.cycle;
        [starting start:^(NSError *error){completed++;}];
        [capture haltStream];
        FMQAResult(results,@"stop detaches output immediately while start is pending",stream.removes==1&&stream.stops==0&&starting.owner==nil);
        [stream finishStart];[starting detach];
        FMQAResult(results,@"a late successful start is stopped exactly once",completed==1&&stream.stops==1&&stream.removes==1&&starting.stream==nil);
        capture.generation++;stream=FMQACycle(capture);
        capture.wantedSize=CGSizeMake(160,120);capture.configuredSize=CGSizeMake(64,48);
        [capture resize];FMStreamCycle *resizing=capture.cycle;
        [capture haltStream];
        FMQAResult(results,@"stop waits for an in-flight configuration update",stream.updates==1&&stream.removes==1&&stream.stops==0);
        [stream finishUpdate];[resizing detach];
        FMQAResult(results,@"late resize completion cannot revive a detached stream",stream.stops==1&&stream.removes==1&&capture.stopped&&capture.cycle==nil);

        // A different current stream must reject late output from an older one.
        FMQAMockStream *obsolete=stream;capture.generation++;stream=FMQACycle(capture);
        FMQADeliver(capture,obsolete,blue);
        FMQAResult(results,@"an old stream cannot supply a new generation's first frame",!capture.firstFrame&&![capture qaHasLastFrame]);
        // Check the queue directly because an accepted current stream is not a pixel.
        FMQAResult(results,@"old-stream output never enters the new frame mailbox",[capture qaPendingIs:NULL]);
        FMQADeliver(capture,stream,blue);
        [capture receiveSample:red stream:(SCStream *)stream];
        FMCapture *empty=FMQACapture(UINT64_MAX);captures[@(empty.token)]=empty;
        FMQAMockStream *emptyStream=FMQACycle(empty);
        [empty fail:@"source_closed" generation:empty.generation];
        FMQAResult(results,@"a source closed before any complete frame fails without retained pixels",
            empty.stopped&&![empty qaHasPixels]&&[events.lastObject[@"kind"] isEqual:@"failed"]&&emptyStream.stops==1);
        FMCapture *frozen=FMQACapture(UINT64_MAX-2);captures[@(frozen.token)]=frozen;
        FMQAMockStream *frozenStream=FMQACycle(frozen);FMQADeliver(frozen,frozenStream,red);
        [frozen freezeImage];[frozen haltStream];
        FMQAResult(results,@"privacy fixture includes an already frozen independent image",frozen.independentStill&&[frozen qaHasPixels]&&![frozen qaHasStreamPixels]);
        PrivacyBoundary(@"screen_permission");
        FMQAResult(results,@"privacy synchronously clears live, pending and frozen pixels",
            captures.count==0&&![capture qaHasPixels]&&![capture qaHasStreamPixels]&&capture.surface==nil&&capture.stopped&&![frozen qaHasPixels]&&frozen.surface==nil);
        FMQAResult(results,@"privacy replaces queued live/failure events with one boundary event",
            events.count==1&&[events[0][@"kind"] isEqual:@"privacy"]&&[events[0][@"message"] isEqual:@"screen_permission"]);
        FMQADeliver(capture,stream,blue);
        FMQAResult(results,@"callbacks after privacy cannot retain or re-present pixels",![capture qaHasPixels]&&events.count==1);

        CGSize retina=Pixels(800,600,2),huge=Pixels(10000,10000,4),wide=Pixels(1000000,1,4),invalid=Pixels(NAN,600,2);
        FMQAResult(results,@"native point-to-pixel sizing respects Retina and the 4 MP budget",
            CGSizeEqualToSize(retina,CGSizeMake(1600,1200))&&huge.width*huge.height<=4000000&&wide.width*wide.height<=4000000&&wide.height>=2&&CGSizeEqualToSize(invalid,CGSizeMake(2,2)));
        CGSize boundary=Pixels(2001,2001,1),ratio=Pixels(3200,1800,2);
        FMQAResult(results,@"fitting floors at the 4 MP boundary and preserves normal aspect ratios",
            CGSizeEqualToSize(boundary,CGSizeMake(2000,2000))&&ratio.width*ratio.height<=4000000&&fabs(ratio.width/ratio.height-16.0/9)<0.002);

        CFRelease(red);CFRelease(blue);CFRelease(idle);[events setArray:savedEvents];
        return JSON(results);
    }
}
#endif
