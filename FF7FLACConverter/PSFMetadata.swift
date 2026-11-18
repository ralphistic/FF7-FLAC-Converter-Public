import Foundation

struct PSFTrackMetadata: Equatable {
    let title: String?
    let lengthSeconds: Double?
    let fadeSeconds: Double?
    let libraryNames: [String]

    var totalSeconds: Double? {
        guard let lengthSeconds else { return nil }
        return lengthSeconds + (fadeSeconds ?? 0)
    }
}

enum PSFMetadataError: Error {
    case invalidHeader
    case truncated
    case invalidTags
}

enum PSFMetadataReader {
    static func parseTime(_ value: String) -> Double? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let number = Double(part), number.isFinite, number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds
    }

    static func read(_ data: Data) throws -> PSFTrackMetadata {
        guard data.count >= 16, data[0] == 0x50, data[1] == 0x53,
              data[2] == 0x46, data[3] == 0x01 else {
            throw PSFMetadataError.invalidHeader
        }
        func uint32(_ offset: Int) -> UInt64 {
            (0..<4).reduce(UInt64(0)) { $0 | (UInt64(data[offset + $1]) << (8 * $1)) }
        }
        let offset = UInt64(16) + uint32(4) + uint32(8)
        guard offset <= UInt64(data.count) else { throw PSFMetadataError.truncated }
        let tags = data.subdata(in: Int(offset)..<data.count)
        guard tags.starts(with: Data("[TAG]".utf8)) else {
            return PSFTrackMetadata(title: nil, lengthSeconds: nil, fadeSeconds: nil, libraryNames: [])
        }
        guard let string = String(data: tags.dropFirst(5), encoding: .utf8) else {
            throw PSFMetadataError.invalidTags
        }
        var entries: [String: String] = [:]
        for line in string.components(separatedBy: .newlines) {
            guard let index = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<index]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            entries[key] = value
        }
        let libraries = entries.keys.filter { $0 == "_lib" || $0.range(of: #"^_lib\d+$"#, options: .regularExpression) != nil }
            .sorted { lhs, rhs in
                if lhs == "_lib" { return true }
                if rhs == "_lib" { return false }
                return (Int(lhs.dropFirst(4)) ?? 0) < (Int(rhs.dropFirst(4)) ?? 0)
            }.compactMap { entries[$0] }
        return PSFTrackMetadata(title: entries["title"],
                                lengthSeconds: entries["length"].flatMap(parseTime),
                                fadeSeconds: entries["fade"].flatMap(parseTime),
                                libraryNames: libraries)
    }
}
