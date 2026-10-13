// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Keep the beginning and the most recent output while continuously draining
/// the child. A noisy loader must not hide the eventual fatal error.
final class SessionDiagnostics {
    static let segmentLimit = 2 << 20
    static let headLimit = 512 << 10
    let directory: URL
    private var current: FileHandle
    private var head: FileHandle
    private var currentBytes = 0
    private var headBytes = 0
    private(set) var totalBytes: UInt64 = 0
    private(set) var rotations = 0
    private(set) var writeError: String?

    init(directory: URL) throws {
        self.directory = directory
        let currentURL = directory.appendingPathComponent("stderr.log")
        let headURL = directory.appendingPathComponent("stderr.first.log")
        try Data().write(to: currentURL); try Data().write(to: headURL)
        current = try FileHandle(forWritingTo: currentURL)
        head = try FileHandle(forWritingTo: headURL)
    }

    func append(_ data: Data) {
        totalBytes += UInt64(data.count)
        do {
            if headBytes < Self.headLimit {
                let bytes = data.prefix(Self.headLimit - headBytes)
                try head.write(contentsOf: bytes); headBytes += bytes.count
            }
            var offset = 0
            while offset < data.count {
                if currentBytes == Self.segmentLimit {
                    try current.close()
                    let previous = directory.appendingPathComponent("stderr.previous.log")
                    let url = directory.appendingPathComponent("stderr.log")
                    // POSIX rename replaces the older segment atomically.
                    guard rename(url.path, previous.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                    try Data().write(to: url)
                    current = try FileHandle(forWritingTo: url); currentBytes = 0; rotations += 1
                }
                let count = min(data.count - offset, Self.segmentLimit - currentBytes)
                try current.write(contentsOf: data[offset..<(offset + count)])
                offset += count; currentBytes += count
            }
        } catch { writeError = error.localizedDescription }
    }

    func record(_ fields: [String: Any]) {
        var value = fields
        value["schema"] = 1
        value["stderrBytes"] = totalBytes
        value["stderrRotations"] = rotations
        value["stderrOrder"] = rotations > 1 ? ["stderr.first.log", "stderr.previous.log", "stderr.log"]
            : rotations == 1 ? ["stderr.previous.log", "stderr.log"] : ["stderr.log"]
        value["stderrMiddleDiscarded"] = rotations > 1
        if let writeError { value["diagnosticWriteError"] = writeError }
        do { try AtomicFile.write(JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                                  to: directory.appendingPathComponent("supervisor.json")) }
        catch { writeError = error.localizedDescription }
    }

    func close() { try? current.close(); try? head.close() }
    deinit { close() }
}
