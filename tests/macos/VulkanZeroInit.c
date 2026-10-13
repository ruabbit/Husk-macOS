/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compile a zero-initialized workgroup array without a WorkgroupSize builtin.
 * The unpatched SPIRV-Cross emits an undeclared gl_WorkGroupSize in its MSL. */
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#define OP(code, count) (((count) << 16) | (code))
static const uint32_t shader[] = {
    0x07230203,0x00010300,0,14,0,
    OP(17,2),1, OP(14,3),0,1, OP(15,5),5,1,0x6e69616d,0,
    OP(16,6),1,17,4,1,1,
    OP(19,2),2, OP(33,3),3,2, OP(21,4),4,32,0, OP(43,4),4,5,8,
    OP(28,4),6,4,5, OP(32,4),7,4,6, OP(46,3),6,8, OP(59,5),7,9,4,8,
    OP(43,4),4,10,0, OP(32,4),11,4,4, OP(54,5),2,1,0,3,
    OP(248,2),12, OP(65,5),11,13,9,10, OP(62,3),13,10, OP(253,1), OP(56,1)
};
#define CHECK(call) do { VkResult r=(call); if(r!=VK_SUCCESS){fprintf(stderr,"%s returned %d\n",#call,r);return 1;} }while(0)
#define LOAD(name) PFN_##name name=(PFN_##name)dlsym(library,#name);if(!name)return 2
int main(int argc,char **argv) {
    if(argc!=2)return 64;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!library){fprintf(stderr,"%s\n",dlerror());return 2;}
    LOAD(vkCreateInstance);LOAD(vkEnumeratePhysicalDevices);LOAD(vkGetPhysicalDeviceQueueFamilyProperties);
    LOAD(vkGetPhysicalDeviceFeatures2);LOAD(vkCreateDevice);LOAD(vkCreateShaderModule);LOAD(vkCreatePipelineLayout);
    LOAD(vkCreateComputePipelines);LOAD(vkDestroyPipeline);LOAD(vkDestroyPipelineLayout);LOAD(vkDestroyShaderModule);
    LOAD(vkDestroyDevice);LOAD(vkDestroyInstance);
    VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="Husk shader regression",.apiVersion=VK_API_VERSION_1_1};
    /* This loads the ICD directly, without the Vulkan loader's enumeration extension. */
    VkInstanceCreateInfo info={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
    VkInstance instance;CHECK(vkCreateInstance(&info,NULL,&instance));
    uint32_t count=1;VkPhysicalDevice physical;CHECK(vkEnumeratePhysicalDevices(instance,&count,&physical));if(!count)return 2;
    uint32_t queues=0;vkGetPhysicalDeviceQueueFamilyProperties(physical,&queues,NULL);
    VkQueueFamilyProperties *properties=calloc(queues,sizeof(*properties));vkGetPhysicalDeviceQueueFamilyProperties(physical,&queues,properties);
    uint32_t family=0;while(family<queues&&!(properties[family].queueFlags&VK_QUEUE_COMPUTE_BIT))family++;free(properties);if(family==queues)return 2;
    VkPhysicalDeviceZeroInitializeWorkgroupMemoryFeatures zero={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ZERO_INITIALIZE_WORKGROUP_MEMORY_FEATURES};
    VkPhysicalDeviceFeatures2 features={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,.pNext=&zero};
    vkGetPhysicalDeviceFeatures2(physical,&features);if(!zero.shaderZeroInitializeWorkgroupMemory)return 2;
    float priority=1;VkDeviceQueueCreateInfo queue={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=family,.queueCount=1,.pQueuePriorities=&priority};
    const char *deviceExtensions[]={"VK_KHR_portability_subset",VK_KHR_ZERO_INITIALIZE_WORKGROUP_MEMORY_EXTENSION_NAME};
    VkDeviceCreateInfo deviceInfo={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&zero,.queueCreateInfoCount=1,.pQueueCreateInfos=&queue,
        .enabledExtensionCount=2,.ppEnabledExtensionNames=deviceExtensions};
    VkDevice device;CHECK(vkCreateDevice(physical,&deviceInfo,NULL,&device));
    VkShaderModuleCreateInfo source={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=sizeof(shader),.pCode=shader};
    VkShaderModule module;CHECK(vkCreateShaderModule(device,&source,NULL,&module));
    VkPipelineLayoutCreateInfo layoutInfo={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    VkPipelineLayout layout;CHECK(vkCreatePipelineLayout(device,&layoutInfo,NULL,&layout));
    VkComputePipelineCreateInfo compute={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,.layout=layout,
        .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=module,.pName="main"}};
    VkPipeline pipeline;CHECK(vkCreateComputePipelines(device,VK_NULL_HANDLE,1,&compute,NULL,&pipeline));
    vkDestroyPipeline(device,pipeline,NULL);vkDestroyPipelineLayout(device,layout,NULL);vkDestroyShaderModule(device,module,NULL);
    vkDestroyDevice(device,NULL);vkDestroyInstance(instance,NULL);dlclose(library);
    puts("PASS bundled MoltenVK compiles zero-initialized workgroup arrays without WorkgroupSize");return 0;
}
