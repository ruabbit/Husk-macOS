/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#include <pthread.h>

@interface MacAudio () {
@public
    AudioQueueRef queue;
    pthread_mutex_t mutex;
    int16_t ring[16384 * 2];
    NSUInteger head, count;
    NSUInteger callbacks;
    BOOL paused, closed;
}
@end
static void fill(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    MacAudio *audio = (__bridge MacAudio *)context;
    int16_t *output = buffer->mAudioData;
    pthread_mutex_lock(&audio->mutex);
    audio->callbacks++;
    NSUInteger available = audio->paused ? 0 : MIN(audio->count, 800);
    for (NSUInteger i=0; i<800; ++i) {
        output[i*2] = i < available ? audio->ring[((audio->head+i)%16384)*2] : 0;
        output[i*2+1] = i < available ? audio->ring[((audio->head+i)%16384)*2+1] : 0;
    }
    audio->head = (audio->head + available) % 16384; audio->count -= available;
    BOOL closed = audio->closed;
    pthread_mutex_unlock(&audio->mutex);
    buffer->mAudioDataByteSize = 800 * 4;
    if (!closed) AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

@implementation MacAudio {
    NSFileHandle *_capture;
    NSUInteger _capturedBytes;
}
- (instancetype)initMuted:(BOOL)muted capture:(NSString *)capture
{ return [self initMuted:muted capture:capture silentDevice:NO]; }
- (instancetype)initMuted:(BOOL)muted capture:(NSString *)capture silentDevice:(BOOL)silent
{
    if (!(self = [super init])) return nil;
    pthread_mutex_init(&mutex, NULL);
    if (capture) {
        [NSFileManager.defaultManager createFileAtPath:capture contents:[NSMutableData dataWithLength:44] attributes:nil];
        _capture = [NSFileHandle fileHandleForWritingAtPath:capture];
        [_capture seekToEndOfFile];
    }
    if (!muted) {
        AudioStreamBasicDescription format = {0};
        format.mSampleRate=48000; format.mFormatID=kAudioFormatLinearPCM;
        format.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
        format.mBytesPerPacket=4; format.mFramesPerPacket=1; format.mBytesPerFrame=4;
        format.mChannelsPerFrame=2; format.mBitsPerChannel=16;
        OSStatus status=AudioQueueNewOutput(&format,fill,(__bridge void *)self,NULL,NULL,0,&queue);
        if(status==noErr && silent) status=AudioQueueSetParameter(queue,kAudioQueueParam_Volume,0);
        for (int i=0; i<3 && status==noErr; i++) {
            AudioQueueBufferRef buffer;
            status=AudioQueueAllocateBuffer(queue,800*4,&buffer);
            if (status==noErr) fill((__bridge void *)self,queue,buffer);
        }
        if (status==noErr) status=AudioQueueStart(queue,NULL);
        if (status!=noErr) { [self close]; return nil; }
    }
    return self;
}
- (NSUInteger)callbackCount
{ pthread_mutex_lock(&mutex);NSUInteger value=callbacks;pthread_mutex_unlock(&mutex);return value; }
- (void)submit:(const int16_t *)samples frames:(NSUInteger)frames
{
    _sampleFrames += frames;
    for (NSUInteger i=0; i<frames*2; ++i) if (samples[i]) _nonzeroSamples++;
    if (_capture && _capturedBytes < 32*1024*1024) {
        NSData *data=[NSData dataWithBytes:samples length:frames*4];
        [_capture writeData:data]; _capturedBytes+=data.length;
    }
    if (!queue) return;
    pthread_mutex_lock(&mutex);
    if (!paused && !closed) {
        for (NSUInteger i=0; i<frames; ++i) {
            if (count==16384) { head=(head+1)%16384; count--; }
            NSUInteger offset=(head+count)%16384;
            ring[offset*2]=samples[i*2];ring[offset*2+1]=samples[i*2+1];count++;
        }
    }
    pthread_mutex_unlock(&mutex);
}
- (void)setPaused:(BOOL)value
{
    pthread_mutex_lock(&mutex); paused=value; count=0; head=0; pthread_mutex_unlock(&mutex);
    if (queue) { if (value) AudioQueuePause(queue); else AudioQueueStart(queue,NULL); }
}
- (void)close
{
    pthread_mutex_lock(&mutex); closed=YES; pthread_mutex_unlock(&mutex);
    if (queue) { AudioQueueStop(queue,true); AudioQueueDispose(queue,true); queue=NULL; }
    if (_capture) {
        uint8_t header[44]={0}; memcpy(header,"RIFF",4);memcpy(header+8,"WAVEfmt ",8);memcpy(header+36,"data",4);
        uint32_t length=(uint32_t)_capturedBytes, riff=length+36, fmt=16, rate=48000, bytes=192000;
        uint16_t pcm=1,channels=2,align=4,bits=16;
        memcpy(header+4,&riff,4);memcpy(header+16,&fmt,4);memcpy(header+20,&pcm,2);memcpy(header+22,&channels,2);
        memcpy(header+24,&rate,4);memcpy(header+28,&bytes,4);memcpy(header+32,&align,2);memcpy(header+34,&bits,2);memcpy(header+40,&length,4);
        [_capture seekToFileOffset:0];[_capture writeData:[NSData dataWithBytes:header length:44]];
        [_capture synchronizeFile];[_capture closeFile];_capture=nil;
    }
}
@end
