// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CryptoKit
import Security

/// Verifies APK v2/v3 signatures and Android's chunked content digest. Certificate
/// identity is used for update continuity, not as a claim of Play provenance.
public enum APKSignature {
    private static func fail() -> LibraryFailure { LibraryFailure("APK 签名无效、内容已改变或使用了尚不支持的签名格式。") }
    private struct Reader {
        let data: Data
        var offset = 0
        var remaining: Int { data.count - offset }
        mutating func take(_ n: Int) throws -> Data {
            guard n >= 0, n <= remaining else { throw fail() }
            defer { offset += n }; return data.subdata(in: offset..<offset+n)
        }
        mutating func number(_ n: Int) throws -> UInt64 {
            let bytes = try take(n)
            return bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        mutating func block() throws -> Data { try take(Int(number(4))) }
    }
    private static func number(_ data: Data, _ offset: Int, _ n: Int) throws -> UInt64 {
        var reader = Reader(data: data, offset: offset); return try reader.number(n)
    }
    private static func little(_ n: Int) -> Data {
        var n = UInt32(n).littleEndian; return withUnsafeBytes(of: &n) { Data($0) }
    }
    private static func hash(_ data: Data, sha512: Bool) -> Data {
        sha512 ? Data(SHA512.hash(data: data)) : Data(SHA256.hash(data: data))
    }
    public static func verify(_ file: URL) throws -> [String]? {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count >= 22, data.count < Int(UInt32.max) else { throw fail() }
        let lower = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
            (try? number(data, $0, 4)) == 0x06054b50 &&
                (try? number(data, $0 + 20, 2)) == UInt64(data.count - $0 - 22)
        }) else { throw fail() }
        let cd = Int(try number(data, end + 16, 4))
        guard cd >= 0, cd <= end, Int(try number(data, end + 12, 4)) == end - cd,
              try number(data, end + 4, 4) == 0 else { throw fail() }
        guard cd >= 24, data.subdata(in: cd-16..<cd) == Data("APK Sig Block 42".utf8) else { return nil }
        let size = try number(data, cd - 24, 8)
        guard size >= 24, size <= UInt64(cd - 8), size <= 16 << 20 else { throw fail() }
        let start = cd - Int(size) - 8
        guard try number(data, start, 8) == size else { throw fail() }
        var pairs = Reader(data: data.subdata(in: start+8..<cd-24))
        var schemes: [UInt64: Data] = [:]
        while pairs.remaining > 0 {
            let length = try pairs.number(8)
            guard length >= 4, length <= UInt64(pairs.remaining) else { throw fail() }
            var pair = Reader(data: try pairs.take(Int(length)))
            let id = try pair.number(4)
            guard schemes[id] == nil else { throw fail() }
            schemes[id] = try pair.take(pair.remaining)
        }
        // v3.1 key rotation is intentionally not inferred. Require the same
        // verified signer on updates until lineage verification is implemented.
        let isV3 = schemes[0xf05368c0] != nil
        guard let block = schemes[isV3 ? 0xf05368c0 : 0x7109871a] else { throw fail() }
        var outer = Reader(data: block)
        var signers = Reader(data: try outer.block())
        guard outer.remaining == 0 else { throw fail() }
        var certificates: [String] = [], cachedDigests: [Bool: Data] = [:]
        while signers.remaining > 0 {
            guard certificates.count < 16 else { throw fail() }
            var signer = Reader(data: try signers.block())
            let signedBytes = try signer.block()
            let sdk = isV3 ? try signer.take(8) : Data()
            var signatures = Reader(data: try signer.block())
            let publicKey = try signer.block()
            guard signer.remaining == 0 else { throw fail() }
            var records: [(UInt64, Data)] = []
            while signatures.remaining > 0 {
                var record = Reader(data: try signatures.block())
                let id = try record.number(4), signature = try record.block()
                guard record.remaining == 0 else { throw fail() }
                records.append((id, signature))
            }
            let supported: [UInt64: (SecKeyAlgorithm, Bool)] = [
                0x0101: (.rsaSignatureMessagePSSSHA256, false), 0x0102: (.rsaSignatureMessagePSSSHA512, true),
                0x0103: (.rsaSignatureMessagePKCS1v15SHA256, false), 0x0104: (.rsaSignatureMessagePKCS1v15SHA512, true),
                0x0201: (.ecdsaSignatureMessageX962SHA256, false), 0x0202: (.ecdsaSignatureMessageX962SHA512, true)]
            guard let selected = records.filter({ supported[$0.0] != nil }).max(by: {
                (supported[$0.0]!.1 ? 2 : 1) < (supported[$1.0]!.1 ? 2 : 1)
            }), let (algorithm, sha512) = supported[selected.0] else { throw fail() }
            var signed = Reader(data: signedBytes), digests = Reader(data: try signed.block())
            var digestRecords: [(UInt64, Data)] = []
            while digests.remaining > 0 {
                var digest = Reader(data: try digests.block())
                digestRecords.append((try digest.number(4), try digest.block()))
                guard digest.remaining == 0 else { throw fail() }
            }
            guard records.map({ $0.0 }) == digestRecords.map({ $0.0 }),
                  Set(records.map({ $0.0 })).count == records.count,
                  let expected = digestRecords.first(where: { $0.0 == selected.0 })?.1 else { throw fail() }
            var certs = Reader(data: try signed.block())
            let certificateBytes = try certs.block()
            guard let certificate = SecCertificateCreateWithData(nil, certificateBytes as CFData),
                  let key = SecCertificateCopyKey(certificate),
                  try publicKeyBytes(publicKey) == (SecKeyCopyExternalRepresentation(key, nil) as Data?),
                  SecKeyIsAlgorithmSupported(key, .verify, algorithm),
                  SecKeyVerifySignature(key, algorithm, signedBytes as CFData, selected.1 as CFData, nil)
            else { throw fail() }
            if isV3 { guard try signed.take(8) == sdk else { throw fail() } }
            var attributes = Reader(data: try signed.block())
            while attributes.remaining > 0 {
                var attribute = Reader(data: try attributes.block())
                let id = try attribute.number(4)
                if id == 0xbeeff00d, try attribute.number(4) == 3, !isV3 { throw fail() }
            }
            guard signed.remaining == 0 else { throw fail() }
            if cachedDigests[sha512] == nil {
                var eocd = data.subdata(in: end..<data.count)
                eocd.replaceSubrange(16..<20, with: little(start))
                let ranges = [0..<start, cd..<end]
                let chunks = ranges.reduce(0) { $0 + ($1.count + (1 << 20) - 1) / (1 << 20) } + (eocd.count + (1 << 20) - 1) / (1 << 20)
                var hashes = Data([0x5a]) + little(chunks)
                for range in ranges {
                    for offset in stride(from: range.lowerBound, to: range.upperBound, by: 1 << 20) {
                        let n = min(1 << 20, range.upperBound - offset)
                        hashes += hash(Data([0xa5]) + little(n) + data.subdata(in: offset..<offset+n), sha512: sha512)
                    }
                }
                hashes += hash(Data([0xa5]) + little(eocd.count) + eocd, sha512: sha512)
                cachedDigests[sha512] = hash(hashes, sha512: sha512)
            }
            guard cachedDigests[sha512] == expected else { throw fail() }
            certificates.append(SHA256.hash(data: certificateBytes).map { String(format: "%02x", $0) }.joined())
        }
        guard !certificates.isEmpty, Set(certificates).count == certificates.count else { throw fail() }
        return certificates.sorted()
    }

    /// SubjectPublicKeyInfo wraps the RSA PKCS#1 key or EC point that Security exports.
    private static func publicKeyBytes(_ spki: Data) throws -> Data {
        func der(_ reader: inout Reader, tag: UInt64) throws -> Data {
            guard try reader.number(1) == tag else { throw fail() }
            var length = Int(try reader.number(1))
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4 else { throw fail() }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(try reader.number(1)) }
            }
            return try reader.take(length)
        }
        var outer = Reader(data: spki), body = Reader(data: try der(&outer, tag: 0x30))
        guard outer.remaining == 0 else { throw fail() }
        _ = try der(&body, tag: 0x30)
        var bits = Reader(data: try der(&body, tag: 0x03))
        guard body.remaining == 0, try bits.number(1) == 0 else { throw fail() }
        return try bits.take(bits.remaining)
    }
}
