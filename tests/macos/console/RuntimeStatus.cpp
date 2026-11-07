/* SPDX-License-Identifier: GPL-2.0-or-later */
// Actual core, no prepared window: reject invalid lifecycle calls before guest, mounts,
// graphics or audio initialization. This does not execute a PS4 game.
#include "emulator.h"
#include "core/thread.h"
#include "platform/ios/shadps4_ios_api.h"
#include <atomic>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <pthread.h>
#include <thread>

namespace {
std::mutex gate;
std::condition_variable changed;
bool tls_entered, allow_tls;
std::atomic<int> tls_finished{}, self_join{}, joined{};
pthread_key_t key;
bool Await(bool& flag) {
    std::unique_lock lock{gate};
    return changed.wait_for(lock,std::chrono::seconds(5),[&]{return flag;});
}
void Release(bool& flag) {std::scoped_lock lock{gate};flag=true;changed.notify_all();}
void* Worker(void* opaque) {
    auto& owner=*static_cast<Core::NativeThread*>(opaque);
    owner.Initialize();
    self_join=owner.Join();
    if(pthread_setspecific(key,opaque)!=0) return nullptr;
    owner.PrepareExit();
    return nullptr; // pthread still has native TLS to destroy after the entry function returns
}
}
#define CHECK(x) do {if(!(x)){std::fprintf(stderr,"FAIL actual runtime status line %d: %s\n",__LINE__,#x);return 1;}}while(0)
int main() {
    CHECK(shadps4_run_loop()!=0);
    Core::Emulator emulator;
    CHECK(emulator.RuntimeResult()==0 && emulator.GetWindow()==nullptr);
    emulator.RunLoop();
    CHECK(emulator.RuntimeResult()!=0 && emulator.GetWindow()==nullptr);
    emulator.RunLoop();
    CHECK(emulator.RuntimeResult()!=0);
    CHECK(pthread_key_create(&key,+[](void*) {
        Release(tls_entered);
        if(Await(allow_tls)) tls_finished=1;
    })==0);
    Core::NativeThread worker;
    CHECK(worker.Create(Worker,&worker)==0 && Await(tls_entered));
    CHECK(self_join==EDEADLK && worker.GetHandle()!=0);
    int result=-1;
    std::thread joiner{[&]{result=worker.Join();joined=1;}};
    const bool pending=joined==0;
    Release(allow_tls);
    joiner.join();
    CHECK(pending && result==0 && joined==1 && tls_finished==1);
    CHECK(worker.GetHandle()==0 && worker.Join()==0);
    pthread_key_delete(key);
    std::puts("PASS actual core rejects unprepared execution; real NativeThread joins after TLS with owner retained; no guest/audio/graphics");
    return 0;
}
