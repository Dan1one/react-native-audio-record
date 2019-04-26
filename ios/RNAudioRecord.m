#import "RNAudioRecord.h"

#define kBufferLengthForAudioBuffer 2048 * 16 * 60 // Times seconds (60)

@interface RNAudioRecord ()

@end

@implementation RNAudioRecord

void HandleInputBuffer(void *inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *inPacketDesc)
{
    AQRecordState* pRecordState = (AQRecordState *)inUserData;
    
    if (!pRecordState->mIsRunning) {
        return;
    }
    
    // read the number of bytes available
    int32_t availableBytes = 0;
    TPCircularBufferHead(&pRecordState->mCircularBuffer, &availableBytes);
    
    //clear/consume(discard) bytes if needed
    if (availableBytes < inBuffer->mAudioDataByteSize) {
        TPCircularBufferConsume(&pRecordState->mCircularBuffer, inBuffer->mAudioDataByteSize - availableBytes);
        [pRecordState->mSelf consumeTimestampBytes:(inBuffer->mAudioDataByteSize - availableBytes)];
    }
    
    //insert bytes into buffer
    AudioTimeStamp ts = *inStartTime;
    TPCircularBufferProduceBytes(&pRecordState->mCircularBuffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    [pRecordState->mSelf appendTimestamps:ts withBytes:inBuffer->mAudioDataByteSize];
    [pRecordState->mSelf setLatestTimestamp:CFAbsoluteTimeGetCurrent()];
    AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
    
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents {
    return @[@"data"];
}

- (void)dealloc {
    RCTLogInfo(@"dealloc");
    AudioQueueDispose(_recordState.mQueue, true);
}

-(void)appendTimestamps:(AudioTimeStamp)timestamp withBytes:(UInt32)bytes
{
    _totalBytes += bytes;
    NSValue * timestampOBJ = [NSValue valueWithBytes:&timestamp objCType:@encode(AudioTimeStamp)];
    NSNumber * bytesOBJ = @(self.totalBytes);
    [self.timestamps addObject: @{bytesOBJ : timestampOBJ }];
}

-(void)consumeTimestampBytes:(UInt32)bytes;
{
    _totalConsumedBytes += bytes;
    NSUInteger index = [self.timestamps indexOfObjectPassingTest:^BOOL(NSDictionary * obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [[[obj allKeys] firstObject] unsignedIntegerValue] >= _totalConsumedBytes;
        //        return stop;
    }];
    [self.timestamps removeObjectsInRange:NSMakeRange(0, index)];
}

-(NSUInteger )indexForTimestamp:(double)targetTimestamp
{
    __block float bestDifference = CGFLOAT_MAX;
    AudioTimeStamp firstTimestamp;
    [[[[self.timestamps firstObject] allValues] firstObject] getValue:&firstTimestamp];
    float initial = firstTimestamp.mSampleTime/_recordState.mDataFormat.mSampleRate;
    
    NSUInteger index = [self.timestamps indexOfObjectPassingTest:^BOOL(NSDictionary * obj, NSUInteger idx, BOOL * _Nonnull stop) {
        AudioTimeStamp timestamp = [self timestampForDictionary:obj];
        float currentTimestamp = timestamp.mSampleTime/_recordState.mDataFormat.mSampleRate;
        float adjustedTimestamp = currentTimestamp - initial;
        
        if (ABS(targetTimestamp - adjustedTimestamp) <= bestDifference) {
            bestDifference = targetTimestamp - adjustedTimestamp;
            return NO;
        } else {
            return YES;
        }
    }];
    
    if(index == NSNotFound)
    {
        index = MAX([self.timestamps count] - 1, 0);
    }
    
    return index;
}

-(AudioTimeStamp) timestampForDictionary:(NSDictionary *)targetDictionary
{
    AudioTimeStamp timestamp;
    [[[targetDictionary allValues] firstObject] getValue:&timestamp];
    return timestamp;
}

-(UInt32) byteOffsetForDictionary:(NSDictionary *)targetDictionary
{
    return (UInt32)[[[targetDictionary allKeys] firstObject] unsignedIntegerValue];
}

RCT_EXPORT_METHOD(init:(NSDictionary *) options) {
    RCTLogInfo(@"init");
    _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 44100 : [options[@"sampleRate"] doubleValue];
    _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
    _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
    _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
    _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
    _recordState.mDataFormat.mFramesPerPacket   = 1;
    _recordState.mDataFormat.mReserved          = 0;
    _recordState.mDataFormat.mFormatID          = kAudioFormatLinearPCM;
    _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);
    
    _recordState.bufferByteSize = 2048;
    _recordState.mSelf = self;
    self.latestTimestamp = CFAbsoluteTimeGetCurrent();
    
    NSString *fileName = options[@"wavFile"] == nil ? @"audio.wav" : options[@"wavFile"];
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    _filePath = [NSString stringWithFormat:@"%@/%@", docDir, fileName];
}

RCT_EXPORT_METHOD(start) {
    RCTLogInfo(@"start");
    
    if (_recordState.mCircularBuffer.length) {
        TPCircularBufferCleanup(&_recordState.mCircularBuffer);
        TPCircularBufferClear(&_recordState.mCircularBuffer);
    }
    
    TPCircularBufferInit(&_recordState.mCircularBuffer, kBufferLengthForAudioBuffer);
    
    // most audio players set session category to "Playback", record won't work in this mode
    // therefore set session category to "Record" before recording
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];
    
    _recordState.mIsRunning = true;
    _recordState.mCurrentPacket = 0;
    
    _timestamps = [NSMutableArray new];
    _totalBytes = 0;
    _totalConsumedBytes = 0;
    
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)_filePath, NULL);
    AudioFileCreateWithURL(url, kAudioFileWAVEType, &_recordState.mDataFormat, kAudioFileFlags_EraseFile, &_recordState.mAudioFile);
    CFRelease(url);
    
    AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
    }
    AudioQueueStart(_recordState.mQueue, NULL);
}


RCT_EXPORT_METHOD(
                  outputFileWithOptions:(NSDictionary *)options
                  callback:(RCTResponseSenderBlock)callback
                  )
{
        NSNumber *startTime = options[@"startTimestamp"];
        NSNumber *endTime = options[@"endTimestamp"];
        
        if (!startTime || !endTime) {
            callback(@[[NSError errorWithDomain:@"RNAudioRecord" code:100 userInfo:@{@"message": @"Incorrect Arguments: {startTimestamp , endTimestamp} must be included"}], @{}]);
            return;
        }
        
        //generate file URL
    NSString *fileName = [NSString stringWithFormat:@"%@.wav", [NSUUID UUID].UUIDString];
        NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *targetFilepath = [NSString stringWithFormat:@"%@/%@", docDir, fileName];
        
        //Create AudioFile
        
        CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)targetFilepath, NULL);
        AudioFileID targetFile;
        AudioFileCreateWithURL(url, kAudioFileWAVEType, &_recordState.mDataFormat, kAudioFileFlags_EraseFile, &targetFile);
        CFRelease(url);
        
        //Extract Correct Time Stamps
        UInt32 firstByteOffset = [self byteOffsetForDictionary:[[self timestamps] firstObject]];
        NSDictionary *initialframe = [self.timestamps objectAtIndex:[self indexForTimestamp:[startTime doubleValue]]];
        UInt32 adjustedInitialByteOffset = [self byteOffsetForDictionary:initialframe] - firstByteOffset;
        NSDictionary *finalframe = [self.timestamps objectAtIndex:[self indexForTimestamp:[endTime doubleValue]]];
        UInt32 adjustedFinalByteOffset = [self byteOffsetForDictionary:finalframe] - firstByteOffset;
        
        // CopyBytes from the right position
        
        // Consume bytes for the first window
        TPCircularBufferConsume(&_recordState.mCircularBuffer, adjustedInitialByteOffset);
        
        //Get all the remaning bytes
        int32_t availableBytes = 0;
        void* sourceBuffer = TPCircularBufferTail(&_recordState.mCircularBuffer, &availableBytes);
        
        // Copy the desired length of the buffer
        UInt32 totalBytes = MIN(adjustedInitialByteOffset - adjustedFinalByteOffset, availableBytes);
        void *targetBuffer = malloc(totalBytes);
        memcpy(targetBuffer, sourceBuffer, totalBytes);
        
        // Write them to file
        
        OSStatus err =  AudioFileWriteBytes(targetFile, false, 0, &totalBytes, targetBuffer);
        free(targetBuffer);
        //clean up
        AudioFileClose(targetFile);
        
        
        callback(@[[NSNull null], @{
                       @"filePath": _filePath
                       }]);
    }


RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject) {
    //    RCTLogInfo(@"stop");
    if (_recordState.mIsRunning) {
        _recordState.mIsRunning = false;
        
        AudioTimeStamp firstTimestamp = [self timestampForDictionary:[self.timestamps firstObject]];
        AudioTimeStamp lastTimestamp = [self timestampForDictionary:[self.timestamps lastObject]];
        float initial = firstTimestamp.mSampleTime/_recordState.mDataFormat.mSampleRate;
        float final  = lastTimestamp.mSampleTime/_recordState.mDataFormat.mSampleRate;
        float difference = final - initial;
        
//        [self produceFileWithOptions:@{@"startTimestamp": @(0.0f), @"endTimestamp": @(difference)}];
        
        
        // Consume buffer
        int32_t availableBytes = 0;
        void* buffer = TPCircularBufferTail(&_recordState.mCircularBuffer, &availableBytes);
        OSStatus err =  AudioFileWriteBytes(_recordState.mAudioFile, false, 0, &availableBytes, buffer);

        AudioQueueStop(_recordState.mQueue, true);
        AudioQueueDispose(_recordState.mQueue, true);
        AudioFileClose(_recordState.mAudioFile);
        
        if(err)
        {
//            reject(@{@"error": @"Unable to save file"});
            reject(@"E_AUDIO_FILE_FAILED", @"Audio File failed to produce a file output", nil);
            return;
        }
 
        resolve(@{
                  @"filePath": _filePath,
                  @"startTime" : @(self.latestTimestamp - difference),
                  @"endTime": @(self.latestTimestamp)
                  });
    } else {
        resolve(@{});

    }
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
    RCTLogInfo(@"file path %@", _filePath);
    RCTLogInfo(@"file size %llu", fileSize);
}


@end
