/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-egl.h"
#include <EGL/egl.h>
#include <GLES3/gl31.h>
#include <string.h>
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
    tl_egl_es31_shim(true);
    RESOLVE(PFNGLCREATEPROGRAMPROC,glCreateProgram);RESOLVE(PFNGLATTACHSHADERPROC,glAttachShader);
    RESOLVE(PFNGLLINKPROGRAMPROC,glLinkProgram);RESOLVE(PFNGLGETPROGRAMIVPROC,glGetProgramiv);
    RESOLVE(PFNGLGETPROGRAMINFOLOGPROC,glGetProgramInfoLog);RESOLVE(PFNGLDELETEPROGRAMPROC,glDeleteProgram);
    RESOLVE(PFNGLGETPROGRAMINTERFACEIVPROC,glGetProgramInterfaceiv);RESOLVE(PFNGLGETPROGRAMRESOURCEINDEXPROC,glGetProgramResourceIndex);
    RESOLVE(PFNGLGETPROGRAMRESOURCENAMEPROC,glGetProgramResourceName);RESOLVE(PFNGLGETPROGRAMRESOURCEIVPROC,glGetProgramResourceiv);
    RESOLVE(PFNGLGETUNIFORMLOCATIONPROC,glGetUniformLocation);RESOLVE(PFNGLGETUNIFORMIVPROC,glGetUniformiv);
    const char *vertex="#version 310 es\nlayout(location=0) in vec4 pos; layout(std140,binding=2) uniform State { vec4 tint; }; out vec4 v; void main(){gl_Position=pos;v=tint;}";
    const char *fragment="#version 310 es\nprecision mediump float;\n#define UNITY_SUPPORTS_UNIFORM_LOCATION 1\n#if UNITY_SUPPORTS_UNIFORM_LOCATION\n#define UNITY_LOCATION(x) layout(location=x)\n#else\n#define UNITY_LOCATION(x)\n#endif\nUNITY_LOCATION(3) uniform sampler2D image;\nin vec4 v; out vec4 color; void main(){color=texture(image,vec2(0.5))*v;}";
    GLuint program=glCreateProgram(),shaders[2];
    for(int i=0;i<2;i++){
        shaders[i]=glCreateShader(i?GL_FRAGMENT_SHADER:GL_VERTEX_SHADER);
        const char *src=i?fragment:vertex;glShaderSource(shaders[i],1,&src,NULL);glCompileShader(shaders[i]);
        GLint ok=0;glGetShaderiv(shaders[i],GL_COMPILE_STATUS,&ok);
        if(!ok){char log[2048];glGetShaderInfoLog(shaders[i],sizeof(log),NULL,log);fprintf(stderr,"%s\n",log);}CHECK(ok);
        glAttachShader(program,shaders[i]);
    }
    glLinkProgram(program);GLint linked=0;glGetProgramiv(program,GL_LINK_STATUS,&linked);
    if(!linked){char log[2048];glGetProgramInfoLog(program,sizeof(log),NULL,log);fprintf(stderr,"%s\n",log);}CHECK(linked);
    GLint count=-77;glGetProgramInterfaceiv(program,GL_UNIFORM,GL_ACTIVE_RESOURCES,&count);CHECK(count>=2);
    glGetProgramInterfaceiv(program,GL_PROGRAM_INPUT,GL_ACTIVE_RESOURCES,&count);CHECK(count==1);
    glGetProgramInterfaceiv(program,GL_SHADER_STORAGE_BLOCK,GL_ACTIVE_RESOURCES,&count);CHECK(count==0);
    GLuint uniform=glGetProgramResourceIndex(program,GL_UNIFORM,"image"),block=glGetProgramResourceIndex(program,GL_UNIFORM_BLOCK,"State");
    CHECK(uniform!=GL_INVALID_INDEX && block!=GL_INVALID_INDEX);
    char name[64];GLsizei length=-1;glGetProgramResourceName(program,GL_UNIFORM,uniform,sizeof(name),&length,name);
    CHECK(length==5 && !strcmp(name,"image"));
    GLenum props[]={GL_TYPE,GL_LOCATION};GLint values[3]={-1,-1,765};
    glGetProgramResourceiv(program,GL_UNIFORM,uniform,2,props,2,&length,values);
    CHECK(length==2 && values[0]==GL_SAMPLER_2D && values[1]==glGetUniformLocation(program,"image") && values[2]==765);
    GLint unit=-1;glGetUniformiv(program,values[1],&unit);CHECK(unit==3);
    GLenum binding=GL_BUFFER_BINDING;glGetProgramResourceiv(program,GL_UNIFORM_BLOCK,block,1,&binding,1,&length,values);
    CHECK(length==1 && values[0]==2);
    void (*label)(unsigned,unsigned,int,int *,char *)=tl_egl_resolve("glGetObjectLabel");CHECK(label);
    strcpy(name,"unchanged");length=-1;label(0x82E4 /* GL_PROGRAM_PIPELINE */,0,sizeof(name),&length,name);CHECK(length==0 && name[0]==0);
    for(int i=0;i<2;i++)glDeleteShader(shaders[i]);glDeleteProgram(program);
    CHECK(eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT));
    CHECK(eglDestroySurface(display,surface));CHECK(eglDestroyContext(display,context));CHECK(eglTerminate(display));
    puts("PASS actual ANGLE external shaders, Unity ES31 program queries, sampler/block bindings and empty labels; no external image sampled");return 0;
}
