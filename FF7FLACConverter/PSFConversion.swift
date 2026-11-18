import Foundation

enum ConversionFailure: LocalizedError {
    case noDuration
    case decoderFailed
    case noAudio
    case invalidPCM
    case wrongDuration(expected: Double, actual: Double)
    case silent

    var errorDescription: String? {
        switch self {
        case .noDuration: return "Missing valid length/fade tags; cannot safely determine full track length."
        case .decoderFailed: return "PSF decoder could not load the track or its libraries."
        case .noAudio: return "Decoder produced no PCM samples."
        case .invalidPCM: return "Decoder produced an incomplete stereo PCM block."
        case .wrongDuration(let expected, let actual):
            return String(format: "Audio duration %.2fs differs from declared %.2fs.", actual, expected)
        case .silent: return "Decoder output is entirely silent; export rejected."
        }
    }
}

private final class PCMReceiver {
    let writer: FLACWriter
    var error: Error?
    var peak: Int32 = 0
    let maximumFrames: UInt64
    init(writer: FLACWriter, expectedSeconds: Double) {
        self.writer = writer
        self.maximumFrames = UInt64((expectedSeconds + max(2, expectedSeconds * 0.02)) * 44100)
    }

    func accept(_ bytes: UnsafePointer<UInt8>, count: Int) {
        guard error == nil else { return }
        guard count >= 0, count % 4 == 0 else {
            error = ConversionFailure.invalidPCM
            ff7_stop_psf()
            return
        }
        var pcm: [Int16] = []
        pcm.reserveCapacity(count / 2)
        for index in stride(from: 0, to: count, by: 2) {
            let value = Int16(bitPattern: UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
            peak = max(peak, abs(Int32(value)))
            pcm.append(value)
        }
        do {
            try writer.append(interleavedPCM: pcm)
            if writer.sampleFrames > maximumFrames {
                error = ConversionFailure.invalidPCM
                ff7_stop_psf()
            }
        } catch {
            self.error = error
            ff7_stop_psf()
        }
    }
}

enum PSFConversion {
    /// Call serially on a background queue; the native decoder has global state.
    static func convert(source: URL, destination: URL, declaredSeconds: Double?) throws {
        guard let expected = declaredSeconds, expected.isFinite, expected > 0 else {
            throw ConversionFailure.noDuration
        }
        let writer = try FLACWriter(url: destination)
        let receiver = PCMReceiver(writer: writer, expectedSeconds: expected)
        let context = Unmanaged.passUnretained(receiver).toOpaque()
        let result = source.path.withCString { path in
            ff7_decode_psf(path, { bytes, count, context in
                guard let bytes, let context else { return }
                Unmanaged<PCMReceiver>.fromOpaque(context).takeUnretainedValue()
                    .accept(bytes, count: Int(count))
            }, context)
        }
        do {
            guard result == 0 else { throw ConversionFailure.decoderFailed }
            if let error = receiver.error { throw error }
            guard writer.sampleFrames > 0 else { throw ConversionFailure.noAudio }
            guard receiver.peak > 0 else { throw ConversionFailure.silent }
            let actual = Double(writer.sampleFrames) / 44100
            guard abs(actual - expected) <= max(2, expected * 0.02) else {
                throw ConversionFailure.wrongDuration(expected: expected, actual: actual)
            }
            try writer.finish()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
