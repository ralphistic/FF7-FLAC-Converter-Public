import Foundation

enum PSFDependencies {
    /// Resolves direct and transitive _lib references, case-insensitively.
    /// Files with invalid PSF headers must be omitted from the metadata map.
    static func missing(for filename: String,
                        metadataByFilename: [String: PSFTrackMetadata]) -> [String] {
        var visited = Set<String>()
        var missing = Set<String>()
        func visit(_ name: String) {
            let key = (name as NSString).lastPathComponent.lowercased()
            guard visited.insert(key).inserted else { return }
            guard let metadata = metadataByFilename[key] else {
                missing.insert(name)
                return
            }
            for library in metadata.libraryNames {
                // Do not silently resolve paths outside the imported source folder.
                guard library == (library as NSString).lastPathComponent,
                      !library.isEmpty, library != ".", library != ".." else {
                    missing.insert(library)
                    continue
                }
                visit(library)
            }
        }
        visit(filename)
        return missing.sorted()
    }
}
