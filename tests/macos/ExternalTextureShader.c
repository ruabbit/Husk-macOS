/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-egl.h"
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL shader line %d: %s\n",__LINE__,#c); return 1; } } while (0)
void tl_log_line(const char *format, ...) { (void)format; }
#define RESOLVE(type,name) type name=(type)tl_egl_resolve(#name); CHECK(name)
int main(int argc,char **argv) {
    if(argc!=2)return 64;
    CHECK(tl_egl_init(argv[1],NULL,NULL,0));
    RESOLVE(PFNEGLGETDISPLAYPROC,eglGetDisplay);RESOLVE(PFNEGLINITIALIZEPROC,eglInitialize);
    RESOLVE(PFNEGLBINDAPIPROC,eglBindAPI);RESOLVE(PFNEGLCHOOSECONFIGPROC,eglChooseConfig);
    RESOLVE(PFNEGLCREATECONTEXTPROC,eglCreateContext);RESOLVE(PFNEGLCREATEPBUFFERSURFACEPROC,eglCreatePbufferSurface);
    RESOLVE(PFNEGLMAKECURRENTPROC,eglMakeCurrent);RESOLVE(PFNEGLDESTROYCONTEXTPROC,eglDestroyContext);
    RESOLVE(PFNEGLDESTROYSURFACEPROC,eglDestroySurface);RESOLVE(PFNEGLTERMINATEPROC,eglTerminate);
    EGLDisplay display=eglGetDisplay(EGL_DEFAULT_DISPLAY);CHECK(display!=EGL_NO_DISPLAY);
    EGLint major,minor,n=0;CHECK(eglInitialize(display,&major,&minor));CHECK(eglBindAPI(EGL_OPENGL_ES_API));
    const EGLint want[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_NONE};
    EGLConfig config;CHECK(eglChooseConfig(display,want,&config,1,&n)&&n>0);
    const EGLint ctx[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE},size[]={EGL_WIDTH,4,EGL_HEIGHT,4,EGL_NONE};
    EGLContext context=eglCreateContext(display,config,EGL_NO_CONTEXT,ctx);CHECK(context!=EGL_NO_CONTEXT);
    EGLSurface surface=eglCreatePbufferSurface(display,config,size);CHECK(surface!=EGL_NO_SURFACE);
    CHECK(eglMakeCurrent(display,surface,surface,context));
    RESOLVE(PFNGLCREATESHADERPROC,glCreateShader);RESOLVE(PFNGLSHADERSOURCEPROC,glShaderSource);
    RESOLVE(PFNGLCOMPILESHADERPROC,glCompileShader);RESOLVE(PFNGLGETSHADERIVPROC,glGetShaderiv);
    RESOLVE(PFNGLGETSHADERINFOLOGPROC,glGetShaderInfoLog);RESOLVE(PFNGLDELETESHADERPROC,glDeleteShader);
    /* Segmented source and explicit lengths exercise the guest wrapper too. */
    const char *parts[]={"#version 300 es\n", "#extension GL_OES_EGL_image_external_essl3 : require\n",
        "precision mediump float; uniform samplerExternalOES video; out vec4 color;\nvoid main(){color=texture(video,vec2(0.5));}\n"};
    const char *plain="#version 300 es\nprecision mediump float; out vec4 color; void main(){color=vec4(1.0);}";
    for(int shim=0;shim<2;shim++)for(int external=0;external<2;external++) {
        tl_egl_es31_shim(shim!=0);GLuint shader=glCreateShader(GL_FRAGMENT_SHADER);CHECK(shader);
        if(external) { const GLint lengths[]={16,-1,-1};glShaderSource(shader,3,parts,lengths); }
        else glShaderSource(shader,1,&plain,NULL);
        glCompileShader(shader);GLint ok=0;glGetShaderiv(shader,GL_COMPILE_STATUS,&ok);
        if(!ok) { char log[2048];glGetShaderInfoLog(shader,sizeof(log),NULL,log);fprintf(stderr,"%s\n",log); }
        CHECK(ok);glDeleteShader(shader);
    }
    CHECK(eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT));
    CHECK(eglDestroySurface(display,surface));CHECK(eglDestroyContext(display,context));CHECK(eglTerminate(display));
    puts("PASS actual ANGLE external/ordinary shader compilation with ES31 shim enabled and disabled; no external image sampled");return 0;
}
