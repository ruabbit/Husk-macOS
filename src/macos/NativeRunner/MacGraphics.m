/* SPDX-License-Identifier: GPL-2.0-or-later */
#import "MacGraphics.h"
#import <AppKit/AppKit.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <dlfcn.h>

@implementation MacGraphics {
    void *_library;
    EGLDisplay _display;
    EGLContext _context;
    EGLSurface _surface;
    PFNEGLGETPROCADDRESSPROC _proc;
    PFNEGLMAKECURRENTPROC _makeCurrent;
    PFNEGLSWAPBUFFERSPROC _swap;
    PFNEGLDESTROYSURFACEPROC _destroySurface;
    PFNEGLDESTROYCONTEXTPROC _destroyContext;
    PFNEGLTERMINATEPROC _terminate;
    PFNGLREADPIXELSPROC _readPixels;
    PFNGLFINISHPROC _finish;
    BOOL _offscreen;
}
- (instancetype)initWithLibrary:(NSString *)path layer:(CAMetalLayer *)layer error:(NSError **)error
{
    if (!(self = [super init])) return nil;
    _offscreen = layer == nil;
    const char *stage = "dlopen";
    _library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_library) goto failed;
    stage = "entry-points";
    _proc = dlsym(_library, "eglGetProcAddress");
    if (!_proc) goto failed;
    PFNEGLGETPLATFORMDISPLAYEXTPROC getDisplay = (void *)_proc("eglGetPlatformDisplayEXT");
    PFNEGLINITIALIZEPROC initialize = dlsym(_library, "eglInitialize");
    PFNEGLCHOOSECONFIGPROC choose = dlsym(_library, "eglChooseConfig");
    PFNEGLCREATECONTEXTPROC createContext = dlsym(_library, "eglCreateContext");
    PFNEGLCREATEWINDOWSURFACEPROC windowSurface = dlsym(_library, "eglCreateWindowSurface");
    PFNEGLCREATEPBUFFERSURFACEPROC pbuffer = dlsym(_library, "eglCreatePbufferSurface");
    _makeCurrent = dlsym(_library, "eglMakeCurrent"); _swap = dlsym(_library, "eglSwapBuffers");
    _destroySurface = dlsym(_library, "eglDestroySurface"); _destroyContext = dlsym(_library, "eglDestroyContext");
    _terminate = dlsym(_library, "eglTerminate");
    if (!getDisplay || !initialize || !choose || !createContext || !windowSurface || !pbuffer || !_makeCurrent ||
        !_swap || !_destroySurface || !_destroyContext || !_terminate) goto failed;
    EGLint attributes[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE};
    stage = "display-initialize";
    _display = getDisplay(EGL_PLATFORM_ANGLE_ANGLE, NULL, attributes);
    EGLint major, minor;
    if (!_display || !initialize(_display, &major, &minor)) goto failed;
    EGLint configAttributes[] = {EGL_SURFACE_TYPE, layer ? EGL_WINDOW_BIT : EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
    EGLConfig config; EGLint count;
    stage = "choose-config";
    if (!choose(_display, configAttributes, &config, 1, &count) || count != 1) goto failed;
    EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    stage = "context-and-surface";
    _context = createContext(_display, config, EGL_NO_CONTEXT, contextAttributes);
    EGLint surfaceAttributes[] = {EGL_WIDTH, 640, EGL_HEIGHT, 400, EGL_NONE};
    _surface = layer ? windowSurface(_display, config, (__bridge void *)layer, NULL) : pbuffer(_display, config, surfaceAttributes);
    if (!_context || !_surface || !_makeCurrent(_display, _surface, _surface, _context)) goto failed;
    stage = "gles-entry-points";
    PFNGLVIEWPORTPROC viewport = (void *)_proc("glViewport");
    _readPixels = (void *)_proc("glReadPixels"); _finish = (void *)_proc("glFinish");
    if (!viewport || !_readPixels || !_finish) goto failed;
    viewport(0, 0, 640, 400);
    return self;
failed:
    {
        PFNEGLGETERRORPROC getError = _library ? dlsym(_library, "eglGetError") : NULL;
        const char *loaderError = dlerror();
        fprintf(stderr, "graphics: %s failed; EGL=%#x; dlerror=%s; path=%s\n", stage,
            getError ? getError() : 0, loaderError ?: "none", path.fileSystemRepresentation);
    }
    if (error) *error = [NSError errorWithDomain:@"HuskGraphics" code:1 userInfo:@{NSLocalizedDescriptionKey: @"ANGLE / Metal 图形初始化失败。"}];
    [self close]; return nil;
}
- (void *)symbol:(const char *)name { return _proc ? (void *)_proc(name) : NULL; }
- (BOOL)present
{
    // ANGLE's Metal pbuffer swap is a no-op. Without an explicit completion,
    // headless frames accumulate unsubmitted Metal commands indefinitely.
    if (_offscreen) { if (!_finish) return NO; _finish(); return YES; }
    return _swap && _swap(_display, _surface);
}
- (BOOL)capture:(NSString *)path
{
    if (!_readPixels) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:640 * 400 * 4];
    _finish(); _readPixels(0, 0, 640, 400, GL_RGBA, GL_UNSIGNED_BYTE, pixels.mutableBytes);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:640 pixelsHigh:400
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:640*4 bitsPerPixel:32];
    for (int row = 0; row < 400; row++) memcpy(bitmap.bitmapData + row * 640 * 4, (char *)pixels.bytes + (399-row) * 640 * 4, 640 * 4);
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png && [png writeToFile:path options:NSDataWritingAtomic error:NULL];
}
- (void)close
{
    if (_display && _makeCurrent) _makeCurrent(_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (_surface && _destroySurface) _destroySurface(_display, _surface);
    if (_context && _destroyContext) _destroyContext(_display, _context);
    if (_display && _terminate) _terminate(_display);
    _surface = NULL; _context = NULL; _display = NULL;
    if (_library) dlclose(_library); _library = NULL;
}
@end
