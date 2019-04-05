#import "RNAudioRecord.h"

#define kBufferLengthForAudioBuffer 2048 * 16 * 60 // Times seconds (60)

@interface RNAudioRecord ()

@end

@implementation RNAudioRecord

RCT_EXPORT_MODULE();

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
    
    NSString *fileName = options[@"wavFile"] == nil ? @"audio.wav" : options[@"wavFile"];
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    _filePath = [NSString stringWithFormat:@"%@/%@", docDir, fileName];
}

RCT_EXPORT_METHOD(start) {
    RCTLogInfo(@"start");
    
    TPCircularBufferInit(&_recordState.mCircularBuffer, kBufferLengthForAudioBuffer);
    
    // most audio players set session category to "Playback", record won't work in this mode
    // therefore set session category to "Record" before recording
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];
    
    _recordState.mIsRunning = true;
    _recordState.mCurrentPacket = 0;
    
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

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject) {
    //    RCTLogInfo(@"stop");
    if (_recordState.mIsRunning) {
        _recordState.mIsRunning = false;
        
        // Consume buffer
        int32_t availableBytes = 0;
        void* buffer = TPCircularBufferTail(&_recordState.mCircularBuffer, &availableBytes);
        OSStatus err =  AudioFileWriteBytes(_recordState.mAudioFile, false, 0, &availableBytes, buffer);
        
        AudioQueueStop(_recordState.mQueue, true);
        AudioQueueDispose(_recordState.mQueue, true);
        AudioFileClose(_recordState.mAudioFile);
        
        TPCircularBufferCleanup(&_recordState.mCircularBuffer)
        TPCircularBufferClear(&_recordState.mCircularBuffer);
    }
    resolve(_filePath);
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
    RCTLogInfo(@"file path %@", _filePath);
    RCTLogInfo(@"file size %llu", fileSize);
}

void HandleInputBuffer(void *inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *inPacketDesc) {
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
    }
    
    //insert bytes into buffer
    TPCircularBufferProduceBytes(&pRecordState->mCircularBuffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    
    AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"data"];
}

- (void)dealloc {
    RCTLogInfo(@"dealloc");
    AudioQueueDispose(_recordState.mQueue, true);
}

@end
