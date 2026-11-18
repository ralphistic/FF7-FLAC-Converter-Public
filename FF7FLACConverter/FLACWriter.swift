import Foundation
import CryptoKit

/// Minimal standards-compliant FLAC writer for interleaved 16-bit stereo PCM.
/// Uses verbatim subframes (lossless, but larger than compressed FLAC).
/// Output must be finalized before it is shared.
enum FLACWriteError: Error {
    case invalidSampleCount
    case invalidFrame
    case unsupportedSampleRate
}

final class FLACWriter {
    private let handle: FileHandle
    private let sampleRate: Int
    private let blockSize = 4096
    private var pending: [Int16] = []
    private var frameNumber: UInt64 = 0
    private(set) var sampleFrames: UInt64 = 0
    private var finalized = false
    private var md5 = Insecure.MD5()

    init(url: URL, sampleRate: Int = 44100) throws {
        guard sampleRate == 44100 else { throw FLACWriteError.unsupportedSampleRate }
        self.sampleRate = sampleRate
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        // 4-byte signature, 4-byte last metadata block header, 34-byte STREAMINFO.
        try handle.write(contentsOf: Data("fLaC".utf8))
        try handle.write(contentsOf: Data([0x80, 0, 0, 34]))
        try handle.write(contentsOf: Self.streamInfo(totalSamples: 0, md5: [UInt8](repeating: 0, count: 16)))
    }

    /// Accepts interleaved stereo samples. Keep writing until the decoder ends.
    func append(interleavedPCM: [Int16]) throws {
        guard !finalized, interleavedPCM.count % 2 == 0 else { throw FLACWriteError.invalidSampleCount }
        var pcmBytes = Data(capacity: interleavedPCM.count * 2)
        for sample in interleavedPCM {
            let bits = UInt16(bitPattern: sample)
            pcmBytes.append(UInt8(truncatingIfNeeded: bits))
            pcmBytes.append(UInt8(bits >> 8))
        }
        md5.update(data: pcmBytes)
        pending.append(contentsOf: interleavedPCM)
        while pending.count >= blockSize * 2 {
            try writeFrame(Array(pending.prefix(blockSize * 2)))
            pending.removeFirst(blockSize * 2)
        }
    }

    func finish() throws {
        guard !finalized else { return }
        if !pending.isEmpty {
            try writeFrame(pending)
            pending.removeAll()
        }
        finalized = true
        try handle.seek(toOffset: 8)
        try handle.write(contentsOf: Self.streamInfo(totalSamples: sampleFrames, md5: Array(md5.finalize())))
        try handle.close()
    }

    private static func streamInfo(totalSamples: UInt64, md5: [UInt8]) -> Data {
        var bytes = Data([0x10, 0x00, 0x10, 0x00]) // min/max block: 4096
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 6)) // unknown frame sizes
        let packed = (UInt64(44100) << 44) | (UInt64(1) << 41) |
                     (UInt64(15) << 36) | (totalSamples & 0xFFFFFFFFF)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: packed >> shift))
        }
        bytes.append(contentsOf: md5) // MD5 of decoded interleaved little-endian PCM
        return bytes
    }

    private func writeFrame(_ samples: [Int16]) throws {
        let count = samples.count / 2
        guard count > 0, count <= blockSize else { throw FLACWriteError.invalidFrame }
        var frame = Data([0xFF, 0xF8, count == 4096 ? 0xC9 : 0x79, 0x18])
        frame.append(contentsOf: Self.utf8Number(frameNumber))
        if count != 4096 {
            let n = UInt16(count - 1)
            frame.append(UInt8(n >> 8))
            frame.append(UInt8(truncatingIfNeeded: n))
        }
        frame.append(Self.crc8(frame))
        // Each independent channel is a verbatim 16-bit signed subframe.
        for channel in 0..<2 {
            frame.append(0x02)
            for index in stride(from: channel, to: samples.count, by: 2) {
                let bits = UInt16(bitPattern: samples[index])
                frame.append(UInt8(bits >> 8))
                frame.append(UInt8(truncatingIfNeeded: bits))
            }
        }
        let crc = Self.crc16(frame)
        frame.append(UInt8(crc >> 8))
        frame.append(UInt8(truncatingIfNeeded: crc))
        try handle.write(contentsOf: frame)
        sampleFrames += UInt64(count)
        frameNumber += 1
    }

    private static func utf8Number(_ number: UInt64) -> [UInt8] {
        if number < 0x80 { return [UInt8(number)] }
        let widths: [(Int, UInt64)] = [(2, 1 << 11), (3, 1 << 16), (4, 1 << 21),
                                      (5, 1 << 26), (6, 1 << 31), (7, 1 << 36)]
        let width = widths.first { number < $0.1 }?.0 ?? 7
        var bytes = [UInt8](repeating: 0, count: width)
        var value = number
        for i in stride(from: width - 1, through: 1, by: -1) {
            bytes[i] = 0x80 | UInt8(value & 0x3F)
            value >>= 6
        }
        bytes[0] = UInt8(truncatingIfNeeded: (0xFF << (8 - width)) | Int(value))
        return bytes
    }

    private static func crc8(_ bytes: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? (crc &<< 1) ^ 0x07 : crc &<< 1
            }
        }
        return crc
    }

    private static func crc16(_ bytes: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc &<< 1) ^ 0x8005 : crc &<< 1
            }
        }
        return crc
    }
}
