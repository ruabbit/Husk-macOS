// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Darwin

enum AtomicFile {
    static func write(_ data: Data, to target: URL) throws {
        let directory = target.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LibraryFailure("无法创建临时文件：\(target.lastPathComponent)") }
        var closed = false
        defer { if !closed { close(fd) }; unlink(temporary.path) }
        try data.withUnsafeBytes { buffer in
            var at = 0
            while at < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: at), buffer.count - at)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw LibraryFailure("写入资料失败；原文件已保留。") }
                at += count
            }
        }
        guard fsync(fd) == 0 else { throw LibraryFailure("无法同步资料到磁盘。") }
        let status = close(fd); closed = true
        guard status == 0, rename(temporary.path, target.path) == 0 else { throw LibraryFailure("无法原子替换资料文件。") }
        let dir = open(directory.path, O_RDONLY)
        guard dir >= 0 else { throw LibraryFailure("无法打开资料目录。") }
        defer { close(dir) }
        guard fsync(dir) == 0 else { throw LibraryFailure("无法同步资料目录。") }
    }
}
