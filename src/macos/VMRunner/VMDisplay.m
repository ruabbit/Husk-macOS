/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "VMDisplay.h"
#include "husk-display.h"
#include <pthread.h>

@implementation VMDisplay {
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLSamplerState> _sampler;
    id<MTLTexture> _capture;
    NSLock *_lock;
    NSData *_pixels;
    int _width, _height;
    uint64_t _frames, _cpuSequence;
    NSMutableSet<NSString *> *_keys;
    BOOL _button;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    _lock=[NSLock new]; _keys=[NSMutableSet new]; self.wantsLayer=YES;
    _metalLayer=[CAMetalLayer layer]; _metalLayer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly=NO; _metalLayer.opaque=YES;
    _metalLayer.drawableSize=frame.size; _metalLayer.frame=self.bounds; self.layer=_metalLayer;
    return self;
}
- (CAMetalLayer *)metalLayer { return _metalLayer; }
- (uint64_t)frames { [_lock lock]; uint64_t n=_frames; [_lock unlock]; return n; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size]; _metalLayer.frame=self.bounds;
    _metalLayer.drawableSize=CGSizeMake(size.width*self.window.backingScaleFactor,size.height*self.window.backingScaleFactor);
}
- (BOOL)prepare:(id<MTLDevice>)device {
    if (_device==device && _pipeline) return YES;
    _device=device; _metalLayer.device=device; _queue=[device newCommandQueue];
    NSString *source=@"#include <metal_stdlib>\nusing namespace metal;\n"
    "struct V { float4 p [[position]]; float2 uv; };\n"
    "vertex V vertexMain(uint id [[vertex_id]], constant float4 &p [[buffer(0)]]) {"
    "float2 v[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};"
    "V o; o.p=float4(v[id]*p.yz,0,1); float2 u=v[id]*0.5+0.5; o.uv=float2(u.x,p.x>0.5?u.y:1-u.y); return o;}\n"
    "fragment float4 fragmentMain(V in [[stage_in]],texture2d<float> t [[texture(0)]],sampler s [[sampler(0)]]) {return float4(t.sample(s,in.uv).rgb,1);}";
    NSError *error=nil;
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];
    p.vertexFunction=[library newFunctionWithName:@"vertexMain"];p.fragmentFunction=[library newFunctionWithName:@"fragmentMain"];
    p.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    _pipeline=[device newRenderPipelineStateWithDescriptor:p error:&error];
    MTLSamplerDescriptor *s=[MTLSamplerDescriptor new];s.minFilter=MTLSamplerMinMagFilterLinear;s.magFilter=MTLSamplerMinMagFilterLinear;
    _sampler=[device newSamplerStateWithDescriptor:s];
    if (!_pipeline) fprintf(stderr,"[vm-display] %s\n",error.localizedDescription.UTF8String);
    return _pipeline!=nil;
}
- (void)render:(id<MTLTexture>)source into:(id<MTLTexture>)target flip:(BOOL)flip buffer:(id<MTLCommandBuffer>)buffer {
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);
    id<MTLRenderCommandEncoder> e=[buffer renderCommandEncoderWithDescriptor:pass];
    float sourceAspect=(float)source.width/source.height,targetAspect=(float)target.width/target.height;
    float params[4]={flip?1:0,sourceAspect<targetAspect?sourceAspect/targetAspect:1,sourceAspect>targetAspect?targetAspect/sourceAspect:1,0};
    [e setRenderPipelineState:_pipeline];[e setVertexBytes:params length:sizeof(params) atIndex:0];
    [e setFragmentTexture:source atIndex:0];[e setFragmentSamplerState:_sampler atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];
}
- (void)presentTexture:(id<MTLTexture>)texture flip:(BOOL)flip {
    @autoreleasepool {
        [_lock lock];
        if (![self prepare:texture.device]) { [_lock unlock]; return; }
        if (!_capture || _capture.width!=texture.width || _capture.height!=texture.height) {
            MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:texture.width height:texture.height mipmapped:NO];
            d.storageMode=MTLStorageModeShared; d.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
            _capture=[_device newTextureWithDescriptor:d];
        }
        id<MTLCommandBuffer> buffer=[_queue commandBuffer];
        [self render:texture into:_capture flip:flip buffer:buffer];
        id<CAMetalDrawable> drawable=self.visible?[_metalLayer nextDrawable]:nil;
        if (drawable) { [self render:texture into:drawable.texture flip:flip buffer:buffer];[buffer presentDrawable:drawable]; }
        [buffer commit];[buffer waitUntilCompleted];
        _width=(int)_capture.width;_height=(int)_capture.height;
        NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)_width*_height*4];
        [_capture getBytes:data.mutableBytes bytesPerRow:_width*4 fromRegion:MTLRegionMake2D(0,0,_width,_height) mipmapLevel:0];
        _pixels=data;_frames++;
        [_lock unlock];
    }
}
- (void)pollCPU {
    if (!self.ready || husk_display_sequence()==_cpuSequence) return;
    HuskFrameInfo frame;
    if (!husk_display_lock_frame(&frame)) return;
    if (!frame.pixels || frame.width<=0 || frame.height<=0 || frame.bpp!=32) { husk_display_unlock_frame(); return; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)frame.width*frame.height*4];
    for(int y=0;y<frame.height;y++) memcpy((char *)data.mutableBytes+y*frame.width*4,(const char *)frame.pixels+y*frame.stride,frame.width*4);
    int w=frame.width,h=frame.height;_cpuSequence=frame.sequence;husk_display_unlock_frame();
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;
    id<MTLTexture> texture=[device newTextureWithDescriptor:d];
    [texture replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:data.bytes bytesPerRow:w*4];
    [self presentTexture:texture flip:NO];
}
- (BOOL)screenshot:(NSString *)path {
    [_lock lock]; NSData *pixels=_pixels;int w=_width,h=_height;[_lock unlock];
    if (!pixels || !w || !h) return NO;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate((void *)pixels.bytes,w,h,8,w*4,cs,kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(cs);if(!ctx)return NO;
    CGImageRef image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];CGImageRelease(image);
    return [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
- (NSString *)qcode:(NSEvent *)event {
    NSDictionary *special=@{@36:@"ret",@48:@"tab",@49:@"spc",@51:@"backspace",@53:@"esc",@123:@"left",@124:@"right",@125:@"down",@126:@"up",@56:@"shift",@60:@"shift_r",@59:@"ctrl",@62:@"ctrl_r",@58:@"alt",@61:@"alt_r"};
    NSString *key=special[@(event.keyCode)] ?: event.charactersIgnoringModifiers.lowercaseString;
    return key.length?key:nil;
}
- (void)keyDown:(NSEvent *)event { NSString *key=[self qcode:event];if(self.ready&&key&&!event.isARepeat){husk_display_send_key(key.UTF8String,true);[_keys addObject:key];} }
- (void)keyUp:(NSEvent *)event { NSString *key=[self qcode:event];if(self.ready&&key){husk_display_send_key(key.UTF8String,false);[_keys removeObject:key];} }
- (void)flagsChanged:(NSEvent *)event {
    NSString *key=[self qcode:event];if(!self.ready||!key)return;
    BOOL down=![_keys containsObject:key];husk_display_send_key(key.UTF8String,down);
    if(down)[_keys addObject:key];else [_keys removeObject:key];
}
- (void)pointer:(NSEvent *)event down:(BOOL)down {
    if(!self.ready)return;
    int w=0,h=0;husk_display_guest_size(&w,&h);if(w<=0||h<=0){w=_width;h=_height;}if(w<=0||h<=0)return;
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    CGFloat scale=MIN(self.bounds.size.width/w,self.bounds.size.height/h);
    double x=(p.x-(self.bounds.size.width-w*scale)/2)/scale;
    double y=(self.bounds.size.height-p.y-(self.bounds.size.height-h*scale)/2)/scale;
    husk_display_send_pointer(MAX(0,MIN(w-1,x)),MAX(0,MIN(h-1,y)),down);_button=down;
}
- (void)mouseDown:(NSEvent *)e{[self pointer:e down:YES];}
- (void)mouseDragged:(NSEvent *)e{[self pointer:e down:YES];}
- (void)mouseUp:(NSEvent *)e{[self pointer:e down:NO];}
- (void)releaseInput { if(!self.ready)return;for(NSString *key in _keys)husk_display_send_key(key.UTF8String,false);[_keys removeAllObjects];if(_button)husk_display_send_pointer(0,0,false);_button=NO; }
@end
