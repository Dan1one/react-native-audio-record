#import <AVFoundation/AVFoundation.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTLog.h>
#import "TPCircularBuffer.h"

#define kNumberBuffers 3

typedef struct {
    __unsafe_unretained id      mSelf;
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberBuffers];
    AudioFileID                 mAudioFile;
    UInt32                      bufferByteSize;
    SInt64                      mCurrentPacket;
    bool                        mIsRunning;
    TPCircularBuffer                mCircularBuffer;
} AQRecordState;

@interface RNAudioRecord : RCTEventEmitter <RCTBridgeModule>
    @property (nonatomic, assign) AQRecordState recordState;
    @property (nonatomic, strong) NSString* filePath;
@property (nonatomic, strong) NSMutableArray *timestamps;
@property (nonatomic) UInt32 totalConsumedBytes;
@property (nonatomic) UInt32 totalBytes;
@property (nonatomic) CFAbsoluteTime latestTimestamp;

-(void)appendTimestamps:(AudioTimeStamp)timestamp withBytes:(UInt32)bytes;
-(void)consumeTimestampBytes:(UInt32)bytes;

@end
