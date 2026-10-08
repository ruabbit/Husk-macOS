/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import "MacInput.h"
#import "MacAudio.h"
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <math.h>
#define CHECK(value, name) do { if(!(value)){fprintf(stderr,"FAIL %s\n",name);return 1;}puts("PASS " name); } while(0)
int main(int argc,const char **argv)
{
    @autoreleasepool {
        MacInput input;mac_input_clear(&input);
        mac_input_pointer(&input,400,400,800,800,true);
        OrbitInput frame=mac_input_frame(&input);
        CHECK(frame.pointerDown&&frame.pointerX==320&&frame.pointerY==200,"letterbox-input-coordinates");
        mac_input_pointer(&input,400,50,800,800,true);frame=mac_input_frame(&input);
        CHECK(!frame.pointerDown,"letterbox-bars-ignore-clicks");
        mac_input_key(&input,124,true);mac_input_controller(&input,1,0,false);frame=mac_input_frame(&input);
        CHECK(frame.x==1,"keyboard-controller-combination-clamped");
        mac_input_clear(&input);mac_input_controller(&input,.1,-.1,false);frame=mac_input_frame(&input);
        CHECK(frame.x==0&&frame.y==0,"controller-dead-zone");
        mac_input_controller(&input,NAN,INFINITY,false);frame=mac_input_frame(&input);
        CHECK(frame.x==0&&frame.y==0,"invalid-axes-rejected");
        MacAudio *audio=[[MacAudio alloc] initMuted:NO capture:nil silentDevice:YES];
        CHECK(audio,"AudioQueue-created-at-zero-output-gain");
        int16_t samples[1600];for(int i=0;i<1600;i++)samples[i]=(i%80<40)?1200:-1200;
        for(int i=0;i<12;i++){[audio submit:samples frames:800];[NSThread sleepForTimeInterval:1.0/60];}
        CHECK(audio.callbackCount>3,"real-audio-device-consumes-PCM-silently");
        [audio setPaused:YES];[audio setPaused:NO];[audio close];
        if(argc<2)return 0;
        void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
        if(!library){fprintf(stderr,"%s\n",dlerror());return 1;}
        PFN_vkGetInstanceProcAddr proc=dlsym(library,"vkGetInstanceProcAddr");
        CHECK(proc,"MoltenVK-vkGetInstanceProcAddr");
        PFN_vkCreateInstance create=(void *)proc(NULL,"vkCreateInstance");
        CHECK(create,"MoltenVK-vkCreateInstance-entry");
        VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="Husk macOS verification",.apiVersion=VK_API_VERSION_1_0};
        // Direct MoltenVK ICD entry point. portability_enumeration belongs to
        // the Vulkan Loader, which this runtime does not use.
        VkInstanceCreateInfo config={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
        VkInstance instance=NULL;
        CHECK(create(&config,NULL,&instance)==VK_SUCCESS,"MoltenVK-instance-created");
        PFN_vkEnumeratePhysicalDevices enumerate=(void *)proc(instance,"vkEnumeratePhysicalDevices");
        PFN_vkDestroyInstance destroy=(void *)proc(instance,"vkDestroyInstance");
        uint32_t count=0;
        CHECK(enumerate&&destroy&&enumerate(instance,&count,NULL)==VK_SUCCESS&&count>0,"MoltenVK-Metal-device-enumerated");
        destroy(instance,NULL);dlclose(library);
    }
    return 0;
}
