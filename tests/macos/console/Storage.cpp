// SPDX-License-Identifier: GPL-2.0-or-later
// Links the real pinned PS4 core. No game, graphics, audio or JIT is initialized.
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include "common/logging/log.h"
#include "common/path_util.h"
#include "core/libraries/save_data/save_backup.h"

namespace fs = std::filesystem;
namespace Backup = Libraries::SaveData::Backup;
#define CHECK(x) do { if (!(x)) { std::cerr << "FAIL backup line " << __LINE__ << ": " #x "\n"; Backup::DrainAndJoin(); return 1; } } while (0)

static void Write(const fs::path& file, const std::string& text) {
    fs::create_directories(file.parent_path());
    std::ofstream out(file, std::ios::binary);
    out << text;
    out.close();
    if (!out) throw std::runtime_error("write test save");
}
static std::string Read(const fs::path& file) {
    std::ifstream in(file, std::ios::binary);
    if (!in) throw std::runtime_error("read test save");
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}
static fs::path Save(const fs::path& root, int i) {
    return root / "1/savedata" / ("TEST" + std::to_string(i)) / "slot";
}
static bool Submit(int i) {
    return Backup::NewRequest(1, "TEST" + std::to_string(i), "slot",
                              Backup::OrbisSaveDataEventType::BACKUP);
}
int main(int argc, char** argv) {
    CHECK(argc == 3);
    const fs::path root = argv[2];
    fs::create_directories(root);
    Common::FS::SetUserPath(Common::FS::PathType::HomeDir, root);
    Common::FS::SetUserPath(Common::FS::PathType::LogDir, root);
    Common::Log::SetConsoleOutput(false);
    Common::Log::Setup("backup-test.log");
    const std::string large(1024 * 1024 + 17, 'S');
    const std::string mode = argv[1];
    if (mode == "read") {
        for (int i = 0; i < 12; ++i) {
            CHECK(Read(Save(root, i)/"sce_backup/nested/save.dat") == large + std::to_string(i));
        }
        CHECK(Read(Save(root, 0)/"sce_backup/restarted.dat") == "second batch");
    } else if (mode == "write") {
        for (int i = 0; i < 12; ++i) Write(Save(root, i)/"nested/save.dat", large + std::to_string(i));
        Backup::StartThread();
        // Same directory name in different titles must not coalesce.
        for (int i = 0; i < 12; ++i) CHECK(Submit(i));
        Backup::StopThread();
        CHECK(!Submit(99));
        CHECK(Backup::DrainAndJoin());
        CHECK(Backup::DrainAndJoin());
        for (int i = 0; i < 12; ++i) {
            CHECK(Read(Save(root, i)/"sce_backup/nested/save.dat") == large + std::to_string(i));
            const auto event = Backup::PopLastEvent();
            CHECK(event && event->done && event->success && event->title_id == "TEST" + std::to_string(i));
        }
        CHECK(!Backup::PopLastEvent());
        Write(Save(root, 0)/"restarted.dat", "second batch");
        Backup::StartThread();
        CHECK(Submit(0));
        CHECK(Backup::DrainAndJoin());
        CHECK(!Submit(0));
    } else if (mode == "failure") {
        const auto save = Save(root, 0);
        Write(save/"sce_backup/previous.dat", "keep committed backup");
        // Filesystem refusal exercises actual production error handling, without a crash.
        fs::create_symlink("missing-target", save/"invalid-link");
        Backup::StartThread();
        CHECK(Submit(0));
        CHECK(!Backup::DrainAndJoin());
        CHECK(Read(save/"sce_backup/previous.dat") == "keep committed backup");
        const auto event = Backup::PopLastEvent();
        CHECK(event && event->done && !event->success);
        CHECK(!Submit(1));
        fs::remove(save/"invalid-link");
        Write(save/"valid.dat", "later success");
        Backup::StartThread();
        CHECK(Submit(0));
        CHECK(!Backup::DrainAndJoin()); // The earlier failure remains visible to the host.
        CHECK(Read(save/"sce_backup/valid.dat") == "later success");
    } else {
        CHECK(false);
    }
    Common::Log::Shutdown();
    std::cout << "PASS actual PS4 backup " << mode << "\n";
    return 0;
}
