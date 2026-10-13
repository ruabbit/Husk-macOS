/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include "husk-tl-vulkan.h"
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(c) do { if(!(c)){fprintf(stderr,"FAIL Vulkan loader line %d: %s\n",__LINE__,#c);return 1;} }while(0)
int main(int argc,char **argv) {
    if(argc!=2)return 64;
    void *(*open_library)(const char *,int)=tl_bionic_find("dlopen");
    void *(*find_symbol)(void *,const char *)=tl_bionic_find("dlsym");
    CHECK(open_library&&find_symbol);
    CHECK(!open_library("libvulkan.so",2)&&!open_library("libvulkan.so.1",2));
    tl_vk_configure(argv[1],NULL,0);
    void *canonical=open_library("libvulkan.so",2),*alias=open_library("libvulkan.so.1",2);
    CHECK(canonical&&alias==canonical);
    CHECK(tl_bionic_is_system_lib("libvulkan.so.1"));
    PFN_vkGetInstanceProcAddr gipa=find_symbol(alias,"vkGetInstanceProcAddr");CHECK(gipa);
    PFN_vkEnumerateInstanceExtensionProperties enumerate=(PFN_vkEnumerateInstanceExtensionProperties)gipa(NULL,"vkEnumerateInstanceExtensionProperties");CHECK(enumerate);
    uint32_t count=0;CHECK(enumerate(NULL,&count,NULL)==VK_SUCCESS&&count);
    VkExtensionProperties *extensions=calloc(count,sizeof(*extensions));CHECK(extensions);
    CHECK(enumerate(NULL,&count,extensions)==VK_SUCCESS);
    int android=0;for(unsigned i=0;i<count;i++)if(!strcmp(extensions[i].extensionName,"VK_KHR_android_surface"))android=1;
    free(extensions);CHECK(android);
    PFN_vkCreateInstance create=(PFN_vkCreateInstance)gipa(NULL,"vkCreateInstance");CHECK(create);
    const char *requested[]={"VK_KHR_surface","VK_KHR_android_surface"};
    VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_1};
    VkInstanceCreateInfo info={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app,.enabledExtensionCount=2,.ppEnabledExtensionNames=requested};
    VkInstance instance;CHECK(create(&info,NULL,&instance)==VK_SUCCESS);
    PFN_vkEnumeratePhysicalDevices physical=(PFN_vkEnumeratePhysicalDevices)gipa(instance,"vkEnumeratePhysicalDevices");
    PFN_vkDestroyInstance destroy=(PFN_vkDestroyInstance)gipa(instance,"vkDestroyInstance");CHECK(physical&&destroy);
    count=0;CHECK(physical(instance,&count,NULL)==VK_SUCCESS&&count>0);destroy(instance,NULL);
    puts("PASS versioned Vulkan loader, availability gate, Android extensions and real MoltenVK instance");return 0;
}
