/* SPDX-License-Identifier: GPL-2.0-or-later */
// Link the actual husk_module.cpp against controlled C API boundaries. This exercises
// the real wrapper's pthread and ABI, not a PS4 guest, SDL window, JIT or storage closure.
#include "platform/husk/husk_console_abi.h"
#include "platform/husk/host_surface.h"
#include "platform/ios/shadps4_ios_api.h"
#include "core/ios/ios_jit_allocator.h"
#include "core/pkg_extract/pkg_extractor.h"
#include <SDL3/SDL_events.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <pthread.h>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
std::mutex gate;
std::condition_variable changed;
bool prepared, allow_prepare, running, allow_run;
bool tls_entered, allow_tls;
std::atomic<int> tls_finished{}, joiners_started{}, joiners_finished{};
pthread_key_t tls_key;
std::atomic<int> stop_count{}, run_count{}, paused{}, self_join{};
std::string mode, seen_game, seen_args;
void (*first_frame)() = nullptr;
const HuskConsoleModuleV1* module;
bool Await(bool& flag) {
    std::unique_lock lock{gate};
    return changed.wait_for(lock, std::chrono::seconds(5), [&]{return flag;});
}
void Release(bool& flag) {
    std::scoped_lock lock{gate}; flag=true; changed.notify_all();
}
int WaitJoined() {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    int result=1;
    while ((result=module->join_worker())==1 && std::chrono::steady_clock::now()<deadline)
        std::this_thread::yield();
    return result;
}
}

namespace Core { void SetJitHost(const JitHost&) noexcept {} }
namespace Frontend {
void SetHuskHosted(bool) {}
void SetHostSurface(const HostSurface&) {}
void ResizeHostSurface(int,int) {}
void SetHostTextRequester(HostTextRequester) {}
}
extern "C" {
int shadps4_init(const ShadPS4Options*) {return 0;}
void shadps4_set_log_console(int) {}
void shadps4_set_log_filter(const char*) {}
void shadps4_register_first_frame_callback(void (*fn)()) {first_frame=fn;}
int shadps4_prepare_window_with_args(const char* game,const char* args) {
    {std::scoped_lock lock{gate}; seen_game=game;seen_args=args;prepared=true;changed.notify_all();}
    if(!Await(allow_prepare)) return -2;
    if(mode=="prepare-throw") throw std::runtime_error("controlled preparation error");
    return mode=="prepare-failure" ? -3 : 0;
}
int shadps4_run_loop() {
    ++run_count;
    if (mode=="tls-join") {
        if (pthread_key_create(&tls_key,+[](void*) {
            Release(tls_entered);
            if (Await(allow_tls)) {module->stop(); tls_finished=1;}
        })!=0 || pthread_setspecific(tls_key,&tls_key)!=0) return -5;
    }
    self_join=module->join_worker(); // the worker cannot join itself
    first_frame();
    {std::scoped_lock lock{gate};running=true;changed.notify_all();}
    if(!Await(allow_run)) return -4;
    if(mode=="run-throw") throw std::runtime_error("controlled run-loop error");
    return mode=="run-failure" ? 7 : 0;
}
void shadps4_stop() {++stop_count;}
uint64_t shadps4_get_presented_frame_count() {return 0;}
int shadps4_is_paused() {return paused;}
void shadps4_toggle_pause() {paused=!paused;}
void shadps4_apply_touch_input(uint32_t,int,int,int,int,int,int) {}
int shadps4_take_pending_restart(char*,int,char*,int) {return 0;}
bool SDL_PushEvent(SDL_Event*) {return true;}
int bachata_pkg_probe(int,BachataPkgProbe*) {return -1;}
int bachata_pkg_extract(int,const char*,const char*,void (*)(void*,uint64_t,uint64_t,const char*),void*) {return -1;}
}
#define CHECK(x) do {if(!(x)){std::fprintf(stderr,"FAIL actual wrapper line %d: %s\n",__LINE__,#x);return 1;}}while(0)
int main(int argc,char** argv) {
    CHECK(argc==2);mode=argv[1];
    module=husk_console_module_v1();
    CHECK(module && module->join_worker && module->join_worker()==0);
    HuskHostV1 host{};host.struct_size=sizeof(host);host.version=1;host.jit_size=1;
    host.jit_alloc=+[](size_t,void**)->void*{return nullptr;};
    host.jit_free=+[](void*,size_t)->int{return 0;};
    CHECK(module->init(&host,"unused")==0);
    module->stop(); // idle stop must not poison the only launch
    char game[]="owned-eboot.bin",args[]="first\nsecond";
    CHECK(module->launch(game,args,&host,1280,720,1)==0);
    std::memset(game,'x',sizeof(game)-1);std::memset(args,'x',sizeof(args)-1);
    CHECK(Await(prepared));
    CHECK(seen_game=="owned-eboot.bin" && seen_args=="first\nsecond");
    CHECK(module->state()==HUSK_CONSOLE_BOOTING && module->join_worker()==1);
    CHECK(module->launch("second",nullptr,&host,1280,720,1)!=0);
    if(mode=="stop-prepare") {
        module->stop();module->stop();CHECK(stop_count==0); // held until SDL preparation finishes
    }
    Release(allow_prepare);
    const bool prepare_error=mode=="prepare-failure" || mode=="prepare-throw";
    if(!prepare_error) {
        CHECK(Await(running) && run_count==1 && self_join==-1);
        CHECK(module->state()==HUSK_CONSOLE_RUNNING);
        module->set_paused(1);CHECK(module->state()==HUSK_CONSOLE_PAUSED);
        module->set_paused(0);CHECK(module->state()==HUSK_CONSOLE_RUNNING);
        if(mode=="stop-prepare") CHECK(stop_count==1);
        else if(mode=="stop-running") {module->stop();module->stop();CHECK(stop_count==1);}
        CHECK(module->join_worker()==1);
        Release(allow_run);
    }
    if (mode=="tls-join") {
        CHECK(Await(tls_entered)); // worker body is done, native TLS cleanup is still pending
        std::atomic<int> results[2]{};
        auto joiner=[&](int n){++joiners_started;results[n]=WaitJoined();++joiners_finished;};
        std::thread first{joiner,0},second{joiner,1};
        while(joiners_started!=2) std::this_thread::yield();
        const bool pending=joiners_finished==0;
        Release(allow_tls);
        first.join();second.join();
        CHECK(pending && tls_finished==1 && results[0]==0 && results[1]==0);
        pthread_key_delete(tls_key);
    }
    CHECK(WaitJoined()==0 && module->join_worker()==0);
    const bool failed=prepare_error || mode=="run-failure" || mode=="run-throw";
    CHECK(module->state()==(failed ? HUSK_CONSOLE_FAILED : HUSK_CONSOLE_STOPPED));
    CHECK(run_count==(prepare_error ? 0 : 1));
    const int stops=stop_count;module->stop();CHECK(stop_count==stops);
    first_frame(); // a late renderer callback cannot resurrect a terminal session
    CHECK(module->state()==(failed ? HUSK_CONSOLE_FAILED : HUSK_CONSOLE_STOPPED));
    CHECK(module->launch("again",nullptr,&host,1280,720,1)!=0);
    std::printf("PASS actual module wrapper %s: owner join, ordered stop, stable result; no guest/storage claim\n",argv[1]);
    return 0;
}
